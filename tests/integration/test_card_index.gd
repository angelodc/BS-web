extends "res://tests/UTcommon.gd"

var cards := []

func before_each():
	await setup_board()
	hand = cfc.NMAP.hand
	cards.clear()

func test_hand_z_index():
	for _iter in range(0,8):
		cards.append(hand.draw_card())
		await yield_for(0.07)
	await yield_for(1)
	for card in cards:
		assert_eq(0,card.z_index,"Card in hand at index 0")

func test_table_hand_z_index():
	for _iter in range(0,8):
		cards.append(hand.draw_card())
		await yield_for(0.07)
	await yield_for(1)
	await table_move(cards[0],Vector2(300,100))
	await table_move(cards[1],Vector2(300,200))
	await table_move(cards[5],Vector2(300,300))
	await table_move(cards[7],Vector2(300,400))
	await drag_drop(cards[0],Vector2(300,650))
	cards.append(hand.draw_card())
	await yield_for(0.1)
	cards.append(hand.draw_card())
	await yield_for(0.7)
	await drag_drop(cards[1],Vector2(300,650))
	await move_mouse(Vector2(0,0))
	assert_eq(8,hand.get_card_count(),"Correct amount of cards in hand")
	for c in cards:
		if c.get_parent() == cfc.NMAP.hand:
			assert_eq(0,c.z_index,"Card in hand at index 0")


# A played card is parented under the board after the hand, so at the same z it
# covered the player's cards. The hand keeps a layer of its own above the table.
func test_hand_draws_above_the_table():
	assert_eq(CFConst.TABLE_HAND_Z, hand.z_index,
			"The hand has its own layer above the table")
	for _iter in range(0, 3):
		cards.append(hand.draw_card())
		await yield_for(0.07)
	await yield_for(1)
	await table_move(cards[0], Vector2(300, 500))
	assert_eq(0, cards[0].z_index, "A rested table card stays on the table layer")
	assert_true(hand.z_index > cards[0].z_index,
			"The hand draws over a card played on the table")


# The rows overlap by a few pixels, so the card played last in the row behind
# can hide the one being read. Hovering lifts it over the hand until the mouse
# leaves it again, when the hand goes back over the table.
func test_focused_table_card_lifts_over_its_neighbours():
	for _iter in range(0, 3):
		cards.append(hand.draw_card())
		await yield_for(0.07)
	await yield_for(1)
	await table_move(cards[0], Vector2(300, 500))
	await table_move(cards[1], Vector2(300, 560))
	cards[1]._on_Card_mouse_entered()
	await yield_for(0.1)
	assert_eq(CFConst.TABLE_FOCUS_Z, cards[1].z_index,
			"The card being read comes forward")
	assert_true(cards[1].z_index > cards[0].z_index,
			"It draws over the neighbouring table card")
	assert_true(cards[1].z_index > hand.z_index,
			"It is read above the hand while the pointer is on it")
	cards[1]._on_Card_mouse_exited()
	await yield_for(0.1)
	assert_eq(0, cards[1].z_index,
			"Leaving the card returns it to the table layer")
	assert_true(hand.z_index > cards[1].z_index,
			"The hand draws over the table again")


# The physics overlap list carries no draw order, so picking the hover by the
# index inside each zone handed it to the table card even when the hand draws
# over it. The hover follows the order the cards are actually drawn in.
func test_hover_follows_draw_order():
	for _iter in range(0, 3):
		cards.append(hand.draw_card())
		await yield_for(0.07)
	await yield_for(1)
	await table_move(cards[0], Vector2(300, 500))
	board.mouse_pointer.forget_focus()
	board.mouse_pointer.overlaps = [cards[0], cards[1]]
	board.mouse_pointer._discover_focus()
	assert_eq(cards[1], board.mouse_pointer.current_focused_card,
			"The card drawn on top of the overlap receives the hover")
	board.mouse_pointer.overlaps = []
	board.mouse_pointer.forget_focus()
	cards[1]._on_Card_mouse_exited()

