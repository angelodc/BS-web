# Camada dos pins X do cenário ativo.
#
# Cada cenário de negação que entra em cena cria um pin vermelho automático; o
# hover mostra o nome do cenário que o criou. As duas fontes à esquerda do texto
# "Cena: Personagens e Suportes" criam pins manuais arrastando para a mesa: a
# vermelha fica sem texto de hover, a verde recebe o nome da carta em que é
# solta. Esse nome é escolhido uma vez e não muda mais: tirar o pin da carta, pôr
# num vão ou prendê-lo em outro personagem mantém o texto. O botão direito copia
# qualquer pin (cor e texto) para o encaixe livre mais próximo. A lixeira ao
# lado apaga: clique limpa todos, arrastar um pin até ela apaga só aquele. O
# estado dos pins vai para o outro jogador, que os desenha como cópias remotas
# no tabuleiro.
#
# O encaixe usa três famílias de posições: a quina superior direita e a base de
# cada carta da cena, e cada vão entre colunas de cartas tem seis posições
# empilhadas. O pin preso a uma carta acompanha posição e rotação dela a cada
# quadro, então gira junto quando o tabuleiro espelha ou a troca de assento no
# hotseat reconstrói a mesa.
#
# A camada fica acima das cartas, inclusive da carta levantada pelo hover e da
# que está sendo arrastada (z 99), e abaixo do HUD (z 110). O Godot escolhe o
# Control do clique pela ordem da árvore, então a camada também precisa ser a
# última filha do tabuleiro: o tabuleiro a recoloca no fim a cada carta nova e
# a cada reordenação das filhas.
extends Control

const PinScript = preload("res://src/custom/NegationPin.gd")
const Catalog = preload("res://src/custom/cards/ScenarioCatalog.gd")

const PIN_SIZE := PinScript.SIZE
const TOOL_GAP := 8.0
const HINT_WIDTH := 260.0
const HINT_MARGIN := 10.0
const SNAP_EPSILON := 10.0
const TRASH_GRAB := 8.0
# Posições empilhadas no vão entre duas colunas de cartas.
const GAP_STACK := 6
# Acima de tudo que o tabuleiro desenha (a carta arrastada vai a z 99).
const LAYER_Z := 105

var _board: Control
var _grid: Control
var _source: Control
var _green_source: Control
var _trash: Control
var _hint: Label
var _pins: Array = []
# Cópias dos pins do outro jogador; são refeitas a cada estado recebido.
var _remote_pins: Array = []
var _tools_placed_at := Vector2.INF
# Pins automáticos repetem a cada snapshot remoto; a chave evita duplicar.
var _pin_keys: Dictionary = {}
var _drag_pin: Control = null
var _hint_pin = null
var _source_home := Vector2.ZERO
var _green_home := Vector2.ZERO
# Assento visto no quadro anterior, para espelhar os pins soltos na troca P1↔P2.
var _seat_seen := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = LAYER_Z
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board = get_parent()
	_grid = _board.get_node_or_null("PlacementGridDemo")
	if not _grid:
		# Bare test boards carry a plain grid instead of the authored scene.
		for candidate in get_tree().get_nodes_in_group("placement_grid"):
			if _board.is_ancestor_of(candidate):
				_grid = candidate
				break
	_source = _make_tool(PinScript.Kind.SOURCE, PinScript.Tone.RED, "Source",
			"Arraste para a cena para criar um pin X.")
	_green_source = _make_tool(PinScript.Kind.SOURCE, PinScript.Tone.GREEN,
			"GreenSource", "Arraste para uma carta: o pin mostra o nome dela.")
	_trash = _make_tool(PinScript.Kind.TRASH, PinScript.Tone.RED, "Trash",
			"Clique para apagar todos os pins. Arraste um pin até aqui "
			+ "para apagar só ele.")
	call_deferred("place_tools")
	get_viewport().size_changed.connect(place_tools)


func _make_tool(kind : int, tone : int, tool_name : String,
		description : String) -> Control:
	var tool: Control = PinScript.new()
	tool.name = tool_name
	tool.kind = kind
	tool.tone = tone
	tool.description = description
	add_child(tool)
	tool.drag_started.connect(_on_drag_started)
	tool.drag_moved.connect(_on_drag_moved)
	tool.drag_finished.connect(_on_drag_finished)
	tool.clicked.connect(_on_clicked)
	tool.hover_changed.connect(_on_hover_changed)
	return tool


# Os três ícones ficam juntos na área de Recursos, na linha do contador e à
# direita dele: [0] [verde] [vermelha] [lixeira]. Sem a pilha (tabuleiro enxuto
# dos testes) eles voltam para a esquerda da legenda do grid.
func place_tools() -> void:
	if not is_instance_valid(_source) or not is_instance_valid(_green_source) \
			or not is_instance_valid(_trash):
		return
	var origin := _tool_row_origin()
	_tools_placed_at = origin
	_green_source.position = origin
	_source.position = origin + Vector2(PIN_SIZE + TOOL_GAP, 0.0)
	_trash.position = origin + Vector2((PIN_SIZE + TOOL_GAP) * 2.0, 0.0)
	_green_home = _green_source.position
	_source_home = _source.position


func _tool_row_origin() -> Vector2:
	var panel := _discard_panel()
	var badge := _discard_badge()
	if panel and badge:
		var panel_rect: Rect2 = panel.get_global_rect()
		if panel_rect.size.x >= 80.0:
			var badge_rect: Rect2 = badge.get_global_rect()
			var row_width := PIN_SIZE * 3.0 + TOOL_GAP * 2.0
			var x: float = min(badge_rect.end.x + TOOL_GAP,
					panel_rect.end.x - 4.0 - row_width)
			x = max(x, panel_rect.position.x + 4.0)
			var y := badge_rect.get_center().y - PIN_SIZE * 0.5
			return Vector2(x, y) - global_position
	var reference := Rect2()
	if is_instance_valid(_grid):
		reference = _grid.get_global_rect()
		var label: Control = _grid.get_node_or_null("Control/Label")
		if label:
			reference = label.get_global_rect()
	var local := reference.position - global_position
	return Vector2(local.x - TOOL_GAP * 3.0 - PIN_SIZE * 3.0,
			local.y + reference.size.y * 0.5 - PIN_SIZE * 0.5)


func _discard_panel() -> Control:
	if not is_instance_valid(_board):
		return null
	var discard = _board.get_node_or_null("Discard")
	var panel = discard.get_node_or_null("Control") if discard else null
	return panel if panel is Control else null


func _discard_badge() -> Control:
	if not is_instance_valid(_board):
		return null
	var discard = _board.get_node_or_null("Discard")
	var badge = discard.get_node_or_null(
			"Control/CenterContainer/VBoxContainer/PanelContainer") \
			if discard else null
	return badge if badge is Control else null


# -----------------------------------------------------------------------------
# Pins
# -----------------------------------------------------------------------------

# Chamado pela automação quando um cenário de negação entra em cena, e pelo
# MultiplayerSync no cliente que recebe o espelho. `key` identifica o cenário
# remoto para o snapshot repetido não empilhar o mesmo pin.
func add_negation_pin(card, key := "") -> void:
	if not is_instance_valid(card):
		return
	var entry := Catalog.entry_for(card)
	if not bool(entry.get("negation", false)):
		return
	if not key.is_empty() and _pin_keys.has(key):
		return
	var pin := _create_pin(Catalog.display_name(card, entry))
	_place_pin(pin, _nearest_free_anchor(_card_center(card)))
	if not key.is_empty():
		_pin_keys[key] = pin
	_notify_changed()


func pin_count() -> int:
	return _pins.size()


# Clique na lixeira: apaga os pins deste jogador, automáticos e manuais. As
# cópias dos pins do outro jogador saem quando o dono os apaga.
func clear_pins() -> void:
	for pin in _pins.duplicate():
		if is_instance_valid(pin) and not pin.remote:
			_remove_pin(pin)
	_notify_changed()


