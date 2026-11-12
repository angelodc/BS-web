# Executa as partes automatizadas dos cenários reais.
#
# O gancho vem de `TableActions.apply()`: depois de uma intenção bem-sucedida a
# mesa compara os endereços antes/depois e avisa aqui quando um cenário entrou
# ou saiu de cena. Cada compra automática é uma intenção normal, validada e
# registrada no histórico; a linha do log do HUD é uma só, com o nome do
# cenário, por isso o `GameEvents` fica suprimido durante a intenção aninhada.
#
# O que a mesa não resolve sozinho vai para o log em amarelo: os trechos
# impressos que dependem de escolha, busca, dano ou de outro gatilho ficam em
# `pending` no catálogo e são anunciados na entrada em cena e no uso manual de
# uma opção. As condições simples (afiliação e contagem de personagens) são
# checadas: uma ação condicionada só roda quando a condição vale na mesa.
#
# A escolha A/B/C fica nos botões que o menu da carta de cenário mostra. O
# timing "affiliation" segura os botões até um personagem com a afiliação
# entrar em cena sob controle do dono do cenário.

const Catalog = preload("res://src/custom/cards/ScenarioCatalog.gd")
const TableStateScript = preload("res://src/core/table/TableState.gd")

# Seats are stored on the card node because the shared scenario has no owner in
# `TableState`; the scenario zone address belongs to the table, not to a seat.
const OWNER_META := "scenario_owner"
const OPTION_META := "scenario_option_used"

# The automatic effects run through the same runner, so this flag stops the
# post-intent diff from reacting to its own nested intents.
static var _running := false


# -----------------------------------------------------------------------------
# Entrada e saída de cena
# -----------------------------------------------------------------------------

# Compares the before/after addresses of one applied intent and resolves the
# scenarios that changed hands. Leaving comes first: a replacement resolves the
# old scenario before the new one triggers.
static func on_intent_applied(board, actions, entry : Dictionary) -> void:
	if _running:
		return
	var before: Dictionary = entry.get("before", {})
	var after: Dictionary = entry.get("after", {})
	var seat := int(entry.get("seat", actions.get_seat()))
	for id in before:
		if not _is_scenario_address(str(before[id])):
			continue
		if _is_scenario_address(str(after.get(id, ""))):
			continue
		_emit(board, actions, str(id), seat, false)
	for id in after:
		if not _is_scenario_address(str(after[id])):
			continue
		if _is_scenario_address(str(before.get(id, ""))):
			continue
		_emit(board, actions, str(id), seat, true)


static func _emit(board, actions, id : String, seat : int,
		entered : bool) -> void:
	var card = actions.node_of(id)
	if not is_instance_valid(card):
		return
	_running = true
	if entered:
		on_entered(board, actions, card, seat)
	else:
		on_left(board, actions, card, seat)
	_running = false


static func _is_scenario_address(address : String) -> bool:
	if address.is_empty():
		return false
	var parsed := TableStateScript.parse_address(address)
	return str(parsed.get("kind", "")) == "scenario"

# Called for a scenario that just arrived in the shared slot. The owner is the
# seat that played it, so it is also the seat that compras on entry.
static func on_entered(board, actions, card, seat : int) -> void:
	if not is_instance_valid(card):
		return
	card.set_meta(OWNER_META, seat)
	card.set_meta(OPTION_META, false)
	var entry := Catalog.entry_for(card)
	for action in entry.get("enter", []):
		_run_action(actions, card, seat, action, "entrada")
	for fragment in entry.get("pending", []):
		_log_pending(card, fragment)
	if bool(entry.get("negation", false)) \
			and is_instance_valid(board) \
			and board.has_method("add_negation_pin"):
		board.add_negation_pin(card)


# Called for a scenario that left the shared slot, whether it was replaced,
# discarded or removed. The draw belongs to the scenario's owner, which can be
# the other seat in a match; when this client cannot act for that seat the line
# tells the player the draw is manual.
static func on_left(_board, actions, card, seat : int) -> void:
	if not is_instance_valid(card):
		return
	var entry := Catalog.entry_for(card)
	if entry.is_empty():
		return
	var owner := owner_seat(card)
	if owner <= 0:
		owner = seat
	for action in entry.get("leave", []):
		_run_action(actions, card, owner, action, "saída")
	for fragment in Catalog.pending_leave_of(card):
		_log_pending(card, fragment)


# -----------------------------------------------------------------------------
# Conditions
# -----------------------------------------------------------------------------

# True when the table satisfies a simple printed condition. Unknown conditions
# answer false, so nothing runs on a guess.
static func condition_met(actions, seat : int, condition : Dictionary) -> bool:
	if condition.is_empty():
		return true
	var nodes := _field_characters(actions, seat)
	match str(condition.get("type", "")):
		"characters":
			return nodes.size() >= int(condition.get("min", 1))
		"affiliation":
			var wanted := str(condition.get("value", ""))
			var count := _count_affiliation(nodes, wanted)
			return count >= int(condition.get("min", 1))
		"all_affiliation":
			var value := str(condition.get("value", ""))
			if nodes.size() < int(condition.get("min", 1)):
				return false
			return _count_affiliation(nodes, value) == nodes.size()
		"shared_affiliation":
			return _shared_affiliation_count(nodes) >= int(condition.get("min", 3))
	return false


