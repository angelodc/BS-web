extends "res://tests/UTcommon.gd"

func before_each():
	await setup_board()


func test_single_card_draw_use_rectangle():
	cfc.game_settings.hand_use_oval_shape = false
	var card0: Card = hand.draw_card()
	assert_eq(len(hand.get_children()), 5,
			"Correct amount of cards drawn")
	assert_true(card0.visible,
			"Cards drawn is visible")
	await yield_to(card0._tween, "tween_all_completed", 1)
	await yield_to(card0._tween, "tween_all_completed", 1)
	assert_almost_eq(449.5,card0.recalculate_position().x,5.0,
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
	await yield_to(card0._tween, "tween_all_completed", 1)
	await yield_to(card0._tween, "tween_all_completed", 1)
	assert_almost_eq(449.5,card0.recalculate_position().x,5.0,
			"Card position x is recalculated correctly")
	assert_almost_eq(-52.5,card0.recalculate_position().y,5.0,
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
	await yield_to(card0._tween, "tween_all_completed", 1)
	await yield_to(card0._tween, "tween_all_completed", 1)
	var card1: Card = hand.draw_card()
	await yield_to(card1._tween, "tween_all_completed", 1)
	await yield_to(card1._tween, "tween_all_completed", 1)
	assert_almost_eq(card0.recalculate_position(),card0.position,Vector2(2,2),
			"Card at index 0 placed in correct position")
	assert_almost_eq(card1.recalculate_position(),card1.position,Vector2(2,2),
			"Card at index 1 placed in correct position")
	var card2: Card = hand.draw_card()
	await yield_to(card2._tween, "tween_all_completed", 1)
	await yield_to(card2._tween, "tween_all_completed", 1)
	assert_almost_eq(391.0,card0.recalculate_position().x,5.0,
			"Index 0 card position x is recalculated correctly")
	assert_almost_eq(0.0,card0.recalculate_position().y,5.0,
			"Index 0 card position y is recalculated correctly")
	assert_almost_eq(449.5,card1.recalculate_position().x,5.0,
			"Index 1 card position x is recalculated correctly")
	assert_almost_eq(0.0,card1.recalculate_position().y,5.0,
			"Index 1 card position y is recalculated correctly")
	assert_almost_eq(508.5,card2.recalculate_position().x,5.0,
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
	await yield_to(card0._tween, "tween_all_completed", 1)
	await yield_to(card0._tween, "tween_all_completed", 1)
	var card1: Card = hand.draw_card()
	await yield_to(card1._tween, "tween_all_completed", 1)
	await yield_to(card1._tween, "tween_all_completed", 1)
	assert_almost_eq(card0.recalculate_position(),card0.position,Vector2(2,2),
			"Card at index 0 placed in correct position")
	assert_almost_eq(card1.recalculate_position(),card1.position,Vector2(2,2),
			"Card at index 1 placed in correct position")
	var card2: Card = hand.draw_card()
	await yield_to(card2._tween, "tween_all_completed", 1)
	await yield_to(card2._tween, "tween_all_completed", 1)
	assert_almost_eq(266.46,card0.recalculate_position().x,5.0,
			"Index 0 card position x is recalculated correctly")
	assert_almost_eq(-42.1136,card0.recalculate_position().y,5.0,
			"Index 0 card position y is recalculated correctly")
	assert_almost_eq(449.5,card1.recalculate_position().x,5.0,
			"Index 1 card position x is recalculated correctly")
	assert_almost_eq(-52.5,card1.recalculate_position().y,5.0,
			"Index 1 card position y is recalculated correctly")
	assert_almost_eq(632.54,card2.recalculate_position().x,5.0,
			"Index 2 card position x is recalculated correctly")
	assert_almost_eq(-42.1136,card2.recalculate_position().y,5.0,
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
	await yield_for(0.2)
	var card1: Card = hand.draw_card()
	await yield_for(0.1)
	var card2: Card = hand.draw_card()
	await yield_for(0.3)
	var card3: Card = hand.draw_card()
	await yield_for(0.5)
	var card4: Card = hand.draw_card()
	await yield_for(0.1)
	var card5: Card = hand.draw_card()
	await yield_to(card5._tween, "tween_all_completed", 1)
	await yield_to(card5._tween, "tween_all_completed", 1)
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
	await yield_to(card5._tween, "tween_all_completed", 1)
	await yield_to(card5._tween, "tween_all_completed", 1)
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
	await yield_for(0.2)
	card._on_Card_mouse_entered()
	assert_eq(Card.CardState.MOVING_TO_CONTAINER, card.state, "Card state is still MovingToContainer")


func test_card_not_draggable_without_focus_first():
	var card = hand.draw_card()
	await yield_to(card._tween, "tween_all_completed", 1)
	await yield_to(card._tween, "tween_all_completed", 1)
	click_card(card, false)
	await yield_for(0.2)
	assert_eq(Card.CardState.IN_HAND, card.state,
			"Card state is still InHand because it wasn't focused first")


func test_left_half_click_sends_card_to_resources():
	var card: Card = hand.draw_card()
	await yield_to(card._tween, "tween_all_completed", 1)
	await yield_to(card._tween, "tween_all_completed", 1)
	card.properties["_tipo"] = "Suporte"
	card.set_state(Card.CardState.FOCUSED_IN_HAND)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = false
	click.position = Vector2(10, 50)

	card._on_Card_gui_input(click)

	assert_eq(card.get_parent(), discard,
			"Left half click sends a hand card to resources")


func test_right_half_click_discards_ability():
	var card: Card = hand.draw_card()
	await yield_to(card._tween, "tween_all_completed", 1)
	await yield_to(card._tween, "tween_all_completed", 1)
	card.properties["_tipo"] = "Habilidade"
	card.set_state(Card.CardState.FOCUSED_IN_HAND)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = false
	click.position = Vector2(140, 50)

	card._on_Card_gui_input(click)

	assert_eq(card.get_parent(), discard,
			"Right half click discards an ability from the hand")


# The board draws "Mão: N · Deck: M" above the deck box, so the counter the
# framework puts inside the hand stays hidden instead of repeating the number.
func test_hand_counter_is_hidden():
	var card: Card = hand.draw_card()
	await yield_to(card._tween, "tween_all_completed", 1)
	await yield_to(card._tween, "tween_all_completed", 1)
	hand._process(0)

	assert_eq(hand.get_card_count(), 1, "The drawn card reached the hand")
	assert_false(hand.get_node("Counters").visible,
			"The hand draws no counter of its own")


func test_resources_pile_has_a_view_button():
	assert_true(discard.view_button.visible,
			"Resources and discard pile can be opened for viewing")
	assert_true(discard.view_button.pressed.is_connected(
			discard._on_View_Button_pressed),
			"Pressing the view button opens the resources pile")


func test_game_deck_actions_and_unlimited_hand_configuration():
	var game_board = load("res://src/custom/CGFBoard.tscn").instantiate()
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
			"res://src/core/SelectionWindow.tscn").instantiate()
	board.add_child(selection_window)
	selection_window.close_on_selection = true
	selection_window.selection_count = 1
	selection_window.selection_type = "equal"
	selection_window._card_dupe_map[card] = card
	selection_window.popup_centered()
	watch_signals(selection_window)

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	selection_window.on_selection_gui_input(click, card, card)

	assert_false(selection_window.visible)
	assert_signal_emitted(selection_window, "card_selected")
	selection_window.queue_free()


# The deck search builds the same selection window and hovers its cards, which
# shows the enlarged preview. That preview used to position itself through a
# Viewport method that does not exist in Godot 4 and broke the search.
func test_search_selection_preview_placement():
	var card: Card = hand.draw_card()
	var selection_window = load(
			"res://src/core/SelectionWindow.tscn").instantiate()
	board.add_child(selection_window)
	selection_window.initiate_selection([card], 1, "max", true)
	await yield_to(selection_window, "selection_window_opened", 2)
	var grid_card_obj = selection_window.get_node(
			"ScrollContainer/GridContainer").get_child(0)
	var preview_popup = grid_card_obj.preview_popup
	preview_popup.show_preview_card(card.canonical_name)
	await yield_for(0.3)

	var placement = preview_popup.get_preview_placement()
	assert_eq(typeof(placement), TYPE_VECTOR2,
			"Preview placement is computed inside the selection window")
	assert_true(placement.is_finite(), "Preview placement is a finite point")
	assert_almost_eq(preview_popup.position, placement, Vector2(30,30),
			"Preview follows its computed placement instead of the grid cell")
	selection_window.queue_free()


# A Window crops its children, so the preview has to stay inside the selection
# dialog. Hovering a central card used to push it past the left edge, where it
# was cut in half.
func test_search_preview_stays_inside_the_window():
	var screen := Vector2(1000, 600)
	var card := Vector2(225, 315)
	var panel := Vector2(300, 280)
	for mouse in [Vector2(20, 20), Vector2(500, 300), Vector2(980, 580)]:
		var placement = CVPreviewPopup.compute_preview_position(
				mouse, screen, card, panel)
		assert_between(placement.x, 12.0, screen.x - 12.0 - card.x - panel.x,
				"Preview stays inside the window horizontally")
		assert_between(placement.y, 34.0, screen.y - 12.0 - panel.y,
				"Preview stays inside the window vertically")
	var right_edge = CVPreviewPopup.compute_preview_position(
			Vector2(990, 300), screen, card, panel)
	assert_true(right_edge.x + card.x + panel.x <= screen.x - 12.0,
			"A preview at the right edge moves left instead of overflowing")
	assert_between(right_edge.x, 12.0, screen.x - 12.0 - card.x - panel.x,
			"The preview at the right edge is fully inside the window")


# Small dialogs (a single row of choices) are shorter than the full preview, so
# the card is scaled down just enough to fit instead of being cropped.
func test_search_preview_scales_down_to_a_small_dialog():
	var canonical := Vector2(150, 210)
	assert_eq(CVPreviewPopup.fit_preview_scale(1.5, Vector2(1280, 720), canonical),
			1.5, "The game viewport keeps the full preview scale")
	var small := CVPreviewPopup.fit_preview_scale(1.5, Vector2(400, 230), canonical)
	assert_true(small < 1.5, "A small dialog shrinks the preview")
	assert_almost_eq(small * canonical.y, 230.0 - 46.0, 0.01,
			"The scaled card fits the dialog height")


# Imported decks rename the cards to their printed names while the definition
# stays under its catalog key. The grid preview has to instance by that key, as
# the printed name is not a card_definitions entry.
func test_search_preview_uses_the_definition_key():
	var card: Card = hand.draw_card()
	var key := card.definition_key()
	card.set_card_name("Nome Impresso")
	assert_ne(card.canonical_name, key,
			"The printed name differs from the catalog key")
	var selection_window = load(
			"res://src/core/SelectionWindow.tscn").instantiate()
	board.add_child(selection_window)
	selection_window.initiate_selection([card], 1, "max", true)
	await yield_to(selection_window, "selection_window_opened", 2)
	var grid_card_obj = selection_window.get_node(
			"ScrollContainer/GridContainer").get_child(0)
	grid_card_obj._on_GridCardObject_mouse_entered()
	await yield_for(0.2)
	assert_true(grid_card_obj.preview_popup.has_preview_card(),
			"The grid hover instances the preview card")
	assert_eq(grid_card_obj.preview_popup.preview_card.definition_key(), key,
			"The preview is instanced by the definition key")
	selection_window.queue_free()


# The deck search closes on the card click, so its dialog has no use for OK;
# every other selection still confirms with it. The grid scrolls inside the
# dialog instead of pushing it past the design height.
func test_search_window_drops_the_ok_button():
	var options: Array = [hand.draw_card(), hand.draw_card()]
	var search = load("res://src/core/SelectionWindow.tscn").instantiate()
	board.add_child(search)
	search.close_on_selection = true
	search.initiate_selection(options, 1, "equal", true)
	await yield_for(0.3)
	assert_false(search.get_ok_button().visible,
			"The search dialog drops the redundant OK button")
	assert_true(search.get_node("ScrollContainer").is_visible_in_tree(),
			"The cards live in a scroll container")
	assert_true(search.size.y <= 720.0,
			"The dialog stays inside the design height")
	# The dialog is exclusive, so it must be gone before the next one opens.
	search.free()
	var other = load("res://src/core/SelectionWindow.tscn").instantiate()
	board.add_child(other)
	other.initiate_selection(options, 1, "min", true)
	await yield_for(0.3)
	assert_true(other.get_ok_button().visible,
			"Selections confirmed by OK keep the button")
	other.queue_free()


# Selecting a card used to freeze the hover on it: the engine hover signals
# stopped driving the preview after the click, so the pointer could no longer
# reach the remaining choices. The window tracks the hover by hit-test and
# resets the preview of the chosen card.
func test_selection_hover_survives_card_selection():
	var cards: Array = [hand.draw_card(), hand.draw_card(), hand.draw_card()]
	var selection_window = load(
			"res://src/core/SelectionWindow.tscn").instantiate()
	board.add_child(selection_window)
	selection_window.initiate_selection(cards, 3, "max", true)
	await yield_to(selection_window, "selection_window_opened", 2)
	# The frame-driven tracker reads the real pointer, which is not what the
	# test moves; freeze it and drive the hover directly.
	selection_window.set_process(false)
	var grid = selection_window.get_node("ScrollContainer/GridContainer")
	var obj_a: CVGridCardObject = grid.get_child(0)
	var obj_b: CVGridCardObject = grid.get_child(1)

	selection_window._update_hover(obj_a.get_global_rect().get_center())
	await yield_for(0.3)
	assert_eq(obj_a.preview_popup.modulate.a, 1.0,
			"Hovering a choice shows its preview")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	selection_window.on_selection_gui_input(
			click, obj_a.display_card, cards[0])
	assert_eq(selection_window.selected_cards, [cards[0]],
			"The click selects the card")
	assert_eq(obj_a.preview_popup.modulate.a, 0.0,
			"Choosing the card resets its preview")

	selection_window._update_hover(obj_b.get_global_rect().get_center())
	await yield_for(0.3)
	assert_eq(obj_a.preview_popup.modulate.a, 0.0,
			"The chosen card keeps its preview hidden")
	assert_eq(obj_b.preview_popup.modulate.a, 1.0,
			"Moving on shows the next preview without engine hover signals")

	selection_window._update_hover(obj_a.get_global_rect().get_center())
	await yield_for(0.3)
	assert_eq(obj_a.preview_popup.modulate.a, 1.0,
			"Moving back to the chosen card shows its preview again")
	selection_window.queue_free()


# Clarividência keeps the row on screen until the player closes it. The old
# reveal closed itself three seconds after showing the cards, which never left
# time to read the row, let alone reorder it.
func test_clairvoyance_stays_open_until_finished():
	var deck_count: int = deck.get_card_count()
	var top_cards: Array = deck.get_top_cards(3)
	deck._show_top_cards(3)
	var view = deck._clarividencia
	assert_not_null(view, "Clarividência opens a view over the board")
	await wait_until(func(): return view._row_ready, 6)

	assert_eq(view._cards.size(), 3, "The three top cards are in the row")
	for index in range(3):
		assert_eq(view._cards[index], top_cards[index],
				"The row reads left to right from the top of the deck")
		assert_eq(top_cards[index].get_parent(), board,
				"The peeked card is shown on the table")
		assert_true(top_cards[index].is_faceup,
				"The peeked card is revealed")

	# Past the old three second timeout.
	await yield_for(3.4)
	assert_true(view.is_inside_tree(), "The peek no longer closes on a timer")
	assert_eq(view._cards.size(), 3, "The row is still complete")

	view._finish()
	await wait_until(func(): return deck._clarividencia == null, 4)

	assert_eq(deck.get_card_count(), deck_count,
			"Every card went back to the deck")
	var restored: Array = deck.get_top_cards(3)
	for index in range(3):
		assert_eq(restored[index], top_cards[index],
				"An untouched row keeps the deck order")


func test_clairvoyance_header_stays_clear_of_the_row():
	deck._show_top_cards(3)
	var view = deck._clarividencia
	await wait_until(func(): return view._row_ready, 6)

	# The match HUD draws at z_index 110 over the board; the peek and its
	# "Concluir" button must stay above it.
	assert_gt(view.z_index, 110, "The peek draws above the match HUD")
	var metrics: Dictionary = view._metrics()
	var header: Rect2 = Rect2(view._header_panel.position,
			view._header_panel.size)
	var row: Rect2 = Rect2(metrics["x"], metrics["y"],
			metrics["total"], metrics["card"].y)
	assert_true(header.end.y <= row.position.y,
			"The header sits above the card row")
	var button: Rect2 = Rect2(view._finish_button.position,
			view._finish_button.size)
	assert_true(Rect2(Vector2.ZERO, view._header_panel.size).encloses(button),
			"The Concluir button is inside the header panel")
	view._finish()
	await wait_until(func(): return deck._clarividencia == null, 4)


func test_clairvoyance_reorder_is_kept_when_closing():
	deck._show_top_cards(3)
	var view = deck._clarividencia
	await wait_until(func(): return view._row_ready, 6)
	var first: Card = view._cards[0]
	var second: Card = view._cards[1]
	var third: Card = view._cards[2]

	view._move_in_row(first, view._slot_rect(view._metrics(), 2).get_center())

	assert_eq(view._cards, [second, third, first],
			"The card moves to the slot it was dropped on")
	view._finish()
	await wait_until(func(): return deck._clarividencia == null, 4)

	assert_eq(deck.get_top_cards(3), [second, third, first],
			"The deck keeps the row order, leftmost on top")


func test_clairvoyance_drags_one_card_to_the_hand():
	deck._show_top_cards(3)
	var view = deck._clarividencia
	await wait_until(func(): return view._row_ready, 6)
	var hand_count: int = hand.get_card_count()
	var first: Card = view._cards[0]
	var second: Card = view._cards[1]
	var hand_shape: CollisionShape2D = hand.get_node("CollisionShape2D")
	var hand_point: Vector2 = view.get_global_transform_with_canvas() \
			.affine_inverse() * hand_shape.global_position

	view._begin_drag(view._slot_rect(view._metrics(), 0).get_center())
	assert_eq(first.state, Card.CardState.DRAGGED,
			"The peeked card can be picked up")
	view._end_drag(hand_point)

	assert_eq(hand.get_card_count(), hand_count + 1,
			"The dragged peeked card is drawn into the hand")
	assert_eq(first.get_parent(), hand, "The card leaves the table")
	assert_eq(view._cards.size(), 2, "The drawn card leaves the row")

	await yield_for(0.4)
	view._begin_drag(view._slot_rect(view._metrics(), 0).get_center())
	view._end_drag(hand_point)

	assert_eq(hand.get_card_count(), hand_count + 1,
			"Only one peeked card goes to the hand")
	assert_eq(second.get_parent(), board, "The refused card stays in the row")
	assert_eq(view._cards.size(), 2, "The row keeps its cards")

	view._finish()
	await wait_until(func(): return deck._clarividencia == null, 4)
	assert_eq(second.get_parent(), deck, "Closing returns the remaining card")


func test_searched_card_is_revealed_then_added_to_hand():
	var card: Card = deck.get_top_card()
	deck._reveal_searched_card(card)

	await wait_until(func(): return card.get_parent() == board, 2)
	assert_eq(card.get_parent(), board,
			"The selected card is revealed on the table first")
	await wait_until(func(): return card.get_parent() == hand, 6)

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
