# Checks that the mouse entry points (manipulation buttons and the deck) run
# through the same intents as the scripts. The drag drop is covered by the
# intent suite, because a synthetic drop needs real pointer input.
#
# Every test reads the shared runner kept on the board, so the assertion is not
# only that the card changed but that the change is in the log.
extends "res://tests/UTcommon.gd"

const Snapshot = preload("res://src/core/table/TableSnapshot.gd")

var runner


func before_each():
	await setup_board()
	runner = board.table_actions()


func _last_op() -> String:
	var entry: Dictionary = runner.last_undo_target()
	return str(entry.get("op", ""))


func _play_one():
	var cards = draw_test_cards(1)
	var result: Dictionary = board.apply_intent({"op": "jogar", "card": cards[0]})
	assert_true(bool(result.get("ok", false)), str(result))
	return cards[0]


func test_the_board_keeps_one_runner_for_the_whole_match():
	var card = _play_one()
	var first_size: int = runner.history.size()

	var result: Dictionary = board.apply_intent({"op": "virar", "card": card})

	assert_true(bool(result.get("ok", false)), str(result))
	assert_true(board.table_actions() == runner)
	assert_eq(runner.history.size(), first_size + 1)


func test_shield_button_goes_through_the_intent_log():
	var card = _play_one()
	var buttons = card.get_node("Control/ManipulationButtons")

	buttons._on_ShieldMenu_id_pressed(1)

	assert_eq(int(card.tokens.get_token_count("escudo")), 1)
	assert_eq(_last_op(), "escudo")


func test_the_deck_mill_zone_goes_through_the_intent_log():
	var top = deck.get_top_card()
	var top_id: String = Snapshot.id_of(top)

	deck._mill_top_card_to_resources()

	assert_eq(deck.get_top_card() != top, true)
	assert_eq(discard.get_top_card(), top)
	assert_eq(_last_op(), "mandar_topo_para_recursos")
	assert_eq(str(runner.state.address_of(top_id)), "p1:recursos:1")


func test_clicking_the_deck_draws_through_the_intent_log():
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(10, 10000)

	deck._on_Deck_input_event(event)

	assert_eq(int(hand.get_card_count()), 1)
	assert_eq(_last_op(), "comprar")


func test_a_refused_button_click_logs_nothing():
	var card = _play_one()
	var buttons = card.get_node("Control/ManipulationButtons")
	# The card is a character: rotating it is refused by the rules.
	var size_before: int = runner.history.size()

	buttons._on_Rot90_pressed()

	assert_eq(runner.history.size(), size_before)
	assert_eq(int(card.card_rotation), 0)


# -----------------------------------------------------------------------------
# Materializar
# -----------------------------------------------------------------------------

func _materialize_button() -> Button:
	return board.get_node("Materializar") as Button


func _release_on(card: Card) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = Vector2(10, 10)
	card._on_Card_gui_input(event)


func test_the_materialize_button_arms_the_mode_and_the_click_materializes():
	var cards = draw_test_cards(1)
	var card: Card = cards[0]
	# The resting state the click sees in the game once the hand tween ends.
	card.state = Card.CardState.IN_HAND
	var button := _materialize_button()

	board._on_Materializar_pressed()

	assert_true(board.materialize_mode)
	assert_eq(button.text, "Cancelar")
	assert_true(button.button_pressed)
	assert_true(card.highlight.visible)
	assert_eq(card.highlight.modulate, CFConst.MATERIALIZE_HOVER_COLOUR)

	_release_on(card)

	assert_false(board.materialize_mode)
	assert_false(button.button_pressed)
	assert_eq(button.text, "Materializar")
	assert_eq(card.get_parent(), board)
	assert_eq(str(runner.state.address_of(Snapshot.id_of(card))),
			"p1:campo:frente:2")
	assert_eq(_last_op(), "materializar")


func test_escape_cancels_the_materialize_mode():
	var cards = draw_test_cards(1)
	board._on_Materializar_pressed()
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true

	board._unhandled_input(event)

	assert_false(board.materialize_mode)
	assert_false(cards[0].highlight.visible)


func test_a_card_the_table_refuses_keeps_the_mode_armed():
	var token = cfc.instance_card("Spawn Card")
	hand.add_child(token)
	token.state = Card.CardState.IN_HAND
	board._on_Materializar_pressed()

	var result: Dictionary = board.materialize_hand_card(token)

	assert_false(bool(result.get("ok", false)), str(result))
	assert_eq(str(result.get("error", "")), "tipo_invalido")
	assert_true(board.materialize_mode)
	assert_eq(token.get_parent(), hand)
