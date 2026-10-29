extends "res://tests/UTcommon.gd"

var cards := []
var grid : BoardPlacementGrid

func before_each():
	var confirm_return = setup_board()
	if confirm_return is GDScriptFunctionState: # Still working.
		confirm_return = yield(confirm_return, "completed")
	board.get_node("BoardPlacementGrid").visible = true
	cards = draw_test_cards(5)
	yield(yield_for(0.1), YIELD)
	grid = board.get_node("BoardPlacementGrid")
	grid.rect_position = Vector2(200,200)
	grid.visible = true

func test_placement_slots():
	var card = cards[1]
	yield(drag_card(card, Vector2(250,300)), 'completed')
	assert_eq(grid.get_highlighted_slot(), grid.get_slot(0),
			"First slot highlighted")
	assert_eq(grid.highlight,
			grid.get_slot(0).get_node("Highlight").modulate,
			"slot highlight matches the var of the grid container")
	yield(move_mouse(Vector2(350,300)), 'completed')
	assert_eq(grid.get_highlighted_slot(), grid.get_slot(1),
			"Second slot highlighted")
	grid.highlight = CFConst.TARGET_HOVER_COLOUR
	yield(move_mouse(Vector2(420,300)), 'completed')
	assert_eq(grid.get_highlighted_slot(), grid.get_slot(2),
			"Third slot highlighted")
	assert_eq(CFConst.TARGET_HOVER_COLOUR,
			grid.get_slot(2).get_node("Highlight").modulate,
			"Third slot highlighted with new colour")
	yield(move_mouse(Vector2(560,300)), 'completed')
	assert_eq(grid.get_highlighted_slot(), grid.get_slot(3),
			"Fourth slot highlighted")
	yield(move_mouse(Vector2(250,300)), 'completed')
	assert_eq(grid.get_highlighted_slot(), grid.get_slot(0),
			"First slot highlighted again")
	assert_eq(grid.highlight,
			grid.get_slot(0).get_node("Highlight").modulate,
			"First slot highlighted with new colour")
	drop_card(card,board._UT_mouse_position)
	yield(yield_to(card._tween, "tween_all_completed", 0.5), YIELD)
	assert_almost_eq(grid.get_slot(0).rect_global_position, card.global_position, Vector2(2,2),
			"Card moved to the slot placement")
	assert_eq(card._placement_slot, grid.get_slot(0),
			"card refers to its placement slot")
	assert_eq(grid.get_slot(0).occupying_card, card,
			"placement slot refers to the card")
	yield(drag_drop(card,Vector2(420,300)), 'completed')
	assert_eq(card._placement_slot, grid.get_slot(2),
			"card refers to  newplacement slot")
	assert_null(grid.get_slot(0).occupying_card,
			"old placement slot cleared reference")
	assert_eq(grid.get_slot(2).occupying_card, card,
			"new placement slot refers to the card")
	yield(drag_drop(card,Vector2(1000,300)), 'completed')
	assert_null(card._placement_slot,
			"card placement slot cleared when dropping to the table")
	assert_null(grid.get_slot(2).occupying_card,
			"placement slot clears reference to the card")
	yield(drag_drop(card,Vector2(420,300)), 'completed')
	yield(drag_drop(card,Vector2(500,600)), 'completed')
	assert_null(card._placement_slot,
			"card placement slot cleared when dropping to the hand")
	assert_null(grid.get_slot(2).occupying_card,
			"placement slot clears reference to the card after dropping to hand")

func test_any_grid_placement():
	var card: Card = cards[0]
	card.board_placement = Card.BoardPlacement.ANY_GRID
	yield(drag_drop(card,Vector2(1000,300)), 'completed')
	assert_eq(card.get_parent(), hand,
		"Card not moved to board")
	yield(move_mouse(Vector2(300,200)), 'completed')
	yield(drag_drop(card,Vector2(420,300)), 'completed')
	assert_eq(card.get_parent(), board,
		"Card moved to board")
	yield(drag_drop(card,Vector2(1000,300)), 'completed')
	yield(yield_to(card._tween, "tween_all_completed", 0.5), YIELD)
	assert_almost_eq(grid.get_slot(2).rect_global_position, card.global_position, Vector2(2,2),
			"Card returned back to the slot")

