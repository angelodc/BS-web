# Rules for table intents.
#
# `TableActions` applies the side effects; this class only answers whether an
# intent is allowed and fills in the values the action needs (`to`, `quantity`,
# `host`, ...). It reads only the `TableState`, so a button, a drag, a keyboard
# shortcut and a script all share the same validation and the same errors.
#
# Verbs follow the plan in ACOES_SEM_MOUSE.md. The catalogue stays close to the
# actions that already exist; `pagar`, `trocar_recurso`, `buscar` and
# `usar_habilidade` still need a UI flow of their own and are not accepted yet.
class_name TableRules
extends RefCounted

const _Table = preload("res://src/core/table/TableState.gd")

const VERBS := [
	"comprar",
	"mandar_topo_para_recursos",
	"jogar",
	"anexar",
	"mover",
	"descartar",
	"ferir",
	"nocautear",
	"enviar_aos_prêmios",
	"escudo",
	"virar",
	"girar",
	"capacitar",
	"incapacitar",
	"reordenar_mão",
	"embaralhar",
	"passar_fase",
	"trocar_assento",
	"desfazer",
]

const FIELD_ROWS := ["frente", "trás"]
const SCENARIO_ADDRESS := "mesa:cenário"
const KNOCKOUT_TYPES := ["Personagem", "Suporte"]
const SHIELD_STEP := 3


# Validates an intent and returns `{ok, error, message, intent}`. On success,
# `intent` is a normalized copy: the action can rely on `seat`, `card`, `to`,
# `quantity`, `amount` and `host` without re-checking the input.
#
# `context` holds what is not table data:
#   active        — a match is running (Multiplayer.is_session_active())
#   solo          — the match is hotseat (Multiplayer.is_solo())
#   my_slot       — the seat acting now
#   my_phase      — the turn belongs to `my_slot`
#   enforce_cost  — check the card's ENERGIA against the resources
#   undo_entry    — last log entry that can still be undone (or null)
func validate(state, intent : Dictionary, context : Dictionary) -> Dictionary:
	var op := str(intent.get("op", ""))
	if not op in VERBS:
		return _fail("verbo_desconhecido", "Verbo desconhecido: " + op)
	var seat := int(intent.get("seat", context.get("my_slot", 1)))
	if seat != int(context.get("my_slot", 1)):
		return _fail("fora_do_seu_assento",
				"Esta ação é do assento P" + str(seat) + ".")
	if bool(context.get("active", false)) \
			and not bool(context.get("solo", false)) \
			and not bool(context.get("my_phase", true)):
		return _fail("fora_da_sua_fase", "Não é a sua fase.")
	var normalized := intent.duplicate(true)
	normalized["op"] = op
	normalized["seat"] = seat
	match op:
		"comprar":
			return _validate_draw(state, normalized)
		"mandar_topo_para_recursos":
			return _validate_mill(state, normalized)
		"jogar":
			return _validate_play(state, normalized, context)
		"anexar":
			return _validate_attach(state, normalized)
		"mover":
			return _validate_move(state, normalized)
		"descartar":
			return _validate_discard(state, normalized)
		"ferir":
			return _validate_wound(state, normalized)
		"nocautear":
			return _validate_knockout(state, normalized)
		"enviar_aos_prêmios":
			return _validate_send_prizes(state, normalized, context)
		"escudo":
			return _validate_shield(state, normalized)
		"virar":
			return _validate_flip(state, normalized)
		"girar":
			return _validate_rotate(state, normalized)
		"capacitar":
			return _validate_stage(state, normalized, 1)
		"incapacitar":
			return _validate_stage(state, normalized, -1)
		"reordenar_mão":
			return _validate_reorder(state, normalized)
		"embaralhar":
			return _validate_shuffle(state, normalized)
		"passar_fase":
			if not bool(context.get("active", false)):
				return _fail("sem_partida", "Não há partida em andamento.")
			return _ok(normalized)
		"trocar_assento":
			if not bool(context.get("active", false)) \
					or not bool(context.get("solo", false)):
				return _fail("apenas_hotseat",
						"Trocar de assento só existe na partida solo.")
			return _ok(normalized)
		"desfazer":
			return _validate_undo(normalized, context)
	return _fail("verbo_desconhecido", "Verbo desconhecido: " + op)


