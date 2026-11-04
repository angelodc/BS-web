class_name UTCommon
extends "res://addons/gut/test.gd"

# TODO: I should make 2 scenes just for UT so I don't rely on these which
# might get deleted
const MAIN_SCENE = preload("res://tests/UTMain.tscn")
var BOARD_SCENE = load("res://tests/UTBoard.tscn")
const MOUSE_SPEED := {
	"fast": [10,0.3],
	"slow": [3,0.6],
	"debug": [1,2],
}


var main
var board: Board
var hand: Hand
var deck: Pile
var discard: Pile

func fake_click(pressed, position) -> InputEvent:
	var ev := InputEventMouseButton.new()
	ev.button_index=MOUSE_BUTTON_LEFT
	# `button_pressed` is the BaseButton property; the input event uses `pressed`.
	ev.pressed = pressed
	ev.position = position
	return ev


func setup_main() -> void:
	cfc.is_testing = true
	cfc._setup()
	main = autoqfree(MAIN_SCENE.instantiate())
	get_tree().get_root().add_child(main)
	if not cfc.are_all_nodes_mapped:
		await cfc.all_nodes_mapped
	board = cfc.NMAP.board
	board.load_test_cards()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE) # Always reveal the mouseon unclick
	hand = cfc.NMAP.hand
	deck = cfc.NMAP.deck
	discard = cfc.NMAP.discard


func setup_board() -> void:
	cfc.is_testing = true
	cfc._setup()
	board = add_child_autofree(BOARD_SCENE.instantiate())
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE) # Always reveal the mouseon unclick
	if not cfc.are_all_nodes_mapped:
		await cfc.all_nodes_mapped
	board.load_test_cards()
	hand = cfc.NMAP.hand
	deck = cfc.NMAP.deck
	discard = cfc.NMAP.discard

func teardown_board() -> void:
	cfc.flush_cache()
	cfc.are_all_nodes_mapped = false
	cfc.card_drag_ongoing = null
	cfc.NMAP.clear()


func draw_test_cards(count: int, fast := true) -> Array:
	var cards = []
	for _iter in range(count):
		if fast:
			var card = deck.get_top_card()
			deck.remove_child(card)
			hand.add_child(card)
			card.state = Card.CardState.IN_HAND
			cards.append(card)
		else:
			cards.append(hand.draw_card())
	for c in cards:
		c.interruptTweening()
		c.reorganize_self()
	return cards

func click_card(card: Card, _use_fake_mouse := true, offset:=Vector2(0,0)) -> void:
	# A simulated pointer press lands on the card under the cursor, and the pointer
	# forwards the event to whichever card it last focused. Keep both in sync, or a
	# stale focus from the previous drag swallows the synthetic click. A bare click
	# (no simulated mouse) leaves the pointer alone on purpose: delivering the
	# event to a card must not be the same as hovering it first.
	if _use_fake_mouse and board and is_instance_valid(board.mouse_pointer):
		board.mouse_pointer.current_focused_card = card
	var fc:= fake_click(true, offset)
	card._on_Card_gui_input(fc)

func unclick_card(card: Card) -> void:
	var fc:= fake_click(false, card.global_position)
	card._on_Card_gui_input(fc)

# We need this for targetting arrows which don't release back on the card gui
func unclick_card_anywhere(card: Card) -> void:
	var fc:= fake_click(false, card.global_position)
	card._input(fc)


func drag_card(card: Card, target_position: Vector2, interpolation_speed := "fast") -> void:
	# Cards entering the hand animate to their resting scale and position. Wait
	# for that tween so the simulated mouse targets the card's final position.
	var card_tween = card._tween
	if card_tween.is_active():
		await yield_to(card_tween, "tween_all_completed", 1)
	var mouse_speed = MOUSE_SPEED[interpolation_speed][0]
	var mouse_yield_wait = MOUSE_SPEED[interpolation_speed][1]
	var extra_offset = Vector2(20,20)
	if card.card_rotation in [90,270]:
		extra_offset = Vector2(10,60)
	# Moving the virtual mouse can make the hand focus and reorganize cards, so
	# the target may shift away from the first position we aimed at. Retarget
	# until the card under the pointer is the one we want to drag.
	for _attempt in range(3):
		board._UT_interpolate_mouse_move(card.global_position + extra_offset,
				board._UT_mouse_position,mouse_speed)
		await yield_for(mouse_yield_wait)
		if board.mouse_pointer.current_focused_card == card:
			break
		var retarget_tween = card._tween
		if retarget_tween.is_active():
			await yield_to(retarget_tween, "tween_all_completed", 1)
	click_card(card)
	if interpolation_speed == "debug":
		await yield_for(4) # Allow for review
	else:
		await yield_for(0.3) # Wait to allow dragging to start
	board._UT_interpolate_mouse_move(target_position,board._UT_mouse_position,mouse_speed)
	await yield_for(mouse_yield_wait)


