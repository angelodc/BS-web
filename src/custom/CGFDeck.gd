# Code for a sample deck, you're expected to provide your own ;)
extends Pile

signal draw_card(deck)

const SELECTION_WINDOW_SCENE = preload("res://src/core/SelectionWindow.tscn")

# The deck lies sideways in the bottom-left corner inside a box with a fixed
# size, so the pile no longer grows with the card count. The cards are stacked
# with a couple of pixels of offset each, as only the edges of the lower cards
# should peek out.
const BOX_SIZE := Vector2(156.0, 150.0)
const BOX_BOTTOM_GAP := 2.0
const CARD_INSET := 12.0
const FAN_STEP := Vector2(0.8, 0.9)
const FAN_MAX := 10
# Distance from the top edge of the box to the center of the pile label.
const LABEL_TOP_OFFSET := 23.0
# Distance from the top edge of the box to the center of the action buttons.
const BUTTONS_TOP_OFFSET := 43.0

onready var _clarividencia_button: Button = get_node_or_null(
		"Control/ManipulationButtons/Clarividencia")
onready var _search_button: Button = get_node_or_null(
		"Control/ManipulationButtons/Procurar")

var _peek_menu: PopupMenu
var _custom_peek_dialog: ConfirmationDialog
var _custom_peek_count: SpinBox
var _deck_action_in_progress := false
var _label_count := -1


# The deck rests turned 270 degrees, so after the shuffle animation leaves it
# at a random angle it is put back sideways.
func _on_shuffle_completed(_pile) -> void:
	rotation_degrees = 270


# The pile node is turned 270 degrees; the label and the action buttons are
# turned back so their text stays readable. The local +y axis then points to
# the screen right, so the label can sit centered in the empty strip above the
# stacked cards and the buttons near the bottom edge.
func keep_children_upright() -> void:
	var control: Control = get_node("Control")
	var label: Control = get_node("Control/CenterContainer")
	var buttons: Control = get_node("Control/ManipulationButtons")
	for child in [label, buttons]:
		child.rect_pivot_offset = child.rect_size * 0.5
		child.rect_rotation = 90
	label.rect_position = Vector2(
			BOX_BOTTOM_GAP + BOX_SIZE.y - LABEL_TOP_OFFSET \
					- label.rect_size.x * 0.5,
			control.rect_size.y * 0.5 - label.rect_size.y * 0.5)
	_place_manipulation_buttons(control)


# The action buttons are an upright column over the top of the box, above the
# stacked cards. The pile is turned 270 degrees, so the visual centre of a
# child at pile position p is (p.y, pile.y - p.x); the formula below inverts
# that after the buttons are turned back upright.
func _place_manipulation_buttons(control: Control) -> void:
	var buttons: Control = get_node("Control/ManipulationButtons")
	var pivot: Vector2 = buttons.rect_size * 0.5
	if buttons.rect_pivot_offset != pivot:
		buttons.rect_pivot_offset = pivot
	var box_top: float = position.y - control.rect_position.x \
			- control.rect_size.x
	var center := Vector2(
			control.rect_position.y + control.rect_size.y * 0.5,
			box_top + BUTTONS_TOP_OFFSET)
	buttons.rect_position = Vector2(
			position.y - center.y - buttons.rect_size.x * 0.5,
			center.x - buttons.rect_size.y * 0.5)


func _process(delta: float) -> void:
	._process(delta)
	if cfc.ut:
		return
	_hold_layout()


# Keeps the lying deck inside its fixed box: the panel no longer follows the
# stack size, and the cards fan a little inside it instead of hugging the
# bottom-left corner and running off the screen edge.
func _hold_layout() -> void:
	var control: Control = get_node("Control")
	var panel_size := Vector2(BOX_SIZE.y, BOX_SIZE.x)
	if not control.rect_size.is_equal_approx(panel_size):
		control.rect_size = panel_size
		call_deferred("keep_children_upright")
	control.rect_position = Vector2(
			BOX_BOTTOM_GAP + BOX_SIZE.y - panel_size.x, 0.0)
	$Control/Highlight.rect_size = panel_size
	_place_manipulation_buttons(control)
	_refresh_label()
	if pile_popup.visible or cfc.card_drag_ongoing:
		return
	var cards := get_all_cards(false)
	var count := cards.size()
	var card_screen: Vector2 = Vector2(
			CFConst.CARD_SIZE.y, CFConst.CARD_SIZE.x) * card_display_scale
	var base := Vector2(
			position.x + (BOX_SIZE.x - card_screen.x) * 0.5,
			position.y - BOX_BOTTOM_GAP - CARD_INSET - card_screen.y)
	for index in range(count):
		var card: Card = cards[index]
		if card.state != Card.CardState.IN_PILE:
			continue
		var depth: int = min(count - 1 - index, FAN_MAX)
		var screen_pos: Vector2 = base + FAN_STEP * depth
		card.position = Vector2(
				position.y - screen_pos.y - card_screen.y,
				screen_pos.x - position.x)


