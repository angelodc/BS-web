# Mirrors public card state to the opponent field and shows hidden counts.
#
# Only hand and deck are private. Prizes, resources, scenario and board are
# public and mirrored. Board coordinates travel normalized so both clients can
# use different viewport sizes. The remote presence reveals only which zone
# the opponent mouse is in, drawn as a lens over the mirrored zone.
extends Control

const SELECTION_WINDOW_SCENE = preload("res://src/core/SelectionWindow.tscn")
const DRAG_SEND_INTERVAL := 0.08
const COUNTS_SEND_DELAY := 0.12
const HIDDEN_SWEEP_INTERVAL := 1.5
const HIDDEN_ZONES := ["hand", "deck"]
const VISIBLE_ZONES := ["board", "scenario", "resources", "prizes"]
# The opponent field is the local field rotated 180 degrees, so scene cards
# must have the same size on both sides to line up across the middle. The
# corner boxes only mirror one card each, so they use smaller scales.
const BOARD_SCALE := CFConst.PLAY_AREA_SCALE
const SCENARIO_SCALE := 0.42
const PRIZES_SCALE := 0.2
const HAND_SCALE := 0.2
const MAX_HAND_PLACEHOLDERS := 24
# Room kept free at the bottom of the mirrored scene so attachments stacked
# under a character stay inside the opponent half of the board.
const SCENE_ATTACHMENT_MARGIN := 30.0
# The scenario and pile boxes show their labels along the bottom edge.
const SCENARIO_LABEL_MARGIN := 22.0
# The mirrored resource box draws the same mini grid the local discard shows:
# three columns with a 6 px gap inside the authored panel width.
const RESOURCES_GRID_COLUMNS := 3
const RESOURCES_GRID_GAP := 6.0
const RESOURCES_GRID_MAX := 6
# The zone lens pulses so a still frame still reads as "someone is here".
const LENS_PULSE_SPEED := 5.0

var _active := false
var _suppressed := false
var _spawning_remote := false
var _remote_cards := {}
var _remote_meta := {}
var _remote_zone_order := {"resources": [], "prizes": []}
var _remote_drag_card: Card = null
var _remote_drag_offset := Vector2.ZERO
var _sent_visible := {}
var _pending_cards := {}
var _resource_preview: Card = null
var _hand_placeholders := []
var _lens: Panel
var _lens_time := 0.0
var _remote_zone := ""
var _sent_zone := ""
var _solo_preview := false
var _drag_timer := 0.0
var _counts_timer := 0.0
var _sweep_timer := 0.0
var _counts_dirty := false
var _last_sent_counts := {"hand": -1, "deck": -1}
var _last_hidden_counts := {"hand": -1, "deck": -1}
# Scenarios are unique across both fields. Claims use a Lamport-style clock so
# the latest play wins even when both players act at nearly the same time.
var _scenario_clock := 0
var _scenario_claims := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cfc.ut:
		return
	_build_lens()
	# warning-ignore:return_value_discarded
	Rede.connect("message_received", self, "_on_network_message")
	# warning-ignore:return_value_discarded
	Rede.connect("peer_disconnected", self, "_on_peer_disconnected")
	# warning-ignore:return_value_discarded
	Multiplayer.connect("session_ended", self, "_on_session_ended")
	# warning-ignore:return_value_discarded
	cfc.signal_propagator.connect("signal_received", self, "_on_card_signal")
	# warning-ignore:return_value_discarded
	cfc.connect("new_card_instanced", self, "_on_new_card")
	_connect_view_button("OpponentResourcesView", "resources")
	_connect_view_button("OpponentPrizesView", "prizes")


func start_mirroring() -> void:
	if _active:
		return
	_active = true
	_counts_dirty = true
	_last_sent_counts = {"hand": -1, "deck": -1}
	_update_opponent_labels(0, 0)


func stop_mirroring() -> void:
	_active = false
	_remote_drag_card = null
	_clear_remote_cards()
	_clear_hand_placeholders()
	_remote_zone = ""
	_sent_zone = ""
	_solo_preview = false
	_hide_lens()


func set_suppressed(value: bool) -> void:
	_suppressed = value


func _process(delta: float) -> void:
	_update_remote_drag()
	_update_lens(delta)
	_update_remote_resources()
	if _solo_preview:
		_preview_zone_presence()
		return
	if not _can_send():
		return
	_send_zone_presence()
	_send_pending_counts(delta)
	_send_dragged_card(delta)
	_sweep_hidden_cards(delta)


func _can_send() -> bool:
	return _active and not _suppressed and Rede.is_connected \
			and Multiplayer.is_playing()


#-----------------------------------------------------------------------------
# Outgoing state
#-----------------------------------------------------------------------------

func send_snapshot() -> void:
	if not _can_send():
		return
	_last_sent_counts = {"hand": -1, "deck": -1}
	for card in get_tree().get_nodes_in_group("cards"):
		if not (card is Card) or not is_instance_valid(card) \
				or not card.is_inside_tree() or card.network_mirror:
			continue
		var zone := _zone_for_card(card)
		if zone in HIDDEN_ZONES:
			continue
		_send_card_state(card, zone)
	send_counts()


func send_counts() -> void:
	if not _can_send():
		return
	var counts := _local_hidden_counts()
	if int(counts["hand"]) == int(_last_sent_counts["hand"]) \
			and int(counts["deck"]) == int(_last_sent_counts["deck"]):
		return
	_last_sent_counts = counts
	Rede.send_message({
		"t": "mp_counts",
		"hand": int(counts["hand"]),
		"deck": int(counts["deck"]),
	})


func _send_pending_counts(delta: float) -> void:
	if not _counts_dirty:
		return
	_counts_timer += delta
	if _counts_timer < COUNTS_SEND_DELAY:
		return
	_counts_timer = 0.0
	_counts_dirty = false
	send_counts()


func _send_dragged_card(delta: float) -> void:
	var dragged = cfc.card_drag_ongoing
	if not (dragged is Card) or not is_instance_valid(dragged) \
			or dragged.network_mirror:
		return
	var zone := _zone_for_card(dragged)
	if zone in HIDDEN_ZONES:
		return
	_drag_timer += delta
	if _drag_timer < DRAG_SEND_INTERVAL:
		return
	_drag_timer = 0.0
	_send_card_state(dragged, zone, true)


func _send_card_state(card: Card, zone: String, dragging := false) -> void:
	if not _can_send() or not is_instance_valid(card) or card.network_mirror:
		return
	if card.state == Card.CardState.VIEWPORT_FOCUS:
		return
	var net_id := Multiplayer.ensure_card_id(card)
	if net_id.empty():
		return
	if zone in HIDDEN_ZONES:
		_send_hidden_card(card)
		return
	var payload := {
		"t": "mp_card",
		"id": net_id,
		"zone": zone,
		"name": card.definition_key(),
		"face": 1 if card.is_faceup else 0,
		"rot": int(card.card_rotation),
		"drag": 1 if dragging else 0,
		"host": "",
		"x": 0.5,
		"y": 0.5,
	}
	if zone == "board":
		var normalized := _normalize_board_position(card.global_position)
		payload["x"] = normalized.x
		payload["y"] = normalized.y
		# A dragged card has left its slot, so only a settled card names one.
		if not dragging:
			payload["slot"] = _slot_index(card._placement_slot)
	if zone == "scenario":
		payload["claim"] = int(_scenario_claims.get(net_id, 0))
	if card.current_host_card and is_instance_valid(card.current_host_card):
		payload["host"] = Multiplayer.ensure_card_id(card.current_host_card)
	var definition = cfc.card_definitions.get(card.definition_key(), {})
	if typeof(definition) == TYPE_DICTIONARY and not definition.empty():
		payload["definition"] = definition
	Rede.send_message(payload)
	_sent_visible[net_id] = true


func _send_hidden_card(card: Card) -> void:
	if not is_instance_valid(card):
		return
	var net_id := Multiplayer.ensure_card_id(card)
	if _sent_visible.has(net_id):
		_sent_visible.erase(net_id)
		Rede.send_message({"t": "mp_remove", "id": net_id})
	_counts_dirty = true


