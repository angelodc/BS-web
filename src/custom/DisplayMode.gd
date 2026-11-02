extends Node

const WINDOWED_ENV := "BS_WINDOWED"
const WINDOWED_SIZE := Vector2i(960, 540)
const WINDOWED_POSITION := Vector2i(220, 140)
# With stretch mode 2D the UI keeps its 1280x720 design coordinates while
# rendering at the window's native resolution, so a larger window stays sharp.
const DESKTOP_WINDOW_SIZE := Vector2i(1280, 720)
const TITLE_BAR_ALLOWANCE := 30.0


func _ready() -> void:
	if OS.get_environment(WINDOWED_ENV) == "1":
		call_deferred("_apply_windowed")
	else:
		_apply_desktop_window()


func _apply_desktop_window() -> void:
	get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if (false) else Window.MODE_WINDOWED
	if DisplayServer.get_screen_count() == 0:
		get_window().borderless = true
		get_window().size = DESKTOP_WINDOW_SIZE
		return
	var screen := _primary_screen()
	var screen_position := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	# A window tall enough to touch the screen edges only fits without a title
	# bar and taskbar, so it takes over the monitor as a borderless window.
	var borderless := DESKTOP_WINDOW_SIZE.y + TITLE_BAR_ALLOWANCE > screen_size.y
	get_window().borderless = borderless
	var window_size := Vector2i(
			min(DESKTOP_WINDOW_SIZE.x, screen_size.x),
			min(DESKTOP_WINDOW_SIZE.y, screen_size.y))
	if not borderless:
		window_size = Vector2i(
				min(window_size.x, screen_size.x - 40),
				min(window_size.y, screen_size.y - 70))
	get_window().size = window_size
	var y_offset := (screen_size.y - window_size.y) * 0.5
	if not borderless:
		y_offset -= TITLE_BAR_ALLOWANCE * 0.5
	get_window().position = screen_position + Vector2i(
			int((screen_size.x - window_size.x) * 0.5), int(y_offset))


# Godot's screen order does not follow the primary monitor order. Windows
# always places the primary monitor at the virtual desktop origin.
func _primary_screen() -> int:
	for index in range(DisplayServer.get_screen_count()):
		if DisplayServer.screen_get_position(index) == Vector2i.ZERO:
			return index
	return 0


func _apply_windowed() -> void:
	get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if (false) else Window.MODE_WINDOWED
	get_window().borderless = false
	get_window().size = WINDOWED_SIZE
	get_window().position = WINDOWED_POSITION


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F11:
		get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if (not ((get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN) or (get_window().mode == Window.MODE_FULLSCREEN))) else Window.MODE_WINDOWED
		get_viewport().set_input_as_handled()
