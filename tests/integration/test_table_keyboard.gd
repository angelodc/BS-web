extends "res://tests/UTcommon.gd"

# F6 of "ações sem mouse": every shortcut becomes the same intent the buttons
# and scripts use. The runner remembers one selected card and walks the table in
# a stable order. Question 22 was answered with "none", so no key asks for
# confirmation: the press applies at once, irreversible actions included.

const Actions = preload("res://src/core/table/TableActions.gd")
const Snapshot = preload("res://src/core/table/TableSnapshot.gd")
const Keyboard = preload("res://src/core/table/TableKeyboard.gd")

var actions
var keyboard


func before_each():
	var setup = setup_board()
	if setup is GDScriptFunctionState:
		await setup.completed
	actions = Actions.new(board, 1)
	keyboard = Keyboard.new(actions)


func after_each():
	if not is_instance_valid(board):
		return
	var focus = board.get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus):
		focus.release_focus()


func _id(card) -> String:
	return Snapshot.id_of(card)


func _ok(result : Dictionary) -> bool:
	return bool(result.get("ok", false))


# Plays a Personagem with the given number of attachments through the intents
# and returns [host, attachment...].
func _character_in_play(attachments := 0) -> Array:
	var cards = draw_test_cards(1 + attachments)
	cards[0].properties["_tipo"] = "Personagem"
	cards[0].properties["ENERGIA"] = "1"
	for index in range(1, cards.size()):
		cards[index].properties["_tipo"] = "Habilidade"
		cards[index].properties["ENERGIA"] = "1"
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))
	for index in range(1, cards.size()):
		assert_true(_ok(actions.apply({
			"op": "anexar",
			"card": _id(cards[index]),
			"host": _id(cards[0]),
		})))
	return cards


# -----------------------------------------------------------------------------
# Selection
# -----------------------------------------------------------------------------

func test_the_selection_walks_the_table_in_a_stable_order():
	var cards = draw_test_cards(2)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))
	keyboard.select_next(1, false)

	# The runner starts on the first hand card and moves through the field.
	assert_eq(keyboard.selected_id, _id(cards[1]))
	assert_eq(keyboard.selected_address(), "p1:mão:1")

	assert_true(keyboard.handle_key(KEY_PERIOD))
	assert_eq(keyboard.selected_id, _id(cards[0]))
	assert_eq(keyboard.selected_address(), "p1:campo:frente:2")

	assert_true(keyboard.handle_key(KEY_PERIOD))
	assert_eq(keyboard.selected_id, _id(cards[1]),
			"The selection wraps back to the hand")
	assert_true(keyboard.handle_key(KEY_COMMA))
	assert_eq(keyboard.selected_id, _id(cards[0]),
			"Comma walks back to the field")


func test_j_plays_the_selected_card_through_the_same_intent():
	var cards = draw_test_cards(1)

	assert_true(keyboard.handle_key(KEY_J))

	assert_eq(actions.state.address_of(_id(cards[0])), "p1:campo:frente:2")
	assert_eq(actions.history.size(), 1)
	assert_eq(keyboard.last_message, actions.history[0]["text"])


# -----------------------------------------------------------------------------
# No confirmation
# -----------------------------------------------------------------------------

func test_an_irreversible_action_applies_on_the_first_press():
	var cards = _character_in_play(2)
	var host = _id(cards[0])
	keyboard.selected_id = host
	assert_eq(actions.history.size(), 3)

	assert_true(keyboard.handle_key(KEY_F))

	assert_eq(actions.history.size(), 4, "The press applied instead of asking")
	assert_eq(cards[0].attachments.size(), 1, "The damage was applied once")
	assert_eq(keyboard.last_message,
			"P1 feriu " + cards[0].canonical_name + " (-1)")
	assert_true(not keyboard.last_message.contains("Confirme"),
			"The keyboard never asks for a second press")


