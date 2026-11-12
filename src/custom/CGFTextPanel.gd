# Card text panel shown beside the focused card (hover preview and deck
# builder). A VBoxContainer so Header/Meta/Details stay direct children —
# DetailPanels.add_info() locates "Details" with get_node() — and the panel
# background is drawn here because plain containers don't render styleboxes.
extends VBoxContainer

# The text is laid out from the panel's own rect, so the background is drawn
# larger than the panel to give the text its padding.
const PADDING := Vector2(8, 6)

var _background := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	_background.bg_color = Color(0.09, 0.09, 0.11, 0.92)
	_background.border_color = Color(0.6, 0.6, 0.65, 0.6)
	_background.set_border_width_all(1)
	_background.set_corner_radius_all(4)
	queue_redraw()


func _draw() -> void:
	_background.draw(get_canvas_item(), Rect2(-PADDING, size + PADDING * 2))
