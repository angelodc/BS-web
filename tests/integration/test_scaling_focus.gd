extends "res://tests/UTcommon.gd"

class TestSingleCardFocus:
	extends "res://tests/Basic_common.gd"

	func test_single_card_focus_use_rectangle():
		cfc.game_settings.hand_use_oval_shape = false
		cards[0]._on_Card_mouse_entered()
		await yield_to(cards[0]._tween, "tween_all_completed", 1)
		assert_almost_eq(Vector2(257.5, -210),cards[0].position,Vector2(2,2),
				"Card dragged in correct global position")
		assert_almost_eq(Vector2(1.5, 1.5),cards[0].scale,Vector2(0.1,0.1),
				"Card has correct scale")
		cards[0]._on_Card_mouse_exited()
		await yield_to(cards[0]._tween, "tween_all_completed", 1)
		assert_almost_eq(cards[0].recalculate_position(),cards[0].position,Vector2(2,2),
				"Card placed in correct global position")
		assert_almost_eq(Vector2(0.5, 0.5),cards[0].scale,Vector2(0.1,0.1),
				"Card has correct scale")
		cfc.game_settings.hand_use_oval_shape = true

	func test_single_card_focus_use_oval():
		cfc.game_settings.hand_use_oval_shape = true
		cards[0]._on_Card_mouse_entered()
		await yield_to(cards[0]._tween, "tween_all_completed", 1)
		assert_almost_eq(Vector2(87.27745, -210.20842),cards[0].position,Vector2(2,2),
				"Card dragged in correct global position")
		assert_almost_eq(Vector2(1.5, 1.5),cards[0].scale,Vector2(0.1,0.1),
				"Card has correct scale")
		cards[0]._on_Card_mouse_exited()
		await yield_to(cards[0]._tween, "tween_all_completed", 1)
		assert_almost_eq(cards[0].recalculate_position(),cards[0].position,Vector2(2,2),
				"Card placed in correct global position")
		assert_almost_eq(Vector2(0.5, 0.5),cards[0].scale,Vector2(0.1,0.1),
				"Card has correct scale")
		cfc.game_settings.hand_use_oval_shape = true

class TestNeightbourPush:
	extends "res://tests/Basic_common.gd"

	func test_card_focus_neighbour_push_use_rectangle():
		cfc.game_settings.hand_use_oval_shape = false
		cards[2]._on_Card_mouse_entered()
		await yield_for(1)
		# Both sides of the focused card spread apart, each as a single shifted
		# block so the resting gap between those cards is kept (no piling behind
		# each other). The nearest cards tuck 12 px under the enlarged card, so
		# the mouse never crosses a dead gap between them.
		assert_almost_eq(Vector2(253.0, 0),cards[0].position,Vector2(2,2),
				"Card dragged in correct global position")
		assert_almost_eq(Vector2(311.5, 0),cards[1].position,Vector2(2,2),
				"Card dragged in correct global position")
		assert_almost_eq(Vector2(587.5, 0),cards[3].position,Vector2(2,2),
				"Card dragged in correct global position")
		assert_almost_eq(Vector2(646.0, 0),cards[4].position,Vector2(2,2),
				"Card dragged in correct global position")
		cfc.game_settings.hand_use_oval_shape = true

	func test_card_focus_neighbour_push_use_oval():
		cfc.game_settings.hand_use_oval_shape = true
		cards[2]._on_Card_mouse_entered()
		await yield_for(1)
		# The oval spacing is wider than the enlarged card, so both side blocks
		# tuck in under it until they touch.
		assert_almost_eq(Vector2(171.365, -26.20842),cards[0].position,Vector2(2,2),
				"Card dragged in correct global position")
		assert_almost_eq(Vector2(311.5, -45.83563),cards[1].position,Vector2(2,2),
				"Card dragged in correct global position")
		assert_almost_eq(Vector2(587.5, -45.83563),cards[3].position,Vector2(2,2),
				"Card dragged in correct global position")
		assert_almost_eq(Vector2(727.6349, -26.20842),cards[4].position,Vector2(2,2),
				"Card dragged in correct global position")
		cfc.game_settings.hand_use_oval_shape = true

