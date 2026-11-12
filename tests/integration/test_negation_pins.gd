extends "res://tests/UTcommon.gd"

# Pins X dos cenários de negação. O tabuleiro é o mesmo `CGFBoard` do jogo, que
# cria a camada `NegationPins`; o grid de cena entra aqui para a automação
# colocar o cenário no mesmo endereço que os botões usam.

const Actions = preload("res://src/core/table/TableActions.gd")
const Catalog = preload("res://src/custom/cards/ScenarioCatalog.gd")
const Pin = preload("res://src/custom/NegationPin.gd")
const SCENARIO_GRID_SCENE = preload("res://src/custom/CGFModifiedLabelGrid.tscn")

const NEGATION_ID := "BSET_056"
const NEGATION_NAME := "Momento de Hesitação"
const SIMPLE_ID := "BSOS_058"

var actions
var layer


func before_each():
	await setup_board()
	layer = board.get_node_or_null("NegationPins")
	assert_not_null(layer)
	var scenario_grid: BoardPlacementGrid = SCENARIO_GRID_SCENE.instantiate()
	scenario_grid.name = "ModifiedLabelGrid"
	board.add_child(scenario_grid)
	scenario_grid.add_slot()
	actions = Actions.new(board, 1)
	GameEvents.set_enabled(true)
	await get_tree().process_frame
	# The resources panel is laid out by the pile's own _process, which is off
	# in the tests; laying it out here gives the tools their real geometry.
	var discard = board.get_node_or_null("Discard")
	if discard and discard.has_method("_layout_panel"):
		discard._layout_panel()
	layer.place_tools()


func after_each():
	GameEvents.set_enabled(false)
	GameEvents.entries.clear()
	Multiplayer.my_slot = 0


func _scenario(bsdb_id: String) -> Card:
	var card: Card = cfc.instance_card("Demo Scenario")
	hand.add_child(card)
	card.properties["_bsdb_id"] = bsdb_id
	card.properties["Name"] = str(Catalog.BY_ID[bsdb_id]["name"])
	return card


# -----------------------------------------------------------------------------
# Fonte e lixeira
# -----------------------------------------------------------------------------

# Os três ícones ficam juntos na área de Recursos, na linha do contador e à
# direita dele: [0] [verde] [vermelha] [lixeira].
func test_the_tools_sit_in_the_resources_area_beside_the_count():
	var discard = board.get_node("Discard")
	var panel: Control = discard.get_node("Control")
	var badge: Control = discard.get_node(
			"Control/CenterContainer/VBoxContainer/PanelContainer")
	var panel_rect: Rect2 = panel.get_global_rect()
	assert_gt(panel_rect.size.x, 80.0, "a área de Recursos tem largura real")
	var badge_rect: Rect2 = badge.get_global_rect()
	for tool in [layer._green_source, layer._source, layer._trash]:
		assert_almost_eq(tool.global_position.y,
				badge_rect.get_center().y - 13.5, 0.5)
		assert_gt(tool.global_position.x, badge_rect.position.x)
		assert_lt(tool.global_position.x + tool.size.x, panel_rect.end.x)
	assert_lt(layer._green_source.global_position.x,
			layer._source.global_position.x)
	assert_lt(layer._source.global_position.x, layer._trash.global_position.x)
	assert_eq(layer._source.size, Vector2(27, 27))
	assert_eq(layer._green_source.size, Vector2(27, 27))


# O pin fica acima das cartas focadas (z 10) para o clique nele não cair na
# carta de baixo, e abaixo do HUD (z 110).
func test_the_pin_layer_draws_above_the_cards():
	assert_gt(layer.z_index, 10)
	assert_lt(layer.z_index, 110)


# O pin tem metade do tamanho do botão de bug do HUD.
func test_the_pin_uses_half_the_bug_button_size():
	layer.add_negation_pin(_scenario(NEGATION_ID))
	var pin: Control = layer._pins[0]
	assert_eq(pin.size, Vector2(27, 27))


func test_the_trash_click_removes_every_pin():
	layer.add_negation_pin(_scenario(NEGATION_ID))
	layer.add_negation_pin(_scenario(SIMPLE_ID))
	layer.add_negation_pin(_scenario(NEGATION_ID))
	assert_eq(layer.pin_count(), 2)
	layer._trash.clicked.emit(layer._trash)
	assert_eq(layer.pin_count(), 0)
	assert_true(layer._pins.is_empty())