func test_specific_grid_placement():
	var card: Card = cards[0]
	card.board_placement = Card.BoardPlacement.SPECIFIC_GRID
	card.mandatory_grid_name = "GUT Grid"
	yield(drag_drop(card,Vector2(1000,300)), 'completed')
	assert_eq(card.get_parent(), hand,
		"Card not moved to board")
	yield(move_mouse(Vector2(300,200)), 'completed')
	yield(drag_drop(card,Vector2(500,300)), 'completed')
	assert_eq(card.get_parent(), hand,
		"Card not moved to wrong grid name")
	card.mandatory_grid_name = grid.name_label.text
	yield(move_mouse(Vector2(300,200)), 'completed')
	yield(drag_drop(card,Vector2(500,300)), 'completed')
	yield(yield_to(card._tween, "tween_all_completed", 0.5), YIELD)
	assert_eq(card.get_parent(), board,
		"Card moved to correct grid name")


func test_occupied_slot():
	var card: Card = cards[0]
	card.board_placement = Card.BoardPlacement.ANY_GRID
	yield(drag_drop(card,Vector2(500,300)), 'completed')
	assert_eq(card.get_parent(), board,
		"Card moved to board")
	card = cards[3]
	card.board_placement = Card.BoardPlacement.ANY_GRID
	yield(drag_card(card, Vector2(500,300)), 'completed')
	assert_null(grid.get_highlighted_slot(),"No slot highlighted")
	drop_card(card,board._UT_mouse_position)
	yield(yield_to(card._tween, "tween_all_completed", 0.5), YIELD)
	assert_eq(card.get_parent(), hand,
		"Card not moved to board when slot is occupied")


func test_scenario_replaces_active_scenario():
	grid.name_label.text = "Cenário Ativo"
	var first_scenario: Card = cards[0]
	var replacement_scenario: Card = cards[1]
	first_scenario.properties["_tipo"] = "Cenário"
	replacement_scenario.properties["_tipo"] = "Cenário"

	yield(drag_drop(first_scenario, Vector2(250,300)), "completed")
	assert_eq(first_scenario.get_parent(), board,
			"First scenario is placed on the board")
	assert_eq(grid.get_slot(0).occupying_card, first_scenario,
			"Active scenario slot references the first scenario")

	yield(drag_drop(replacement_scenario, Vector2(250,300)), "completed")
	assert_eq(first_scenario.get_parent(), discard,
			"Previous scenario moves to the discard pile")
	assert_eq(replacement_scenario.get_parent(), board,
			"Replacement scenario is placed on the board")
	assert_eq(grid.get_slot(0).occupying_card, replacement_scenario,
			"Active scenario slot references the replacement")


func test_invalid_scenario_drop_returns_to_hand():
	grid.name_label.text = "Cenário Ativo"
	var scenario: Card = cards[0]
	scenario.properties["_tipo"] = "Cenário"

	yield(drag_drop(scenario, Vector2(900,300)), "completed")
	assert_eq(scenario.get_parent(), hand,
			"Scenario stays in hand when dropped outside its active slot")
	assert_eq(scenario.state, Card.CardState.IN_HAND,
			"Rejected scenario drop restores the card state")


func test_move_script_placed_card_out_of_grid():
	yield(yield_for(0.2), YIELD)
	var card: Card = cards[1]
# warning-ignore:unused_variable
	var target: Card
	target = deck.get_card(0)
	card.scripts = {"manual": {"hand": [
			{"name": "move_card_to_board",
			"subject": "self",
			"grid_name":  "BoardPlacementGrid"}]}}
	cards[0].scripts = {"manual": {"hand": [
			{"name": "move_card_to_board",
			"subject": "self",
			"grid_name":  "BoardPlacementGrid"}]}}
	cards[0].execute_scripts()
	yield(yield_for(0.1), YIELD)
	card.execute_scripts()
	yield(yield_to(card._tween, "tween_all_completed", 0.5), YIELD)
	gut.p(card.board_placement)
	yield(drag_drop(card,Vector2(1000,0)), 'completed')
	yield(move_mouse(Vector2(0,0)), 'completed')
	assert_null(card._placement_slot,
			"Card should have moved outside grid slot")

