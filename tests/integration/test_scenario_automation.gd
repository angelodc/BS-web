extends "res://tests/UTcommon.gd"

# Automação dos cenários reais.
#
# O tabuleiro de teste usa o mesmo `CGFBoard` do jogo, então cada `apply()`
# passa pelo gancho pós-intenção de verdade. O resto — escolher, comprar, mover
# — é o mesmo caminho dos botões e do arrasto.

const Actions = preload("res://src/core/table/TableActions.gd")
const Snapshot = preload("res://src/core/table/TableSnapshot.gd")
const Automation = preload("res://src/custom/cards/ScenarioAutomation.gd")
const Catalog = preload("res://src/custom/cards/ScenarioCatalog.gd")
const SCENARIO_GRID_SCENE = preload("res://src/custom/CGFModifiedLabelGrid.tscn")

var actions


func before_each():
	await setup_board()
	var scenario_grid: BoardPlacementGrid = SCENARIO_GRID_SCENE.instantiate()
	scenario_grid.name = "ModifiedLabelGrid"
	board.add_child(scenario_grid)
	scenario_grid.add_slot()
	actions = Actions.new(board, 1)
	GameEvents.set_enabled(true)


func after_each():
	GameEvents.set_enabled(false)
	GameEvents.entries.clear()


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

func _scenario(bsdb_id: String) -> Card:
	var card: Card = cfc.instance_card("Demo Scenario")
	hand.add_child(card)
	card.properties["_bsdb_id"] = bsdb_id
	card.properties["Name"] = str(Catalog.BY_ID[bsdb_id]["name"])
	return card


func _character(affiliation: String) -> Card:
	var card: Card = draw_test_cards(1)[0]
	card.properties["_tipo"] = "Personagem"
	card.properties["Requirements"] = affiliation
	card.properties["ENERGIA"] = "0"
	return card


func _place_character(affiliation: String) -> Card:
	var card := _character(affiliation)
	var result = actions.apply({"op": "jogar", "card": card})
	assert_true(bool(result.get("ok", false)), str(result))
	return card


func _play(card: Card) -> Dictionary:
	var result = actions.apply({"op": "jogar", "card": card})
	assert_true(bool(result.get("ok", false)), str(result))
	return result


func _deck_count() -> int:
	actions.sync()
	return int(actions.state.zone_counts(1)["deck"])


func _hand_count() -> int:
	actions.sync()
	return int(actions.state.zone_counts(1)["hand"])


func _resource_count() -> int:
	actions.sync()
	return int(actions.state.zone_counts(1)["resources"])


func _effects() -> Array:
	var found := []
	for entry in GameEvents.entries:
		if str(entry.get("action", "")) == "scenario_effect":
			found.append(entry)
	return found


func _last_effect_text() -> String:
	var effects := _effects()
	if effects.is_empty():
		return ""
	return str(effects.back()["text"])


func _has_action(action: String) -> bool:
	for entry in GameEvents.entries:
		if str(entry.get("action", "")) == action:
			return true
	return false


# The test board is a reduced copy of the game board and has no message line.
# The tests add the same label the board looks up, so the feedback path runs as
# it does in the game.
func _message_label() -> Label:
	var label: Label = board.get_node_or_null("ResourceSelectionLabel")
	if label == null:
		label = Label.new()
		label.name = "ResourceSelectionLabel"
		board.add_child(label)
	return label


# -----------------------------------------------------------------------------
# Catálogo
# -----------------------------------------------------------------------------

func test_catalog_covers_every_real_scenario():
	assert_eq(Catalog.BY_ID.size(), 288,
			"Todos os cards de Cenário do BSDB estão no catálogo")
	for id in ["BSCA_069", "BSCA_076", "BSCA_080", "BSCA_082", "BSCA_079",
			"BSET_056", "BSET_058", "BSFE_064", "BSFE_073", "BSOS_058"]:
		assert_true(Catalog.BY_ID.has(id), "Falta o cenário " + id)
		assert_false(str(Catalog.BY_ID[id].get("name", "")).is_empty(),
				"O cenário " + id + " precisa do nome impresso")


# A demo card is not in the catalog; a real one is. The id wins over the
# printed name because nine duplicated names carry different texts.
func test_catalog_matches_the_definition_id():
	var card := _scenario("BSCA_069")
	assert_eq(str(Catalog.entry_for(card).get("name", "")), "Aranhaverso")
	card.properties["_bsdb_id"] = "X_SEM_DEFINICAO"
	card.properties["Name"] = "Desfechos Paralelos"
	assert_eq(str(Catalog.entry_for(card).get("name", "")), "Desfechos Paralelos",
			"Sem o id o nome impresso resolve a entrada")


