# Creates a GridContainer in which cards can be placed organized next
# to each other.
#
# To use this scene properly, create an inherited scene,
# then add as many instanced BoardPlacementSlots as you need this grid to hold
#
# Adjust its highlight colour and the amount of columns it should have as well
#
# The BoardPlacementSlots will adjust to card_size on runtime, but
# If you want to visually see on the editor your result
class_name BoardPlacementGrid
extends Control

# Used to add new BoardPlacementSlot instances to grids. We have to add the consts
# together before passing to the preload, or the parser complains
const _SLOT_SCENE_FILE = CFConst.PATH_CORE + "BoardPlacementSlot.tscn"
const _SLOT_SCENE = preload(_SLOT_SCENE_FILE)

# Set the highlight colour for all contained BoardPlacementSlot slots
export(Color) var highlight = CFConst.TARGET_HOVER_COLOUR
# If set to true, the grid will automatically add more slots
# when find_available_slot() is used and there's no more available slots
# (only useful when using the ScriptingEngine)
export var auto_extend := false
# Used to adjust the grid according to the card size that will be put into it.
# This size should match the
export var card_size := CFConst.CARD_SIZE
export var card_play_scale := CFConst.PLAY_AREA_SCALE
# When true, the grid fits the card area exactly, without the border padding
# used by regular grids.
export var exact_card_size := false
# When true, the grid recalculates its columns from the available width and
# highlights the whole grid area while a card is dragged over it. The card is
# placed on a slot chosen automatically, from the center outwards.
export var auto_arrange := false
# The smallest amount of columns an auto-arranged grid accepts.
export var minimum_columns := 2
# Caps the column count. Zero means no cap; the grid uses all width available.
export var maximum_columns := 0

# Sets a custom label for this grid
onready var name_label = $Control/Label

var _full_highlight: Panel
var _auto_slot: BoardPlacementSlot = null


func _ready() -> void:
	# We ensure the separation of the grid slots is always 1 pixel larger
	# Than the radius of the mouse pointer collision area.
	# This ensures that we don't highlight 2 slots at the same time.
	var separation := MousePointer.MOUSE_RADIUS * 2 + 1
	$GridContainer.set("custom_constants/vseparation", separation)
	$GridContainer.set("custom_constants/hseparation",
			_horizontal_separation())
	if auto_arrange:
		_ensure_full_highlight()
	_apply_grid_size()
	if not name_label.text:
		name_label.text = name
	set_process(auto_arrange)


func _process(_delta: float) -> void:
	if not auto_arrange:
		return
	var dragged = cfc.card_drag_ongoing
	if not is_instance_valid(dragged) or not (dragged is Card):
		clear_auto_highlight()
		return
	var board = cfc.NMAP.get("board", null)
	if not board or not board.mouse_pointer:
		clear_auto_highlight()
		return
	update_auto_highlight(
			dragged, board.mouse_pointer.determine_global_mouse_pos())


func _apply_grid_size() -> void:
	var separation: int = MousePointer.MOUSE_RADIUS * 2 + 1
	var hseparation: int = _horizontal_separation()
	var columns_count: int = max(1, int($GridContainer.columns))
	var slot_count: int = max(1, get_slot_count())
	var rows_count: int = int(ceil(float(slot_count) / columns_count))
	var content := Vector2(
			columns_count * card_size.x * card_play_scale \
					+ (columns_count - 1) * hseparation,
			rows_count * card_size.y * card_play_scale \
					+ (rows_count - 1) * separation)
	if exact_card_size:
		rect_min_size = card_size * card_play_scale
		rect_size = rect_min_size
	else:
		rect_min_size = content + Vector2(4, 4)
		rect_size = rect_min_size
		$GridContainer.rect_min_size = content
	if _full_highlight:
		_full_highlight.rect_position = Vector2(2, 2)
		_full_highlight.rect_size = content


# Recalculates the column count from the horizontal space the grid may use.
# Rows are fixed at two (front and back).
func configure_width(available_width: float) -> void:
	if not auto_arrange or available_width <= 0:
		return
	var separation: int = _horizontal_separation()
	var slot_width: float = card_size.x * card_play_scale
	var columns := int(floor(
			(available_width - 4.0 + separation) / (slot_width + separation)))
	columns = max(minimum_columns, columns)
	if maximum_columns > 0:
		columns = min(maximum_columns, columns)
	configure_columns(columns)