# -----------------------------------------------------------------------------
# Pins automáticos
# -----------------------------------------------------------------------------

func test_a_negation_pin_names_the_scenario_that_created_it():
	layer.add_negation_pin(_scenario(NEGATION_ID))
	assert_eq(layer.pin_count(), 1)
	assert_eq(layer._pins[0].description, NEGATION_NAME)


# A fonte só cria um pin quando o arrasto termina dentro da cena; fora dela
# volta para o lugar ao lado da legenda.
func test_dropping_the_source_outside_the_scene_creates_nothing():
	var home: Vector2 = layer._source.position
	layer._on_drag_finished(layer._source)
	assert_eq(layer.pin_count(), 0)
	assert_eq(layer._source.position, home)


func test_the_remote_snapshot_key_does_not_duplicate_the_pin():
	var card := _scenario(NEGATION_ID)
	layer.add_negation_pin(card, "remoto:7")
	layer.add_negation_pin(card, "remoto:7")
	assert_eq(layer.pin_count(), 1)
	# Sem chave, cada entrada em cena marca um pin novo (fica até a lixeira).
	layer.add_negation_pin(card)
	assert_eq(layer.pin_count(), 2)


func test_a_scenario_without_negation_does_not_pin_the_table():
	layer.add_negation_pin(_scenario(SIMPLE_ID))
	assert_eq(layer.pin_count(), 0)


# A automação só roda no cliente que aplicou a intenção; é ela quem chama o
# gancho do tabuleiro na entrada em cena.
func test_playing_a_negation_scenario_adds_the_pin():
	var card := _scenario(NEGATION_ID)
	var result = actions.apply({"op": "jogar", "card": card})
	assert_true(bool(result.get("ok", false)), str(result))
	assert_eq(layer.pin_count(), 1)
	assert_eq(layer._pins[0].description, NEGATION_NAME)


# -----------------------------------------------------------------------------
# Encaixes
# -----------------------------------------------------------------------------

func _occupy_slot(index: int, card: Card):
	var slot = layer._grid.get_slot(index)
	slot.occupying_card = card
	return slot


func test_the_gap_anchors_sit_between_the_slots():
	var anchors: Array = layer._anchors()
	assert_gt(anchors.size(), 0)
	for anchor in anchors:
		if anchor["card"] != null:
			continue
		for slot in layer._grid.get_all_slots():
			assert_false(slot.get_global_rect().has_point(anchor["point"]),
					"o pin do vão não fica em cima de um personagem")


# Cada vão entre colunas recebe seis posições empilhadas, uma embaixo da outra.
func test_each_gap_column_stacks_six_anchors():
	var anchors: Array = layer._anchors()
	var columns := {}
	for anchor in anchors:
		if anchor["card"] != null:
			continue
		var key := int(round(anchor["point"].x))
		columns[key] = int(columns.get(key, 0)) + 1
	assert_gt(columns.size(), 0)
	for key in columns:
		assert_eq(columns[key], layer.GAP_STACK,
				"o vão tem seis alturas encaixáveis")


# Toda carta na cena ganha um encaixe na quina superior direita e outro no
# centro da base.
func test_each_card_anchors_on_the_top_right_and_bottom_centre():
	var card := _scenario(SIMPLE_ID)
	var slot = _occupy_slot(0, card)
	var anchors: Array = layer._anchors()
	var top_right: Vector2 = layer._edge_anchor(card, "top")
	var bottom_centre: Vector2 = layer._edge_anchor(card, "bottom")
	var control: Control = card.get_node("Control")
	var transform := control.get_global_transform()
	var inset: float = 13.5 / maxf(absf(transform.get_scale().x), 0.001)
	assert_almost_eq(top_right.distance_to(
			transform * Vector2(control.size.x - inset, inset)), 0.0, 0.01,
			"o encaixe de cima fica na quina superior direita")
	assert_almost_eq(bottom_centre.distance_to(
			transform * Vector2(control.size.x * 0.5, control.size.y)),
			0.0, 0.01)
	var found := 0
	for anchor in anchors:
		if anchor["card"] != card:
			continue
		found += 1
		var expected: Vector2 = top_right \
				if str(anchor["edge"]) == "top" else bottom_centre
		assert_almost_eq(Vector2(anchor["point"]).distance_to(expected),
				0.0, 0.5)
	assert_eq(found, 2)
	slot.occupying_card = null


