# Keyboard face of the intent API.
#
# The same `TableActions` the buttons, drag and scripts use is driven by keys,
# so a shortcut can never do something the mouse could not do. The runner holds
# one selected card, walks the table in a stable order and turns a key into an
# intent; the rules validate it exactly as they do for a click.
#
# Keys (`,`/`.` cycle the selection; Tab/Shift+Tab do the same when no control
# is focused):
#   , .            card anterior / próxima
#   Esc            limpa seleção e anexo pendente
#   Ctrl+Z         desfazer
#   C              comprar 1 (Shift: 5)
#   M              mandar o topo do deck para os recursos
#   J              jogar a carta selecionada
#   A              anexar (1ª vez: origem; 2ª vez: hospedeiro)
#   N              mover para a outra fileira do campo
#   D              descartar
#   F              ferir 1
#   K              nocautear
#   R              enviar aos prêmios do oponente
#   S              escudo +1 (Shift: -1)
#   V              virar
#   G              girar 90°
#   =              capacitar
#   -              incapacitar
#   [ ]            mover na mão para a esquerda / direita
#   H              embaralhar o deck
#   T              passar a fase
#   X              trocar de assento (hotseat)
#
# No action asks for confirmation: question 22 was answered with "none", so the
# press applies at once and whoever drives the keyboard is responsible for the
# command it sends. The console and the scripts follow the same rule.
class_name TableKeyboard
extends RefCounted

const _Table = preload("res://src/core/table/TableState.gd")

# Shown by the F8 console ("teclas") so the map is discoverable in the game.
const KEY_HELP := "Teclas: , . seleciona · Esc cancela · Ctrl+Z desfaz\n" \
		+ "C comprar (Shift 5) · M topo p/ recursos · J jogar · A anexar · N mover fileira\n" \
		+ "D descartar · F ferir · K nocautear · R prêmios · S escudo (Shift -1)\n" \
		+ "V virar · G girar · = capacitar · - incapacitar · [ ] reordenar mão\n" \
		+ "H embaralhar · T passar fase · X trocar assento\n" \
		+ "Nenhuma tecla pede confirmação: a tecla aplica na hora."

var actions
var selected_id := ""
var attach_source := ""
# The last line the runner asked the table to show. Tests read it; the game
# shows it through the same label the resource payment uses.
var last_message := ""


func _init(table_actions = null) -> void:
	actions = table_actions
	if not is_instance_valid(actions):
		var board = cfc.NMAP.get("board", null)
		if is_instance_valid(board) and board.has_method("table_actions"):
			actions = board.table_actions()
	select_next(1, false)


# -----------------------------------------------------------------------------
# Entry points
# -----------------------------------------------------------------------------

# OS-facing entry. Text fields and the command console own the keyboard while
# they have focus, so a shortcut never types over a search box.
func handle_event(event : InputEventKey) -> bool:
	if not event.pressed or event.echo:
		return false
	if _text_input_focused():
		return false
	return handle_key(int(event.keycode), event.shift, event.control)


# Test and script entry. Returns true when the key was consumed.
func handle_key(keycode : int, shift := false, ctrl := false) -> bool:
	if not is_instance_valid(actions):
		return false
	actions.sync()
	# The table can change outside the keyboard (a click, a draw, a script), so
	# a shortcut never acts on a card that is no longer there.
	if selected_id.is_empty() or not actions.state.cards.has(selected_id):
		select_next(1, false)
	if keycode == KEY_TAB or keycode == KEY_COMMA \
			or keycode == KEY_PERIOD:
		var forward := true
		if keycode == KEY_COMMA or (keycode == KEY_TAB and shift):
			forward = false
		return select_next(1 if forward else -1)
	if keycode == KEY_ESCAPE:
		attach_source = ""
		_say("Seleção cancelada.")
		return true
	if ctrl and keycode == KEY_Z:
		attach_source = ""
		return _apply({"op": "desfazer"})
	var op := _op_for(keycode)
	if op.is_empty():
		return false
	var intent := _intent_for(op, shift)
	if intent.is_empty():
		return true
	return _apply(intent)


# -----------------------------------------------------------------------------
# Selection
# -----------------------------------------------------------------------------

# Every card the keyboard can target, in a stable order: the hand slots, the
# field rows (each host followed by its attachments), the scenario, the
# resources and the prizes. The deck is driven as a whole, not card by card.
func selectable_ids() -> Array:
	var ids := []
	if not is_instance_valid(actions):
		return ids
	var state = actions.state
	var seat := int(actions.get_seat())
	for id in state.hand.get(seat, []):
		if str(id) != "":
			ids.append(str(id))
	for row in _Table.ROWS:
		var row_ids: Array = state.field.get(seat, {}).get(row, [])
		for id in row_ids:
			if str(id) == "":
				continue
			ids.append(str(id))
			var attachments: Array = state.cards.get(str(id), {}) \
					.get("attachments", [])
			for attachment in attachments:
				ids.append(str(attachment))
	if str(state.scenario) != "":
		ids.append(str(state.scenario))
	for id in state.resources.get(seat, []):
		if str(id) != "":
			ids.append(str(id))
	for id in state.prizes.get(seat, []):
		if str(id) != "":
			ids.append(str(id))
	return ids


func selected_address() -> String:
	if selected_id.is_empty():
		return ""
	return actions.state.address_of(selected_id)


