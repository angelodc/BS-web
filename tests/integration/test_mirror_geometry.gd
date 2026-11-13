extends "res://tests/UTcommon.gd"

# The opponent field is the local field seen from the other side of the table.
# These tests pin that single reflection: the field slots and the resource grid
# have to be the local boxes turned 180 degrees around the middle line, so the
# two halves cannot drift apart again.

const SPLIT_Y := 366.2
const BOARD_WIDTH := 1280.0
const BOARD_HEIGHT := 720.0


func after_each():
	Multiplayer.leave_session()


# The UT board has no opponent band, so each test builds the box the shipped
# scene authors: a full-width strip ending on the middle line.
func _add_opponent_band() -> Control:
	var visual := Control.new()
	visual.name = "OpponentFieldVisual"
	board.add_child(visual)
	autofree(visual)
	visual.position = Vector2.ZERO
	visual.size = Vector2(BOARD_WIDTH, SPLIT_Y)
	return visual


func _add_scene_grid() -> BoardPlacementGrid:
	var grid = load("res://src/custom/CGFPlacementGridDemo.tscn").instantiate()
	grid.name = "PlacementGridDemo"
	board.add_child(grid)
	autofree(grid)
	grid.position = Vector2(156, SPLIT_Y)
	await yield_for(0.2)
	return grid


func _add_sync():
	var sync = load("res://src/custom/MultiplayerSync.gd").new()
	sync.name = "MultiplayerSync"
	board.add_child(sync)
	autofree(sync)
	return sync


# The reflection is a 180 degree turn: x and y both invert around the middle
# line and the board centre, and turning the result again returns the box.
func test_mirror_rect_turns_a_box_around_the_middle_line():
	await setup_board()
	_add_opponent_band()
	var sync = _add_sync()

	var rect := Rect2(100, 400, 150, 210)
	var mirrored: Rect2 = sync.mirror_rect(rect)
	var expected := Rect2(BOARD_WIDTH - rect.position.x - rect.size.x,
			SPLIT_Y * 2.0 - rect.position.y - rect.size.y, rect.size.x,
			rect.size.y)
	assert_almost_eq(mirrored.position, expected.position, Vector2(1, 1),
			"The box lands across the middle line")
	assert_almost_eq(mirrored.size, rect.size, Vector2(1, 1),
			"The reflection keeps the box size")
	assert_almost_eq(sync.mirror_rect(mirrored).position, rect.position,
			Vector2(1, 1), "Turning the mirror again returns the original box")


# Every slot of the owner's field has a slot on the other side, mirrored across
# the middle line, which is what makes the two rows face each other.
func test_scene_slots_are_the_reflection_of_the_local_slots():
	await setup_board()
	_add_opponent_band()
	var grid: BoardPlacementGrid = await _add_scene_grid()
	var sync = _add_sync()
	assert_true(grid.get_slot_count() > 0, "The scene grid has slots")

	for index in range(grid.get_slot_count()):
		var slot: Control = grid.get_slot(index)
		var expected := Rect2(
				BOARD_WIDTH - slot.global_position.x - slot.size.x,
				SPLIT_Y * 2.0 - slot.global_position.y - slot.size.y,
				slot.size.x, slot.size.y)
		var mirrored: Rect2 = sync._mirrored_slot_rect(index)
		assert_almost_eq(mirrored.position, expected.position, Vector2(1, 1),
				"Slot " + str(index) + " lands on the mirrored slot")
		assert_almost_eq(mirrored.size, slot.size, Vector2(1, 1),
				"Slot " + str(index) + " keeps its size")