func _refresh_label() -> void:
	var count := get_card_count()
	if count == _label_count:
		return
	_label_count = count
	pile_name_label.text = "Deck: " + str(count)


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not cfc.are_all_nodes_mapped:
		yield(cfc, "all_nodes_mapped")
	# warning-ignore:return_value_discarded
	$Control.connect("gui_input", self, "_on_Deck_input_event")
	# warning-ignore:return_value_discarded
	connect("draw_card", cfc.NMAP.hand, "draw_card")
	# warning-ignore:return_value_discarded
	connect("shuffle_completed", self, "_on_shuffle_completed")
	if _clarividencia_button:
		_clarividencia_button.connect(
				"pressed", self, "_on_clarividencia_pressed")
	if _search_button:
		_search_button.connect("pressed", self, "_on_search_pressed")
	_create_peek_menu()
	_create_custom_peek_dialog()
	# The count is shown next to the pile name, so the separate count box is
	# not needed and would cover the cards.
	$Control/CenterContainer/VBoxContainer/PanelContainer.hide()
	pile_name_label.align = Label.ALIGN_CENTER


func _create_peek_menu() -> void:
	_peek_menu = PopupMenu.new()
	add_child(_peek_menu)
	_peek_menu.add_item("Espiar 1 carta", 1)
	_peek_menu.add_item("Espiar 2 cartas", 2)
	_peek_menu.add_item("Espiar 3 cartas", 3)
	_peek_menu.add_item("+ Outra quantidade", 4)
	_peek_menu.connect("id_pressed", self, "_on_peek_count_selected")


func _create_custom_peek_dialog() -> void:
	_custom_peek_dialog = ConfirmationDialog.new()
	_custom_peek_dialog.window_title = "Clarividência"
	_custom_peek_dialog.rect_min_size = Vector2(280, 90)
	_custom_peek_dialog.get_ok().text = "Espiar"
	_custom_peek_count = SpinBox.new()
	_custom_peek_count.min_value = 4
	_custom_peek_count.step = 1
	_custom_peek_count.rect_position = Vector2(16, 16)
	_custom_peek_count.rect_size = Vector2(240, 30)
	_custom_peek_dialog.add_child(_custom_peek_count)
	add_child(_custom_peek_dialog)
	_custom_peek_dialog.connect(
			"confirmed", self, "_on_custom_peek_confirmed")


func get_top_cards(amount: int) -> Array:
	var top_cards := []
	var cards := get_all_cards()
	var count := min(max(amount, 0), cards.size())
	for index in range(count):
		top_cards.append(cards[cards.size() - index - 1])
	return top_cards


func _on_clarividencia_pressed() -> void:
	if cfc.game_paused or get_card_count() == 0:
		return
	_custom_peek_count.max_value = max(4, get_card_count())
	_custom_peek_count.value = min(4, get_card_count())
	_peek_menu.set_item_disabled(3, get_card_count() < 4)
	_peek_menu.popup(Rect2(_clarividencia_anchor(), Vector2.ZERO))


# The menu opens beside the button that owns it instead of at the mouse, which
# may be anywhere on the board when the button is pressed from a hotkey.
func _clarividencia_anchor() -> Vector2:
	if not _clarividencia_button or not _clarividencia_button.is_inside_tree():
		return get_viewport().get_mouse_position()
	var xf: Transform2D = _clarividencia_button.get_global_transform_with_canvas()
	var size: Vector2 = _clarividencia_button.rect_size
	var corners := [
			xf.xform(Vector2.ZERO),
			xf.xform(Vector2(size.x, 0.0)),
			xf.xform(size),
			xf.xform(Vector2(0.0, size.y))]
	var min_point: Vector2 = corners[0]
	var max_point: Vector2 = corners[0]
	for corner in corners:
		min_point = Vector2(min(min_point.x, corner.x),
				min(min_point.y, corner.y))
		max_point = Vector2(max(max_point.x, corner.x),
				max(max_point.y, corner.y))
	return Vector2(max_point.x + 4.0, min_point.y)