static func _field_characters(actions, seat : int) -> Array:
	var nodes := []
	if actions == null:
		return nodes
	var state = actions.state
	if state == null or not state.field.has(seat):
		return nodes
	for row in state.field[seat]:
		for id in state.field[seat][row]:
			if str(id).is_empty():
				continue
			var node = actions.node_of(str(id))
			if is_instance_valid(node) and _is_character(node):
				nodes.append(node)
	return nodes


static func _is_character(node) -> bool:
	return node.has_method("is_battle_scenes_character") \
			and node.is_battle_scenes_character()


static func _count_affiliation(nodes : Array, wanted : String) -> int:
	if wanted.strip_edges().is_empty():
		return 0
	var count := 0
	for node in nodes:
		if _has_affiliation(node, wanted):
			count += 1
	return count


static func _has_affiliation(node, wanted : String) -> bool:
	var target := wanted.strip_edges().to_lower()
	if target.is_empty():
		return false
	for piece in _affiliation_pieces(node):
		if piece == target:
			return true
	return false


# The printed card carries every affiliation in `Requirements`, separated by
# "/" and, in the older lay-outs, by " I " (e.g. "ARMA X I X-FORCE").
static func _affiliation_pieces(node) -> Array:
	var raw := str(node.properties.get("Requirements", ""))
	var pieces := []
	for slash in raw.split("/"):
		for piece in str(slash).split(" i "):
			var text := str(piece).strip_edges().to_lower()
			if not text.is_empty():
				pieces.append(text)
	return pieces


static func _shared_affiliation_count(nodes : Array) -> int:
	var counts := {}
	for node in nodes:
		for piece in _affiliation_pieces(node):
			counts[piece] = int(counts.get(piece, 0)) + 1
	var best := 0
	for key in counts:
		best = int(max(best, int(counts[key])))
	return best


# -----------------------------------------------------------------------------
# Options
# -----------------------------------------------------------------------------

static func options_of(card) -> Dictionary:
	return Catalog.entry_for(card).get("options", {})


static func items_of(card) -> Array:
	return options_of(card).get("items", [])


static func option_for(card, label : String) -> Dictionary:
	for item in items_of(card):
		if str(item.get("label", "")) == label:
			return item
	return {}


static func owner_seat(card) -> int:
	if not is_instance_valid(card):
		return 0
	return int(card.get_meta(OWNER_META, 0))


static func _runner(board, actions = null):
	if actions != null:
		return actions
	if is_instance_valid(board) and board.has_method("table_actions"):
		return board.table_actions()
	return null


# True when the option must be offered: the card is the active scenario, the
# local client controls its owner, the choice is not spent, the timing is met
# and at least one option is available.
static func can_choose(board, card, actions = null) -> bool:
	if not _is_active_scenario(board, card):
		return false
	var options := options_of(card)
	if options.is_empty() or items_of(card).is_empty():
		return false
	if bool(card.get_meta(OPTION_META, false)):
		return false
	var owner := owner_seat(card)
	if owner <= 0:
		return false
	var runner = _runner(board, actions)
	if runner == null or owner != int(runner.get_seat()):
		return false
	if not _timing_met(runner, options, owner):
		return false
	for item in items_of(card):
		if item_available(item, runner, owner):
			return true
	return false


# The printed text of the option, used as the button tooltip.
static func option_hint(item : Dictionary) -> String:
	return str(item.get("text", ""))


# An option with a condition stays hidden until the condition holds. Options
# that are only text (manual resolution) are always available.
static func item_available(item : Dictionary, runner, seat : int) -> bool:
	if not item.has("if"):
		return item.has("action") or item.has("manual")
	return condition_met(runner, seat, item["if"])


# Used by the card menu to decide which option buttons to draw.
static func label_available(board, card, label : String, actions = null) -> bool:
	var item := option_for(card, label)
	if item.is_empty():
		return false
	var runner = _runner(board, actions)
	if runner == null:
		return false
	var seat := owner_seat(card)
	if seat <= 0:
		return false
	if not _timing_met(runner, options_of(card), seat):
		return false
	return item_available(item, runner, seat)


static func _timing_met(runner, options : Dictionary, seat : int) -> bool:
	if str(options.get("timing", "")) != "affiliation":
		return true
	var wanted := str(options.get("affiliation", ""))
	if wanted.is_empty():
		return false
	return _count_affiliation(_field_characters(runner, seat), wanted) > 0


