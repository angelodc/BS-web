extends "res://tests/UTcommon.gd"

# F3 of "ações sem mouse": the state owns the addresses and the renderer draws
# them on the scene. These tests check that the hand children follow mão:1 … N,
# that every field card sits on the slot of its frente/trás address, that the
# grid grows keeping each card on its own row and column and that the shared
# scenario goes to its single slot. Every assertion reads the scene, so a
# renderer that only returns the right list without moving the nodes fails.

const Table = preload("res://src/core/table/TableState.gd")
const Snapshot = preload("res://src/core/table/TableSnapshot.gd")
const Actions = preload("res://src/core/table/TableActions.gd")
const Renderer = preload("res://src/core/table/TableRenderer.gd")
const SCENARIO_GRID_SCENE = preload("res://src/custom/CGFModifiedLabelGrid.tscn")

var actions
var grid: BoardPlacementGrid
var scenario_grid: BoardPlacementGrid


func before_each():
	var setup = setup_board()
	if setup is GDScriptFunctionState:
		yield(setup, "completed")
	grid = Snapshot.field_grid(board)
	# The test board has no scenario slot, so one is added here the same way the
	# production scene offers it.
	scenario_grid = SCENARIO_GRID_SCENE.instance()
	scenario_grid.name = "ModifiedLabelGrid"
	board.add_child(scenario_grid)
	scenario_grid.add_slot()
	actions = Actions.new(board, 1)


func _id(card) -> String:
	return Snapshot.id_of(card)


func _ok(result : Dictionary) -> bool:
	return bool(result.get("ok", false))


func _card_by_id(id : String):
	for card in hand.get_children():
		if card is Card and _id(card) == id:
			return card
	return null


func _scenario_card():
	var card = cfc.instance_card("Demo Scenario")
	hand.add_child(card)
	return card


# Puts the card on the table without animating, the way an intent leaves it.
func _to_board(card) -> void:
	if card.get_parent():
		card.get_parent().remove_child(card)
	board.add_child(card)


# Takes the card from the state hand to a field address. The scene is moved
# separately so the test can see the renderer doing the placement.
func _place_on_field(state, card, address : String) -> void:
	_to_board(card)
	assert_true(state.place(_id(card), address), address)


func _clear_field_slots() -> void:
	for slot in grid.get_all_slots():
		if is_instance_valid(slot.occupying_card):
			slot.occupying_card._placement_slot = null
		slot.occupying_card = null


# -----------------------------------------------------------------------------
# Hand
# -----------------------------------------------------------------------------

func test_draw_through_the_intent_puts_the_new_card_first_in_the_hand():
	draw_test_cards(2)
	actions.sync(1)
	var top = actions.state.top_of_deck(1)

	var result = actions.apply({"op": "comprar"})

	assert_true(_ok(result), str(result))
	var drawn = _card_by_id(top)
	assert_true(is_instance_valid(drawn), "The drawn card is in the hand")
	assert_eq(hand.get_all_cards()[0], drawn,
			"A draw enters at mão:1, the first card of the fan")
	assert_eq(actions.state.address_of(top), "p1:mão:1")


func test_renderer_repairs_the_hand_order_from_the_addresses():
	var cards = draw_test_cards(3)
	actions.sync(1)
	# Move the first card to the end of the fan behind the state's back.
	hand.move_child(cards[0], hand.get_child_count() - 1)

	var changed = Renderer.reconcile(board, actions.state, 1)

	assert_eq(hand.get_all_cards(), cards,
			"The children are back in mão:1 … 3 order")
	assert_true(changed["hand"].has(_id(cards[0])),
			"The moved card is reported: " + str(changed))
	var again = Renderer.reconcile(board, actions.state, 1)
	assert_eq(again["hand"], [], "A second pass has nothing to fix")


# -----------------------------------------------------------------------------
# Field and scenario
# -----------------------------------------------------------------------------

func test_renderer_puts_each_field_card_on_the_slot_of_its_address():
	var cards = draw_test_cards(3)
	var state = Table.new()
	state.load_board(board, 1)
	_place_on_field(state, cards[0], "p1:campo:frente:1")
	_place_on_field(state, cards[1], "p1:campo:frente:2")
	_place_on_field(state, cards[2], "p1:campo:trás:1")
	_clear_field_slots()

	var changed = Renderer.reconcile(board, state, 1)

	var columns := int(grid.get_node("GridContainer").columns)
	assert_eq(cards[0]._placement_slot, grid.get_slot(0), "frente:1")
	assert_eq(cards[1]._placement_slot, grid.get_slot(1), "frente:2")
	assert_eq(cards[2]._placement_slot, grid.get_slot(columns), "trás:1")
	assert_eq(grid.get_slot(0).occupying_card, cards[0])
	assert_eq(grid.get_slot(1).occupying_card, cards[1])
	assert_eq(grid.get_slot(columns).occupying_card, cards[2])
	assert_eq(cards[2]._target_position,
			grid.get_slot(columns).rect_global_position,
			"The card heads to the slot position")
	assert_true(changed["field"].has("p1:campo:frente:1"), str(changed))
	assert_true(changed["field"].has("p1:campo:trás:1"), str(changed))


