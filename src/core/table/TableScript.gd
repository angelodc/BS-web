# Runs a JSON script of validated intents against the local table.
#
# F4 of "ações sem mouse": a match can be described as a list of steps and
# checked by state, visual order and log, without simulating the mouse. Every
# step becomes an intent that `TableActions.apply()` validates and renders, so a
# script exercises exactly the same path as a button, a drop or a shortcut.
#
# Card references are stable: a step names a card by the definition id (or by
# its canonical name) and the runner resolves it against the current state. Two
# cards that share a name or definition get numbered aliases ("Electro 1",
# "Electro 2"), numbered by zone and slot, so a step can address one copy.
#
# A script is either an array of steps or a dictionary:
#
#   {"seed": "f4", "seat": 1, "steps": [
#       {"op": "embaralhar", "pile": "deck"},
#       {"op": "comprar", "quantity": 2},
#       {"op": "jogar", "card": "Electro"},
#       {"expect": {"card": "Electro", "address": "p1:campo:frente:2"}},
#       {"expect": {"zones": {"field": 1, "deck": 15}}},
#       {"expect": {"hand": ["Test Card 1"]}},
#       {"expect": {"field": {"frente": ["Electro", ""]}}},
#       {"expect": {"log": "jogou Electro"}},
#   ]}
#
# The seed is applied with `cfc.set_seed()` before the first step, so a shuffle
# followed by draws is reproducible. Nothing is applied when an expectation
# fails: the script stops at the first failure and reports its index.
class_name TableScript
extends Reference

const _Table = preload("res://src/core/table/TableState.gd")
const _Snapshot = preload("res://src/core/table/TableSnapshot.gd")

const SEATS := [1, 2]
const ROW_ORDER := ["frente", "trás"]
const CARD_KEYS := ["card", "host", "replaces"]


# Runs `script` against `actions`. `seat` overrides the script's seat when it is
# greater than zero; otherwise the script keeps its own seat or the table's.
#
# Returns {ok, error, message, steps, failed, state, log}:
#   steps  — one {ok, op, card, text} per applied step (or {ok, expect})
#   failed — index of the step that failed, or -1
#   log    — the visible log after the run
static func run(actions, script, seat := 0) -> Dictionary:
	var result := {
		"ok": true,
		"error": "",
		"message": "",
		"steps": [],
		"failed": -1,
		"state": null,
		"log": "",
	}
	if not is_instance_valid(actions):
		return _stop(result, null, -1, "mesa_indisponivel",
				"Não há mesa para executar o script.")
	var steps := []
	var script_seat := int(seat)
	if script is Dictionary:
		if script.has("steps"):
			var raw = script["steps"]
			if raw is Array:
				steps = raw
		if int(script.get("seat", 0)) > 0:
			script_seat = int(script["seat"])
		if script.has("seed"):
			cfc.set_seed(str(script["seed"]))
	elif script is Array:
		steps = script
	else:
		return _stop(result, actions, -1, "script_invalido",
				"O script precisa ser uma lista de passos ou um objeto.")
	if script_seat > 0:
		actions.sync(script_seat)
	else:
		actions.sync()
	for index in range(steps.size()):
		var step = steps[index]
		if not (step is Dictionary):
			return _stop(result, actions, index, "passo_invalido",
					"O passo " + str(index + 1) + " não é um objeto JSON.")
		if step.has("expect"):
			var expect = step["expect"]
			if not (expect is Dictionary):
				return _stop(result, actions, index, "espera_invalida",
						"A espera do passo " + str(index + 1)
						+ " precisa ser um objeto.")
			var issues := check(actions, expect, actions.get_seat())
			if not issues.empty():
				return _stop(result, actions, index, "espera_falhou",
						PoolStringArray(issues).join("; "))
			result["steps"].append({"ok": true, "expect": expect})
			continue
		var intent := resolve_intent(actions.state, step, script_seat)
		var outcome = actions.apply(intent)
		if not bool(outcome.get("ok", false)):
			return _stop(result, actions, index,
					str(outcome.get("error", "")),
					str(outcome.get("message", "")))
		var entry: Dictionary = outcome.get("entry", {})
		result["steps"].append({
			"ok": true,
			"op": str(intent.get("op", "")),
			"card": str(intent.get("card", "")),
			"text": str(entry.get("text", "")),
		})
	result["state"] = actions.state
	result["log"] = actions.describe_log()
	return result


