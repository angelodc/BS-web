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

const CheckpointStore = preload("res://src/custom/CheckpointStore.gd")

enum State { IDLE, PREPARING, STARTING, PLAYING, WAITING, ENDED }
enum Mode { NONE, MATCH, RESUME }

const DECK_SIZE := 60
const START_HAND_SIZE := 10
const MAX_CACHED_STATES := 24

const PHASES := [
	"REG", "PREP", "ADJ", "ANT", "ATK",
	"REG", "PREP", "ADJ", "ANT", "ATK",
]
const PHASE_LABELS := {
	"REG": "Contagem Regressiva",
	"PREP": "Preparação",
	"ADJ": "Ajuste",
	"ANT": "Antecipação",
	"ATK": "Ataque",
}
const PHASE_COLORS := {
	"REG": Color(0.62, 0.78, 1.0),
	"PREP": Color(1, 1, 1),
	"ADJ": Color(0.72, 0.72, 0.72),
	"ANT": Color(1.0, 0.38, 0.38),
	"ATK": Color(0.42, 1.0, 0.5),
}
const VALID_ZONES := [
	"board", "scenario", "hand", "deck", "resources", "prizes",
]

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
var waiting_message := ""
var ended_message := ""
var last_error := ""
var opponent_counts := {"hand": 0, "deck": 0}
var local_display := {}
var opponent_display := {}

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
var _clearing := false
var _display_checked := false


func _ready() -> void:
	# warning-ignore:return_value_discarded
	Rede.connect("match_found", self, "_on_rede_match_found")
	# warning-ignore:return_value_discarded
	Rede.connect("message_received", self, "_on_network_message")
	# warning-ignore:return_value_discarded
	Rede.connect("opponent_lost", self, "_on_opponent_lost")
	# warning-ignore:return_value_discarded
	Rede.connect("opponent_reconnected", self, "_on_opponent_reconnected")
	# warning-ignore:return_value_discarded
	Rede.connect("opponent_left", self, "_on_opponent_left")
	# warning-ignore:return_value_discarded
	Rede.connect("connection_lost", self, "_on_connection_lost")
	# warning-ignore:return_value_discarded
	Rede.connect("room_expired", self, "_on_room_expired")
	# warning-ignore:return_value_discarded
	Rede.connect("status_changed", self, "_on_rede_status_changed")
	# warning-ignore:return_value_discarded
	Rede.connect("rejoined", self, "_on_rejoined")
	# warning-ignore:return_value_discarded
	Rede.connect("join_failed", self, "_on_join_failed")


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


func is_authority() -> bool:
	return Rede.is_host() and state != State.IDLE


func is_frozen() -> bool:
	return state in [State.STARTING, State.WAITING, State.ENDED]


func get_my_username() -> String:
	return Rede.player_username


func get_opponent_username() -> String:
	return Rede.opponent_username


func get_slot_username(slot: int) -> String:
	if slot == 1:
		return p1_username
	if slot == 2:
		return p2_username
	return ""


func get_actor_slot() -> int:
	if starting_slot == 0:
		return 0
	var relative := [0, 0, 0, 1, 0, 1, 1, 1, 0, 1]
	if step_index < 0 or step_index >= relative.size():
		return starting_slot
	if int(relative[step_index]) == 0:
		return starting_slot
	return 3 - starting_slot


func get_actor_username() -> String:
	return get_slot_username(get_actor_slot())


func is_my_phase() -> bool:
	return state == State.PLAYING and get_actor_slot() == my_slot


func get_phase_label() -> String:
	return str(PHASE_LABELS.get(phase, phase))


func get_phase_color() -> Color:
	return PHASE_COLORS.get(phase, Color(0.85, 0.85, 0.85))


func are_both_decks_ready() -> bool:
	return local_deck_count == DECK_SIZE and opponent_deck_ready


func is_local_deck_ready() -> bool:
	return local_deck_count == DECK_SIZE


func get_deck_summary() -> String:
	var mine := str(local_deck_count) + "/" + str(DECK_SIZE)
	var theirs := str(opponent_deck_count) + "/" + str(DECK_SIZE)
	if opponent_deck_count == 0 and opponent_deck_name.empty():
		theirs = "aguardando"
	elif opponent_deck_ready:
		theirs += " pronto"
	return "Seu deck: " + mine + " · Oponente: " + theirs


