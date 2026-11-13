# A grid of cards drawn on the table canvas, like the resources viewer.
# The deck search and the opponent zone viewers used a Window, which owns a
# viewport of its own and needed a hand-placed hover popup inside it. A panel on
# the table keeps the cards as ordinary cards on the board canvas, so the hover
# is the same pinned closeup the resources viewer already uses.
class_name CardGridPanel
extends PanelContainer

signal card_picked(card: Card)
signal closed(picked: bool)

const CARD_SEPARATION := 6.0
const MAX_COLUMNS := 7
const VIEWPORT_MARGIN := 24.0
const PANEL_PADDING := 12.0
const PANEL_BG := Color(0.07, 0.08, 0.11, 0.96)
const PANEL_BORDER := Color(0.62, 0.52, 0.28, 0.9)

var _entries := []
var _selectable := false
var _card_scale := CFConst.HAND_CARD_SCALE
var _hovered: Card = null
var _picked := false
var _closed := false

var _title: Label
var _scroll: ScrollContainer
var _grid: GridContainer
var _close_button: Button


func _init() -> void:
	top_level = true
	z_index = 120
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(PANEL_PADDING)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_title = Label.new()
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 18)
	column.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.add_theme_constant_override("h_separation", int(CARD_SEPARATION))
	_grid.add_theme_constant_override("v_separation", int(CARD_SEPARATION))
	_scroll.add_child(_grid)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(actions)
	_close_button = Button.new()
	_close_button.name = "Close"
	_close_button.custom_minimum_size = Vector2(120, 30)
	_close_button.pressed.connect(_close)
	actions.add_child(_close_button)


# Cards can be card instances (the deck search keeps the real card to move) or
# definition keys (the opponent zones only know the names).
func open(cards: Array, options := {}) -> void:
	_selectable = bool(options.get("selectable", false))
	_card_scale = _hand_scale()
	_title.text = str(options.get("title", ""))
	_close_button.text = "Cancelar" if _selectable else "Fechar"
	for index in range(cards.size()):
		_add_card(cards[index], index)
	_layout_panel()
	_block_table(true)


func title_text() -> String:
	return _title.text


func is_selectable() -> bool:
	return _selectable


func _hand_scale() -> float:
	var hand = cfc.NMAP.get("hand", null)
	if is_instance_valid(hand) and hand.get("card_display_scale") != null:
		return float(hand.card_display_scale)
	return CFConst.HAND_CARD_SCALE


func _add_card(source, index: int) -> void:
	var display: Card
	if typeof(source) == TYPE_STRING:
		if not cfc.card_definitions.has(source):
			return
		display = cfc.instance_card(source)
	else:
		display = source.duplicate(Node.DUPLICATE_USE_INSTANTIATION)
		display.definitions_key = source.definition_key()
		display.canonical_name = source.canonical_name
		display.properties = source.properties.duplicate()
	# The copy is a picture, not a card in play: it must not answer the scripted
	# effects nor reach the snapshots that scan the cards group.
	display.remove_from_group("cards")
	# The grid holds Controls, so the card gets a slot to sit on. The card itself
	# is only scaled as a node, the same way the resources viewer does it. The
	# popup state keeps the scale from popup_scale, so that value is set too.
	display.popup_scale = _card_scale
	display.scale = Vector2(_card_scale, _card_scale)
	var slot := Control.new()
	slot.name = "CardGridSlot" + str(index + 1)
	slot.custom_minimum_size = \
			display.get_node("Control").custom_minimum_size * display.scale
	_grid.add_child(slot)
	slot.add_child(display)
	# The arrow is built in the card's _ready, so it can only be hidden once the
	# copy is on the tree.
	display.targeting_arrow.visible = false
	display.set_is_faceup(true, true)
	# The copy starts as a fresh instance, so its face containers have to be put
	# in the faceup state before it is shown.
	display.ensure_proper()
	display.position = Vector2.ZERO
	display.state = Card.CardState.IN_POPUP
	_entries.append({"card": display, "origin": source})