func test_grid_auto_placement():
	for c in cards:
		c.board_placement = Card.BoardPlacement.GRID_AUTOPLACEMENT
		c.mandatory_grid_name = grid.name_label.text
	var card: Card = cards[0]
	card.mandatory_grid_name = "GUT Grid"
	yield(drag_drop(card,Vector2(1000,300)), 'completed')
	assert_eq(card.get_parent(), hand,
		"Card not moved to board")
	yield(move_mouse(Vector2(300,200)), 'completed')
	yield(drag_drop(card,Vector2(500,300)), 'completed')
	assert_eq(card.get_parent(), hand,
		"Card not moved to wrong grid name")
	card.mandatory_grid_name = grid.name_label.text
	yield(move_mouse(Vector2(300,200)), 'completed')
	yield(drag_drop(card,Vector2(1000,300)), 'completed')
	yield(yield_to(card._tween, "tween_all_completed", 0.5), YIELD)
	assert_eq(card.get_parent(), board,
		"Card moved to correct grid name")
	assert_eq(card._placement_slot. get_grid_name(), grid.name_label.text,
		"Card placed in correct grid")
	var prev_slot = card._placement_slot
	yield(drag_drop(card,Vector2(500,300)), 'completed')
	assert_ne(card._placement_slot, prev_slot,
		"Card can be reorganized in the same grid")
	yield(drag_drop(cards[1],Vector2(1000,0)), 'completed')
	yield(move_mouse(Vector2(300,200)), 'completed')
	yield(drag_drop(cards[2],Vector2(1000,0)), 'completed')
	yield(move_mouse(Vector2(300,200)), 'completed')
	yield(drag_drop(cards[3],Vector2(1000,0)), 'completed')
	yield(move_mouse(Vector2(300,200)), 'completed')
	yield(drag_drop(cards[4],Vector2(1000,0)), 'completed')
	assert_eq(cards[1]._placement_slot. get_grid_name(), grid.name_label.text,
		"Card placed in correct grid")
	assert_eq(cards[4].get_parent(), hand,
		"Last card not moved to board because grid is full")
	grid.auto_extend = true
	yield(move_mouse(Vector2(300,200)), 'completed')
	yield(drag_drop(cards[4],Vector2(1000,0)), 'completed')
	assert_eq(cards[4].get_parent(), board,
		"Last card moved to autoextended grid")


func test_scenario_grid_matches_card_size():
	var scenario_grid = add_child_autoqfree(
			load("res://src/custom/CGFModifiedLabelGrid.tscn").instance())
	yield(yield_for(0.1), YIELD)
	# The active scenario uses its own scale so it stays smaller than the
	# regular board cards.
	var card_area: Vector2 = CFConst.CARD_SIZE * CFConst.PLAY_AREA_SCALE
	assert_eq(scenario_grid.name_label.text, "Cenário Ativo",
			"Scenario grid keeps its label")
	assert_eq(scenario_grid.rect_size, card_area,
			"Scenario grid matches the scenario card size")
	assert_eq(scenario_grid.get_slot(0).rect_size, card_area,
			"Scenario slot matches the scenario card size")


func test_scene_grid_is_three_by_two():
	var scene_grid: BoardPlacementGrid = add_child_autoqfree(
			load("res://src/custom/CGFPlacementGridDemo.tscn").instance())
	yield(yield_for(0.1), YIELD)
	var separation: int = int(scene_grid.get_node("GridContainer").get_constant(
			"hseparation"))
	var slot_size: Vector2 = CFConst.CARD_SIZE * CFConst.PLAY_AREA_SCALE
	assert_eq(scene_grid.get_node("GridContainer").columns, 3,
			"Scene grid has three columns")
	assert_eq(scene_grid.get_slot_count(), 6,
			"Scene grid holds six cards for the active player")
	assert_eq(scene_grid.get_slot(0).rect_size, slot_size,
			"Scene slot matches the size of a card on the board")
	assert_almost_eq(scene_grid.rect_size, Vector2(
			3 * slot_size.x + 2 * separation,
			2 * slot_size.y + MousePointer.MOUSE_RADIUS * 2 + 1)
			+ Vector2(4, 4), Vector2(0.01, 0.01),
			"Scene grid fits two rows of three sideways-wide slots")