func test_the_next_press_does_not_repeat_the_irreversible_action():
	var cards = _character_in_play(2)
	keyboard.selected_id = _id(cards[0])

	assert_true(keyboard.handle_key(KEY_F))
	assert_true(keyboard.handle_key(KEY_PERIOD))
	assert_true(keyboard.handle_key(KEY_COMMA))

	assert_eq(actions.history.size(), 4,
			"Walking the selection after an irreversible action adds nothing")


# -----------------------------------------------------------------------------
# Context
# -----------------------------------------------------------------------------

func test_a_focused_text_field_blocks_the_shortcuts():
	var cards = draw_test_cards(1)
	var edit := LineEdit.new()
	add_child_autofree(edit)
	edit.grab_focus()
	assert_true(edit.has_focus(), "The text field owns the keyboard")
	assert_eq(edit.get_viewport(), board.get_viewport(), "Same viewport")
	assert_eq(board.get_viewport().gui_get_focus_owner(), edit,
			"The viewport reports the text field as focus owner")

	var event := InputEventKey.new()
	event.button_pressed = true
	event.keycode = KEY_J

	assert_false(keyboard.handle_event(event), "The shortcut stays off")
	assert_eq(actions.history.size(), 0)

	edit.release_focus()
	assert_true(keyboard.handle_event(event), "Without focus the key works")
	assert_eq(actions.history.size(), 1)
	assert_eq(actions.state.address_of(_id(cards[0])), "p1:campo:frente:2")


# -----------------------------------------------------------------------------
# Shortcuts that need two keys
# -----------------------------------------------------------------------------

func test_attach_takes_two_presses():
	var cards = draw_test_cards(2)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))

	keyboard.selected_id = _id(cards[1])
	assert_true(keyboard.handle_key(KEY_A))
	assert_eq(keyboard.attach_source, _id(cards[1]))
	assert_eq(actions.history.size(), 1, "The first press only remembers")

	keyboard.selected_id = _id(cards[0])
	assert_true(keyboard.handle_key(KEY_A))

	assert_eq(actions.history.size(), 2)
	assert_eq(actions.state.address_of(_id(cards[1])),
			"anexo:p1:p1:campo:frente:2:1")
	assert_eq(keyboard.attach_source, "")


# -----------------------------------------------------------------------------
# Movement and order
# -----------------------------------------------------------------------------

func test_n_moves_a_field_card_to_the_other_row():
	var cards = draw_test_cards(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))
	keyboard.selected_id = _id(cards[0])

	assert_true(keyboard.handle_key(KEY_N))

	assert_eq(actions.state.address_of(_id(cards[0])), "p1:campo:trás:2")
	assert_eq(cards[0].get_parent(), board)


func test_brackets_reorder_the_selected_hand_card():
	var cards = draw_test_cards(2)
	actions.sync(1)
	keyboard.selected_id = _id(cards[1])
	assert_eq(keyboard.selected_address(), "p1:mão:2")

	assert_true(keyboard.handle_key(KEY_BRACKETRIGHT))
	assert_true(keyboard.last_message.contains("ponta"),
			"The end of the hand refuses instead of doing nothing")
	assert_eq(actions.state.address_of(_id(cards[1])), "p1:mão:2")

	assert_true(keyboard.handle_key(KEY_BRACKETLEFT))
	assert_eq(actions.state.address_of(_id(cards[1])), "p1:mão:1")


func test_ctrl_z_undoes_the_last_shortcut():
	var cards = draw_test_cards(1)
	assert_true(keyboard.handle_key(KEY_J))
	assert_eq(actions.state.address_of(_id(cards[0])), "p1:campo:frente:2")

	assert_true(keyboard.handle_key(KEY_Z, false, true))

	assert_eq(actions.state.address_of(_id(cards[0])), "p1:mão:1")
	assert_eq(actions.history.size(), 1)
	assert_true(bool(actions.history[0]["undone"]))
