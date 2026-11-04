# Reveals the top of the deck as a row of real cards over the table.
#
# Unlike the old timed reveal, the row stays open until the player presses
# "Concluir": the cards can be dragged sideways to change the order that goes
# back to the deck, and one of them can be dragged down to the hand. The layout
# is read left to right, so the first card is the top of the deck.
extends Control

# The match HUD is a child of the board with z_index 110, so the peek only stays
# above it (and above its "Avançar Fase" button) with a higher value.
const VIEW_Z := 130
const DRAG_Z := 140
# The cards leave the deck a little larger than a table slot so they can be read
# during the peek, and land slowly enough that the move is readable.
const PEEK_SCALE := 0.8
const PEEK_FIELD_DURATION := 0.55
const PEEK_STAGGER := 0.14
const SNAP_DURATION := 0.28
const SLOT_GAP := 22.0
const MIN_GAP := 8.0
const BOARD_MARGIN := 48.0
const LABEL_GAP := 8.0
const LABEL_HEIGHT := 22.0
const HEADER_HEIGHT := 64.0
const HEADER_MIN_WIDTH := 620.0
const HEADER_GAP := 10.0
const ROW_LIFT := 0.06
const HINT := "Clique numa carta para reordenar · clique na mão para comprar"

var _deck: Pile = null
var _board: Control = null
var _cards: Array = []
# Original card properties, restored when the card leaves the peek. Keyed by the
# card so a card that goes to the deck and comes back keeps working.
var _saved := {}
var _labels := {}
var _drag_card: Card = null
var _drag_index := -1
var _pointer: MousePointer = null
var _pointer_was_disabled := false
var _pointer_restored := false
var _closing := false
var _hand_taken := false
# False until the last card has landed; the row is not draggable before that.
var _row_ready := false

var _title: Label
var _hint: Label
var _header_panel: Panel
var _finish_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = VIEW_Z
	_board = cfc.NMAP.get("board", null)


# Opens the peek. `cards` is [top, second, ...], the order `get_top_cards()`
# returns, which is also the order shown left to right.
func start(deck: Pile, cards: Array) -> void:
	_deck = deck
	_cards = cards.duplicate()
	_capture_pointer()
	_build_header()
	await _reveal()


# -----------------------------------------------------------------------------
# Reveal
# -----------------------------------------------------------------------------

func _reveal() -> void:
	var total := _cards.size()
	var metrics := _metrics()
	for index in range(total):
		if _closing or index >= _cards.size():
			return
		var card: Card = _cards[index]
		if not is_instance_valid(card) or card.get_parent() != _deck:
			continue
		var slot := _slot_rect(metrics, index)
		_adopt(card, _metrics_scale(metrics))
		# The flip happens while the card is still in the hidden deck, so the
		# opponent never receives its face.
		card.set_is_faceup(true, true)
		_reparent_keeping_place(card, _deck)
		card._target_position = slot.position
		card.set_state(Card.CardState.DROPPING_TO_BOARD)
		_add_label(card, index, slot)
		if index < total - 1:
			await get_tree().create_timer(PEEK_STAGGER).timeout
	# The row is only draggable once the last card has landed.
	await get_tree().create_timer(PEEK_FIELD_DURATION + 0.05).timeout
	if _closing:
		return
	for card in _cards:
		if is_instance_valid(card):
			card.to_board_tween_duration = SNAP_DURATION
	_row_ready = true


# -----------------------------------------------------------------------------
# Input: drag inside the row and drop on the hand
# -----------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if _closing:
		return
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.pressed:
		# A press also closes a drag whose release was lost outside the board.
		if is_instance_valid(_drag_card):
			_end_drag(click.position)
		_begin_drag(click.position)
	elif is_instance_valid(_drag_card):
		_end_drag(click.position)


# The peeked cards keep their own Control on the table, which would take a mouse
# press before this modal view, so the drag starts here, before the GUI. This is
# also where a release outside the board is resolved.
func _input(event: InputEvent) -> void:
	if _closing:
		return
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() \
			* click.position
	if click.pressed:
		if is_instance_valid(_drag_card) or not _row_ready:
			return
		if _card_at(point) == null:
			return
		_begin_drag(point)
		get_viewport().set_input_as_handled()
		return
	if not is_instance_valid(_drag_card):
		return
	_end_drag(point)
	get_viewport().set_input_as_handled()