func select_next(step : int, announce := true) -> bool:
	var ids := selectable_ids()
	if ids.is_empty():
		selected_id = ""
		if announce:
			_say("Nenhuma carta na mesa.")
		return true
	var index := ids.find(selected_id)
	if index < 0:
		index = 0 if step >= 0 else ids.size() - 1
	else:
		index = int(posmod(index + step, ids.size()))
	selected_id = str(ids[index])
	if announce:
		_say("Selecionada: " + _name_of(selected_id) + " ("
				+ selected_address() + ")")
	return true


func _name_of(id : String) -> String:
	return str(actions.state.cards.get(id, {}).get("name", id))


# -----------------------------------------------------------------------------
# Keys to intents
# -----------------------------------------------------------------------------

func _op_for(keycode : int) -> String:
	match keycode:
		KEY_C:
			return "comprar"
		KEY_M:
			return "mandar_topo_para_recursos"
		KEY_J:
			return "jogar"
		KEY_A:
			return "anexar"
		KEY_N:
			return "mover"
		KEY_D:
			return "descartar"
		KEY_F:
			return "ferir"
		KEY_K:
			return "nocautear"
		KEY_R:
			return "enviar_aos_prêmios"
		KEY_S:
			return "escudo"
		KEY_V:
			return "virar"
		KEY_G:
			return "girar"
		KEY_EQUAL:
			return "capacitar"
		KEY_MINUS:
			return "incapacitar"
		KEY_BRACKETLEFT:
			return "mão_esquerda"
		KEY_BRACKETRIGHT:
			return "mão_direita"
		KEY_H:
			return "embaralhar"
		KEY_T:
			return "passar_fase"
		KEY_X:
			return "trocar_assento"
	return ""


func _intent_for(op : String, shift : bool) -> Dictionary:
	if op in ["comprar", "mandar_topo_para_recursos", "embaralhar",
			"passar_fase", "trocar_assento"]:
		var intent := {"op": op}
		if op == "comprar" and shift:
			intent["quantity"] = 5
		return intent
	if op == "anexar":
		return _attach_intent()
	if selected_id.is_empty() or not actions.state.cards.has(selected_id):
		_say("Selecione uma carta com , e . e tente de novo.")
		return {}
	var intent := {"op": op, "card": selected_id}
	match op:
		"escudo":
			intent["amount"] = -1 if shift else 1
		"mover":
			var to := _other_row_address(selected_id)
			if to.is_empty():
				_say("Mover: a carta precisa estar no campo.")
				return {}
			intent["to"] = to
		"mão_esquerda", "mão_direita":
			return _reorder_intent(op)
	return intent


# Attaching needs two cards, so the first press remembers the source and the
# second names the host. The selection itself is what Tab moves.
func _attach_intent() -> Dictionary:
	if attach_source.is_empty():
		if selected_id.is_empty() or not actions.state.cards.has(selected_id):
			_say("Anexar: selecione a carta que vai virar anexo.")
			return {}
		attach_source = selected_id
		_say("Anexar: escolha o hospedeiro e pressione A de novo.")
		return {}
	if selected_id.is_empty() or not actions.state.cards.has(selected_id):
		_say("Anexar: selecione o hospedeiro com , e .")
		return {}
	var intent := {"op": "anexar", "card": attach_source, "host": selected_id}
	attach_source = ""
	return intent


# A hand card moves one slot at a time; the ends of the hand refuse instead of
# silently doing nothing.
func _reorder_intent(op : String) -> Dictionary:
	var entry: Dictionary = actions.state.cards.get(selected_id, {})
	var parsed := _Table.parse_address(str(entry.get("address", "")))
	if str(parsed.get("kind", "")) != "hand":
		_say("Reordenar: selecione uma carta da mão.")
		return {}
	var from_slot := int(parsed.get("slot", 0))
	var to_slot := from_slot + (-1 if op == "mão_esquerda" else 1)
	var hand_size: int = actions.state.hand_count(int(actions.get_seat()))
	if to_slot < 1 or to_slot > hand_size:
		_say("A carta já está na ponta da mão.")
		return {}
	return {"op": "reordenar_mão", "from": from_slot, "to_slot": to_slot}


# The keyboard moves a field card to the same column in the other row; an
# occupied destination is refused by the rules with the usual message.
func _other_row_address(id : String) -> String:
	var entry: Dictionary = actions.state.cards.get(id, {})
	if entry.is_empty() or str(entry.get("zone", "")) != "field":
		return ""
	var parsed := _Table.parse_address(str(entry.get("address", "")))
	var row := "trás" if str(parsed.get("row", "")) == "frente" else "frente"
	return "p" + str(entry["seat"]) + ":campo:" + row + ":" \
			+ str(parsed.get("column", 1))


# -----------------------------------------------------------------------------
# Applying
# -----------------------------------------------------------------------------

func _apply(intent : Dictionary) -> bool:
	var result = actions.apply(intent)
	if not bool(result.get("ok", false)):
		_say(str(result.get("message", "")))
		_after_action()
		return true
	var entry: Dictionary = actions.history[actions.history.size() - 1]
	_say(str(entry.get("text", "")))
	_after_action()
	return true


# The card that left the table cannot stay selected; the runner picks the first
# remaining one so a sequence of keys never lands on nothing.
func _after_action() -> void:
	actions.sync()
	if selected_id.is_empty() or actions.state.cards.has(selected_id):
		return
	select_next(1, false)


func _say(message : String) -> void:
	last_message = message
	if not is_instance_valid(actions):
		return
	var board = actions.board
	if is_instance_valid(board) and board.has_method("show_resource_message"):
		board.show_resource_message(message)


func _text_input_focused() -> bool:
	if not is_instance_valid(actions):
		return false
	var board = actions.board
	if not is_instance_valid(board) or not board.is_inside_tree():
		return false
	var focus = board.get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit
