# Botão redondo dos pins de negação: o pin colocado na mesa, a fonte que o
# arrasta e a lixeira que o apaga. O desenho segue o botão de bug do HUD com
# metade do tamanho (27 px) e um X no lugar do inseto; a lixeira usa o mesmo
# corpo com o glifo de lata. O pin criado à mão fica sem texto de hover:
# `description` vazio não abre balão. O pin verde é igual ao vermelho, só muda a
# cor; preso a uma carta ele recebe o nome dela como texto de hover na primeira
# carta em que é solto, e o texto continua no pin quando ele passa para outra
# carta ou para um vão. O botão direito pede uma cópia dele.
extends Control

signal drag_started(pin)
signal drag_moved(pin)
signal drag_finished(pin)
signal clicked(pin)
signal right_clicked(pin)
signal hover_changed(pin, hovered)

enum Kind { PIN, SOURCE, TRASH }
enum Tone { RED, GREEN }

const SIZE := 27.0
const DRAG_THRESHOLD := 5.0

var kind := Kind.PIN
var tone := Tone.RED
var description := ""
# Pin copiado do outro jogador: só aparece, não recebe clique nem arrasto.
var remote := false
# Posição antes do arrasto, para devolver o pin quando o solto cai fora da cena.
var origin := Vector2.ZERO
# Pin no centro do topo ou da base de uma carta: `attach_edge` guarda a borda
# ("top"/"bottom"), `attached_card` a carta viva e `attached_net_id` permite
# reencontrá-la depois que o tabuleiro é reconstruído (troca P1↔P2 no hotseat).
var attached_card = null
var attach_edge := ""
var attached_net_id := ""
# Assento dono do pin. Um pin solto guarda o ponto na visão do dono e só é
# espelhado quando o outro assento assume a mesa; preso a uma carta ele já segue
# a carta e a rotação dela.
var owner_slot := 0
var anchor_point := Vector2.ZERO

var _hovered := false
var _pressed := false
var _dragging := false
var _press_point := Vector2.ZERO
var _press_offset := Vector2.ZERO
var _accepting := false


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	pivot_offset = Vector2(SIZE, SIZE) * 0.5
	if remote:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# A lixeira avisa enquanto um pin é arrastado sobre ela.
func set_accepting(value : bool) -> void:
	if value == _accepting:
		return
	_accepting = value
	queue_redraw()


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()
	hover_changed.emit(self, true)


func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()
	hover_changed.emit(self, false)


func _gui_input(event : InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _pressed and kind != Kind.TRASH:
			_handle_motion()
			accept_event()
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		# Botão direito num pin da mesa pede uma cópia no encaixe livre mais
		# próximo. Não vale para as fontes nem para a lixeira.
		if event.pressed and kind == Kind.PIN and not remote:
			right_clicked.emit(self)
			accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_pressed = true
		_dragging = false
		origin = position
		_press_point = get_global_mouse_position()
		_press_offset = _press_point - global_position
		accept_event()
		return
	if not _pressed:
		return
	_pressed = false
	if _dragging:
		_dragging = false
		drag_finished.emit(self)
	else:
		clicked.emit(self)
	accept_event()


func _handle_motion() -> void:
	var pointer := get_global_mouse_position()
	if not _dragging:
		if pointer.distance_to(_press_point) < DRAG_THRESHOLD:
			return
		_dragging = true
		drag_started.emit(self)
	global_position = pointer - _press_offset
	drag_moved.emit(self)


func _draw() -> void:
	var center := Vector2(SIZE, SIZE) * 0.5
	var radius := SIZE * 0.5 - 1.5
	if kind == Kind.TRASH:
		_draw_trash(center, radius)
		return
	var background := Color(0.16, 0.05, 0.06, 0.94)
	var border := Color(0.95, 0.32, 0.32, 0.95)
	var glyph := Color(1.0, 0.62, 0.55)
	if tone == Tone.GREEN:
		background = Color(0.04, 0.15, 0.07, 0.94)
		border = Color(0.35, 0.9, 0.45, 0.95)
		glyph = Color(0.65, 1.0, 0.7)
	if _hovered:
		if tone == Tone.GREEN:
			background = Color(0.07, 0.24, 0.12, 0.97)
			border = Color(0.55, 1.0, 0.65)
			glyph = Color(0.85, 1.0, 0.88)
		else:
			background = Color(0.28, 0.08, 0.09, 0.97)
			border = Color(1.0, 0.55, 0.5)
			glyph = Color(1.0, 0.78, 0.72)
	draw_circle(center, radius, background)
	draw_arc(center, radius, 0.0, TAU, 32, border, 1.6, true)
	var arm := 5.5
	draw_line(center + Vector2(-arm, -arm), center + Vector2(arm, arm),
			glyph, 2.6, true)
	draw_line(center + Vector2(arm, -arm), center + Vector2(-arm, arm),
			glyph, 2.6, true)


func _draw_trash(center : Vector2, radius : float) -> void:
	var background := Color(0.08, 0.10, 0.14, 0.9)
	var border := Color(0.55, 0.7, 0.95, 0.8)
	var glyph := Color(0.85, 0.9, 1.0)
	if _accepting:
		background = Color(0.32, 0.12, 0.10, 0.95)
		border = Color(1.0, 0.62, 0.35)
		glyph = Color(1.0, 0.88, 0.72)
	elif _hovered:
		background = Color(0.14, 0.18, 0.25, 0.95)
		border = Color(0.80, 0.88, 1.0)
	draw_circle(center, radius, background)
	draw_arc(center, radius, 0.0, TAU, 32, border, 1.6, true)
	draw_line(center + Vector2(-7, -6), center + Vector2(7, -6), glyph, 1.6)
	draw_line(center + Vector2(-2, -8), center + Vector2(2, -8), glyph, 1.6)
	var body := Rect2(center + Vector2(-5, -3), Vector2(10, 10))
	draw_rect(body, glyph, false, 1.6)
	draw_line(center + Vector2(-2, -1), center + Vector2(-2, 5), glyph, 1.2)
	draw_line(center + Vector2(2, -1), center + Vector2(2, 5), glyph, 1.2)
