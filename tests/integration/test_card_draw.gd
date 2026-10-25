extends "res://tests/UTcommon.gd"

func before_each():
	var confirm_return = setup_board()
	if confirm_return is GDScriptFunctionState: # Still working.
		confirm_return = yield(confirm_return, "completed")


func test_single_card_draw_use_rectangle():
	cfc.game_settings.hand_use_oval_shape = false
	var card0: Card = hand.draw_card()
	assert_eq(len(hand.get_children()), 5,
			"Correct amount of cards drawn")
	assert_true(card0.visible,
			"Cards drawn is visible")
	yield(yield_to(card0.get_node('Tween'), "tween_all_completed", 1), YIELD)
	yield(yield_to(card0.get_node('Tween'), "tween_all_completed", 1), YIELD)
	assert_almost_eq(412.0,card0.recalculate_position().x,5.0,
			"Card position x is recalculated correctly")
	assert_almost_eq(0.0,card0.recalculate_position().y,5.0,
			"Card position y is recalculated correctly")
	assert_almost_eq(hand.to_global(card0.recalculate_position()),
			card0.global_position,Vector2(2,2),
			"Card placed in correct global position")
	assert_almost_eq(card0.recalculate_position(),card0.position,Vector2(2,2),
			"Card placed in correct position")
	cfc.game_settings.hand_use_oval_shape = true


func test_single_card_draw_use_oval():
	cfc.game_settings.hand_use_oval_shape = true
	var card0: Card = hand.draw_card()
	assert_eq(len(hand.get_children()), 5,
			"Correct amount of cards drawn")
	assert_true(card0.visible,
			"Cards drawn is visible")
	yield(yield_to(card0.get_node('Tween'), "tween_all_completed", 1), YIELD)
	yield(yield_to(card0.get_node('Tween'), "tween_all_completed", 1), YIELD)
	assert_almost_eq(412.0,card0.recalculate_position().x,5.0,
			"Card position x is recalculated correctly")
	assert_almost_eq(-60.0,card0.recalculate_position().y,5.0,
			"Card position y is recalculated correctly")
	assert_almost_eq(hand.to_global(card0.recalculate_position()),
			card0.global_position,Vector2(2,2),
			"Card placed in correct global position")
	assert_almost_eq(card0.recalculate_position(),card0.position,Vector2(2,2),
			"Card placed in correct position")
	cfc.game_settings.hand_use_oval_shape = true


func test_draw_multiple_cards_slow_use_rectangle():
	cfc.game_settings.hand_use_oval_shape = false
	var card0: Card = hand.draw_card()
	yield(yield_to(card0.get_node('Tween'), "tween_all_completed", 1), YIELD)
	yield(yield_to(card0.get_node('Tween'), "tween_all_completed", 1), YIELD)
	var card1: Card = hand.draw_card()
	yield(yield_to(card1.get_node('Tween'), "tween_all_completed", 1), YIELD)
	yield(yield_to(card1.get_node('Tween'), "tween_all_completed", 1), YIELD)
	assert_almost_eq(card0.recalculate_position(),card0.position,Vector2(2,2),
			"Card at index 0 placed in correct position")
	assert_almost_eq(card1.recalculate_position(),card1.position,Vector2(2,2),
			"Card at index 1 placed in correct position")
	var card2: Card = hand.draw_card()
	yield(yield_to(card2.get_node('Tween'), "tween_all_completed", 1), YIELD)
	yield(yield_to(card2.get_node('Tween'), "tween_all_completed", 1), YIELD)
	assert_almost_eq(250.0,card0.recalculate_position().x,5.0,
			"Index 0 card position x is recalculated correctly")
	assert_almost_eq(0.0,card0.recalculate_position().y,5.0,
			"Index 0 card position y is recalculated correctly")
	assert_almost_eq(415.0,card1.recalculate_position().x,5.0,
			"Index 1 card position x is recalculated correctly")
	assert_almost_eq(0.0,card1.recalculate_position().y,5.0,
			"Index 1 card position y is recalculated correctly")
	assert_almost_eq(580.0,card2.recalculate_position().x,5.0,
			"Index 2 card position x is recalculated correctly")
	assert_almost_eq(0.0,card2.recalculate_position().y,5.0,
			"Index 2 card position y is recalculated correctly")
	assert_almost_eq(card0.recalculate_position(),card0.position,Vector2(2,2),
			"Card at index 0 placed in correct position")
	assert_almost_eq(card1.recalculate_position(),card1.position,Vector2(2,2),
			"Card at index 1 placed in correct position")
	assert_almost_eq(card2.recalculate_position(),card2.position,Vector2(2,2),
			"Card at index 2 placed in correct position")
	cfc.game_settings.hand_use_oval_shape = true


