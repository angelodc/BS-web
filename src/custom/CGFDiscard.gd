extends Pile

# The discard always shows the top cards as a grid of mini cards; hovering one
# of them opens the big card preview on the right side of the screen. The pile
# background keeps the width of the left column so it never covers the field.
const GRID_COLUMNS := 3
const GRID_MAX_CARDS := 6
const GRID_GAP := 6.0
const GRID_MAX_SCALE := 0.4
const GRID_MIN_SCALE := 0.26
const LABEL_SCALE := 0.45
const BUTTON_SCALE := 0.5
const PANEL_WIDTH := 156.0
const BACKDROP_RADIUS := 12
const BACKDROP_COLOR := Color(0.08, 0.09, 0.12, 0.55)
# Cards past the grid limit are parked outside the board instead of only made
# invisible, as an invisible Area2D would still be hoverable.
const OFF_GRID_POSITION := Vector2(-1000, -1000)
# The selection popup shows the resources at the hand card scale, so the cards
# read the same as the ones the player holds. The grid wraps into as many
# columns as fit the viewport, and the window shrinks as resources are picked.
const POPUP_CARD_SEPARATION := 4.0
const POPUP_MAX_COLUMNS := 7
const POPUP_VIEWPORT_MARGIN := 48.0

var _grid_scale := GRID_MAX_SCALE
var _grid_origin := Vector2.ZERO
var _grid_step := Vector2.ZERO
var _backdrop: Panel

var _focused_card: Card = null
var _preview_card: Card = null


func _ready() -> void:
	._ready()
	_create_backdrop()
	$Control/ManipulationButtons/View.show()
	$Control/ManipulationButtons/View.text = "Ver"
	$Control/ManipulationButtons/View.hint_tooltip = \
			"Ver cartas em Recursos / Descarte"
	$Control/ManipulationButtons/ViewSorted.hide()
	$Control/ManipulationButtons/Shuffle.hide()
	var label: Label = $Control/CenterContainer/VBoxContainer/Label
	label.text = "Recursos"
	label.align = Label.ALIGN_CENTER
	var swap_button := Button.new()
	swap_button.name = "SwapResource"
	swap_button.text = "Trocar"
	swap_button.rect_min_size = Vector2(92, 27)
	swap_button.mouse_filter = Control.MOUSE_FILTER_PASS
	swap_button.modulate.a = 0
	swap_button.add_to_group("manipulation_button")
	$Control/ManipulationButtons.add_child(swap_button)
	swap_button.connect("pressed", self, "_on_SwapResource_pressed")


func _exit_tree() -> void:
	_set_preview(null)


func remove_child(node, legible_unique_name := false) -> void:
	.remove_child(node, legible_unique_name)
	if node is Card:
		# The grid cards stay out of the global mouse detection while they are
		# here, so a card leaving the pile has to return to it.
		node.monitorable = true


func _process(_delta: float) -> void:
	# The popup upkeep also runs in tests, as the pile's own _process would.
	_keep_popup_fitted()
	if cfc.ut:
		return
	_layout_panel()
	# While the selection popup is open the cards live in its slots, so the mini
	# grid must keep its hands off them. `is_popup_open` stays true through the
	# close animation, after the popup is already hidden.
	if is_popup_open or pile_popup.visible:
		_set_preview(null)
		return
	_apply_grid()
	_update_preview()


# The pile maintains its own popup in _process, which this pile overrides. The
# empty slots left behind by the picked resources are dropped and the window is
# resized so it follows the shrinking card count.
func _keep_popup_fitted() -> void:
	var changed := false
	for slot in $ViewPopup/CardView.get_children():
		if not slot.get_child_count():
			$ViewPopup/CardView.remove_child(slot)
			slot.queue_free()
			changed = true
	if not pile_popup.visible and not changed:
		return
	var previous_size: Vector2 = $ViewPopup.rect_size
	$ViewPopup.set_as_minsize()
	if not pile_popup.visible \
			or $ViewPopup.rect_size.is_equal_approx(previous_size):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	$ViewPopup.rect_position = (viewport_size - $ViewPopup.rect_size) * 0.5