# Sets an explicit column count, keeping exactly two rows of slots.
func configure_columns(columns: int) -> void:
	columns = max(1, columns)
	if int($GridContainer.columns) == columns \
			and get_slot_count() == columns * 2:
		_apply_grid_size()
		return
	$GridContainer.columns = columns
	var target_slots := columns * 2
	while get_slot_count() > target_slots:
		var last_slot: BoardPlacementSlot = get_slot(get_slot_count() - 1)
		if last_slot.occupying_card:
			var replacement := _find_free_slot_except(last_slot)
			if not replacement:
				break
			replacement.occupying_card = last_slot.occupying_card
			last_slot.occupying_card._placement_slot = replacement
			last_slot.occupying_card.global_position = \
					replacement.rect_global_position
			last_slot.occupying_card._target_position = \
					last_slot.occupying_card.global_position
			last_slot.occupying_card = null
		$GridContainer.remove_child(last_slot)
		last_slot.queue_free()
	while get_slot_count() < target_slots:
		add_slot()
	_apply_grid_size()


# Returns the slot a card should occupy when placed automatically.
#
# Cards fill the front row first (nearest the center line), starting at the
# most central column. Supports move to the back row when the front row already
# has characters, so characters keep the front.
func get_auto_placement_slot(card: Card = null) -> BoardPlacementSlot:
	if not auto_arrange or get_slot_count() == 0:
		return null
	var columns: int = max(1, int($GridContainer.columns))
	var rows: int = int(ceil(float(get_slot_count()) / columns))
	var row_order := [0, 1]
	if card and _prefers_back_row(card):
		row_order = [1, 0]
	for row in row_order:
		if row >= rows:
			continue
		for column in _center_out_columns(columns):
			var index: int = row * columns + column
			if index >= get_slot_count():
				continue
			var slot: BoardPlacementSlot = get_slot(index)
			if not slot.occupying_card or slot.occupying_card == card:
				return slot
	return null


# Shows the full-grid highlight and selects the slot closest to the pointer
# while the mouse is over the grid. This applies both to cards coming from the
# hand and to cards already on the board.
func update_auto_highlight(card: Card, mouse_pos: Vector2) -> void:
	if not auto_arrange or not is_instance_valid(card) \
			or not _contains_point(mouse_pos) or _is_scenario(card):
		clear_auto_highlight()
		return
	var slot: BoardPlacementSlot = _nearest_free_slot(mouse_pos, card)
	if not slot:
		clear_auto_highlight()
		return
	if is_instance_valid(_auto_slot) and _auto_slot != slot:
		_auto_slot.set_auto_highlight(false)
	_auto_slot = slot
	_auto_slot.set_auto_highlight(true)
	_ensure_full_highlight()
	_refresh_full_highlight_style()
	_full_highlight.visible = true


func clear_auto_highlight() -> void:
	if is_instance_valid(_auto_slot):
		_auto_slot.set_auto_highlight(false)
	_auto_slot = null
	if _full_highlight:
		_full_highlight.visible = false


# If a BoardPlacementSlot object child in this container is highlighted
# Returns the object. Else returns null
func get_highlighted_slot() -> BoardPlacementSlot:
	if is_instance_valid(_auto_slot):
		return _auto_slot
	var ret_slot: BoardPlacementSlot = null
	for slot in get_all_slots():
		if slot.is_highlighted():
			ret_slot = slot
	return(ret_slot)


# Returns the slot at the specified index.
func get_slot(idx: int) -> BoardPlacementSlot:
	var ret_slot: BoardPlacementSlot = $GridContainer.get_child(idx)
	return(ret_slot)


# Adds new placement slot to the grid.
# Returns the slot object
func add_slot() -> BoardPlacementSlot:
	var new_slot : BoardPlacementSlot = _SLOT_SCENE.instance()
	$GridContainer.add_child(new_slot)
	return(new_slot)


