# Applies table intents.
#
# One entry point — `apply()` — turns a verb into the same side effect the
# buttons, drag and keyboard already perform, validates it through
# `TableRules`, keeps `TableState` in sync with the scene and records a log
# entry that can be undone once. It is synchronous: animations and the
# coroutine parts of `move_to()` keep running on their own, but the parent and
# the slot change before `apply()` returns, so the state read back is the state
# the table has.
#
# Intent shape (all keys except `op` are optional depending on the verb):
#   {op, seat, card, to, host, quantity, amount, degree, from, to_slot, pile,
#    life}
#
# `card` and `host` accept a card id (the one in `TableSnapshot`) or a Card
# node; the node is resolved here so a script can use either.
class_name TableActions
extends RefCounted

const _Snapshot = preload("res://src/core/table/TableSnapshot.gd")
const _Rules = preload("res://src/core/table/TableRules.gd")
const _Table = preload("res://src/core/table/TableState.gd")
const _Renderer = preload("res://src/core/table/TableRenderer.gd")

# Actions whose effects cannot be reversed by looking at the before/after
# addresses: they remove cards from the table or change a global order.
const IRREVERSIBLE := [
	"ferir",
	"nocautear",
	"enviar_aos_prêmios",
	"passar_fase",
	"trocar_assento",
	"embaralhar",
]

const IRREVERSIBLE_REASONS := {
	"ferir": "O dano já consumiu recursos.",
	"nocautear": "A carta saiu da cena com os anexos.",
	"enviar_aos_prêmios": "A carta foi para os prêmios do oponente.",
	"passar_fase": "Passar a fase não pode ser desfeito.",
	"trocar_assento": "Trocar de assento não pode ser desfeito.",
	"embaralhar": "A ordem anterior se perdeu no embaralhamento.",
}

var board : Node
var state
var rules
# Complete history, newest last. Entries undone are kept with `undone = true`.
# The name avoids `log`, which is a built-in math function and cannot be a
# member variable in GDScript 3.
var history := []
var last_error := ""
# The network half of the prize send. The board is the default; a test points
# this at an object that records the send without a relay.
var prize_sink = null
# Optional MatchRecorder. Kept duck-typed so the core table does not depend on
# the custom folder, and null keeps every intent cheap when nothing is recorded.
var recorder = null

var _snapshot := {}
var _nodes := {}
var _seat := 1
var _seq := 0


func _init(table_board = null, seat := -1) -> void:
	board = table_board if is_instance_valid(table_board) \
			else cfc.NMAP.get("board", null)
	rules = _Rules.new()
	state = _Table.new()
	sync(seat)


# -----------------------------------------------------------------------------
# Context and state
# -----------------------------------------------------------------------------

# Rebuilds the state from the scene. `seat` also becomes the seat this object
# acts for; negative follows the controlled seat (which the hotseat swaps with
# "Controlar P1/P2") and falls back to the local seat.
func sync(seat := -1) -> void:
	if int(seat) > 0:
		_seat = int(seat)
	elif int(Multiplayer.my_slot) > 0:
		_seat = int(Multiplayer.my_slot)
	if _seat <= 0:
		_seat = 1
	_snapshot = _Snapshot.capture(board, _seat)
	state.load_snapshot(_snapshot)
	_nodes = _snapshot.get("nodes", {})


func get_seat() -> int:
	return _seat


# Makes the scene follow the addresses of the state: hand order, field slots and
# the shared scenario. Every applied intent and every undo ends here, so the
# table the player sees is the state that was validated.
func _render() -> void:
	_Renderer.reconcile(board, state, _seat)


func _context() -> Dictionary:
	var active := Multiplayer.is_session_active()
	return {
		"active": active,
		"solo": Multiplayer.is_solo(),
		"my_slot": _seat,
		"my_phase": Multiplayer.is_my_phase() if active else true,
		"setup_only_discard": Multiplayer.is_prep_game_open(),
		"enforce_cost": not cfc.ut,
		"undo_entry": last_undo_target(),
	}


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

# Validates and applies one intent. A failed intent changes nothing, including
# the log; the returned `error` and `message` say why.
func apply(raw_intent : Dictionary) -> Dictionary:
	# The UI keeps one runner across clicks and the table can change outside an
	# intent (payment popups, network sync, scripts), so the state is rebuilt
	# from the scene before validating.
	sync()
	var intent := _resolve(raw_intent)
	var decision = rules.validate(state, intent, _context())
	if not decision.get("ok", false):
		var failure := _failure(decision)
		_record(intent, failure)
		return failure
	var normalized: Dictionary = decision["intent"]
	if str(normalized["op"]) == "desfazer":
		var undone := _undo(normalized)
		_record(normalized, undone)
		return undone
	var card_id := str(normalized.get("card", ""))
	var card_name := str(state.cards.get(card_id, {}).get("name", ""))
	var host_name := ""
	if normalized.has("host"):
		host_name = str(state.cards.get(
				str(normalized["host"]), {}).get("name", ""))
	var before := _cards_snapshot()
	var outcome := _dispatch(normalized)
	if not outcome.get("ok", false):
		_record(normalized, outcome)
		return outcome
	sync()
	_render()
	var entry := _build_entry(normalized, before, card_id, card_name,
			host_name, outcome)
	history.append(entry)
	last_error = ""
	var result := {
		"ok": true,
		"error": "",
		"message": "",
		"entry": entry,
		"state": state,
	}
	_record(normalized, result)
	return result


