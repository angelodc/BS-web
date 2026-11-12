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


# The popup cards belong to the popup Window, which has its own physics world,
# so the board pointer can never reach them. Their GUI hover drives the same
# card state machine and has to open the preview.
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
