extends "res://tests/UTcommon.gd"

class TestMoveToContainer:
	extends "res://tests/Basic_common.gd"

	func test_move_to_container():
		var card: Card
		card = cards[2]
		await drag_drop(card, cfc.NMAP.discard.position)
		await yield_to(card._tween, "tween_all_completed", 0.5)
		await yield_to(card._tween, "tween_all_completed", 0.5)
		assert_almost_eq(card.global_position,cfc.NMAP.discard.position,Vector2(2,2),
				"Card's final position matches pile's position")
		assert_eq(1,cfc.NMAP.discard.get_card_count(),
				"The correct amount of cards are hosted")

	func test_move_to_multiple_container():
		await drag_drop(cards[2], cfc.NMAP.discard.position + Vector2(10,10))
		await move_mouse(Vector2(500,300))
		await drag_drop(cards[4], cfc.NMAP.deck.position + Vector2(10,10))
		await move_mouse(Vector2(500,300))
		await drag_drop(cards[1], cfc.NMAP.discard.position + Vector2(10,10))
		await move_mouse(Vector2(500,300))
		await drag_drop(cards[0], cfc.NMAP.deck.position + Vector2(10,10))
		await yield_to(cards[0]._tween, "tween_all_completed", 0.5)
		await yield_to(cards[0]._tween, "tween_all_completed", 0.5)
		assert_almost_eq(cards[2].global_position,
				cfc.NMAP.discard.global_position,Vector2(2,2),
				"Card 2 final position matches pile's position")
		assert_almost_eq(cards[1].global_position,
				cfc.NMAP.discard.global_position,Vector2(2,2),
				"Card 1 final position matches pile's position")
		assert_almost_eq(cards[4].global_position,
				cfc.NMAP.deck.position + cfc.NMAP.deck.get_stack_position(cards[4]),
				Vector2(2,2),
				"Card 3 final position matches pile's position")
		assert_almost_eq(cards[0].global_position,
				cfc.NMAP.deck.to_global(cfc.NMAP.deck.get_stack_position(cards[0])),Vector2(2,2),
				"Card 0 final position matches pile's position")
		assert_eq(2,cfc.NMAP.discard.get_card_count(),
				"Correct amount of cards are hosted in discard")
		assert_eq(14,cfc.NMAP.deck.get_card_count(),
				"Correct amount of cards are hosted in deck")
		assert_eq(1,cfc.NMAP.hand.get_card_count(),
				"Correct amount of cards are hosted in hand")

	func test_move_from_board_to_deck_to_hand():
		var card: Card
		card = cards[2]
		await drag_drop(card, Vector2(1000,100))
		await drag_drop(card, cfc.NMAP.deck.position)
		await yield_to(card._tween, "tween_all_completed", 0.5)
		await yield_to(card._tween, "tween_all_completed", 0.5)
	# warning-ignore:return_value_discarded
		hand.draw_card()
		await yield_to(card._tween, "tween_all_completed", 0.5)
		await yield_to(card._tween, "tween_all_completed", 0.5)
		assert_almost_eq(hand.to_global(card.recalculate_position()),
				card.global_position,Vector2(2,2),
				"Card finished move to hand from deck from board")

class TestPileFacing:
	extends "res://tests/Basic_common.gd"

	func test_pile_facing():
		var card: Card = cfc.NMAP.deck.get_top_card()
		card.move_to(cfc.NMAP.discard)
		await yield_to(card._tween, "tween_all_completed", 0.5)
		await yield_to(card._tween, "tween_all_completed", 0.5)
		assert_true(card.is_faceup, "Card should be faceup in discard")
		card = cards[0]
		card.move_to(cfc.NMAP.deck)
		await yield_to(card._tween, "tween_all_completed", 0.5)
		await yield_to(card._tween, "tween_all_completed", 0.5)
		assert_false(card.is_faceup,"Card should be facedown in deck")

