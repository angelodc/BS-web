extends Node

const RenderResolution = preload("res://src/custom/RenderResolution.gd")
const WINDOWED_ENV := "BS_WINDOWED"
const WINDOWED_SIZE := Vector2i(960, 540)
const WINDOWED_POSITION := Vector2i(220, 140)
# With stretch mode canvas_items the UI keeps its 1280x720 design coordinates
# while rendering at the window's native resolution, so a larger window stays
# sharp. The desktop also picks the board raster density in the menu; the
# window follows it so the table is shown 1:1.
const TITLE_BAR_ALLOWANCE := 30.0


func _ready() -> void:
	if OS.has_feature("web"):
		_fit_web_canvas()
		return
	if OS.get_environment(WINDOWED_ENV) == "1":
		call_deferred("_apply_windowed")
	else:
		_apply_desktop_window()


# O engine arranca com a janela do projeto (1280x720) enquanto o canvas ja tem
# o tamanho do navegador. A escala do conteudo nao acompanha esse ajuste, entao
# a cena fica colada embaixo com faixa preta no topo (e a direita, em janelas
# mais largas que 16:9) ate alguem redimensionar a janela. Mexer 1px no canvas
# obriga o engine a recalcular a escala sem mudar o layout final.
func _fit_web_canvas() -> void:
	_install_web_canvas_fixups()
	await get_tree().process_frame
	await get_tree().process_frame
	_nudge_web_canvas()
	await get_tree().create_timer(1.0).timeout
	_nudge_web_canvas()


# Chrome restores the page from the back/forward cache when it reopens a window.
# No resize reaches the engine on that path, so the canvas keeps the size of the
# old window and the table is cropped in the new one.
func _install_web_canvas_fixups() -> void:
	JavaScriptBridge.eval(
			"(() => { if (window.__bsCanvasFix) return;"
			+ " window.__bsCanvasFix = true;"
			+ " const fit = () => {"
			+ " const c = document.getElementById('canvas');"
			+ " if (!c) return;"
			+ " window.dispatchEvent(new Event('resize'));"
			+ " const h = c.style.height;"
			+ " c.style.height = 'calc(100% - 1px)';"
			+ " void c.offsetHeight;"
			+ " c.style.height = h; };"
			+ " window.addEventListener('pageshow', (event) => {"
			+ " if (!event.persisted) return;"
			+ " setTimeout(fit, 50);"
			+ " setTimeout(fit, 700); });"
			+ " });", true)


func _nudge_web_canvas() -> void:
	JavaScriptBridge.eval(
			"(() => { const c = document.getElementById('canvas');"
			+ " if (!c) return; const h = c.style.height;"
			+ " c.style.height = 'calc(100% - 1px)';"
			+ " void c.offsetHeight; c.style.height = h; })();", true)


# Called by the menu when the board render size changes. The table reads the
# setting when a match starts; here we only match the window to the choice.
func apply_render_choice() -> void:
	if OS.get_environment(WINDOWED_ENV) == "1":
		_apply_windowed()
		return
	_apply_desktop_window()


func _desktop_window_size() -> Vector2i:
	if OS.has_feature("web"):
		return RenderResolution.DESIGN_SIZE
	return RenderResolution.window_size()


func _apply_desktop_window() -> void:
	get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if (false) else Window.MODE_WINDOWED
	var target_size := _desktop_window_size()
	if DisplayServer.get_screen_count() == 0:
		get_window().borderless = true
		get_window().size = target_size
		return
	var screen := _primary_screen()
	var screen_position := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	# A window tall enough to touch the screen edges only fits without a title
	# bar and taskbar, so it takes over the monitor as a borderless window.
	var borderless := target_size.y + TITLE_BAR_ALLOWANCE > screen_size.y
	get_window().borderless = borderless
	var window_size := Vector2i(
			min(target_size.x, screen_size.x),
			min(target_size.y, screen_size.y))
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