func test_draw_multiple_cards_slow_use_oval():
	cfc.game_settings.hand_use_oval_shape = true
	var card0: Card = hand.draw_card()
	yield(yield_to(card0.get_node('Tween'), "tween_all_completed", 1), YIELD)
	yield(yield_to(card0.get_node('Tween'), "tween_all_completed", 1), YIELD)
	var card1: Card = hand.draw_card()
	yield(yield_to(card1.get_node('Tween'), "tween_all_completed", 1), YIELD)
	yield(yield_to(card1.get_node('Tween'), "tween_all_completed", 1), YIELD)
	assert_almost_eq(card0.recalculate_position(),card0.position,Vector2(2,2),
			"Card at index 0 placed in correct position")
	assert_almost_eq(card1.recalculate_position(),card1.position,Vector2(2,2),
			"Card at index 1 placed in correct position")
	var card2: Card = hand.draw_card()
	yield(yield_to(card2.get_node('Tween'), "tween_all_completed", 1), YIELD)
	yield(yield_to(card2.get_node('Tween'), "tween_all_completed", 1), YIELD)
	assert_almost_eq(238.0,card0.recalculate_position().x,5.0,
			"Index 0 card position x is recalculated correctly")
	assert_almost_eq(-48.754,card0.recalculate_position().y,5.0,
			"Index 0 card position y is recalculated correctly")
	assert_almost_eq(412.0,card1.recalculate_position().x,5.0,
			"Index 1 card position x is recalculated correctly")
	assert_almost_eq(-60.0,card1.recalculate_position().y,5.0,
			"Index 1 card position y is recalculated correctly")
	assert_almost_eq(585.0,card2.recalculate_position().x,5.0,
			"Index 2 card position x is recalculated correctly")
	assert_almost_eq(-48.754,card2.recalculate_position().y,5.0,
			"Index 2 card position y is recalculated correctly")
	assert_almost_eq(card0.recalculate_position(),card0.position,Vector2(2,2),
			"Card at index 0 placed in correct position")
	assert_almost_eq(card1.recalculate_position(),card1.position,Vector2(2,2),
			"Card at index 1 placed in correct position")
	assert_almost_eq(card2.recalculate_position(),card2.position,Vector2(2,2),
			"Card at index 2 placed in correct position")
	cfc.game_settings.hand_use_oval_shape = true
#
#
func test_draw_multiple_cards_fast():
	var card0: Card = hand.draw_card()
	yield(yield_for(0.2), YIELD)
	var card1: Card = hand.draw_card()
	yield(yield_for(0.1), YIELD)
	var card2: Card = hand.draw_card()
	yield(yield_for(0.3), YIELD)
	var card3: Card = hand.draw_card()
	yield(yield_for(0.5), YIELD)
	var card4: Card = hand.draw_card()
	yield(yield_for(0.1), YIELD)
	var card5: Card = hand.draw_card()
	yield(yield_to(card5.get_node('Tween'), "tween_all_completed", 1), YIELD)
	yield(yield_to(card5.get_node('Tween'), "tween_all_completed", 1), YIELD)
	assert_almost_eq(card0.recalculate_position(),card0.position,Vector2(2,2),
			"Card at index 0 placed in correct position")
	assert_almost_eq(card1.recalculate_position(),card1.position,Vector2(2,2),
			"Card at index 1 placed in correct position")
	assert_almost_eq(card2.recalculate_position(),card2.position,Vector2(2,2),
			"Card at index 2 placed in correct position")
	assert_almost_eq(card3.recalculate_position(),card3.position,Vector2(2,2),
			"Card at index 3 placed in correct position")
	assert_almost_eq(card4.recalculate_position(),card4.position,Vector2(2,2),
			"Card at index 4 placed in correct position")
	assert_almost_eq(card5.recalculate_position(),card5.position,Vector2(2,2),
			"Card at index 5 placed in correct position")


