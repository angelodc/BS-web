# Mirrors local Battle Scenes actions onto the opponent visual field.
extends Control

const DRAG_SEND_INTERVAL := 0.08
const HIDDEN_ZONES := ["hand", "deck", "prizes"]

var _local_seq := 0
var _remote_cards := {}
var _hand_order := []
var _drag_timer := 0.0
var _spawning_remote := false
var _status: Label
var _log: Label
var _disconnect_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cfc.ut:
		return
	_build_ui()
	# warning-ignore:return_value_discarded
	Rede.connect("status_changed", self, "_on_status_changed")
	# warning-ignore:return_value_discarded
	Rede.connect("peer_connected", self, "_on_peer_connected")
	# warning-ignore:return_value_discarded
	Rede.connect("peer_disconnected", self, "_on_peer_disconnected")
	# warning-ignore:return_value_discarded
	Rede.connect("message_received", self, "_on_network_message")
	# warning-ignore:return_value_discarded
	cfc.signal_propagator.connect("signal_received", self, "_on_card_signal")
	# warning-ignore:return_value_discarded
	cfc.connect("new_card_instanced", self, "_on_new_card")
	_on_status_changed(Rede.get_status())
	if Rede.is_connected:
		_on_peer_connected()


func _exit_tree() -> void:
	if not cfc.ut:
		Rede.disconnect_game()


func _process(delta: float) -> void:
	if cfc.ut or not Rede.is_connected:
		return
	var dragged: Card = cfc.card_drag_ongoing
	if dragged and not dragged.network_mirror:
		_drag_timer += delta
		if _drag_timer >= DRAG_SEND_INTERVAL:
			_drag_timer = 0.0
			_send_card_state(dragged, _zone_for_card(dragged), true)


func _build_ui() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	margin_left = -530
	margin_top = 328
	margin_right = -8
	margin_bottom = 430
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)

	_status = Label.new()
	_status.text = "Multiplayer: desconectado"
	box.add_child(_status)

	_disconnect_button = Button.new()
	_disconnect_button.text = "Sair da partida"
	_disconnect_button.connect("pressed", self, "_on_disconnect_pressed")
	box.add_child(_disconnect_button)

	_log = Label.new()
	_log.autowrap = true
	_log.text = "Ações do oponente aparecem aqui."
	box.add_child(_log)


func _on_disconnect_pressed() -> void:
	Rede.disconnect_game()


func _on_status_changed(text: String) -> void:
	if _status:
		_status.text = text


func _on_peer_connected() -> void:
	_log_action("Partida contra " + Rede.opponent_username
			+ ". Enviando estado atual.")
	Rede.send_message({"t": "hello"})
	_send_snapshot()


func _on_peer_disconnected() -> void:
	_clear_remote_cards()
	_log_action("Espelhamento encerrado.")


func _on_new_card(card: Card) -> void:
	if _spawning_remote:
		card.network_mirror = true
		return
	if card.network_mirror:
		return
	_ensure_id(card)


func _on_card_signal(card: Card, trigger: String, details: Dictionary) -> void:
	if not Rede.is_connected or card.network_mirror:
		return
	var tags = details.get("tags", [])
	if typeof(tags) == TYPE_ARRAY and "net" in tags:
		return
	match trigger:
		"card_moved_to_hand":
			_send_card_state(card, "hand")
			if str(details.get("source", "")).to_lower() == "deck":
				_send_hidden("Comprou carta")
		"card_moved_to_pile":
			var destination := _pile_zone(str(details.get("destination", "")))
			_send_card_state(card, destination)
			_send_hidden(_hidden_for_pile(destination, str(details.get("source", ""))))
		"card_moved_to_board":
			_send_card_state(card, "board")
		"card_rotated":
			_send_card_state(card, "board")
		"card_flipped":
			_send_card_state(card, _zone_for_card(card))
		"card_attached", "card_unattached":
			_send_card_state(card, "board")


func _on_network_message(data: Dictionary) -> void:
	var kind := str(data.get("t", ""))
	match kind:
		"hidden":
			_log_action(str(data.get("msg", "O oponente fez uma ação oculta.")))
		"card":
			_apply_remote_card(data)
		"hello":
			_send_snapshot()