# -----------------------------------------------------------------------------
# Per-verb rules
# -----------------------------------------------------------------------------

func _validate_draw(state, normalized : Dictionary) -> Dictionary:
	var quantity := int(normalized.get("quantity", 1))
	if quantity < 1:
		return _fail("quantidade_invalida",
				"A quantidade precisa ser pelo menos 1.")
	var available_cards: int = state.deck_count(int(normalized["seat"]))
	if available_cards < quantity:
		return _fail("deck_insuficiente",
				"O deck não tem " + str(quantity) + " carta(s).")
	normalized["quantity"] = quantity
	return _ok(normalized)


func _validate_mill(state, normalized : Dictionary) -> Dictionary:
	if state.deck_count(int(normalized["seat"])) == 0:
		return _fail("deck_vazio", "O deck está vazio.")
	return _ok(normalized)


func _validate_play(state, normalized : Dictionary,
		context : Dictionary) -> Dictionary:
	var entry := _entry_of(state, normalized)
	if entry.is_empty():
		return _fail("carta_desconhecida", "A carta não está na mesa.")
	if str(entry["zone"]) != "hand":
		return _fail("fora_da_mão", "Só é possível jogar uma carta da mão.")
	var seat := int(normalized["seat"])
	var card_type := str(entry.get("type", ""))
	var to := str(normalized.get("to", ""))
	if card_type == "Cenário":
		to = SCENARIO_ADDRESS
	elif to.is_empty():
		to = _next_field_address(state, seat, card_type == "Suporte")
	var parsed := _Table.parse_address(to)
	match str(parsed.get("kind", "")):
		"field":
			if card_type == "Cenário":
				return _fail("cenario_exige_cenario",
						"Um cenário só entra no slot do cenário.")
			if not str(parsed.get("row", "")) in FIELD_ROWS:
				return _fail("fileira_invalida",
						"Fileira inválida: " + str(parsed.get("row", "")))
			if int(parsed.get("column", 0)) < 1:
				return _fail("coluna_invalida", "A coluna começa em 1.")
			var occupant = state.card_at(to)
			if not occupant.is_empty() and occupant != str(normalized["card"]):
				return _fail("slot_ocupado", "O slot " + to + " já está ocupado.")
		"scenario":
			if card_type != "Cenário":
				return _fail("cenario_exige_cenario",
						"Só uma carta de cenário entre em " + SCENARIO_ADDRESS
						+ ".")
			var current = state.card_at(SCENARIO_ADDRESS)
			if not current.is_empty() and current != str(normalized["card"]):
				# Replacing is allowed; the action sends the old one to the
				# owner's resources, as the confirmed rule says.
				normalized["replaces"] = current
		_:
			return _fail("destino_invalido",
					"Destino inválido para jogar: " + to)
	if bool(context.get("enforce_cost", false)):
		var cost := int(entry.get("cost", 0))
		var available: int = state.resource_count(seat)
		if cost > available:
			return _fail("recursos_insuficientes",
					"A carta custa " + str(cost) + " e há só "
					+ str(available) + " recurso(s).")
	normalized["to"] = to
	return _ok(normalized)


func _validate_attach(state, normalized : Dictionary) -> Dictionary:
	var entry := _entry_of(state, normalized)
	if entry.is_empty():
		return _fail("carta_desconhecida", "A carta não está na mesa.")
	var zone := str(entry["zone"])
	if not zone in ["hand", "field", "attachment"]:
		return _fail("origem_invalida",
				"Anexos vêm da mão, do campo ou de outro anexo.")
	var card_type := str(entry.get("type", ""))
	if card_type == "Cenário":
		return _fail("carta_nao_anexavel", "Um cenário não pode ser anexado.")
	if zone == "field" and card_type == "Personagem":
		return _fail("carta_nao_anexavel",
				"Um personagem não pode ser anexado a outra carta.")
	var host_id := str(normalized.get("host", ""))
	if host_id.is_empty() or not state.cards.has(host_id):
		return _fail("hospedeiro_desconhecido", "Hospedeiro desconhecido.")
	if host_id == str(normalized["card"]):
		return _fail("anexo_em_si", "Uma carta não pode ser anexada a si mesma.")
	var host: Dictionary = state.cards[host_id]
	if str(host["zone"]) != "field":
		return _fail("hospedeiro_fora_do_campo",
				"O hospedeiro precisa estar na cena.")
	if int(host["seat"]) != int(normalized["seat"]):
		return _fail("fora_do_seu_assento",
				"O hospedeiro é do assento P" + str(host["seat"]) + ".")
	normalized["host"] = host_id
	normalized["to"] = ""
	return _ok(normalized)


