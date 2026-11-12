# Session state, authority and checkpoints for the LAN multiplayer v1.
#
# The relay only transports messages. The room host is the authority for the
# match start, dice, phase sequence and canonical checkpoint state. Guest
# requests are validated structurally by the host (slot, phase, zone and
# visibility) but full Battle Scenes rules are not reimplemented here.
extends Node

signal session_changed()
signal prep_changed()
signal phase_changed()
signal match_started()
signal checkpoint_saved(sequence, path)
signal checkpoint_error(message)
signal resume_status(text)
signal resume_finished(ok, message)
signal session_ended(message)
signal waiting_changed(waiting, message)
signal action_logged(text)
signal display_changed()
signal lobby_ready()
signal mulligan_changed()
signal prep_game_changed()
signal adjustment_changed()

const CheckpointStore = preload("res://src/custom/CheckpointStore.gd")

enum State { IDLE, PREPARING, STARTING, PLAYING, WAITING, ENDED }
enum Mode { NONE, MATCH, RESUME, SOLO }

const DECK_SIZE := 60
const START_HAND_SIZE := 10
const MAX_CACHED_STATES := 24

# Depois que a conexao local cai, o relay nao derruba a sala: se o adversario
# ainda esta lá a vaga fica livre, e se os dois sairam ha 120 s de graca. O botao
# "Reconecte" sempre existiu, mas online o jogador tem que ver o aviso e clicar
# dentro dessa janela — medido em 30/10/2026, o tunel ficou 13 s fora e a partida
# so voltou quando alguem clicou. O backoff tenta sozinho nos mesmos termos do
# botao e soma 77 s, menos que os 120 s do relay, para nunca tentar uma sala que
# ja expirou.
const RECONNECT_RETRY_SECONDS := [2.0, 5.0, 10.0, 20.0, 40.0]
const RECONNECT_RETRYING_MESSAGE := \
		"Conexão perdida. Tentando reconectar à sala..."
const RECONNECT_GIVEUP_MESSAGE := \
		"Conexão perdida. Reconecte à sala ou encerre a partida."

# A turn is the six official phases (AUTOTURNO.md §3.4) and a round is the two
# turns of the match, so the step counter wraps every twelve steps. The owner of
# the turn acts on every step but Antecipação, which the opponent plays.
const TURN_PHASES := ["REG", "DRAW", "PREP", "ADJ", "ANT", "ATK"]
const PHASE_LABELS := {
	"REG": "Contagem Regressiva",
	"DRAW": "Compra",
	"PREP": "Preparação",
	"ADJ": "Ajuste",
	"ANT": "Antecipação",
	"ATK": "Ataque",
}
const PHASE_COLORS := {
	"REG": Color(0.62, 0.78, 1.0),
	"DRAW": Color(1.0, 0.78, 0.35),
	"PREP": Color(1, 1, 1),
	"ADJ": Color(0.72, 0.72, 0.72),
	"ANT": Color(1.0, 0.38, 0.38),
	"ATK": Color(0.42, 1.0, 0.5),
}
const VALID_ZONES := [
	"board", "scenario", "hand", "deck", "resources", "prizes",
]
# Phases whose first step the game plays by itself when they open
# (AUTOTURNO.md §3.4): the countdown and the draw. The adjustment is manual: it
# opens a gate that waits for the owner to remove the excess energy.
const EFFECT_PHASES := ["REG", "DRAW"]
# A turn that opens on the countdown pays both automatic phases and moves on by
# itself. The pause lets the cards land and the log show each phase before the
# table stops on Preparação.
const AUTO_TURN_SECONDS := 1.0

var state = State.IDLE
var mode = Mode.NONE
var game_id := ""
var p1_username := ""
var p2_username := ""
var my_slot := 0
var opponent_slot := 0
var local_deck := {}
var local_deck_name := ""
var local_deck_count := 0
var opponent_deck_name := ""
var opponent_deck_count := 0
var opponent_deck_ready := false
var rolls := []
var starting_slot := 0
var round_number := 1
var step_index := 0
var phase := ""
var sequence := -1
## How many manual mulligans each seat has taken this match, keyed by slot.
var _mulligan_counts := {}
## The mulligan window (AUTOTURNO.md §3.2): open from the deal until every seat
## keeps its hand. The authority owns it, the guest mirrors it from the public
## state so a button never waits on a flag nobody can press.
var _mulligan_open := false
## The local seat already answered; the panel then waits for the other one.
var _mulligan_local_choice := false
## Slots that clicked "Ficar com a mão".
var _mulligan_accepts := {}
## The preparation window (AUTOTURNO.md §3.3): open between the mulligan and the
## first turn, so both seats may throw away as many hand cards as they want at
## the same time (decisions 7 and 8a). It closes when both click "Pronto".
var _prep_game_open := false
## The local seat already clicked "Pronto".
var _prep_game_local_choice := false
## Slots that clicked "Pronto".
var _prep_game_accepts := {}
## The adjustment gate: open during the Ajuste phase while the seat on the table
## carries more energy than its characters accept. The player removes the excess
## by hand and the gate closes on its own; until then the phase cannot advance.
var _adjustment_open := false
var _adjustment_operations := []
## The automatic opening of a turn: after an Ataque the next seat's countdown and
## draw are played and passed without a click. Only the seat that owns the cards
## runs this part, so the flags live on whichever client is holding them.
var _auto_turn_active := false
var _auto_advance_pending := false
var _auto_turn_resources := 0
var _auto_turn_draws := 0
## Steps whose automatic effect this client already played, keyed by
## "round:step". A seat swap can open a phase for the seat that was not on the
## table, so the marker is what keeps a draw from happening twice.
var _effects_applied := {}
var waiting_message := ""
var ended_message := ""
var last_error := ""
var opponent_counts := {"hand": 0, "deck": 0}
var local_display := {}
var opponent_display := {}
# Hotseat only: which seat the deck picker is choosing for, the deck of each
# seat, and the cards of the seat that is currently mirrored. The mirrored seat
# is kept as data because its Card nodes only exist once the player swaps in.
var solo_pick_slot := 1
var solo_decks := {}
var _solo_hidden := {}

var _board: Control
var _hud: Control
var _sync: Control
var _id_prefix := ""
var _id_counter := 0
var _start_applied := false
var _start_payload := {}
var _initial_state_sent := false
var _opponent_board_counts_received := false
var _public_states := {}
var _private_envelopes := {}
var _saved_sequences := {}
var _restore_pending := {}
var _restore_live := false
var _restore_scheduled := false
var _resume_live := false
var _resume_peer_manifests := []
var _resume_peer_manifest_received := false
var _resume_peer_checkpoint := {}
var _resume_waiting_ack := false
var _resume_expected_participants := []
var _resume_state_before_wait = State.IDLE
var _waiting_reason := ""
var _retry_step := RECONNECT_RETRY_SECONDS.size()
var _retry_elapsed := 0.0
var _clearing := false
var _display_checked := false


func _ready() -> void:
	# A unica coisa que roda por frame e a janela de reconexao automatica, entao
	# o processo fica desligado enquanto nao ha conexao perdida.
	set_process(false)
	# warning-ignore:return_value_discarded
	Rede.match_found.connect(_on_rede_match_found)
	# warning-ignore:return_value_discarded
	Rede.message_received.connect(_on_network_message)
	# warning-ignore:return_value_discarded
	Rede.opponent_lost.connect(_on_opponent_lost)
	# warning-ignore:return_value_discarded
	Rede.opponent_reconnected.connect(_on_opponent_reconnected)
	# warning-ignore:return_value_discarded
	Rede.opponent_left.connect(_on_opponent_left)
	# warning-ignore:return_value_discarded
	Rede.connection_lost.connect(_on_connection_lost)
	# warning-ignore:return_value_discarded
	Rede.room_expired.connect(_on_room_expired)
	# warning-ignore:return_value_discarded
	Rede.status_changed.connect(_on_rede_status_changed)
	# warning-ignore:return_value_discarded
	Rede.rejoined.connect(_on_rejoined)
	# warning-ignore:return_value_discarded
	Rede.join_failed.connect(_on_join_failed)


func _process(delta: float) -> void:
	if not _auto_reconnect_armed():
		set_process(false)
		# A janela venceu e o jogador continua sem conexao: o aviso para de
		# prometer tentativa automatica e aponta o botao, uma sola vez.
		if state == State.WAITING and _waiting_reason == "local" \
				and waiting_message != RECONNECT_GIVEUP_MESSAGE:
			waiting_message = RECONNECT_GIVEUP_MESSAGE
			emit_signal("waiting_changed", true, waiting_message)
		return
	_retry_elapsed += delta
	if _retry_elapsed < RECONNECT_RETRY_SECONDS[_retry_step]:
		return
	# Uma tentativa em andamento nao recebe outra por cima: o socket ainda esta
	# conectando e fecharia no meio o proprio rejoin. Espera sem gastar a etapa.
	if Rede.is_connected or Rede.is_searching:
		return
	_retry_elapsed = 0.0
	_retry_step += 1
	manual_reconnect()


#-----------------------------------------------------------------------------
# Public session queries
#-----------------------------------------------------------------------------

func is_session_active() -> bool:
	return state != State.IDLE


func is_playing() -> bool:
	return state == State.PLAYING


func is_preparing() -> bool:
	return state == State.PREPARING


func is_starting() -> bool:
	return state == State.STARTING


func is_waiting() -> bool:
	return state == State.WAITING


func is_ended() -> bool:
	return state == State.ENDED


func is_solo() -> bool:
	return mode == Mode.SOLO


func is_authority() -> bool:
	return Rede.is_host() and state != State.IDLE


func is_frozen() -> bool:
	return state in [State.STARTING, State.WAITING, State.ENDED]


func get_my_username() -> String:
	if mode == Mode.SOLO:
		return get_slot_username(my_slot)
	return Rede.player_username


func get_opponent_username() -> String:
	if mode == Mode.SOLO:
		return get_slot_username(opponent_slot)
	return Rede.opponent_username


func get_slot_username(slot: int) -> String:
	if slot == 1:
		return p1_username
	if slot == 2:
		return p2_username
	return ""


func phase_for_step(step: int) -> String:
	if step < 0 or step >= get_steps_per_round():
		return ""
	return str(TURN_PHASES[step % TURN_PHASES.size()])


func get_steps_per_round() -> int:
	return TURN_PHASES.size() * 2


## Which of the two turns of the round a step belongs to: 0 is the turn of the
## player who started the match, 1 is the other one.
func turn_half(step: int) -> int:
	return int(step / TURN_PHASES.size())


func get_turn_owner_slot() -> int:
	if starting_slot == 0:
		return 0
	if turn_half(step_index) == 0:
		return starting_slot
	return 3 - starting_slot


func get_actor_slot() -> int:
	var owner := get_turn_owner_slot()
	if owner == 0:
		return 0
	# Antecipação is the step the opponent of the attacker plays (§2).
	if phase_for_step(step_index) == "ANT":
		return 3 - owner
	return owner


## The player who starts the match does not draw on their first turn (§2).
func is_first_turn_of_match() -> bool:
	return round_number == 1 and turn_half(step_index) == 0


func get_actor_username() -> String:
	return get_slot_username(get_actor_slot())


func is_my_phase() -> bool:
	if state != State.PLAYING:
		return false
	# In the hotseat the human is both seats, so the phase never blocks them.
	return mode == Mode.SOLO or get_actor_slot() == my_slot


func get_phase_label() -> String:
	return str(PHASE_LABELS.get(phase, phase))


func get_phase_color() -> Color:
	return PHASE_COLORS.get(phase, Color(0.85, 0.85, 0.85))


func are_both_decks_ready() -> bool:
	return local_deck_count == DECK_SIZE and opponent_deck_ready


func is_local_deck_ready() -> bool:
	if mode == Mode.SOLO:
		return is_solo_deck_ready(solo_pick_slot)
	return local_deck_count == DECK_SIZE


func is_solo_deck_ready(slot: int) -> bool:
	return _count_deck_cards(solo_decks.get(slot, {})) == DECK_SIZE


func get_solo_deck(slot: int) -> Dictionary:
	var deck: Dictionary = solo_decks.get(slot, {})
	return deck


func get_deck_summary() -> String:
	if mode == Mode.SOLO:
		return get_slot_username(1) + ": " + _solo_deck_text(1) \
				+ " · " + get_slot_username(2) + ": " + _solo_deck_text(2)
	var mine := str(local_deck_count) + "/" + str(DECK_SIZE)
	var theirs := str(opponent_deck_count) + "/" + str(DECK_SIZE)
	if opponent_deck_count == 0 and opponent_deck_name.is_empty():
		theirs = "aguardando"
	elif opponent_deck_ready:
		theirs += " pronto"
	return "Seu deck: " + mine + " · Oponente: " + theirs


func _solo_deck_text(slot: int) -> String:
	var deck: Dictionary = solo_decks.get(slot, {})
	if deck.is_empty():
		return "aguardando"
	return str(deck.get("name", "Deck")) + " " \
			+ str(_count_deck_cards(deck)) + "/" + str(DECK_SIZE)


func get_rolls_text() -> String:
	if rolls.size() != 2:
		return ""
	return str(rolls[0]) + " x " + str(rolls[1])


func get_display_info() -> Dictionary:
	var viewport_size := Vector2(1280, 720)
	var board_size := Vector2.ZERO
	if is_instance_valid(_board):
		viewport_size = _board.get_viewport().get_visible_rect().size
		board_size = _board.size
	var screen_size := DisplayServer.screen_get_size()
	return {
		"screen": [int(screen_size.x), int(screen_size.y)],
		"window": [int(get_window().size.x), int(get_window().size.y)],
		"viewport": [int(viewport_size.x), int(viewport_size.y)],
		"board": [int(board_size.x), int(board_size.y)],
		"stretch": str(ProjectSettings.get_setting(
				"display/window/stretch/mode")),
		"aspect": str(ProjectSettings.get_setting(
				"display/window/stretch/aspect")),
		"fullscreen": ((get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN) or (get_window().mode == Window.MODE_FULLSCREEN)),
	}