# Resolves one clicked option. The nested intents run with `GameEvents`
# suppressed so the whole choice becomes a single line:
# "P1 · Reforços Aliados — opção A: comprou 1 carta".
static func use_option(board, card, label : String, actions = null) -> Dictionary:
	if not can_choose(board, card, actions):
		return {"ok": false, "error": "sem_escolha",
				"message": "Esta opção não está disponível agora."}
	var item := option_for(card, label)
	if item.is_empty():
		return {"ok": false, "error": "opcao_desconhecida",
				"message": "Opção desconhecida: " + label}
	var runner = _runner(board, actions)
	if runner == null:
		return {"ok": false, "error": "mesa_indisponivel",
				"message": "A mesa não está disponível para esta ação."}
	var seat := owner_seat(card)
	if not item_available(item, runner, seat):
		return {"ok": false, "error": "condicao_nao_atendida",
				"message": "A condição da opção " + label + " não está atendida."}
	var moved := false
	if str(options_of(card).get("before", "")) == "recursos":
		var move_result := _apply_quietly(runner,
				{"op": "descartar", "card": card, "seat": seat})
		if not bool(move_result.get("ok", false)):
			_log(card, "opção " + label + " não aconteceu: "
					+ str(move_result.get("message", "")))
			return move_result
		moved = true
	if item.has("manual"):
		card.set_meta(OPTION_META, true)
		var manual := str(item["manual"])
		var prefix := "opção " + label + ": "
		if moved:
			prefix += "colocou o cenário nos recursos; "
		_log_pending(card, prefix + manual)
		return {"ok": true, "error": "", "manual": true,
				"message": prefix + manual}
	var action: Dictionary = item.get("action", {})
	if action.is_empty():
		return {"ok": false, "error": "opcao_sem_acao",
				"message": "A opção " + label + " ainda não tem ação."}
	var results := _apply_option_action(runner, action, seat)
	card.set_meta(OPTION_META, true)
	for result in results:
		if not bool(result.get("ok", false)):
			_log(card, "opção " + label + " não aconteceu: "
					+ str(result.get("message", "")))
			return result
	var text := "opção " + label + ": "
	if moved:
		text += "colocou o cenário nos recursos e "
	text += _option_label(action)
	_log(card, text)
	return {"ok": true, "error": "", "entry": results[0].get("entry", {}),
			"message": text}


static func _apply_option_action(runner, action : Dictionary,
		seat : int) -> Array:
	var results := []
	if str(action.get("op", "")) == "multi":
		for one in action.get("actions", []):
			results.append(_apply_option_intent(runner, one, seat))
		return results
	results.append(_apply_option_intent(runner, action, seat))
	return results


static func _apply_option_intent(runner, action : Dictionary,
		seat : int) -> Dictionary:
	var intent := action.duplicate(true)
	intent.erase("if")
	intent["seat"] = seat
	return _apply_quietly(runner, intent)


static func _option_label(action : Dictionary) -> String:
	if str(action.get("op", "")) == "multi":
		var labels := []
		for one in action.get("actions", []):
			labels.append(action_label(one))
		return " e ".join(PackedStringArray(labels))
	return action_label(action)


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

static func _is_active_scenario(board, card) -> bool:
	if not is_instance_valid(board) or not is_instance_valid(card):
		return false
	if card.get_parent() != board:
		return false
	return card.has_method("is_battle_scenes_scenario") \
			and card.is_battle_scenes_scenario()


static func _run_action(actions, card, seat : int,
		action : Dictionary, moment : String) -> bool:
	if action.is_empty():
		return true
	if action.has("if") and not condition_met(actions, seat, action["if"]):
		return true
	var intent := action.duplicate(true)
	intent.erase("if")
	intent["seat"] = seat
	var result := _apply_quietly(actions, intent)
	if not bool(result.get("ok", false)):
		_log(card, action_label(intent) + " não aconteceu (" + moment + "): "
				+ str(result.get("message", "")))
		return false
	_log(card, action_label(intent) + " (" + moment + ")")
	return true


static func _apply_quietly(actions, intent : Dictionary) -> Dictionary:
	var was_suppressed: bool = GameEvents.suppressed
	GameEvents.suppressed = true
	var result: Dictionary = actions.apply(intent)
	GameEvents.suppressed = was_suppressed
	return result


static func action_label(intent : Dictionary) -> String:
	var quantity := int(intent.get("quantity", 1))
	match str(intent.get("op", "")):
		"comprar":
			return "comprou " + _cards(quantity)
		"mandar_topo_para_recursos":
			return "colocou " + _cards(quantity) + " do topo do deck nos recursos"
	return str(intent.get("op", ""))


static func _cards(quantity : int) -> String:
	if quantity == 1:
		return "1 carta"
	return str(quantity) + " cartas"


static func _log(card, text : String, tone := "real") -> void:
	var name := Catalog.display_name(card)
	if name.is_empty():
		return
	GameEvents.record_scenario(name, text, tone)


static func _log_pending(card, text : String) -> void:
	_log(card, text, "pending")