class TestPopupView:
	extends "res://tests/Basic_common.gd"

	func test_popup_discard_view():
		var discard = cfc.NMAP.discard
		for card in cfc.NMAP.deck.get_all_cards():
			card.move_to(discard)
		await yield_for(1)
		discard._on_View_Button_pressed()
		await yield_for(1)
		for child in discard.get_children():
			assert_false(child is Card,
					"No cards should appear in the pile root after popup")
		assert_eq(12,discard.get_card_count(),
				"Cards in popup should be returned with get_all_cards()")
		assert_eq(12,discard.get_node("ViewPopup/PopupContent/CardView").get_child_count(),
				"All cards all migrated to popup window")
		assert_true(discard.get_node("ViewPopup").visible,
				"ViewPopup should be visible")
		for slot in discard.get_node("ViewPopup/PopupContent/CardView").get_children():
			assert_true(slot.get_child(0).visible,
					"Every card in the popup should be visible")
		cards[1].move_to(discard)
		await yield_for(1)
		assert_eq(13,discard.get_node("ViewPopup/PopupContent/CardView").get_child_count(),
				"Hosting a card in the pile, while popup is open, puts it in the popup")
		var hand_scale: float = cfc.NMAP.hand.card_display_scale
		assert_eq(Vector2(1,1) * hand_scale, cards[1].scale,
				"Moving a card into the popup, should scale it to the hand size")
		assert_almost_eq(Vector2(CFConst.CARD_SIZE.x, CFConst.CARD_SIZE.y) * hand_scale,
				cards[1].get_parent().custom_minimum_size, Vector2(1,1),
				"The popup slot should fit the hand-sized card")
		pending("Drawing a card from the pile, picks it from the popup")
		assert_false(discard.get_node("Control/ManipulationButtons").visible,
				"Manipulation Buttons should be hidden while popup is active")
		discard.get_node("ViewPopup").hide()
		await yield_for(1)
		assert_true(cards[1].is_faceup,
				"Cards returning from popup should respect piles card facing")

	func test_popup_discard_drops_slots_of_card_that_left():
		var discard = cfc.NMAP.discard
		for card in cfc.NMAP.deck.get_all_cards():
			card.move_to(discard)
		await yield_for(1)
		discard._on_View_Button_pressed()
		await yield_for(1)
		var grid: GridContainer = discard.get_node("ViewPopup/PopupContent/CardView")
		var card: Card = discard.pre_sorted_order[0]
		var slot: Control = card.get_parent()
		card.move_to(cfc.NMAP.deck)
		await yield_for(0.5)
		assert_false(is_instance_valid(slot),
				"The slot of a card that left the popup should be dropped")
		assert_eq(11, grid.get_child_count(),
				"The popup should keep only the remaining cards")
		discard.get_node("ViewPopup").hide()
		await yield_for(1)

	func test_view_on_an_empty_pile_keeps_the_popup_closed():
		var discard = cfc.NMAP.discard
		assert_eq(0, discard.get_all_cards(false).size(),
				"The resources start empty")
		discard._on_View_Button_pressed()
		await yield_for(0.2)

		assert_false(discard.is_popup_open,
				"An empty viewer does not open")
		assert_false(discard.pile_popup.visible,
				"No empty window covers the board")

	func test_popup_deck_view():
		var deck = cfc.NMAP.deck
		var card: Card = deck.get_top_card()
		deck._on_View_Button_pressed()
		# PopupPanel is a Window in Godot 4: it no longer fades in through a
		# tween child, so just give the popup a frame to settle.
		await yield_for(0.5)
		card.move_to(deck)
		await yield_for(0.3)
		assert_eq(Vector2(0,0),card.position,
				"Moving card from popup back to the same pile, should do nothing")
		assert_eq(Vector2(0.75,0.75),card.scale,
				"Moving card from popup back to the same pile, should do nothing")
		assert_true(card.is_faceup,
				"Moving card from popup back to the same pile, should do nothing")
		deck.get_node("ViewPopup").hide()
		await yield_for(1)
		assert_false(card.is_faceup,
				"Cards returning from popup should respect piles card facing")

class TestStacking:
	extends "res://tests/Basic_common.gd"

	func test_stacking():
		var deck : Pile = cfc.NMAP.deck
		var card: Card = cards[4]
		card.move_to(deck)
		await yield_to(card._tween, "tween_all_completed", 0.5)
		await yield_to(card._tween, "tween_all_completed", 0.5)
		assert_eq(deck.get_stack_position(card),card.position,
				"Card moved in, placed in stack position")
		card = cards[2]
		card.move_to(deck)
		await yield_to(card._tween, "tween_all_completed", 0.5)
		await yield_to(card._tween, "tween_all_completed", 0.5)
		assert_eq(deck.get_stack_position(card),card.position,
				"Card moved in, placed in stack position")
		deck.shuffle_cards(false)
		assert_eq(deck.get_stack_position(card),card.position,
				"Reshuffle, restacks cards correctly.")