class TestChangeFocusNeighbour:
	extends "res://tests/Basic_common.gd"

	func test_card_change_focus_to_neighbour():
		var YIELD_TIME := 0.07
		var YIELD_TIME2 := 0.5
		cards[2]._on_Card_mouse_entered()
		await yield_for(YIELD_TIME)
		cards[2]._on_Card_mouse_exited()
		cards[3]._on_Card_mouse_entered()
		await yield_for(YIELD_TIME)
		cards[3]._on_Card_mouse_exited()
		cards[4]._on_Card_mouse_entered()
		await yield_for(YIELD_TIME2)
		cards[4]._on_Card_mouse_exited()
		cards[3]._on_Card_mouse_entered()
		await yield_for(YIELD_TIME)
		cards[3]._on_Card_mouse_exited()
		cards[2]._on_Card_mouse_entered()
		await yield_for(YIELD_TIME)
		cards[2]._on_Card_mouse_exited()
		cards[1]._on_Card_mouse_entered()
		await yield_for(YIELD_TIME2)
		cards[1]._on_Card_mouse_exited()
		cards[0]._on_Card_mouse_entered()
		await yield_for(YIELD_TIME2)
		cards[0]._on_Card_mouse_exited()
		await yield_to(cards[0]._tween, "tween_all_completed", 1)
		assert_almost_eq(cards[0].recalculate_position(),
				cards[0].position,Vector2(2,2),
				"Card dragged in correct global position")
		assert_almost_eq(cards[1].recalculate_position(),
				cards[1].position,Vector2(2,2),
				"Card dragged in correct global position")
		assert_almost_eq(cards[2].recalculate_position(),
				cards[2].position,Vector2(2,2),
				"Card dragged in correct global position")
		assert_almost_eq(cards[3].recalculate_position(),
				cards[3].position,Vector2(2,2),
				"Card dragged in correct global position")
		assert_almost_eq(cards[4].recalculate_position(),
				cards[4].position,Vector2(2,2),
				"Card dragged in correct global position")

