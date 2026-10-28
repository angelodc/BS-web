extends Pile

# The prize pile shows up to four quarter-size miniatures in a 2x2 grid, the
# same style as the discard. Hovering one opens the big card preview.
const GRID_COLUMNS := 2
const GRID_MAX_CARDS := 4
const GRID_CARD_SCALE := 0.25
const GRID_STEP := Vector2(42, 58)
const GRID_ORIGIN := Vector2(4, 4)
const PANEL_SIZE := Vector2(156, 122)
const LABEL_SCALE := 0.5
const BUTTON_SCALE := 0.5

var _focused_card: Card = null
var _preview_card: Card = null


func _ready() -> void:
	._ready()
	var label: Label = $Control/CenterContainer/VBoxContainer/Label
	label.align = Label.ALIGN_CENTER


func _exit_tree() -> void:
	_set_preview(null)


func _process(_delta: float) -> void:
	if cfc.ut:
		return
	_hold_panel()
	_layout_ui()
	_apply_grid()
	_update_preview()


# The pile restacking changes the panel size and its position, so the prize
# slot keeps a fixed quarter-size box at the pile origin.
func _hold_panel() -> void:
	var control: Control = get_node("Control")
	control.rect_min_size = PANEL_SIZE
	if control.rect_size != PANEL_SIZE:
		control.rect_size = PANEL_SIZE
	if control.rect_position != Vector2.ZERO:
		control.rect_position = Vector2.ZERO


# Keeps the shrunken label in the right column and the buttons under it.
func _layout_ui() -> void:
	var label: Control = $Control/CenterContainer
	var buttons: Control = $Control/ManipulationButtons
	var label_center := label.rect_size * 0.5
	label.rect_scale = Vector2(LABEL_SCALE, LABEL_SCALE)
	label.rect_position = Vector2(
			PANEL_SIZE.x - 32.0 - label_center.x * LABEL_SCALE,
			PANEL_SIZE.y * 0.5 - label_center.y * LABEL_SCALE)
	var buttons_size: Vector2 = \
			buttons.get_combined_minimum_size() * BUTTON_SCALE
	buttons.rect_scale = Vector2(BUTTON_SCALE, BUTTON_SCALE)
	buttons.rect_position = Vector2(
			PANEL_SIZE.x - buttons_size.x - 6.0,
			PANEL_SIZE.y - buttons_size.y - 4.0)


func _apply_grid() -> void:
	var cards := get_all_cards(false)
	var count := cards.size()
	for index in range(count):
		var card: Card = cards[index]
		var from_top := count - 1 - index
		if from_top >= GRID_MAX_CARDS:
			card.visible = false
			continue
		card.visible = true
		card.scale = Vector2(GRID_CARD_SCALE, GRID_CARD_SCALE)
		card.position = GRID_ORIGIN + Vector2(
				from_top % GRID_COLUMNS,
				int(from_top / GRID_COLUMNS)) * GRID_STEP
		card.z_index = 30 + GRID_MAX_CARDS - from_top


func _update_preview() -> void:
	if cfc.card_drag_ongoing or pile_popup.visible:
		_set_preview(null)
		return
	var mouse := get_global_mouse_position()
	var card_size: Vector2 = CFConst.CARD_SIZE * GRID_CARD_SCALE
	var hovered: Card = null
	for card in get_all_cards(false):
		if not card.visible:
			continue
		if Rect2(card.global_position, card_size).has_point(mouse):
			hovered = card
	_set_preview(hovered)


func _set_preview(card: Card) -> void:
	if card == _focused_card:
		return
	_focused_card = card
	if cfc.ut or not cfc.NMAP.has("main") or not cfc.NMAP.main:
		return
	if is_instance_valid(_preview_card):
		cfc.NMAP.main.unfocus(_preview_card)
	_preview_card = card if is_instance_valid(card) else null
	if _preview_card:
		cfc.NMAP.main.focus_card(_preview_card)