func test_scene_grid_uses_all_available_width():
	var scene_grid: BoardPlacementGrid = add_child_autoqfree(
			load("res://src/custom/CGFPlacementGridDemo.tscn").instance())
	yield(yield_for(0.1), YIELD)
	scene_grid.configure_width(983.0)
	var separation: int = int(scene_grid.get_node("GridContainer").get_constant(
			"hseparation"))
	var slot_size: Vector2 = CFConst.CARD_SIZE * CFConst.PLAY_AREA_SCALE
	assert_eq(scene_grid.get_node("GridContainer").columns, 7,
			"Seven sideways-wide columns fit in the central area")
	assert_eq(scene_grid.get_slot_count(), 14,
			"Seven columns become two rows of seven slots")
	assert_almost_eq(scene_grid.rect_size, Vector2(
			7 * slot_size.x + 6 * separation,
			2 * slot_size.y + MousePointer.MOUSE_RADIUS * 2 + 1)
			+ Vector2(4, 4), Vector2(0.01, 0.01),
			"Scene grid covers the widest central area")


func test_scene_grid_reserves_space_for_sideways_cards():
	var scene_grid: BoardPlacementGrid = add_child_autoqfree(
			load("res://src/custom/CGFPlacementGridDemo.tscn").instance())
	yield(yield_for(0.1), YIELD)
	var base_separation: int = MousePointer.MOUSE_RADIUS * 2 + 1
	var slot_size: Vector2 = CFConst.CARD_SIZE * CFConst.PLAY_AREA_SCALE
	var separation: int = int(scene_grid.get_node("GridContainer").get_constant(
			"hseparation"))
	assert_eq(separation,
			int(slot_size.y - slot_size.x + base_separation),
			"Horizontal gap fits a card rotated 90 degrees")
	var first_center: Vector2 = scene_grid.get_slot(0).rect_global_position \
			+ scene_grid.get_slot(0).rect_size * 0.5
	var second_center: Vector2 = scene_grid.get_slot(1).rect_global_position \
			+ scene_grid.get_slot(1).rect_size * 0.5
	assert_true(second_center.x - first_center.x >= slot_size.y,
			"Neighbouring rotated cards keep a full card width")


func test_scene_grid_keeps_minimum_columns():
	var scene_grid: BoardPlacementGrid = add_child_autoqfree(
			load("res://src/custom/CGFPlacementGridDemo.tscn").instance())
	yield(yield_for(0.1), YIELD)
	scene_grid.configure_width(300.0)
	assert_eq(scene_grid.get_node("GridContainer").columns, 2,
			"Grid never goes below two columns")
	assert_eq(scene_grid.get_slot_count(), 4,
			"A two-column grid keeps four slots")


func test_scene_grid_auto_placement_starts_at_center():
	var scene_grid: BoardPlacementGrid = add_child_autoqfree(
			load("res://src/custom/CGFPlacementGridDemo.tscn").instance())
	yield(yield_for(0.1), YIELD)
	scene_grid.configure_width(983.0)
	assert_eq(scene_grid.get_auto_placement_slot(), scene_grid.get_slot(3),
			"First automatic card goes to the front center")
	scene_grid.get_slot(3).occupying_card = cards[0]
	# Seven columns leave one exact center, so the order walks left first:
	# 3, 2, 4, 1, 5, 0, 6.
	assert_eq(scene_grid.get_auto_placement_slot(cards[1]),
			scene_grid.get_slot(2),
			"Next card fills the front row from the center outwards")
	for index in range(7):
		scene_grid.get_slot(index).occupying_card = cards[0]
	assert_eq(scene_grid.get_auto_placement_slot(cards[1]),
			scene_grid.get_slot(10),
			"Cards move to the back center after the front row is full")
	for slot in scene_grid.get_all_slots():
		slot.occupying_card = null