func get_display_summary() -> String:
	var lines := ["Você: " + _format_display(get_display_info())]
	if opponent_display.is_empty():
		lines.append("Oponente: aguardando resolução")
	else:
		lines.append("Oponente: " + _format_display(opponent_display))
	return "\n".join(PackedStringArray(lines))


#-----------------------------------------------------------------------------
# Board registration and user actions
#-----------------------------------------------------------------------------

func register_board(board: Control, hud: Control, sync_node: Control) -> void:
	_board = board
	_hud = hud
	_sync = sync_node
	if not _restore_pending.is_empty():
		_apply_pending_restore()
	elif not _start_payload.is_empty() and not _start_applied:
		_apply_start(_start_payload)


func select_deck(deck: Dictionary) -> Dictionary:
	if state != State.PREPARING:
		return {"ok": false, "reason": "A partida não está em preparação."}
	if mode == Mode.SOLO:
		return _select_solo_deck(solo_pick_slot, deck)
	var count := _count_deck_cards(deck)
	local_deck = deck
	local_deck_name = str(deck.get("name", "Deck"))
	local_deck_count = count
	_merge_definitions(deck.get("definitions", {}))
	emit_signal("prep_changed")
	_send_prep()
	_log("Deck selecionado: " + local_deck_name + " (" + str(count) + "/60).")
	return {"ok": true, "count": count}


func set_solo_pick_slot(slot: int) -> void:
	if mode != Mode.SOLO or slot < 1 or slot > 2:
		return
	solo_pick_slot = slot
	emit_signal("prep_changed")


# Each seat has its own deck button on the preparation screen, so the deck goes
# straight to that seat. The pick slot still marks the seat the link import
# targets.
func select_solo_deck(slot: int, deck: Dictionary) -> Dictionary:
	if state != State.PREPARING or mode != Mode.SOLO:
		return {"ok": false, "reason": "A partida não está em preparação."}
	if slot < 1 or slot > 2:
		return {"ok": false, "reason": "Assento inválido."}
	return _select_solo_deck(slot, deck)


# The hotseat picks one deck per seat; both are known locally from the start, so
# the second deck never travels and only its counts are shown while mirrored.
func _select_solo_deck(slot: int, deck: Dictionary) -> Dictionary:
	var count := _count_deck_cards(deck)
	var deck_name := str(deck.get("name", "Deck"))
	solo_decks[slot] = deck
	_merge_definitions(deck.get("definitions", {}))
	if slot == my_slot:
		local_deck = deck
		local_deck_name = deck_name
		local_deck_count = count
	else:
		opponent_deck_name = deck_name
		opponent_deck_count = count
		opponent_deck_ready = count == DECK_SIZE
	emit_signal("prep_changed")
	_log("Deck de " + get_slot_username(slot) + ": " + deck_name + " ("
			+ str(count) + "/" + str(DECK_SIZE) + ").")
	return {"ok": true, "count": count}


func request_start() -> bool:
	if state != State.PREPARING:
		return false
	if not are_both_decks_ready():
		return false
	if is_authority():
		_host_start_match()
	else:
		Rede.send_message({"t": "mp_start_request", "game_id": game_id})
		_log("Pedido de início enviado ao anfitrião.")
	return true


func advance_phase() -> bool:
	if state != State.PLAYING:
		return false
	# The automatic opening is already on its way to the next phase; a click in
	# the middle of it would skip Preparação.
	if _auto_advance_pending:
		return false
	if _mulligan_open or _prep_game_open or _adjustment_open:
		return false
	if mode != Mode.SOLO and get_actor_slot() != my_slot:
		return false
	if is_authority():
		_advance_as_authority()
	else:
		Rede.send_message({
			"t": "mp_phase_request",
			"game_id": game_id,
			"sequence": sequence,
			"step": step_index,
		})
	return true


func manual_reconnect() -> bool:
	if Rede.room_id.is_empty():
		return false
	return Rede.reconnect_room(Rede.last_address, Rede.player_username)


func can_manual_reconnect() -> bool:
	return state == State.WAITING and _waiting_reason == "local" \
			and not Rede.room_id.is_empty()


# As mesmas condicoes do botao, mais as duas que o botao nao precisa: hotseat
# nunca falou com o relay (tentar reconectar abriria socket LOCAL na maquina) e
# a janela de tentativas tem um fim.
func _auto_reconnect_armed() -> bool:
	if state != State.WAITING or _waiting_reason != "local":
		return false
	if mode == Mode.SOLO or Rede.room_id.is_empty():
		return false
	return _retry_step < RECONNECT_RETRY_SECONDS.size()


func _begin_reconnect_retries() -> void:
	_retry_step = 0
	_retry_elapsed = 0.0
	set_process(true)


func _stop_reconnect_retries() -> void:
	_retry_step = RECONNECT_RETRY_SECONDS.size()
	_retry_elapsed = 0.0
	set_process(false)


func get_waiting_reason() -> String:
	return _waiting_reason


func leave_session(message := "", disconnect := true) -> void:
	if disconnect:
		Rede.disconnect_game()
	state = State.IDLE
	mode = Mode.NONE
	_clear_session_fields()
	cfc.game_paused = false
	_board = null
	_hud = null
	_sync = null
	emit_signal("session_changed")
	if not message.is_empty():
		emit_signal("session_ended", message)


func reset_session() -> void:
	_clearing = true
	state = State.IDLE
	mode = Mode.NONE
	_clear_session_fields()
	cfc.game_paused = false
	_board = null
	_hud = null
	_sync = null
	_clearing = false
	emit_signal("session_changed")


func begin_match(
		address: String,
		username: String,
		as_host: bool) -> Dictionary:
	var cleaned := username.strip_edges()
	if cleaned.is_empty():
		return {"ok": false, "reason": "Digite seu username."}
	reset_session()
	mode = Mode.MATCH
	if as_host:
		if not Rede.create_room(address, cleaned):
			mode = Mode.NONE
			return {"ok": false, "reason": Rede.get_status()}
		state = State.PREPARING
		my_slot = 1
		opponent_slot = 2
		p1_username = cleaned
		p2_username = ""
		_set_resume_state_before_wait(State.PREPARING)
		emit_signal("session_changed")
	else:
		if not Rede.find_match(address, cleaned):
			mode = Mode.NONE
			return {"ok": false, "reason": Rede.get_status()}
	return {"ok": true, "reason": ""}


func begin_join(
		address: String,
		username: String,
		room_code: String) -> Dictionary:
	var cleaned := username.strip_edges()
	if cleaned.is_empty():
		return {"ok": false, "reason": "Digite seu username."}
	if room_code.strip_edges().is_empty():
		return {"ok": false, "reason": "Informe o codigo da sala."}
	reset_session()
	mode = Mode.MATCH
	if not Rede.join_room(address, cleaned, room_code):
		mode = Mode.NONE
		return {"ok": false, "reason": Rede.get_status()}
	return {"ok": true, "reason": ""}


# The hotseat session starts synchronously: Rede.start_solo emits match_found
# before returning, so the preparation state is ready when this call ends.
func begin_solo(username: String) -> Dictionary:
	var cleaned := username.strip_edges()
	if cleaned.is_empty():
		return {"ok": false, "reason": "Digite seu username."}
	reset_session()
	if not Rede.start_solo(cleaned):
		mode = Mode.NONE
		return {"ok": false, "reason": Rede.get_status()}
	if mode != Mode.SOLO:
		mode = Mode.NONE
		return {"ok": false, "reason": "A partida solo não abriu."}
	return {"ok": true, "reason": ""}


func begin_resume(
		address: String,
		username: String,
		checkpoint_game_id: String,
		participants: Array,
		as_host: bool) -> Dictionary:
	var cleaned := username.strip_edges()
	if cleaned.is_empty():
		return {"ok": false, "reason": "Digite seu username."}
	if checkpoint_game_id.is_empty():
		return {"ok": false, "reason": "Este save não identifica a partida."}
	if as_host and participants.size() != 2:
		return {"ok": false, "reason": "Este save não identifica os dois jogadores."}
	if not participants.is_empty() and not cleaned in participants:
		return {
			"ok": false,
			"reason": "Este save exige os jogadores: " + str(participants[0]) \
					+ " e " + str(participants[1]) + ".",
		}
	reset_session()
	_resume_expected_participants = participants.duplicate()
	mode = Mode.RESUME
	game_id = checkpoint_game_id
	if as_host:
		if not Rede.create_resume_room(
				address, cleaned, checkpoint_game_id, participants):
			mode = Mode.NONE
			return {"ok": false, "reason": Rede.get_status()}
	else:
		if not Rede.join_resume_room(
				address, cleaned, checkpoint_game_id, participants):
			mode = Mode.NONE
			return {"ok": false, "reason": Rede.get_status()}
	return {"ok": true, "reason": ""}


func change_username(new_username: String) -> Dictionary:
	var cleaned := new_username.strip_edges()
	if cleaned.is_empty():
		return {"ok": false, "reason": "O username não pode ficar vazio."}
	var old_username := str(cfc.game_settings.get("multiplayer_username", ""))
	if old_username != cleaned and not old_username.is_empty():
		var result := CheckpointStore.reprotect_all(old_username, cleaned)
		var skipped := int(result.get("skipped", 0))
		if skipped > 0:
			# Old saves that cannot follow the rename stay under the previous
			# username; the other player can still use their own copy.
			_log("Username alterado. " + str(skipped) \
					+ " save(s) mantidos com o username anterior.")
		elif int(result.get("changed", 0)) > 0:
			_log("Saves locais reprotegidos com o novo username.")
	cfc.set_setting("multiplayer_username", cleaned)
	return {"ok": true, "reason": ""}


func ensure_card_id(card: Card) -> String:
	if card.network_id.is_empty():
		if _id_prefix.is_empty():
			_id_prefix = (Rede.peer_tag if not Rede.peer_tag.is_empty() else "P") \
					+ str(Time.get_ticks_usec())
		_id_counter += 1
		card.network_id = _id_prefix + "_" + str(_id_counter)
	return card.network_id


func set_opponent_counts(counts: Dictionary) -> void:
	opponent_counts = {
		"hand": max(0, int(counts.get("hand", 0))),
		"deck": max(0, int(counts.get("deck", 0))),
	}
	if _board:
		opponent_deck_count = int(opponent_counts["deck"]) \
				+ int(opponent_counts["hand"])
	if _sync and is_instance_valid(_sync) \
			and _sync.has_method("set_hidden_counts"):
		_sync.set_hidden_counts(
				int(opponent_counts["hand"]), int(opponent_counts["deck"]))


func log_action(message: String) -> void:
	_log(message)


#-----------------------------------------------------------------------------
# Rede handlers
#-----------------------------------------------------------------------------

func _on_rede_match_found(_opponent: String) -> void:
	if _clearing:
		return
	var kept_deck := {}
	var kept_name := ""
	var kept_count := 0
	if mode == Mode.MATCH and state == State.PREPARING:
		kept_deck = local_deck
		kept_name = local_deck_name
		kept_count = local_deck_count
	_clear_session_fields()
	if not kept_deck.is_empty():
		local_deck = kept_deck
		local_deck_name = kept_name
		local_deck_count = kept_count
	if Rede.is_solo:
		mode = Mode.SOLO
	else:
		mode = Mode.RESUME if Rede.match_mode == "resume" else Mode.MATCH
	game_id = Rede.game_id
	_id_prefix = (Rede.peer_tag if not Rede.peer_tag.is_empty() else "P") \
			+ str(Time.get_ticks_usec())
	opponent_counts = {"hand": 0, "deck": 0}
	var my_name := Rede.player_username
	if mode == Mode.SOLO:
		my_slot = 1
		opponent_slot = 2
		solo_pick_slot = 1
		solo_decks = {}
		_solo_hidden = {}
		p1_username = "P1"
		p2_username = "P2"
		state = State.PREPARING
		_set_resume_state_before_wait(State.PREPARING)
		_log("Partida solo: " + my_name + " controla P1 e P2. "
				+ "Escolha os dois decks.")
	elif mode == Mode.MATCH:
		my_slot = 1 if Rede.is_host() else 2
		opponent_slot = 3 - my_slot
		p1_username = my_name if my_slot == 1 else Rede.opponent_username
		p2_username = Rede.opponent_username if my_slot == 1 else my_name
		state = State.PREPARING
		_set_resume_state_before_wait(State.PREPARING)
		_log("Sala de " + p1_username + " contra " + p2_username
				+ ". Escolham os decks.")
	else:
		var participants = Rede.match_participants
		if typeof(participants) == TYPE_ARRAY and participants.size() == 2:
			_resume_expected_participants = participants.duplicate()
			p1_username = str(participants[0])
			p2_username = str(participants[1])
		elif _resume_expected_participants.size() == 2:
			p1_username = str(_resume_expected_participants[0])
			p2_username = str(_resume_expected_participants[1])
		else:
			_end_session("A retomada não identificou os dois participantes.")
			return
		if my_name == p1_username:
			my_slot = 1
		elif my_name == p2_username:
			my_slot = 2
		else:
			_end_session("Seu username não participa desta partida salva.")
			return
		opponent_slot = 3 - my_slot
		state = State.WAITING
		_set_resume_state_before_wait(State.PLAYING)
		_log("Retomada de " + p1_username + " contra " + p2_username + ".")
	_send_hello()
	_update_pause()
	emit_signal("session_changed")
	if mode == Mode.RESUME:
		_begin_resume_negotiation(false)
	emit_signal("lobby_ready")