# Validates without changing anything, for buttons that want to grey out and
# for scripts that check a sequence before running it.
func check(raw_intent : Dictionary) -> Dictionary:
	sync()
	var decision = rules.validate(state, _resolve(raw_intent), _context())
	if decision.get("ok", false):
		decision["state"] = state
	return decision


# The entry `desfazer` would target: the newest entry that is not undone yet.
func last_undo_target() -> Dictionary:
	for index in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[index]
		if bool(entry.get("undone", false)):
			continue
		return entry
	return {}


func can_undo() -> bool:
	var entry := last_undo_target()
	return not entry.is_empty() and bool(entry.get("undoable", false))


# Undoes the last action once and marks it as undone. A second call walks back
# to the previous action, skipping what was already undone.
func undo() -> Dictionary:
	return apply({"op": "desfazer", "seat": _seat})


func describe_log(limit := 0) -> String:
	var start := 0
	if int(limit) > 0:
		start = int(max(0, history.size() - int(limit)))
	var lines := []
	for index in range(start, history.size()):
		var entry: Dictionary = history[index]
		var line := "#" + str(entry.get("seq", index + 1)) + " " \
				+ str(entry.get("text", ""))
		if bool(entry.get("undone", false)):
			line = "[desfeito] " + line
		lines.append(line)
	return "\n".join(PackedStringArray(lines))


# -----------------------------------------------------------------------------
# Undo
# -----------------------------------------------------------------------------

func _undo(normalized : Dictionary) -> Dictionary:
	var target = normalized.get("entry", {})
	if not (target is Dictionary) or target.is_empty():
		return _failure({"error": "nada_para_desfazer",
				"message": "Não há ação para desfazer."})
	var outcome := _restore(target.get("undo", {}))
	if not outcome.get("ok", false):
		return outcome
	sync()
	_render()
	target["undone"] = true
	last_error = ""
	return {
		"ok": true,
		"error": "",
		"message": "",
		"entry": target,
		"state": state,
		"undone": true,
	}


func _restore(undo : Dictionary) -> Dictionary:
	var records: Array = undo.get("cards", [])
	if records.is_empty():
		return _ok_result()
	# Hosts first: an attachment address is only valid after the host is back.
	# Piles are restored from the bottom up so the recorded top card ends on
	# top again after the appends.
	var ordered := _sort_for_restore(records)
	for record in ordered:
		var id := str(record["card"])
		var address := str(record["address"])
		# Attribute-only records (flip, rotate, shield) keep the address; moving
		# them again would push a resource card back to the top of its pile.
		if state.cards.has(id) and state.address_of(id) == address:
			continue
		var outcome := _move_to_address(id, address)
		if not outcome.get("ok", false):
			return outcome
	for record in records:
		_restore_attributes(record)
	_restore_hand_order(records)
	return _ok_result()


# Ascending key: hosts/scene first, then prizes/resources, deck, hand and
# attachments. Inside a pile the slots count down, because the scene only
# appends (appending puts the card on top, which is slot 1).
func _sort_for_restore(records : Array) -> Array:
	var entries := []
	for record in records:
		entries.append([_restore_key(record), record])
	for index in range(1, entries.size()):
		var current = entries[index]
		var position := index - 1
		while position >= 0 and str(entries[position][0]) > str(current[0]):
			entries[position + 1] = entries[position]
			position -= 1
		entries[position + 1] = current
	var ordered := []
	for entry in entries:
		ordered.append(entry[1])
	return ordered


func _restore_key(record : Dictionary) -> String:
	var parsed := _Table.parse_address(str(record.get("address", "")))
	var kind := str(parsed.get("kind", ""))
	var rank := 0
	match kind:
		"field", "scenario":
			rank = 0
		"prizes", "resources":
			rank = 1
		"deck":
			rank = 2
		"hand":
			rank = 3
		"attachment":
			rank = 4
	var slot := int(parsed.get("slot", 0))
	var seat := int(parsed.get("seat", 0))
	return str(rank).pad_zeros(2) + ":" + str(seat).pad_zeros(2) + ":" \
			+ str(999999 - slot).pad_zeros(6)