func test_container_custom_card_functions():
	# warning-ignore:return_value_discarded
	hand.draw_card()
	# warning-ignore:return_value_discarded
	hand.draw_card()
	# warning-ignore:return_value_discarded
	hand.draw_card()
	# warning-ignore:return_value_discarded
	hand.draw_card()
	# warning-ignore:return_value_discarded
	hand.draw_card()
	var card5: Card = hand.draw_card()
	yield(yield_to(card5._tween, "tween_all_completed", 1), YIELD)
	yield(yield_to(card5._tween, "tween_all_completed", 1), YIELD)
	assert_eq(len(hand.get_all_cards()), 6,
			"get_all_cards() returns right amount of cards")
	assert_eq(hand.get_card_count(), 6,
			"get_card_count() returns right amount of cards")
	assert_eq(hand.get_card(5), card5,
			"get_card() returns the card at the correct index")
	assert_eq(hand.get_card_index(card5), 5,
			"get_card_index() returns the correct index")


func test_card_does_not_become_focused_during_movement():
	var card = hand.draw_card()
	yield(yield_for(0.2), YIELD)
	card._on_Card_mouse_entered()
	assert_eq(Card.CardState.MOVING_TO_CONTAINER, card.state, "Card state is still MovingToContainer")


func test_card_not_draggable_without_focus_first():
	var card = hand.draw_card()
	yield(yield_to(card._tween, "tween_all_completed", 1), YIELD)
	yield(yield_to(card._tween, "tween_all_completed", 1), YIELD)
	click_card(card, false)
	yield(yield_for(0.2), YIELD)
	assert_eq(Card.CardState.IN_HAND, card.state,
			"Card state is still InHand because it wasn't focused first")


func test_double_clicking_card_in_hand_moves_it_to_resources():
	var card: Card = hand.draw_card()
	yield(yield_to(card.get_node("Tween"), "tween_all_completed", 1), YIELD)
	yield(yield_to(card.get_node("Tween"), "tween_all_completed", 1), YIELD)
	card.properties["_tipo"] = "Personagem"
	card.set_state(Card.CardState.FOCUSED_IN_HAND)
	var double_click := InputEventMouseButton.new()
	double_click.button_index = BUTTON_LEFT
	double_click.pressed = true
	double_click.doubleclick = true

	card._on_Card_gui_input(double_click)

	assert_eq(card.get_parent(), discard,
			"Double-clicking a card in hand sends it to resources")


func test_single_clicking_card_in_hand_does_not_move_it_to_resources():
	var card: Card = hand.draw_card()
	card.set_state(Card.CardState.FOCUSED_IN_HAND)
	var single_click := InputEventMouseButton.new()
	single_click.button_index = BUTTON_LEFT
	single_click.pressed = false

	card._on_Card_gui_input(single_click)

	assert_eq(card.get_parent(), hand,
			"A single click does not send a card to resources")


func test_hand_counter_only_shows_card_count():
	var card: Card = hand.draw_card()
	yield(yield_to(card.get_node("Tween"), "tween_all_completed", 1), YIELD)
	yield(yield_to(card.get_node("Tween"), "tween_all_completed", 1), YIELD)
	hand._process(0)

	assert_eq(hand._counter_cards.text, "1")


func test_resources_pile_has_a_view_button():
	assert_true(discard.view_button.visible,
			"Resources and discard pile can be opened for viewing")
	assert_true(discard.view_button.is_connected(
			"pressed", discard, "_on_View_Button_pressed"),
			"Pressing the view button opens the resources pile")