func _on_network_message(data: Dictionary) -> void:
	if not is_session_active():
		return
	var kind := str(data.get("t", ""))
	match kind:
		"mp_hello":
			_on_mp_hello(data)
		"mp_prep":
			_on_mp_prep(data)
		"mp_start_request":
			_on_mp_start_request(data)
		"mp_start":
			_on_mp_start(data)
		"mp_abort":
			_on_mp_abort(data)
		"mp_result":
			_on_mp_result(data)
		"mp_board_ready":
			_on_mp_board_ready(data)
		"mp_phase_request":
			_on_mp_phase_request(data)
		"mp_mulligan_accept":
			_on_mp_mulligan_accept(data)
		"mp_prep_game_ready":
			_on_mp_prep_game_ready(data)
		"mp_log":
			_on_mp_log(data)
		"mp_state":
			_on_mp_state(data)
		"mp_private":
			_on_mp_private(data)
		"mp_private_request":
			_on_mp_private_request(data)
		"mp_resume_manifest":
			_on_mp_resume_manifest(data)
		"mp_resume_plan":
			_on_mp_resume_plan(data)
		"mp_resume_checkpoint":
			_on_mp_resume_checkpoint(data)
		"mp_resume_ready":
			_on_mp_resume_ready(data)


func _on_opponent_lost(_reconnectable: bool, _grace: int, _room_id: String) -> void:
	if not is_session_active() or state == State.WAITING or state == State.ENDED:
		return
	_resume_state_before_wait = state
	_waiting_reason = "opponent"
	state = State.WAITING
	waiting_message = "O oponente desconectou. O jogo está congelado."
	if mode == Mode.RESUME and _resume_state_before_wait != State.PLAYING:
		waiting_message = "O oponente desconectou durante a retomada."
	_update_pause()
	emit_signal("waiting_changed", true, waiting_message)
	emit_signal("session_changed")


func _on_connection_lost() -> void:
	if not is_session_active() or state == State.ENDED:
		return
	if state != State.WAITING:
		_resume_state_before_wait = state
		# Janela nova a cada queda real. Uma tentativa que falha chega aqui com o
		# estado ja em WAITING, entao o backoff continua a sequencia em vez de
		# recomecar do zero e estender o tempo total.
		_begin_reconnect_retries()
	_waiting_reason = "local"
	state = State.WAITING
	waiting_message = RECONNECT_RETRYING_MESSAGE
	_update_pause()
	emit_signal("waiting_changed", true, waiting_message)
	emit_signal("session_changed")


func _on_opponent_reconnected(_username: String, _role: String) -> void:
	if not is_session_active() or state != State.WAITING:
		return
	_log("O oponente voltou (" + Rede.opponent_username + ").")
	if mode == Mode.MATCH and _resume_state_before_wait == State.PREPARING:
		state = State.PREPARING
		_update_pause()
		_send_hello()
		_send_prep()
		emit_signal("waiting_changed", false, "")
		emit_signal("session_changed")
		return
	if mode == Mode.MATCH and _resume_state_before_wait == State.STARTING:
		if is_authority() and not _start_payload.is_empty():
			Rede.send_message(_start_payload)
			state = State.PLAYING
			_start_applied = true
			_update_pause()
			_initial_state_sent = false
			_send_board_ready()
			emit_signal("match_started")
			emit_signal("session_changed")
		else:
			_send_hello()
		return
	_begin_resume_negotiation(true)


func _on_rejoined(_role: String, _opponent: String) -> void:
	if not is_session_active():
		return
	_stop_reconnect_retries()
	_log("Reconectado à sala.")
	if mode == Mode.MATCH and _resume_state_before_wait == State.PREPARING:
		state = State.PREPARING
		_update_pause()
		_send_hello()
		_send_prep()
		emit_signal("waiting_changed", false, "")
		emit_signal("session_changed")
		return
	if mode == Mode.MATCH and _resume_state_before_wait == State.STARTING:
		_send_hello()
		if is_authority() and not _start_payload.is_empty():
			Rede.send_message(_start_payload)
			state = State.PLAYING
			_start_applied = true
			_update_pause()
			_initial_state_sent = false
			_send_board_ready()
			emit_signal("match_started")
			emit_signal("session_changed")
		return
	_begin_resume_negotiation(true)


func _on_opponent_left() -> void:
	if not is_session_active():
		return
	_end_session("O oponente encerrou a partida.")


func _on_room_expired(message: String) -> void:
	if not is_session_active():
		return
	_end_session(message)


func _on_join_failed(message: String) -> void:
	if mode == Mode.RESUME and state != State.PLAYING:
		_fail_resume(message)
		return
	if not is_session_active():
		return
	if state == State.WAITING:
		_fail_resume(message)


func _on_rede_status_changed(text: String) -> void:
	if state == State.PREPARING and mode == Mode.MATCH \
			and not Rede.is_searching and not Rede.is_connected \
			and Rede.room_id.is_empty():
		_end_session(text)


#-----------------------------------------------------------------------------
# Preparation and start
#-----------------------------------------------------------------------------

func _send_hello() -> void:
	local_display = get_display_info()
	Rede.send_message({
		"t": "mp_hello",
		"mode": "resume" if mode == Mode.RESUME else "match",
		"game_id": game_id,
		"display": local_display,
	})


func _on_mp_hello(data: Dictionary) -> void:
	if str(data.get("game_id", game_id)) != game_id:
		return
	_store_opponent_display(data)
	if state == State.PREPARING:
		_send_prep()
		if is_authority() and not opponent_deck_name.is_empty():
			emit_signal("prep_changed")


func _send_prep() -> void:
	if state != State.PREPARING:
		return
	local_display = get_display_info()
	Rede.send_message({
		"t": "mp_prep",
		"game_id": game_id,
		"count": local_deck_count,
		"ready": local_deck_count == DECK_SIZE,
		"name": local_deck_name,
		"display": local_display,
	})


func _on_mp_prep(data: Dictionary) -> void:
	if str(data.get("game_id", game_id)) != game_id:
		return
	if state != State.PREPARING:
		return
	var count := int(data.get("count", 0))
	if count < 0 or count > DECK_SIZE:
		return
	opponent_deck_count = count
	opponent_deck_ready = bool(data.get("ready", false)) and count == DECK_SIZE
	opponent_deck_name = str(data.get("name", ""))
	_store_opponent_display(data)
	emit_signal("prep_changed")


func _on_mp_start_request(data: Dictionary) -> void:
	if not is_authority() or state != State.PREPARING:
		return
	if str(data.get("game_id", game_id)) != game_id:
		return
	if not are_both_decks_ready():
		_log("O oponente pediu para iniciar, mas os decks ainda não estão prontos.")
		return
	_host_start_match()


func _host_start_match() -> void:
	if not is_authority() or state != State.PREPARING:
		return
	var die_one := cfc.game_rng.randi_range(1, 6)
	var die_two := cfc.game_rng.randi_range(1, 6)
	while die_one == die_two:
		die_one = cfc.game_rng.randi_range(1, 6)
		die_two = cfc.game_rng.randi_range(1, 6)
	starting_slot = 1 if die_one > die_two else 2
	rolls = [die_one, die_two]
	round_number = 1
	step_index = 0
	phase = TURN_PHASES[0]
	sequence = -1
	var shuffle_seed := str(cfc.game_rng.randi()) + "-" \
			+ str(cfc.game_rng.randi())
	_start_payload = {
		"t": "mp_start",
		"game_id": game_id,
		"rolls": rolls,
		"starting_slot": starting_slot,
		"seed": shuffle_seed,
		"round": round_number,
		"step": step_index,
		"phase": phase,
	}
	state = State.STARTING
	_start_applied = false
	_initial_state_sent = false
	_opponent_board_counts_received = false
	_update_pause()
	Rede.send_message(_start_payload)
	_log("Dados do anfitrião: " + str(die_one) + " x " + str(die_two)
			+ ". " + get_slot_username(starting_slot) + " começa.")
	_apply_start(_start_payload)


func _on_mp_start(data: Dictionary) -> void:
	if is_authority():
		return
	if str(data.get("game_id", game_id)) != game_id:
		return
	var new_rolls = data.get("rolls", [])
	var new_start := int(data.get("starting_slot", 0))
	if typeof(new_rolls) != TYPE_ARRAY or new_rolls.size() != 2 \
			or new_start < 1 or new_start > 2:
		return
	_start_payload = data.duplicate(true)
	rolls = [int(new_rolls[0]), int(new_rolls[1])]
	starting_slot = new_start
	round_number = int(data.get("round", 1))
	step_index = int(data.get("step", 0))
	phase = str(data.get("phase", TURN_PHASES[0]))
	if _start_applied:
		state = State.PLAYING
		_update_pause()
		_send_board_ready()
		emit_signal("match_started")
		emit_signal("session_changed")
		return
	state = State.STARTING
	_initial_state_sent = false
	_update_pause()
	_log("Dados: " + str(rolls[0]) + " x " + str(rolls[1]) + ". "
			+ get_slot_username(starting_slot) + " começa.")
	_apply_start(data)


func _on_mp_abort(data: Dictionary) -> void:
	if str(data.get("game_id", game_id)) != game_id:
		return
	_end_session(str(data.get(
			"message", "A partida não pôde ser iniciada.")))


func _apply_start(data: Dictionary) -> void:
	if _start_applied:
		return
	if not _board or not is_instance_valid(_board) or not _sync:
		return
	var seed_text := str(data.get("seed", ""))
	if local_deck.is_empty() or _count_deck_cards(local_deck) != DECK_SIZE:
		_abort_match("Seu deck não tem 60 cartas; não é possível iniciar.")
		return
	if not _build_local_start(seed_text):
		_abort_match("Não foi possível montar seu deck para a partida.")
		return
	if mode == Mode.SOLO and not _build_solo_opponent(seed_text):
		_abort_match("Não foi possível montar o deck do segundo jogador.")
		return
	_start_applied = true
	state = State.PLAYING
	_mulligan_open = true
	_update_pause()
	if _sync.has_method("set_solo_preview"):
		_sync.set_solo_preview(mode == Mode.SOLO)
	if _sync.has_method("start_mirroring"):
		_sync.start_mirroring()
	if mode == Mode.SOLO:
		# Mirroring starts with the counts at zero because a real peer has not
		# reported yet; the hotseat already knows the other seat's deck.
		set_opponent_counts(opponent_counts)
	_send_board_ready()
	if _sync.has_method("send_snapshot"):
		_sync.send_snapshot()
	emit_signal("match_started")
	emit_signal("phase_changed")
	emit_signal("session_changed")
	_log("Decks embaralhados e 10 cartas compradas.")
	if is_authority():
		_maybe_broadcast_initial_state()


func _build_local_start(seed_text: String) -> bool:
	var deck: Pile = cfc.NMAP.deck
	var hand: Hand = cfc.NMAP.hand
	if not deck or not hand:
		return false
	_mulligan_counts = {}
	_mulligan_accepts = {}
	_mulligan_local_choice = false
	_prep_game_accepts = {}
	_prep_game_local_choice = false
	_effects_applied = {}
	var names: Array = local_deck.get("cards", {}).keys()
	names.sort()
	var instance_count := 0
	for card_name in names:
		var quantity := int(local_deck.cards[card_name])
		for _i in range(quantity):
			var card = cfc.instance_card(str(card_name))
			if not card:
				return false
			deck.add_child(card)
			card.set_is_faceup(false, true)
			card.set_state(Card.CardState.IN_PILE)
			ensure_card_id(card)
			instance_count += 1
	if instance_count != DECK_SIZE:
		return false
	cfc.set_seed(seed_text + "|deck")
	deck.shuffle_cards(false)
	deck.reorganize_stack()
	if not _deal_to_hand(hand, deck, START_HAND_SIZE):
		return false
	hand.re_place()
	hand.call_deferred("re_place")
	_resolve_auto_mulligan(seed_text)
	return true


# Moves `count` cards from the top of the deck to the hand.
func _deal_to_hand(hand: Hand, deck: Pile, count: int) -> bool:
	for _i in range(count):
		var card = deck.get_top_card()
		if not card:
			return false
		deck.remove_child(card)
		hand.add_child(card)
		card.set_is_faceup(true, true)
		card.set_state(Card.CardState.IN_HAND)
		card.position = card.recalculate_position()
		ensure_card_id(card)
	return true


# Sends every card of the hand back to the deck, face down.
func _return_hand_to_deck(hand: Hand, deck: Pile) -> void:
	for card in hand.get_all_cards():
		if not is_instance_valid(card):
			continue
		hand.remove_child(card)
		deck.add_child(card)
		card.set_is_faceup(false, true)
		card.set_state(Card.CardState.IN_PILE)


# A hand with one or no characters goes back to the deck and is dealt again
# (AUTOTURNO.md §3.1). The shuffle is seeded from the match seed, so every
# client reaches the same hand without exchanging messages.
func _resolve_auto_mulligan(seed_text: String) -> void:
	var deck: Pile = cfc.NMAP.get("deck", null)
	var hand: Hand = cfc.NMAP.get("hand", null)
	if not deck or not hand:
		return
	var attempts := 0
	while TurnRules.needs_auto_mulligan(hand.get_all_cards()) \
			and not TurnRules.auto_mulligan_limit_reached(attempts):
		attempts += 1
		_return_hand_to_deck(hand, deck)
		cfc.set_seed(seed_text + "|mulligan" + str(attempts))
		deck.shuffle_cards(false)
		deck.reorganize_stack()
		if not _deal_to_hand(hand, deck, START_HAND_SIZE):
			return
		hand.re_place()
		_log("Mulligan automático " + str(attempts) + ": a mão tinha menos de "
				+ "dois Personagens e foi trocada.")
	if attempts > 0:
		hand.call_deferred("re_place")
	if TurnRules.auto_mulligan_limit_reached(attempts) \
			and TurnRules.needs_auto_mulligan(hand.get_all_cards()):
		_log("Mulligan automático: limite de proteção atingido; seguindo com "
				+ "a mão atual.")