func _restore_attributes(record : Dictionary) -> void:
	var node = _node(str(record.get("card", "")))
	if not is_instance_valid(node):
		return
	var on_board = node.get_parent() == board
	if on_board or node.get_parent() == _hand():
		var face_up := str(record.get("face", "up")) == "up"
		if node.is_faceup != face_up:
			node.set_is_faceup(face_up, true)
	if on_board:
		var rotation := int(record.get("rotation", 0))
		if int(node.card_rotation) != rotation:
			node.set_card_rotation(rotation)
		var tokens = _tokens(node)
		if is_instance_valid(tokens):
			var shield := int(record.get("shield", 0))
			var current := int(tokens.get_token_count("escudo"))
			if current != shield:
				tokens.mod_token("escudo", shield - current)


# Puts the hand back in the recorded slot order. Every hand address changed
# when a card entered or left the front of the hand, so the undo list carries
# the slot of every card and they are reapplied at once.
func _restore_hand_order(records : Array) -> void:
	var hand = _hand()
	if not is_instance_valid(hand):
		return
	var slots := {}
	for record in records:
		var parsed := _Table.parse_address(str(record.get("address", "")))
		if str(parsed.get("kind", "")) == "hand":
			slots[str(record["card"])] = int(parsed["slot"])
	if slots.is_empty():
		return
	var cards: Array = hand.get_all_cards()
	var entries := []
	var fallback := 1000000
	for card in cards:
		var id := _Snapshot.id_of(card)
		var slot := int(slots.get(id, fallback))
		fallback += 1
		entries.append([slot, card])
	for index in range(1, entries.size()):
		var current = entries[index]
		var position := index - 1
		while position >= 0 \
				and int(entries[position][0]) > int(current[0]):
			entries[position + 1] = entries[position]
			position -= 1
		entries[position + 1] = current
	var base: int = hand.get_child_count() - cards.size()
	for index in range(entries.size()):
		hand.move_child(entries[index][1], base + index)


# -----------------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------------

func _dispatch(intent : Dictionary) -> Dictionary:
	match str(intent.get("op", "")):
		"comprar":
			return _do_draw(intent)
		"mandar_topo_para_recursos":
			return _do_mill(intent)
		"jogar":
			return _do_play(intent)
		"materializar":
			return _do_materialize(intent)
		"anexar":
			return _do_attach(intent)
		"mover":
			return _do_move(intent)
		"descartar":
			return _do_discard(intent)
		"ferir":
			return _do_wound(intent)
		"nocautear":
			return _do_knockout(intent)
		"enviar_aos_prêmios":
			return _do_prizes(intent)
		"escudo":
			return _do_shield(intent)
		"virar":
			return _do_flip(intent)
		"girar":
			return _do_rotate(intent)
		"capacitar":
			return _do_stage(intent, true)
		"incapacitar":
			return _do_stage(intent, false)
		"reordenar_mão":
			return _do_reorder(intent)
		"embaralhar":
			return _do_shuffle(intent)
		"passar_fase":
			return _do_phase(intent)
		"trocar_assento":
			return _do_swap(intent)
		"_restaurar":
			return _restore(intent)
	return _fail("verbo_desconhecido",
			"Verbo desconhecido: " + str(intent.get("op", "")))


func _do_draw(intent : Dictionary) -> Dictionary:
	var deck = _deck()
	var hand = _hand()
	if not is_instance_valid(deck) or not is_instance_valid(hand):
		return _fail("mesa_indisponivel", "Deck ou mão não estão na mesa.")
	var drawn := []
	var names := []
	for _index in range(int(intent.get("quantity", 1))):
		var card: Card = deck.get_top_card()
		if not card:
			break
		drawn.append(_Snapshot.id_of(card))
		names.append(str(card.canonical_name))
		# The draw enters the front of the hand. On an empty hand the append is
		# the only safe path: the container cannot translate index 0.
		if hand.get_card_count() == 0:
			card.move_to(hand)
		else:
			card.move_to(hand, 0)
	return {"ok": true, "cards": drawn, "names": names}


func _do_mill(intent : Dictionary) -> Dictionary:
	var deck = _deck()
	var resources = _resources_pile()
	if not is_instance_valid(deck) or not is_instance_valid(resources):
		return _fail("mesa_indisponivel", "Deck ou recursos não estão na mesa.")
	var moved := []
	var names := []
	for _index in range(int(intent.get("quantity", 1))):
		var card: Card = deck.get_top_card()
		if not card:
			break
		moved.append(_Snapshot.id_of(card))
		names.append(str(card.canonical_name))
		card.move_to(resources)
	if moved.is_empty():
		return _fail("deck_vazio", "O deck está vazio.")
	return {"ok": true, "cards": moved, "names": names}