func _validate_move(state, normalized : Dictionary) -> Dictionary:
	var entry := _entry_of(state, normalized)
	if entry.is_empty():
		return _fail("carta_desconhecida", "A carta não está na mesa.")
	if str(entry["zone"]) == "deck":
		return _fail("carta_no_deck",
				"Cartas no deck só saem por compra ou topo para recursos.")
	var to := str(normalized.get("to", ""))
	var parsed := _Table.parse_address(to)
	if parsed.is_empty():
		return _fail("destino_invalido", "Destino inválido: " + to)
	var seat := int(normalized["seat"])
	match str(parsed.get("kind", "")):
		"hand":
			if int(parsed["seat"]) != seat:
				return _fail("destino_de_outro_assento",
						"A mão de destino é do assento P"
						+ str(parsed["seat"]) + ".")
			var hand_size: int = state.hand_count(seat)
			if int(parsed["slot"]) < 1 or int(parsed["slot"]) > hand_size + 1:
				return _fail("slot_invalido",
						"O slot da mão vai de 1 a " + str(hand_size + 1) + ".")
		"resources":
			if int(parsed["seat"]) != seat:
				return _fail("destino_de_outro_assento",
						"Os recursos de destino são do assento P"
						+ str(parsed["seat"]) + ".")
			# Resources are a pile: a card always enters on top, which the
			# snapshot numbers as recursos:1.
			if int(parsed["slot"]) != 1:
				return _fail("slot_invalido",
						"Os recursos recebem cartas no topo (recursos:1).")
		"prizes":
			if int(parsed["seat"]) != seat:
				return _fail("destino_de_outro_assento",
						"Os prêmios de destino são do assento P"
						+ str(parsed["seat"]) + ".")
			# Prizes are stacked as well: the new card becomes the top one.
			if int(parsed["slot"]) != 1:
				return _fail("slot_invalido",
						"Os prêmios recebem cartas no topo (prêmios:1).")
		"field":
			if int(parsed["seat"]) != seat:
				return _fail("destino_de_outro_assento",
						"O campo de destino é do assento P"
						+ str(parsed["seat"]) + ".")
			if str(entry.get("type", "")) == "Cenário":
				return _fail("cenario_exige_cenario",
						"Um cenário só entra no slot do cenário.")
			if not str(parsed.get("row", "")) in FIELD_ROWS:
				return _fail("fileira_invalida",
						"Fileira inválida: " + str(parsed.get("row", "")))
			if int(parsed.get("column", 0)) < 1:
				return _fail("coluna_invalida", "A coluna começa em 1.")
			var occupant = state.card_at(to)
			if not occupant.is_empty() and occupant != str(normalized["card"]):
				return _fail("slot_ocupado", "O slot " + to + " já está ocupado.")
		"scenario":
			if str(entry.get("type", "")) != "Cenário":
				return _fail("cenario_exige_cenario",
						"Só uma carta de cenário entra em " + SCENARIO_ADDRESS + ".")
			var current = state.card_at(SCENARIO_ADDRESS)
			if not current.is_empty() and current != str(normalized["card"]):
				return _fail("use_jogar",
						"Para trocar o cenário ativo, use jogar.")
		"attachment":
			var host_id = state.card_at(str(parsed.get("host_address", "")))
			if host_id.is_empty():
				return _fail("hospedeiro_desconhecido",
						"O hospedeiro do anexo não está na mesa.")
			if int(state.cards[host_id]["seat"]) != seat:
				return _fail("fora_do_seu_assento",
						"O hospedeiro é do assento P"
						+ str(state.cards[host_id]["seat"]) + ".")
		"transit":
			return _fail("destino_invalido", "Uma carta não fica em trânsito.")
		_:
			return _fail("destino_invalido", "Destino inválido: " + to)
	normalized["to"] = to
	return _ok(normalized)