func _send_snapshot() -> void:
	var snapshot := []
	for card in get_tree().get_nodes_in_group("cards"):
		if not (card is Card) or card.network_mirror:
			continue
		snapshot.append(card)
	snapshot.sort_custom(self, "_sort_hosts_first")
	for card in snapshot:
		_send_card_state(card, _zone_for_card(card))


func _send_hidden(message: String) -> void:
	if message.empty():
		return
	Rede.send_message({
		"t": "hidden",
		"msg": message,
	})


func _send_card_state(card: Card, zone: String, dragging := false) -> void:
	_ensure_id(card)
	var hidden := zone in HIDDEN_ZONES
	var payload := {
		"t": "card",
		"id": card.network_id,
		"zone": zone,
		"x": card.global_position.x,
		"y": card.global_position.y,
		"rot": card.card_rotation,
		"face": 1 if card.is_faceup and not hidden else 0,
		"hidden": 1 if hidden else 0,
		"name": "" if hidden else card.canonical_name,
		"host": "",
		"drag": 1 if dragging else 0,
	}
	if card.current_host_card and card.current_host_card.network_id:
		payload["host"] = card.current_host_card.network_id
	Rede.send_message(payload)


func _apply_remote_card(data: Dictionary) -> void:
	var net_id := str(data.get("id", ""))
	if net_id.empty():
		return
	var zone := str(data.get("zone", "board"))
	var hidden := int(data.get("hidden", 0)) == 1
	var card_name := str(data.get("name", ""))
	var card: Card = _remote_cards.get(net_id)
	if zone == "deck":
		if card and is_instance_valid(card):
			card.queue_free()
		_remote_cards.erase(net_id)
		_hand_order.erase(net_id)
		return
	if hidden:
		if not is_instance_valid(card):
			card = _instance_hidden_card(net_id)
	else:
		if is_instance_valid(card) and card.canonical_name != card_name and card_name:
			card.queue_free()
			_remote_cards.erase(net_id)
			card = null
		if not is_instance_valid(card):
			card = _instance_named_card(net_id, card_name)
	if not is_instance_valid(card):
		return
	_configure_remote_card(card)
	# warning-ignore:return_value_discarded
	card.set_is_faceup(int(data.get("face", 0)) == 1, true, false, ["net"])
	var host_id := str(data.get("host", ""))
	if host_id and _remote_cards.has(host_id):
		var host: Card = _remote_cards[host_id]
		card.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
		card.attachment_offset = Card.AttachmentOffset.BATTLE_SCENES_BOTTOM
		if card.current_host_card != host:
			card.attach_to_host(host, false, ["net"])
	elif card.current_host_card:
		card._clear_attachment_status()
	var target := _position_for_zone(zone, Vector2(data.get("x", 0), data.get("y", 0)), net_id)
	if card.get_parent() != cfc.NMAP.board:
		card.get_parent().remove_child(card)
		cfc.NMAP.board.add_child(card)
	card.global_position = target
	card._target_position = target
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	if zone == "board":
		# warning-ignore:return_value_discarded
		card.set_card_rotation(int(data.get("rot", 0)), false, true, false, ["net"])
	if zone == "hand" and not net_id in _hand_order:
		_hand_order.append(net_id)
		_layout_remote_hand()
	elif zone != "hand":
		_hand_order.erase(net_id)
		_layout_remote_hand()


func _instance_hidden_card(net_id: String) -> Card:
	var dummy_name := _dummy_card_name()
	if dummy_name.empty():
		return null
	return _instance_named_card(net_id, dummy_name)


func _instance_named_card(net_id: String, card_name: String) -> Card:
	if card_name.empty() or not cfc.card_definitions.has(card_name):
		card_name = _dummy_card_name()
	if card_name.empty():
		return null
	_spawning_remote = true
	var card: Card = cfc.instance_card(card_name)
	_spawning_remote = false
	card.network_id = net_id
	card.network_mirror = true
	cfc.NMAP.board.add_child(card)
	_configure_remote_card(card)
	_remote_cards[net_id] = card
	return card


func _configure_remote_card(card: Card) -> void:
	card.network_mirror = true
	card.remove_from_group("cards")
	if not card.is_in_group("remote_cards"):
		card.add_to_group("remote_cards")
	card.monitoring = false
	card.monitorable = false
	card.set_control_mouse_filters(false)
	if card.buttons:
		card.buttons.set_active(false)


