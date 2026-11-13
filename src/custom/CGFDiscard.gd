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
var _preview_pinned := false
# The send buttons live in the pile panel and again inside the viewer, and both
# copies read the armed side from the board so they always agree.
var _send_deck_panel: Button
var _add_perso_panel: Button
var _popup_actions: HBoxContainer
var _popup_send_top: Button
var _popup_send_base: Button
var _popup_send_hand: Button
var _popup_add_perso: Button
# The actions taken in the viewer answer under the card box, where the window
# is on screen; the board label would end up under the hand.
var _viewer_message: Label


func _ready() -> void:
	super._ready()
	_create_backdrop()
	$Control/ManipulationButtons/View.show()
	$Control/ManipulationButtons/View.text = "Ver"
	$Control/ManipulationButtons/View.tooltip_text = \
			"Ver cartas em Recursos / Descarte"
	$Control/ManipulationButtons/ViewSorted.hide()
	$Control/ManipulationButtons/Shuffle.hide()
	var label: Label = $Control/CenterContainer/VBoxContainer/Label
	label.text = "Recursos"
	label.align = HORIZONTAL_ALIGNMENT_CENTER
	var swap_button := Button.new()
	swap_button.name = "SwapResource"
	swap_button.text = "Trocar"
	swap_button.custom_minimum_size = Vector2(92, 27)
	swap_button.mouse_filter = Control.MOUSE_FILTER_PASS
	swap_button.modulate.a = 0
	swap_button.add_to_group("manipulation_button")
	$Control/ManipulationButtons.add_child(swap_button)
	swap_button.pressed.connect(_on_SwapResource_pressed)
	var add_perso_button := _add_panel_button("AddPerso", "+ personagem")
	add_perso_button.tooltip_text = "Adiciona carta ao personagem escolhido"
	add_perso_button.pressed.connect(_on_AddPerso_pressed)
	_add_perso_panel = add_perso_button
	_send_deck_panel = _add_panel_button("SendDeck", "Enviar deck", false)
	_send_deck_panel.pressed.connect(_on_SendDeck_pressed)
	_arrange_panel_buttons(swap_button, add_perso_button)
	_build_popup_actions()
	# The viewer is a panel over the field: while it is open the field cards
	# must not keep the hover (and its closeup) behind it.
	pile_popup.visibility_changed.connect(_on_viewer_popup_visibility_changed)
	# The pile's own remove_child() override is never called in Godot 4, so the
	# grid cards get their mouse detection back through the tree signal.
	child_exiting_tree.connect(_restore_card_monitorable)


func _exit_tree() -> void:
	_set_preview(null)


func _restore_card_monitorable(node: Node) -> void:
	if node is Card:
		# The grid cards stay out of the global mouse detection while they are
		# here, so a card leaving the pile has to return to it.
		node.monitorable = true


func _process(_delta: float) -> void:
	# The popup upkeep also runs in tests, as the pile's own _process would.
	_keep_popup_fitted()
	_sync_action_buttons()
	if cfc.ut:
		return
	_layout_panel()
	# While the selection popup is open the cards live in its slots, so the mini
	# grid must keep its hands off them. `is_popup_open` stays true through the
	# close animation, after the popup is already hidden.
	if is_popup_open or pile_popup.visible:
		_update_popup_preview()
		return
	_apply_grid()
	_update_preview()


# The pile maintains its own popup in _process, which this pile overrides. The
# empty slots left behind by the picked resources are dropped and the window is
# resized so it follows the shrinking card count.
func _keep_popup_fitted() -> void:
	var changed := false
	for slot in _popup_grid.get_children():
		if not slot.get_child_count():
			_popup_grid.remove_child(slot)
			slot.queue_free()
			changed = true
	if not pile_popup.visible and not changed:
		return
	# The viewer is a panel of the table now: resizing keeps it centered.
	if pile_popup.visible:
		_center_popup()
	else:
		$ViewPopup.reset_size()


