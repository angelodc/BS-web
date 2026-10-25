# Code for a sample deck, you're expected to provide your own ;)
extends Pile

signal draw_card(deck)

const SELECTION_WINDOW_SCENE = preload("res://src/core/SelectionWindow.tscn")

onready var _clarividencia_button: Button = get_node_or_null(
		"Control/ManipulationButtons/Clarividencia")
onready var _search_button: Button = get_node_or_null(
		"Control/ManipulationButtons/Procurar")

var _peek_menu: PopupMenu
var _custom_peek_dialog: ConfirmationDialog
var _custom_peek_count: SpinBox
var _deck_action_in_progress := false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not cfc.are_all_nodes_mapped:
		yield(cfc, "all_nodes_mapped")
	# warning-ignore:return_value_discarded
	$Control.connect("gui_input", self, "_on_Deck_input_event")
	# warning-ignore:return_value_discarded
	connect("draw_card", cfc.NMAP.hand, "draw_card")
	if _clarividencia_button:
		_clarividencia_button.connect(
				"pressed", self, "_on_clarividencia_pressed")
	if _search_button:
		_search_button.connect("pressed", self, "_on_search_pressed")
	_create_peek_menu()
	_create_custom_peek_dialog()


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
	_peek_menu.popup(Rect2(get_viewport().get_mouse_position(), Vector2.ZERO))


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