# --- Manual mulligan (AUTOTURNO.md §3.2) -------------------------------

## The mulligan window is open from the deal until every seat keeps its hand.
func is_mulligan_open() -> bool:
	return _mulligan_open


## What the HUD needs to draw the mulligan panel.
func get_mulligan_info() -> Dictionary:
	var hand: Hand = cfc.NMAP.get("hand", null)
	var resources: Pile = cfc.NMAP.get("discard", null)
	var hand_size := hand.get_all_cards().size() if hand else 0
	return {
		"hand_size": hand_size,
		"resources": resources.get_all_cards().size() if resources else 0,
		"cost": TurnRules.manual_mulligan_cost(hand_size),
		"draw": TurnRules.manual_mulligan_draw(hand_size),
		"repetition": int(_mulligan_counts.get(str(my_slot), 0)),
		"max_repetitions": TurnRules.manual_mulligan_sequence().size(),
		"can_mulligan": _mulligan_open and TurnRules.can_manual_mulligan(hand_size),
		"pending": _mulligan_open,
		"waiting_for_opponent": _mulligan_open and _mulligan_local_choice,
	}


## One manual mulligan: only the hand goes back to the deck, the cards already
## in resources stay there, two cards from the top become resources and the
## player draws two fewer cards than before. Returns false when there is
## nothing left to shuffle back.
func manual_mulligan_local() -> bool:
	var deck: Pile = cfc.NMAP.get("deck", null)
	var hand: Hand = cfc.NMAP.get("hand", null)
	var resources: Pile = cfc.NMAP.get("discard", null)
	if not deck or not hand or not resources:
		return false
	if not _mulligan_open:
		return false
	var hand_size := hand.get_all_cards().size()
	if not TurnRules.can_manual_mulligan(hand_size):
		return false
	var cost := TurnRules.manual_mulligan_cost(hand_size)
	var draw := TurnRules.manual_mulligan_draw(hand_size)
	var repetition := int(_mulligan_counts.get(str(my_slot), 0)) + 1
	_mulligan_counts[str(my_slot)] = repetition
	_return_hand_to_deck(hand, deck)
	deck.shuffle_cards(false)
	deck.reorganize_stack()
	for _i in range(cost):
		var card = deck.get_top_card()
		if not card:
			break
		deck.remove_child(card)
		resources.add_child(card)
		card.set_is_faceup(true, true)
		card.set_state(Card.CardState.IN_PILE)
		ensure_card_id(card)
	if draw > 0 and not _deal_to_hand(hand, deck, draw):
		return false
	hand.re_place()
	hand.call_deferred("re_place")
	resources.reorganize_stack()
	_log_shared("Mulligan manual " + str(repetition) + ": " + str(cost)
			+ " carta(s) para Recursos/Descarte, comprou " + str(draw) + ".")
	emit_signal("display_changed")
	emit_signal("mulligan_changed")
	# Decision 6b: an empty hand has nothing left to give back, so the seat keeps
	# what it has and the turn opens as soon as the other seat answers.
	if not TurnRules.can_manual_mulligan(hand.get_all_cards().size()):
		accept_local_hand()
	return true


## The seat keeps the hand it was dealt. The first turn only opens after both
## seats answer (decision 12).
func accept_local_hand() -> bool:
	if not _mulligan_open or _mulligan_local_choice:
		return false
	_mulligan_local_choice = true
	_log_shared(get_my_username() + " ficou com a mão de "
			+ str(_hand_size_of(my_slot)) + " cartas.")
	if is_authority():
		_record_mulligan_accept(my_slot)
	else:
		Rede.send_message({"t": "mp_mulligan_accept", "game_id": game_id})
	emit_signal("mulligan_changed")
	# In the hotseat the next answer belongs to the other seat, which takes the
	# table on its own.
	_hand_to_seat_that_owes_an_answer()
	return true


func _hand_size_of(slot: int) -> int:
	# In the hotseat only the controlled seat has Card nodes; the other one is
	# still the data payload the seat swap will materialise.
	if slot != my_slot:
		var payload: Dictionary = _solo_hidden.get(slot, {})
		return _entry_count(payload.get("hand", []))
	var hand: Hand = cfc.NMAP.get("hand", null)
	return hand.get_all_cards().size() if hand else 0


func _record_mulligan_accept(slot: int) -> void:
	if not is_authority():
		return
	_mulligan_accepts[str(slot)] = true
	if _mulligan_accepts.has("1") and _mulligan_accepts.has("2"):
		_mulligan_open = false
		_log_shared("Os dois jogadores ficaram com a mão. A partida vai começar.")
		# The match opens on Contagem Regressiva, but the preparation window comes
		# first: the owed step is paid when that one closes (decision 11a).
		_open_prep_game_window()
		_broadcast_public_state(false)
	emit_signal("mulligan_changed")


func _on_mp_mulligan_accept(data: Dictionary) -> void:
	if not is_authority() or state != State.PLAYING:
		return
	if str(data.get("game_id", game_id)) != game_id:
		return
	_record_mulligan_accept(opponent_slot)


# --- Preparação do jogo (AUTOTURNO.md §3.3) ------------------------------

## True while the free discard window is open. The authority owns it and the
## guest mirrors it from the public state, exactly like the mulligan gate.
func is_prep_game_open() -> bool:
	return _prep_game_open


## What the HUD needs to draw the preparation panel.
func get_prep_game_info() -> Dictionary:
	var hand: Hand = cfc.NMAP.get("hand", null)
	var resources: Pile = cfc.NMAP.get("discard", null)
	return {
		"hand_size": hand.get_all_cards().size() if hand else 0,
		"resources": resources.get_all_cards().size() if resources else 0,
		"answered": _prep_game_local_choice,
		"waiting_for_opponent": _prep_game_open and _prep_game_local_choice,
	}


func _open_prep_game_window() -> void:
	_prep_game_open = true
	_prep_game_local_choice = false
	_prep_game_accepts = {}
	_log_shared("Preparação: descartem quantas cartas quiserem e cliquem em Pronto.")


## The seat has nothing left to throw away. The first turn only opens after both
## seats answer, the same way the mulligan window closes (decision 8a).
func ready_local_prep_game() -> bool:
	if not _prep_game_open or _prep_game_local_choice:
		return false
	_prep_game_local_choice = true
	_log_shared(get_my_username() + " terminou a preparação com "
			+ str(_hand_size_of(my_slot)) + " carta(s) na mão.")
	if is_authority():
		_record_prep_game_ready(my_slot)
	else:
		Rede.send_message({"t": "mp_prep_game_ready", "game_id": game_id})
	emit_signal("prep_game_changed")
	_hand_to_seat_that_owes_an_answer()
	return true


func _record_prep_game_ready(slot: int) -> void:
	if not is_authority():
		return
	_prep_game_accepts[str(slot)] = true
	if not (_prep_game_accepts.has("1") and _prep_game_accepts.has("2")):
		emit_signal("prep_game_changed")
		return
	_prep_game_open = false
	_log_shared("Os dois jogadores terminaram a preparação.")
	# Contagem Regressiva is the step the match opens on, and it is the one this
	# window was standing in front of (decision 11a). The hotseat gives the table
	# to whoever opens the turn before paying it, so the step uses that seat's deck.
	_follow_turn_in_solo()
	# The opening of the match pays the countdown and the draw on its own, like
	# every other turn: the table stops on Preparação.
	_update_auto_turn()
	run_phase_effects()
	# The skip of an empty Ajuste is a decision of the table: it is armed before
	# the state is announced so the advance button never shows for that step.
	_schedule_auto_advance()
	_broadcast_public_state(false)
	emit_signal("prep_game_changed")


func _on_mp_prep_game_ready(data: Dictionary) -> void:
	if not is_authority() or state != State.PLAYING:
		return
	if str(data.get("game_id", game_id)) != game_id:
		return
	_record_prep_game_ready(opponent_slot)


# --- Ajuste de Energia (AUTOTURNO.md §3.4) -------------------------------

## True while the seat on the table still has to take energy off a character.
func is_adjustment_open() -> bool:
	return _adjustment_open


## What the HUD needs to draw the adjustment panel.
func get_adjustment_info() -> Dictionary:
	var lines := PackedStringArray()
	for operation in _adjustment_operations:
		var count := int(operation.get("count", 0))
		lines.append("Retire " + str(count) + " carta"
				+ ("" if count == 1 else "s") + " de "
				+ str(operation.get("target", "")) + ".")
	return {
		"pending": _adjustment_open,
		"operations": _adjustment_operations.duplicate(true),
		"text": "\n".join(lines),
	}


## Recomputes the gate from the real cards of the seat on the table. It opens
## only on the Ajuste step, for the seat that owns the cards, and closes as
## soon as every character is back to its Energia Inicial — which is what
## releases the advance button again.
func refresh_adjustment() -> bool:
	var operations: Array = []
	var should_open := false
	if state == State.PLAYING and phase == TurnRules.PHASE_ADJ \
			and not _mulligan_open and not _prep_game_open \
			and my_slot > 0 and get_actor_slot() == my_slot:
		operations = TurnRules.adjustment_operations(
				_turn_facts().get("characters", []))
		should_open = not operations.is_empty()
	var changed := should_open != _adjustment_open
	_adjustment_open = should_open
	_adjustment_operations = operations
	if changed:
		emit_signal("adjustment_changed")
	return _adjustment_open


#-----------------------------------------------------------------------------
# Automatic phase effects (AUTOTURNO.md §3.4)
#-----------------------------------------------------------------------------

## True when the open phase still has its automatic step waiting for the seat
## this client controls.
func has_pending_phase_effect() -> bool:
	if state != State.PLAYING or _mulligan_open or _prep_game_open:
		return false
	if not phase in EFFECT_PHASES:
		return false
	# Only the seat holding its own Card nodes can move them: the other seat is a
	# data payload in the hotseat and lives on the peer's client online.
	if my_slot <= 0 or get_actor_slot() != my_slot:
		return false
	if _effects_applied.has(_phase_effect_key()):
		return false
	return _board != null and is_instance_valid(_board)


func _phase_effect_key() -> String:
	return str(round_number) + ":" + str(step_index)


## Plays the automatic step of the open phase. Called by everything that can
## open a phase for the local seat: a step, a seat swap or the mulligan gate.
## The Ajuste step has no automatic move; this is where its gate is recomputed.
func run_phase_effects() -> bool:
	if not has_pending_phase_effect():
		refresh_adjustment()
		return false
	_effects_applied[_phase_effect_key()] = true
	# The automatic opening is summarized in one shared line, so the cards it
	# moves stay out of the event log instead of filling it with one line each.
	var keep_suppressed := GameEvents.suppressed
	if _auto_turn_active:
		GameEvents.suppressed = true
	var facts := _turn_facts()
	facts["is_first_turn"] = is_first_turn_of_match()
	var operations: Array = TurnRules.operations_for_phase(phase, facts)
	var applied := 0
	for operation in operations:
		# A demand the deck could not pay for ends the match, and the steps that
		# follow it belong to a turn that is not being played anymore.
		if state != State.PLAYING:
			break
		applied += _apply_turn_operation(operation)
	GameEvents.suppressed = keep_suppressed
	refresh_adjustment()
	return applied > 0


# The countdown and the draw are the only phases with nothing for the seat to
# decide, so the table pays them and moves on — including the one the match
# opens on, right after the preparation window closes.
func _is_auto_turn_opening() -> bool:
	return phase == TurnRules.PHASE_REG


# Marks the automatic opening for the seat that owns the cards. The other client
# leaves the flags off and only mirrors: it has no Card nodes to move for a
# turn that is not its own.
func _update_auto_turn() -> void:
	if _is_auto_turn_opening() \
			and (mode == Mode.SOLO or get_actor_slot() == my_slot):
		if not _auto_turn_active:
			_auto_turn_active = true
			_auto_turn_resources = 0
			_auto_turn_draws = 0
	elif not phase in EFFECT_PHASES:
		_auto_turn_active = false
		_auto_advance_pending = false


## True while the table is paying or skipping a step on its own; the HUD hides
## the advance button for that stretch.
func is_auto_turn_running() -> bool:
	if _auto_advance_pending:
		return true
	return _auto_turn_active and phase in EFFECT_PHASES


## True while the open step is one of the automatic phases of a turn opening.
## The sync reads it to leave the mirrored cards of that opening out of the log.
func is_auto_turn_step() -> bool:
	return _is_auto_state({"round": round_number, "step": step_index})


# A public state that opens a turn on the automatic phases. Both clients can
# tell it from the step alone, which is what keeps the mirrored moves of that
# opening out of the opponent's log too.
func _is_auto_state(public_state: Dictionary) -> bool:
	return phase_for_step(int(public_state.get("step", -1))) in EFFECT_PHASES