func test_the_pin_snaps_to_an_anchor():
	var anchors: Array = layer._anchors()
	var center: Vector2 = layer._grid.get_global_rect().get_center()
	var snapped: Dictionary = layer._nearest_anchor(center)
	var nearest := INF
	for anchor in anchors:
		nearest = min(nearest,
				Vector2(snapped["point"]).distance_to(anchor["point"]))
	assert_lt(nearest, 0.5)


# -----------------------------------------------------------------------------
# Pin verde e vínculo com a carta
# -----------------------------------------------------------------------------

# Soltar um pin verde numa carta prende o pin nela e o hover passa a mostrar o
# nome da carta.
func test_a_green_pin_takes_the_card_name_on_the_top_right():
	var card := _scenario(SIMPLE_ID)
	var slot = _occupy_slot(0, card)
	var pin: Control = layer._create_pin("", Pin.Tone.GREEN)
	layer._attach(pin, card, "top")
	assert_true(layer._follow(pin), "o pin encontra a carta")
	assert_eq(pin.description, str(card.properties["Name"]))
	assert_eq(pin.rotation_degrees, 0.0)
	var top_right: Vector2 = layer._edge_anchor(card, "top")
	assert_almost_eq(_pin_centre(pin).distance_to(top_right), 0.0, 0.5)
	# Sair da carta, num vão do grid, deixa o pin solto mas mantém o nome.
	var gap := {}
	for anchor in layer._anchors():
		if anchor["card"] == null:
			gap = anchor
			break
	var name: String = pin.description
	layer._place_pin(pin, gap)
	assert_eq(pin.description, name, "o nome continua com o pin no vão")
	assert_eq(pin.attached_card, null, "o pin sai da carta")
	slot.occupying_card = null


# O nome do pin verde é escolhido na primeira carta em que ele é solto. Passar
# para outro personagem prende o pin lá, mas não troca o nome.
func test_a_green_pin_keeps_the_first_name_it_took():
	var first := _scenario(SIMPLE_ID)
	var second := _scenario(NEGATION_ID)
	var pin: Control = layer._create_pin("", Pin.Tone.GREEN)
	layer._attach(pin, first, "top")
	var chosen: String = str(first.properties["Name"])
	assert_eq(pin.description, chosen)
	layer._attach(pin, second, "bottom")
	assert_eq(pin.attached_card, second, "o pin passa para a outra carta")
	assert_eq(pin.description, chosen,
			"o nome escolhido na primeira carta não muda de personagem")


# Só o pin ainda sem nome recebe o da carta: o solto num personagem novo leva
# o nome dele.
func test_releasing_a_nameless_green_pin_on_a_card_takes_its_name():
	var first := _on_board(_scenario(SIMPLE_ID))
	var second := _on_board(_scenario(NEGATION_ID))
	second.position = Vector2(520, 260)
	await get_tree().process_frame
	var pin: Control = layer._create_pin("", Pin.Tone.GREEN)
	layer._attach(pin, first, "top")
	assert_eq(pin.description, str(first.properties["Name"]))
	layer._drag_pin = pin
	var control: Control = second.get_node("Control")
	layer._release_pin(pin, control.get_global_transform() * (control.size * 0.5))
	assert_eq(pin.attached_card, second, "o pin fica preso à carta de baixo")
	assert_eq(pin.description, str(first.properties["Name"]),
			"o pin já nomeado mantém o nome do primeiro personagem")


# O primeiro solto num pin sem nome decide o nome: o pin novo largado em cima de
# uma carta leva o nome dela, e um segundo solto não muda mais.
func test_a_new_green_pin_takes_the_name_of_the_card_it_lands_on():
	var first := _on_board(_scenario(SIMPLE_ID))
	var second := _on_board(_scenario(NEGATION_ID))
	second.position = Vector2(520, 260)
	await get_tree().process_frame
	var pin: Control = layer._create_pin("", Pin.Tone.GREEN)
	layer._drag_pin = pin
	var second_control: Control = second.get_node("Control")
	layer._release_pin(pin,
			second_control.get_global_transform() * (second_control.size * 0.5))
	assert_eq(pin.description, NEGATION_NAME, "o primeiro solto nomeia o pin")
	layer._drag_pin = pin
	var first_control: Control = first.get_node("Control")
	layer._release_pin(pin,
			first_control.get_global_transform() * (first_control.size * 0.5))
	assert_eq(pin.attached_card, first)
	assert_eq(pin.description, NEGATION_NAME,
			"o segundo solto não troca o nome já escolhido")