static func _stop(result : Dictionary, actions, index : int,
		error : String, message : String) -> Dictionary:
	result["ok"] = false
	result["error"] = error
	result["message"] = message
	result["failed"] = int(index)
	if is_instance_valid(actions):
		result["state"] = actions.state
		result["log"] = actions.describe_log()
	return result


# -----------------------------------------------------------------------------
# Card references
# -----------------------------------------------------------------------------

# Replaces the card references of a step by the ids of the current state. A
# reference that resolves to nothing is kept as typed, so the rules answer with
# the same "carta_desconhecida" a button would show.
static func resolve_intent(state, step : Dictionary, seat := 0) -> Dictionary:
	var intent := step.duplicate(true)
	intent.erase("expect")
	for key in CARD_KEYS:
		if intent.has(key) and intent[key] is String:
			var id := resolve_card(state, str(intent[key]))
			if not id.empty():
				intent[key] = id
	if int(seat) > 0:
		intent["seat"] = int(seat)
	return intent


# Resolves a definition id, a canonical name, an address id or an alias to the
# id the state uses. Empty when nothing matches.
static func resolve_card(state, reference : String) -> String:
	var ref := str(reference)
	if ref.empty() or state == null:
		return ""
	if state.cards.has(ref):
		return ref
	var aliases := alias_map(state)
	if aliases.has(ref):
		return str(aliases[ref])
	var lowered := ref.to_lower()
	for id in _ordered_ids(state):
		var entry: Dictionary = state.cards[id]
		if str(entry.get("name", "")).to_lower() == lowered \
				or str(entry.get("definition", "")).to_lower() == lowered:
			return str(id)
	return ""


# alias -> id. A unique name or definition resolves directly; a duplicated one
# adds "<chave> 1" … "<chave> N" in zone order. The plain key always points at
# the first copy, the same way a hand card is picked by a click.
static func alias_map(state) -> Dictionary:
	var ids := _ordered_ids(state)
	var totals := {}
	for id in ids:
		for key in _keys_of(state, id):
			totals[key] = int(totals.get(key, 0)) + 1
	var counters := {}
	var aliases := {}
	for id in ids:
		for key in _keys_of(state, id):
			var ordinal := int(counters.get(key, 0)) + 1
			counters[key] = ordinal
			if not aliases.has(key):
				aliases[key] = str(id)
			if int(totals.get(key, 0)) > 1:
				aliases[key + " " + str(ordinal)] = str(id)
	return aliases


# id -> the alias a person would type. Used by expectations and by the log a
# caller builds from a script result.
static func display_names(state) -> Dictionary:
	var ids := _ordered_ids(state)
	var totals := {}
	for id in ids:
		for key in _keys_of(state, id):
			totals[key] = int(totals.get(key, 0)) + 1
	var counters := {}
	var names := {}
	for id in ids:
		var primary := _primary_key(state, id)
		var ordinal := int(counters.get(primary, 0)) + 1
		counters[primary] = ordinal
		if int(totals.get(primary, 0)) > 1:
			names[str(id)] = primary + " " + str(ordinal)
		else:
			names[str(id)] = primary
	return names


static func _primary_key(state, id : String) -> String:
	var keys := _keys_of(state, id)
	if keys.empty():
		return str(id)
	return str(keys[0])


static func _keys_of(state, id : String) -> Array:
	var keys := []
	if state == null or not state.cards.has(str(id)):
		return keys
	var entry: Dictionary = state.cards[str(id)]
	for key in [str(entry.get("name", "")), str(entry.get("definition", ""))]:
		if key.empty() or keys.has(key):
			continue
		keys.append(key)
	return keys