func test_support_prefers_back_center_with_characters_in_front():
	var scene_grid: BoardPlacementGrid = add_child_autoqfree(
			load("res://src/custom/CGFPlacementGridDemo.tscn").instance())
	yield(yield_for(0.1), YIELD)
	scene_grid.configure_width(983.0)
	cards[0].properties["_tipo"] = "Personagem"
	cards[1].properties["_tipo"] = "Suporte"
	scene_grid.get_slot(3).occupying_card = cards[0]
	var support_slot: BoardPlacementSlot = \
			scene_grid.get_auto_placement_slot(cards[1])
	assert_eq(support_slot, scene_grid.get_slot(10),
			"Support starts at the back center when characters hold the front")
	scene_grid.get_slot(3).occupying_card = null


func test_scene_grid_highlights_full_central_area():
	var scene_grid: BoardPlacementGrid = add_child_autoqfree(
			load("res://src/custom/CGFPlacementGridDemo.tscn").instance())
	yield(yield_for(0.1), YIELD)
	scene_grid.configure_width(983.0)
	var center := scene_grid.rect_global_position + scene_grid.rect_size * 0.5
	scene_grid.update_auto_highlight(cards[0], center)
	assert_true(scene_grid._full_highlight.visible,
			"Whole central area is highlighted")
	var target: BoardPlacementSlot = scene_grid.get_highlighted_slot()
	assert_true(target.auto_highlighted,
			"The automatic target slot is marked")
	assert_eq(cards[0].get_potential_placement_slot(), target,
			"Dragged card uses the automatic target slot")
	scene_grid.clear_auto_highlight()
	assert_false(scene_grid._full_highlight.visible,
			"Highlight disappears when the drag leaves the area")


func test_hand_drag_keeps_the_slot_chosen_by_the_pointer():
	var scene_grid: BoardPlacementGrid = add_child_autoqfree(
			load("res://src/custom/CGFPlacementGridDemo.tscn").instance())
	yield(yield_for(0.1), YIELD)
	scene_grid.configure_width(983.0)
	yield(yield_for(0.1), YIELD)
	var slot: BoardPlacementSlot = scene_grid.get_slot(9)
	var pointer: Vector2 = slot.rect_global_position + slot.rect_size * 0.5
	scene_grid.update_auto_highlight(cards[0], pointer)
	assert_eq(scene_grid.get_highlighted_slot(), slot,
			"Dragging a hand card selects the slot under the pointer")
	assert_eq(cards[0].get_potential_placement_slot(), slot,
			"The card drops on the chosen slot instead of the center")


func test_scene_grid_does_not_block_card_input():
	var scene_grid: BoardPlacementGrid = add_child_autoqfree(
			load("res://src/custom/CGFPlacementGridDemo.tscn").instance())
	yield(yield_for(0.1), YIELD)
	scene_grid.configure_width(983.0)
	assert_eq(scene_grid.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"Scene grid lets clicks through to cards")
	assert_eq(scene_grid.get_node("GridContainer").mouse_filter,
			Control.MOUSE_FILTER_IGNORE,
			"Grid container does not intercept card input")
	assert_eq(scene_grid.get_node("Control").mouse_filter,
			Control.MOUSE_FILTER_IGNORE,
			"Grid label layer does not intercept card input")
	for slot in scene_grid.get_all_slots():
		assert_eq(slot.mouse_filter, Control.MOUSE_FILTER_IGNORE,
				"Every placement slot lets card input through")
	assert_true(scene_grid.z_index < 0,
			"Scene grid draws behind the cards")


func test_hand_left_half_click_sends_card_to_resources():
	var card: Card = cards[0]
	card._handle_hand_half_click(true)
	yield(yield_to(card._tween, "tween_all_completed", 1), YIELD)
	assert_eq(card.get_parent(), discard,
			"Left half of a hand card sends it to Recursos/Descarte")


func test_hand_right_half_click_plays_character_to_scene():
	var scene_grid: BoardPlacementGrid = grid
	scene_grid.name = "PlacementGridDemo"
	scene_grid.auto_arrange = true
	scene_grid.configure_columns(2)
	var card: Card = cards[0]
	card.properties["_tipo"] = "Personagem"
	card.properties["ENERGIA"] = "0"
	card._handle_hand_half_click(false)
	yield(yield_to(card._tween, "tween_all_completed", 1), YIELD)
	assert_eq(card.get_parent(), board,
			"Right half of a character card plays it to the scene")
	assert_eq(card._placement_slot, scene_grid.get_slot(0),
			"Automatic placement uses the center slot")


