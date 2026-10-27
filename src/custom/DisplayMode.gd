extends Node

const WINDOWED_ENV := "BS_WINDOWED"
const WINDOWED_SIZE := Vector2(960, 540)
const WINDOWED_POSITION := Vector2(220, 140)
# With stretch mode 2D the UI keeps its 1280x720 design coordinates while
# rendering at the window's native resolution, so a larger window stays sharp.
const DESKTOP_WINDOW_SIZE := Vector2(1280, 720)
const TITLE_BAR_ALLOWANCE := 30.0


func _ready() -> void:
	if OS.get_environment(WINDOWED_ENV) == "1":
		call_deferred("_apply_windowed")
	else:
		_apply_desktop_window()


func _apply_desktop_window() -> void:
	OS.window_fullscreen = false
	if OS.get_screen_count() == 0:
		OS.window_borderless = true
		OS.window_size = DESKTOP_WINDOW_SIZE
		return
	var screen := _primary_screen()
	var screen_position := OS.get_screen_position(screen)
	var screen_size := OS.get_screen_size(screen)
	# A window tall enough to touch the screen edges only fits without a title
	# bar and taskbar, so it takes over the monitor as a borderless window.
	var borderless := DESKTOP_WINDOW_SIZE.y + TITLE_BAR_ALLOWANCE > screen_size.y
	OS.window_borderless = borderless
	var window_size := Vector2(
			min(DESKTOP_WINDOW_SIZE.x, screen_size.x),
			min(DESKTOP_WINDOW_SIZE.y, screen_size.y))
	if not borderless:
		window_size = Vector2(
				min(window_size.x, screen_size.x - 40),
				min(window_size.y, screen_size.y - 70))
	OS.window_size = window_size
	var y_offset := (screen_size.y - window_size.y) * 0.5
	if not borderless:
		y_offset -= TITLE_BAR_ALLOWANCE * 0.5
	OS.window_position = screen_position + Vector2(
			(screen_size.x - window_size.x) * 0.5, y_offset)


# Godot's screen order does not follow the primary monitor order. Windows
# always places the primary monitor at the virtual desktop origin.
func _primary_screen() -> int:
	for index in range(OS.get_screen_count()):
		if OS.get_screen_position(index) == Vector2.ZERO:
			return index
	return 0


func _apply_windowed() -> void:
	OS.window_fullscreen = false
	OS.window_borderless = false
	OS.window_size = WINDOWED_SIZE
	OS.window_position = WINDOWED_POSITION


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.scancode == KEY_F11:
		OS.window_fullscreen = not OS.window_fullscreen
		get_tree().set_input_as_handled()