func _create_pin(description : String,
		tone := PinScript.Tone.RED, remote := false) -> Control:
	var pin: Control = PinScript.new()
	pin.kind = PinScript.Kind.PIN
	pin.tone = tone
	pin.description = description
	pin.remote = remote
	if not remote:
		pin.owner_slot = Multiplayer.my_slot
	add_child(pin)
	if not remote:
		pin.drag_started.connect(_on_drag_started)
		pin.drag_moved.connect(_on_drag_moved)
		pin.drag_finished.connect(_on_drag_finished)
		pin.clicked.connect(_on_clicked)
		pin.right_clicked.connect(_on_right_clicked)
		pin.hover_changed.connect(_on_hover_changed)
	_pins.append(pin)
	return pin


func _remove_pin(pin) -> void:
	if not is_instance_valid(pin):
		return
	_pins.erase(pin)
	for key in _pin_keys.keys():
		if _pin_keys[key] == pin:
			_pin_keys.erase(key)
	if _hint_pin == pin:
		_hide_hint()
	pin.queue_free()


# -----------------------------------------------------------------------------
# Arrasto
# -----------------------------------------------------------------------------

func _on_drag_started(pin) -> void:
	_drag_pin = pin
	pin.z_index = 10
	# Em cima da mesa o pin segue a rotação da carta; durante o arrasto ele fica
	# em pé para o X continuar legível.
	pin.rotation = 0.0
	_hide_hint()
	_set_accepting(false)


func _on_drag_moved(_pin) -> void:
	_set_accepting(_over_trash())


func _on_drag_finished(pin) -> void:
	_release_pin(pin, get_global_mouse_position())


# O ponto do solto decide onde o pin fica; separado do sinal para o mesmo
# caminho valer num ponto que não é o do ponteiro.
func _release_pin(pin, pointer : Vector2) -> void:
	_set_accepting(false)
	pin.z_index = 1
	pin.rotation = 0.0
	# O pin deixa de ser o arrastado antes de voltar ao encaixe: `_follow` não
	# posiciona o próprio pin que está na mão.
	_drag_pin = null
	if pin == _source or pin == _green_source:
		_create_from_source(pin, pointer)
	elif _over_trash(pointer):
		_remove_pin(pin)
	else:
		var card = _card_at(pointer)
		if pin.tone == PinScript.Tone.GREEN and is_instance_valid(card):
			_attach(pin, card, _edge_near(card, pointer))
			_follow(pin)
		elif _grid_rect().has_point(pointer):
			_place_pin(pin, _nearest_anchor(pointer))
		elif not _follow(pin):
			pin.position = pin.origin
	_notify_changed()


# A fonte devolve-se ao canto e deixa um pin novo na cena. A verde também aceita
# soltar em qualquer carta do tabuleiro, fora do grid inclusive.
func _create_from_source(source, pointer : Vector2) -> void:
	if not _over_trash():
		var card = _card_at(pointer) if source.tone == PinScript.Tone.GREEN \
				else null
		if is_instance_valid(card):
			var attached := _create_pin("", source.tone)
			_attach(attached, card, _edge_near(card, pointer))
			_follow(attached)
		elif _grid_rect().has_point(pointer):
			var created := _create_pin("", source.tone)
			_place_pin(created, _nearest_free_anchor(pointer))
	source.position = _green_home if source == _green_source else _source_home


func _on_clicked(pin) -> void:
	if pin == _trash:
		clear_pins()


# O botão direito copia o pin: mesma cor e mesmo texto de hover, num encaixe
# livre perto dele. A cópia mantém o nome do original mesmo quando o encaixe
# cai na borda de outra carta.
func _on_right_clicked(pin) -> void:
	if _drag_pin != null or not is_instance_valid(pin) or pin.remote:
		return
	if not _pins.has(pin):
		return
	var name: String = pin.description
	var copy := _create_pin(name, pin.tone)
	_place_pin(copy, _nearest_free_anchor(_pin_center(pin)))
	copy.description = name
	_notify_changed()


func _over_trash(pointer := get_global_mouse_position()) -> bool:
	if not is_instance_valid(_trash):
		return false
	return _trash.get_global_rect().grow(TRASH_GRAB).has_point(pointer)