# Returns a slot that is not currently occupied by a card
func find_available_slot() -> BoardPlacementSlot:
	var found_slot : BoardPlacementSlot
	if auto_arrange:
		found_slot = get_auto_placement_slot()
	elif not get_available_slots().empty():
		found_slot = get_available_slots().front()
	if not found_slot and auto_extend:
		found_slot = add_slot()
	return(found_slot)


# Returns an array containing all the BoardPlacementSlot nodes
func get_all_slots() -> Array:
	return($GridContainer.get_children())


# Returns the amount of BoardPlacementSlot contained.
func get_slot_count() -> int:
	return(get_all_slots().size())


# Returns an array with all slots not occupied by a card
func get_available_slots() -> Array:
	var available_slots := []
	for slot in get_all_slots():
		if not slot.occupying_card:
			available_slots.append(slot)
	return(available_slots)


# Returns the count of all available slots
func count_available_slots() -> int:
	return(get_available_slots().size())


func _ensure_full_highlight() -> void:
	if _full_highlight:
		return
	_full_highlight = Panel.new()
	_full_highlight.name = "FullHighlight"
	_full_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_highlight.visible = false
	add_child(_full_highlight)
	_refresh_full_highlight_style()
	_full_highlight.raise()


func _refresh_full_highlight_style() -> void:
	if not _full_highlight:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(highlight.r, highlight.g, highlight.b, 0.16)
	style.border_color = Color(highlight.r, highlight.g, highlight.b, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	_full_highlight.add_stylebox_override("panel", style)


# A card rotated 90 degrees is as wide as the card is tall. Auto-arranged
# grids reserve that width so rotated cards never overlap their neighbours.
func _horizontal_separation() -> int:
	var separation: int = MousePointer.MOUSE_RADIUS * 2 + 1
	if not auto_arrange:
		return separation
	var upright_width: float = card_size.x * card_play_scale
	var rotated_width: float = card_size.y * card_play_scale
	return int(max(separation,
			rotated_width - upright_width + separation))


func _center_out_columns(columns: int) -> Array:
	var order := []
	var left := int(floor((columns - 1) * 0.5))
	var right := int(ceil((columns - 1) * 0.5))
	var offset := 0
	while order.size() < columns:
		var left_column := left - offset
		var right_column := right + offset
		if left_column >= 0 and not order.has(left_column):
			order.append(left_column)
		if right_column < columns and not order.has(right_column):
			order.append(right_column)
		offset += 1
	return order


func _prefers_back_row(card: Card) -> bool:
	if not card.has_method("is_battle_scenes_support") \
			or not card.is_battle_scenes_support():
		return false
	var columns: int = max(1, int($GridContainer.columns))
	for column in range(columns):
		if column >= get_slot_count():
			break
		var front_card = get_slot(column).occupying_card
		if front_card and front_card.has_method("is_battle_scenes_character") \
				and front_card.is_battle_scenes_character():
			return true
	return false


func _nearest_free_slot(
		mouse_pos: Vector2, card: Card) -> BoardPlacementSlot:
	var best_slot: BoardPlacementSlot = null
	var best_distance := INF
	for slot in get_all_slots():
		if slot.occupying_card and slot.occupying_card != card:
			continue
		var center: Vector2 = slot.rect_global_position \
				+ slot.rect_size * 0.5
		var distance := center.distance_squared_to(mouse_pos)
		if distance < best_distance:
			best_distance = distance
			best_slot = slot
	if not best_slot:
		best_slot = get_auto_placement_slot(card)
	return best_slot


func _find_free_slot_except(excluded: BoardPlacementSlot) -> BoardPlacementSlot:
	for slot in get_all_slots():
		if slot != excluded and not slot.occupying_card:
			return slot
	return null


func _contains_point(global_point: Vector2) -> bool:
	var local_point := global_point - rect_global_position
	return local_point.x >= 0 and local_point.y >= 0 \
			and local_point.x <= rect_size.x and local_point.y <= rect_size.y


func _is_scenario(card: Card) -> bool:
	if card.has_method("is_battle_scenes_scenario"):
		return card.is_battle_scenes_scenario()
	return str(card.properties.get("_tipo", "")) == "Cenário"