func drop_card(card: Card, drop_location: Vector2) -> void:
	var fc:= fake_click(false, drop_location)
	card._on_Card_gui_input(fc)
	# The board state machine starts the drop tween on the following frame, so
	# checking is_active() right away would skip the wait and let the callers
	# assert on a card that is still travelling towards its slot.
	await get_tree().process_frame
	await get_tree().process_frame
	# Most tests call this without awaiting and wait on the tween themselves.
	# GUT's yield_to() shares one awaiter per test, so a concurrent internal wait
	# would collide ("signal already connected"); await the tween directly.
	var tween = card._tween
	if tween.is_active():
		await tween.tween_all_completed


# Takes care of simple drag&drop requests
func drag_drop(card: Card, target_position: Vector2, interpolation_speed := "fast") -> void:
	await drag_card(card,target_position,interpolation_speed)
	await drop_card(card,board._UT_mouse_position)
	await yield_for(0.1) # Wait to allow dragging to start
	card._on_Card_mouse_exited()

# Interpolates the virtual mouse so that it correctly targets a card
func target_card(source: Card,
		target: Card, interpolation_speed := "fast") -> void:
	var mouse_speed = MOUSE_SPEED[interpolation_speed][0]
	var mouse_yield_wait = MOUSE_SPEED[interpolation_speed][1]
	if source == target:
		# If the target is the same as the source, we need to wait a bit
		# because otherwise the _is_targeted might not be set yet.
		await yield_for(0.6)
	# We need to offset a bit towards the card rect, to ensure the arrow
	# Area2D collides
	var extra_offset = Vector2(10,10)
	if target.card_rotation in [90,270]:
		extra_offset = Vector2(10,100)
	board._UT_interpolate_mouse_move(target.global_position + extra_offset,
			source.global_position,mouse_speed)
	await yield_for(mouse_yield_wait)
	var repeat := 0
	while not target.highlight.visible and repeat <= 3:
		board._UT_interpolate_mouse_move(target.global_position + extra_offset,
				board._UT_mouse_position,mouse_speed)
		await yield_for(mouse_yield_wait)
		repeat += 1
	unclick_card_anywhere(source)


func table_move(card: Card, pos: Vector2) -> void:
	card.move_to(board, -1, pos)
	await yield_to(card._tween, "tween_all_completed", 0.5)
#	if cfc.game_settings.fancy_movement:
#		yield(yield_to(card._tween, "tween_all_completed", 0.5), YIELD)

func move_mouse(target_position: Vector2, interpolation_speed := "fast") -> void:
	var mouse_speed = MOUSE_SPEED[interpolation_speed][0]
	var mouse_yield_wait = MOUSE_SPEED[interpolation_speed][1]
	board._UT_interpolate_mouse_move(target_position,board._UT_mouse_position,mouse_speed)
	await yield_for(mouse_yield_wait)

func execute_with_yield(card: Card) -> void:
	await card.execute_scripts()


# Godot 4 refuses a bare call to a coroutine when the card type is known, but
# some tests need the scripts running while they watch the follow-up tweens.
func start_scripts(card: Card) -> void:
	card.call("execute_scripts")


func execute_with_target(card: Card, target: Card) -> void:
	# execute_scripts() blocks on targetting, so this has to stay a background
	# call while the virtual mouse picks the target. The coroutine handle is not
	# exposed in Godot 4, so completion is read from the card's signal.
	var executed := false
	var on_executed := func(_card, _sceng, _trigger): executed = true
	card.scripts_executed.connect(on_executed)
	card.execute_scripts()
	# GUT's awaiter is shared per test, so this wait must finish before
	# wait_until registers on the same awaiter (it would overwrite the timer).
	await target_card(card, target, "slow")
	await wait_until(func(): return executed, 5)
	card.scripts_executed.disconnect(on_executed)