func _do_play(intent : Dictionary) -> Dictionary:
	# A new scenario replaces the active one, which goes to the discard pile,
	# exactly as the card template already does when a scenario is dropped.
	var replaces := str(intent.get("replaces", ""))
	if not replaces.is_empty():
		var previous = _node(replaces)
		var resources = _resources_pile()
		if is_instance_valid(previous) and is_instance_valid(resources):
			_release_board_slot(previous)
			previous.move_to(resources)
	return _move_to_address(str(intent["card"]), str(intent["to"]))


# The card goes to the chosen field slot and the life arrives with it: the top
# cards of the deck are attached under the card in the same intent, so the table
# never shows a character without its energy.
func _do_materialize(intent : Dictionary) -> Dictionary:
	var deck = _deck()
	if not is_instance_valid(deck):
		return _fail("deck_indisponivel", "O deck não está na mesa.")
	var moved := _move_to_address(str(intent["card"]), str(intent["to"]),
			["Materializar"])
	if not moved.get("ok", false):
		return moved
	var card = _node(str(intent["card"]))
	if not is_instance_valid(card):
		return _fail("carta_ausente", "A carta não está na mesa.")
	var attached := []
	for _index in range(int(intent.get("life", 0))):
		var top: Card = deck.get_top_card()
		if not top:
			break
		var result := _attach_at(top, card, -1)
		if not result.get("ok", false):
			return result
		# The deck keeps its cards face-down; the life under the character is
		# meant to be read, so show the faces as the resource payment does.
		top.set_is_faceup(true)
		attached.append(_Snapshot.id_of(top))
	return {"ok": true, "error": "", "message": "", "attachments": attached}


func _do_attach(intent : Dictionary) -> Dictionary:
	var node = _node(str(intent["card"]))
	var host = _node(str(intent["host"]))
	if not is_instance_valid(node) or not is_instance_valid(host):
		return _fail("mesa_indisponivel", "Carta ou hospedeiro não estão na mesa.")
	return _attach_at(node, host, -1)


func _do_move(intent : Dictionary) -> Dictionary:
	return _move_to_address(str(intent["card"]), str(intent["to"]))


func _do_discard(intent : Dictionary) -> Dictionary:
	return _move_to_address(str(intent["card"]), str(intent["to"]))


func _do_wound(intent : Dictionary) -> Dictionary:
	var node = _node(str(intent["card"]))
	if not is_instance_valid(node):
		return _fail("carta_ausente", "A carta não está na mesa.")
	var result := int(board.damage_character(node, int(intent.get("amount", 1))))
	if result == CFConst.ReturnCode.FAILED:
		return _fail("dano_falhou", "Não foi possível ferir a carta.")
	return _ok_result()


func _do_knockout(intent : Dictionary) -> Dictionary:
	var node = _node(str(intent["card"]))
	if not is_instance_valid(node):
		return _fail("carta_ausente", "A carta não está na mesa.")
	if node.is_battle_scenes_character():
		board.knockout_character(node)
	elif node.is_battle_scenes_support():
		board.knockout_support(node)
	else:
		return _fail("tipo_invalido", "Essa carta não pode ser nocauteada.")
	return _ok_result()


# Sending a character to the opponent's prizes is one transaction: the network
# payload goes out first and, once it is out, the attachments return to the
# resources and the card leaves the table. If the send is refused nothing
# changes, so the transaction has no half-applied state.
func _do_prizes(intent : Dictionary) -> Dictionary:
	var node = _node(str(intent["card"]))
	if not is_instance_valid(node):
		return _fail("carta_ausente", "A carta não está na mesa.")
	if not node.attachments.is_empty() and not is_instance_valid(_resources_pile()):
		return _fail("recursos_indisponiveis",
				"Os recursos não estão na mesa para receber os anexos.")
	var sink = prize_sink if is_instance_valid(prize_sink) else board
	if not sink.has_method("send_card_to_opponent_prizes") \
			or not sink.send_card_to_opponent_prizes(node):
		return _fail("premios_indisponiveis",
				"A carta não foi enviada aos prêmios.")
	_release_prize_card(node, _seat)
	return _ok_result()


# The card already reached the opponent, so the table cannot keep it: each
# attachment goes back to the owner's resources as part of the same intent, the
# slot is freed and the node leaves the group and the mouse detection. The
# state is rebuilt right after this, so the card only has to stop being seen.
func _release_prize_card(node : Card, seat : int) -> void:
	for attachment in node.attachments.duplicate():
		attachment.current_host_card = null
		node.attachments.erase(attachment)
		_move_to_address(_Snapshot.id_of(attachment),
				_Table.resource_address(int(seat), 1))
	node.attachments.clear()
	_release_board_slot(node)
	node.remove_from_group("cards")
	node.monitoring = false
	node.monitorable = false
	node.visible = false
	node.queue_free()