# The opening pays itself and moves on. The Ajuste has nothing automatic to play
# either, so it is skipped the same way — but only while every character is back
# to its Energia Inicial: with the gate open the seat has a decision to make and
# the table waits for it.
func _can_auto_advance() -> bool:
	if state != State.PLAYING:
		return false
	if _mulligan_open or _prep_game_open or _adjustment_open:
		return false
	if mode != Mode.SOLO and get_actor_slot() != my_slot:
		return false
	if phase in EFFECT_PHASES:
		return _auto_turn_active and _effects_applied.has(_phase_effect_key())
	return phase == TurnRules.PHASE_ADJ


# Pays the rest of the automatic opening and moves the table to Preparação. Each
# client schedules its own turn because only the seat holding the cards can move
# them; the guest asks the authority for the step like any other advance.
func _schedule_auto_advance() -> void:
	if _auto_advance_pending or not _can_auto_advance():
		return
	var key := _phase_effect_key()
	_auto_advance_pending = true
	await get_tree().create_timer(AUTO_TURN_SECONDS).timeout
	_auto_advance_pending = false
	# A phase that changed in the meantime is not the one this timer was for.
	if _phase_effect_key() != key or not _can_auto_advance():
		return
	if phase == TurnRules.PHASE_DRAW:
		_log_auto_turn()
	advance_phase()


# One line summarizes the two automatic phases, so the top of every turn does not
# cost one log line per card moved. It is shared: both seats read the same story.
func _log_auto_turn() -> void:
	if not _auto_turn_active:
		return
	_auto_turn_active = false
	var resources := _auto_turn_resources
	var draws := _auto_turn_draws
	_auto_turn_resources = 0
	_auto_turn_draws = 0
	_log_shared("Contagem Regressiva e Compra: " + str(resources)
			+ (" carta" if resources == 1 else " cartas")
			+ " para os Recursos + " + str(draws)
			+ (" compra" if draws == 1 else " compras") + ".")


func _turn_facts() -> Dictionary:
	if _sync and _sync.has_method("get_turn_facts"):
		return _sync.get_turn_facts()
	return {
		"characters_in_play": 0,
		"characters": [],
		"opponent_characters": 0,
		"opponent_prizes": 0,
	}


# Every automatic move runs through the intent runner, so it is validated,
# logged and mirrored exactly like the same move made by hand.
func _apply_turn_operation(operation: Dictionary) -> int:
	var count := int(operation.get("count", 0))
	match str(operation.get("op", "")):
		"top_to_resources":
			if count > 0 and _apply_intent({
					"op": "mandar_topo_para_recursos", "quantity": count}):
				if _auto_turn_active:
					_auto_turn_resources += count
				else:
					_log("Contagem Regressiva: " + str(count)
							+ " carta(s) do topo do deck viraram Recursos.")
				return 1
		"draw":
			if count > 0 and _apply_intent({"op": "comprar", "quantity": count}):
				if _auto_turn_active:
					_auto_turn_draws += count
				else:
					_log("Compra: " + str(count) + " carta(s) comprada(s).")
				return 1
	return 0


func _apply_intent(intent: Dictionary) -> bool:
	if not _board or not is_instance_valid(_board) \
			or not _board.has_method("apply_intent"):
		return false
	var result: Dictionary = _board.apply_intent(intent)
	if not bool(result.get("ok", false)):
		_log("A fase automática não conseguiu jogar: "
				+ str(result.get("message", "")))
		return false
	return true


#-----------------------------------------------------------------------------
# Empty deck (AUTOTURNO.md §3.5)
#-----------------------------------------------------------------------------

## The result of an empty deck (decisão 10c): the seat that owed the cards loses
## on the spot, the opponent is credited with the victory and the reason is
## written in the log. The table calls it for every demand that could not be
## paid for — a phase, a click or an effect of a card.
func declare_empty_deck_loss(seat: int, needed: int) -> void:
	if state != State.PLAYING or seat < 1 or seat > 2:
		return
	var amount := maxi(1, needed)
	var reason := get_slot_username(seat) + " precisou de " + str(amount) \
			+ " carta(s) de um deck vazio."
	_log(reason)
	# Every client that hears about the run-out declares it, so a guest whose own
	# deck ran out does not have to wait for the host to stop playing.
	if Rede.is_connected and not game_id.is_empty():
		Rede.send_message({
			"t": "mp_result",
			"game_id": game_id,
			"seat": seat,
			"needed": amount,
		})
	var winner := 3 - seat
	if _board and is_instance_valid(_board) \
			and _board.has_method("report_empty_deck_victory"):
		_board.report_empty_deck_victory(winner, reason)
	_end_session(reason + " " + get_slot_username(winner)
			+ " venceu a partida.")


func _on_mp_result(data: Dictionary) -> void:
	if str(data.get("game_id", game_id)) != game_id:
		return
	declare_empty_deck_loss(int(data.get("seat", 0)),
			int(data.get("needed", 1)))


#-----------------------------------------------------------------------------
# Solo hotseat
#-----------------------------------------------------------------------------

# The seat that is not being controlled keeps its cards as data only: its Card
# nodes are created when the player swaps into it and freed when they swap out.
func _build_solo_opponent(seed_text: String) -> bool:
	var deck: Dictionary = solo_decks.get(opponent_slot, {})
	if _count_deck_cards(deck) != DECK_SIZE:
		return false
	var payload := _solo_hidden_payload(deck, opponent_slot, seed_text)
	if payload.is_empty():
		return false
	_solo_hidden[opponent_slot] = payload
	set_opponent_counts({
		"hand": payload["hand"].size(),
		"deck": payload["deck"].size(),
	})
	_opponent_board_counts_received = true
	return true


func _solo_hidden_payload(
		deck: Dictionary, slot: int, seed_text: String) -> Dictionary:
	var names: Array = deck.get("cards", {}).keys()
	names.sort()
	var pool := []
	for card_name in names:
		for _i in range(int(deck.cards[card_name])):
			pool.append(str(card_name))
	if pool.size() != DECK_SIZE:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text + "|seat" + str(slot))
	# The hidden seat obeys the same automatic mulligan as the local one.
	var attempts := 0
	while true:
		_shuffle_names(pool, rng)
		if not _names_need_auto_mulligan(pool.slice(0, START_HAND_SIZE)) \
				or TurnRules.auto_mulligan_limit_reached(attempts):
			break
		attempts += 1
	if attempts > 0:
		_log("Mulligan automático do assento " + str(slot) + ": "
				+ str(attempts) + " troca(s) por falta de Personagens.")
	var hand := []
	var rest := []
	for index in range(pool.size()):
		var entry := {
			"id": "SOLO" + str(slot) + "_" + str(index + 1),
			"name": pool[index],
		}
		if index < START_HAND_SIZE:
			hand.append(entry)
		else:
			rest.append(entry)
	return {"hand": hand, "deck": rest, "definitions": {}}


# Fisher-Yates over card names, driven by an explicit RNG so the hidden seat
# stays reproducible from the match seed.
func _shuffle_names(pool: Array, rng: RandomNumberGenerator) -> void:
	for index in range(pool.size() - 1, 0, -1):
		var pick := rng.randi_range(0, index)
		var held = pool[index]
		pool[index] = pool[pick]
		pool[pick] = held


# Same question as TurnRules.needs_auto_mulligan, answered from card names.
func _names_need_auto_mulligan(names: Array) -> bool:
	var cards := []
	for card_name in names:
		var definition: Dictionary = cfc.card_definitions.get(str(card_name), {})
		cards.append({"_tipo": str(definition.get("_tipo", ""))})
	return TurnRules.needs_auto_mulligan(cards)


# Swapping seats rebuilds the table from the state that a checkpoint restore
# would use, so the hotseat shows exactly what the other client would show.
func swap_solo_seat() -> bool:
	if mode != Mode.SOLO or state != State.PLAYING:
		return false
	if not _board or not is_instance_valid(_board) or not _sync:
		return false
	var target_slot := opponent_slot
	if _solo_hidden.get(target_slot, {}).is_empty():
		_log("O assento " + get_slot_username(target_slot)
				+ " ainda não tem cartas.")
		return false
	var public_state := _build_public_state(sequence)
	_solo_hidden[my_slot] = _build_private_payload()
	my_slot = target_slot
	opponent_slot = 3 - target_slot
	if _mulligan_open:
		# Every seat keeps its own hand, so the seat that just took the table has
		# to answer for itself (decision 12) — unless it already did.
		_mulligan_local_choice = _mulligan_accepts.has(str(my_slot))
	if _prep_game_open:
		# The same argument for the preparation window: each seat discards its own
		# hand and clicks Pronto for itself (decision 8a).
		_prep_game_local_choice = _prep_game_accepts.has(str(my_slot))
	_rebuild_solo_board(public_state)
	return true


# --- Hotseat convenience -------------------------------------------------
# The hotseat player is both seats, so the table follows the action: after a
# seat answers, the next answer belongs to the other one, and between steps the
# seat that acts takes the table. Nothing here runs online, where each side is
# already sitting at its own seat.

func _hand_to_seat_that_owes_an_answer() -> bool:
	if mode != Mode.SOLO or state != State.PLAYING:
		return false
	var other := 3 - my_slot
	if _mulligan_open and _mulligan_local_choice \
			and not _mulligan_accepts.has(str(other)):
		return swap_solo_seat()
	if _prep_game_open and _prep_game_local_choice \
			and not _prep_game_accepts.has(str(other)):
		return swap_solo_seat()
	return false


func _follow_turn_in_solo() -> bool:
	if mode != Mode.SOLO or state != State.PLAYING:
		return false
	if _mulligan_open or _prep_game_open:
		return false
	if get_actor_slot() == my_slot:
		return false
	return swap_solo_seat()


func _rebuild_solo_board(public_state: Dictionary) -> void:
	if _sync.has_method("set_suppressed"):
		_sync.set_suppressed(true)
	GameEvents.suppressed = true
	_solo_clear_local_cards()
	_restore_own_hidden_cards(_solo_hidden.get(my_slot, {}))
	# The mirror is applied before the local cards, which is the same order the
	# checkpoint restore uses. `_restore_own_public_cards` ends by resolving the
	# opponent attachments against the mirror, so it has to run after
	# `apply_public_snapshot` (which starts by clearing it). With the reverse
	# order a resource sitting under a character lost its host and turned into a
	# loose card in the opponent band.
	if _sync.has_method("apply_public_snapshot"):
		_sync.apply_public_snapshot(public_state, opponent_slot)
	_restore_own_public_cards(public_state)
	GameEvents.suppressed = false
	if _sync.has_method("set_suppressed"):
		_sync.set_suppressed(false)
	var mirrored: Dictionary = _solo_hidden.get(opponent_slot, {})
	set_opponent_counts({
		"hand": _entry_count(mirrored.get("hand", [])),
		"deck": _entry_count(mirrored.get("deck", [])),
	})
	if _sync.has_method("reconcile_scenarios"):
		_sync.reconcile_scenarios(public_state)
	# The seat that just took the table may be the one an open phase is waiting
	# for, so the automatic step runs as soon as its real cards exist.
	run_phase_effects()
	emit_signal("phase_changed")
	emit_signal("session_changed")
	_log("Você agora controla " + get_slot_username(my_slot) + ".")


func _entry_count(entries) -> int:
	return entries.size() if typeof(entries) == TYPE_ARRAY else 0


func _solo_clear_local_cards() -> void:
	for card in get_tree().get_nodes_in_group("cards"):
		if not (card is Card) or not is_instance_valid(card) or card.network_mirror:
			continue
		var slot = card._placement_slot
		if slot and is_instance_valid(slot):
			slot.occupying_card = null
		card._placement_slot = null
		var parent = card.get_parent()
		if parent:
			parent.remove_child(card)
		card.queue_free()
	for pile_name in ["deck", "discard"]:
		var pile = cfc.NMAP.get(pile_name, null)
		if pile and pile.has_method("reorganize_stack"):
			pile.reorganize_stack()
	var prizes: Pile = _prizes_pile()
	if prizes and prizes.has_method("reorganize_stack"):
		prizes.reorganize_stack()


func _send_board_ready() -> void:
	var counts := _local_hidden_counts()
	Rede.send_message({
		"t": "mp_board_ready",
		"game_id": game_id,
		"hand": counts["hand"],
		"deck": counts["deck"],
	})
	if _sync and _sync.has_method("send_counts"):
		_sync.send_counts()


func _on_mp_board_ready(data: Dictionary) -> void:
	if str(data.get("game_id", game_id)) != game_id:
		return
	var counts := {
		"hand": max(0, int(data.get("hand", 0))),
		"deck": max(0, int(data.get("deck", 0))),
	}
	set_opponent_counts(counts)
	_opponent_board_counts_received = true
	if is_authority() and state == State.PLAYING and not _initial_state_sent:
		_maybe_broadcast_initial_state()


func _maybe_broadcast_initial_state() -> void:
	if not is_authority() or _initial_state_sent or not _opponent_board_counts_received:
		return
	if not _board or not _sync:
		return
	_initial_state_sent = true
	_broadcast_public_state()


#-----------------------------------------------------------------------------
# Phase / authority
#-----------------------------------------------------------------------------

func _on_mp_phase_request(data: Dictionary) -> void:
	if not is_authority() or state != State.PLAYING:
		return
	if str(data.get("game_id", game_id)) != game_id:
		return
	if int(data.get("sequence", -1)) != sequence:
		_broadcast_current_state_again()
		return
	if int(data.get("step", -1)) != step_index:
		_broadcast_current_state_again()
		return
	if get_actor_slot() != opponent_slot:
		_broadcast_current_state_again()
		return
	_advance_as_authority()