func _validate_discard(state, normalized : Dictionary) -> Dictionary:
	var entry := _entry_of(state, normalized)
	if entry.is_empty():
		return _fail("carta_desconhecida", "A carta não está na mesa.")
	if not str(entry["zone"]) in ["hand", "field", "attachment", "scenario",
			"prizes"]:
		return _fail("origem_invalida", "Essa carta não pode ser descartada.")
	normalized["to"] = _Table.resource_address(int(normalized["seat"]), 1)
	return _ok(normalized)


func _validate_wound(state, normalized : Dictionary) -> Dictionary:
	var entry := _entry_of(state, normalized)
	if entry.is_empty():
		return _fail("carta_desconhecida", "A carta não está na mesa.")
	if str(entry["zone"]) != "field":
		return _fail("fora_do_campo", "Só uma carta na cena pode levar dano.")
	if str(entry.get("type", "")) != "Personagem":
		return _fail("tipo_invalido", "Só personagens levam dano.")
	var amount := int(normalized.get("amount", 1))
	if amount < 1:
		return _fail("quantidade_invalida", "O dano precisa ser pelo menos 1.")
	normalized["amount"] = amount
	return _ok(normalized)


func _validate_knockout(state, normalized : Dictionary) -> Dictionary:
	var entry := _entry_of(state, normalized)
	if entry.is_empty():
		return _fail("carta_desconhecida", "A carta não está na mesa.")
	if str(entry["zone"]) != "field":
		return _fail("fora_do_campo", "Só uma carta na cena pode ser nocauteada.")
	if not str(entry.get("type", "")) in KNOCKOUT_TYPES:
		return _fail("tipo_invalido",
				"Só personagens e suportes podem ser nocauteados.")
	return _ok(normalized)


func _validate_send_prizes(state, normalized : Dictionary,
		context : Dictionary) -> Dictionary:
	var entry := _entry_of(state, normalized)
	if entry.is_empty():
		return _fail("carta_desconhecida", "A carta não está na mesa.")
	if str(entry["zone"]) != "field":
		return _fail("fora_do_campo", "Só uma carta na cena vai aos prêmios.")
	if str(entry.get("type", "")) != "Personagem":
		return _fail("tipo_invalido", "Só personagens vão aos prêmios.")
	if not bool(context.get("active", false)):
		return _fail("sem_partida",
				"Prêmios do adversário só existem em partida.")
	return _ok(normalized)


func _validate_shield(state, normalized : Dictionary) -> Dictionary:
	var entry := _entry_of(state, normalized)
	if entry.is_empty():
		return _fail("carta_desconhecida", "A carta não está na mesa.")
	if str(entry["zone"]) != "field":
		return _fail("fora_do_campo", "Só uma carta na cena tem escudo.")
	var amount := int(normalized.get("amount", 0))
	if amount == 0:
		return _fail("quantidade_invalida", "O ajuste de escudo não pode ser 0.")
	var current := int(entry.get("shield", 0))
	if current + amount < 0:
		return _fail("escudo_negativo",
				"A carta tem só " + str(current) + " escudo(s).")
	normalized["amount"] = amount
	return _ok(normalized)


func _validate_flip(state, normalized : Dictionary) -> Dictionary:
	var entry := _entry_of(state, normalized)
	if entry.is_empty():
		return _fail("carta_desconhecida", "A carta não está na mesa.")
	if str(entry["zone"]) == "transit":
		return _fail("destino_invalido", "Uma carta em trânsito não vira.")
	return _ok(normalized)