func test_hand_right_half_click_discards_ability():
	var card: Card = cards[0]
	card.properties["_tipo"] = "Habilidade"
	card._handle_hand_half_click(false)
	yield(yield_to(card._tween, "tween_all_completed", 1), YIELD)
	assert_eq(card.get_parent(), discard,
			"Ability cards are discarded by the right half click")


func test_hand_card_shows_type_legend():
	var card: Card = cards[0]
	var legend: Label = card.card_front.get_node("TypeLegend")
	card.properties["_tipo"] = "Personagem"
	card.set_state(Card.CardState.IN_HAND)
	assert_true(legend.visible, "Legend is visible for cards in hand")
	assert_eq(legend.text, "Personagem", "Legend shows the rule type")
	assert_true(legend.rect_position.y >= CFConst.CARD_SIZE.y * 0.5,
			"Legend sits at the foot of the card")
	assert_true(legend.get_font("font").size <= 10,
			"Legend uses a smaller font")
	card.properties["_tipo"] = "Personagen"
	card.set_state(Card.CardState.IN_HAND)
	assert_eq(legend.text, "Personagen",
			"Invalid saved types are shown as they are")
	card.properties.erase("_tipo")
	card.set_state(Card.CardState.IN_HAND)
	assert_eq(legend.text, "SEM TIPO", "Missing type is clearly flagged")


func test_support_knockout_sends_card_to_resources():
	var card: Card = cards[0]
	card.properties["_tipo"] = "Suporte"
	card.properties["ENERGIA"] = "0"
	card.move_to(board)
	yield(yield_to(card._tween, "tween_all_completed", 1), YIELD)
	assert_eq(card.get_parent(), board, "Support starts in the scene")
	board.knockout_support(card)
	yield(yield_to(card._tween, "tween_all_completed", 1), YIELD)
	assert_eq(card.get_parent(), discard,
			"Knocked out support goes to Recursos/Descarte")


func test_prizes_button_requires_multiplayer_session():
	var card: Card = cards[0]
	card.properties["_tipo"] = "Personagem"
	card.properties["ENERGIA"] = "0"
	card.move_to(board)
	yield(yield_to(card._tween, "tween_all_completed", 1), YIELD)
	board.send_character_to_opponent_prizes(card)
	assert_eq(card.get_parent(), board,
			"Without a multiplayer session the card stays in the scene")


func test_deck_validation_flags_missing_essential_fields():
	var importer = load("res://src/custom/BSDBDeckImportDialog.gd")
	assert_eq(
			importer._missing_essential_fields({
				"Name": "Carta", "_tipo": "Personagem", "ENERGIA": ""}),
			["ENERGIA"],
			"Characters without ENERGIA are flagged")
	assert_eq(
			importer._missing_essential_fields({
				"Name": "Carta", "_tipo": "Habilidade"}),
			[],
			"Abilities do not require ENERGIA")
	assert_eq(
			importer._missing_essential_fields({
				"Name": "", "_tipo": "", "ENERGIA": ""}),
			["Nome", "Tipo"],
			"Name and type are always required")
	assert_eq(importer._template_for_category("Suporte"), "Red",
			"Support cards use the red template")


func test_missing_energy_is_not_silently_zeroed():
	var importer = load("res://src/custom/BSDBDeckImportDialog.gd")
	var properties: Dictionary = importer.make_card_properties({
		"id_card": "card-1",
		"nome": "Carta",
		"tipo": "Personagem",
		"imagem": "/cards/carta.png",
		"dados": {"TEXTO": "Habilidade"},
	})
	assert_eq(properties.get("ENERGIA", "ausente"), "",
			"Missing ENERGIA stays empty for the validation popup")
	var unknown: Dictionary = importer.make_card_properties({
		"id_card": "card-2",
		"nome": "Sem tipo",
		"tipo": "",
		"imagem": "/cards/carta.png",
		"dados": {},
	})
	assert_eq(unknown.get("_tipo", "ausente"), "",
			"Unknown type reaches the validation popup")
	assert_eq(importer._template_for_category(""), "",
			"Unknown type has no card template until corrected")