# Numa pilha o pin fica com a carta que o jogador vê no ponto solto: no meio do
# hospedeiro, ele; na beirada exposta de uma carta presa atrás, a carta presa.
func test_a_green_pin_names_the_card_under_the_pointer_in_a_stack():
	var host := _on_board(_scenario(NEGATION_ID))
	host.position = Vector2(300, 200)
	var energy := _on_board(_scenario(SIMPLE_ID))
	energy.current_host_card = host
	energy.position = host.position \
			+ Vector2(0, host.card_size.y * CFConst.ATTACHMENT_OFFSET[
					Card.AttachmentOffset.BATTLE_SCENES_BOTTOM].y)
	# A pilha deixa o hospedeiro por último para ele desenhar por cima.
	board.move_child(host, -1)
	await get_tree().process_frame
	var host_control: Control = host.get_node("Control")
	var energy_control: Control = energy.get_node("Control")
	var middle: Vector2 = host_control.get_global_transform() \
			* (host_control.size * 0.5)
	assert_eq(layer._card_at(middle), host, "no meio da pilha vale a de cima")
	var pin: Control = layer._create_pin("", Pin.Tone.GREEN)
	layer._attach(pin, layer._card_at(middle), "top")
	assert_eq(pin.description, NEGATION_NAME,
			"o pin leva o nome do hospedeiro, não do anexo")
	var exposed: Vector2 = energy_control.get_global_transform() \
			* Vector2(energy_control.size.x * 0.5, energy_control.size.y * 0.97)
	assert_false(host_control.get_global_rect().has_point(exposed),
			"o ponto está fora da carta de cima")
	assert_eq(layer._card_at(exposed), energy,
			"a beirada exposta vale para a carta de baixo")
	var second: Control = layer._create_pin("", Pin.Tone.GREEN)
	layer._attach(second, layer._card_at(exposed), "top")
	assert_eq(second.description, str(energy.properties["Name"]),
			"o pin leva o nome da carta que está na beirada")


# Botão direito copia o pin para o encaixe livre mais próximo, com a mesma cor
# e o mesmo texto de hover.
func test_the_right_click_copies_a_green_pin_to_a_free_anchor():
	var card := _scenario(SIMPLE_ID)
	var slot = _occupy_slot(0, card)
	var pin: Control = layer._create_pin("", Pin.Tone.GREEN)
	layer._attach(pin, card, "top")
	layer._follow(pin)
	pin.right_clicked.emit(pin)
	assert_eq(layer.pin_count(), 2, "a cópia entra na mesa")
	var copy: Control = layer._pins[1]
	assert_eq(copy.tone, Pin.Tone.GREEN, "a cópia mantém a cor")
	assert_eq(copy.description, str(card.properties["Name"]),
			"a cópia mantém o nome do original")
	assert_gt(_pin_centre(copy).distance_to(_pin_centre(pin)),
			layer.SNAP_EPSILON, "a cópia não empilha no mesmo encaixe")
	var nearest := INF
	for anchor in layer._anchors():
		nearest = min(nearest,
				_pin_centre(copy).distance_to(anchor["point"]))
	assert_lt(nearest, 0.5, "a cópia senta num encaixe")
	slot.occupying_card = null


func test_the_right_click_copies_a_red_pin_too():
	var pin: Control = layer._create_pin("", Pin.Tone.RED)
	layer._place_pin(pin, layer._nearest_free_anchor(
			Vector2(_layer_center())))
	pin.right_clicked.emit(pin)
	assert_eq(layer.pin_count(), 2)
	assert_eq(layer._pins[1].tone, Pin.Tone.RED)
	assert_eq(layer._pins[1].description, "")


func _layer_center() -> Vector2:
	return layer._grid.get_global_rect().get_center()