func _layout_panel() -> void:
	var count := _entries.size()
	var card_size: Vector2 = CFConst.CARD_SIZE * _card_scale
	var view := get_viewport().get_visible_rect().size
	var usable := view.x - 2.0 * VIEWPORT_MARGIN - 2.0 * PANEL_PADDING
	var per_column := card_size.x + CARD_SEPARATION
	var fit_columns: int = max(1, int((usable + CARD_SEPARATION) / per_column))
	var columns := clampi(min(count, min(fit_columns, MAX_COLUMNS)), 1, MAX_COLUMNS)
	_grid.columns = columns
	var rows := int(ceil(float(count) / columns))
	var grid_size := Vector2(
			columns * card_size.x + (columns - 1) * CARD_SEPARATION,
			rows * card_size.y + (rows - 1) * CARD_SEPARATION)
	# The grid scrolls when the deck holds more rows than the table fits, the
	# same way the resources viewer keeps its window inside the viewport.
	var chrome: float = _title.get_combined_minimum_size().y \
			+ _close_button.custom_minimum_size.y + 2.0 * PANEL_PADDING + 16.0
	var scroll_height: float = max(card_size.y,
			min(grid_size.y, view.y - 2.0 * VIEWPORT_MARGIN - chrome))
	_scroll.custom_minimum_size = Vector2(grid_size.x, scroll_height)
	reset_size()
	position = Vector2(
			max(VIEWPORT_MARGIN, (view.x - size.x) * 0.5),
			max(VIEWPORT_MARGIN, (view.y - size.y) * 0.5))


func _process(_delta: float) -> void:
	if _closed:
		return
	var point := get_global_mouse_position()
	if _scroll.get_global_rect().has_point(point):
		_update_hover(_card_at(point))
	else:
		_update_hover(null)


func _update_hover(hovered: Card) -> void:
	if hovered == _hovered:
		return
	var main = cfc.NMAP.get("main", null)
	if not is_instance_valid(main):
		_hovered = hovered
		return
	if is_instance_valid(_hovered):
		main.unfocus(_hovered)
	if is_instance_valid(hovered):
		main.focus_card_pinned(hovered)
	_hovered = hovered


func _card_at(point: Vector2) -> Card:
	for entry in _entries:
		var card: Card = entry["card"]
		if not is_instance_valid(card) or not card.visible:
			continue
		if Rect2(card.global_position,
				CFConst.CARD_SIZE * card.scale).has_point(point):
			return card
	return null


# The panel owns the mouse while it is up: a click outside closes it and is
# consumed, so the deck or the field underneath never answers the same click.
func _input(event: InputEvent) -> void:
	if _closed:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.get_button_index() == MOUSE_BUTTON_RIGHT:
		_close()
		get_viewport().set_input_as_handled()
		return
	if event.get_button_index() != MOUSE_BUTTON_LEFT:
		return
	if not get_global_rect().has_point(event.position):
		_close()
		get_viewport().set_input_as_handled()
		return
	if not _scroll.get_global_rect().has_point(event.position):
		return
	var card := _card_at(event.position)
	if not is_instance_valid(card):
		return
	# The panel owns the click over a copy: the card must not start a drag or
	# run its scripts from the same press.
	get_viewport().set_input_as_handled()
	if _selectable:
		_pick(card)


func _pick(display: Card) -> void:
	var origin = null
	for entry in _entries:
		if entry["card"] == display:
			origin = entry["origin"]
			break
	_picked = true
	_close()
	if origin is Card and is_instance_valid(origin):
		card_picked.emit(origin)


func _close() -> void:
	if _closed:
		return
	_closed = true
	var main = cfc.NMAP.get("main", null)
	if is_instance_valid(_hovered) and is_instance_valid(main):
		main.unfocus(_hovered)
	_hovered = null
	_block_table(false)
	closed.emit(_picked)
	queue_free()


func _block_table(blocked: bool) -> void:
	var board = cfc.NMAP.get("board", null)
	if is_instance_valid(board) and board.has_method("set_table_input_blocked"):
		board.set_table_input_blocked(blocked)
