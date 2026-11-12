# The popup with an instance of a card instide. 
# Typically in larger version for easy viewing.
class_name CVPreviewPopup
extends Control

signal placement_initialized

# The preview is kept inside the host window so it is never cropped. The top
# margin keeps it clear of the embedded window title bar.
const PLACEMENT_MARGIN := 12.0
const PLACEMENT_TOP_MARGIN := 34.0

# The card currently being shown in a popup.
var preview_card: Card
var _tween_wait := 0
var _placement_initialized := false
var _visible = true
# The popup panel which contains the card.
@onready var focus_info := $FocusInfo
@onready var _tween := LegacyTween.new(self)

func _ready() -> void:
	# The preview is placed in viewport coordinates so it follows the cursor
	# instead of inheriting the grid cell that owns it. Inside a Window (the
	# card selection dialog) those coordinates are the window's own, so the
	# placement below is clamped to that window's visible rect.
	top_level = true
	# warning-ignore:return_value_discarded
	get_viewport().size_changed.connect(_on_viewport_resized)
	# warning-ignore:return_value_discarded
	placement_initialized.connect(_on_placement_initialized)

func _process(_delta: float) -> void:
	if _placement_initialized and visible and is_instance_valid(preview_card):
		_set_placement()

func _set_placement() -> void:
	if _tween.is_active():
		return
	var new_position : Vector2 = get_preview_placement()
	# We only want to tween, if the card position is changing dramatically
	# such as when the info panels would exceed the width of the monitor, and therefore
	# we need to move them to the other side of the mouse cursor.
	if not _placement_initialized:
		await get_tree().create_timer(0.1).timeout
		position = get_preview_placement()
	elif new_position.distance_to(position) > 200:
		_tween_wait += 1
		# This is needed because the focus_info is wiped of all panels every time it's refreshed
		# so there's a small period of time where it's width is always 0
		# This causes the tween to activate twice back and forth every time a card hover is switched to
		# a new card. 
		# To avoid that, we put a small delay, to ensure the info panels have neen repopulated
		if _tween_wait > 10:
			_tween_wait = 0
			_tween.interpolate_property(self, "position", position, new_position, 0.2, Tween.TRANS_EXPO, Tween.EASE_IN)
			_tween.start()
#			print_debug([preview_card, get_preview_placement()])
	else:
		position = new_position
	focus_info.custom_minimum_size.x = 0.0
	focus_info.size.x = 0.0
	focus_info.position.y = 0
	focus_info.position.x = preview_card.canonical_size.x * preview_card.preview_scale * cfc.curr_scale
	if not _placement_initialized:
		_placement_initialized = true
		emit_signal("placement_initialized")

	
# Figures out where to place the card preview in respect to the player's mouse.
func get_preview_placement() -> Vector2:
	if not is_instance_valid(preview_card):
		return position
	var screen := get_viewport().get_visible_rect().size
	var card_size := _preview_card_size()
	# A narrow dialog has no room for the info panels beside the card; showing
	# the card alone keeps both from being cropped by the window.
	if focus_info.visible\
			and card_size.x + focus_info.size.x > screen.x - 2.0 * PLACEMENT_MARGIN:
		focus_info.visible = false
	var panel_size: Vector2 = focus_info.size if focus_info.visible else Vector2.ZERO
	# A Viewport has no get_global_mouse_position(); the CanvasItem helper keeps
	# working both in the game viewport and in the selection dialog's window.
	return compute_preview_position(
			get_global_mouse_position(), screen, card_size, panel_size)


# Places the card and its panels around the mouse, then clamps the whole block
# into the host window. Inside a Window (the card selection dialog) anything
# past the window edge would be clipped, so the preview has to stay inside it.
static func compute_preview_position(
		mouse: Vector2, screen: Vector2, card_size: Vector2,
		panel_size: Vector2) -> Vector2:
	var total := Vector2(
			card_size.x + panel_size.x,
			max(card_size.y, panel_size.y))
	var max_x: float = max(PLACEMENT_MARGIN, screen.x - PLACEMENT_MARGIN - total.x)
	var max_y: float = max(PLACEMENT_TOP_MARGIN, screen.y - PLACEMENT_MARGIN - total.y)
	var ret := Vector2(mouse.x + 20.0, mouse.y + 30.0)
	# The card moves to the other side of the cursor only when it would not fit
	# on the preferred side.
	if ret.x + total.x > screen.x - PLACEMENT_MARGIN:
		ret.x = mouse.x - 20.0 - total.x
	if ret.y + total.y > screen.y - PLACEMENT_MARGIN:
		ret.y = screen.y - PLACEMENT_MARGIN - total.y
	ret.x = clamp(ret.x, PLACEMENT_MARGIN, max_x)
	ret.y = clamp(ret.y, PLACEMENT_TOP_MARGIN, max_y)
	return ret


# In a small dialog even the card alone would be cropped, so the preview scale
# is reduced just enough to fit the host window.
static func fit_preview_scale(
		requested: float, screen: Vector2, canonical_size: Vector2,
		curr_scale := 1.0) -> float:
	if requested <= 0.0 or canonical_size.x <= 0.0 or canonical_size.y <= 0.0:
		return requested
	var available := Vector2(
			screen.x - 2.0 * PLACEMENT_MARGIN,
			screen.y - PLACEMENT_TOP_MARGIN - PLACEMENT_MARGIN)
	var fit: float = min(
			available.x / (canonical_size.x * curr_scale),
			available.y / (canonical_size.y * curr_scale))
	return min(requested, fit)


func _preview_card_size() -> Vector2:
	return preview_card.canonical_size * preview_card.preview_scale * cfc.curr_scale


# Instances a card object. Populates it with the card details
# Then displays it in the popup.
# The variable passed can be a card name, or a card instance.
# If it's a card instance, it will be added to this node as a child directly.
func show_preview_card(card) -> void:
	if not has_preview_card():
		if typeof(card) == TYPE_STRING:
			preview_card = cfc.instance_card(card)
		else:
			preview_card = card
			preview_card.position = Vector2(0,0)
			preview_card.scale = Vector2(1,1)
		add_child(preview_card)
		preview_card.preview_scale = fit_preview_scale(
				preview_card.preview_scale,
				get_viewport().get_visible_rect().size,
				preview_card.canonical_size,
				cfc.curr_scale)
		# It's necessary we do this here because if we only we it during
		# the process, the card will appear to teleport
		if CFConst.VIEWPORT_FOCUS_ZOOM_TYPE == "resize":
			preview_card.resize_recursively(preview_card._control, preview_card.preview_scale * cfc.curr_scale)
			preview_card.card_front.scale_to(preview_card.preview_scale * cfc.curr_scale)
		cfc.ov_utils.populate_info_panels(preview_card,focus_info)
		call_deferred("_set_placement")
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true
	_visible = true
	if _placement_initialized:
		modulate.a = 1



# Hides currently shown card.
# We're modulating to 0 instead of hide() because that messes with the rich text labels formatting
func hide_preview_card() -> void:
	modulate.a = 0
	
	_visible = false

func _on_placement_initialized() -> void:
	if _visible:
		modulate.a = 1

# We want to recreate the popup after the viewport size has changed
# As otherwise its elements may end up messed up
func _on_viewport_resized() -> void:
	if is_instance_valid(preview_card):
		preview_card.queue_free()


# Returns true if the preview_card variable has a valid Card instance
# else returns false
func has_preview_card() -> bool:
	return(is_instance_valid(preview_card))