func get_rolls_text() -> String:
	if rolls.size() != 2:
		return ""
	return str(rolls[0]) + " x " + str(rolls[1])


func get_display_info() -> Dictionary:
	var viewport_size := Vector2(1280, 720)
	var board_size := Vector2.ZERO
	if is_instance_valid(_board):
		viewport_size = _board.get_viewport().get_visible_rect().size
		board_size = _board.rect_size
	var screen_size := OS.get_screen_size()
	return {
		"screen": [int(screen_size.x), int(screen_size.y)],
		"window": [int(OS.window_size.x), int(OS.window_size.y)],
		"viewport": [int(viewport_size.x), int(viewport_size.y)],
		"board": [int(board_size.x), int(board_size.y)],
		"stretch": str(ProjectSettings.get_setting(
				"display/window/stretch/mode")),
		"aspect": str(ProjectSettings.get_setting(
				"display/window/stretch/aspect")),
		"fullscreen": OS.window_fullscreen,
	}


func get_display_summary() -> String:
	var lines := ["Você: " + _format_display(get_display_info())]
	if opponent_display.empty():
		lines.append("Oponente: aguardando resolução")
	else:
		lines.append("Oponente: " + _format_display(opponent_display))
	return PoolStringArray(lines).join("\n")


#-----------------------------------------------------------------------------
# Board registration and user actions
#-----------------------------------------------------------------------------

func register_board(board: Control, hud: Control, sync_node: Control) -> void:
	_board = board
	_hud = hud
	_sync = sync_node
	if not _restore_pending.empty():
		_apply_pending_restore()
	elif not _start_payload.empty() and not _start_applied:
		_apply_start(_start_payload)


func select_deck(deck: Dictionary) -> Dictionary:
	if state != State.PREPARING:
		return {"ok": false, "reason": "A partida não está em preparação."}
	var count := _count_deck_cards(deck)
	local_deck = deck
	local_deck_name = str(deck.get("name", "Deck"))
	local_deck_count = count
	_merge_definitions(deck.get("definitions", {}))
	emit_signal("prep_changed")
	_send_prep()
	_log("Deck selecionado: " + local_deck_name + " (" + str(count) + "/60).")
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
	if get_actor_slot() != my_slot:
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
	if Rede.room_id.empty():
		return false
	return Rede.reconnect_room(Rede.last_address, Rede.player_username)


func can_manual_reconnect() -> bool:
	return state == State.WAITING and _waiting_reason == "local" \
			and not Rede.room_id.empty()


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
	if not message.empty():
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
	if cleaned.empty():
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
	if cleaned.empty():
		return {"ok": false, "reason": "Digite seu username."}
	if room_code.strip_edges().empty():
		return {"ok": false, "reason": "Informe o codigo da sala."}
	reset_session()
	mode = Mode.MATCH
	if not Rede.join_room(address, cleaned, room_code):
		mode = Mode.NONE
		return {"ok": false, "reason": Rede.get_status()}
	return {"ok": true, "reason": ""}