func test_deck_validation_dialog_confirms_corrected_card():
	var dialog = add_child_autoqfree(
			load("res://src/custom/BSDBDeckValidationDialog.tscn").instance())
	yield(yield_for(0.1), YIELD)
	var type_field: OptionButton = dialog.get_node(
			"VBox/Content/Fields/TypeField")
	assert_eq(type_field.get_item_count(), 4,
			"Validation popup offers the four card types")
	watch_signals(dialog)
	var name_field: LineEdit = dialog.get_node("VBox/Content/Fields/NameField")
	var energy_field: SpinBox = dialog.get_node(
			"VBox/Content/Fields/EnergyField")
	name_field.text = "  Carta Corrigida  "
	type_field.select(1)
	energy_field.value = 2
	dialog._on_confirm_pressed()
	assert_signal_emitted_with_parameters(
			dialog, "card_confirmed", ["Carta Corrigida", "Suporte", "2"])
	name_field.text = ""
	dialog._on_confirm_pressed()
	assert_signal_emit_count(dialog, "card_confirmed", 1,
			"Empty name does not confirm the card")
	assert_eq(
			dialog.get_node("VBox/Content/Fields/Error").text,
			"Informe o nome da carta.",
			"Empty name keeps the popup open with an error")


func test_scenario_claim_resolution():
	var sync = autofree(load("res://src/custom/MultiplayerSync.gd").new())
	assert_true(sync.scenario_claim_wins(2, 1, false),
			"A newer scenario claim wins")
	assert_false(sync.scenario_claim_wins(1, 2, true),
			"An older scenario claim loses")
	assert_true(sync.scenario_claim_wins(3, 3, true),
			"A tie keeps the host scenario")
	assert_false(sync.scenario_claim_wins(3, 3, false),
			"A tie discards the guest scenario")


func test_zone_presence_maps_board_points_to_zones():
	var sync = autofree(load("res://src/custom/MultiplayerSync.gd").new())
	var deck_area: Control = deck.get_node("Control")
	var deck_center: Vector2 = deck_area.rect_global_position \
			+ deck_area.rect_size * 0.5
	assert_eq(sync._zone_at(deck_center), "deck",
			"A point over the deck reports the deck zone")
	var discard_area: Control = discard.get_node("Control")
	var discard_center: Vector2 = discard_area.rect_global_position \
			+ discard_area.rect_size * 0.5
	assert_eq(sync._zone_at(discard_center), "resources",
			"A point over the discard pile reports the resources zone")
	var hand_area: Control = hand.get_node("Control")
	var hand_point := Vector2(640.0,
			hand_area.rect_global_position.y + hand_area.rect_size.y * 0.5)
	assert_eq(sync._zone_at(hand_point), "hand",
			"A point over the hand band reports the hand zone")
	assert_eq(sync._zone_at(Vector2(640, 20)), "",
			"A point outside every box reports no zone")
	assert_true(sync._local_mouse_zone() is String,
			"The live mouse lookup always answers with a zone name")


func test_remote_board_positions_are_mirrored_and_contained():
	var sync = autofree(load("res://src/custom/MultiplayerSync.gd").new())
	var area := ColorRect.new()
	area.rect_position = Vector2(300, 205)
	area.rect_size = Vector2(745, 145)
	add_child_autoqfree(area)
	var display: Vector2 = CFConst.CARD_SIZE * 0.45
	var near_left: Vector2 = sync._map_zone_position(
			area, Vector2(0.0, 0.0), 8, 30, display)
	var near_right: Vector2 = sync._map_zone_position(
			area, Vector2(1.0, 1.0), 8, 30, display)
	assert_true(near_right.x < near_left.x,
			"Remote card x axis is mirrored")
	assert_true(near_right.y < near_left.y,
			"Remote card y axis is mirrored")
	for position in [near_left, near_right]:
		assert_true(position.x >= area.rect_global_position.x + 8,
				"Remote card starts inside the scene horizontally")
		assert_true(position.x + display.x \
				<= area.rect_global_position.x + area.rect_size.x - 8,
				"Remote card ends inside the scene horizontally")
		assert_true(position.y >= area.rect_global_position.y + 30,
				"Remote card starts inside the scene vertically")
		assert_true(position.y + display.y \
				<= area.rect_global_position.y + area.rect_size.y,
				"Remote card ends inside the scene vertically")