func _begin_drag(point: Vector2) -> void:
	if is_instance_valid(_drag_card) or not _row_ready or _cards_are_moving():
		return
	var card := _card_at(point)
	if card == null:
		return
	var canvas_point: Vector2 = get_global_transform_with_canvas() * point
	var offset: Vector2 = card.get_node("Control") \
			.get_global_transform_with_canvas().affine_inverse() * canvas_point
	_drag_card = card
	_drag_index = _cards.find(card)
	cfc.card_drag_ongoing = card
	card._start_dragging(offset)
	# The release is resolved here, where the row and the hand are known.
	card._drop_release_handled = true
	card.z_index = DRAG_Z


func _end_drag(point: Vector2) -> void:
	var card: Card = _drag_card
	var from := _drag_index
	_drag_card = null
	_drag_index = -1
	cfc.card_drag_ongoing = null
	if not is_instance_valid(card):
		return
	card._drop_release_handled = true
	if is_instance_valid(_pointer):
		_pointer.forget_focus()
	if _pointer_over_hand(point):
		if not _hand_taken:
			_hand_taken = true
			_set_hint("Uma carta foi para a mão. As demais voltam nesta ordem.")
			_send_to_hand(card)
			return
		# A refused drop leaves the card where it was instead of sending it to
		# the slot nearest the hand.
		_set_hint("Só uma carta vai para a mão.")
		_restore_index(card, from)
		return
	_move_in_row(card, point)


func _card_at(point: Vector2) -> Card:
	for index in range(_cards.size() - 1, -1, -1):
		var card: Card = _cards[index]
		if not is_instance_valid(card) or card.get_parent() != _board:
			continue
		if Rect2(card.position, card.card_size * card.scale).has_point(point):
			return card
	return null


func _cards_are_moving() -> bool:
	for card in _cards:
		if is_instance_valid(card) and card._tween.is_active():
			return true
	return false


# The hand is an Area2D: its drop area is the rectangle of its collision shape.
func _pointer_over_hand(point: Vector2) -> bool:
	var hand = cfc.NMAP.get("hand", null)
	if not is_instance_valid(hand):
		return false
	var shape_node := hand.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not (shape_node.shape is RectangleShape2D):
		return false
	var canvas_point: Vector2 = get_global_transform_with_canvas() * point
	var local: Vector2 = shape_node.global_transform.affine_inverse() * canvas_point
	var half: Vector2 = shape_node.shape.size * 0.5
	return Rect2(-half, shape_node.shape.size).has_point(local)


# Moves the card to the slot nearest the pointer and lays the row out again.
func _move_in_row(card: Card, point: Vector2) -> void:
	_restore_index(card, _nearest_index(point))


func _restore_index(card: Card, index: int) -> void:
	var current := _cards.find(card)
	if current >= 0:
		_cards.remove_at(current)
	_cards.insert(clampi(index, 0, _cards.size()), card)
	_layout_cards()


func _nearest_index(point: Vector2) -> int:
	var metrics := _metrics()
	var best := 0
	var best_distance := INF
	for index in range(_cards.size()):
		var center: float = _slot_rect(metrics, index).get_center().x
		var distance := absf(point.x - center)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


# -----------------------------------------------------------------------------
# Leaving the row
# -----------------------------------------------------------------------------

# The peeked card goes to the top of the deck and is drawn through the normal
# draw: the log, the network echo and the hand animation stay the same as a
# draw from the deck.
func _send_to_hand(card: Card) -> void:
	var from := _cards.find(card)
	if from >= 0:
		_cards.remove_at(from)
	_remove_label(card)
	_layout_cards()
	_release(card)
	card.set_is_faceup(false, true)
	var keep := card.global_position
	var parent := card.get_parent()
	if is_instance_valid(parent):
		parent.remove_child(card)
	_deck.add_child(card)
	card.global_position = keep
	card.set_state(Card.CardState.IN_PILE)
	var board = cfc.NMAP.get("board", null)
	if is_instance_valid(board) and board.has_method("apply_intent"):
		var result: Dictionary = board.apply_intent(
				{"op": "comprar", "quantity": 1})
		board.report_intent(result)
		if not bool(result.get("ok", false)):
			# A refused draw leaves the one-card allowance untouched.
			_hand_taken = false
			_set_hint(str(result.get("message", "Não foi possível comprar agora.")))
			_return_to_row(card, from)
		return
	var hand = cfc.NMAP.get("hand", null)
	if is_instance_valid(hand):
		hand.draw_card(_deck)
		return
	_hand_taken = false
	_return_to_row(card, from)