func _advance_as_authority() -> void:
	if not is_authority() or state != State.PLAYING:
		return
	step_index += 1
	if step_index >= get_steps_per_round():
		step_index = 0
		round_number += 1
		# Every step of the finished round has been played; the marker only has
		# to remember the current turn so it does not grow with the match.
		_effects_applied = {}
	phase = phase_for_step(step_index)
	_update_auto_turn()
	# The step that just opened belongs to the other seat in the hotseat, so the
	# table goes with it instead of waiting for a manual "Controlar P2"; the swap
	# also pays that seat's automatic step with its own cards, before the state is
	# published.
	_follow_turn_in_solo()
	run_phase_effects()
	# Armed before the announcement so the HUD never offers a button for a step
	# the table is already passing by itself.
	_schedule_auto_advance()
	_broadcast_public_state()


# `announce` emits phase_changed, which GameEvents turns into a phase line in
# the log. A message that only moves a gate, like the end of the mulligan
# window, has to refresh the state without repeating the phase entry.
func _broadcast_public_state(announce: bool = true) -> void:
	if not is_authority() or not _board or not _sync:
		return
	sequence += 1
	var public_state := _build_public_state(sequence)
	_store_public_state(public_state)
	Rede.send_message({"t": "mp_state", "state": public_state})
	_send_private_envelope(sequence)
	if announce:
		emit_signal("phase_changed")
	emit_signal("mulligan_changed")
	emit_signal("prep_game_changed")
	emit_signal("session_changed")


func _broadcast_current_state_again() -> void:
	if not is_authority() or sequence < 0:
		return
	var cached = _public_states.get(sequence)
	if typeof(cached) == TYPE_DICTIONARY:
		Rede.send_message({"t": "mp_state", "state": cached})
	else:
		_broadcast_public_state()


func _on_mp_state(data: Dictionary) -> void:
	if is_authority() or state != State.PLAYING:
		return
	var public_state = data.get("state", {})
	if typeof(public_state) != TYPE_DICTIONARY:
		return
	if not _validate_public_state(public_state):
		return
	var incoming_sequence := int(public_state.get("sequence", -1))
	if incoming_sequence < sequence:
		return
	sequence = incoming_sequence
	phase = str(public_state.get("phase", phase))
	round_number = int(public_state.get("round", round_number))
	step_index = int(public_state.get("step", step_index))
	starting_slot = int(public_state.get("starting_slot", starting_slot))
	_update_auto_turn()
	var keep_suppressed := GameEvents.suppressed
	if _is_auto_state(public_state):
		GameEvents.suppressed = true
	_absorb_turn_state(public_state)
	GameEvents.suppressed = keep_suppressed
	var new_rolls = public_state.get("rolls", rolls)
	if typeof(new_rolls) == TYPE_ARRAY:
		rolls = [int(new_rolls[0]), int(new_rolls[1])] if new_rolls.size() == 2 else rolls
	_store_public_state(public_state)
	# The automatic step of a phase belongs to the seat that owns the cards, so
	# the guest plays its own draw here and only then reports the private state
	# for the checkpoint.
	run_phase_effects()
	_send_private_envelope(sequence)
	_schedule_auto_advance()
	emit_signal("phase_changed")
	emit_signal("mulligan_changed")
	emit_signal("prep_game_changed")
	emit_signal("session_changed")


func _validate_public_state(public_state: Dictionary) -> bool:
	if str(public_state.get("phase", "")) == "":
		return false
	if int(public_state.get("step", -1)) < 0 \
			or int(public_state.get("step", -1)) >= get_steps_per_round():
		return false
	if int(public_state.get("round", 0)) < 1:
		return false
	var slot := int(public_state.get("starting_slot", 0))
	if slot < 1 or slot > 2:
		return false
	var step := int(public_state.get("step", -1))
	if str(public_state.get("phase", "")) != phase_for_step(step):
		return false
	if typeof(public_state.get("cards", null)) != TYPE_ARRAY:
		return false
	if typeof(public_state.get("hidden", null)) != TYPE_DICTIONARY:
		return false
	return true


func _build_public_state(seq: int) -> Dictionary:
	var hidden := {}
	hidden[str(my_slot)] = _local_hidden_counts()
	hidden[str(opponent_slot)] = opponent_counts.duplicate()
	var cards := []
	var definitions := {}
	if _sync and _sync.has_method("build_public_card_entries"):
		var result = _sync.build_public_card_entries(my_slot, opponent_slot)
		if typeof(result) == TYPE_DICTIONARY:
			cards = result.get("cards", [])
			definitions = result.get("definitions", {})
	return {
		"phase": phase,
		"round": round_number,
		"step": step_index,
		"sequence": seq,
		"starting_slot": starting_slot,
		"mulligan_open": _mulligan_open,
		"prep_game_open": _prep_game_open,
		"mulligan_counts": _mulligan_counts.duplicate(true),
		"effects_applied": _effects_applied.duplicate(true),
		"rolls": rolls,
		"hidden": hidden,
		"cards": cards,
		"definitions": definitions,
	}


## Brings the turn bookkeeping of this client in line with a public state it just
## received. The two gates are copied whole because the authority owns them; the
## per-seat counters and the paid-step markers are merged, since each client only
## ever writes the entries of its own seat and a resumed player must not replay a
## step the table already paid (AUTOTURNO.md §4.1).
func _absorb_turn_state(public_state: Dictionary) -> void:
	var open_flag = public_state.get("mulligan_open", _mulligan_open)
	if typeof(open_flag) == TYPE_BOOL:
		_mulligan_open = open_flag
	var prep_flag = public_state.get("prep_game_open", _prep_game_open)
	if typeof(prep_flag) == TYPE_BOOL:
		_prep_game_open = prep_flag
	var counts = public_state.get("mulligan_counts", {})
	if typeof(counts) == TYPE_DICTIONARY:
		for seat in counts:
			_mulligan_counts[str(seat)] = int(counts[seat])
	var applied = public_state.get("effects_applied", {})
	if typeof(applied) == TYPE_DICTIONARY:
		for step in applied:
			_effects_applied[str(step)] = true


func _store_public_state(public_state: Dictionary) -> void:
	var seq := int(public_state.get("sequence", -1))
	if seq < 0:
		return
	_public_states[seq] = public_state
	while _public_states.size() > MAX_CACHED_STATES:
		var oldest := 2147483647
		for key in _public_states:
			oldest = min(oldest, int(key))
		_public_states.erase(oldest)


#-----------------------------------------------------------------------------
# Private data and checkpoints
#-----------------------------------------------------------------------------

func _local_hidden_counts() -> Dictionary:
	return {
		"hand": _container_card_count(cfc.NMAP.get("hand", null)),
		"deck": _container_card_count(cfc.NMAP.get("deck", null)),
	}


func _container_card_count(container) -> int:
	if not container or not is_instance_valid(container):
		return 0
	if container is Pile and container.is_popup_open:
		var count := 0
		for card in container.pre_sorted_order:
			if is_instance_valid(card) and card is Card:
				count += 1
		return count
	var total := 0
	for child in container.get_children():
		if child is Card and is_instance_valid(child):
			total += 1
	return total


func _local_cards_in(container) -> Array:
	var result := []
	if container is Pile and container.is_popup_open:
		for card in container.pre_sorted_order:
			if is_instance_valid(card):
				result.append(card)
		return result
	for child in container.get_children():
		if child is Card:
			result.append(child)
	return result


func _build_private_payload() -> Dictionary:
	var hand_entries := []
	var deck_entries := []
	var definitions := {}
	if cfc.NMAP.has("hand"):
		for card in _local_cards_in(cfc.NMAP.hand):
			ensure_card_id(card)
			hand_entries.append({"id": card.network_id, "name": card.definition_key()})
			definitions[card.definition_key()] = \
					cfc.card_definitions.get(card.definition_key(), {})
	if cfc.NMAP.has("deck"):
		for card in _local_cards_in(cfc.NMAP.deck):
			ensure_card_id(card)
			deck_entries.append({"id": card.network_id, "name": card.definition_key()})
			definitions[card.definition_key()] = \
					cfc.card_definitions.get(card.definition_key(), {})
	return {
		"hand": hand_entries,
		"deck": deck_entries,
		"definitions": definitions,
	}


func _send_private_envelope(seq: int) -> void:
	if seq < 0 or Rede.player_username.is_empty():
		return
	# A hotseat has no peer to send to and both seats share one username, so a
	# checkpoint could never hold two distinct envelopes.
	if mode == Mode.SOLO:
		return
	var payload := _build_private_payload()
	var envelope := CheckpointStore.protect_payload(
			payload, Rede.player_username)
	if not _private_envelopes.has(seq):
		_private_envelopes[seq] = {}
	_private_envelopes[seq][Rede.player_username] = envelope
	_prune_private_envelopes()
	Rede.send_message({
		"t": "mp_private",
		"game_id": game_id,
		"sequence": seq,
		"envelope": envelope,
		"hand": payload["hand"].size(),
		"deck": payload["deck"].size(),
	})
	_try_save_checkpoint(seq)


func _on_mp_private(data: Dictionary) -> void:
	if str(data.get("game_id", game_id)) != game_id:
		return
	var seq := int(data.get("sequence", -1))
	var envelope := str(data.get("envelope", ""))
	if seq < 0 or envelope.is_empty():
		return
	# The envelope is sealed with the sender's `Rede.player_username`. The name
	# this client knows for the opponent can differ in case or come from the
	# participant list on a resumed match, so every known name is tried before
	# declaring the payload unreadable. Our own names never open it.
	var opener := ""
	for key in _opponent_envelope_keys(data):
		if not CheckpointStore.unprotect_payload(envelope, key).is_empty():
			opener = key
			break
	if opener.is_empty():
		_log("Dados privados do oponente não puderam ser verificados.")
		return
	if not _private_envelopes.has(seq):
		_private_envelopes[seq] = {}
	# The checkpoint is looked up by seat name, so the envelope is filed under
	# every name that may stand for the opponent, plus the one that opened it.
	for key in [opener, Rede.opponent_username, get_slot_username(opponent_slot)]:
		var name := str(key)
		if not name.is_empty():
			_private_envelopes[seq][name] = envelope
	_prune_private_envelopes()
	_try_save_checkpoint(seq)


# Candidate usernames for opening the opponent's envelope: the one the relay
# attached to the message, the room's opponent name and both seats, minus our
# own names.
func _opponent_envelope_keys(data: Dictionary) -> Array:
	var own := [Rede.player_username, get_my_username()]
	var keys := []
	for candidate in [str(data.get("username", "")),
			Rede.opponent_username, get_opponent_username(),
			p1_username, p2_username]:
		var key := str(candidate)
		if key.is_empty() or own.has(key) or keys.has(key):
			continue
		keys.append(key)
	return keys


func _prune_private_envelopes() -> void:
	while _private_envelopes.size() > MAX_CACHED_STATES:
		var oldest := 2147483647
		for key in _private_envelopes:
			oldest = min(oldest, int(key))
		_private_envelopes.erase(oldest)


func _on_mp_private_request(data: Dictionary) -> void:
	if str(data.get("game_id", game_id)) != game_id:
		return
	var seq := int(data.get("sequence", sequence))
	if seq == sequence:
		_send_private_envelope(seq)
		return
	var envelopes = _private_envelopes.get(seq, {})
	if typeof(envelopes) == TYPE_DICTIONARY \
			and envelopes.has(Rede.player_username):
		Rede.send_message({
			"t": "mp_private",
			"game_id": game_id,
			"sequence": seq,
			"envelope": str(envelopes[Rede.player_username]),
		})


func _try_save_checkpoint(seq: int) -> void:
	if _saved_sequences.has(seq):
		return
	var public_state = _public_states.get(seq)
	var envelopes = _private_envelopes.get(seq)
	if typeof(public_state) != TYPE_DICTIONARY \
			or typeof(envelopes) != TYPE_DICTIONARY:
		return
	if not envelopes.has(p1_username) or not envelopes.has(p2_username):
		return
	# The opponent count in the public state may still be one snapshot old when
	# the private envelope arrives. The envelopes are authoritative.
	var save_state: Dictionary = public_state.duplicate(true)
	var hidden = save_state.get("hidden", {})
	if typeof(hidden) != TYPE_DICTIONARY:
		hidden = {}
	for slot in [1, 2]:
		var username := p1_username if slot == 1 else p2_username
		var payload := CheckpointStore.unprotect_payload(
				str(envelopes[username]), username)
		if payload.is_empty():
			return
		var hand = payload.get("hand", [])
		var deck = payload.get("deck", [])
		if typeof(hand) != TYPE_ARRAY or typeof(deck) != TYPE_ARRAY:
			return
		hidden[str(slot)] = {"hand": hand.size(), "deck": deck.size()}
	save_state["hidden"] = hidden
	var result := CheckpointStore.save_checkpoint(
			game_id,
			seq,
			int(save_state.get("round", 1)),
			int(save_state.get("step", 0)),
			int(save_state.get("starting_slot", 1)),
			save_state.get("rolls", []),
			p1_username,
			p2_username,
			save_state,
			{
				p1_username: str(envelopes[p1_username]),
				p2_username: str(envelopes[p2_username]),
			})
	if result.get("ok", false):
		_saved_sequences[seq] = true
		_log("Checkpoint " + str(seq) + " salvo.")
		emit_signal("checkpoint_saved", seq, str(result.get("path", "")))
	else:
		_log("Checkpoint " + str(seq) + " não foi salvo: "
				+ str(result.get("reason", "erro desconhecido")))
		emit_signal("checkpoint_error", str(result.get("reason", "")))