# Cards that reach a hidden zone without emitting the usual move signal (the
# shuffle animation, for example) would leave a phantom mirror on the other
# side, so advertised cards are re-checked against the hidden zones.
func _sweep_hidden_cards(delta: float) -> void:
	if _sent_visible.empty():
		return
	_sweep_timer += delta
	if _sweep_timer < HIDDEN_SWEEP_INTERVAL:
		return
	_sweep_timer = 0.0
	var board: Control = cfc.NMAP.board
	if board:
		for node in board.get_children():
			if node is Card and not node.network_mirror \
					and node.state == Card.CardState.VIEWPORT_FOCUS \
					and _sent_visible.has(node.network_id):
				_send_hidden_card(node)
	for container in [cfc.NMAP.get("deck"), cfc.NMAP.get("hand")]:
		if not container:
			continue
		for card in container.get_all_cards():
			if card is Card and _sent_visible.has(card.network_id):
				_send_hidden_card(card)


func _send_card_state_soon(card: Card) -> void:
	if not is_instance_valid(card):
		return
	yield(get_tree().create_timer(0.2), "timeout")
	if not is_instance_valid(card) or not card.is_inside_tree():
		return
	_send_card_state(card, _zone_for_card(card))


# Sends a local character to the opponent's prize area. The card leaves the
# local field; the receiver hosts it as one of its own prize cards.
func send_card_to_opponent_prizes(card: Card) -> bool:
	if not is_instance_valid(card) or card.network_mirror:
		return false
	var net_id := Multiplayer.ensure_card_id(card)
	if net_id.empty():
		return false
	if not _can_send():
		# The hotseat has no peer, so the same mirror the other client would
		# echo back is built here directly.
		return Multiplayer.is_solo() and _hold_prize_card_locally(card, net_id)
	var payload := {
		"t": "mp_card",
		"id": net_id,
		"zone": "opponent_prizes",
		"name": card.definition_key(),
		"face": 1,
		"rot": 0,
		"drag": 0,
		"host": "",
		"x": 0.5,
		"y": 0.5,
		"claim": 0,
	}
	var definition = cfc.card_definitions.get(card.definition_key(), {})
	if typeof(definition) == TYPE_DICTIONARY and not definition.empty():
		payload["definition"] = definition
	Rede.send_message(payload)
	_sent_visible[net_id] = true
	return true


#-----------------------------------------------------------------------------
# Incoming state
#-----------------------------------------------------------------------------

func _on_network_message(data: Dictionary) -> void:
	match str(data.get("t", "")):
		"mp_card":
			_apply_remote_card(data)
		"mp_remove":
			_remove_remote_card(str(data.get("id", "")))
		"mp_counts":
			_apply_remote_counts(data)
		"mp_defs":
			_apply_definitions(data.get("definitions", {}))
			_apply_remote_defs_waiting()
		"mp_def_request":
			_send_definition(str(data.get("name", "")))
		"mp_sync_request":
			send_snapshot()
		"mp_zone":
			_apply_remote_zone(str(data.get("zone", "")))
		"mp_card_move_request":
			_apply_move_request(data)


func _apply_remote_card(data: Dictionary) -> void:
	if not Multiplayer.is_session_active():
		return
	var net_id := str(data.get("id", ""))
	var zone := str(data.get("zone", "board"))
	var card_name := str(data.get("name", ""))
	if net_id.empty() or card_name.empty() \
			or (not zone in VISIBLE_ZONES and zone != "opponent_prizes"):
		return
	var definition = data.get("definition", {})
	if typeof(definition) == TYPE_DICTIONARY and not definition.empty():
		cfc.card_definitions[card_name] = definition
	if not cfc.card_definitions.has(card_name):
		if not _pending_cards.has(card_name):
			_pending_cards[card_name] = []
		_pending_cards[card_name].append(data.duplicate(true))
		Rede.send_message({"t": "mp_def_request", "name": card_name})
		return
	if zone == "opponent_prizes":
		_apply_remote_card_to_local_prizes(net_id, card_name)
		return
	var claim := int(data.get("claim", 0))
	if zone == "scenario" and not _accept_remote_scenario(net_id, claim):
		var resource_data := data.duplicate(true)
		resource_data["zone"] = "resources"
		resource_data["x"] = 0.5
		resource_data["y"] = 0.5
		resource_data["claim"] = 0
		_apply_remote_card(resource_data)
		return
	var card: Card = _remote_cards.get(net_id)
	if is_instance_valid(card) and card.definition_key() != card_name:
		_discard_remote_card(net_id)
		card = null
	if not is_instance_valid(card):
		card = _instance_named_card(net_id, card_name)
	if not is_instance_valid(card):
		return
	var travel := Vector2(float(data.get("x", 0.5)), float(data.get("y", 0.5)))
	var slot_index := int(data.get("slot", -1))
	var rotation := int(data.get("rot", 0))
	var face := int(data.get("face", 1)) == 1
	var host_id := str(data.get("host", ""))
	var previous_meta = _remote_meta.get(net_id, {})
	var previous_zone := ""
	if typeof(previous_meta) == TYPE_DICTIONARY:
		previous_zone = str(previous_meta.get("zone", ""))
	_remember_remote_meta(net_id, zone, card_name, travel, rotation, face,
			host_id, claim, slot_index)
	_configure_remote_card(card)
	_set_remote_card_interactive(card, zone)
	var host: Card = _remote_cards.get(host_id)
	if is_instance_valid(host) and host != card:
		card.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
		card.attachment_offset = Card.AttachmentOffset.BATTLE_SCENES_BOTTOM
		if card.current_host_card != host:
			card.attach_to_host(host, false, ["net"])
	elif card.current_host_card:
		card._clear_attachment_status(["net"])
	var target := _target_for_remote(zone, travel, net_id, slot_index)
	if card.get_parent() != cfc.NMAP.board:
		if card.get_parent():
			card.get_parent().remove_child(card)
		cfc.NMAP.board.add_child(card)
	card.global_position = target
	card._target_position = target
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	# warning-ignore:return_value_discarded
	card.set_is_faceup(face, true, false, ["net"])
	card.scale = Vector2(1, 1) * _scale_for_zone(zone)
	# The mirror is seen from the other side of the table, so it is shown
	# upside down like a real opponent's card. The rotation only reaches the
	# drawn control through the tween, so it has to start here.
	# warning-ignore:return_value_discarded
	card.set_card_rotation((rotation + 180) % 360, false, true, false, ["net"])
	if card.attachments.size() > 0:
		card._organize_attachments()
	_update_remote_zone_labels()
	# Drag ticks repeat the same zone many times per second, so only a zone
	# change is worth a line in the log.
	if int(data.get("drag", 0)) == 0 and previous_zone != zone:
		GameEvents.record_remote_card(zone, card_name, face,
				host.canonical_name if is_instance_valid(host) else "")


# The hotseat keeps the knocked-out character as a mirror in the opponent prize
# box, which is exactly the entry a snapshot carries once the seats are swapped.
func _hold_prize_card_locally(card: Card, net_id: String) -> bool:
	if not _active:
		return false
	var card_name := card.definition_key()
	var mirror: Card = _instance_named_card(net_id, card_name)
	if not is_instance_valid(mirror):
		return false
	_remember_remote_meta(net_id, "prizes", card_name, Vector2(0.5, 0.5),
			0, true, "", 0, -1)
	_set_remote_card_interactive(mirror, "prizes")
	var target := _target_for_remote("prizes", Vector2(0.5, 0.5), net_id, -1)
	mirror.global_position = target
	mirror._target_position = target
	mirror.set_state(Card.CardState.ON_PLAY_BOARD)
	# warning-ignore:return_value_discarded
	mirror.set_is_faceup(true, true, false, ["net"])
	mirror.scale = Vector2(1, 1) * _scale_for_zone("prizes")
	# warning-ignore:return_value_discarded
	mirror.set_card_rotation(180, false, true, false, ["net"])
	_update_remote_zone_labels()
	return true