func _return_to_row(card: Card, index: int) -> void:
	if not is_instance_valid(card) or _closing:
		return
	var keep := card.global_position
	var parent := card.get_parent()
	if is_instance_valid(parent):
		parent.remove_child(card)
	if not is_instance_valid(_board):
		return
	_board.add_child(card)
	card.global_position = keep
	_adopt(card, _metrics_scale(_metrics()))
	card.set_is_faceup(true, true)
	if index < 0 or index > _cards.size():
		index = _cards.size()
	_cards.insert(index, card)
	_add_label(card, index, _slot_rect(_metrics(), index))
	_layout_cards()


func _finish() -> void:
	if _closing:
		return
	_closing = true
	_drag_card = null
	cfc.card_drag_ongoing = null
	if is_instance_valid(_finish_button):
		_finish_button.disabled = true
	if is_instance_valid(_header_panel):
		_header_panel.visible = false
	for label in _labels.values():
		if is_instance_valid(label):
			label.queue_free()
	_labels.clear()
	var remaining := _cards.duplicate()
	_cards.clear()
	for index in range(remaining.size() - 1, -1, -1):
		_return_to_deck(remaining[index])
	await get_tree().create_timer(0.4).timeout
	if is_instance_valid(_deck) and _deck.has_method("finish_clarividencia"):
		_deck.finish_clarividencia(self)
	_restore_pointer()
	queue_free()


# Returning in reverse display order appends the first card last, so it becomes
# the deck's new top.
func _return_to_deck(card: Card) -> void:
	if not is_instance_valid(card) or card.get_parent() != _board:
		return
	_release(card)
	card.set_is_faceup(false, true)
	card._drop_release_handled = true
	card.move_to(_deck, -1, null, ["Clarividência"])


# -----------------------------------------------------------------------------
# Card bookkeeping
# -----------------------------------------------------------------------------

func _adopt(card: Card, scale: float) -> void:
	if not _saved.has(card):
		_saved[card] = {
			"to_board": card.to_board_tween_duration,
			"play_area": card.play_area_scale,
		}
	card.play_area_scale = scale
	card.to_board_tween_duration = PEEK_FIELD_DURATION
	card.set_control_mouse_filters(false)


func _release(card: Card) -> void:
	var saved: Dictionary = _saved.get(card, {})
	if not saved.is_empty():
		card.to_board_tween_duration = saved["to_board"]
		card.play_area_scale = saved["play_area"]
		_saved.erase(card)
	card.set_control_mouse_filters(true)


func _reparent_keeping_place(card: Card, from: Node) -> void:
	var keep := card.global_position
	from.remove_child(card)
	_board.add_child(card)
	card.global_position = keep


func _layout_cards() -> void:
	if _closing:
		return
	var metrics := _metrics()
	var scale := _metrics_scale(metrics)
	for index in range(_cards.size()):
		var card: Card = _cards[index]
		if not is_instance_valid(card) or card.get_parent() != _board:
			continue
		card.play_area_scale = scale
		card.to_board_tween_duration = SNAP_DURATION
		card._target_position = _slot_rect(metrics, index).position
		card.set_state(Card.CardState.DROPPING_TO_BOARD)
	_layout_labels(metrics)
	_layout_header(metrics)


# -----------------------------------------------------------------------------
# Layout and labels
# -----------------------------------------------------------------------------

func _metrics() -> Dictionary:
	var board := _board_size()
	var count: int = max(_cards.size(), 1)
	var scale := PEEK_SCALE
	var card_size: Vector2 = CFConst.CARD_SIZE * scale
	var gap := SLOT_GAP
	var total: float = count * card_size.x + (count - 1) * gap
	var limit: float = board.x - BOARD_MARGIN * 2.0
	if total > limit and count > 1:
		gap = maxf(MIN_GAP, (limit - count * card_size.x) / (count - 1))
		total = count * card_size.x + (count - 1) * gap
	if total > limit:
		scale = PEEK_SCALE * limit / total
		card_size = CFConst.CARD_SIZE * scale
		total = limit
	var row_height: float = card_size.y + LABEL_GAP + LABEL_HEIGHT
	var top: float = (board.y - row_height) * 0.5 - board.y * ROW_LIFT
	return {
		"card": card_size,
		"gap": gap,
		"total": total,
		"x": (board.x - total) * 0.5,
		"y": maxf(top, HEADER_HEIGHT + HEADER_GAP + 12.0),
	}


func _slot_rect(metrics: Dictionary, index: int) -> Rect2:
	var card_size: Vector2 = metrics["card"]
	var x: float = metrics["x"] \
			+ index * (card_size.x + float(metrics["gap"]))
	return Rect2(Vector2(x, metrics["y"]), card_size)