class TestShuffleRng:
	extends "res://tests/Basic_common.gd"

	func test_shuffle_rng():
		var rng_threshold: int = 0
		var card = deck.get_bottom_card()
		var prev_index = card.get_my_card_index()
		deck.shuffle_cards()
		await yield_for(1)
		if prev_index == card.get_my_card_index():
			rng_threshold += 1
		prev_index = card.get_my_card_index()
		deck.shuffle_cards()
		await yield_for(1)
		if prev_index == card.get_my_card_index():
			rng_threshold += 1
		prev_index = card.get_my_card_index()
		deck.shuffle_cards()
		await yield_for(1)
		if prev_index == card.get_my_card_index():
			rng_threshold += 1
		prev_index = card.get_my_card_index()
		assert_gt(2,rng_threshold,
			"Card should not fall in he same spot too many times")


class TestDeckSearch:
	extends "res://tests/Basic_common.gd"

	func _deck_order() -> Array:
		var order := []
		for card in deck.get_all_cards(false):
			order.append(card.get_instance_id())
		return order

	# Cancelling the search leaves the deck in the order the player browsed, so
	# it has to be shuffled as soon as the window closes.
	func test_cancelling_the_search_shuffles_the_deck():
		var window = load("res://src/core/SelectionWindow.tscn").instantiate()
		window.is_cancelled = true
		var before := _deck_order()
		deck._on_search_window_closed(window)
		await yield_for(0.4)
		assert_ne(_deck_order(), before, "Cancelar embaralha o deck")
		window.free()


class TestPileDisplayScale:
	extends "res://tests/Basic_common.gd"

	func test_scaled_pile_keeps_card_display_scale():
		var scaled_pile: Pile = add_child_autofree(
				load("res://src/core/Pile.tscn").instantiate())
		scaled_pile.card_size = Vector2(120, 168)
		scaled_pile.card_display_scale = 0.8
		await yield_for(0.1)
		var card: Card = cards[0]
		card.move_to(scaled_pile)
		await yield_for(1)
		assert_eq(Vector2(0.8, 0.8), card.scale,
				"Card keeps the pile display scale while idle in the pile")
		assert_eq(scaled_pile.get_stack_position(card), card.position,
				"Card is stacked inside the scaled pile")