# The opponent sent one of their characters to this player's prize area. It
# stops being a mirror and becomes a real local prize card.
func _apply_remote_card_to_local_prizes(net_id: String, card_name: String) -> void:
	if _remote_cards.has(net_id):
		_discard_remote_card(net_id)
	var board = cfc.NMAP.get("board", null)
	if not board:
		return
	var prize_pile = board.get_node_or_null("Prêmios")
	if not prize_pile:
		return
	for existing in get_tree().get_nodes_in_group("cards"):
		if existing is Card and is_instance_valid(existing) \
				and not existing.network_mirror \
				and str(existing.network_id) == net_id:
			return
	_spawning_remote = true
	var card = cfc.instance_card(card_name)
	_spawning_remote = false
	if not card:
		return
	card.network_id = net_id
	prize_pile.add_child(card)
	card._determine_idle_state()
	# warning-ignore:return_value_discarded
	card.set_is_faceup(true, true, false, ["net"])
	card.card_rotation = 0
	GameEvents.record_remote_card("opponent_prizes", card_name, true)
	_send_card_state(card, "prizes")
	if board.has_method("_update_prize_energy"):
		board._update_prize_energy()


# Scene cards can be dragged by either player. The owner receives the request,
# snaps the real card to its nearest free slot and broadcasts the new state.
func _set_remote_card_interactive(card: Card, zone: String) -> void:
	var interactive := zone in ["board", "scenario"]
	card.remote_draggable = interactive
	# The mirrored resource grid previews the card under the pointer by position,
	# like the local discard grid does, so its mirrors stay out of the mouse
	# detection: Area2D hover fires for every overlapping mirror at once and
	# leaves the preview flickering between them.
	var pointer_zone := zone in VISIBLE_ZONES and zone != "resources"
	card.set_control_mouse_filters(pointer_zone)
	if pointer_zone:
		if not card.is_connected("mouse_entered", self, "_on_remote_card_hover_entered"):
			card.connect("mouse_entered", self, "_on_remote_card_hover_entered", [card])
			card.connect("mouse_exited", self, "_on_remote_card_hover_exited", [card])
	elif card.is_connected("mouse_entered", self, "_on_remote_card_hover_entered"):
		card.disconnect("mouse_entered", self, "_on_remote_card_hover_entered")
		card.disconnect("mouse_exited", self, "_on_remote_card_hover_exited")
		_on_remote_card_hover_exited(card)
	if not interactive:
		if _remote_drag_card == card:
			_remote_drag_card = null
		return
	var control := card.get_node("Control")
	if not control.is_connected("gui_input", self, "_on_remote_card_gui_input"):
		control.connect("gui_input", self, "_on_remote_card_gui_input", [card])


func _on_remote_card_hover_entered(card: Card) -> void:
	if cfc.ut or not is_instance_valid(card) \
			or not cfc.NMAP.has("main") or not cfc.NMAP.main:
		return
	card.preview_force_front = not card.is_faceup
	card.preview_locked = true
	cfc.NMAP.main.focus_card(card)


func _on_remote_card_hover_exited(card: Card) -> void:
	if not is_instance_valid(card):
		return
	card.preview_force_front = false
	card.preview_locked = false
	if cfc.NMAP.has("main") and cfc.NMAP.main:
		cfc.NMAP.main.unfocus(card)


func _on_remote_card_gui_input(event, card: Card) -> void:
	if not _active or not is_instance_valid(card) \
			or not card.remote_draggable:
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != BUTTON_LEFT or not event.pressed:
		return
	_remote_drag_card = card
	_remote_drag_offset = card.get_global_mouse_position() \
			- card.global_position
	card.z_index = 100


func _update_remote_drag() -> void:
	if not is_instance_valid(_remote_drag_card):
		_remote_drag_card = null
		return
	if Input.is_mouse_button_pressed(BUTTON_LEFT):
		var target := _remote_drag_card.get_global_mouse_position() \
				- _remote_drag_offset
		_remote_drag_card.global_position = target
		_remote_drag_card._target_position = target
		return
	var card := _remote_drag_card
	_remote_drag_card = null
	card.z_index = 0
	var meta = _remote_meta.get(str(card.network_id), {})
	var zone := str(meta.get("zone", "board"))
	if not zone in ["board", "scenario"]:
		return
	var travel := Vector2(0.5, 0.5)
	var slot_index := -1
	if zone == "board":
		travel = _owner_travel_for_mirror(card.global_position)
		slot_index = _mirror_slot_at(card.global_position)
	if _drop_mirror_locally(card, zone, slot_index):
		return
	if not _can_send():
		return
	var request := {
		"t": "mp_card_move_request",
		"id": str(card.network_id),
		"zone": zone,
		"x": travel.x,
		"y": travel.y,
	}
	if slot_index >= 0:
		request["slot"] = slot_index
	Rede.send_message(request)


# The mirror lives in the opponent band, which is the owner grid turned 180
# degrees, so a drop has to be reported in the owner's own frame. The dragged
# position is the corner of a slot-sized card, hence the half slot shift.
func _owner_travel_for_mirror(point: Vector2) -> Vector2:
	var scene := _opponent_scene()
	var grid := _scene_grid()
	if not scene or not grid or scene.rect_size.x <= 0.0 \
			or scene.rect_size.y <= 0.0:
		return Vector2(0.5, 0.5)
	var travel: Vector2 = (point + _half_slot(grid) \
			- scene.rect_global_position) / scene.rect_size
	return Vector2(clamp(1.0 - travel.x, 0.0, 1.0),
			clamp(1.0 - travel.y, 0.0, 1.0))


# Slot of the opponent band a mirrored drop lines up with, or -1 when the card
# was released outside the band.
func _mirror_slot_at(point: Vector2) -> int:
	var scene := _opponent_scene()
	var grid := _scene_grid()
	if not scene or not grid:
		return -1
	var center := point + _half_slot(grid)
	if not Rect2(scene.rect_global_position, scene.rect_size).has_point(center):
		return -1
	var best := -1
	var best_distance := INF
	for index in range(grid.get_slot_count()):
		var mirrored := _mirrored_slot_rect(index)
		if mirrored.size.x <= 0.0:
			continue
		var distance: float = (mirrored.position + mirrored.size * 0.5) \
				.distance_to(center)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


# A mirrored scene card is drawn at the slot size, and the dragged position is
# its corner, so the corner plus half a slot is the point both sides agree on.
func _half_slot(grid: BoardPlacementGrid) -> Vector2:
	if grid.get_slot_count() == 0:
		return Vector2.ZERO
	return grid.get_slot(0).rect_size * 0.5


# Normalized centre of a local scene slot in the owner's frame, so the travel
# that accompanies a slot always agrees with it.
func _slot_travel(index: int) -> Vector2:
	var grid := _scene_grid()
	if not grid or index < 0 or index >= grid.get_slot_count():
		return Vector2(0.5, 0.5)
	var slot: Control = grid.get_slot(index)
	return _normalize_board_position(slot.rect_global_position \
			+ slot.rect_size * 0.5)


# In the hotseat both seats live in this process, so there is no owner to ask:
# the ghost settles on the slot it was dropped on and the slot travels with the
# public state when the seats are swapped. Returns true when the drop was
# handled here and no request should cross the relay.
func _drop_mirror_locally(card: Card, zone: String, slot_index: int) -> bool:
	if not Multiplayer.is_solo() or _suppressed or not _active \
			or not Multiplayer.is_playing():
		return false
	if zone != "board" or slot_index < 0:
		_restore_mirror_position(card)
		return true
	var meta = _remote_meta.get(str(card.network_id), {})
	if typeof(meta) != TYPE_DICTIONARY:
		return true
	var mirrored := _mirrored_slot_rect(slot_index)
	if mirrored.size.x <= 0.0:
		return true
	card.global_position = mirrored.position
	card._target_position = mirrored.position
	meta["slot"] = slot_index
	var travel := _slot_travel(slot_index)
	meta["x"] = travel.x
	meta["y"] = travel.y
	return true


# A mirrored drop that misses every slot goes back to where the recorded state
# keeps it, instead of staying stranded between the two bands.
func _restore_mirror_position(card: Card) -> void:
	var meta = _remote_meta.get(str(card.network_id), {})
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var zone := str(meta.get("zone", "board"))
	var travel := Vector2(float(meta.get("x", 0.5)), float(meta.get("y", 0.5)))
	var target := _target_for_remote(zone, travel, str(card.network_id),
			int(meta.get("slot", -1)))
	card.global_position = target
	card._target_position = target


