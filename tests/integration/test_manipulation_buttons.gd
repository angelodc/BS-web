extends "res://tests/UTcommon.gd"

class TestManipulationButtons:
	extends "res://tests/Basic_common.gd"


	func test_manipulation_buttons_not_messing_hand_focus():
		# The focus position asserted below is the oval hand layout; do not let a
		# player's saved settings decide which layout the test runs.
		cfc.game_settings.hand_use_oval_shape = true
		var card = cards[0]
		await move_mouse(card.global_position)
		await move_mouse(card.global_position - Vector2(0,100))
		await yield_for(0.2)
		await move_mouse(card.global_position)
		await move_mouse(card.global_position - Vector2(0,100))
		await yield_for(0.2)
		await move_mouse(card.global_position)
		await yield_to(cards[0]._tween, "tween_all_completed", 1)
		assert_almost_eq(Vector2(87.27745, -210.20842),cards[0].position,Vector2(2,2),
				"Card focused and in correct global position")
		assert_almost_eq(Vector2(1.5, 1.5),cards[0].scale,Vector2(0.1,0.1),
				"Card has correct scale")
