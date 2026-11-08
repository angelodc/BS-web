extends Control

# Ícone redondo de bug na borda direita, centralizado na vertical. O HUD usa as
# coordenadas autorais 1280x720 do tabuleiro, então o botão fica em espaço de
# tela sem depender da densidade de render do SubViewport.
#
# Arrastar uma carta e soltá-la aqui é interceptado antes da regra do jogo
# (CGFCardTemplate.common_pre_drop_scripts), que anexa a carta ao relato sem
# jogá-la. Hover e clique abrem o mesmo diálogo, com a carta quando houver.

const DialogScript = preload("res://src/custom/FeedbackDialog.gd")

const SIZE := 54.0
const EDGE_MARGIN := 12.0

const HINT_SIZE := Vector2(292, 96)

var _dialog: Window = null
var _toast: Label = null
var _hint: Label = null
var _hovered := false
var _drag_hover := false


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -SIZE - EDGE_MARGIN
	offset_right = -EDGE_MARGIN
	offset_top = -SIZE * 0.5
	offset_bottom = SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	Feedback.set_target(self)


func _exit_tree() -> void:
	Feedback.clear_target(self)


func _process(_delta: float) -> void:
	var dragging: bool = cfc.card_drag_ongoing is Card \
			and cfc.card_drag_ongoing.state == Card.CardState.DRAGGED
	var over := dragging and Feedback.is_pointer_over_target()
	if over != _drag_hover:
		_drag_hover = over
		queue_redraw()


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()
	_show_hint()


func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()
	if is_instance_valid(_hint):
		_hint.hide()


# A descrição aparece ao passar o mouse, desenhada na mesma tela do tabuleiro:
# o tooltip nativo do Godot pode ser cortado pela borda do SubViewport.
func _show_hint() -> void:
	if not is_instance_valid(_hint):
		_hint = Label.new()
		_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_hint.add_theme_font_size_override("font_size", 13)
		_hint.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.07, 0.09, 0.13, 0.94)
		box.border_color = Color(0.55, 0.7, 0.95, 0.8)
		box.set_border_width_all(1)
		box.set_corner_radius_all(6)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		_hint.add_theme_stylebox_override("normal", box)
		add_child(_hint)
	_hint.text = "Relatar bug ou sugerir melhoria.\nClique para abrir o " \
			+ "formulário ou arraste uma carta\npara anexá-la. A gravação da " \
			+ "partida vai junto."
	_hint.size = HINT_SIZE
	_hint.position = Vector2(-HINT_SIZE.x - EDGE_MARGIN,
			SIZE * 0.5 - HINT_SIZE.y * 0.5)
	_hint.z_index = 5
	_hint.show()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed() \
			and event.get_button_index() == MOUSE_BUTTON_LEFT:
		_open_without_card()
		accept_event()


func open_with_attached_card() -> void:
	_open(true)


func _open_without_card() -> void:
	_open(false)


func _open(keep_attached: bool) -> void:
	if not keep_attached:
		Feedback.clear_attached_card()
	if is_instance_valid(_hint):
		_hint.hide()
	if not is_instance_valid(_dialog):
		_dialog = DialogScript.new()
		add_child(_dialog)
		_dialog.saved.connect(_show_toast)
	_dialog.open()


func _show_toast(message: String) -> void:
	if message.strip_edges().is_empty():
		return
	if not is_instance_valid(_toast):
		_toast = Label.new()
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_toast.z_index = 5
		add_child(_toast)
	_toast.text = message
	_toast.size = Vector2(320, 24)
	_toast.position = Vector2(-320 + SIZE, SIZE + 8)
	_toast.show()
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(_toast):
		_toast.hide()


func _draw() -> void:
	var center := Vector2(SIZE, SIZE) * 0.5
	var radius := SIZE * 0.5 - 2.0
	var background := Color(0.10, 0.12, 0.16, 0.9)
	var border := Color(0.55, 0.7, 0.95, 0.9)
	var glyph := Color(0.90, 0.93, 1.0)
	if _drag_hover:
		background = Color(0.32, 0.12, 0.10, 0.95)
		border = Color(1.0, 0.62, 0.35)
		glyph = Color(1.0, 0.88, 0.72)
	elif _hovered:
		background = Color(0.16, 0.20, 0.28, 0.95)
		border = Color(0.80, 0.88, 1.0)
	draw_circle(center, radius, background)
	draw_arc(center, radius, 0.0, TAU, 48, border, 2.0, true)
	if _drag_hover:
		draw_arc(center, radius + 3.5, 0.0, TAU, 48, Color(1.0, 0.6, 0.3, 0.65),
				2.0, true)
	_draw_bug(center + Vector2(0, 1), glyph)


func _draw_bug(center: Vector2, color: Color) -> void:
	# Corpo, cabeça e três pares de pernas. Formas simples mantêm o ícone
	# legível sem depender de fonte de emoji no build web.
	draw_circle(center + Vector2(0, 3), 7.5, color)
	draw_circle(center + Vector2(0, -6), 4.2, color)
	draw_line(center + Vector2(0, -10), center + Vector2(-3, -14), color, 1.6)
	draw_line(center + Vector2(0, -10), center + Vector2(3, -14), color, 1.6)
	for index in range(3):
		var y := center.y - 2.0 + index * 4.0
		draw_line(Vector2(center.x - 5.0, y),
				Vector2(center.x - 12.0, y - 3.0 + index * 2.0),
				color, 1.6)
		draw_line(Vector2(center.x + 5.0, y),
				Vector2(center.x + 12.0, y - 3.0 + index * 2.0),
				color, 1.6)
	draw_line(center + Vector2(0, -2), center + Vector2(0, 8), color, 1.2)
