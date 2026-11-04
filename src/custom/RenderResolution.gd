extends RefCounted

# The table and the card preview are SubViewports rasterised at a fixed pixel
# size and stretched over the window, so they are the only blurred surfaces:
# the menu and the HUD re-rasterise their vector UI every frame. Raising the
# raster density here keeps the 1280x720 design coordinates (and the 300x450
# preview box) through `size_2d_override`, so no authored offset changes.
const DESIGN_SIZE := Vector2i(1280, 720)
const FOCUS_DESIGN_SIZE := Vector2i(300, 450)
const SETTING := "board_render_res"
const HD := "hd"
const HD_PLUS := "hdplus"
const FULL_HD := "fullhd"
# The web build always renders the table at HD+. The browser canvas decides how
# big it appears, so there is nothing to store or choose there.
const WEB_BOARD_SIZE := Vector2i(1600, 900)


static func is_web() -> bool:
	return OS.has_feature("web")


# On the desktop the player picks the density in the menu; Full HD is the
# default so the table arrives sharp, and HD stays as the fallback for smaller
# monitors that would rather keep a window instead of upscaling.
static func current_choice() -> String:
	if is_web():
		return HD_PLUS
	var choice := str(cfc.game_settings.get(SETTING, FULL_HD))
	return choice if choice in [HD, FULL_HD] else FULL_HD


static func set_choice(choice: String) -> void:
	if is_web() or not (choice in [HD, FULL_HD]):
		return
	cfc.set_setting(SETTING, choice)


static func board_pixels() -> Vector2i:
	match current_choice():
		FULL_HD:
			return Vector2i(1920, 1080)
		HD_PLUS:
			return WEB_BOARD_SIZE
		_:
			return DESIGN_SIZE


static func focus_pixels() -> Vector2i:
	return _scaled(FOCUS_DESIGN_SIZE)


# The desktop window follows the chosen density so the table is shown 1:1.
# The web window is the browser canvas and is left alone.
static func window_size() -> Vector2i:
	return board_pixels()


static func label(choice: String) -> String:
	match choice:
		FULL_HD:
			return "Full HD (1920x1080)"
		_:
			return "HD (1280x720)"


static func _scaled(base: Vector2i) -> Vector2i:
	var factor := float(board_pixels().x) / float(DESIGN_SIZE.x)
	return Vector2i(roundi(base.x * factor), roundi(base.y * factor))