# Resources in the popup use the hand card scale and wrap to the viewport width.
func populate_popup(sorted := sorted_popup) -> void:
	_update_popup_columns(get_all_cards(false).size())
	.populate_popup(sorted)


func _update_popup_columns(card_count: int) -> void:
	var card_width: float = CFConst.CARD_SIZE.x * _popup_card_scale() \
			+ POPUP_CARD_SEPARATION
	var available: float = get_viewport().get_visible_rect().size.x \
			- 2.0 * POPUP_VIEWPORT_MARGIN
	var fit_columns := int(available / card_width)
	var columns := int(min(min(card_count, fit_columns), POPUP_MAX_COLUMNS))
	$ViewPopup/CardView.columns = max(columns, 1)


func _popup_card_scale() -> float:
	var hand = cfc.NMAP.get("hand", null)
	if hand and is_instance_valid(hand):
		return hand.card_display_scale
	return CFConst.HAND_CARD_SCALE


# Cards come from the mini grid, which hides the overflow ones and takes them
# out of the mouse detection. In the popup they all have to be visible, at the
# hand size and hoverable so the player can click them.
func _slot_card_into_popup(card: Card) -> void:
	var card_scale := _popup_card_scale()
	card.popup_scale = card_scale
	card.scale = Vector2(card_scale, card_scale)
	card.visible = true
	card.monitorable = true
	card.z_index = 0
	var card_slot := Control.new()
	card_slot.set_name("CardPopUpSlot")
	card_slot.rect_min_size = card.get_node("Control").rect_min_size * card.scale
	$ViewPopup/CardView.add_child(card_slot)
	card_slot.add_child(card)
	card.set_is_faceup(true, true)
	card.position = Vector2(0, 0)
	card.state = card.CardState.IN_POPUP


# The pile fades its own panel out once it holds cards, which would leave the
# label and the buttons floating over the field. The panel style is replaced by
# this tray, which lives under the Control children and ignores the fade so the
# column always reads as the resources zone.
func _create_backdrop() -> void:
	var control: Control = get_node("Control")
	control.add_stylebox_override("panel", StyleBoxEmpty.new())
	_backdrop = Panel.new()
	_backdrop.name = "GridBackdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = BACKDROP_COLOR
	style.set_corner_radius_all(BACKDROP_RADIUS)
	_backdrop.add_stylebox_override("panel", style)
	control.add_child(_backdrop)
	control.move_child(_backdrop, 0)


func _on_SwapResource_pressed() -> void:
	cfc.NMAP.board.begin_resource_swap()


# Places the label above the mini grid and the action buttons below it, all
# inside a panel with the width of the left column.
func _layout_panel() -> void:
	var control: Control = get_node("Control")
	var width: float = PANEL_WIDTH
	var label: Control = $Control/CenterContainer
	var content: Control = $Control/CenterContainer/VBoxContainer
	var buttons: Control = $Control/ManipulationButtons
	_grid_scale = clamp(
			(width - 12.0 - (GRID_COLUMNS - 1) * GRID_GAP) \
					/ (GRID_COLUMNS * CFConst.CARD_SIZE.x),
			GRID_MIN_SCALE, GRID_MAX_SCALE)
	# The card state machine uses this scale while the card rests in the pile,
	# so it has to match the grid or a freshly discarded card would grow back
	# to the pile size and cover the whole tray.
	card_display_scale = _grid_scale
	var card_size: Vector2 = CFConst.CARD_SIZE * _grid_scale
	var grid_size := Vector2(
			GRID_COLUMNS * card_size.x + (GRID_COLUMNS - 1) * GRID_GAP,
			2 * card_size.y + GRID_GAP)
	# The label container is anchored to the panel width, so its content is
	# centered inside it; scaling it needs the position corrected to keep the
	# shrunken content centered as well.
	var content_size: Vector2 = content.get_combined_minimum_size()
	var label_center := label.rect_size * 0.5
	var buttons_size: Vector2 = \
			buttons.get_combined_minimum_size() * BUTTON_SCALE
	var panel_size := Vector2(
			width,
			4.0 + content_size.y * LABEL_SCALE + 4.0 + grid_size.y + 4.0 \
					+ buttons_size.y + 4.0)
	control.rect_min_size = panel_size
	if not control.rect_size.is_equal_approx(panel_size):
		control.rect_size = panel_size
	control.rect_position = Vector2.ZERO
	if is_instance_valid(_backdrop):
		_backdrop.rect_size = panel_size
	label.rect_scale = Vector2(LABEL_SCALE, LABEL_SCALE)
	label.rect_position = Vector2(
			label_center.x - label_center.x * LABEL_SCALE,
			4.0 + content_size.y * LABEL_SCALE * 0.5 \
					- label_center.y * LABEL_SCALE)
	buttons.rect_scale = Vector2(BUTTON_SCALE, BUTTON_SCALE)
	buttons.rect_position = Vector2(
			width - buttons_size.x - 6.0,
			panel_size.y - buttons_size.y - 4.0)
	_grid_origin = Vector2(
			(width - grid_size.x) * 0.5,
			4.0 + content_size.y * LABEL_SCALE + 4.0)
	_grid_step = card_size + Vector2(GRID_GAP, GRID_GAP)