func _set_accepting(value : bool) -> void:
	if is_instance_valid(_trash):
		_trash.set_accepting(value)


# -----------------------------------------------------------------------------
# Encaixes
# -----------------------------------------------------------------------------

func _grid_rect() -> Rect2:
	if not is_instance_valid(_grid):
		return Rect2()
	return _grid.get_global_rect()


func _card_control(card) -> Control:
	if not is_instance_valid(card) or not card.is_inside_tree():
		return null
	var control = card.get_node_or_null("Control")
	return control if control is Control else null


func _card_center(card) -> Vector2:
	var control := _card_control(card)
	if control:
		return control.get_global_transform() * (control.size * 0.5)
	return _grid_rect().get_center()


# Centro do pin no encaixe da carta, em coordenadas de tela. O pin tem tamanho
# fixo, então o recuo da quina é dividido pela escala da carta para continuar
# com 27 px na tela; a transformação leva a rotação da carta (espelho) junto.
func _edge_anchor(card, edge : String) -> Vector2:
	var control := _card_control(card)
	if not control:
		return _grid_rect().get_center()
	var transform := control.get_global_transform()
	var scale_x := maxf(absf(transform.get_scale().x), 0.001)
	var inset := PIN_SIZE * 0.5 / scale_x
	var local := Vector2(control.size.x * 0.5, control.size.y)
	if edge == "top":
		local = Vector2(control.size.x - inset, inset)
	return transform * local


# Cada encaixe é um dicionário com o ponto global e, quando fica no centro do
# topo ou da base de uma carta, a carta e a borda que o pin deve acompanhar.
func _anchors() -> Array:
	var anchors := []
	if not is_instance_valid(_grid) or not _grid.has_method("get_all_slots"):
		return anchors
	var slots := []
	for slot in _grid.get_all_slots():
		if slot is Control:
			slots.append(slot)
	if slots.is_empty():
		return anchors
	var rects := []
	for slot in slots:
		rects.append(slot.get_global_rect())
	for slot in slots:
		var card = slot.occupying_card
		if not is_instance_valid(card):
			continue
		# O pin de cima fica na quina superior direita, longe do nome e da
		# barra de energia impressos no topo da carta.
		anchors.append({"point": _edge_anchor(card, "top"),
				"card": card, "edge": "top"})
		anchors.append({"point": _edge_anchor(card, "bottom"),
				"card": card, "edge": "bottom"})
	# Colunas pela posição x e fileiras de cada vão: seis alturas iguais entre o
	# topo da primeira fileira e a base da última.
	var columns := {}
	var top := INF
	var bottom := -INF
	for rect in rects:
		columns[int(round(rect.position.x))] = rect
		top = min(top, rect.position.y)
		bottom = max(bottom, rect.end.y)
	var keys := columns.keys()
	keys.sort()
	var span := bottom - top
	if span > 0.0 and keys.size() > 1:
		for index in range(keys.size() - 1):
			var left: Rect2 = columns[keys[index]]
			var right: Rect2 = columns[keys[index + 1]]
			var x := (left.end.x + right.position.x) * 0.5
			for row in range(GAP_STACK):
				anchors.append({
					"point": Vector2(
							x, top + span * (float(row) + 0.5) / float(GAP_STACK)),
					"card": null,
					"edge": "",
				})
	return anchors


func _nearest_anchor(point : Vector2) -> Dictionary:
	var best := {}
	var best_distance := INF
	for anchor in _anchors():
		var distance: float = point.distance_squared_to(anchor["point"])
		if distance < best_distance:
			best_distance = distance
			best = anchor
	if best.is_empty():
		return {"point": _grid_rect().get_center(), "card": null, "edge": ""}
	return best


func _nearest_free_anchor(point : Vector2) -> Dictionary:
	var best := {}
	var best_distance := INF
	for anchor in _anchors():
		if _anchor_taken(anchor["point"]):
			continue
		var distance: float = point.distance_squared_to(anchor["point"])
		if distance < best_distance:
			best_distance = distance
			best = anchor
	if best.is_empty():
		return _nearest_anchor(point)
	return best