# The resource mini grid is the same three-column grid the local pile draws,
# reflected. The first card of the pile therefore sits on the opposite corner
# and the columns read in reverse on this side of the table.
func test_resource_cells_reflect_the_local_grid():
	await setup_board()
	# The UT discard sits on the right column; the shipped board puts it on the
	# left, under the deck, which is the box the mirror is authored for.
	discard.position = Vector2(0, 372.2)
	discard._layout_panel()
	var visual := _add_opponent_band()
	var resources := ColorRect.new()
	resources.name = "OpponentResourcesBackground"
	visual.add_child(resources)
	resources.position = Vector2(1124, 144.2)
	resources.size = Vector2(156, 216)
	var sync = _add_sync()

	var layout: Dictionary = discard.grid_layout()
	assert_false(layout.is_empty(), "The local grid reports its layout")
	var panel: Control = discard.get_node("Control")
	var origin: Vector2 = layout["origin"]
	var step: Vector2 = layout["step"]
	var cell_size: Vector2 = CFConst.CARD_SIZE * float(layout["scale"])

	for index in range(6):
		var local := Rect2(panel.global_position + origin + Vector2(
				index % 3, int(index / 3)) * step, cell_size)
		var expected := Rect2(
				BOARD_WIDTH - local.position.x - local.size.x,
				SPLIT_Y * 2.0 - local.position.y - local.size.y,
				local.size.x, local.size.y)
		var mirrored: Rect2 = sync._resource_cell_rect(index)
		assert_almost_eq(mirrored.position, expected.position, Vector2(1, 1),
				"Resource cell " + str(index) + " is the reflected cell")
		assert_almost_eq(mirrored.size, cell_size, Vector2(1, 1),
				"Resource cell " + str(index) + " keeps the local cell size")
		var box := Rect2(resources.global_position, resources.size)
		assert_true(box.encloses(mirrored),
				"Resource cell " + str(index) + " stays inside the opponent box")

	var first: Rect2 = sync._resource_cell_rect(0)
	var third: Rect2 = sync._resource_cell_rect(2)
	assert_true(first.position.x > third.position.x,
			"The grid columns read in reverse on the mirrored side")


# The opponent box draws its own label band on top. A mirrored cell that reached
# into it would answer the pointer while the player is still over the text, and
# the preview would pop up before any card is touched.
func test_resource_cells_stay_below_the_opponent_label():
	await setup_board()
	discard.position = Vector2(0, 372.2)
	discard._layout_panel()
	var visual := _add_opponent_band()
	var resources := ColorRect.new()
	resources.name = "OpponentResourcesBackground"
	visual.add_child(resources)
	resources.position = Vector2(1124, 144.2)
	resources.size = Vector2(156, 216)
	var sync = _add_sync()

	var label_band := Rect2(Vector2(1124, 144.2), Vector2(156, 22))
	for index in range(6):
		var cell: Rect2 = sync._resource_cell_rect(index)
		assert_false(cell.intersects(label_band),
				"Resource cell " + str(index) + " leaves the label band alone")
		assert_true(cell.position.y >= label_band.end.y,
				"Resource cell " + str(index) + " starts below the label band")


# The scenario that loses the dispute goes to its owner's resources and can come
# back under a character. The mirror read the card type alone, so that play kept
# the scenario box: the mirror drew it at the scenario scale and treated it as
# the active scenario. A card under a host is a field card like any other.
func test_attached_scenario_card_is_mirrored_as_a_field_card():
	await setup_board()
	var sync = _add_sync()
	var cards := draw_test_cards(2)
	for card in cards:
		card.get_parent().remove_child(card)
		board.add_child(card)
		card.state = Card.CardState.ON_PLAY_BOARD
	var scenario_card: Card = cards[1]
	scenario_card.properties["_tipo"] = "Cenário"
	await yield_for(0.1)
	assert_eq(sync._zone_for_card(scenario_card), "scenario",
			"A scenario card standing alone is the scenario")

	scenario_card.attach_to_host(cards[0])
	await yield_for(0.2)
	assert_eq(sync._zone_for_card(scenario_card), "board",
			"An attached scenario card is a field card")
	assert_almost_eq(
			sync._scale_for_zone(sync._zone_for_card(scenario_card)),
			CFConst.PLAY_AREA_SCALE, 0.001,
			"The mirror draws it at the field scale")