# The row shrinks the cards when they do not fit, so every card adopts the
# scale the layout computed instead of the fixed peek scale.
func _metrics_scale(metrics: Dictionary) -> float:
	return float(metrics["card"].x) / CFConst.CARD_SIZE.x


func _board_size() -> Vector2:
	if is_instance_valid(_board):
		return _board.size
	return get_viewport_rect().size


func _build_header() -> void:
	# A panel right above the row keeps the title, the hint and "Concluir" clear
	# of the match HUD, which owns the top strip of the board.
	_header_panel = Panel.new()
	_header_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.86)
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(0.62, 0.7, 0.85, 0.5)
	_header_panel.add_theme_stylebox_override("panel", style)
	add_child(_header_panel)
	_title = _make_label("Clarividência · topo do deck", 18)
	_header_panel.add_child(_title)
	_hint = _make_label(HINT, 12)
	_header_panel.add_child(_hint)
	_finish_button = Button.new()
	_finish_button.text = "Concluir"
	_finish_button.pressed.connect(_finish)
	_header_panel.add_child(_finish_button)
	_layout_header(_metrics())


func _layout_header(metrics: Dictionary) -> void:
	if not is_instance_valid(_header_panel):
		return
	var board := _board_size()
	var width: float = clampf(
			maxf(HEADER_MIN_WIDTH, float(metrics["total"])),
			320.0, board.x - 24.0)
	var x: float = (board.x - width) * 0.5
	var y: float = float(metrics["y"]) - HEADER_HEIGHT - HEADER_GAP
	_header_panel.position = Vector2(x, maxf(y, 4.0))
	_header_panel.size = Vector2(width, HEADER_HEIGHT)
	var text_width: float = maxf(width - 176.0, 120.0)
	if is_instance_valid(_title):
		_title.position = Vector2(14.0, 8.0)
		_title.size = Vector2(text_width, 24.0)
	if is_instance_valid(_hint):
		_hint.position = Vector2(14.0, 34.0)
		_hint.size = Vector2(text_width, 20.0)
	if is_instance_valid(_finish_button):
		_finish_button.size = Vector2(140.0, 40.0)
		_finish_button.position = Vector2(width - 154.0, 12.0)


func _set_hint(text: String) -> void:
	if is_instance_valid(_hint):
		_hint.text = text


func _add_label(card: Card, index: int, slot: Rect2) -> void:
	var label := _make_label(_label_text(index), 16)
	label.size = Vector2(slot.size.x, LABEL_HEIGHT)
	label.position = Vector2(
			slot.position.x, slot.position.y + slot.size.y + LABEL_GAP)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_labels[card] = label
	add_child(label)


func _layout_labels(metrics: Dictionary) -> void:
	for index in range(_cards.size()):
		var card = _cards[index]
		var label = _labels.get(card, null)
		if not is_instance_valid(label):
			continue
		var slot := _slot_rect(metrics, index)
		label.text = _label_text(index)
		label.position = Vector2(
				slot.position.x, slot.position.y + slot.size.y + LABEL_GAP)


func _remove_label(card: Card) -> void:
	var label = _labels.get(card, null)
	if is_instance_valid(label):
		label.queue_free()
	_labels.erase(card)


# The first card is the deck's top, so it is named instead of only numbered.
func _label_text(index: int) -> String:
	if index == 0:
		return "1 · topo"
	return str(index + 1)


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)
	return label


# -----------------------------------------------------------------------------
# Modality
# -----------------------------------------------------------------------------

# The board pointer would keep highlighting the table under the open peek, so
# it is switched off while the row is visible and put back on close.
func _capture_pointer() -> void:
	if not is_instance_valid(_board):
		_board = cfc.NMAP.get("board", null)
	if not is_instance_valid(_board):
		return
	var pointer = _board.mouse_pointer
	if not is_instance_valid(pointer):
		return
	_pointer = pointer
	_pointer_was_disabled = pointer.is_disabled
	pointer.is_disabled = true


func _restore_pointer() -> void:
	if _pointer_restored:
		return
	_pointer_restored = true
	if is_instance_valid(_pointer):
		_pointer.is_disabled = _pointer_was_disabled


func _exit_tree() -> void:
	_restore_pointer()
	# A view torn down without "Concluir" (scene change) must not leave the
	# deck refusing every action.
	if not _closing and is_instance_valid(_deck) \
			and _deck.has_method("finish_clarividencia"):
		_deck.finish_clarividencia(self)