func _anchor_taken(anchor : Vector2) -> bool:
	for pin in _pins:
		if not is_instance_valid(pin):
			continue
		if _pin_center(pin).distance_to(anchor) < SNAP_EPSILON:
			return true
	return false


# O centro visual do pin: `get_global_rect` não acompanha a rotação em torno do
# pivô, e o pin preso a uma carta espelhada fica girado.
func _pin_center(pin) -> Vector2:
	return pin.get_global_transform() * (pin.size * 0.5)


# Prende o pin ao encaixe. Fora das cartas o ponto é fixo; nos centros de carta
# o pin passa a acompanhar a carta por `_follow`. O ponto do vão fica guardado
# na visão do assento dono, então a troca P1↔P2 só o espelha.
func _place_pin(pin, anchor : Dictionary) -> void:
	var card = anchor.get("card", null)
	if is_instance_valid(card):
		_attach(pin, card, str(anchor.get("edge", "top")))
		_follow(pin)
		return
	_detach(pin)
	pin.rotation = 0.0
	pin.anchor_point = _owner_point(pin, anchor["point"])
	pin.position = _loose_position(pin)


# O ponto chega na visão do assento que está na mesa; o pin do outro assento
# guarda o ponto espelhado de volta para a visão do dono.
func _owner_point(pin, point : Vector2) -> Vector2:
	if pin.owner_slot == 0 or pin.owner_slot == Multiplayer.my_slot:
		return point
	return _mirror_point(point)


func _loose_position(pin) -> Vector2:
	return _local_of(_owner_point(pin, pin.anchor_point)) \
			- Vector2(PIN_SIZE, PIN_SIZE) * 0.5


func _mirror_point(point : Vector2) -> Vector2:
	if not is_instance_valid(_board):
		return point
	var sync = _board.get_node_or_null("MultiplayerSync")
	if sync and sync.has_method("mirror_rect"):
		return sync.mirror_rect(Rect2(point, Vector2.ZERO)).position
	# Bare test boards have no sync node; the reflection is the same one it uses:
	# the board centre in x and the bottom of the opponent band in y.
	var axis_x: float = _board.global_position.x + _board.size.x * 0.5
	var split_y: float = _board.global_position.y + _board.size.y * 0.5
	var visual: Control = _board.get_node_or_null("OpponentFieldVisual")
	if visual and visual.size.y > 0.0:
		split_y = visual.global_position.y + visual.size.y
	return Vector2(axis_x * 2.0 - point.x, split_y * 2.0 - point.y)


func _attach(pin, card, edge : String) -> void:
	pin.attached_card = card
	pin.attach_edge = edge
	pin.attached_net_id = str(card.network_id)
	# O nome é escolhido na primeira carta em que o pin verde é solto e não muda
	# mais: mover o pin de um personagem para outro não troca o nome dele.
	if pin.tone == PinScript.Tone.GREEN and pin.description.is_empty():
		pin.description = Catalog.display_name(card)


# Soltar num vão só solta o pin da carta: o texto de hover é a identidade do
# pin (o que ele nega), então continua lá fora e também quando ele passa para
# outro personagem.
func _detach(pin) -> void:
	pin.attached_card = null
	pin.attach_edge = ""
	pin.attached_net_id = ""


# Coloca o pin no centro da borda da carta e copia a rotação do Control
# desenhado. A carta espelhada fica a 180° e o pin vira junto com ela.
func _follow(pin) -> bool:
	if pin == _drag_pin or pin.attach_edge.is_empty():
		return false
	var card = pin.attached_card
	if not is_instance_valid(card) or not card.is_inside_tree():
		card = _find_card(pin.attached_net_id)
		if not is_instance_valid(card):
			return false
		pin.attached_card = card
		pin.attached_net_id = str(card.network_id)
	var control := _card_control(card)
	if not control:
		return false
	var edge_point := _edge_anchor(card, pin.attach_edge)
	var transform := control.get_global_transform()
	var layer_transform := get_global_transform()
	pin.position = layer_transform.affine_inverse() * edge_point \
			- Vector2(PIN_SIZE, PIN_SIZE) * 0.5
	pin.pivot_offset = Vector2(PIN_SIZE, PIN_SIZE) * 0.5
	pin.rotation = transform.get_rotation() - layer_transform.get_rotation()
	return true