func _do_shield(intent : Dictionary) -> Dictionary:
	var node = _node(str(intent["card"]))
	if not is_instance_valid(node):
		return _fail("carta_ausente", "A carta não está na mesa.")
	var tokens = _tokens(node)
	if not is_instance_valid(tokens):
		return _fail("carta_sem_escudo", "A carta não tem contador de escudo.")
	if int(tokens.mod_token("escudo", int(intent.get("amount", 0)))) \
			== CFConst.ReturnCode.FAILED:
		return _fail("escudo_falhou", "Não foi possível ajustar o escudo.")
	return _ok_result()


func _do_flip(intent : Dictionary) -> Dictionary:
	var node = _node(str(intent["card"]))
	if not is_instance_valid(node):
		return _fail("carta_ausente", "A carta não está na mesa.")
	if int(node.set_is_faceup(not node.is_faceup)) == CFConst.ReturnCode.FAILED:
		return _fail("virada_falhou", "Não foi possível virar a carta.")
	return _ok_result()


func _do_rotate(intent : Dictionary) -> Dictionary:
	var node = _node(str(intent["card"]))
	if not is_instance_valid(node):
		return _fail("carta_ausente", "A carta não está na mesa.")
	# `toggle` keeps the T button cycling: a card already at the requested
	# angle returns to 0 instead of staying turned.
	var result: int = node.set_card_rotation(int(intent.get("degree", 90)),
			bool(intent.get("toggle", false)))
	if result == CFConst.ReturnCode.FAILED:
		return _fail("giro_falhou", "Não foi possível girar a carta.")
	return _ok_result()


func _do_stage(intent : Dictionary, capacitate : bool) -> Dictionary:
	var node = _node(str(intent["card"]))
	if not is_instance_valid(node):
		return _fail("carta_ausente", "A carta não está na mesa.")
	var result: int = node.capacitar() if capacitate else node.incapacitar()
	if result == CFConst.ReturnCode.FAILED:
		return _fail("estado_falhou", "Não foi possível mudar o estado da carta.")
	return _ok_result()


func _do_reorder(intent : Dictionary) -> Dictionary:
	var hand = _hand()
	if not is_instance_valid(hand):
		return _fail("mesa_indisponivel", "A mão não está na mesa.")
	var ids := []
	for id in state.hand[int(intent["seat"])]:
		if str(id) != "":
			ids.append(str(id))
	var from_index := int(intent.get("from", 0)) - 1
	var to_index := int(intent.get("to_slot", 0)) - 1
	if from_index < 0 or from_index >= ids.size() \
			or to_index < 0 or to_index >= ids.size():
		return _fail("slot_invalido", "Slot inválido para reordenar a mão.")
	var moved: String = ids[from_index]
	ids.remove_at(from_index)
	ids.insert(to_index, moved)
	_set_hand_order(ids)
	return _ok_result()


func _do_shuffle(intent : Dictionary) -> Dictionary:
	var pile_name := str(intent.get("pile", "deck"))
	var pile = _hand() if pile_name == "hand" else _deck()
	if not is_instance_valid(pile):
		return _fail("mesa_indisponivel", "A pilha não está na mesa.")
	if pile_name == "hand":
		pile.shuffle_cards()
	else:
		pile.shuffle_cards(false)
	return _ok_result()


func _do_phase(_intent : Dictionary) -> Dictionary:
	if not Multiplayer.advance_phase():
		return _fail("fase_indisponivel", "Não foi possível passar a fase.")
	return _ok_result()


func _do_swap(_intent : Dictionary) -> Dictionary:
	if not Multiplayer.swap_solo_seat():
		return _fail("assento_indisponivel", "Não foi possível trocar de assento.")
	return _ok_result()


# -----------------------------------------------------------------------------
# Moving cards
# -----------------------------------------------------------------------------