# Resources in the popup use the hand card scale and wrap to the viewport width.
func populate_popup(sorted := sorted_popup) -> void:
	_update_popup_columns(get_all_cards(false).size())
	super.populate_popup(sorted)


# An empty viewer has no window size, so its action row would be drawn but the
# click would fall through and close the popup. Pressing Ver on an empty pile
# says so instead of opening a window that cannot be used.
func _on_View_Button_pressed() -> void:
	if get_all_cards(false).is_empty():
		cfc.NMAP.board.show_transient_resource_message(
				"Não há cartas nos Recursos.", 3.0)
		return
	super._on_View_Button_pressed()


func _update_popup_columns(card_count: int) -> void:
	var card_width: float = CFConst.CARD_SIZE.x * _popup_card_scale() \
			+ POPUP_CARD_SEPARATION
	var available: float = get_viewport().get_visible_rect().size.x \
			- 2.0 * POPUP_VIEWPORT_MARGIN
	var fit_columns := int(available / card_width)
	var columns := int(min(min(card_count, fit_columns), POPUP_MAX_COLUMNS))
	_popup_grid.columns = max(columns, 1)


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
	_popup_slot_serial += 1
	card_slot.set_name("CardPopUpSlot" + str(_popup_slot_serial))
	card_slot.custom_minimum_size = card.get_node("Control").custom_minimum_size * card.scale
	_popup_grid.add_child(card_slot)
	card_slot.add_child(card)
	card.set_is_faceup(true, true)
	card.position = Vector2(0, 0)
	card.state = card.CardState.IN_POPUP
	if not card.is_connected("card_moved_to_pile", _on_popup_card_moved_to_pile):
		# The signal already carries the card as its first argument, so binding it
		# again would hand four values to a three-parameter method.
		card.card_moved_to_pile.connect(_on_popup_card_moved_to_pile)
	if not card.is_connected("card_moved_to_hand", _on_popup_card_moved_to_hand):
		card.card_moved_to_hand.connect(_on_popup_card_moved_to_hand)


# A resource leaving the viewer for the deck keeps its own place: the viewer
# asks which end before the click, so the card is not moved a second time here.
func _on_popup_card_moved_to_pile(card: Card, _trigger: String,
		details: Dictionary) -> void:
	# The card is already under the destination pile when the signal arrives, so
	# the viewer is identified by the slot the card came from.
	if not "CardPopUpSlot" in str(details.get("source", "")):
		return
	# The viewer keeps its own list of the cards it opened with, so a card that
	# left has to be dropped from it or the count and the shrinking window keep
	# counting a card that is no longer here.
	pre_sorted_order.erase(card)
	card_count_label.text = str(get_card_count())
	_close_popup_if_empty()


# A viewer card picked into the hand leaves the same way a pile move does.
func _on_popup_card_moved_to_hand(card: Card, _trigger: String,
		details: Dictionary) -> void:
	if not "CardPopUpSlot" in str(details.get("source", "")):
		return
	pre_sorted_order.erase(card)
	card_count_label.text = str(get_card_count())
	_close_popup_if_empty()


# Once the last card leaves, the viewer has nothing left to show and the action
# row would keep floating over the field, so the window closes with it.
func _close_popup_if_empty() -> void:
	if pile_popup.visible and pre_sorted_order.is_empty():
		pile_popup.hide()


# The pile fades its own panel out once it holds cards, which would leave the
# label and the buttons floating over the field. The panel style is replaced by
# this tray, which lives under the Control children and ignores the fade so the
# column always reads as the resources zone.
func _create_backdrop() -> void:
	var control: Control = get_node("Control")
	control.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_backdrop = Panel.new()
	_backdrop.name = "GridBackdrop"
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = BACKDROP_COLOR
	style.set_corner_radius_all(BACKDROP_RADIUS)
	_backdrop.add_theme_stylebox_override("panel", style)
	control.add_child(_backdrop)
	control.move_child(_backdrop, 0)


func _on_SwapResource_pressed() -> void:
	cfc.NMAP.board.begin_resource_swap()