# Everything the table cannot resolve ends up in `pending`, which the HUD shows
# in yellow; the fully automated ones have no pending fragment.
func test_pending_fragments_are_listed_for_the_manual_parts():
	var venom := _scenario("BSCA_082")
	var parallel := _scenario("BSOS_058")
	assert_true(Catalog.pending_of(venom).is_empty(),
			"Venomverso é compra na entrada e opções na carta")
	assert_true(Catalog.pending_of(parallel).is_empty(),
			"Desfechos Paralelos é totalmente automático")


# -----------------------------------------------------------------------------
# Entrada e saída de cena
# -----------------------------------------------------------------------------

func test_entering_draws_one_and_logs_the_scenario_name():
	var card := _scenario("BSCA_069")
	var deck_before := _deck_count()
	var hand_before := _hand_count()

	_play(card)

	assert_eq(_deck_count(), deck_before - 1, "A entrada compra uma carta")
	assert_eq(_hand_count(), hand_before, "A mão troca o cenário pela compra")
	var effects := _effects()
	assert_eq(effects.size(), 1, "Uma linha para a compra automática")
	assert_eq(str(effects[0]["card"]), "Aranhaverso",
			"A linha traz o nome do cenário")
	var text := str(effects[0]["text"])
	assert_true(text.find("Aranhaverso") >= 0, text)
	assert_true(text.find("comprou 1 carta (entrada)") >= 0, text)
	assert_false(_has_action("drew"),
			"A compra aninhada não vira uma segunda linha")


func test_entering_mills_two_to_resources():
	var card := _scenario("BSOS_058")
	var deck_before := _deck_count()
	var resources_before := _resource_count()

	_play(card)

	assert_eq(_deck_count(), deck_before - 2, "A entrada manda duas ao topo")
	assert_eq(_resource_count(), resources_before + 2,
			"As duas cartas chegam aos recursos")
	assert_true(_last_effect_text().find(
			"colocou 2 cartas do topo do deck nos recursos (entrada)") >= 0,
			_last_effect_text())


func test_leaving_draws_for_the_owner():
	var card := _scenario("BSOS_058")
	_play(card)
	var deck_before := _deck_count()

	var result = actions.apply({"op": "descartar", "card": card})
	assert_true(bool(result.get("ok", false)), str(result))

	assert_eq(_deck_count(), deck_before - 1, "Sair de cena compra uma carta")
	assert_true(_last_effect_text().find("comprou 1 carta (saída)") >= 0,
			_last_effect_text())


func test_replacement_resolves_the_old_scenario_before_the_new_one():
	var old := _scenario("BSOS_058")
	_play(old)
	# A entrada do antigo já cumpriu seu papel; o teste olha só a troca.
	GameEvents.entries.clear()
	var new := _scenario("BSCA_069")
	var deck_before := _deck_count()

	_play(new)

	# Duas compras: a saída do antigo e a entrada do novo.
	assert_eq(_deck_count(), deck_before - 2, "Saída e entrada compram")
	var effects := _effects()
	assert_eq(effects.size(), 2, "Uma linha por cenário")
	var leave := str(effects[0]["text"])
	var enter := str(effects[1]["text"])
	assert_true(leave.find("Desfechos Paralelos") >= 0 and leave.find("saída") >= 0,
			leave)
	assert_true(enter.find("Aranhaverso") >= 0 and enter.find("entrada") >= 0,
			enter)
	assert_eq(old.get_parent(), discard, "O antigo foi para os recursos do dono")
	assert_eq(new.get_parent(), board, "O novo ocupa o slot do cenário")


func test_demo_scenarios_are_ignored():
	var card: Card = cfc.instance_card("Demo Scenario")
	hand.add_child(card)
	var deck_before := _deck_count()

	var result = actions.apply({"op": "jogar", "card": card})
	assert_true(bool(result.get("ok", false)), str(result))

	assert_eq(_deck_count(), deck_before, "Cenário de demonstração não compra")
	assert_eq(_effects().size(), 0, "E não gera linha de automação")
	assert_true(Catalog.entry_for(card).is_empty(),
			"O catálogo não conhece a demonstração")
	assert_false(Automation.can_choose(board, card, actions),
			"Sem opções no cenário de demonstração")


# -----------------------------------------------------------------------------
# Opções
# -----------------------------------------------------------------------------

# O primeiro momento não checa as condições impressas: com o cenário na área de
# cenário as duas opções ficam prontas e o texto da carta vai no tooltip.
func test_choice_scenario_offers_a_and_b():
	var card := _scenario("BSCA_079")
	_play(card)

	assert_true(Automation.can_choose(board, card, actions),
			"A escolha aparece na entrada")
	var a: Dictionary = Automation.option_for(card, "A")
	var b: Dictionary = Automation.option_for(card, "B")
	assert_false(a.is_empty(), "A opção A existe")
	assert_false(b.is_empty(), "A opção B existe")
	assert_true(Automation.option_hint(a).find("Compre um card") >= 0,
			Automation.option_hint(a))
	assert_true(Automation.option_hint(b).find("afiliação em comum") >= 0,
			Automation.option_hint(b))