func _dummy_card_name() -> String:
	if cfc.card_definitions.has("Test Card 1"):
		return "Test Card 1"
	var names := cfc.card_definitions.keys()
	if names.empty():
		return ""
	return str(names[0])


func _position_for_zone(zone: String, local_pos: Vector2, net_id: String) -> Vector2:
	var visual: Control = cfc.NMAP.board.get_node("OpponentFieldVisual")
	match zone:
		"hand":
			return _hand_slot_position(net_id)
		"resources":
			return visual.get_node("OpponentResourcesBackground").rect_global_position + Vector2(10, 30)
		"prizes":
			return visual.get_node("OpponentPrizes").rect_global_position + Vector2(10, 30)
		"scenario":
			return visual.get_node("OpponentScenario").rect_global_position + Vector2(10, 30)
		_:
			return _map_board_position(local_pos)


func _map_board_position(local_pos: Vector2) -> Vector2:
	var board: Control = cfc.NMAP.board
	var visual: Control = board.get_node("OpponentFieldVisual")
	var scene: ColorRect = visual.get_node("OpponentScene")
	var grid: Control = board.get_node("PlacementGridDemo")
	var local_origin := grid.rect_global_position
	var local_size := grid.rect_size
	var rel := Vector2.ZERO
	if local_size.x > 0 and local_size.y > 0:
		rel = Vector2(
				clamp((local_pos.x - local_origin.x) / local_size.x, 0.0, 1.0),
				clamp((local_pos.y - local_origin.y) / local_size.y, 0.0, 1.0)
		)
	return scene.rect_global_position + Vector2(rel.x * scene.rect_size.x, rel.y * scene.rect_size.y)


func _hand_slot_position(net_id: String) -> Vector2:
	var visual: Control = cfc.NMAP.board.get_node("OpponentFieldVisual")
	var hand_bg: ColorRect = visual.get_node("OpponentHandBackground")
	var index := _hand_order.find(net_id)
	if index < 0:
		index = _hand_order.size()
	return hand_bg.rect_global_position + Vector2(12 + index * 42, 28)


func _layout_remote_hand() -> void:
	var valid := []
	for net_id in _hand_order:
		if _remote_cards.has(net_id) and is_instance_valid(_remote_cards[net_id]):
			valid.append(net_id)
	_hand_order = valid
	for net_id in _hand_order:
		var card: Card = _remote_cards[net_id]
		card.global_position = _hand_slot_position(net_id)


func _clear_remote_cards() -> void:
	for card in _remote_cards.values():
		if is_instance_valid(card):
			card.queue_free()
	_remote_cards.clear()
	_hand_order.clear()


func _sort_hosts_first(card_a: Card, card_b: Card) -> bool:
	if card_a.current_host_card and not card_b.current_host_card:
		return false
	if not card_a.current_host_card and card_b.current_host_card:
		return true
	return true


func _ensure_id(card: Card) -> void:
	if card.network_id.empty():
		_local_seq += 1
		card.network_id = Rede.peer_tag + "_" + str(_local_seq)


func _zone_for_card(card: Card) -> String:
	var parent = card.get_parent()
	if parent == cfc.NMAP.board:
		if str(card.properties.get("_tipo", "")) == "Cenário":
			return "scenario"
		return "board"
	if parent == cfc.NMAP.hand:
		return "hand"
	if parent == cfc.NMAP.deck:
		return "deck"
	if parent == cfc.NMAP.discard:
		return "resources"
	if str(parent.name) == "Prêmios":
		return "prizes"
	return "board"


func _pile_zone(destination_name: String) -> String:
	var lowered := destination_name.to_lower()
	if "prêm" in lowered or "prem" in lowered:
		return "prizes"
	if "deck" in lowered:
		return "deck"
	return "resources"


func _hidden_for_pile(zone: String, source: String) -> String:
	if zone == "resources":
		if source.to_lower() == "hand":
			return "Baixou recurso"
		return "Enviou carta a Recursos/Descarte"
	if zone == "deck":
		return "Moveu carta ao Deck"
	if zone == "prizes":
		return ""
	return "Moveu uma carta oculta"


func _log_action(text: String) -> void:
	if _log:
		_log.text = text
	var opponent_label = cfc.NMAP.board.get_node_or_null(
			"OpponentFieldVisual/OpponentFieldLabel") as Label
	if opponent_label:
		opponent_label.text = "CAMPO DO OPONENTE - " + text