# Every card id in a stable order: the shared scenario, then both seats by
# hand, field rows, resources, prizes and deck, then the attachments in host
# order and finally anything in transit. The order never depends on Dictionary
# iteration, so the numbered aliases are the same on every run.
static func _ordered_ids(state) -> Array:
	var ids := []
	if state == null:
		return ids
	var scenario := str(state.scenario)
	if not scenario.empty():
		_append_id(ids, scenario)
	for seat in SEATS:
		for id in state.hand.get(seat, []):
			_append_id(ids, str(id))
		var rows: Dictionary = state.field.get(seat, {})
		for row in ROW_ORDER:
			for id in rows.get(row, []):
				_append_id(ids, str(id))
		for id in state.resources.get(seat, []):
			_append_id(ids, str(id))
		for id in state.prizes.get(seat, []):
			_append_id(ids, str(id))
		for id in state.deck.get(seat, []):
			_append_id(ids, str(id))
	for id in ids.duplicate():
		var entry: Dictionary = state.cards.get(str(id), {})
		for child in entry.get("attachments", []):
			_append_id(ids, str(child))
	for id in state.cards:
		var zone := str(state.cards[id].get("zone", ""))
		if zone in ["attachment", "transit"]:
			_append_id(ids, str(id))
	return ids


static func _append_id(ids : Array, id : String) -> void:
	if id.empty() or ids.has(id):
		return
	ids.append(id)


# -----------------------------------------------------------------------------
# Expectations
# -----------------------------------------------------------------------------

# Checks one `expect` object against the live table and returns the failures as
# human-readable lines. An empty array means everything matched.
#
# Supported keys:
#   card   + address   — the card is at that address
#   zones              — zone counts of the acting seat
#   hand               — the hand slots, left to right (holes as "")
#   field              — each row as a list, holes as ""
#   log                — the last log line contains the text
#   log_count          — the visible log has exactly that many entries
static func check(actions, expect : Dictionary, seat := 1) -> Array:
	var issues := []
	if not is_instance_valid(actions):
		return ["não há mesa"]
	var state = actions.state
	var names := display_names(state)
	if expect.has("card"):
		var ref := str(expect["card"])
		var id := resolve_card(state, ref)
		if id.empty():
			issues.append("carta desconhecida: " + ref)
		elif expect.has("address"):
			var address := str(expect["address"])
			var actual = state.address_of(id)
			if actual != address:
				issues.append(ref + " está em " + actual
						+ ", esperado " + address)
	if expect.has("zones"):
		var counts = state.zone_counts(int(seat))
		var wanted: Dictionary = expect["zones"]
		for zone in wanted:
			var actual := int(counts.get(str(zone), -1))
			if actual != int(wanted[zone]):
				issues.append("zona " + str(zone) + " tem " + str(actual)
						+ ", esperado " + str(int(wanted[zone])))
	if expect.has("hand"):
		var actual := _names_of(state.hand.get(int(seat), []), names)
		var wanted := _resolved_names(state, names, expect["hand"])
		if actual != wanted:
			issues.append("mão: " + str(actual) + ", esperado " + str(wanted))
	if expect.has("field"):
		var rows: Dictionary = state.field.get(int(seat), {})
		var wanted_rows: Dictionary = expect["field"]
		for row in wanted_rows:
			var actual := _names_of(rows.get(str(row), []), names)
			var wanted := _resolved_names(state, names, wanted_rows[row])
			if actual != wanted:
				issues.append("campo " + str(row) + ": " + str(actual)
						+ ", esperado " + str(wanted))
	if expect.has("log"):
		var text := _last_log_text(actions)
		var wanted := str(expect["log"])
		if text.find(wanted) < 0:
			issues.append("log \"" + text + "\" não contém \"" + wanted + "\"")
	if expect.has("log_count"):
		var count = actions.history.size()
		if count != int(expect["log_count"]):
			issues.append("log tem " + str(count) + " entradas, esperado "
					+ str(int(expect["log_count"])))
	return issues


static func _names_of(ids : Array, names : Dictionary) -> Array:
	var result := []
	for id in ids:
		if str(id) == "":
			result.append("")
			continue
		result.append(str(names.get(str(id), str(id))))
	return result


# Expected slots can name any copy ("Test Card 2 2") or leave a hole ("").
static func _resolved_names(state, names : Dictionary, raw) -> Array:
	var result := []
	if not (raw is Array):
		return result
	for ref in raw:
		var text := str(ref)
		if text.empty():
			result.append("")
			continue
		var id := resolve_card(state, text)
		if id.empty():
			result.append(text)
		else:
			result.append(str(names.get(id, text)))
	return result


static func _last_log_text(actions) -> String:
	var history: Array = actions.history
	if history.empty():
		return ""
	return str(history[history.size() - 1].get("text", ""))