func _apply_grid() -> void:
	var cards := get_all_cards(false)
	var count := cards.size()
	for index in range(count):
		var card: Card = cards[index]
		var from_top := count - 1 - index
		# The grid draws and previews the cards itself, so they are kept out of
		# the global mouse detection. Otherwise a mini left over from a hover can
		# take the focus from the hand card under the pointer.
		if card.monitorable:
			card.monitorable = false
		if from_top >= GRID_MAX_CARDS:
			card.visible = false
			if card.position != OFF_GRID_POSITION:
				card.position = OFF_GRID_POSITION
			continue
		if not card.visible:
			card.visible = true
		var target_scale := Vector2(_grid_scale, _grid_scale)
		if not card.scale.is_equal_approx(target_scale):
			card.scale = target_scale
		var target_position := _grid_origin + Vector2(
				from_top % GRID_COLUMNS,
				int(from_top / GRID_COLUMNS)) * _grid_step
		if card.position != target_position:
			card.position = target_position
		card.z_index = 30 + GRID_MAX_CARDS - from_top


func _update_preview() -> void:
	if cfc.card_drag_ongoing or pile_popup.visible:
		_set_preview(null)
		return
	var mouse := get_global_mouse_position()
	var card_size: Vector2 = CFConst.CARD_SIZE * _grid_scale
	var hovered: Card = null
	for card in get_all_cards(false):
		if not card.visible:
			continue
		if Rect2(card.global_position, card_size).has_point(mouse):
			hovered = card
	_set_preview(hovered)
	if hovered:
		return
	# The pile focuses its top card while the pointer rests over its area, and
	# the card state machine keeps that preview when the pointer leaves, so the
	# grid releases its own cards as soon as the pile is not under the mouse.
	if _is_pointer_over_pile():
		return
	_unfocus_pile_cards()


func _is_pointer_over_pile() -> bool:
	var board = cfc.NMAP.get("board", null)
	if not board or not board.mouse_pointer:
		return false
	return board.mouse_pointer in get_overlapping_areas()


# A card entering the pile is focused by the card state machine, which would
# leave its preview covering the board. The grid only previews what is hovered.
func _unfocus_pile_cards() -> void:
	if cfc.ut or not cfc.NMAP.has("main") or not cfc.NMAP.main:
		return
	for card in get_all_cards(false):
		_release_card_focus(card)


func _release_card_focus(card: Card) -> void:
	cfc.NMAP.main.unfocus(card)
	# A card left in VIEWED_IN_PILE asks the focus viewport for its preview every
	# frame, which would keep stealing it from the hand card under the pointer.
	if card.state == Card.CardState.VIEWED_IN_PILE:
		card.set_state(Card.CardState.IN_PILE)


# The focus viewport shows one preview at a time, so the previous card is
# unfocused before the next one is asked for.
func _set_preview(card: Card) -> void:
	if card == _focused_card:
		return
	_focused_card = card
	if cfc.ut or not cfc.NMAP.has("main") or not cfc.NMAP.main:
		return
	if is_instance_valid(_preview_card):
		_release_card_focus(_preview_card)
	_preview_card = card if is_instance_valid(card) else null
	if _preview_card:
		cfc.NMAP.main.focus_card(_preview_card)