func _apply_move_request(data: Dictionary) -> void:
	if not _active or not Multiplayer.is_playing():
		return
	var net_id := str(data.get("id", ""))
	var zone := str(data.get("zone", "board"))
	if net_id.empty() or not zone in ["board", "scenario"]:
		return
	var card: Card = null
	for candidate in get_tree().get_nodes_in_group("cards"):
		if candidate is Card and is_instance_valid(candidate) \
				and not candidate.network_mirror \
				and Multiplayer.ensure_card_id(candidate) == net_id:
			card = candidate
			break
	if not card or _zone_for_card(card) != zone:
		return
	var board: Control = cfc.NMAP.board
	var slot: BoardPlacementSlot = null
	if zone == "board":
		var grid: BoardPlacementGrid = board.get_node_or_null(
				"PlacementGridDemo")
		if grid:
			slot = _requested_board_slot(grid, data, card)
	else:
		var scenario_grid: BoardPlacementGrid = board.get_node_or_null(
				"ModifiedLabelGrid")
		if scenario_grid and scenario_grid.get_slot_count() > 0:
			var scenario_slot := scenario_grid.get_slot(0)
			if not scenario_slot.occupying_card \
					or scenario_slot.occupying_card == card:
				slot = scenario_slot
	if not slot:
		_send_card_state(card, zone)
		return
	if card._placement_slot and card._placement_slot != slot:
		card._placement_slot.occupying_card = null
	slot.occupying_card = card
	card._placement_slot = slot
	card.global_position = slot.rect_global_position
	card._target_position = card.global_position
	_send_card_state(card, zone)


# The mirror names the slot its drop lined up with. The normalized travel is
# only the fallback for a drop that missed every slot of the opponent band, or
# for a request coming from a client whose grid has a different shape.
func _requested_board_slot(grid: BoardPlacementGrid, data: Dictionary,
		card: Card) -> BoardPlacementSlot:
	var slots := grid.get_all_slots()
	var wanted := int(data.get("slot", -1))
	if wanted >= 0 and wanted < slots.size():
		var requested: BoardPlacementSlot = slots[wanted]
		if is_instance_valid(requested) \
				and (not requested.occupying_card \
						or requested.occupying_card == card):
			return requested
	var travel := Vector2(
			clamp(float(data.get("x", 0.5)), 0.0, 1.0),
			clamp(float(data.get("y", 0.5)), 0.0, 1.0))
	var target := grid.rect_global_position \
			+ Vector2(travel.x * grid.rect_size.x, travel.y * grid.rect_size.y)
	var best: BoardPlacementSlot = null
	var best_distance := INF
	for candidate_slot in slots:
		if candidate_slot.occupying_card \
				and candidate_slot.occupying_card != card:
			continue
		var center: Vector2 = candidate_slot.rect_global_position \
				+ candidate_slot.rect_size * 0.5
		var distance := center.distance_to(target)
		if distance < best_distance:
			best_distance = distance
			best = candidate_slot
	return best


func _connect_view_button(node_name: String, zone: String) -> void:
	var board: Control = cfc.NMAP.board
	if not board:
		return
	var button: Button = board.get_node_or_null(
			"OpponentFieldVisual/" + node_name)
	if button and not button.is_connected(
			"pressed", self, "_show_remote_zone_cards"):
		button.connect("pressed", self, "_show_remote_zone_cards", [zone])


func _show_remote_zone_cards(zone: String) -> void:
	var board: Control = cfc.NMAP.board
	if not board:
		return
	var names := []
	for net_id in _remote_meta:
		var meta = _remote_meta[net_id]
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		if str(meta.get("zone", "")) != zone:
			continue
		var card_name := str(meta.get("name", ""))
		if cfc.card_definitions.has(card_name):
			names.append(card_name)
	if names.empty():
		if board.has_method("show_resource_message"):
			board.show_resource_message(
					"O oponente não tem cartas nesta área.")
		return
	var window = SELECTION_WINDOW_SCENE.instance()
	board.add_child(window)
	window.connect("confirmed", window, "queue_free")
	window.initiate_selection(names, 0, "display", false)
	window.window_title = "Prêmios do oponente" if zone == "prizes" \
			else "Recursos do oponente"


func _update_remote_zone_labels() -> void:
	var board: Control = cfc.NMAP.board
	if not board:
		return
	var total_energy := 0
	for net_id in _remote_meta:
		var meta = _remote_meta[net_id]
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		if str(meta.get("zone", "")) != "prizes":
			continue
		var card = _remote_cards.get(net_id)
		if is_instance_valid(card):
			total_energy += str(
					card.properties.get("ENERGIA", "0")).to_int()
	var prizes_label: Label = board.get_node_or_null(
			"OpponentFieldVisual/OpponentPrizesLabel")
	if prizes_label:
		prizes_label.text = "Prêmios: " + str(total_energy)
	if Multiplayer.is_session_active() \
			and board.has_method("report_prize_energy"):
		board.report_prize_energy(Multiplayer.opponent_slot, total_energy)
	var resources_label: Label = board.get_node_or_null(
			"OpponentFieldVisual/OpponentResourcesLabel")
	if resources_label:
		resources_label.text = "Recursos/Descarte (" \
				+ str(_remote_zone_order["resources"].size()) + ")"


func _remember_remote_meta(
		net_id: String,
		zone: String,
		card_name: String,
		travel: Vector2,
		rotation: int,
		face: bool,
		host_id: String,
		claim := 0,
		slot := -1) -> void:
	var previous = _remote_meta.get(net_id, {})
	if typeof(previous) == TYPE_DICTIONARY:
		var old_zone := str(previous.get("zone", ""))
		if old_zone in _remote_zone_order and old_zone != zone:
			_remote_zone_order[old_zone].erase(net_id)
	_remote_meta[net_id] = {
		"zone": zone,
		"name": card_name,
		"x": travel.x,
		"y": travel.y,
		"slot": slot,
		"rot": rotation,
		"face": 1 if face else 0,
		"host": host_id,
		"claim": claim,
	}
	if zone in _remote_zone_order \
			and not net_id in _remote_zone_order[zone]:
		_remote_zone_order[zone].append(net_id)


func _apply_remote_counts(data: Dictionary) -> void:
	var hand := int(data.get("hand", 0))
	var deck := int(data.get("deck", 0))
	if hand < 0 or deck < 0:
		return
	Multiplayer.set_opponent_counts({"hand": hand, "deck": deck})


func _apply_remote_zone(zone: String) -> void:
	if not _active:
		return
	if zone == _remote_zone:
		return
	_remote_zone = zone
	_place_lens()


# The opponent pointer never leaves their own half, so presence travels as a
# zone name only and is drawn as a lens over the mirrored box on this side.
func _send_zone_presence() -> void:
	var zone := _local_mouse_zone()
	if zone == _sent_zone:
		return
	_sent_zone = zone
	Rede.send_message({"t": "mp_zone", "zone": zone})


func set_solo_preview(value: bool) -> void:
	_solo_preview = value
	if not value:
		_hide_lens()


# The hotseat has no peer to report to, so the local zone drives the lens
# directly: hovering a zone shows what the other client would draw over the
# mirrored box of that same zone.
func _preview_zone_presence() -> void:
	if not _active:
		return
	_apply_remote_zone(_local_mouse_zone())


func _local_mouse_zone() -> String:
	var board: Control = cfc.NMAP.board
	if not board:
		return ""
	return _zone_at(board.get_global_mouse_position())


# The local piles are matched before the hand because the hand band stretches
# under them, so a point over the deck belongs to the deck and not the hand.
func _zone_at(point: Vector2) -> String:
	var board: Control = cfc.NMAP.board
	if not board:
		return ""
	var scenario: Control = board.get_node_or_null("ModifiedLabelGrid")
	if _contains_global(scenario, point):
		return "scenario"
	if _contains_global(_container_area(board.get_node_or_null("Prêmios")), point):
		return "prizes"
	for entry in [["deck", "deck"], ["discard", "resources"], ["hand", "hand"]]:
		if _contains_global(_container_area(cfc.NMAP.get(entry[0], null)), point):
			return entry[1]
	return ""


# Hand and piles are Area2D containers whose clickable box is a Control child.
func _container_area(container) -> Control:
	if container is Control:
		return container
	if container and container.has_node("Control"):
		return container.get_node("Control") as Control
	return null