# The panel keeps the send buttons left of Ver/Trocar in a two-column grid that
# spans the column, so the empty strip on the left of the buttons is used.
func _arrange_panel_buttons(swap_button: Button,
		add_perso_button: Button) -> void:
	var stack: VBoxContainer = $Control/ManipulationButtons
	var view_button: Button = stack.get_node("View")
	var grid := GridContainer.new()
	grid.name = "ResourceButtonGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.custom_minimum_size = Vector2(PANEL_WIDTH / BUTTON_SCALE, 0)
	stack.add_child(grid)
	for button in [_send_deck_panel, view_button, swap_button, add_perso_button]:
		stack.remove_child(button)
		grid.add_child(button)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 27)


# The panel buttons are created here rather than authored in Pile.tscn so every
# pile in the project keeps its own button set.
func _add_panel_button(button_name: String, text: String,
		toggle := true) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.toggle_mode = toggle
	button.custom_minimum_size = Vector2(92, 27)
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.modulate.a = 0
	button.add_to_group("manipulation_button")
	$Control/ManipulationButtons.add_child(button)
	return button


# The viewer covers the board, so the destinations are offered under the card
# grid while it is open: the two ends of the deck, the hand of the player who
# owns the resources, and one more card under a character.
func _build_popup_actions() -> void:
	_popup_actions = HBoxContainer.new()
	_popup_actions.name = "ResourceActions"
	_popup_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_popup_actions.add_theme_constant_override("separation", 8)
	# The popup stretches its only direct child to the panel, so the row lives
	# in the same vertical container as the grid and is stacked under it.
	$ViewPopup/PopupContent.add_child(_popup_actions)
	_popup_send_top = _add_popup_button("SendTop", "Enviar topo do deck", true)
	_popup_send_top.pressed.connect(_on_SendTop_pressed)
	_popup_send_base = _add_popup_button("SendBase", "Enviar base do deck", true)
	_popup_send_base.pressed.connect(_on_SendBase_pressed)
	_popup_send_hand = _add_popup_button("SendHand", "Adicionar à mão", true)
	_popup_send_hand.pressed.connect(_on_SendHand_pressed)
	_popup_add_perso = _add_popup_button("AddPerso", "Adiciona personagem", true)
	_popup_add_perso.tooltip_text = "Adiciona carta ao personagem escolhido"
	_popup_add_perso.pressed.connect(_on_AddPerso_pressed)
	_viewer_message = Label.new()
	_viewer_message.name = "ViewerMessage"
	_viewer_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_viewer_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_viewer_message.custom_minimum_size = Vector2(320, 0)
	$ViewPopup/PopupContent.add_child(_viewer_message)


# The board writes its action messages here while the viewer is open.
func viewer_message_label() -> Label:
	return _viewer_message


func _on_viewer_popup_hide() -> void:
	if is_instance_valid(_viewer_message):
		_viewer_message.text = ""


func _on_viewer_popup_visibility_changed() -> void:
	if pile_popup.visible:
		_on_viewer_popup_about_to_show()
	else:
		_on_viewer_popup_hide()


func _on_viewer_popup_about_to_show() -> void:
	var board = cfc.NMAP.get("board", null)
	if is_instance_valid(board) and board.has_method("set_table_input_blocked"):
		board.set_table_input_blocked(true)


func _add_popup_button(button_name: String, text: String,
		toggle := false) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.toggle_mode = toggle
	button.custom_minimum_size = Vector2(118, 34)
	_popup_actions.add_child(button)
	return button


func _on_SendDeck_pressed() -> void:
	cfc.NMAP.board.open_resource_send_viewer()


func _on_SendTop_pressed() -> void:
	cfc.NMAP.board.begin_resource_send("topo")


func _on_SendBase_pressed() -> void:
	cfc.NMAP.board.begin_resource_send("base")


func _on_SendHand_pressed() -> void:
	cfc.NMAP.board.begin_resource_send("mao")


func _on_AddPerso_pressed() -> void:
	cfc.NMAP.board.begin_resource_add()