func test_a_hole_in_the_row_keeps_the_address_column():
	# The rules place the first character on the centre column, so frente:1 is
	# empty and frente:2 must still land on the second slot of the row.
	var cards = draw_test_cards(2)
	var state = Table.new()
	state.load_board(board, 1)
	assert_true(state.columns >= 2)
	_place_on_field(state, cards[0], "p1:campo:frente:2")
	_place_on_field(state, cards[1], "p1:campo:trás:2")
	_clear_field_slots()

	var changed = Renderer.reconcile(board, state, 1)

	var columns := int(grid.get_node("GridContainer").columns)
	assert_eq(cards[0]._placement_slot, grid.get_slot(1), "frente:2")
	assert_eq(cards[1]._placement_slot, grid.get_slot(columns + 1), "trás:2")
	assert_eq(grid.get_slot(0).occupying_card, null,
			"The empty frente:1 slot stays free")
	assert_true(changed["field"].has("p1:campo:frente:2"), str(changed))


func test_settling_a_card_releases_the_slot_it_used_to_claim():
	var cards = draw_test_cards(1)
	var state = Table.new()
	state.load_board(board, 1)
	_place_on_field(state, cards[0], "p1:campo:frente:2")
	_clear_field_slots()
	# A stale reference left on the wrong slot would make the snapshot report
	# the card at two addresses.
	grid.get_slot(0).occupying_card = cards[0]
	cards[0]._placement_slot = grid.get_slot(0)

	Renderer.reconcile(board, state, 1)

	assert_eq(grid.get_slot(0).occupying_card, null, "The old slot is released")
	assert_eq(cards[0]._placement_slot, grid.get_slot(1))


func test_growing_the_columns_keeps_each_field_address_on_its_row():
	grid.configure_columns(2)
	var cards = draw_test_cards(4)
	var state = Table.new()
	state.load_board(board, 1)
	assert_eq(state.columns, 2)
	_place_on_field(state, cards[0], "p1:campo:frente:1")
	_place_on_field(state, cards[1], "p1:campo:frente:2")
	_place_on_field(state, cards[2], "p1:campo:trás:1")
	_place_on_field(state, cards[3], "p1:campo:trás:2")
	Renderer.reconcile(board, state, 1)
	assert_eq(cards[2]._placement_slot, grid.get_slot(2))
	assert_eq(cards[3]._placement_slot, grid.get_slot(3))

	state.grow_field()
	Renderer.reconcile(board, state, 1)

	assert_eq(int(grid.get_node("GridContainer").columns), 3)
	assert_eq(grid.get_slot_count(), 6)
	assert_eq(cards[0]._placement_slot, grid.get_slot(0), "frente:1 stays")
	assert_eq(cards[1]._placement_slot, grid.get_slot(1), "frente:2 stays")
	assert_eq(cards[2]._placement_slot, grid.get_slot(3),
			"trás:1 keeps the back row")
	assert_eq(cards[3]._placement_slot, grid.get_slot(4),
			"trás:2 keeps the back row")
	assert_eq(cards[2]._target_position,
			grid.get_slot(3).rect_global_position)
	# The column resize already redraws every card; a renderer pass after it has
	# nothing left to fix.
	var again = Renderer.reconcile(board, state, 1)
	assert_eq(again["field"], [], "The grown field is already drawn")


func test_renderer_puts_the_scenario_in_the_shared_slot():
	var scenario = _scenario_card()
	var state = Table.new()
	state.load_board(board, 1)
	_to_board(scenario)
	assert_true(state.place(_id(scenario), "mesa:cenário"))

	var changed = Renderer.reconcile(board, state, 1)

	assert_eq(scenario_grid.get_slot(0).occupying_card, scenario)
	assert_eq(scenario._placement_slot, scenario_grid.get_slot(0))
	assert_eq(scenario._target_position,
			scenario_grid.get_slot(0).rect_global_position)
	assert_eq(changed["scenario"], [_id(scenario)])


# -----------------------------------------------------------------------------
# Intents end already rendered
# -----------------------------------------------------------------------------

func test_a_play_intent_leaves_the_scene_already_rendered():
	var cards = draw_test_cards(2)
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))

	var changed = Renderer.reconcile(board, actions.state, 1)

	assert_eq(changed["hand"], [], "The hand is already drawn")
	assert_eq(changed["field"], [], "The field is already drawn")
	assert_eq(changed["scenario"], [], "The scenario is already drawn")