# As cartas deitadas a 90° saem da caixa sem rotação; o acerto do pin precisa
# acompanhar a transformação da carta.
func test_a_card_lying_sideways_still_receives_the_pin():
	var card := _on_board(_scenario(SIMPLE_ID))
	var control: Control = card.get_node("Control")
	control.pivot_offset = control.size * 0.5
	control.rotation_degrees = 90
	var point: Vector2 = control.get_global_transform() \
			* Vector2(2.0, control.size.y * 0.5)
	assert_false(control.get_global_rect().has_point(point),
			"o ponto está fora da caixa sem rotação")
	assert_eq(layer._card_at(point), card,
			"o acerto da carta acompanha a rotação")


func _pin_centre(pin: Control) -> Vector2:
	return pin.get_global_transform() * (pin.size * 0.5)


# A carta espelhada fica a 180°; o pin preso nela vira junto e continua na
# quina superior direita da carta.
func test_a_pin_on_a_card_turns_with_the_card():
	var card := _scenario(SIMPLE_ID)
	var pin: Control = layer._create_pin("", Pin.Tone.RED)
	layer._attach(pin, card, "top")
	layer._follow(pin)
	var control: Control = card.get_node("Control")
	control.pivot_offset = control.size * 0.5
	control.rotation_degrees = 180
	layer._follow(pin)
	assert_almost_eq(absf(pin.rotation_degrees), 180.0, 0.5)
	var top_right: Vector2 = layer._edge_anchor(card, "top")
	assert_almost_eq(_pin_centre(pin).distance_to(top_right), 0.0, 0.5)


func _on_board(card: Card) -> Card:
	hand.remove_child(card)
	board.add_child(card)
	return card


# A troca P1↔P2 reconstrói a mesa: o pin reencontra a carta pelo id de rede e
# volta a ficar no centro da borda da nova carta.
func test_the_pin_finds_the_card_again_after_the_rebuild():
	var first := _on_board(_scenario(SIMPLE_ID))
	first.network_id = "carta-77"
	var pin: Control = layer._create_pin("", Pin.Tone.GREEN)
	layer._attach(pin, first, "bottom")
	layer._follow(pin)
	first.free()
	var second := _on_board(_scenario(SIMPLE_ID))
	second.network_id = "carta-77"
	second.position = Vector2(400, 300)
	assert_true(layer._follow(pin), "o pin reencontra a carta reconstruída")
	assert_eq(pin.attached_card, second)
	var control: Control = second.get_node("Control")
	var bottom_centre: Vector2 = control.get_global_transform() \
			* Vector2(control.size.x * 0.5, control.size.y)
	assert_almost_eq(_pin_centre(pin).distance_to(bottom_centre), 0.0, 0.5)


# O espelho da banda do adversário sai do grupo "cards"; mesmo assim o pin o
# encontra pelo id quando a carta vira espelho depois da troca de assento.
func test_the_pin_follows_a_card_that_became_a_mirror():
	var mirror := _on_board(_scenario(SIMPLE_ID))
	mirror.network_id = "carta-88"
	mirror.network_mirror = true
	mirror.remove_from_group("cards")
	var pin: Control = layer._create_pin("", Pin.Tone.RED)
	layer._attach(pin, mirror, "top")
	assert_true(layer._follow(pin))
	var control: Control = mirror.get_node("Control")
	control.pivot_offset = control.size * 0.5
	control.rotation_degrees = 180
	assert_true(layer._follow(pin), "o pin segue o espelho")
	assert_almost_eq(absf(pin.rotation_degrees), 180.0, 0.5)


# O vão espelhado: mesmo eixo que as cartas usam (centro do tabuleiro em x, base
# da banda do adversário em y).
func _mirror_axis() -> Vector2:
	var visual: Control = board.get_node_or_null("OpponentFieldVisual")
	var split_y: float = board.global_position.y + board.size.y * 0.5
	if visual and visual.size.y > 0.0:
		split_y = visual.global_position.y + visual.size.y
	return Vector2(board.global_position.x + board.size.x * 0.5, split_y)


