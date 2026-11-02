extends "res://tests/UTcommon.gd"

var cards := []

func before_each():
	await setup_board()
	cards = draw_test_cards(5)
	await yield_for(0.1)

func after_each():
	cfc.game_settings.fancy_movement = true

# CGFBoard dropped reshuffle_all_in_pile() with the pile overhaul (2ca1a04),
# so these two tests exercise a framework method Battle Scenes no longer has.
func test_fancy_reshuffle_all():
	pending("reshuffle_all_in_pile() was removed from CGFBoard in 2ca1a04")
	return

func test_basic_reshuffle_all():
	pending("reshuffle_all_in_pile() was removed from CGFBoard in 2ca1a04")
	return