func _contains_global(area: Control, point: Vector2) -> bool:
	if not area:
		return false
	return Rect2(area.rect_global_position, area.rect_size).has_point(point)


func _place_lens() -> void:
	var target := _lens_target()
	if not target:
		_hide_lens()
		return
	_lens.rect_global_position = target.rect_global_position - Vector2(4, 4)
	_lens.rect_size = target.rect_size + Vector2(8, 8)
	_lens.modulate.a = 1.0
	_lens_time = 0.0
	_lens.visible = true
	_lens.raise()


func _hide_lens() -> void:
	if _lens and is_instance_valid(_lens):
		_lens.visible = false


func _lens_target() -> Control:
	var board: Control = cfc.NMAP.board
	if not board:
		return null
	var visual: Control = board.get_node_or_null("OpponentFieldVisual")
	if not visual:
		return null
	match _remote_zone:
		"hand":
			return visual.get_node_or_null(
					"OpponentHandBackground") as Control
		"deck":
			return visual.get_node_or_null("OpponentDeck") as Control
		"resources":
			return visual.get_node_or_null(
					"OpponentResourcesBackground") as Control
		"prizes":
			return visual.get_node_or_null("OpponentPrizes") as Control
		"scenario":
			return visual.get_node_or_null("OpponentScenario") as Control
	return null


func _update_lens(delta: float) -> void:
	if not is_instance_valid(_lens) or not _lens.visible:
		return
	_lens_time += delta
	_lens.modulate.a = 0.65 + 0.35 * sin(_lens_time * LENS_PULSE_SPEED)


#-----------------------------------------------------------------------------
# Public snapshot for checkpoints and restoration
#-----------------------------------------------------------------------------

func build_public_card_entries(my_slot: int, opponent_slot: int) -> Dictionary:
	var cards := []
	var definitions := {}
	for card in get_tree().get_nodes_in_group("cards"):
		if not (card is Card) or not is_instance_valid(card) \
				or not card.is_inside_tree() or card.network_mirror:
			continue
		var zone := _zone_for_card(card)
		if zone in HIDDEN_ZONES:
			continue
		cards.append(_local_entry(card, zone, my_slot))
		_add_definition(definitions, card.definition_key())
	for net_id in _remote_cards:
		var card = _remote_cards[net_id]
		if not is_instance_valid(card):
			continue
		var meta = _remote_meta.get(net_id, {})
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		var zone := str(meta.get("zone", "board"))
		if zone in HIDDEN_ZONES:
			continue
		var card_name := str(meta.get("name", card.definition_key()))
		cards.append({
			"id": net_id,
			"owner": opponent_slot,
			"zone": zone,
			"name": card_name,
			"x": float(meta.get("x", 0.5)),
			"y": float(meta.get("y", 0.5)),
			"slot": int(meta.get("slot", -1)),
			"rot": int(meta.get("rot", 0)),
			"face": int(meta.get("face", 1)),
			"host": str(meta.get("host", "")),
			"claim": int(meta.get("claim", 0)),
		})
		_add_definition(definitions, card_name)
	return {"cards": cards, "definitions": definitions}


func apply_public_snapshot(public_state: Dictionary, opponent_slot: int) -> void:
	_clear_remote_cards()
	_clear_hand_placeholders()
	_apply_definitions(public_state.get("definitions", {}))
	var cards = public_state.get("cards", [])
	if typeof(cards) == TYPE_ARRAY:
		for entry in cards:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if int(entry.get("owner", 0)) != opponent_slot:
				continue
			_apply_remote_card(_entry_as_message(entry))
	var hidden = public_state.get("hidden", {})
	var counts = {}
	if typeof(hidden) == TYPE_DICTIONARY:
		counts = hidden.get(str(opponent_slot), {})
	if typeof(counts) != TYPE_DICTIONARY:
		counts = {}
	set_hidden_counts(int(counts.get("hand", 0)), int(counts.get("deck", 0)), true)


func find_remote_card(net_id: String) -> Card:
	var card = _remote_cards.get(net_id)
	if is_instance_valid(card):
		return card
	return null


func set_hidden_counts(hand_count: int, deck_count: int, force := false) -> void:
	hand_count = max(0, hand_count)
	deck_count = max(0, deck_count)
	if not force \
			and hand_count == int(_last_hidden_counts["hand"]) \
			and deck_count == int(_last_hidden_counts["deck"]):
		return
	_last_hidden_counts = {"hand": hand_count, "deck": deck_count}
	_refresh_hand_placeholders(hand_count)
	_update_opponent_labels(hand_count, deck_count)


#-----------------------------------------------------------------------------
# Local signal hooks
#-----------------------------------------------------------------------------

func _on_new_card(card) -> void:
	if cfc.ut or _spawning_remote or not (card is Card):
		return
	if card.network_mirror or not Multiplayer.is_session_active():
		return
	Multiplayer.ensure_card_id(card)


func _on_card_signal(card, trigger: String, details: Dictionary) -> void:
	if not (card is Card) or not is_instance_valid(card) \
			or card.network_mirror:
		return
	var tags = details.get("tags", [])
	if typeof(tags) == TYPE_ARRAY and "net" in tags:
		return
	# The hotseat has no peer to send to, but it still needs the claim: the
	# opponent's scenario is a mirror here and only this step takes it off the
	# arena, the same move the other client would echo back.
	if _active and trigger == "card_moved_to_board" \
			and _zone_for_card(card) == "scenario":
		_register_local_scenario(card)
	if not _can_send():
		return
	_counts_dirty = true
	match trigger:
		"card_moved_to_hand":
			_send_hidden_card(card)
		"card_moved_to_pile":
			var zone := _pile_zone(str(details.get("destination", "")))
			if zone in HIDDEN_ZONES:
				_send_hidden_card(card)
			else:
				_send_card_state_soon(card)
		"card_moved_to_board":
			_send_card_state_soon(card)
		"card_rotated", "card_flipped", "card_attached", "card_unattached":
			var visible_zone := _zone_for_card(card)
			if visible_zone in HIDDEN_ZONES:
				_send_hidden_card(card)
			else:
				_send_card_state(card, visible_zone)


func _on_peer_disconnected() -> void:
	_remote_zone = ""
	_hide_lens()


func _on_session_ended(_message: String) -> void:
	stop_mirroring()


#-----------------------------------------------------------------------------
# Scenario uniqueness
#-----------------------------------------------------------------------------

# Returns true when a scenario claim beats the scenario currently on the local
# field. Equal claims happen when both players play at nearly the same time;
# the host keeps the active scenario in that case.
func scenario_claim_wins(
		claim: int,
		local_claim: int,
		remote_is_host: bool) -> bool:
	if claim != local_claim:
		return claim > local_claim
	return remote_is_host


func _register_local_scenario(card: Card) -> void:
	var net_id := Multiplayer.ensure_card_id(card)
	if net_id.empty():
		return
	_scenario_clock = max(_scenario_clock, _active_remote_scenario_claim()) + 1
	_scenario_claims[net_id] = _scenario_clock
	# A newly played scenario always has a newer claim than the mirrored one,
	# so the opponent's scenario goes to its owner's discard.
	var remote := _active_remote_scenario()
	if remote:
		_move_remote_scenario_to_resources(str(remote.network_id))


func _accept_remote_scenario(net_id: String, claim: int) -> bool:
	_scenario_clock = max(_scenario_clock, claim)
	var meta = _remote_meta.get(net_id, {})
	if typeof(meta) == TYPE_DICTIONARY \
			and str(meta.get("zone", "")) == "scenario":
		return true
	var local := _local_active_scenario()
	if not local:
		_drop_other_remote_scenarios(net_id)
		return true
	var local_claim := int(_scenario_claims.get(str(local.network_id), 0))
	var remote_is_host := Multiplayer.my_slot != 1
	if not scenario_claim_wins(claim, local_claim, remote_is_host):
		return false
	# The opponent's scenario wins: ours goes to its owner's discard (ours).
	_discard_local_scenario(local)
	_drop_other_remote_scenarios(net_id)
	return true


func _drop_other_remote_scenarios(keep_id: String) -> void:
	for net_id in _remote_meta.keys():
		var meta = _remote_meta[net_id]
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		if str(meta.get("zone", "")) != "scenario" or str(net_id) == keep_id:
			continue
		_discard_remote_card(str(net_id))