func test_option_a_draws_and_spends_the_choice():
	var card := _scenario("BSCA_079")
	_play(card)
	var deck_before := _deck_count()

	var result := Automation.use_option(board, card, "A", actions)

	assert_true(bool(result.get("ok", false)), str(result))
	assert_eq(_deck_count(), deck_before - 1, "A opção A compra uma carta")
	assert_false(Automation.can_choose(board, card, actions),
			"A escolha é usada uma vez só")
	var text := _last_effect_text()
	assert_true(text.find("Reforços Aliados — opção A: comprou 1 carta") >= 0,
			text)


func test_option_b_opens_without_the_printed_condition():
	var card := _scenario("BSCA_079")
	_play(card)
	var result := Automation.use_option(board, card, "B", actions)

	assert_true(bool(result.get("ok", false)), str(result))
	assert_true(bool(result.get("manual", false)), "A busca continua manual")
	assert_true(str(result.get("message", "")).find("aquela afiliação") >= 0,
			str(result.get("message", "")))
	assert_true(_last_effect_text().find("opção B") >= 0, _last_effect_text())
	assert_false(Automation.can_choose(board, card, actions),
			"A escolha é usada uma vez só")


func test_buttons_on_the_scenario_card_resolve_the_options():
	var card := _scenario("BSCA_079")
	_play(card)
	var deck_before := _deck_count()

	card.buttons.set_active(true)
	var button_a: Button = card.buttons.get_node_or_null("ScenarioA")
	var button_b: Button = card.buttons.get_node_or_null("ScenarioB")
	assert_not_null(button_a, "O menu do cenário tem o botão A")
	assert_not_null(button_b, "O menu do cenário tem o botão B")
	assert_true(button_a.visible, "O botão A aparece na entrada")
	assert_true(button_b.visible, "O botão B aparece na entrada")
	assert_false(button_b.disabled, "B fica pronto mesmo sem a condição")
	assert_false(card.buttons.has_node("Flip"),
			"O menu do cenário não oferece Flip")
	assert_false(card.buttons.get_node("Rot90").visible,
			"O menu do cenário não oferece giro")

	button_a.pressed.emit()
	await yield_for(0.1)

	assert_eq(_deck_count(), deck_before - 1, "O clique em A compra uma carta")
	assert_false(Automation.can_choose(board, card, actions),
			"O clique consome a escolha")
	assert_true(_last_effect_text().find("opção A: comprou 1 carta") >= 0,
			_last_effect_text())