# O pin solto guarda o ponto na visão do dono. A troca P1↔P2 vira o lado do
# outro assento, então o pin muda de lado junto com as cartas da banda; voltar
# ao assento do dono devolve o pin ao ponto escolhido.
func test_a_loose_pin_mirrors_when_the_seat_swaps():
	Multiplayer.my_slot = 1
	layer._seat_seen = 1
	var pin: Control = layer._create_pin("", Pin.Tone.RED)
	var point := Vector2(320, 240)
	layer._place_pin(pin, {"point": point, "card": null, "edge": ""})
	assert_almost_eq(_pin_centre(pin).distance_to(point), 0.0, 0.5,
			"o dono põe o pin no ponto dele")
	assert_eq(pin.anchor_point, point, "o ponto fica guardado na visão do dono")
	Multiplayer.my_slot = 2
	layer._process(0.0)
	var axis := _mirror_axis()
	var mirrored := Vector2(axis.x * 2.0 - point.x, axis.y * 2.0 - point.y)
	assert_almost_eq(_pin_centre(pin).distance_to(mirrored), 0.0, 0.5,
			"o pin do outro assento aparece espelhado, como as cartas")
	assert_eq(pin.anchor_point, point, "o espelho não move o ponto do dono")
	Multiplayer.my_slot = 1
	layer._process(0.0)
	assert_almost_eq(_pin_centre(pin).distance_to(point), 0.0, 0.5,
			"de volta ao assento do dono o pin volta ao lugar")


# -----------------------------------------------------------------------------
# Espelho dos pins entre os clientes
# -----------------------------------------------------------------------------

# O estado enviado leva o vínculo pela carta (id de rede), o tom e o nome; a
# cópia que chega do outro jogador é só desenhada e não volta para o relay.
func test_the_pin_state_round_trips_to_a_remote_copy():
	var card := _on_board(_scenario(NEGATION_ID))
	card.network_id = "carta-91"
	var pin: Control = layer._create_pin(NEGATION_NAME)
	layer._attach(pin, card, "top")
	layer._follow(pin)
	var state: Array = layer.local_pin_state()
	assert_eq(state.size(), 1)
	assert_eq(str(state[0]["net"]), "carta-91")
	assert_eq(str(state[0]["edge"]), "top")
	assert_eq(str(state[0]["name"]), NEGATION_NAME)
	layer.clear_pins()
	layer.apply_remote_pins(state)
	assert_eq(layer._remote_pins.size(), 1)
	var remote: Control = layer._remote_pins[0]
	assert_true(remote.remote)
	assert_eq(remote.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(remote.description, NEGATION_NAME)
	assert_eq(remote.attached_card, card)
	assert_eq(layer.local_pin_state().size(), 0,
			"a cópia remota não volta para o outro cliente")


# O nome é do pin, já escolhido pelo dono. A cópia remota presa a uma carta
# verde não pode herdar o nome que a mesma carta tem deste lado.
func test_a_remote_pin_keeps_the_name_the_owner_sent():
	var card := _on_board(_scenario(SIMPLE_ID))
	card.network_id = "carta-92"
	layer.apply_remote_pins([{
		"tone": Pin.Tone.GREEN, "name": NEGATION_NAME,
		"net": "carta-92", "edge": "top", "x": 0.0, "y": 0.0,
	}])
	assert_eq(layer._remote_pins.size(), 1)
	var remote: Control = layer._remote_pins[0]
	assert_eq(remote.attached_card, card)
	assert_eq(remote.description, NEGATION_NAME,
			"a cópia mantém o nome que veio do outro jogador")


# Um pin solto viaja com o ponto na visão do dono e é desenhado espelhado do
# outro lado, do mesmo jeito que as cartas do campo adversário.
func test_a_remote_loose_pin_is_drawn_mirrored():
	var point := Vector2(320, 240)
	layer.apply_remote_pins([{
		"tone": Pin.Tone.RED, "name": "", "net": "", "edge": "",
		"x": point.x, "y": point.y,
	}])
	assert_eq(layer._remote_pins.size(), 1)
	var axis := _mirror_axis()
	var mirrored := Vector2(axis.x * 2.0 - point.x, axis.y * 2.0 - point.y)
	assert_almost_eq(_pin_centre(layer._remote_pins[0]).distance_to(mirrored),
			0.0, 0.5)


# O Godot escolhe o Control do clique pela ordem da árvore, não pelo z_index:
# a camada tem de ficar depois das cartas para o clique no pin não pegar a
# carta que está debaixo.
func test_the_pin_layer_is_the_last_board_child():
	_on_board(_scenario(SIMPLE_ID))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(layer.get_index(), board.get_child_count() - 1)