func test_game_deck_actions_and_unlimited_hand_configuration():
	var game_board = load("res://src/custom/CGFBoard.tscn").instance()
	var game_deck = game_board.get_node("Deck")
	var game_hand = game_board.get_node("Hand")

	assert_false(game_board.has_node("ReshuffleAllDeck"))
	assert_false(game_board.has_node("ReshuffleAllDiscard"))
	assert_true(game_deck.get_node(
			"Control/ManipulationButtons/Shuffle").visible)
	assert_not_null(game_deck.get_node(
			"Control/ManipulationButtons/Clarividencia"))
	assert_not_null(game_deck.get_node(
			"Control/ManipulationButtons/Procurar"))
	assert_eq(
			game_hand.excess_cards,
			Hand.ExcessCardsBehaviour.ALLOW)
	assert_eq(game_hand.hand_size, 10)

	game_board.free()


func test_peeking_top_cards_preserves_deck_order():
	var expected_top := deck.get_top_card()
	var deck_count := deck.get_card_count()
	var peeked_cards: Array = deck.get_top_cards(3)

	assert_eq(peeked_cards.size(), 3)
	assert_eq(peeked_cards[0], expected_top)
	assert_eq(deck.get_card_count(), deck_count)
	assert_eq(deck.get_top_card(), expected_top)


func test_search_selection_closes_immediately_after_card_click():
	var card: Card = hand.draw_card()
	var selection_window = load(
			"res://src/core/SelectionWindow.tscn").instance()
	board.add_child(selection_window)
	selection_window.close_on_selection = true
	selection_window.selection_count = 1
	selection_window.selection_type = "equal"
	selection_window._card_dupe_map[card] = card
	selection_window.popup_centered()
	watch_signals(selection_window)

	var click := InputEventMouseButton.new()
	click.button_index = BUTTON_LEFT
	click.pressed = true
	selection_window.on_selection_gui_input(click, card, card)

	assert_false(selection_window.visible)
	assert_signal_emitted(selection_window, "card_selected")
	selection_window.queue_free()


func test_clairvoyance_reveals_top_cards_then_restores_the_deck():
	var expected_top := deck.get_top_card()
	var deck_count := deck.get_card_count()
	var top_cards: Array = deck.get_top_cards(2)
	var reveal = deck._reveal_top_cards(top_cards)
	if reveal is GDScriptFunctionState:
		yield(reveal, "completed")

	assert_eq(deck.get_card_count(), deck_count)
	assert_eq(deck.get_top_card(), expected_top)
	for card in top_cards:
		assert_eq(card.get_parent(), deck)


func test_searched_card_is_revealed_then_added_to_hand():
	var card: Card = deck.get_top_card()
	var search_move = deck._reveal_searched_card(card)

	assert_eq(card.get_parent(), board,
			"The selected card is revealed on the table first")
	yield(search_move, "completed")

	assert_eq(card.get_parent(), hand,
			"The revealed card then moves into the player's hand")


func test_excess_cards_disallowed():
	hand.excess_cards = Hand.ExcessCardsBehaviour.DISALLOW
	hand.hand_size = 3
	var cards = draw_test_cards(5, false)
	assert_eq(hand.get_card_count(), 3)
	assert_eq(cards[3], cards[4])

func test_excess_cards_allowed():
	hand.excess_cards = Hand.ExcessCardsBehaviour.ALLOW
	hand.hand_size = 3
	var cards = draw_test_cards(5, false)
	assert_eq(hand.get_card_count(), 5)
	assert_ne(cards[3], cards[4])


func test_game_hand_accepts_more_than_ten_cards():
	hand.excess_cards = Hand.ExcessCardsBehaviour.ALLOW
	hand.hand_size = 10
	draw_test_cards(12, false)

	assert_eq(hand.get_card_count(), 12,
			"The Battle Scenes hand has no maximum card count")


func test_excess_cards_discard_drawn():
	hand.excess_cards = Hand.ExcessCardsBehaviour.DISCARD_DRAWN
	hand.hand_size = 3
	var cards = draw_test_cards(5, false)
	assert_eq(hand.get_card_count(), 3)
	assert_eq(cards[3].get_parent(), discard)
	assert_eq(cards[4].get_parent(), discard)

func test_excess_cards_discard_oldest():
	hand.excess_cards = Hand.ExcessCardsBehaviour.DISCARD_OLDEST
	hand.hand_size = 3
	var cards = draw_test_cards(5, false)
	assert_eq(hand.get_card_count(), 3)
	assert_eq(cards[0].get_parent(), discard)
	assert_eq(cards[1].get_parent(), discard)
#
