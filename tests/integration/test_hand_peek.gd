extends "res://tests/UTcommon.gd"

# The hand is the one zone that never travels on its own: the cards only leave
# the owner as the answer to a request, and the viewer forgets them when it
# closes.


func after_each():
	Multiplayer.leave_session()


func _add_sync():
	var sync = load("res://src/custom/MultiplayerSync.gd").new()
	sync.name = "MultiplayerSync"
	board.add_child(sync)
	autofree(sync)
	return sync


func _grid_panels() -> Array:
	var panels := []
	for child in board.get_children():
		if child is CardGridPanel:
			panels.append(child)
	return panels


func test_payload_carries_the_local_hand_and_its_definitions():
	await setup_board()
	var sync = _add_sync()
	var cards := draw_test_cards(3)
	var expected := []
	for card in cards:
		expected.append(card.definition_key())

	var payload: Dictionary = sync._hand_peek_payload()

	assert_eq(payload["cards"], expected,
			"The reveal lists the hand in its own order")
	for key in expected:
		assert_true(payload["definitions"].has(key),
				"The viewer rebuilds " + key + " without a second request")


func test_revealed_hand_opens_the_read_only_viewer():
	await setup_board()
	var sync = _add_sync()
	var key: String = draw_test_cards(1)[0].definition_key()

	sync._show_hand_viewer([key])

	var panels := _grid_panels()
	assert_eq(panels.size(), 1,
			"The revealed hand uses the same table panel as the resources")
	assert_true(panels[0].title_text().begins_with("Mão de"),
			"The panel names whose hand it shows")
	assert_false(panels[0].is_selectable(),
			"The viewer offers no selection")