# Applies an address to a card node. Every zone the model knows has a way back
# into the scene here, so undo and scripts do not need a second set of rules.
func _move_to_address(id : String, address : String,
		tags := ["Manual"]) -> Dictionary:
	var node = _node(id)
	if not is_instance_valid(node):
		return _fail("carta_ausente", "A carta " + id + " não está na mesa.")
	var parsed := _Table.parse_address(address)
	var kind := str(parsed.get("kind", ""))
	# Everything except the field and the scenario leaves the board. The card
	# template only frees the slot when its tween finishes (a pile move yields
	# before that), so the intent frees it here and the table never reports the
	# card in two zones.
	if kind in ["hand", "resources", "prizes", "deck"]:
		_release_board_slot(node)
		_detach_from_host(node)
	match kind:
		"hand":
			return _move_to_hand(node, int(parsed.get("slot", 1)))
		"field":
			var slot = _field_slot(str(parsed.get("row", "frente")),
					int(parsed.get("column", 1)))
			if not is_instance_valid(slot):
				return _fail("campo_indisponivel", "O campo não está na mesa.")
			node.move_to(board, -1, slot, tags)
			return _ok_result()
		"resources":
			var resources = _resources_pile()
			if not is_instance_valid(resources):
				return _fail("recursos_indisponiveis",
						"Os recursos não estão na mesa.")
			node.move_to(resources)
			return _ok_result()
		"prizes":
			var prizes = _prizes_pile()
			if not is_instance_valid(prizes):
				return _fail("premios_indisponiveis",
						"Os prêmios não estão na mesa.")
			node.move_to(prizes)
			return _ok_result()
		"deck":
			var deck = _deck()
			if not is_instance_valid(deck):
				return _fail("deck_indisponivel", "O deck não está na mesa.")
			# Appending to a pile puts the card on top, which is deck:1.
			node.move_to(deck)
			return _ok_result()
		"scenario":
			var slot = _scenario_slot()
			if not is_instance_valid(slot):
				return _fail("cenario_indisponivel",
						"O slot do cenário não está na mesa.")
			node.move_to(board, -1, slot, tags)
			return _ok_result()
		"attachment":
			var host_id = state.card_at(str(parsed.get("host_address", "")))
			var host = _node(host_id)
			if not is_instance_valid(host):
				return _fail("hospedeiro_desconhecido",
						"O hospedeiro do anexo não está na mesa.")
			return _attach_at(node, host, int(parsed.get("index", 0)))
	return _fail("destino_invalido", "Destino inválido: " + address)


# Frees the grid slot the card occupies, so a card that leaves the board stops
# answering to its old field address immediately. Moving between field slots
# does not need this: the card template hands the new slot over synchronously.
func _release_board_slot(node) -> void:
	var slot = node._placement_slot
	if is_instance_valid(slot) and slot.occupying_card == node:
		slot.occupying_card = null
	node._placement_slot = null


# A card that leaves its host is a plain card again. The host list and the card
# reference are cleared before the move, or the host keeps an attachment that is
# no longer under it and arranges it on the board.
func _detach_from_host(node) -> void:
	if not is_instance_valid(node) or not is_instance_valid(node.current_host_card):
		return
	var host: Card = node.current_host_card
	host.attachments.erase(node)
	node.current_host_card = null
	host._organize_attachments()


func _move_to_hand(node : Card, slot : int) -> Dictionary:
	var hand = _hand()
	if not is_instance_valid(hand):
		return _fail("mesa_indisponivel", "A mão não está na mesa.")
	if node.get_parent() != hand:
		# The append is safe on an empty hand and the order is fixed below.
		if hand.get_card_count() == 0:
			node.move_to(hand)
		else:
			node.move_to(hand, 0)
	var order := []
	for card in hand.get_all_cards():
		if card != node:
			order.append(_Snapshot.id_of(card))
	var target := int(clamp(slot - 1, 0, order.size()))
	order.insert(target, _Snapshot.id_of(node))
	_set_hand_order(order)
	return _ok_result()


func _set_hand_order(ids : Array) -> void:
	var hand = _hand()
	if not is_instance_valid(hand):
		return
	var cards := []
	for id in ids:
		var card = _node(str(id))
		if is_instance_valid(card) and card.get_parent() == hand:
			cards.append(card)
	var base: int = hand.get_child_count() - hand.get_all_cards().size()
	for index in range(cards.size()):
		hand.move_child(cards[index], base + index)


func _attach_at(node : Card, host : Card, index : int) -> Dictionary:
	if not is_instance_valid(node) or not is_instance_valid(host):
		return _fail("mesa_indisponivel", "Carta ou hospedeiro não estão na mesa.")
	node.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
	node.attachment_offset = Card.AttachmentOffset.BATTLE_SCENES_BOTTOM
	node.attach_to_host(host)
	if node.current_host_card != host:
		return _fail("anexo_falhou", "Não foi possível anexar a carta.")
	if int(index) > 0:
		var position: int = host.attachments.find(node)
		if position >= 0:
			host.attachments.remove_at(position)
			var target := int(clamp(int(index) - 1, 0,
					host.attachments.size()))
			host.attachments.insert(target, node)
	host.arrange_attachment_stack()
	return _ok_result()


func _hand():
	return _container("Hand", "hand")


func _deck():
	return _container("Deck", "deck")


func _resources_pile():
	return _container("Discard", "discard")


func _prizes_pile():
	return _container("Prêmios", "prêmios")


func _container(node_name : String, nmap_key : String):
	if is_instance_valid(board):
		var direct = board.get_node_or_null(node_name)
		if is_instance_valid(direct):
			return direct
	return cfc.NMAP.get(nmap_key, null)


