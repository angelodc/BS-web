extends "res://tests/UTcommon.gd"

class TestBattleScenesCapacity:
	extends "res://tests/Basic_common.gd"

	func _put_card_on_board(card: Card, card_type: String) -> void:
		hand.remove_child(card)
		board.add_child(card)
		card.properties["_tipo"] = card_type
		card.set_state(Card.CardState.ON_PLAY_BOARD)


	func test_character_capacity_advances_and_reverses_with_limits() -> void:
		var card = cards[0]
		_put_card_on_board(card, "Personagem")

		assert_eq(0, card.get_incapacitation_stage())
		assert_eq(CFConst.ReturnCode.CHANGED, card.incapacitar())
		assert_eq(-1, card.get_incapacitation_stage())
		assert_eq(-90, card.card_rotation)
		assert_almost_eq(
				-90.0,
				card.get_node("CollisionShape2D").rotation_degrees,
				0.01)
		assert_eq(CFConst.ReturnCode.FAILED, card.incapacitar())
		assert_eq(CFConst.ReturnCode.CHANGED, card.capacitar())
		assert_eq(0, card.get_incapacitation_stage())
		assert_eq(CFConst.ReturnCode.CHANGED, card.capacitar())
		assert_eq(1, card.get_incapacitation_stage())
		assert_eq(90, card.card_rotation)
		assert_eq(CFConst.ReturnCode.FAILED, card.capacitar())
		assert_eq(CFConst.ReturnCode.CHANGED, card.incapacitar())
		assert_eq(0, card.get_incapacitation_stage())


	func test_menu_only_shows_valid_actions_for_characters_on_board() -> void:
		var card = cards[0]
		_put_card_on_board(card, "Personagem")
		card.buttons.set_active(true)

		assert_true(card.buttons.get_node("Capacitar").visible)
		assert_true(card.buttons.get_node("Incapacitar").visible)
		assert_false(card.buttons.get_node("Rot90").visible)
		assert_true(card.buttons.get_node("Flip").visible)
		assert_true(card.buttons.get_node("Escudo").visible)
		assert_false(card.buttons.has_node("View"))
		assert_false(card.buttons.has_node("Rot180"))
		assert_eq("Flip", card.buttons.get_node("Flip").text)

		card.incapacitar()
		card.buttons.set_active(true)
		assert_true(card.buttons.get_node("Capacitar").visible)
		assert_false(card.buttons.get_node("Incapacitar").visible)

		card.capacitar()
		card.buttons.set_active(true)
		assert_true(card.buttons.get_node("Capacitar").visible)
		assert_true(card.buttons.get_node("Incapacitar").visible)
		card.capacitar()
		card.buttons.set_active(true)
		assert_false(card.buttons.get_node("Capacitar").visible)
		assert_true(card.buttons.get_node("Incapacitar").visible)


	func test_non_character_does_not_receive_capacity_actions() -> void:
		var card = cards[0]
		_put_card_on_board(card, "Cenário")
		card.buttons.set_active(true)

		assert_false(card.buttons.get_node("Capacitar").visible)
		assert_false(card.buttons.get_node("Incapacitar").visible)
		assert_true(card.buttons.get_node("Rot90").visible)
		assert_true(card.buttons.get_node("Flip").visible)
		assert_false(card.buttons.get_node("Escudo").visible)
		assert_false(card.buttons.has_node("View"))
		assert_false(card.buttons.has_node("Rot180"))
		assert_eq(CFConst.ReturnCode.FAILED, card.incapacitar())
		assert_eq(0, card.get_incapacitation_stage())


	func test_shield_menu_adds_and_removes_selected_amount() -> void:
		var card = cards[0]
		_put_card_on_board(card, "Personagem")

		card.buttons._on_ShieldMenu_id_pressed(3)
		assert_eq(3, card.tokens.get_token_count("escudo"))
		card.buttons._on_ShieldMenu_id_pressed(5)
		assert_eq(1, card.tokens.get_token_count("escudo"))