class TestHoverContinuity:
	extends "res://tests/Basic_common.gd"

	# The game hand is wider than this test's default hand (the 1280x720 board
	# leaves more than 1100 px for it). With a wider hand the resting fan is
	# spread further apart, so the side blocks must tuck further under the
	# enlarged card. If they stop short, the mouse crosses a dead gap, the hover
	# is lost, the fan collapses and the neighbour slides back behind the
	# pointer: the player sees the first card on each side skipped.
	func test_side_blocks_tuck_under_the_focused_card():
		for hand_width in [974.0, 1124.0, 1230.0]:
			hand.get_node("Control").size.x = hand_width
			cards[2]._on_Card_mouse_entered()
			await yield_for(0.8)
			var focused_left: float = cards[2].position.x
			var focused_right: float = focused_left \
					+ cards[2].card_size.x * CFConst.FOCUSED_SCALE
			var resting_width: float = cards[2].card_size.x \
					* cards[2]._get_hand_display_scale()
			# At least 8 px of overlap on each side keeps both areas around the
			# mouse while the hover swaps (the pointer radius is 2 px).
			assert_true(cards[1].position.x + resting_width >= focused_left + 8,
					"Left neighbour tucks under the focused card at %s px (gap %s)"
					% [hand_width, focused_left
					- cards[1].position.x - resting_width])
			assert_true(cards[3].position.x <= focused_right - 8,
					"Right neighbour tucks under the focused card at %s px (gap %s)"
					% [hand_width,
					cards[3].position.x - focused_right])
			assert_true(cards[0].position.x >= 0,
					"Left block stays inside the hand at %s px" % hand_width)
			assert_true(cards[4].position.x + resting_width <= hand_width,
					"Right block stays inside the hand at %s px" % hand_width)
			cards[2]._on_Card_mouse_exited()
			await yield_for(0.5)

	func test_full_hand_keeps_the_hover_gap_closed():
		hand.get_node("Control").size.x = 1124.0
		for _iter in range(0, 5):
			hand.draw_card()
			await yield_for(0.07)
		await yield_for(1)
		var middle: Card = hand.get_card(5)
		middle._on_Card_mouse_entered()
		await yield_for(1)
		var focused_left: float = middle.position.x
		var focused_right: float = focused_left \
				+ middle.card_size.x * CFConst.FOCUSED_SCALE
		var resting_width: float = middle.card_size.x \
				* middle._get_hand_display_scale()
		var left_neighbour: Card = hand.get_card(4)
		var right_neighbour: Card = hand.get_card(6)
		assert_true(left_neighbour.position.x + resting_width >= focused_left + 8,
				"Left neighbour tucks under the focused card (gap %s)"
				% [focused_left - left_neighbour.position.x - resting_width])
		assert_true(right_neighbour.position.x <= focused_right - 8,
				"Right neighbour tucks under the focused card (gap %s)"
				% [right_neighbour.position.x - focused_right])
		var first: Card = hand.get_card(0)
		var last: Card = hand.get_card(hand.get_card_count() - 1)
		assert_true(first.position.x >= 0, "Left block stays inside the hand")
		assert_true(last.position.x + resting_width <= 1124.0,
				"Right block stays inside the hand")
		middle._on_Card_mouse_exited()

	# End-to-end version of the bug: sweep the real virtual mouse across the
	# hand and record which card gets the hover at every step. A gap between the
	# enlarged card and its neighbours shows up as a skipped card here.
	func _sweep_hand(direction: int, final_index: int) -> Array:
		hand.get_node("Control").size.x = 1124.0
		for c in cards:
			c.interruptTweening()
			c.reorganize_self()
		await yield_for(0.5)
		var middle: Card = cards[2]
		var start: Vector2 = middle.global_position + Vector2(40, 60)
		await move_mouse(start, "fast")
		await yield_for(0.5)
		assert_eq(board.mouse_pointer.current_focused_card, middle,
				"The mouse starts focused on the middle card")
		var seen := [middle]
		var x: float = start.x
		for _step in range(0, 40):
			x += 10 * direction
			await move_mouse(Vector2(x, start.y), "fast")
			var focused: Card = board.mouse_pointer.current_focused_card
			assert_true(focused != null,
					"Some card keeps the hover at x=%s" % x)
			if focused != null and not focused in seen:
				seen.append(focused)
			if focused == cards[final_index]:
				break
		return seen

	func test_mouse_sweep_right_does_not_skip_hand_cards():
		var seen: Array = await _sweep_hand(1, 4)
		assert_eq(seen, [cards[2], cards[3], cards[4]],
				"Sweeping right visits every card without skipping one")
		cards[4]._on_Card_mouse_exited()
		await yield_for(0.5)

	func test_mouse_sweep_left_does_not_skip_hand_cards():
		var seen: Array = await _sweep_hand(-1, 0)
		assert_eq(seen, [cards[2], cards[1], cards[0]],
				"Sweeping left visits every card without skipping one")
		cards[0]._on_Card_mouse_exited()
		await yield_for(0.5)

	func test_mouse_sweep_in_rectangle_hand_does_not_skip():
		cfc.game_settings.hand_use_oval_shape = false
		var seen: Array = await _sweep_hand(1, 4)
		assert_eq(seen, [cards[2], cards[3], cards[4]],
				"The rectangle hand visits every card without skipping one")
		cards[4]._on_Card_mouse_exited()
		await yield_for(0.5)
		cfc.game_settings.hand_use_oval_shape = true

class TestHandCardSlide:
	extends "res://tests/Basic_common.gd"

	func test_card_hand_mouseslide():
		var YIELD_TIME := 0.02
		cards[0]._on_Card_mouse_entered()
		await yield_for(YIELD_TIME)
		cards[0]._on_Card_mouse_exited()
		await yield_for(YIELD_TIME)
		cards[1]._on_Card_mouse_entered()
		await yield_for(YIELD_TIME)
		cards[2]._on_Card_mouse_entered()
		await yield_for(YIELD_TIME)
		cards[1]._on_Card_mouse_exited()
		await yield_for(YIELD_TIME)
		cards[3]._on_Card_mouse_entered()
		await yield_for(YIELD_TIME)
		cards[2]._on_Card_mouse_exited()
		await yield_for(YIELD_TIME)
		cards[4]._on_Card_mouse_entered()
		await yield_for(YIELD_TIME)
		cards[3]._on_Card_mouse_exited()
		await yield_for(YIELD_TIME)
		#cards[4]._on_Card_mouse_entered()
		await yield_to(cards[4]._tween, "tween_all_completed", 1)
		assert_eq(cards[4].state,Card.CardState.FOCUSED_IN_HAND, "Card is Focused")