func _validate_rotate(state, normalized : Dictionary) -> Dictionary:
	var entry := _entry_of(state, normalized)
	if entry.is_empty():
		return _fail("carta_desconhecida", "A carta não está na mesa.")
	if str(entry["zone"]) != "field":
		return _fail("fora_do_campo", "Só uma carta na cena gira.")
	if str(entry.get("type", "")) == "Personagem":
		return _fail("tipo_invalido",
				"Personagens usam capacitar/incapacitar, não girar.")
	var degree := int(normalized.get("degree", 90))
	if not degree in [90, 180, 270]:
		return _fail("angulo_invalido",
				"O giro precisa ser 90, 180 ou 270 graus.")
	normalized["degree"] = degree
	return _ok(normalized)


func _validate_stage(state, normalized : Dictionary, step : int) -> Dictionary:
	var entry := _entry_of(state, normalized)
	if entry.is_empty():
		return _fail("carta_desconhecida", "A carta não está na mesa.")
	if str(entry["zone"]) != "field":
		return _fail("fora_do_campo", "Só uma carta na cena muda de estado.")
	if str(entry.get("type", "")) != "Personagem":
		return _fail("tipo_invalido", "Só personagens têm estado de cena.")
	var stage := _stage_of(int(entry.get("rotation", 0)))
	if stage < -1 or stage > 1:
		return _fail("estado_invalido", "Rotação de personagem desconhecida.")
	if step > 0 and stage > 0:
		return _fail("estado_invalido", "A carta já está capacitada.")
	if step < 0 and stage < 0:
		return _fail("estado_invalido", "A carta já está incapacitada.")
	return _ok(normalized)


func _validate_reorder(state, normalized : Dictionary) -> Dictionary:
	var from_slot := int(normalized.get("from", 0))
	var to_slot := int(normalized.get("to_slot", 0))
	var hand_size: int = state.hand_count(int(normalized["seat"]))
	if from_slot < 1 or from_slot > hand_size:
		return _fail("slot_invalido",
				"O slot de origem vai de 1 a " + str(hand_size) + ".")
	if to_slot < 1 or to_slot > hand_size:
		return _fail("slot_invalido",
				"O slot de destino vai de 1 a " + str(hand_size) + ".")
	if from_slot == to_slot:
		return _fail("ordem_igual", "A carta já está nesse slot.")
	normalized["from"] = from_slot
	normalized["to_slot"] = to_slot
	return _ok(normalized)


func _validate_shuffle(state, normalized : Dictionary) -> Dictionary:
	var pile := str(normalized.get("pile", "deck"))
	if not pile in ["deck", "hand"]:
		return _fail("pilha_invalida", "Só o deck ou a mão podem ser embaralhados.")
	normalized["pile"] = pile
	return _ok(normalized)


func _validate_undo(normalized : Dictionary, context : Dictionary) -> Dictionary:
	var entry = context.get("undo_entry", null)
	if not (entry is Dictionary) or entry.is_empty():
		return _fail("nada_para_desfazer", "Não há ação para desfazer.")
	if not bool(entry.get("undoable", false)):
		return _fail("acao_nao_desfazivel",
				str(entry.get("undo_reason", "Essa ação não pode ser desfeita.")))
	normalized["entry"] = entry
	return _ok(normalized)


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# The address where a card from the hand would land. The state is not changed:
# when both rows are full, the next free column is returned and the action grows
# the grid before moving the card.
func _next_field_address(state, seat : int, prefer_back : bool) -> String:
	var address: String = state.find_field_slot(seat, prefer_back, false)
	if not address.is_empty():
		return address
	return _Table.field_address(seat, "frente", int(state.columns) + 1)


func _entry_of(state, normalized : Dictionary) -> Dictionary:
	return state.cards.get(str(normalized.get("card", "")), {})


func _stage_of(rotation : int) -> int:
	match rotation:
		-90:
			return -1
		0:
			return 0
		90:
			return 1
	return -2


func _ok(intent : Dictionary) -> Dictionary:
	return {"ok": true, "error": "", "message": "", "intent": intent}


func _fail(code : String, message : String) -> Dictionary:
	return {"ok": false, "error": code, "message": message, "intent": {}}
