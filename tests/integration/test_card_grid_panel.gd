extends "res://tests/UTcommon.gd"

# The deck search and the opponent zone viewers draw their cards on the table
# canvas inside a CardGridPanel. The cards are ordinary cards on the board
# canvas, so the hover is the pinned closeup the resources viewer already uses.
# These tests cover the grid it builds, the card it reports under the pointer
# and the pick/close contract the deck search relies on.


func before_each():
	await setup_main()


func _open_panel(sources: Array, options := {}) -> CardGridPanel:
	var panel := CardGridPanel.new()
	board.add_child(panel)
	panel.open(sources, options)
	await yield_for(0.2)
	return panel


func _source_cards(count: int) -> Array:
	var cards := []
	for _index in range(count):
		cards.append(deck.get_top_card())
	return cards


func _display_cards(panel: CardGridPanel) -> Array:
	var cards := []
	for slot in panel.get_node("Column/Scroll/Grid").get_children():
		for node in slot.get_children():
			if node is Card:
				cards.append(node)
	return cards


func _card_center(card: Card) -> Vector2:
	return card.global_position + CFConst.CARD_SIZE * card.scale * 0.5


func _click(point: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	return event


func test_open_builds_a_grid_of_read_only_copies():
	var sources := _source_cards(3)
	var panel: CardGridPanel = await _open_panel(sources, {
		"title": "Buscar carta no deck",
		"selectable": true,
	})
	assert_eq(panel.title_text(), "Buscar carta no deck",
			"The panel carries the search title")
	assert_true(panel.is_selectable(), "The search panel answers a pick")

	var displays := _display_cards(panel)
	assert_eq(displays.size(), sources.size(), "One slot per card offered")
	for index in range(displays.size()):
		var display: Card = displays[index]
		var source: Card = sources[index]
		assert_eq(display.state, Card.CardState.IN_POPUP,
				"The copy rests in the popup state")
		assert_true(display.is_faceup, "The copy is shown face up")
		assert_false(display.is_in_group("cards"),
				"The copy never answers the card scripts")
		assert_eq(display.definition_key(), source.definition_key(),
				"The copy keeps the definition key of the card")
		assert_eq(display.card_front.card_labels["Name"].text,
				source.card_front.card_labels["Name"].text,
				"The copy draws the same card front")
		assert_eq(display.scale, Vector2(hand.card_display_scale,
				hand.card_display_scale), "The grid uses the hand card scale")
		assert_eq(display.get_parent().custom_minimum_size,
				CFConst.CARD_SIZE * display.scale,
				"The slot matches the scaled card")


func test_definition_names_are_instanced_as_copies():
	var key := "Test Card 1"
	var panel: CardGridPanel = await _open_panel([key])
	var displays := _display_cards(panel)
	assert_eq(displays.size(), 1, "The definition key opens a card")
	assert_eq(displays[0].definition_key(), key,
			"The copy carries the definition key it was opened with")
	assert_false(displays[0].is_in_group("cards"),
			"The copy never reaches the cards group")


func test_card_at_finds_the_card_under_the_point():
	var panel: CardGridPanel = await _open_panel(_source_cards(2))
	var displays := _display_cards(panel)
	assert_eq(panel._card_at(_card_center(displays[1])), displays[1],
			"The point over a card reports that card")
	assert_null(panel._card_at(displays[0].global_position + Vector2(-30, -30)),
			"A point outside the cards reports nothing")


func test_picking_reports_the_card_in_the_deck():
	var sources := _source_cards(2)
	var panel: CardGridPanel = await _open_panel(sources, {"selectable": true})
	var picked := []
	var closed := []
	panel.card_picked.connect(func(card): picked.append(card))
	panel.closed.connect(func(did_pick): closed.append(did_pick))
	var display: Card = _display_cards(panel)[1]

	panel._input(_click(_card_center(display)))

	assert_eq(picked, [sources[1]],
			"The pick reports the card in the deck, not the picture")
	assert_eq(closed, [true], "The pick closes the panel as a search result")
	assert_true(panel.is_queued_for_deletion(), "The panel leaves the table")


func test_display_panel_ignores_card_clicks():
	var panel: CardGridPanel = await _open_panel(_source_cards(2))
	assert_false(panel.is_selectable(), "A viewer offers no selection")
	var picked := []
	panel.card_picked.connect(func(card): picked.append(card))

	panel._input(_click(_card_center(_display_cards(panel)[0])))

	assert_true(picked.is_empty(), "A viewer reports no pick")
	assert_false(panel.is_queued_for_deletion(), "The viewer stays open")


func test_clicking_outside_closes_without_picking():
	var panel: CardGridPanel = await _open_panel(_source_cards(1))
	var closed := []
	panel.closed.connect(func(did_pick): closed.append(did_pick))

	panel._input(_click(Vector2(2, 2)))

	assert_eq(closed, [false], "The outside click closes without a pick")
	assert_true(panel.is_queued_for_deletion(), "The panel leaves the table")


func test_unknown_definition_is_skipped():
	var panel: CardGridPanel = await _open_panel(["No Such Card"])
	assert_eq(_display_cards(panel).size(), 0,
			"A name without a definition cannot be shown")


func test_hover_uses_the_pinned_closeup():
	var panel: CardGridPanel = await _open_panel(_source_cards(2))
	var target: Card = _display_cards(panel)[0]

	panel._update_hover(target)
	assert_eq(main._current_focus_source, target,
			"The hover opens the closeup")
	assert_eq(main._pinned_source, target,
			"The closeup is pinned beside the pointer")

	panel._update_hover(null)
	assert_null(main._current_focus_source,
			"Leaving the card closes the closeup")