# Manual save from the match menu. Both peers already exchange the private
# envelopes of every sequence, so the current checkpoint can be written again
# on demand without any extra network round.
func save_current_game() -> Dictionary:
	if mode == Mode.SOLO:
		return {"ok": false,
				"message": "A partida solo não salva checkpoints."}
	if sequence < 0 or not _public_states.has(sequence):
		return {"ok": false,
				"message": "Ainda não há estado da partida para salvar."}
	var already_saved := _saved_sequences.has(sequence)
	_saved_sequences.erase(sequence)
	_try_save_checkpoint(sequence)
	if _saved_sequences.has(sequence):
		return {"ok": true, "message": "Jogo salvo: " + get_save_label() \
				+ " · ponto #" + str(sequence) + "."}
	if already_saved:
		return {"ok": true, "message": "O jogo já está salvo no ponto #" \
				+ str(sequence) + "."}
	return {"ok": false,
			"message": "Não foi possível salvar: aguardando dados do oponente."}


func get_save_label() -> String:
	if p1_username.is_empty() or p2_username.is_empty():
		return "partida"
	return p1_username + " vs " + p2_username


#-----------------------------------------------------------------------------
# Resume / live resync negotiation
#-----------------------------------------------------------------------------

func _begin_resume_negotiation(live: bool) -> void:
	_resume_live = live
	_resume_peer_manifests = []
	_resume_peer_manifest_received = false
	_resume_peer_checkpoint = {}
	_resume_waiting_ack = false
	_restore_pending = {}
	_restore_scheduled = false
	state = State.WAITING
	_update_pause()
	emit_signal("resume_status", "Comparando checkpoints locais...")
	emit_signal("waiting_changed", true,
			"Comparando checkpoints entre os jogadores...")
	var manifests := CheckpointStore.manifests_for_game(game_id)
	Rede.send_message({
		"t": "mp_resume_manifest",
		"live": 1 if live else 0,
		"game_id": game_id,
		"username": Rede.player_username,
		"manifests": manifests,
	})
	emit_signal("session_changed")


func _on_mp_resume_manifest(data: Dictionary) -> void:
	if str(data.get("game_id", game_id)) != game_id:
		return
	if str(data.get("username", "")) != Rede.opponent_username:
		return
	var manifests = data.get("manifests", [])
	if typeof(manifests) != TYPE_ARRAY:
		return
	_resume_peer_manifests = _sanitize_manifests(manifests)
	_resume_peer_manifest_received = true
	if is_authority():
		_decide_resume()
	else:
		emit_signal("resume_status",
				"Checkpoints recebidos. Aguardando o anfitrião decidir.")


func _sanitize_manifests(manifests: Array) -> Array:
	var result := []
	for manifest in manifests:
		if typeof(manifest) != TYPE_DICTIONARY:
			continue
		var seq := int(manifest.get("sequence", -1))
		var checksum := str(manifest.get("checksum", ""))
		if seq < 0 or checksum.is_empty():
			continue
		result.append({"sequence": seq, "checksum": checksum})
	result.sort_custom(Callable(self, "_sort_manifest_desc"))
	return result


func _sort_manifest_desc(a: Dictionary, b: Dictionary) -> bool:
	return int(a["sequence"]) > int(b["sequence"])


func _decide_resume() -> void:
	if not is_authority() or not _resume_peer_manifest_received:
		return
	var mine := CheckpointStore.manifests_for_game(game_id)
	var theirs := _resume_peer_manifests
	var common := _find_common_manifest(mine, theirs)
	if not common.is_empty():
		var loaded := CheckpointStore.load_checkpoint(
				game_id, int(common["sequence"]))
		if loaded.get("ok", false):
			_send_resume_plan({
				"t": "mp_resume_plan",
				"game_id": game_id,
				"action": "load",
				"sequence": int(common["sequence"]),
				"checksum": str(common["checksum"]),
			})
			_apply_resume_data(loaded["data"])
			return
		_resume_waiting_ack = true
		_send_resume_plan({
			"t": "mp_resume_plan",
			"game_id": game_id,
			"action": "send_peer",
			"sequence": int(common["sequence"]),
			"checksum": str(common["checksum"]),
		})
		emit_signal("resume_status", "Cópia local corrompida; recuperando do oponente...")
		return
	if not mine.is_empty() and theirs.is_empty():
		var latest: Dictionary = mine[0]
		var loaded := CheckpointStore.load_checkpoint(
				game_id, int(latest["sequence"]))
		if loaded.get("ok", false):
			_send_resume_plan({
				"t": "mp_resume_plan",
				"game_id": game_id,
				"action": "use_host",
				"sequence": int(latest["sequence"]),
				"checkpoint": loaded["data"],
			})
			_apply_resume_data(loaded["data"])
			return
		_abort_resume("O checkpoint local está corrompido e o oponente não tem cópia.")
		return
	if mine.is_empty() and not theirs.is_empty():
		_resume_waiting_ack = true
		_send_resume_plan({
			"t": "mp_resume_plan",
			"game_id": game_id,
			"action": "send_peer",
			"sequence": int(theirs[0]["sequence"]),
			"checksum": str(theirs[0]["checksum"]),
		})
		emit_signal("resume_status", "Recebendo o checkpoint íntegro do oponente...")
		return
	if mine.is_empty() and theirs.is_empty():
		_abort_resume("Nenhum checkpoint íntegro foi encontrado. Não é possível retomar este jogo.")
		return
	_abort_resume("Os saves não têm um checkpoint em comum. Não é possível retomar automaticamente.")


func _find_common_manifest(mine: Array, theirs: Array) -> Dictionary:
	var their_checksums := {}
	for manifest in theirs:
		their_checksums[int(manifest["sequence"])] = str(manifest["checksum"])
	var best := {}
	for manifest in mine:
		var seq := int(manifest["sequence"])
		if their_checksums.get(seq, "") == str(manifest["checksum"]):
			if best.is_empty() or seq > int(best["sequence"]):
				best = manifest
	return best


func _send_resume_plan(plan: Dictionary) -> void:
	Rede.send_message(plan)


func _on_mp_resume_plan(data: Dictionary) -> void:
	if is_authority():
		if str(data.get("action", "")) == "request_host":
			_send_resume_copy_to_guest(data)
		return
	if str(data.get("game_id", game_id)) != game_id:
		return
	var action := str(data.get("action", ""))
	match action:
		"load":
			var loaded := CheckpointStore.load_checkpoint(
					game_id, int(data.get("sequence", -1)))
			if not loaded.get("ok", false):
				emit_signal("resume_status",
						"Sua cópia local está corrompida; pedindo a cópia do anfitrião...")
				Rede.send_message({
					"t": "mp_resume_plan",
					"game_id": game_id,
					"action": "request_host",
					"sequence": int(data.get("sequence", -1)),
				})
				return
			_apply_resume_data(loaded["data"])
			Rede.send_message({"t": "mp_resume_ready", "game_id": game_id})
		"use_host":
			var checkpoint = data.get("checkpoint", {})
			if typeof(checkpoint) != TYPE_DICTIONARY:
				_abort_resume("O checkpoint enviado pelo anfitrião é inválido.")
				return
			var validation := CheckpointStore.validate_checkpoint(checkpoint)
			if not validation.get("ok", false):
				_abort_resume(str(validation.get("reason", "Checkpoint inválido.")))
				return
			_apply_resume_data(checkpoint)
			Rede.send_message({"t": "mp_resume_ready", "game_id": game_id})
		"send_peer":
			var loaded := CheckpointStore.load_checkpoint(
					game_id, int(data.get("sequence", -1)))
			if not loaded.get("ok", false):
				_abort_resume("Seu checkpoint local está corrompido e não pôde ser enviado.")
				return
			_resume_waiting_ack = true
			Rede.send_message({
				"t": "mp_resume_checkpoint",
				"game_id": game_id,
				"sequence": int(loaded["data"].get("sequence", -1)),
				"checkpoint": loaded["data"],
			})
			_apply_resume_data(loaded["data"])
			emit_signal("resume_status", "Checkpoint enviado. Aguardando confirmação...")
		"abort":
			_fail_resume(str(data.get("message", "Não foi possível retomar o jogo.")))


func _on_mp_resume_checkpoint(data: Dictionary) -> void:
	if not is_authority():
		return
	if str(data.get("game_id", game_id)) != game_id:
		return
	var checkpoint = data.get("checkpoint", {})
	if typeof(checkpoint) != TYPE_DICTIONARY:
		_abort_resume("O checkpoint recebido é inválido.")
		return
	var validation := CheckpointStore.validate_checkpoint(checkpoint)
	if not validation.get("ok", false):
		_abort_resume(str(validation.get("reason", "Checkpoint inválido.")))
		return
	_apply_resume_data(checkpoint)
	Rede.send_message({"t": "mp_resume_ready", "game_id": game_id})


func _on_mp_resume_ready(data: Dictionary) -> void:
	if str(data.get("game_id", game_id)) != game_id:
		return
	# Both sides apply the chosen checkpoint locally before acknowledging.
	_resume_waiting_ack = false
	_resume_peer_checkpoint = {}


func _send_resume_copy_to_guest(request: Dictionary) -> void:
	if not is_authority() or str(request.get("game_id", game_id)) != game_id:
		return
	var seq := int(request.get("sequence", -1))
	var loaded := CheckpointStore.load_checkpoint(game_id, seq)
	if not loaded.get("ok", false):
		_abort_resume("Nenhuma cópia íntegra do checkpoint está disponível.")
		return
	_send_resume_plan({
		"t": "mp_resume_plan",
		"game_id": game_id,
		"action": "use_host",
		"sequence": seq,
		"checkpoint": loaded["data"],
	})
	if state != State.PLAYING and _restore_pending.is_empty():
		_apply_resume_data(loaded["data"])


func _abort_resume(message: String) -> void:
	if is_authority():
		_send_resume_plan({
			"t": "mp_resume_plan",
			"game_id": game_id,
			"action": "abort",
			"message": message,
		})
	_fail_resume(message)


func _fail_resume(message: String) -> void:
	_resume_waiting_ack = false
	_restore_pending = {}
	_restore_scheduled = false
	state = State.ENDED
	ended_message = message
	last_error = message
	_update_pause()
	emit_signal("resume_finished", false, message)
	emit_signal("session_ended", message)
	emit_signal("session_changed")


func _apply_resume_data(checkpoint: Dictionary) -> void:
	if not _restore_pending.is_empty():
		return
	var validation := CheckpointStore.validate_checkpoint(checkpoint)
	if not validation.get("ok", false):
		_abort_resume(str(validation.get("reason", "Checkpoint inválido.")))
		return
	if not str(checkpoint.get("game_id", "")) == game_id:
		_abort_resume("O checkpoint pertence a outra partida.")
		return
	var checkpoint_p1 := str(checkpoint.get("p1", ""))
	var checkpoint_p2 := str(checkpoint.get("p2", ""))
	var my_name := Rede.player_username
	if not my_name in [checkpoint_p1, checkpoint_p2]:
		_abort_resume("Este checkpoint não inclui o seu username.")
		return
	if mode == Mode.RESUME and not _resume_expected_participants.is_empty():
		if not checkpoint_p1 in _resume_expected_participants \
				or not checkpoint_p2 in _resume_expected_participants:
			_abort_resume("Este checkpoint não corresponde aos jogadores da sala.")
			return
	p1_username = checkpoint_p1
	p2_username = checkpoint_p2
	my_slot = 1 if my_name == checkpoint_p1 else 2
	opponent_slot = 3 - my_slot
	_restore_pending = checkpoint.duplicate(true)
	_restore_live = _resume_live
	state = State.WAITING
	_update_pause()
	if _board and is_instance_valid(_board) and _sync:
		if _restore_live:
			_restore_scheduled = true
			emit_signal("resume_status", "Checkpoint comum encontrado. Recarregando a partida...")
			call_deferred("_reload_for_restore")
		else:
			_apply_pending_restore()
	else:
		waiting_message = "Montando o tabuleiro a partir do checkpoint..."
		emit_signal("waiting_changed", true, waiting_message)
		emit_signal("resume_status", "Checkpoint comum encontrado. Montando o tabuleiro...")
		emit_signal("session_changed")


func _reload_for_restore() -> void:
	var tree := get_tree()
	if tree:
		# warning-ignore:return_value_discarded
		tree.reload_current_scene()


func _apply_pending_restore() -> void:
	if _restore_pending.is_empty() or not _board or not _sync:
		return
	var checkpoint: Dictionary = _restore_pending
	var validation := CheckpointStore.validate_checkpoint(checkpoint)
	if not validation.get("ok", false):
		_restore_pending = {}
		_fail_resume(str(validation.get("reason", "Checkpoint inválido.")))
		return
	var public_state = checkpoint.get("public", {})
	var payload := CheckpointStore.get_private_payload(
			checkpoint, Rede.player_username)
	if payload.is_empty():
		_restore_pending = {}
		_fail_resume("Seus dados privados no checkpoint não puderam ser abertos.")
		return
	_restore_pending = {}
	_restore_scheduled = false
	game_id = str(checkpoint.get("game_id", game_id))
	round_number = int(checkpoint.get("round", 1))
	step_index = int(checkpoint.get("step", 0))
	starting_slot = int(checkpoint.get("starting_slot", 1))
	phase = str(checkpoint.get("phase", phase_for_step(step_index)))
	sequence = int(checkpoint.get("sequence", -1))
	rolls = checkpoint.get("rolls", [])
	_saved_sequences[sequence] = true
	_initial_state_sent = true
	_start_applied = true
	# The resumed player lands inside the same window the match was standing in,
	# and remembers which automatic steps the table already paid.
	_absorb_turn_state(public_state)
	_merge_definitions(public_state.get("definitions", {}))
	_merge_definitions(payload.get("definitions", {}))
	var hidden = public_state.get("hidden", {})
	if typeof(hidden) == TYPE_DICTIONARY:
		var restored_counts = hidden.get(str(opponent_slot), {})
		if typeof(restored_counts) == TYPE_DICTIONARY:
			set_opponent_counts(restored_counts)
	if _sync.has_method("set_suppressed"):
		_sync.set_suppressed(true)
	GameEvents.suppressed = true
	_restore_own_hidden_cards(payload)
	if _sync.has_method("apply_public_snapshot"):
		_sync.apply_public_snapshot(public_state, opponent_slot)
	_restore_own_public_cards(public_state)
	GameEvents.suppressed = false
	if _sync.has_method("set_suppressed"):
		_sync.set_suppressed(false)
	if _sync.has_method("start_mirroring"):
		_sync.start_mirroring()
	state = State.PLAYING
	_set_resume_state_before_wait(State.PLAYING)
	_update_pause()
	if _sync.has_method("reconcile_scenarios"):
		_sync.reconcile_scenarios(public_state)
	emit_signal("waiting_changed", false, "")
	emit_signal("match_started")
	emit_signal("phase_changed")
	emit_signal("session_changed")
	emit_signal("resume_finished", true,
			"Partida retomada no checkpoint " + str(sequence) + ".")
	_log("Partida retomada: rodada " + str(round_number)
			+ ", fase " + phase + ".")