# Cartas na mesa: campo local e banda espelhada. A mão e as pilhas ficam de
# fora, e os espelhos saem do grupo "cards", então a varredura é pela árvore do
# tabuleiro.
func _board_cards() -> Array:
	var cards := []
	for candidate in _board.find_children("*", "Card", true, false):
		if not (candidate is Card) or not candidate.is_inside_tree():
			continue
		if candidate.get_parent() == _board:
			cards.append(candidate)
	return cards


func _find_card(net_id : String):
	if net_id.is_empty():
		return null
	var fallback = null
	for candidate in _board_cards():
		if str(candidate.network_id) != net_id:
			continue
		if not candidate.network_mirror:
			return candidate
		if fallback == null:
			fallback = candidate
	return fallback


# O retângulo de um Control não acompanha a rotação, e as cartas da banda do
# adversário ficam a 180°; o ponteiro é convertido para o espaço da carta para o
# encaixe funcionar também nelas. Numa pilha mais de uma caixa contém o ponto, e
# o pin fica com a carta que o jogador vê ali: a desenhada por cima. A beirada
# exposta de uma carta de baixo continua valendo para ela.
func _card_at(pointer : Vector2):
	var best = null
	var best_z := 0
	var best_index := -1
	for candidate in _board_cards():
		var control := _card_control(candidate)
		if not control:
			continue
		var local: Vector2 = control.get_global_transform().affine_inverse() * pointer
		if not Rect2(Vector2.ZERO, control.size).has_point(local):
			continue
		var index: int = candidate.get_index()
		var better := false
		if best == null:
			better = true
		elif candidate.z_index != best_z:
			better = candidate.z_index > best_z
		else:
			better = index > best_index
		if better:
			best = candidate
			best_z = candidate.z_index
			best_index = index
	return best


func _edge_near(card, pointer : Vector2) -> String:
	var control := _card_control(card)
	if not control:
		return "top"
	var center: Vector2 = control.get_global_transform() * (control.size * 0.5)
	return "top" if pointer.y < center.y else "bottom"