func _discard_local_scenario(card: Card) -> void:
	if not is_instance_valid(card) or card.network_mirror:
		return
	_scenario_claims.erase(str(card.network_id))
	card.move_to(cfc.NMAP.discard)


# The losing scenario goes to its owner's discard. The owner confirms the move
# with a normal zone update; moving the mirror immediately keeps checkpoints
# from briefly losing the card while that update travels.
func _move_remote_scenario_to_resources(net_id: String) -> void:
	var card = _remote_cards.get(net_id)
	if not is_instance_valid(card):
		return
	_apply_remote_card({
		"t": "mp_card",
		"id": net_id,
		"zone": "resources",
		"name": card.definition_key(),
		"x": 0.5,
		"y": 0.5,
		"rot": int(card.card_rotation),
		"face": 1 if card.is_faceup else 0,
		"host": "",
		"claim": 0,
	})


func _local_active_scenario() -> Card:
	var tree := get_tree()
	if not tree or not cfc.NMAP.has("board"):
		return null
	for card in tree.get_nodes_in_group("cards"):
		if not (card is Card) or not is_instance_valid(card) \
				or card.network_mirror:
			continue
		if card.get_parent() == cfc.NMAP.board \
				and _zone_for_card(card) == "scenario":
			return card
	return null


func _active_remote_scenario() -> Card:
	for net_id in _remote_meta.keys():
		var meta = _remote_meta[net_id]
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		if str(meta.get("zone", "")) != "scenario":
			continue
		var card = _remote_cards.get(net_id)
		if is_instance_valid(card):
			return card
	return null


func _active_remote_scenario_claim() -> int:
	var card = _active_remote_scenario()
	if not card:
		return 0
	var meta = _remote_meta.get(str(card.network_id), {})
	if typeof(meta) != TYPE_DICTIONARY:
		return 0
	return int(meta.get("claim", 0))


# Reapplies the single-scenario rule after a checkpoint restore, where the
# opponent snapshot is applied before the local cards exist.
func reconcile_scenarios(public_state: Dictionary) -> void:
	if cfc.ut or not Multiplayer.is_session_active():
		return
	var cards = public_state.get("cards", [])
	if typeof(cards) != TYPE_ARRAY:
		cards = []
	var local_claim := 0
	var local := _local_active_scenario()
	if local:
		var local_id := str(local.network_id)
		local_claim = int(_scenario_claims.get(local_id, 0))
		for entry in cards:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if int(entry.get("owner", 0)) != Multiplayer.my_slot:
				continue
			if str(entry.get("id", "")) != local_id:
				continue
			local_claim = int(entry.get("claim", local_claim))
			break
		_scenario_claims[local_id] = local_claim
		_scenario_clock = max(_scenario_clock, local_claim)
	var remote := _active_remote_scenario()
	if remote:
		_scenario_clock = max(_scenario_clock, _active_remote_scenario_claim())
	if not local or not remote:
		return
	var remote_claim := _active_remote_scenario_claim()
	var remote_is_host := Multiplayer.my_slot != 1
	if scenario_claim_wins(remote_claim, local_claim, remote_is_host):
		_discard_local_scenario(local)
	else:
		_move_remote_scenario_to_resources(str(remote.network_id))


#-----------------------------------------------------------------------------
# Zone / position helpers
#-----------------------------------------------------------------------------

func _zone_for_card(card: Card) -> String:
	var parent = card.get_parent()
	if not parent:
		return "board"
	if "CardPopUpSlot" in str(parent.name):
		var pile := _pile_ancestor(parent)
		if pile:
			return _pile_zone(str(pile.name))
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
	if parent is Pile:
		return _pile_zone(str(parent.name))
	return "board"


func _pile_ancestor(node) -> Pile:
	var current = node
	for _i in range(8):
		if current == null or not is_instance_valid(current):
			return null
		if current is Pile:
			return current
		current = current.get_parent()
	return null


func _pile_zone(pile_name: String) -> String:
	var lowered := pile_name.to_lower()
	if "prêm" in lowered or "prem" in lowered:
		return "prizes"
	if "deck" in lowered:
		return "deck"
	if "mão" in lowered or "mao" in lowered:
		return "hand"
	return "resources"


func _normalize_board_position(global_pos: Vector2) -> Vector2:
	var board: Control = cfc.NMAP.board
	if not board:
		return Vector2(0.5, 0.5)
	var grid: Control = board.get_node_or_null("PlacementGridDemo")
	if not grid or grid.rect_size.x <= 0 or grid.rect_size.y <= 0:
		return Vector2(
				clamp(global_pos.x / board.rect_size.x, 0.0, 1.0),
				clamp(global_pos.y / board.rect_size.y, 0.0, 1.0))
	var relative: Vector2 = (global_pos - grid.rect_global_position) \
			/ grid.rect_size
	return Vector2(clamp(relative.x, 0.0, 1.0), clamp(relative.y, 0.0, 1.0))


func _scene_grid() -> BoardPlacementGrid:
	var board: Control = cfc.NMAP.board
	if not board:
		return null
	return board.get_node_or_null("PlacementGridDemo") as BoardPlacementGrid


func _opponent_scene() -> Control:
	var board: Control = cfc.NMAP.board
	if not board:
		return null
	var visual: Control = board.get_node_or_null("OpponentFieldVisual")
	if not visual:
		return null
	return visual.get_node_or_null("OpponentScene") as Control


# Index of a slot inside the local scene grid, or -1 for a card that is not
# sitting on one.
func _slot_index(slot) -> int:
	var grid := _scene_grid()
	if not grid or not is_instance_valid(slot) \
			or not (slot is BoardPlacementSlot):
		return -1
	return grid.get_all_slots().find(slot)


# The two scene bands are the same box seen from opposite sides of the table,
# so a slot mirrors by turning 180 degrees around the box centre. The owner's
# front row, nearest the middle line on their screen, lands on the row nearest
# the middle line here, which is what makes the two fields face each other.
# An empty rect means the slot could not be mirrored.
func _mirrored_slot_rect(index: int) -> Rect2:
	var grid := _scene_grid()
	var scene := _opponent_scene()
	if not grid or not scene or index < 0 \
			or grid.rect_size.x <= 0.0 or grid.rect_size.y <= 0.0:
		return Rect2()
	var slots := grid.get_all_slots()
	if index >= slots.size():
		return Rect2()
	var slot: Control = slots[index]
	if not is_instance_valid(slot):
		return Rect2()
	var offset: Vector2 = slot.rect_global_position - grid.rect_global_position
	return Rect2(scene.rect_global_position + scene.rect_size - offset \
			- slot.rect_size, slot.rect_size)


# A scene card that sits in one of the owner's slots is mirrored into the
# matching slot of the opponent band, so both fields keep the same geometry.
# A card that is not resting on a slot still lives in the owner's table space,
# so its mirror is the same box turned 180 degrees; only a travelling card
# without any table geometry falls back to the zone stack.
func _target_for_remote(zone: String, travel: Vector2, net_id: String,
		slot_index: int) -> Vector2:
	if zone == "board":
		if slot_index >= 0:
			var mirrored := _mirrored_slot_rect(slot_index)
			if mirrored.size.x > 0.0:
				return mirrored.position
		var point := _mirrored_board_point(travel,
				CFConst.CARD_SIZE * BOARD_SCALE)
		if point != Vector2.INF:
			return point
	return _position_for_remote(zone, travel, net_id)


# Point reflection of a table-space coordinate through the centre of the scene
# box, minus the room the drawn card takes on this side of the table. An INF
# result means the two bands are not laid out yet.
func _mirrored_board_point(travel: Vector2, display_size: Vector2) -> Vector2:
	var grid := _scene_grid()
	var scene := _opponent_scene()
	if not grid or not scene or not is_instance_valid(grid) \
			or not is_instance_valid(scene) or grid.rect_size.x <= 0.0 \
			or grid.rect_size.y <= 0.0 or scene.rect_size.x <= 0.0 \
			or scene.rect_size.y <= 0.0:
		return Vector2.INF
	var scaled := Vector2(
			display_size.x * scene.rect_size.x / grid.rect_size.x,
			display_size.y * scene.rect_size.y / grid.rect_size.y)
	return scene.rect_global_position + scene.rect_size \
			- Vector2(travel.x * scene.rect_size.x,
					travel.y * scene.rect_size.y) - scaled