func _on_peek_count_selected(item_id: int) -> void:
	if item_id == 4:
		_custom_peek_dialog.popup_centered()
	else:
		_show_top_cards(item_id)


func _on_custom_peek_confirmed() -> void:
	_show_top_cards(int(_custom_peek_count.value))


func _show_top_cards(amount: int) -> void:
	var cards := get_top_cards(amount)
	if cards.empty():
		return
	var reveal = _reveal_top_cards(cards)
	if reveal is GDScriptFunctionState:
		yield(reveal, "completed")


func _reveal_top_cards(cards: Array) -> void:
	if _deck_action_in_progress:
		return
	_deck_action_in_progress = true
	var revealed_cards := []
	for card in cards:
		if not is_instance_valid(card) or card.get_parent() != self:
			continue
		card.set_is_faceup(true, true)
		var move_to_board = card.move_to(
				cfc.NMAP.board,
				-1,
				_get_reveal_position(revealed_cards.size(), cards.size()),
				["Clarividência"])
		if move_to_board is GDScriptFunctionState:
			yield(move_to_board, "completed")
		revealed_cards.append(card)
	yield(get_tree().create_timer(3.0), "timeout")
	revealed_cards.invert()
	for card in revealed_cards:
		if not is_instance_valid(card) or card.get_parent() != cfc.NMAP.board:
			continue
		var return_to_deck = card.move_to(self, -1, null, ["Clarividência"])
		if return_to_deck is GDScriptFunctionState:
			yield(return_to_deck, "completed")
	_deck_action_in_progress = false


func _get_reveal_position(index: int, card_count: int) -> Vector2:
	var board: Control = cfc.NMAP.board
	var spacing := min(
			CFConst.CARD_SIZE.x + 12.0,
			max(
					board.rect_size.x - CFConst.CARD_SIZE.x,
					1.0) / max(card_count - 1, 1))
	var total_width := min(
			CFConst.CARD_SIZE.x + spacing * max(card_count - 1, 0),
			board.rect_size.x)
	var start_x := (board.rect_size.x - total_width) / 2
	return Vector2(
			start_x + index * spacing,
			board.rect_size.y * 0.68 - CFConst.CARD_SIZE.y / 2)


func _on_search_pressed() -> void:
	if cfc.game_paused or _deck_action_in_progress or get_card_count() == 0:
		return
	var cards_by_name := {}
	for card in get_all_cards():
		if not cards_by_name.has(card.canonical_name):
			cards_by_name[card.canonical_name] = card
	var card_options := cards_by_name.values()
	card_options.sort_custom(CFUtils, "sort_scriptables_by_name")
	var selection_window = SELECTION_WINDOW_SCENE.instance()
	cfc.NMAP.board.add_child(selection_window)
	selection_window.connect(
			"card_selected", self, "_on_search_card_selected")
	selection_window.connect(
			"confirmed", selection_window, "queue_free")
	selection_window.close_on_selection = true
	selection_window.initiate_selection(card_options, 1, "equal", true)


func _on_search_card_selected(
		_selection_window, _signal_name: String, details: Dictionary) -> void:
	var selected_cards: Array = details.get("selected_cards", [])
	if selected_cards.empty():
		return
	_reveal_searched_card(selected_cards[0])


func _reveal_searched_card(card: Card) -> void:
	if _deck_action_in_progress \
			or not is_instance_valid(card) \
			or card.get_parent() != self:
		return
	_deck_action_in_progress = true
	card.set_is_faceup(true, true)
	var move_to_board = card.move_to(
			cfc.NMAP.board,
			-1,
			_get_reveal_position(0, 1),
			["Procurar"])
	if move_to_board is GDScriptFunctionState:
		yield(move_to_board, "completed")
	yield(get_tree().create_timer(3.0), "timeout")
	if not is_instance_valid(card) or card.get_parent() != cfc.NMAP.board:
		_deck_action_in_progress = false
		return
	var move_to_hand = card.move_to(cfc.NMAP.hand, -1, null, ["Procurar"])
	if move_to_hand is GDScriptFunctionState:
		yield(move_to_hand, "completed")
	_deck_action_in_progress = false


func _on_Deck_input_event(event) -> void:
	if event.is_pressed()\
		and not cfc.game_paused\
		and event.get_button_index() == 1:
		emit_signal("draw_card", self)
