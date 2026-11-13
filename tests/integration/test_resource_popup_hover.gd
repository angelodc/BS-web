extends "res://tests/UTcommon.gd"

var cards := []


func before_each():
	cfc.game_settings.fancy_movement = false
	await setup_main()
	cards = draw_test_cards(3)
	await yield_for(0.3)


func _popup_cards() -> Array:
	var popup_cards := []
	for slot in discard.get_node("ViewPopup/PopupContent/CardView").get_children():
		for node in slot.get_children():
			if node is Card:
				popup_cards.append(node)
	return popup_cards


# The viewer is a panel over the field and the board pointer is switched off
# while it is open, so the popup cards are reached only by their GUI hover. That
# hover drives the same card state machine and has to open the preview.
func test_popup_card_gui_hover_opens_the_preview():
	for card in cards:
		await card.move_to(discard)
	await yield_for(0.3)
	discard.populate_popup()
	await yield_for(0.3)
	var popup_cards := _popup_cards()
	assert_gt(popup_cards.size(), 0, "The popup holds the resources")
	var target: Card = popup_cards[0]
	var control: Control = target.get_node("Control")
	assert_eq(control.mouse_filter, Control.MOUSE_FILTER_STOP,
			"The popup card receives the GUI mouse")

	control.mouse_entered.emit()
	await yield_for(0.3)
	assert_eq(target.state, Card.CardState.FOCUSED_IN_POPUP,
			"The GUI hover focuses the popup card")
	assert_eq(main._current_focus_source, target,
			"The popup card opens the preview")

	# A pointer outside the card produces the exit; the card goes back to its
	# resting popup state and the preview closes.
	target.position = Vector2(600, 600)
	control.mouse_exited.emit()
	await yield_for(0.3)
	assert_eq(target.state, Card.CardState.IN_POPUP,
			"Leaving the card returns it to IN_POPUP")
	assert_null(main._current_focus_source, "The preview closes")


# A press inside the viewer still arms `card_drag_ongoing` (the card state
# machine arms it on every focused card press), even though the board pointer is
# off while the viewer is open. The pointer must not adopt that card: once the
# picked resource lands on the board it would be promoted to FOCUSED_ON_BOARD
# and ask for the closeup every frame, fighting the card under the real mouse.
func test_disabled_pointer_ignores_the_armed_card():
	var pointer: MousePointer = board.mouse_pointer
	pointer.disable()
	cfc.card_drag_ongoing = cards[0]
	await yield_for(0.2)
	assert_null(pointer.current_focused_card,
			"The disabled pointer never adopts the armed card")

	# Even a focus kept from before the viewer opened must not be promoted once
	# the picked card settles on the board.
	var settled: Card = cards[1]
	await settled.move_to(board, -1, Vector2(600, 300))
	await yield_for(0.6)
	assert_eq(settled.state, Card.CardState.ON_PLAY_BOARD,
			"The card settles on the board")
	pointer.current_focused_card = settled
	await yield_for(0.2)
	assert_eq(settled.state, Card.CardState.ON_PLAY_BOARD,
			"The disabled pointer does not promote it to FOCUSED_ON_BOARD")
	assert_null(main._current_focus_source,
			"The settled card does not keep the closeup")

	cfc.card_drag_ongoing = null
	pointer.forget_focus()
	pointer.enable()


# The viewer used to be a Window, which hides itself when the table is clicked.
# The panel keeps that through the outside click, and the cards go back to the
# pile on the way out.
func test_clicking_the_table_closes_the_viewer():
	for card in cards:
		await card.move_to(discard)
	await yield_for(0.3)
	discard.populate_popup()
	await yield_for(0.3)
	var vp: Viewport = discard.pile_popup.get_viewport()
	var outside := Vector2(4, 4)
	assert_false(discard.pile_popup.get_global_rect().has_point(outside),
			"The chosen point is off the panel")

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = outside
	down.global_position = outside
	vp.push_input(down, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = outside
	up.global_position = outside
	vp.push_input(up, true)
	await yield_for(0.3)
	assert_false(discard.pile_popup.visible, "The table click closes the viewer")
	assert_null(main._current_focus_source, "The preview closes with the viewer")