func _field_slot(row : String, column : int):
	var grid := _Snapshot.field_grid(board)
	if not is_instance_valid(grid):
		return null
	var columns := int(max(1, int(
			grid.get_node("GridContainer").columns)))
	if int(column) > columns:
		_grow_field_columns(grid, int(column))
		columns = int(max(1, int(
				grid.get_node("GridContainer").columns)))
	var row_index := 0 if row != "trás" else 1
	var index: int = row_index * columns + int(column) - 1
	while grid.get_slot_count() <= index:
		grid.add_slot()
	if index < 0:
		return null
	return grid.get_slot(index)


# Adds columns to the field grid keeping every placed card at its own
# (row, column). The grid appends the new slots at the end, so the card that
# was at index 2 (trás:1 with two columns) would end up on frente:3 after the
# third column is added.
func _grow_field_columns(grid, needed : int) -> void:
	grid.set_columns_keeping_cards(int(needed))


func _scenario_slot():
	var grid := _Snapshot.scenario_grid(board)
	if not is_instance_valid(grid) or grid.get_slot_count() == 0:
		return null
	return grid.get_slot(0)


func _tokens(node : Node):
	return node.get_node_or_null("Control/Tokens")


func _node(id : String):
	if _nodes.has(id) and is_instance_valid(_nodes[id]):
		return _nodes[id]
	if not is_instance_valid(board):
		return null
	for card in board.get_tree().get_nodes_in_group("cards"):
		if is_instance_valid(card) and _Snapshot.id_of(card) == id:
			return card
	return null


# -----------------------------------------------------------------------------
# Intent and log bookkeeping
# -----------------------------------------------------------------------------

# Resolves a Card node to its snapshot id, so callers can pass either.
func _resolve(raw : Dictionary) -> Dictionary:
	var intent := raw.duplicate()
	intent["seat"] = int(intent.get("seat", _seat))
	if intent["seat"] <= 0:
		intent["seat"] = _seat
	var card_ref = intent.get("card", "")
	if card_ref is Card:
		intent["card"] = _Snapshot.id_of(card_ref)
	var host_ref = intent.get("host", "")
	if host_ref is Card:
		intent["host"] = _Snapshot.id_of(host_ref)
	return intent


func _cards_snapshot() -> Dictionary:
	var snapshot := {}
	for id in state.cards:
		var entry: Dictionary = state.cards[id]
		snapshot[str(id)] = {
			"address": str(entry["address"]),
			"face": str(entry["face"]),
			"rotation": int(entry["rotation"]),
			"shield": int(entry["shield"]),
		}
	return snapshot


func _address_map() -> Dictionary:
	var addresses := {}
	for id in state.cards:
		addresses[str(id)] = str(state.cards[id]["address"])
	return addresses


func _undo_changes(before : Dictionary) -> Array:
	var changes := []
	for id in before:
		if not state.cards.has(id):
			continue
		var old: Dictionary = before[id]
		var now: Dictionary = state.cards[id]
		var old_address := str(old["address"])
		var new_address := str(now["address"])
		var old_zone := _zone_from_address(old_address)
		var new_zone := _zone_from_address(new_address)
		var attribute_changed := str(now["face"]) != str(old["face"]) \
				or int(now["rotation"]) != int(old["rotation"]) \
				or int(now["shield"]) != int(old["shield"])
		var zone_changed := old_zone != new_zone
		# Piles and the deck renumber themselves when a card leaves or enters,
		# so only a real zone change needs an undo move there. Hand and field
		# slots are explicit, so a changed address always counts.
		var slot_changed := old_zone in ["hand", "field", "scenario", "attachment"] \
				and old_address != new_address
		if not (zone_changed or slot_changed or attribute_changed):
			continue
		changes.append({
			"card": str(id),
			"address": old_address,
			"face": str(old["face"]),
			"rotation": int(old["rotation"]),
			"shield": int(old["shield"]),
		})
	return changes


func _zone_from_address(address : String) -> String:
	if address.is_empty():
		return ""
	return str(_Table.parse_address(address).get("kind", ""))


func _removed_from(before : Dictionary) -> String:
	for id in before:
		if not state.cards.has(id):
			return str(id)
	return ""