func _restore_own_hidden_cards(payload: Dictionary) -> void:
	var deck: Pile = cfc.NMAP.deck
	var hand: Hand = cfc.NMAP.hand
	var deck_entries = payload.get("deck", [])
	var hand_entries = payload.get("hand", [])
	if typeof(deck_entries) != TYPE_ARRAY or typeof(hand_entries) != TYPE_ARRAY:
		return
	# A seat can only be rebuilt while its own definitions are still registered,
	# which is not the case after a set changes between sessions.
	var definitions = payload.get("definitions", {})
	if typeof(definitions) == TYPE_DICTIONARY:
		for card_name in definitions:
			if typeof(definitions[card_name]) == TYPE_DICTIONARY \
					and not definitions[card_name].is_empty():
				cfc.card_definitions[str(card_name)] = definitions[card_name]
	for entry in deck_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var card = _instance_restored_card(str(entry.get("name", "")))
		if not card:
			continue
		card.network_id = str(entry.get("id", ""))
		deck.add_child(card)
		card.set_is_faceup(false, true)
		card.set_state(Card.CardState.IN_PILE)
	for entry in hand_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var card = _instance_restored_card(str(entry.get("name", "")))
		if not card:
			continue
		card.network_id = str(entry.get("id", ""))
		hand.add_child(card)
		card.set_is_faceup(true, true)
		card.set_state(Card.CardState.IN_HAND)
		card.position = card.recalculate_position()
	deck.reorganize_stack()
	hand.call_deferred("re_place")


func _restore_own_public_cards(public_state: Dictionary) -> void:
	var cards = public_state.get("cards", [])
	if typeof(cards) != TYPE_ARRAY:
		return
	var by_id := {}
	var pending_attachments := []
	for entry in cards:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("owner", 0)) != my_slot:
			continue
		var zone := str(entry.get("zone", "board"))
		if zone in ["hand", "deck"]:
			continue
		var card = _instance_restored_card(str(entry.get("name", "")))
		if not card:
			continue
		var net_id := str(entry.get("id", ""))
		card.network_id = net_id
		by_id[net_id] = card
		match zone:
			"resources":
				var discard: Pile = cfc.NMAP.discard
				discard.add_child(card)
				card.set_is_faceup(true, true)
				card.set_state(Card.CardState.IN_PILE)
			"prizes":
				var prizes: Pile = _prizes_pile()
				if prizes:
					prizes.add_child(card)
					card.set_is_faceup(true, true)
					card.set_state(Card.CardState.IN_PILE)
			_:
				_board.add_child(card)
				card.set_is_faceup(int(entry.get("face", 1)) == 1, true)
				card.scale = Vector2(1, 1) * card.play_area_scale
				var slot: BoardPlacementSlot = null
				if zone == "scenario":
					slot = _scenario_placement_slot()
				elif zone == "board":
					slot = _scene_placement_slot(int(entry.get("slot", -1)))
				if slot:
					card.global_position = slot.global_position
					card._placement_slot = slot
					slot.occupying_card = card
				else:
					card.global_position = _denormalize_board_position(
							Vector2(float(entry.get("x", 0.5)),
									float(entry.get("y", 0.5))))
				card.set_state(Card.CardState.ON_PLAY_BOARD)
				card.set_card_rotation(
						int(entry.get("rot", 0)), false, true, false)
		var host_id := str(entry.get("host", ""))
		if not host_id.is_empty():
			pending_attachments.append({
				"card": card,
				"host": host_id,
				"offset": int(entry.get("offset", -1)),
			})
	if cfc.NMAP.has("discard"):
		cfc.NMAP.discard.reorganize_stack()
	var prizes: Pile = _prizes_pile()
	if prizes:
		prizes.reorganize_stack()
	for attachment in pending_attachments:
		var host = by_id.get(attachment["host"])
		if not host and _sync and _sync.has_method("find_remote_card"):
			host = _sync.find_remote_card(attachment["host"])
		if host and is_instance_valid(host) \
				and is_instance_valid(attachment["card"]):
			attachment["card"].attachment_mode = \
					Card.AttachmentMode.ATTACH_BEHIND
			var offset := int(attachment.get("offset", -1))
			attachment["card"].attachment_offset = \
					offset if offset >= 0 \
					else Card.AttachmentOffset.BATTLE_SCENES_BOTTOM
			attachment["card"].attach_to_host(host, false, ["net"])
			# The snapshot lists the resources before the character, so the
			# restored cards are not in drop order and the plain organize is
			# not enough: rebuild the pile with the host on top.
			host.arrange_attachment_stack()
	if not _sync or not _sync.has_method("find_remote_card"):
		return
	# Opponent attachments were mirrored before the local hosts existed, so their
	# host links have to be resolved again now that the local cards are restored.
	for entry in cards:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("owner", 0)) != opponent_slot:
			continue
		var host_id := str(entry.get("host", ""))
		if host_id.is_empty():
			continue
		var card = _sync.find_remote_card(str(entry.get("id", "")))
		if not card:
			continue
		var host = by_id.get(host_id)
		if not host:
			host = _sync.find_remote_card(host_id)
		if not host or host == card or card.current_host_card == host:
			continue
		card.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
		var offset := int(entry.get("offset", -1))
		card.attachment_offset = offset if offset >= 0 \
				else Card.AttachmentOffset.BATTLE_SCENES_BOTTOM
		card.attach_to_host(host, false, ["net"])
		host.arrange_attachment_stack()


func _instance_restored_card(card_name: String) -> Card:
	if card_name.is_empty():
		push_warning("Carta restaurada sem nome; assento pode ficar incompleto.")
		return null
	if not cfc.card_definitions.has(card_name):
		push_warning("Carta restaurada fora das definições: '" + card_name + "'")
		return null
	return cfc.instance_card(card_name)


func _prizes_pile() -> Pile:
	if not cfc.NMAP.has("board"):
		return null
	return cfc.NMAP.board.get_node_or_null("Prêmios") as Pile


func _scenario_placement_slot() -> BoardPlacementSlot:
	var grid: BoardPlacementGrid = _board.get_node_or_null("ModifiedLabelGrid")
	if not grid or grid.get_slot_count() == 0:
		return null
	var slot: BoardPlacementSlot = grid.get_slot(0)
	if slot.occupying_card:
		return null
	return slot


# A restored scene card only takes its slot back while the slot is still free,
# so two entries can never end up sharing the same spot.
func _scene_placement_slot(index: int) -> BoardPlacementSlot:
	if index < 0:
		return null
	var grid: BoardPlacementGrid = _board.get_node_or_null("PlacementGridDemo")
	if not grid or index >= grid.get_slot_count():
		return null
	var slot: BoardPlacementSlot = grid.get_slot(index)
	if slot.occupying_card:
		return null
	return slot


func _denormalize_board_position(normalized: Vector2) -> Vector2:
	var grid: Control = _board.get_node_or_null("PlacementGridDemo")
	if not grid:
		return normalized * _board.size
	return grid.global_position + Vector2(
			normalized.x * grid.size.x,
			normalized.y * grid.size.y)


#-----------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------

func _count_deck_cards(deck: Dictionary) -> int:
	var cards = deck.get("cards", {})
	if typeof(cards) != TYPE_DICTIONARY:
		return 0
	var count := 0
	for card_name in cards:
		count += int(cards[card_name])
	return count


func _merge_definitions(definitions) -> void:
	if typeof(definitions) != TYPE_DICTIONARY:
		return
	for card_name in definitions:
		if typeof(definitions[card_name]) == TYPE_DICTIONARY:
			cfc.card_definitions[str(card_name)] = definitions[card_name]


func _set_resume_state_before_wait(value: int) -> void:
	_resume_state_before_wait = value


func _update_pause() -> void:
	if not is_inside_tree():
		return
	cfc.game_paused = state in [State.STARTING, State.WAITING, State.ENDED]


func _abort_match(message: String) -> void:
	if Rede.is_connected and not game_id.is_empty():
		Rede.send_message({
			"t": "mp_abort",
			"game_id": game_id,
			"message": message,
		})
	_end_session(message)


func _end_session(message: String) -> void:
	if state == State.ENDED:
		return
	_stop_reconnect_retries()
	state = State.ENDED
	ended_message = message
	last_error = message
	_update_pause()
	emit_signal("session_ended", message)
	emit_signal("session_changed")


func _clear_session_fields() -> void:
	game_id = ""
	p1_username = ""
	p2_username = ""
	my_slot = 0
	opponent_slot = 0
	local_deck = {}
	local_deck_name = ""
	local_deck_count = 0
	opponent_deck_name = ""
	opponent_deck_count = 0
	opponent_deck_ready = false
	rolls = []
	starting_slot = 0
	round_number = 1
	step_index = 0
	phase = ""
	sequence = -1
	_mulligan_open = false
	_mulligan_local_choice = false
	_mulligan_counts = {}
	_mulligan_accepts = {}
	_prep_game_open = false
	_prep_game_local_choice = false
	_prep_game_accepts = {}
	_adjustment_open = false
	_adjustment_operations = []
	_auto_turn_active = false
	_auto_advance_pending = false
	_auto_turn_resources = 0
	_auto_turn_draws = 0
	_effects_applied = {}
	waiting_message = ""
	ended_message = ""
	last_error = ""
	# Toda sessao nova comeca sem janela de reconexao; quem abre a janela e a
	# queda da conexao, em _on_connection_lost.
	_stop_reconnect_retries()
	opponent_counts = {"hand": 0, "deck": 0}
	_start_applied = false
	_start_payload = {}
	_initial_state_sent = false
	_opponent_board_counts_received = false
	_public_states = {}
	_private_envelopes = {}
	_saved_sequences = {}
	_restore_pending = {}
	_restore_live = false
	_restore_scheduled = false
	_resume_live = false
	_resume_peer_manifests = []
	_resume_peer_manifest_received = false
	_resume_peer_checkpoint = {}
	_resume_waiting_ack = false
	_resume_expected_participants = []
	_resume_state_before_wait = State.IDLE
	_waiting_reason = ""
	_id_counter = 0
	_id_prefix = ""
	local_display = {}
	opponent_display = {}
	_display_checked = false
	solo_pick_slot = 1
	solo_decks = {}
	_solo_hidden = {}


func _store_opponent_display(data: Dictionary) -> void:
	var display = data.get("display", {})
	if typeof(display) != TYPE_DICTIONARY or display.is_empty():
		return
	opponent_display = display
	_check_display_mismatch()
	emit_signal("display_changed")


func _check_display_mismatch() -> void:
	if _display_checked:
		return
	var local_ratio := _aspect_ratio(get_display_info())
	var remote_ratio := _aspect_ratio(opponent_display)
	if local_ratio <= 0.0 or remote_ratio <= 0.0:
		return
	_display_checked = true
	if abs(local_ratio - remote_ratio) > 0.02:
		_log("Proporções de tela diferentes (%.2f vs %.2f). " % [
			local_ratio, remote_ratio]
			+ "O jogo mantém 16:9 e adiciona barras.")


func _format_display(display: Dictionary) -> String:
	if display.is_empty():
		return "—"
	var screen := _size_text(display.get("screen", []))
	var window := _size_text(display.get("window", []))
	var logical := _size_text(display.get("viewport", []))
	var text := "tela " + screen
	if window != screen:
		text += " · janela " + window
	text += " · lógico " + logical
	return text


func _size_text(value) -> String:
	if typeof(value) != TYPE_ARRAY or value.size() < 2:
		return "?"
	return str(int(value[0])) + "x" + str(int(value[1]))


func _aspect_ratio(display: Dictionary) -> float:
	var size_value = display.get("screen", [])
	if typeof(size_value) != TYPE_ARRAY or size_value.size() < 2:
		size_value = display.get("window", [])
	if typeof(size_value) != TYPE_ARRAY or size_value.size() < 2:
		return 0.0
	var height := float(size_value[1])
	if height <= 0.0:
		return 0.0
	return float(size_value[0]) / height


func _log(message: String) -> void:
	emit_signal("action_logged", message)


# A decision line belongs to both logs: the table must not tell two stories
# about the mulligan and the preparation, which each seat sees in its own HUD.
func _log_shared(message: String) -> void:
	_log(message)
	if is_solo():
		return
	Rede.send_message({"t": "mp_log", "game_id": game_id, "text": message})


func _on_mp_log(data: Dictionary) -> void:
	if str(data.get("game_id", game_id)) != game_id:
		return
	var text := str(data.get("text", ""))
	if text.is_empty():
		return
	_log(text)