func _position_for_remote(zone: String, travel: Vector2, net_id: String) -> Vector2:
	var board: Control = cfc.NMAP.board
	if not board:
		return Vector2.ZERO
	var visual: Control = board.get_node_or_null("OpponentFieldVisual")
	if not visual:
		return board.rect_global_position
	match zone:
		"resources":
			var resources: Control = visual.get_node_or_null(
					"OpponentResourcesBackground")
			if resources:
				return _stack_position(resources, "resources", net_id)
		"prizes":
			var prizes: Control = visual.get_node_or_null("OpponentPrizes")
			if prizes:
				return _stack_position(prizes, "prizes", net_id)
		"scenario":
			var scenario: Control = visual.get_node_or_null("OpponentScenario")
			if scenario:
				return _center_zone_position(
						scenario, 2, CFConst.CARD_SIZE * SCENARIO_SCALE,
						SCENARIO_LABEL_MARGIN)
		_:
			var scene: Control = visual.get_node_or_null("OpponentScene")
			if scene:
				return _map_zone_position(scene, travel, 0, 0,
						CFConst.CARD_SIZE * BOARD_SCALE,
						SCENE_ATTACHMENT_MARGIN)
	return board.rect_global_position


# The remote field is the opponent board rotated 180 degrees, so the travel
# coordinate is reversed on both axes. The card display size is reserved so
# the mirror never spills into the local player's half of the board.
func _map_zone_position(
		area: Control,
		travel: Vector2,
		margin_x: float,
		margin_top: float,
		display_size: Vector2,
		margin_bottom := 0.0) -> Vector2:
	var usable := Vector2(
			max(1.0, area.rect_size.x - margin_x * 2.0 - display_size.x),
			max(1.0, area.rect_size.y - margin_top - margin_bottom \
					- display_size.y))
	return area.rect_global_position + Vector2(margin_x, margin_top) \
			+ Vector2((1.0 - travel.x) * usable.x,
					(1.0 - travel.y) * usable.y)


func _center_zone_position(
		area: Control,
		top_margin: float,
		display_size: Vector2,
		bottom_margin := 0.0) -> Vector2:
	var available_y := max(
			0.0, area.rect_size.y - top_margin - bottom_margin - display_size.y)
	return area.rect_global_position + Vector2(
			max(0.0, (area.rect_size.x - display_size.x) * 0.5),
			top_margin + available_y * 0.5)


func _stack_position(area: Control, zone: String, net_id: String) -> Vector2:
	var order: Array = _remote_zone_order.get(zone, [])
	var index := order.find(net_id)
	if index < 0:
		index = 0
	var columns := 3
	var column_step := 40.0
	var row_step := 16.0
	var origin := Vector2(8, 4)
	if zone == "resources":
		var size: Vector2 = CFConst.CARD_SIZE * _resources_grid_scale()
		columns = RESOURCES_GRID_COLUMNS
		column_step = size.x + RESOURCES_GRID_GAP
		row_step = size.y + RESOURCES_GRID_GAP
		origin = Vector2(
				max(0.0, (area.rect_size.x - (columns * size.x
						+ (columns - 1) * RESOURCES_GRID_GAP)) * 0.5),
				4.0)
		# The newest card fills the first cell, like the local pile's top card.
		index = max(0, order.size() - 1 - index)
	if zone == "prizes":
		columns = 4
		column_step = 26.0
		row_step = 11.0
		origin = Vector2(6, 0)
	var column := index % columns
	var row := int(index / columns)
	return area.rect_global_position + origin \
			+ Vector2(column * column_step, row * row_step)


func _scale_for_zone(zone: String) -> float:
	match zone:
		"resources":
			return _resources_grid_scale()
		"prizes":
			return PRIZES_SCALE
		"scenario":
			return SCENARIO_SCALE
		_:
			return BOARD_SCALE


# The local pile lays its miniatures in three columns with a 6 px gap inside the
# authored resources panel; the mirror uses the same numbers so both read alike.
func _resources_grid_scale() -> float:
	var width := _resources_base_width()
	return clamp(
			(width - 12.0 - 2.0 * RESOURCES_GRID_GAP) \
					/ (RESOURCES_GRID_COLUMNS * CFConst.CARD_SIZE.x),
			0.26, 0.4)


func _update_remote_resources() -> void:
	_relayout_remote_resources()
	_update_resource_preview()


# The local grid previews the card under the pointer itself, so the mirrored
# grid follows the same rule instead of the Area2D hover.
func _update_resource_preview() -> void:
	var hovered: Card = null
	if not cfc.card_drag_ongoing and not _suppressed:
		var area := _resources_area()
		if area:
			var mouse: Vector2 = area.get_global_mouse_position()
			var size: Vector2 = CFConst.CARD_SIZE * _resources_grid_scale()
			for net_id in _remote_zone_order["resources"]:
				var card: Card = _remote_cards.get(net_id)
				if not is_instance_valid(card) or not card.visible:
					continue
				if Rect2(card.global_position, size).has_point(mouse):
					hovered = card
	_set_resource_preview(hovered)


func _set_resource_preview(card: Card) -> void:
	if card == _resource_preview:
		return
	if is_instance_valid(_resource_preview):
		_resource_preview.preview_force_front = false
		_resource_preview.preview_locked = false
		if cfc.NMAP.has("main") and cfc.NMAP.main:
			cfc.NMAP.main.unfocus(_resource_preview)
	_resource_preview = card
	if not is_instance_valid(card) or cfc.ut \
			or not cfc.NMAP.has("main") or not cfc.NMAP.main:
		return
	card.preview_force_front = not card.is_faceup
	# Without the lock the mirror's own state machine unfocuses the closeup on
	# the very next frame, which is why the grid hover used to show nothing.
	card.preview_locked = true
	cfc.NMAP.main.focus_card(card)


# The panel width is authored in CGFBoard.tscn, so the grid never falls back to
# a hardcoded size that the scene would not be able to change.
func _resources_base_width() -> float:
	var board = cfc.NMAP.get("board", null)
	if board and board.has_method("resources_base_width"):
		return board.resources_base_width()
	return 156.0


func _relayout_remote_resources() -> void:
	var area := _resources_area()
	if not area:
		return
	var card_scale := _resources_grid_scale()
	var order: Array = _remote_zone_order["resources"]
	for index in range(order.size()):
		var card: Card = _remote_cards.get(order[index])
		if not is_instance_valid(card):
			continue
		if index < order.size() - RESOURCES_GRID_MAX:
			card.visible = false
			continue
		card.visible = true
		var target_scale := Vector2(card_scale, card_scale)
		if not card.scale.is_equal_approx(target_scale):
			card.scale = target_scale
		card.position = _stack_position(area, "resources", order[index])


func _resources_area() -> Control:
	var board: Control = cfc.NMAP.board
	if not board:
		return null
	var area: Control = board.get_node_or_null(
			"OpponentFieldVisual/OpponentResourcesBackground")
	return area


#-----------------------------------------------------------------------------
# Remote card lifecycle
#-----------------------------------------------------------------------------

func _instance_named_card(net_id: String, card_name: String) -> Card:
	if not cfc.card_definitions.has(card_name):
		return null
	if not cfc.NMAP.has("board"):
		return null
	_spawning_remote = true
	var card = cfc.instance_card(card_name)
	_spawning_remote = false
	if not card:
		return null
	card.network_id = net_id
	cfc.NMAP.board.add_child(card)
	_configure_remote_card(card)
	_remote_cards[net_id] = card
	return card


func _configure_remote_card(card: Card) -> void:
	card.network_mirror = true
	# A mirror only exists for zones the local player can read, so its front is
	# fair game for the hover preview and for the log.
	card.was_public = true
	if card.is_in_group("cards"):
		card.remove_from_group("cards")
	if not card.is_in_group("remote_cards"):
		card.add_to_group("remote_cards")
	card.monitoring = false
	card.monitorable = false
	card.set_control_mouse_filters(false)
	if card.buttons:
		card.buttons.set_active(false)