class TestResourceSendActions:
	extends "res://tests/Basic_common.gd"

	# The viewer needs resources to send, so a few deck cards are moved over to
	# become the pool the tests pick from.
	func _open_resources_view(card_count := 3) -> void:
		var deck: Pile = cfc.NMAP.deck
		for index in range(card_count):
			deck.get_top_card().move_to(cfc.NMAP.discard)
		await yield_for(0.3)
		cfc.NMAP.discard._on_View_Button_pressed()
		await yield_for(0.3)

	func test_pile_panel_gains_the_deck_buttons():
		var panel: Control = cfc.NMAP.discard.get_node(
				"Control/ManipulationButtons/ResourceButtonGrid")
		assert_true(panel.has_node("SendDeck"),
				"The resource panel offers the send to the deck")
		assert_false(panel.has_node("SendTop"),
				"The separate deck top button is gone")
		assert_false(panel.has_node("SendBase"),
				"The separate deck base button is gone")
		assert_eq("Enviar deck", panel.get_node("SendDeck").text,
				"The send button names the deck")
		assert_eq("+ personagem", panel.get_node("AddPerso").text,
				"The panel offers one more resource on a character")
		assert_eq("Adiciona carta ao personagem escolhido",
				panel.get_node("AddPerso").tooltip_text,
				"The add button explains itself on hover")
		assert_eq(2, panel.columns,
				"The panel buttons sit in two columns")
		assert_eq("SendDeck", str(panel.get_child(0).name),
				"The send to the deck opens the grid")
		assert_eq("View", str(panel.get_child(1).name),
				"Ver stays to its right")
		assert_eq("SwapResource", str(panel.get_child(2).name),
				"Trocar opens the second row")
		assert_eq("AddPerso", str(panel.get_child(3).name),
				"Add perso stays to its right")

	func test_panel_send_button_opens_the_viewer_without_arming():
		var discard = cfc.NMAP.discard
		cfc.NMAP.deck.get_top_card().move_to(discard)
		await yield_for(0.3)
		discard._on_SendDeck_pressed()
		await yield_for(0.1)
		assert_true(discard.is_popup_open,
				"The panel button brings the send menu on screen")
		assert_eq("", cfc.NMAP.board.pending_resource_send_side,
				"The panel button leaves the side to the viewer")
		assert_false(discard._send_deck_panel.button_pressed,
				"The entry button does not stay pressed")

	func test_pressing_the_armed_side_again_cancels_the_send():
		await _open_resources_view()
		var discard = cfc.NMAP.discard
		var deck: Pile = cfc.NMAP.deck
		var count_before := deck.get_card_count()
		discard._on_SendTop_pressed()
		await yield_for(0.1)
		assert_eq("topo", cfc.NMAP.board.pending_resource_send_side,
				"The viewer button armed the send to the deck top")
		discard._on_SendTop_pressed()
		await yield_for(0.1)

		assert_eq("", cfc.NMAP.board.pending_resource_send_side,
				"The same side pressed again cancels the send")
		assert_false(discard._popup_send_top.button_pressed,
				"The viewer button shows the cancel")
		var card: Card = discard.pre_sorted_order[0]
		assert_false(cfc.NMAP.board.send_resource_from_popup(card),
				"A cancelled send does not handle the card click")
		assert_eq(count_before, deck.get_card_count(),
				"The deck keeps its cards after the cancel")

	func test_viewer_offers_the_actions_under_the_grid():
		await _open_resources_view()
		var discard = cfc.NMAP.discard
		var actions: Control = discard.get_node(
				"ViewPopup/PopupContent/ResourceActions")
		assert_eq(4, actions.get_child_count(),
				"The viewer row holds both deck ends, the hand and the add")
		assert_eq("Enviar topo do deck", actions.get_child(0).text,
				"First viewer action sends to the top of the deck")
		assert_eq("Enviar base do deck", actions.get_child(1).text,
				"Second viewer action sends to the base of the deck")
		assert_eq("Adicionar à mão", actions.get_child(2).text,
				"Third viewer action adds to the hand")
		assert_eq("Adiciona personagem", actions.get_child(3).text,
				"The viewer offers the add to a character")
		assert_eq("Adiciona carta ao personagem escolhido",
				actions.get_child(3).tooltip_text,
				"The viewer add button explains itself on hover")
		assert_true(actions.get_child(0).toggle_mode,
				"The deck top send arms before the card click")
		assert_true(actions.get_child(1).toggle_mode,
				"The deck base send arms before the card click")
		assert_true(actions.get_child(2).toggle_mode,
				"The hand send arms before the card click")
		assert_true(actions.get_child(3).toggle_mode,
				"The add arms before the card click")
		var grid: Control = discard.get_node(
				"ViewPopup/PopupContent/CardView")
		assert_almost_eq(grid.position.y + grid.size.y + 10.0,
				actions.position.y, 1.0,
				"The action row hangs under the card grid")
		assert_almost_eq(grid.position.x, actions.position.x, 1.0,
				"The action row starts where the card grid starts")
		assert_almost_eq(grid.size.x, actions.size.x, 1.0,
				"The action row spans the card grid")

	func test_viewer_top_button_arms_the_deck_top_send():
		await _open_resources_view()
		var discard = cfc.NMAP.discard
		var message: Label = discard.viewer_message_label()
		discard._popup_send_top.emit_signal("pressed")
		await yield_for(0.1)

		assert_eq("topo", cfc.NMAP.board.pending_resource_send_side,
				"The viewer button arms the deck top")
		assert_true(discard._popup_send_top.button_pressed,
				"The armed viewer button stays pressed")
		assert_eq("Enviar para o topo do Deck: "
				+ "clique numa carta dos Recursos.", message.text,
				"The viewer names the deck top")

	func test_viewer_base_button_arms_the_deck_base_send():
		await _open_resources_view()
		var discard = cfc.NMAP.discard
		var message: Label = discard.viewer_message_label()
		discard._popup_send_base.emit_signal("pressed")
		await yield_for(0.1)

		assert_eq("base", cfc.NMAP.board.pending_resource_send_side,
				"The viewer button arms the deck base")
		assert_true(discard._popup_send_base.button_pressed,
				"The armed viewer button stays pressed")
		assert_eq("Enviar para a base do Deck: "
				+ "clique numa carta dos Recursos.", message.text,
				"The viewer names the deck base")

	func test_viewer_add_button_arms_the_character_pick():
		await _open_resources_view()
		var discard = cfc.NMAP.discard
		var message: Label = discard.viewer_message_label()
		discard._popup_add_perso.emit_signal("pressed")
		await yield_for(0.1)

		assert_true(cfc.NMAP.board.pending_resource_add_active,
				"The viewer button arms the add")
		assert_eq("", cfc.NMAP.board.pending_resource_send_side,
				"Arming the add disarms the sends")
		assert_true(discard._popup_add_perso.button_pressed,
				"The viewer add button stays pressed")
		assert_true(discard._add_perso_panel.button_pressed,
				"The panel add button mirrors the armed mode")
		assert_eq("", message.text,
				"The add arms without a written instruction")

	func test_viewer_top_send_leaves_the_clicked_card_on_top_of_the_deck():
		await _open_resources_view()
		var discard = cfc.NMAP.discard
		var deck: Pile = cfc.NMAP.deck
		var count_before := deck.get_card_count()
		var card: Card = discard.pre_sorted_order[0]
		discard._on_SendTop_pressed()
		await yield_for(0.1)

		assert_true(cfc.NMAP.board.send_resource_from_popup(card),
				"The armed click handles the resource card")
		await yield_for(0.3)

		assert_eq("", cfc.NMAP.board.pending_resource_send_side,
				"The click ends the armed mode")
		assert_true(card.get_parent() == deck,
				"The clicked resource reached the deck")
		assert_eq(count_before + 1, deck.get_card_count(),
				"The deck gained the resource")
		assert_eq(card, deck.get_top_card(),
				"Topo leaves the sent card on top of the deck")
		assert_false(discard.pre_sorted_order.has(card),
				"The viewer stops counting the card that left")

	func test_viewer_base_send_leaves_the_clicked_card_at_the_deck_base():
		await _open_resources_view()
		var discard = cfc.NMAP.discard
		var deck: Pile = cfc.NMAP.deck
		var count_before := deck.get_card_count()
		var card: Card = discard.pre_sorted_order[0]
		discard._on_SendBase_pressed()
		await yield_for(0.1)

		assert_true(cfc.NMAP.board.send_resource_from_popup(card),
				"The armed click handles the resource card")
		await yield_for(0.3)

		assert_eq("", cfc.NMAP.board.pending_resource_send_side,
				"The click ends the armed mode")
		assert_eq(count_before + 1, deck.get_card_count(),
				"The deck keeps the sent card")
		assert_eq(card, deck.get_bottom_card(),
				"Base leaves the sent card at the bottom of the deck")
		assert_false(discard.pre_sorted_order.has(card),
				"The viewer stops counting the card that left")

	func test_sending_the_last_resource_closes_the_viewer():
		await _open_resources_view(1)
		var discard = cfc.NMAP.discard
		var deck: Pile = cfc.NMAP.deck
		var card: Card = discard.pre_sorted_order[0]
		discard._on_SendTop_pressed()
		await yield_for(0.1)
		assert_true(discard.is_popup_open, "The viewer is open before the send")

		assert_true(cfc.NMAP.board.send_resource_from_popup(card),
				"The armed click handles the resource card")
		await yield_for(0.2)

		assert_true(card.get_parent() == deck,
				"The resource reached the deck")
		assert_true(discard.pre_sorted_order.is_empty(),
				"The viewer stops counting the last resource")
		assert_false(discard.is_popup_open,
				"The viewer closes with the last resource")
		assert_false(discard.pile_popup.visible,
				"No empty viewer stays over the field")

	func test_send_hand_moves_the_clicked_resource_into_the_hand():
		await _open_resources_view()
		var discard = cfc.NMAP.discard
		var deck: Pile = cfc.NMAP.deck
		var hand: CardContainer = cfc.NMAP.hand
		var deck_before := deck.get_card_count()
		var hand_before := hand.get_card_count()
		var card: Card = discard.pre_sorted_order[0]

		discard._on_SendHand_pressed()
		await yield_for(0.1)
		assert_eq("mao", cfc.NMAP.board.pending_resource_send_side,
				"The viewer button arms the send to the hand")

		assert_true(cfc.NMAP.board.send_resource_from_popup(card),
				"The armed click handles the resource card")
		await yield_for(0.2)

		assert_true(card.get_parent() == hand,
				"The clicked resource reached the hand")
		assert_eq(hand_before + 1, hand.get_card_count(),
				"The hand gained the resource")
		assert_eq(deck_before, deck.get_card_count(),
				"The deck keeps every card")
		assert_eq("", cfc.NMAP.board.pending_resource_send_side,
				"The card click ends the armed mode")
		assert_false(discard.pre_sorted_order.has(card),
				"The viewer stops counting the card that left")

	func test_viewer_writes_its_messages_under_the_card_grid():
		await _open_resources_view()
		var discard = cfc.NMAP.discard
		var message: Label = discard.viewer_message_label()
		assert_true(is_instance_valid(message),
				"The viewer owns a message label")

		discard._on_SendTop_pressed()
		await yield_for(0.1)

		assert_eq("Enviar para o topo do Deck: "
				+ "clique numa carta dos Recursos.", message.text,
				"The instruction lands inside the viewer")
		assert_eq(discard.get_node("ViewPopup/PopupContent"),
				message.get_parent(),
				"The message lives under the card box, not on the board")