func begin_resume(
		address: String,
		username: String,
		checkpoint_game_id: String,
		participants: Array,
		as_host: bool) -> Dictionary:
	var cleaned := username.strip_edges()
	if cleaned.empty():
		return {"ok": false, "reason": "Digite seu username."}
	if checkpoint_game_id.empty():
		return {"ok": false, "reason": "Este save não identifica a partida."}
	if as_host and participants.size() != 2:
		return {"ok": false, "reason": "Este save não identifica os dois jogadores."}
	if not participants.empty() and not cleaned in participants:
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
	if cleaned.empty():
		return {"ok": false, "reason": "O username não pode ficar vazio."}
	var old_username := str(cfc.game_settings.get("multiplayer_username", ""))
	if old_username != cleaned and not old_username.empty():
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
	if card.network_id.empty():
		if _id_prefix.empty():
			_id_prefix = (Rede.peer_tag if not Rede.peer_tag.empty() else "P") \
					+ str(OS.get_ticks_usec())
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
	if not kept_deck.empty():
		local_deck = kept_deck
		local_deck_name = kept_name
		local_deck_count = kept_count
	mode = Mode.RESUME if Rede.match_mode == "resume" else Mode.MATCH
	game_id = Rede.game_id
	_id_prefix = (Rede.peer_tag if not Rede.peer_tag.empty() else "P") \
			+ str(OS.get_ticks_usec())
	opponent_counts = {"hand": 0, "deck": 0}
	var my_name := Rede.player_username
	if mode == Mode.MATCH:
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
		"mp_board_ready":
			_on_mp_board_ready(data)
		"mp_phase_request":
			_on_mp_phase_request(data)
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
	_waiting_reason = "local"
	state = State.WAITING
	waiting_message = "Conexão perdida. Reconecte à sala ou encerre a partida."
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
		if is_authority() and not _start_payload.empty():
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
		if is_authority() and not _start_payload.empty():
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
			and Rede.room_id.empty():
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
		if is_authority() and not opponent_deck_name.empty():
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
	phase = PHASES[0]
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
	phase = str(data.get("phase", PHASES[0]))
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
	if local_deck.empty() or _count_deck_cards(local_deck) != DECK_SIZE:
		_abort_match("Seu deck não tem 60 cartas; não é possível iniciar.")
		return
	if not _build_local_start(seed_text):
		_abort_match("Não foi possível montar seu deck para a partida.")
		return
	_start_applied = true
	state = State.PLAYING
	_update_pause()
	if _sync.has_method("start_mirroring"):
		_sync.start_mirroring()
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
	for _i in range(START_HAND_SIZE):
		var card = deck.get_top_card()
		if not card:
			return false
		deck.remove_child(card)
		hand.add_child(card)
		card.set_is_faceup(true, true)
		card.set_state(Card.CardState.IN_HAND)
		card.position = card.recalculate_position()
		ensure_card_id(card)
	hand.re_place()
	hand.call_deferred("re_place")
	return true


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
	if step_index >= PHASES.size():
		step_index = 0
		round_number += 1
	phase = PHASES[step_index]
	_broadcast_public_state()


func _broadcast_public_state() -> void:
	if not is_authority() or not _board or not _sync:
		return
	sequence += 1
	var public_state := _build_public_state(sequence)
	_store_public_state(public_state)
	Rede.send_message({"t": "mp_state", "state": public_state})
	_send_private_envelope(sequence)
	emit_signal("phase_changed")
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
	var new_rolls = public_state.get("rolls", rolls)
	if typeof(new_rolls) == TYPE_ARRAY:
		rolls = [int(new_rolls[0]), int(new_rolls[1])] if new_rolls.size() == 2 else rolls
	_store_public_state(public_state)
	_send_private_envelope(sequence)
	emit_signal("phase_changed")
	emit_signal("session_changed")


func _validate_public_state(public_state: Dictionary) -> bool:
	if str(public_state.get("phase", "")) == "":
		return false
	if int(public_state.get("step", -1)) < 0 \
			or int(public_state.get("step", -1)) >= PHASES.size():
		return false
	if int(public_state.get("round", 0)) < 1:
		return false
	var slot := int(public_state.get("starting_slot", 0))
	if slot < 1 or slot > 2:
		return false
	var step := int(public_state.get("step", -1))
	if str(public_state.get("phase", "")) != str(PHASES[step]):
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
		"rolls": rolls,
		"hidden": hidden,
		"cards": cards,
		"definitions": definitions,
	}


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
			hand_entries.append({"id": card.network_id, "name": card.canonical_name})
			definitions[card.canonical_name] = \
					cfc.card_definitions.get(card.canonical_name, {})
	if cfc.NMAP.has("deck"):
		for card in _local_cards_in(cfc.NMAP.deck):
			ensure_card_id(card)
			deck_entries.append({"id": card.network_id, "name": card.canonical_name})
			definitions[card.canonical_name] = \
					cfc.card_definitions.get(card.canonical_name, {})
	return {
		"hand": hand_entries,
		"deck": deck_entries,
		"definitions": definitions,
	}


func _send_private_envelope(seq: int) -> void:
	if seq < 0 or Rede.player_username.empty():
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
	if seq < 0 or envelope.empty():
		return
	var payload := CheckpointStore.unprotect_payload(
			envelope, Rede.opponent_username)
	if payload.empty():
		_log("Dados privados do oponente não puderam ser verificados.")
		return
	if not _private_envelopes.has(seq):
		_private_envelopes[seq] = {}
	_private_envelopes[seq][Rede.opponent_username] = envelope
	_prune_private_envelopes()
	_try_save_checkpoint(seq)


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
		if payload.empty():
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
		if seq < 0 or checksum.empty():
			continue
		result.append({"sequence": seq, "checksum": checksum})
	result.sort_custom(self, "_sort_manifest_desc")
	return result