func _discard_remote_card(net_id: String) -> void:
	var card = _remote_cards.get(net_id)
	if is_instance_valid(card):
		card.queue_free()
	_remote_cards.erase(net_id)
	_remote_meta.erase(net_id)
	for zone in _remote_zone_order:
		_remote_zone_order[zone].erase(net_id)
	_sent_visible.erase(net_id)
	if _remote_drag_card == card:
		_remote_drag_card = null
	_update_remote_zone_labels()


func _remove_remote_card(net_id: String) -> void:
	if net_id.empty():
		return
	_discard_remote_card(net_id)


func _clear_remote_cards() -> void:
	_set_resource_preview(null)
	for net_id in _remote_cards.keys():
		_discard_remote_card(net_id)
	_remote_cards.clear()
	_remote_meta.clear()
	_remote_zone_order = {"resources": [], "prizes": []}
	_update_remote_zone_labels()


#-----------------------------------------------------------------------------
# Hand / deck placeholders
#-----------------------------------------------------------------------------

func _refresh_hand_placeholders(hand_count: int) -> void:
	var target := min(hand_count, MAX_HAND_PLACEHOLDERS)
	while _hand_placeholders.size() > target:
		var card = _hand_placeholders.pop_back()
		if is_instance_valid(card):
			card.queue_free()
	while _hand_placeholders.size() < target:
		var card = _create_hand_placeholder()
		if not card:
			break
		_hand_placeholders.append(card)
	_layout_hand_placeholders()


func _create_hand_placeholder() -> Card:
	var dummy_name := _dummy_card_name()
	if dummy_name.empty() or not cfc.NMAP.has("board"):
		return null
	_spawning_remote = true
	var card = cfc.instance_card(dummy_name)
	_spawning_remote = false
	if not card:
		return null
	card.network_mirror = true
	if card.is_in_group("cards"):
		card.remove_from_group("cards")
	card.add_to_group("remote_cards")
	card.monitoring = false
	card.monitorable = false
	card.set_control_mouse_filters(false)
	if card.buttons:
		card.buttons.set_active(false)
	cfc.NMAP.board.add_child(card)
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	# warning-ignore:return_value_discarded
	card.set_is_faceup(false, true, false, ["net"])
	card.scale = Vector2(1, 1) * HAND_SCALE
	# warning-ignore:return_value_discarded
	card.set_card_rotation(180, false, false, false, ["net"])
	card.z_index = 1
	return card


func _layout_hand_placeholders() -> void:
	var board: Control = cfc.NMAP.board
	if not board or _hand_placeholders.empty():
		return
	var background: Control = board.get_node_or_null(
			"OpponentFieldVisual/OpponentHandBackground")
	if not background:
		return
	var count := _hand_placeholders.size()
	var card_width := CFConst.CARD_SIZE.x * HAND_SCALE
	var inner := max(card_width, background.rect_size.x - 20.0)
	var spacing := card_width
	if count > 1:
		spacing = min(card_width, (inner - card_width) / float(count - 1))
	var fan_width := card_width + spacing * float(count - 1)
	var origin := background.rect_global_position + Vector2(
			(background.rect_size.x - fan_width) * 0.5, 6)
	for index in range(count):
		var card = _hand_placeholders[index]
		if is_instance_valid(card):
			card.global_position = origin + Vector2(index * spacing, 0)


func _clear_hand_placeholders() -> void:
	for card in _hand_placeholders:
		if is_instance_valid(card):
			card.queue_free()
	_hand_placeholders.clear()


func _update_opponent_labels(hand_count: int, deck_count: int) -> void:
	var board: Control = cfc.NMAP.board
	if not board:
		return
	var hand_label: Label = board.get_node_or_null(
			"OpponentFieldVisual/OpponentHandLabel")
	if hand_label:
		hand_label.text = "Mão: " + str(hand_count) \
				+ " · Deck: " + str(deck_count)
	var visual: Control = board.get_node_or_null("OpponentFieldVisual")
	if visual:
		var field_label: Label = visual.get_node_or_null("OpponentFieldLabel")
		if field_label:
			var opponent := Multiplayer.get_opponent_username()
			if opponent.empty():
				opponent = "VISUAL"
			field_label.text = "CAMPO DO OPONENTE - " + opponent


#-----------------------------------------------------------------------------
# Definitions
#-----------------------------------------------------------------------------

func _add_definition(definitions: Dictionary, card_name: String) -> void:
	var definition = cfc.card_definitions.get(card_name, {})
	if typeof(definition) == TYPE_DICTIONARY and not definition.empty():
		definitions[card_name] = definition


func _apply_definitions(definitions) -> void:
	if typeof(definitions) != TYPE_DICTIONARY:
		return
	for card_name in definitions:
		if typeof(definitions[card_name]) == TYPE_DICTIONARY:
			cfc.card_definitions[str(card_name)] = definitions[card_name]


func _send_definition(card_name: String) -> void:
	if card_name.empty():
		return
	var definition = cfc.card_definitions.get(card_name, {})
	if typeof(definition) != TYPE_DICTIONARY or definition.empty():
		return
	Rede.send_message({
		"t": "mp_defs",
		"definitions": {card_name: definition},
	})


func _apply_remote_defs_waiting() -> void:
	for card_name in _pending_cards.keys():
		var pending = _pending_cards[card_name]
		_pending_cards.erase(card_name)
		if typeof(pending) != TYPE_ARRAY:
			continue
		for data in pending:
			if typeof(data) == TYPE_DICTIONARY:
				_apply_remote_card(data)


#-----------------------------------------------------------------------------
# Entries / counts
#-----------------------------------------------------------------------------

func _local_entry(card: Card, zone: String, owner: int) -> Dictionary:
	var net_id := Multiplayer.ensure_card_id(card)
	var entry := {
		"id": net_id,
		"owner": owner,
		"zone": zone,
		"name": card.definition_key(),
		"x": 0.5,
		"y": 0.5,
		"slot": -1,
		"rot": int(card.card_rotation),
		"face": 1 if card.is_faceup else 0,
		"host": "",
	}
	if zone == "board":
		var normalized := _normalize_board_position(card.global_position)
		entry["x"] = normalized.x
		entry["y"] = normalized.y
		entry["slot"] = _slot_index(card._placement_slot)
	if zone == "scenario":
		entry["claim"] = int(_scenario_claims.get(net_id, 0))
	if card.current_host_card and is_instance_valid(card.current_host_card):
		entry["host"] = Multiplayer.ensure_card_id(card.current_host_card)
	return entry


func _entry_as_message(entry: Dictionary) -> Dictionary:
	return {
		"t": "mp_card",
		"id": str(entry.get("id", "")),
		"zone": str(entry.get("zone", "board")),
		"name": str(entry.get("name", "")),
		"x": float(entry.get("x", 0.5)),
		"y": float(entry.get("y", 0.5)),
		"slot": int(entry.get("slot", -1)),
		"rot": int(entry.get("rot", 0)),
		"face": int(entry.get("face", 1)),
		"host": str(entry.get("host", "")),
		"claim": int(entry.get("claim", 0)),
	}


func _local_hidden_counts() -> Dictionary:
	return {
		"hand": _container_count(cfc.NMAP.get("hand", null)),
		"deck": _container_count(cfc.NMAP.get("deck", null)),
	}


func _container_count(container) -> int:
	if not container or not is_instance_valid(container):
		return 0
	if container is Pile and container.is_popup_open:
		var count := 0
		for card in container.pre_sorted_order:
			if is_instance_valid(card) and card is Card:
				count += 1
		return count
	var total := 0
	for child in container.get_children():
		if child is Card and is_instance_valid(child):
			total += 1
	return total


func _dummy_card_name() -> String:
	if cfc.card_definitions.has("Test Card 1"):
		return "Test Card 1"
	var names := cfc.card_definitions.keys()
	if names.empty():
		return ""
	return str(names[0])


#-----------------------------------------------------------------------------
# Zone lens
#-----------------------------------------------------------------------------

func _build_lens() -> void:
	if not cfc.NMAP.has("board"):
		return
	_lens = Panel.new()
	_lens.name = "OpponentZoneLens"
	_lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lens.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.83, 0.47, 0.10)
	style.border_color = Color(1.0, 0.83, 0.47, 0.95)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	_lens.add_stylebox_override("panel", style)
	cfc.NMAP.board.add_child(_lens)