func _local_of(point : Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * point


func _process(_delta : float) -> void:
	var seat := Multiplayer.my_slot
	if _seat_seen == -1:
		_seat_seen = seat
	elif seat != _seat_seen:
		# A troca P1↔P2 espelha o lado do outro assento: os pins soltos dele
		# mudam de lado junto com as cartas da banda.
		_seat_seen = seat
		for pin in _pins:
			if is_instance_valid(pin) and pin.attach_edge.is_empty() \
					and pin.owner_slot != 0:
				pin.position = _loose_position(pin)
	for pin in _pins:
		if is_instance_valid(pin):
			_follow(pin)
	# A pilha de Recursos se reorganiza depois do primeiro quadro; a linha dos
	# ícones acompanha o contador quando ele muda de lugar.
	if is_instance_valid(_source) and _tool_row_origin() != _tools_placed_at:
		place_tools()


# Um clique sobre um pin não pode chegar à carta de baixo: o tabuleiro consulta
# isto antes de deixar a carta assumir o hover ou começar o arrasto.
func pointer_over_pin() -> bool:
	if _drag_pin != null:
		return true
	var pointer := get_global_mouse_position()
	for pin in _pins:
		if is_instance_valid(pin) and _pin_has_point(pin, pointer):
			return true
	for tool in [_source, _green_source, _trash]:
		if is_instance_valid(tool) and tool.get_global_rect().has_point(pointer):
			return true
	return false


func _pin_has_point(pin, point : Vector2) -> bool:
	var local: Vector2 = pin.get_global_transform().affine_inverse() * point
	return Rect2(Vector2.ZERO, pin.size).has_point(local)


# -----------------------------------------------------------------------------
# Espelho dos pins no outro cliente
# -----------------------------------------------------------------------------

# Lista dos pins deste jogador. O outro lado refaz a própria cópia a cada
# estado recebido; as cópias remotas não voltam para o relay.
func local_pin_state() -> Array:
	var entries := []
	for pin in _pins:
		if not is_instance_valid(pin) or pin.remote:
			continue
		# O pin solto viaja na visão do dono; o outro lado espelha ao desenhar.
		var point: Vector2 = _pin_center(pin)
		if pin.attach_edge.is_empty():
			point = pin.anchor_point
		entries.append({
			"tone": int(pin.tone),
			"name": pin.description,
			"net": pin.attached_net_id,
			"edge": pin.attach_edge,
			"x": point.x,
			"y": point.y,
		})
	return entries


func apply_remote_pins(entries) -> void:
	if not (entries is Array):
		return
	for pin in _remote_pins.duplicate():
		_pins.erase(pin)
		if is_instance_valid(pin):
			pin.queue_free()
	_remote_pins.clear()
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sent_name := str(entry.get("name", ""))
		var pin := _create_pin(sent_name,
				int(entry.get("tone", PinScript.Tone.RED)), true)
		_remote_pins.append(pin)
		var net := str(entry.get("net", ""))
		if not net.is_empty():
			var card = _find_card(net)
			if is_instance_valid(card):
				_attach(pin, card, str(entry.get("edge", "top")))
				# O nome é do pin, já escolhido pelo dono: uma cópia sem nome
				# continua sem nome e a com nome não herda o nome que a carta
				# tem deste lado.
				pin.description = sent_name
				_follow(pin)
				continue
		# O campo do outro jogador é a banda espelhada deste lado: o ponto do
		# pin passa pela mesma reflexão das cartas espelhadas.
		var point := Vector2(float(entry.get("x", 0.0)),
				float(entry.get("y", 0.0)))
		pin.anchor_point = point
		point = _mirror_point(point)
		pin.position = _local_of(point) - Vector2(PIN_SIZE, PIN_SIZE) * 0.5


func _notify_changed() -> void:
	var sync = _board.get_node_or_null("MultiplayerSync") \
			if is_instance_valid(_board) else null
	if sync and sync.has_method("send_pins_state"):
		sync.send_pins_state(local_pin_state())


# -----------------------------------------------------------------------------
# Balão de hover
# -----------------------------------------------------------------------------

func _on_hover_changed(pin, hovered : bool) -> void:
	if _drag_pin != null:
		return
	if hovered:
		# A carta sob o pin não pode continuar com o hover: ela subiria sobre o
		# pin e o preview cobriria justamente o que o jogador quer arrastar.
		_release_card_under_pointer()
		if not pin.description.is_empty():
			_show_hint(pin, pin.description)
			return
	if _hint_pin == pin:
		_hide_hint()


func _release_card_under_pointer() -> void:
	var main = cfc.NMAP.get("main", null)
	if is_instance_valid(main) and main.has_method("unfocus_all"):
		main.unfocus_all()


func _show_hint(pin, text : String) -> void:
	if not is_instance_valid(_hint):
		_build_hint()
	_hint.size = Vector2(HINT_WIDTH, 0)
	_hint.text = text
	var needed := _hint.get_minimum_size()
	_hint.size = Vector2(HINT_WIDTH, max(needed.y, 26.0))
	var center := _local_of(_pin_center(pin))
	var position := center + Vector2(
			-HINT_WIDTH - HINT_MARGIN,
			-_hint.size.y * 0.5)
	if position.x < 4.0:
		position.x = center.x + PIN_SIZE * 0.5 + HINT_MARGIN
	_hint.position = position
	_hint.show()
	_hint_pin = pin


func _hide_hint() -> void:
	_hint_pin = null
	if is_instance_valid(_hint):
		_hint.hide()


# Mesmo formato do balão do botão de bug: Label com fundo arredondado, porque
# o tooltip nativo do Godot pode ser cortado pela borda do SubViewport.
func _build_hint() -> void:
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
	_hint.z_index = 20
	add_child(_hint)