func _sort_manifest_desc(a: Dictionary, b: Dictionary) -> bool:
	return int(a["sequence"]) > int(b["sequence"])


func _decide_resume() -> void:
	if not is_authority() or not _resume_peer_manifest_received:
		return
	var mine := CheckpointStore.manifests_for_game(game_id)
	var theirs := _resume_peer_manifests
	var common := _find_common_manifest(mine, theirs)
	if not common.empty():
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
	if not mine.empty() and theirs.empty():
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
	if mine.empty() and not theirs.empty():
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
	if mine.empty() and theirs.empty():
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
			if best.empty() or seq > int(best["sequence"]):
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
	if state != State.PLAYING and _restore_pending.empty():
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
	if not _restore_pending.empty():
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
	if mode == Mode.RESUME and not _resume_expected_participants.empty():
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
	if _restore_pending.empty() or not _board or not _sync:
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
	if payload.empty():
		_restore_pending = {}
		_fail_resume("Seus dados privados no checkpoint não puderam ser abertos.")
		return
	_restore_pending = {}
	_restore_scheduled = false
	game_id = str(checkpoint.get("game_id", game_id))
	round_number = int(checkpoint.get("round", 1))
	step_index = int(checkpoint.get("step", 0))
	starting_slot = int(checkpoint.get("starting_slot", 1))
	phase = str(checkpoint.get("phase", PHASES[step_index]))
	sequence = int(checkpoint.get("sequence", -1))
	rolls = checkpoint.get("rolls", [])
	_saved_sequences[sequence] = true
	_initial_state_sent = true
	_start_applied = true
	_merge_definitions(public_state.get("definitions", {}))
	_merge_definitions(payload.get("definitions", {}))
	var hidden = public_state.get("hidden", {})
	if typeof(hidden) == TYPE_DICTIONARY:
		var restored_counts = hidden.get(str(opponent_slot), {})
		if typeof(restored_counts) == TYPE_DICTIONARY:
			set_opponent_counts(restored_counts)
	if _sync.has_method("set_suppressed"):
		_sync.set_suppressed(true)
	_restore_own_hidden_cards(payload)
	if _sync.has_method("apply_public_snapshot"):
		_sync.apply_public_snapshot(public_state, opponent_slot)
	_restore_own_public_cards(public_state)
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
				if slot:
					card.global_position = slot.rect_global_position
					card._placement_slot = slot
					slot.occupying_card = card
				else:
					card.global_position = _denormalize_board_position(
							Vector2(float(entry.get("x", 0.5)),
									float(entry.get("y", 0.5))))
				card.set_state(Card.CardState.ON_PLAY_BOARD)
				card.set_card_rotation(
						int(entry.get("rot", 0)), false, false, false)
		var host_id := str(entry.get("host", ""))
		if not host_id.empty():
			pending_attachments.append({"card": card, "host": host_id})
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
			attachment["card"].attachment_offset = \
					Card.AttachmentOffset.BATTLE_SCENES_BOTTOM
			attachment["card"].attach_to_host(host, false, ["net"])
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
		if host_id.empty():
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
		card.attachment_offset = Card.AttachmentOffset.BATTLE_SCENES_BOTTOM
		card.attach_to_host(host, false, ["net"])


func _instance_restored_card(card_name: String) -> Card:
	if card_name.empty():
		return null
	if not cfc.card_definitions.has(card_name):
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


func _denormalize_board_position(normalized: Vector2) -> Vector2:
	var grid: Control = _board.get_node_or_null("PlacementGridDemo")
	if not grid:
		return normalized * _board.rect_size
	return grid.rect_global_position + Vector2(
			normalized.x * grid.rect_size.x,
			normalized.y * grid.rect_size.y)


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
	if Rede.is_connected and not game_id.empty():
		Rede.send_message({
			"t": "mp_abort",
			"game_id": game_id,
			"message": message,
		})
	_end_session(message)


func _end_session(message: String) -> void:
	if state == State.ENDED:
		return
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
	waiting_message = ""
	ended_message = ""
	last_error = ""
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


func _store_opponent_display(data: Dictionary) -> void:
	var display = data.get("display", {})
	if typeof(display) != TYPE_DICTIONARY or display.empty():
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
	if display.empty():
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
