extends "res://tests/UTcommon.gd"


func before_each():
	await setup_board()
	var deck: Pile = cfc.NMAP.deck
	for index in range(3):
		deck.get_top_card().move_to(discard)
	await yield_for(0.3)


# A real mouse press has to reach the viewer buttons. The panel is drawn over
# the field and used to hide behind a cover that took the clicks meant for its
# own action row, which left every button dead.
func _click(control: Control) -> void:
	var vp: Viewport = control.get_viewport()
	var at: Vector2 = control.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	down.global_position = at
	vp.push_input(down, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	up.global_position = at
	vp.push_input(up, true)
	await yield_for(0.1)


func test_viewer_buttons_receive_real_clicks():
	discard._on_View_Button_pressed()
	await yield_for(0.3)
	var send_top: Button = discard.get_node(
			"ViewPopup/PopupContent/ResourceActions/SendTop")
	await _click(send_top)
	assert_true(send_top.button_pressed, "The click marks the send button")
	assert_eq("topo", cfc.NMAP.board.pending_resource_send_side,
			"The click arms the send to the deck top")
	assert_true(discard.pile_popup.visible,
			"The viewer stays open for the card pick")


# The add to a character sits on the same row, so it has to take over from the
# send that was armed before it.
func test_arming_the_add_drops_the_armed_send():
	discard._on_View_Button_pressed()
	await yield_for(0.3)
	discard._on_SendTop_pressed()
	await yield_for(0.1)
	var add_perso: Button = discard.get_node(
			"ViewPopup/PopupContent/ResourceActions/AddPerso")
	add_perso.pressed.emit()
	await yield_for(0.1)
	assert_true(cfc.NMAP.board.pending_resource_add_active,
			"Add perso arms the add to a character")
	assert_eq("", cfc.NMAP.board.pending_resource_send_side,
			"Arming the add drops the send")