func test_scenario_option_buttons_receive_a_mouse_click():
	var card := _scenario("BSCA_079")
	_play(card)
	var deck_before := _deck_count()

	# The option buttons only exist while the card is the focused scenario. The
	# drop tween has to finish first: until it does the card is still
	# DROPPING_TO_BOARD and the hover does not focus it.
	await yield_for(0.8)
	await move_mouse(card.global_position + Vector2(30, 30))
	await yield_for(0.2)

	var button_a: Button = card.buttons.get_node_or_null("ScenarioA")
	assert_eq(board.mouse_pointer.current_focused_card, card,
			"O cenário está sob o mouse")
	assert_not_null(button_a, "O menu do cenário tem o botão A")
	assert_true(button_a.visible, "O botão A aparece com o cenário focado")

	# The menu is drawn on the card, inside its collision shape, so the pointer
	# never leaves the card on the way to a button. The focus has to survive the
	# GUI hover moving onto the button, otherwise the menu closes mid-click.
	var centre: Vector2 = button_a.get_global_rect().get_center()
	await move_mouse(centre)
	await yield_for(0.2)
	assert_true(card in board.mouse_pointer.overlaps,
			"O botão A fica dentro da área do cenário")
	assert_eq(board.mouse_pointer.current_focused_card, card,
			"O menu mantém o cenário em foco")
	assert_eq(card.state, Card.CardState.FOCUSED_ON_BOARD,
			"O cenário continua focado com o ponteiro no menu")
	assert_true(card.buttons._are_active, "O menu continua ativo")
	assert_true(button_a.visible, "O botão A continua pronto para o clique")

	var vp: Viewport = button_a.get_viewport()
	var motion := InputEventMouseMotion.new()
	motion.position = centre
	motion.global_position = centre
	vp.push_input(motion, true)
	await yield_for(0.05)

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = centre
	down.global_position = centre
	vp.push_input(down, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = centre
	up.global_position = centre
	vp.push_input(up, true)
	await yield_for(0.2)

	assert_eq(_deck_count(), deck_before - 1,
			"O clique de mouse no botão A compra uma carta")


# The printed timing ("quando um personagem com a afiliação entrar em cena") is
# checked: the option waits for someone with the affiliation on the field.
func test_affiliation_scenario_waits_for_its_affiliation():
	var card := _scenario("BSCA_069")
	_play(card)

	assert_false(Automation.can_choose(board, card, actions),
			"A escolha não aparece sem ninguém com a afiliação")
	_place_character("Simbiontes")
	assert_false(Automation.can_choose(board, card, actions),
			"Outra afiliação não libera a escolha")

	_place_character("Aliados do Homem-Aranha")
	assert_true(Automation.can_choose(board, card, actions),
			"O Aliado do Homem-Aranha libera a escolha")
	assert_true(Automation.label_available(board, card, "A", actions),
			"A opção A fica pronta com a condição atendida")


func test_affiliation_scenario_option_moves_itself_to_resources():
	var card := _scenario("BSCA_069")
	_play(card)
	_place_character("Aliados do Homem-Aranha")
	var deck_before := _deck_count()

	var result := Automation.use_option(board, card, "A", actions)

	assert_true(bool(result.get("ok", false)), str(result))
	assert_eq(card.get_parent(), discard,
			"O cenário foi para os recursos do dono")
	assert_eq(_deck_count(), deck_before - 2, "A opção A manda duas ao topo")
	var text := _last_effect_text()
	assert_true(text.find(
			"Aranhaverso — opção A: colocou o cenário nos recursos e colocou "
			+ "2 cartas do topo do deck nos recursos") >= 0, text)


# O efeito precisa ter prova visível: o clique resolve a opção e a linha de
# mensagem da mesa conta o que aconteceu.
func test_option_click_reports_the_effect_on_the_table():
	var card := _scenario("BSCA_079")
	_play(card)
	var deck_before := _deck_count()
	var label := _message_label()

	card.buttons.set_active(true)
	var button_a: Button = card.buttons.get_node_or_null("ScenarioA")
	assert_not_null(button_a, "O menu do cenário tem o botão A")
	button_a.pressed.emit()
	await yield_for(0.1)

	assert_true(label.text.find("opção A: comprou 1 carta") >= 0, label.text)
	assert_eq(_deck_count(), deck_before - 1, "A opção A compra uma carta")


# A busca da opção B continua manual, mas a mesa diz o que fazer em vez de
# deixar só a linha do painel de registro.
func test_manual_option_tells_the_player_what_to_do():
	var card := _scenario("BSCA_069")
	_play(card)
	_place_character("Aliados do Homem-Aranha")
	var label := _message_label()

	card.buttons.set_active(true)
	var button_b: Button = card.buttons.get_node_or_null("ScenarioB")
	assert_not_null(button_b, "O menu do cenário tem o botão B")
	button_b.pressed.emit()
	await yield_for(0.1)

	assert_true(label.text.find("procurar em seu deck") >= 0, label.text)
	assert_eq(card.get_parent(), discard,
			"O cenário foi para os recursos, como a carta manda")


# The parts the table cannot resolve are announced in yellow, with the tone
# kept on the event so the HUD can colour the line.
func test_pending_fragments_are_logged_in_yellow():
	var card := _scenario("BSET_058")
	_play(card)

	var pending := []
	for entry in GameEvents.entries:
		if str(entry.get("action", "")) == "scenario_effect" \
				and str(entry.get("tone", "")) == "pending":
			pending.append(str(entry.get("text", "")))
	assert_eq(pending.size(), 1, "Uma pendência do cenário entrou no log")
	assert_true(pending[0].find("Genialidade") >= 0, pending[0])
	assert_true(pending[0].find("Múltiplas Opções") >= 0, pending[0])


# A condition the table can check is honoured: the draw only happens with the
# affiliation on the field.
func test_simple_conditions_are_checked():
	var card := _scenario("BSCA_069")
	_play(card)
	var runner = actions

	assert_false(Automation.condition_met(runner, 1, {
		"type": "characters", "min": 1,
	}), "O campo vazio não satisfaz a contagem")
	assert_false(Automation.condition_met(runner, 1, {
		"type": "affiliation", "value": "Simbiontes", "min": 1,
	}), "Sem Simbiontes no campo a condição falha")
	_place_character("Simbiontes")
	assert_true(Automation.condition_met(runner, 1, {
		"type": "characters", "min": 1,
	}), "Um personagem no campo satisfaz a contagem")
	assert_true(Automation.condition_met(runner, 1, {
		"type": "affiliation", "value": "Simbiontes", "min": 1,
	}), "O Simbionte atende a condição de afiliação")
	assert_false(Automation.condition_met(runner, 1, {
		"type": "affiliation", "value": "Simbiontes", "min": 2,
	}), "A contagem mínima é respeitada")