func test_remote_scenario_position_is_centered():
	var sync = autofree(load("res://src/custom/MultiplayerSync.gd").new())
	var area := ColorRect.new()
	area.rect_position = Vector2(155, 205)
	area.rect_size = Vector2(135, 145)
	add_child_autoqfree(area)
	var display: Vector2 = CFConst.CARD_SIZE * 0.45
	var position: Vector2 = sync._center_zone_position(area, 30, display)
	var expected_center: float = area.rect_global_position.x \
			+ area.rect_size.x * 0.5
	assert_true(abs(position.x + display.x * 0.5 - expected_center) < 0.01,
			"Remote scenario is horizontally centered in its area")
	assert_true(position.y + display.y \
			<= area.rect_global_position.y + area.rect_size.y,
			"Remote scenario fits inside its area")


func test_scene_slots_mirror_into_the_opponent_band():
	var sync = autofree(load("res://src/custom/MultiplayerSync.gd").new())
	var scene_grid: BoardPlacementGrid = \
			load("res://src/custom/CGFPlacementGridDemo.tscn").instance()
	scene_grid.name = "PlacementGridDemo"
	board.add_child(scene_grid)
	autofree(scene_grid)
	var visual := Control.new()
	visual.name = "OpponentFieldVisual"
	board.add_child(visual)
	autofree(visual)
	var scene := Control.new()
	scene.name = "OpponentScene"
	visual.add_child(scene)
	yield(yield_for(0.2), YIELD)
	scene_grid.rect_position = Vector2(400, 400)
	scene.rect_size = scene_grid.rect_size
	scene.rect_global_position = scene_grid.rect_global_position \
			- Vector2(0, scene_grid.rect_size.y)
	yield(yield_for(0.1), YIELD)

	var first: BoardPlacementSlot = scene_grid.get_slot(0)
	var mirrored: Rect2 = sync._mirrored_slot_rect(0)
	assert_eq(mirrored.size, first.rect_size,
			"A mirrored slot keeps the size of a scene slot")
	var slot_offset: Vector2 = first.rect_global_position \
			+ first.rect_size * 0.5 - scene_grid.rect_global_position
	assert_almost_eq(
			mirrored.position + mirrored.size * 0.5 - scene.rect_global_position,
			scene.rect_size - slot_offset, Vector2(0.01, 0.01),
			"A slot mirrors by turning 180 degrees inside the opponent band")
	var middle_y: float = scene.rect_global_position.y + scene.rect_size.y * 0.5
	assert_true(mirrored.position.y + mirrored.size.y * 0.5 > middle_y,
			"The owner front row lands on the row nearest the middle line")
	var last: Rect2 = sync._mirrored_slot_rect(scene_grid.get_slot_count() - 1)
	assert_true(last.position.y + last.size.y * 0.5 < middle_y,
			"The owner back row lands on the row farthest from the middle line")
	assert_true(sync._mirrored_slot_rect(99).size.x <= 0.0,
			"An unknown slot cannot be mirrored")

	var travel: Vector2 = sync._owner_travel_for_mirror(mirrored.position)
	var target: Vector2 = scene_grid.rect_global_position \
			+ Vector2(travel.x * scene_grid.rect_size.x,
					travel.y * scene_grid.rect_size.y)
	assert_true(Rect2(first.rect_global_position, first.rect_size) \
			.has_point(target),
			"The travel sent back lands inside the slot the owner used")
	assert_eq(sync._mirror_slot_at(mirrored.position), 0,
			"A drop on a mirrored slot asks for the matching owner slot")
	assert_eq(sync._mirror_slot_at(Vector2(10, 10)), -1,
			"A drop outside the opponent band asks for no slot")

	var card: Card = cards[0]
	card._placement_slot = first
	assert_eq(int(sync._local_entry(card, "board", 1)["slot"]), 0,
			"A settled scene card advertises its slot")
	card._placement_slot = null
	assert_eq(int(sync._local_entry(card, "board", 1)["slot"]), -1,
			"A card outside the scene grid advertises no slot")