func _build_entry(intent : Dictionary, before : Dictionary, card_id : String,
		card_name : String, host_name : String,
		outcome : Dictionary) -> Dictionary:
	_seq += 1
	var after := _address_map()
	var op := str(intent["op"])
	var changes := _undo_changes(before)
	var removed := _removed_from(before)
	var undoable := false
	var reason := ""
	if op in IRREVERSIBLE:
		reason = str(IRREVERSIBLE_REASONS.get(op, "Essa ação não pode ser desfeita."))
	elif op == "jogar" and intent.has("replaces"):
		reason = "A troca de cenário não pode ser desfeita."
	elif not removed.is_empty():
		reason = "Uma carta saiu da mesa."
	elif changes.is_empty():
		reason = "Nada mudou."
	else:
		undoable = true
	var entry := {
		"seq": _seq,
		"op": op,
		"seat": int(intent["seat"]),
		"card": card_id,
		"name": card_name,
		"from": str(before.get(card_id, {}).get("address", "")),
		"to": str(after.get(card_id, "")),
		"amount": int(intent.get("amount",
				intent.get("quantity", 0))),
		"before": _address_map_of(before),
		"after": after,
		"undoable": undoable,
		"undo_reason": reason,
		"undo": {"op": "_restaurar", "cards": changes},
		"undone": false,
	}
	entry["text"] = _describe_entry(intent, entry, host_name, outcome)
	return entry


func _address_map_of(snapshot : Dictionary) -> Dictionary:
	var addresses := {}
	for id in snapshot:
		addresses[str(id)] = str(snapshot[id].get("address", ""))
	return addresses


func _describe_entry(intent : Dictionary, entry : Dictionary,
		host_name : String, outcome : Dictionary) -> String:
	var who := "P" + str(entry["seat"])
	var name := str(entry["name"])
	var text := ""
	match str(entry["op"]):
		"comprar":
			var names := PackedStringArray(outcome.get("names", []))
			text = who + " comprou " + str(names.size()) + " carta(s): " \
					+ ", ".join(names)
		"mandar_topo_para_recursos":
			var milled := PackedStringArray(outcome.get("names", []))
			var milled_text := name
			if not milled.is_empty():
				milled_text = ", ".join(milled)
			text = who + " mandou " + milled_text + " do topo para os recursos"
		"jogar":
			text = who + " jogou " + name + " (" + str(entry["from"]) \
					+ " → " + str(entry["to"]) + ")"
		"materializar":
			text = who + " materializou " + name + " em " + str(entry["to"]) \
					+ " com " + str(intent.get("life", 0)) + " de vida"
		"anexar":
			text = who + " anexou " + name + " a " + host_name
		"mover":
			text = who + " moveu " + name + " (" + str(entry["from"]) \
					+ " → " + str(entry["to"]) + ")"
		"descartar":
			text = who + " descartou " + name + " (" + str(entry["from"]) \
					+ " → " + str(entry["to"]) + ")"
		"ferir":
			text = who + " feriu " + name + " (-" \
					+ str(entry["amount"]) + ")"
		"nocautear":
			text = who + " nocauteou " + name
		"enviar_aos_prêmios":
			text = who + " enviou " + name + " aos prêmios do oponente"
		"escudo":
			var amount := int(entry["amount"])
			text = who + " ajustou o escudo de " + name + " (" \
					+ ("+" if amount > 0 else "") + str(amount) + ")"
		"virar":
			text = who + " virou " + name
		"girar":
			text = who + " girou " + name + " para " \
					+ str(intent.get("degree", 90)) + "°"
		"capacitar":
			text = who + " capacitou " + name
		"incapacitar":
			text = who + " incapacitou " + name
		"reordenar_mão":
			text = who + " reordenou a mão (" + str(intent.get("from", 0)) \
					+ " → " + str(intent.get("to_slot", 0)) + ")"
		"embaralhar":
			text = who + " embaralhou " + str(intent.get("pile", "deck"))
		"passar_fase":
			text = who + " passou a fase"
		"trocar_assento":
			text = who + " trocou de assento"
		_:
			text = who + " " + str(entry["op"])
	return text


func _ok_result() -> Dictionary:
	last_error = ""
	return {"ok": true, "error": "", "message": ""}


func _fail(code : String, message : String) -> Dictionary:
	last_error = message
	return {"ok": false, "error": code, "message": message, "state": state}


func _failure(decision : Dictionary) -> Dictionary:
	return _fail(str(decision.get("error", "falhou")),
			str(decision.get("message", "A ação não foi permitida.")))


# Hands the outcome to the optional recorder after `state` is up to date, so the
# snapshot on the line matches the table the action produced.
func _record(intent : Dictionary, result : Dictionary) -> void:
	if not is_instance_valid(recorder) or not recorder.is_recording():
		return
	recorder.record_intent(intent, result, state, _seat)


# A drag that took the legacy path moved a card without being validated here.
# The line is flagged as external so a reader knows it is evidence of what
# happened, not a replayable intent.
func record_external(entry : Dictionary) -> void:
	if not is_instance_valid(recorder) or not recorder.is_recording():
		return
	sync()
	var intent := {"op": str(entry.get("op", "arrastar")), "seat": _seat}
	for field in ["card", "host", "to"]:
		if not str(entry.get(field, "")).is_empty():
			intent[field] = entry[field]
	recorder.record_intent(intent,
			{"ok": true, "external": true, "entry": entry}, state, _seat)