# Every copy of each action button shows which mode is armed; the board owns
# the state.
func _sync_action_buttons() -> void:
	var side := ""
	var add_active := false
	var board = cfc.NMAP.get("board", null)
	if is_instance_valid(board):
		var armed = board.get("pending_resource_send_side")
		if armed is String:
			side = armed
		add_active = bool(board.get("pending_resource_add_active"))
	if is_instance_valid(_popup_send_top):
		_popup_send_top.set_pressed_no_signal(side == "topo")
	if is_instance_valid(_popup_send_base):
		_popup_send_base.set_pressed_no_signal(side == "base")
	if is_instance_valid(_popup_send_hand):
		_popup_send_hand.set_pressed_no_signal(side == "mao")
	for button in [_add_perso_panel, _popup_add_perso]:
		if is_instance_valid(button):
			button.set_pressed_no_signal(add_active)


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
	# The caption and the count sit on the left edge: the negation pins take the
	# strip to the right of the count, inside the same resources area.
	var content_size: Vector2 = content.get_combined_minimum_size()
	var label_center := label.size * 0.5
	var buttons_size: Vector2 = \
			buttons.get_combined_minimum_size() * BUTTON_SCALE
	var panel_size := Vector2(
			width,
			4.0 + content_size.y * LABEL_SCALE + 4.0 + grid_size.y + 4.0 \
					+ buttons_size.y + 4.0)
	control.custom_minimum_size = panel_size
	if not control.size.is_equal_approx(panel_size):
		control.size = panel_size
	control.position = Vector2.ZERO
	if is_instance_valid(_backdrop):
		_backdrop.size = panel_size
	label.scale = Vector2(LABEL_SCALE, LABEL_SCALE)
	label.position = Vector2(
			4.0 - (label.size.x - content_size.x) * 0.5 * LABEL_SCALE,
			4.0 + content_size.y * LABEL_SCALE * 0.5 \
					- label_center.y * LABEL_SCALE)
	buttons.scale = Vector2(BUTTON_SCALE, BUTTON_SCALE)
	buttons.position = Vector2(
			max(0.0, (width - buttons_size.x) * 0.5),
			panel_size.y - buttons_size.y - 4.0)
	_grid_origin = Vector2(
			(width - grid_size.x) * 0.5,
			4.0 + content_size.y * LABEL_SCALE + 4.0)
	_grid_step = card_size + Vector2(GRID_GAP, GRID_GAP)


# The opponent mirror draws the same mini grid, so it asks for these numbers
# instead of keeping a second copy of the layout that could drift from this one.
func grid_layout() -> Dictionary:
	return {"origin": _grid_origin, "step": _grid_step, "scale": _grid_scale}


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
	if cfc.card_drag_ongoing:
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


# The viewer is a panel of the table and its cards share the board canvas, so
# the closeup is pinned beside the pointer on that same canvas.
func _update_popup_preview(mouse := get_global_mouse_position()) -> void:
	if not pile_popup.visible or cfc.card_drag_ongoing:
		_set_preview(null)
		return
	var hovered: Card = null
	for card in pre_sorted_order:
		if not is_instance_valid(card) or not card.visible:
			continue
		if Rect2(card.global_position,
				CFConst.CARD_SIZE * card.scale).has_point(mouse):
			hovered = card
	_set_preview(hovered, true)


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
# unfocused before the next one is asked for. `pinned` keeps the closeup on the
# table beside the pointer, which is what the viewer hover needs.
func _set_preview(card: Card, pinned := false) -> void:
	if card == _focused_card and pinned == _preview_pinned:
		return
	_focused_card = card
	_preview_pinned = pinned
	if cfc.ut or not cfc.NMAP.has("main") or not cfc.NMAP.main:
		return
	if is_instance_valid(_preview_card):
		_release_card_focus(_preview_card)
	_preview_card = card if is_instance_valid(card) else null
	if _preview_card:
		if pinned:
			cfc.NMAP.main.focus_card_pinned(_preview_card)
		else:
			cfc.NMAP.main.focus_card(_preview_card)
