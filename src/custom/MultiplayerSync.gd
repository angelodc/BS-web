# Mirrors public card state to the opponent field and shows hidden counts.
#
# Only hand and deck are private. Prizes, resources, scenario and board are
# public and mirrored. Board coordinates travel normalized so both clients can
# use different viewport sizes. The remote presence reveals only which zone
# the opponent mouse is in, drawn as a lens over the mirrored zone.
extends Control

const SELECTION_WINDOW_SCENE = preload("res://src/core/SelectionWindow.tscn")
const _Snapshot = preload("res://src/core/table/TableSnapshot.gd")
const _Table = preload("res://src/core/table/TableState.gd")
const DRAG_SEND_INTERVAL := 0.08
const COUNTS_SEND_DELAY := 0.12
# A settled change travels as one complete public snapshot instead of a stream of
# per-card messages. The small delay coalesces a cascade (a character and the
# resources it carries, for instance) into a single rebuild on the other side,
# which is the same state a hotseat swap restores.
const SNAPSHOT_SEND_DELAY := 0.12
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
# The local resources panel puts its label above the mini grid, and the mirror
# uses the same arrangement so both read alike.
const RESOURCES_LABEL_BAND := 22.0
const RESOURCES_GRID_PADDING := 4.0
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
# The pointer as the engine delivers it to the GUI. The board is laid out in the
# 1280x720 viewport, but CanvasItem's global mouse position answers in window
# coordinates when the window is stretched: at 1384x805 the mirrored grid sat
# almost a hundred pixels away from its artwork, so the hover met empty space
# over the miniatures and previews above them. The localized input event is the
# same space the GUI hit-tests in, which is what the mirrored rects use.
var _pointer_pos := Vector2.ZERO
var _pointer_known := false
var _hand_placeholders := []
var _lens: Panel
var _lens_time := 0.0
var _remote_zone := ""
var _sent_zone := ""
var _solo_preview := false
var _drag_timer := 0.0
var _counts_timer := 0.0
var _sweep_timer := 0.0
var _snapshot_dirty := false
var _snapshot_timer := 0.0
# The rects the mirror laid out for each remote card, reused by the hover test
# so it reads the same geometry the card was drawn on.
var _remote_layout_rects := {}
var _counts_dirty := false
var _last_sent_counts := {"hand": -1, "deck": -1}
var _last_hidden_counts := {"hand": -1, "deck": -1}
# Scenarios are unique across both fields. Claims use a Lamport-style clock so
# the latest play wins even when both players act at nearly the same time.
var _scenario_clock := 0
var _scenario_claims := {}
# A resource travels before the character it sits under whenever the snapshot
# follows the spawn order, which is what every hotseat rebuild does. The link is
# kept here and retried until the host shows up, so the resource does not settle
# as a loose card in the opponent band.
var _pending_host_links := {}
var _resolving_hosts := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cfc.ut:
		return
	_build_lens()
	# warning-ignore:return_value_discarded
	Rede.message_received.connect(_on_network_message)
	# warning-ignore:return_value_discarded
	Rede.peer_disconnected.connect(_on_peer_disconnected)
	# warning-ignore:return_value_discarded
	Multiplayer.session_ended.connect(_on_session_ended)
	# warning-ignore:return_value_discarded
	cfc.signal_propagator.signal_received.connect(_on_card_signal)
	# warning-ignore:return_value_discarded
	cfc.new_card_instanced.connect(_on_new_card)
	_connect_view_button("OpponentResourcesView", "resources")
	_connect_view_button("OpponentPrizesView", "prizes")


func start_mirroring() -> void:
	if _active:
		return
	_active = true
	_counts_dirty = true
	_last_sent_counts = {"hand": -1, "deck": -1}
	_update_opponent_labels(0, 0)
	# The labels are authored with placeholder counts, so they only leave that
	# state once a card is applied. The hotseat has no peer to do it for us.
	_update_remote_zone_labels()


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


func _input(event) -> void:
	if event is InputEventMouse:
		_pointer_pos = event.position
		_pointer_known = true


# The pointer in the board's coordinate space. Until the first mouse event the
# global position is the only answer available, and it is already right when the
# window has no stretch.
func _pointer_position() -> Vector2:
	if _pointer_known:
		return _pointer_pos
	# A bare instance (tests, teardown) has no viewport to ask for the mouse.
	if not is_inside_tree():
		return Vector2.ZERO
	return get_global_mouse_position()


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
	_send_snapshot_tick(delta)
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
	_snapshot_dirty = false
	_snapshot_timer = 0.0
	_send_public_snapshot(true)
	send_counts()


# Every settled change is rebuilt from the whole public state, exactly like the
# hotseat rebuild. Per-card messages only carry the live drag, so the other side
# never has to reconcile a sequence of partial updates.
func _mark_snapshot_dirty() -> void:
	_snapshot_dirty = true
	_snapshot_timer = 0.0


func _send_snapshot_tick(delta: float) -> void:
	if not _snapshot_dirty:
		return
	_snapshot_timer += delta
	if _snapshot_timer < SNAPSHOT_SEND_DELAY:
		return
	_snapshot_dirty = false
	_snapshot_timer = 0.0
	_send_public_snapshot(false)
	send_counts()


# The definitions ride along only when the peer asked for a full sync, because a
# settled change usually re-sends the same cards the peer already knows.
func _send_public_snapshot(with_definitions: bool) -> void:
	var state := build_public_card_entries(Multiplayer.my_slot,
			Multiplayer.opponent_slot, false, with_definitions)
	var counts := _local_hidden_counts()
	var payload := {
		"t": "mp_snapshot",
		"slot": Multiplayer.my_slot,
		"cards": state.get("cards", []),
		"hand": int(counts["hand"]),
		"deck": int(counts["deck"]),
	}
	if with_definitions:
		payload["definitions"] = state.get("definitions", {})
		# A full sync is also the moment a peer that joined late learns the pins
		# already on the table.
		var pins = _pin_layer()
		if pins and pins.has_method("local_pin_state"):
			payload["pins"] = pins.local_pin_state()
	Rede.send_message(payload)


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


# Pins change only when someone drops, creates or clears one, so the whole list
# goes out at once and the peer rebuilds its copy of the other side's pins.
func send_pins_state(entries: Array) -> void:
	if not _can_send():
		return
	Rede.send_message({"t": "mp_pins", "pins": entries})


func _pin_layer():
	var board = cfc.NMAP.get("board", null)
	if not is_instance_valid(board):
		return null
	return board.get_node_or_null("NegationPins")


func _apply_remote_pins(entries) -> void:
	if not Multiplayer.is_session_active() or not (entries is Array):
		return
	var pins = _pin_layer()
	if pins and pins.has_method("apply_remote_pins"):
		pins.apply_remote_pins(entries)


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
	if net_id.is_empty():
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
		"offset": int(card.attachment_offset),
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
			var address := _board_address_for_slot(card._placement_slot)
			if not address.is_empty():
				payload["address"] = address
	if zone == "scenario":
		payload["claim"] = int(_scenario_claims.get(net_id, 0))
	if zone == "resources":
		# The pile index is what orders the local mini grid; the mirror cannot
		# rebuild that order from arrival alone, and a hotseat rebuild ships the
		# whole pile at once in spawn order.
		payload["pile"] = card.get_index()
	if card.current_host_card and is_instance_valid(card.current_host_card):
		payload["host"] = Multiplayer.ensure_card_id(card.current_host_card)
	var definition = cfc.card_definitions.get(card.definition_key(), {})
	if typeof(definition) == TYPE_DICTIONARY and not definition.is_empty():
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
	if _sent_visible.is_empty():
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


# Sends a local character to the opponent's prize area. The card leaves the
# local field; the receiver hosts it as one of its own prize cards.
func send_card_to_opponent_prizes(card: Card) -> bool:
	if not is_instance_valid(card) or card.network_mirror:
		return false
	var net_id := Multiplayer.ensure_card_id(card)
	if net_id.is_empty():
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
	if typeof(definition) == TYPE_DICTIONARY and not definition.is_empty():
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
		"mp_snapshot":
			_apply_remote_snapshot(data)
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
		"mp_pins":
			_apply_remote_pins(data.get("pins", []))


func _apply_remote_card(data: Dictionary) -> void:
	if not Multiplayer.is_session_active():
		return
	var net_id := str(data.get("id", ""))
	var zone := str(data.get("zone", "board"))
	var card_name := str(data.get("name", ""))
	if net_id.is_empty() or card_name.is_empty() \
			or (not zone in VISIBLE_ZONES and zone != "opponent_prizes"):
		return
	var definition = data.get("definition", {})
	if typeof(definition) == TYPE_DICTIONARY and not definition.is_empty():
		cfc.card_definitions[card_name] = definition
	if not cfc.card_definitions.has(card_name):
		if not _pending_cards.has(card_name):
			_pending_cards[card_name] = []
		var parked: Array = _pending_cards[card_name]
		# Snapshot retries park the same card again; keep the latest copy only,
		# so the list does not grow while the definition is on its way.
		var replaced := false
		for index in range(parked.size()):
			if str(parked[index].get("id", "")) == net_id:
				parked[index] = data.duplicate(true)
				replaced = true
				break
		if not replaced:
			parked.append(data.duplicate(true))
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
	var address := str(data.get("address", ""))
	var rotation := int(data.get("rot", 0))
	var face := int(data.get("face", 1)) == 1
	var host_id := str(data.get("host", ""))
	var pile_index := int(data.get("pile", -1))
	var offset := int(data.get("offset", -1))
	var previous_meta = _remote_meta.get(net_id, {})
	var previous_zone := ""
	if typeof(previous_meta) == TYPE_DICTIONARY:
		previous_zone = str(previous_meta.get("zone", ""))
	_remember_remote_meta(net_id, zone, card_name, travel, rotation, face,
			host_id, claim, slot_index, pile_index, offset, address)
	_configure_remote_card(card)
	_set_remote_card_interactive(card, zone)
	var host: Card = _remote_cards.get(host_id)
	if is_instance_valid(host) and host != card:
		card.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
		card.attachment_offset = _mirror_attachment_offset(offset)
		if card.current_host_card != host:
			card.attach_to_host(host, false, ["net"])
			# A mirror never runs its own ON_PLAY_BOARD step (that would lay
			# the table out from the wrong side), so the host has to put the
			# stack back in card order here. The snapshot lists the resources
			# before the character, so this cannot rely on drop order.
			host.arrange_attachment_stack()
	elif card.current_host_card:
		card._clear_attachment_status(["net"])
	if host_id.is_empty():
		_pending_host_links.erase(net_id)
	else:
		_pending_host_links[net_id] = host_id
	_attach_pending_hosts()
	var target := _target_for_remote(zone, travel, net_id, slot_index, address)
	if card.get_parent() != cfc.NMAP.board:
		if card.get_parent():
			card.get_parent().remove_child(card)
		cfc.NMAP.board.add_child(card)
	card.global_position = target
	card._target_position = target
	if zone != "resources":
		# Remember the box the mirror was laid out in; the resource grid keeps
		# its own rects fresh every frame.
		_remote_layout_rects[net_id] = Rect2(
				target, CFConst.CARD_SIZE * _scale_for_zone(zone))
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	# warning-ignore:return_value_discarded
	card.set_is_faceup(face, true, false, ["net"])
	card.scale = Vector2(1, 1) * _scale_for_zone(zone)
	# The mirror is seen from the other side of the table, so it is shown
	# upside down like a real opponent's card, the resource miniatures
	# included: their grid is already reflected, so the card has to turn with
	# it or the two sides would only half match. Resources are only ever
	# head-down, so a rotation carried over from the owner cannot leave them
	# crooked. The rotation only reaches the drawn control through the tween,
	# so it has to start here.
	var mirror_rotation := 180 if zone == "resources" \
			else (rotation + 180) % 360
	# warning-ignore:return_value_discarded
	card.set_card_rotation(mirror_rotation, false, true, false, ["net"])
	if card.attachments.size() > 0:
		card._organize_attachments()
	_update_remote_zone_labels()
	# The negation automation only runs on the client that applied the intent;
	# that client sends its pins, and this side draws them as remote copies.
	# Drag ticks repeat the same zone many times per second, so only a zone
	# change is worth a line in the log.
	# The automatic opening of a turn is summarized in one shared line, so the
	# cards it moves stay out of the log here too.
	if int(data.get("drag", 0)) == 0 and previous_zone != zone \
			and not Multiplayer.is_auto_turn_step():
		GameEvents.record_remote_card(zone, card_name, face,
				host.canonical_name if is_instance_valid(host) else "")


# Retries every attachment whose host was not mirrored yet. A snapshot can list
# the resource before the character it sits under, and the hotseat only ever
# applies one snapshot, so the link would be lost for good without this pass.
func _attach_pending_hosts() -> void:
	if _resolving_hosts or _pending_host_links.is_empty():
		return
	_resolving_hosts = true
	for net_id in _pending_host_links.keys():
		var host_id := str(_pending_host_links[net_id])
		var card: Card = _remote_cards.get(net_id)
		var host: Card = _remote_cards.get(host_id)
		if not is_instance_valid(card) or not is_instance_valid(host) \
				or card == host:
			continue
		_pending_host_links.erase(net_id)
		if card.current_host_card == host:
			continue
		var meta = _remote_meta.get(net_id, {})
		var offset := -1
		if typeof(meta) == TYPE_DICTIONARY:
			offset = int(meta.get("offset", -1))
		card.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
		card.attachment_offset = _mirror_attachment_offset(offset)
		card.attach_to_host(host, false, ["net"])
		host.arrange_attachment_stack()
	_resolving_hosts = false


# The owner names the edge an attachment uses; the mirror draws the same edge
# from the opposite side. Older peers do not send the edge, so the battle
# scenes bottom (the resource stack) is the one that has always been mirrored.
func _mirror_attachment_offset(offset: int) -> int:
	if offset >= 0 and offset < CFConst.ATTACHMENT_OFFSET.size():
		return offset
	return Card.AttachmentOffset.BATTLE_SCENES_BOTTOM


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
	_remote_layout_rects[net_id] = Rect2(
			target, CFConst.CARD_SIZE * _scale_for_zone("prizes"))
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
		if not card.is_connected("mouse_entered", Callable(self, "_on_remote_card_hover_entered")):
			card.mouse_entered.connect(_on_remote_card_hover_entered.bind(card))
			card.mouse_exited.connect(_on_remote_card_hover_exited.bind(card))
	elif card.is_connected("mouse_entered", Callable(self, "_on_remote_card_hover_entered")):
		card.mouse_entered.disconnect(_on_remote_card_hover_entered)
		card.mouse_exited.disconnect(_on_remote_card_hover_exited)
		_on_remote_card_hover_exited(card)
	if not interactive:
		if _remote_drag_card == card:
			_remote_drag_card = null
		return
	var control := card.get_node("Control")
	if not control.is_connected("gui_input", Callable(self, "_on_remote_card_gui_input")):
		control.gui_input.connect(_on_remote_card_gui_input.bind(card))


# A mirror that sits under another card is reached by hovering the strip that
# peeks out of it, and the preview alone would show it behind the cards the
# pointer is over. The whole pile is lifted as a block, like a focused local
# pile, so every card of the stack can be read while the hover walks down it.
func _remote_stack_root(card: Card) -> Card:
	if is_instance_valid(card.current_host_card):
		return card.current_host_card
	return card


func _remote_stack_is_field(card: Card) -> bool:
	var meta = _remote_meta.get(str(card.network_id), {})
	if typeof(meta) != TYPE_DICTIONARY:
		return false
	return str(meta.get("zone", "")) in ["board", "scenario"]


func _lift_remote_stack(card: Card) -> void:
	var root := _remote_stack_root(card)
	for stacked in [root] + root._live_attachments():
		# A dragged mirror is already on top and belongs to the drag, not to
		# the hover.
		if not is_instance_valid(stacked) or stacked == _remote_drag_card:
			continue
		stacked.z_index = CFConst.TABLE_FOCUS_Z


# The owner can move a hovered mirror (play it, discard it, send it to a pile)
# and the zone is re-read before the hover is dropped, so this works off what
# the sync still has lifted instead of the card's current zone.
func _drop_remote_lifts() -> void:
	for id in _remote_cards:
		var stacked = _remote_cards[id]
		if is_instance_valid(stacked) and stacked != _remote_drag_card \
				and stacked.z_index == CFConst.TABLE_FOCUS_Z:
			stacked.z_index = 0


func _on_remote_card_hover_entered(card: Card) -> void:
	if cfc.ut or not is_instance_valid(card) \
			or not cfc.NMAP.has("main") or not cfc.NMAP.main:
		return
	card.preview_force_front = not card.is_faceup
	card.preview_locked = true
	if _remote_stack_is_field(card):
		_lift_remote_stack(card)
	cfc.NMAP.main.focus_card(card)


func _on_remote_card_hover_exited(card: Card) -> void:
	if not is_instance_valid(card):
		return
	card.preview_force_front = false
	card.preview_locked = false
	_drop_remote_lifts()
	if cfc.NMAP.has("main") and cfc.NMAP.main:
		cfc.NMAP.main.unfocus(card)


func _on_remote_card_gui_input(event, card: Card) -> void:
	if not _active or not is_instance_valid(card) \
			or not card.remote_draggable:
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	_remote_drag_card = card
	_remote_drag_offset = _pointer_position() - card.global_position
	card.z_index = 100


func _update_remote_drag() -> void:
	if not is_instance_valid(_remote_drag_card):
		_remote_drag_card = null
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var target := _pointer_position() - _remote_drag_offset
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
	if not scene or not grid or scene.size.x <= 0.0 \
			or scene.size.y <= 0.0:
		return Vector2(0.5, 0.5)
	var travel: Vector2 = (point + _half_slot(grid) \
			- scene.global_position) / scene.size
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
	if not Rect2(scene.global_position, scene.size).has_point(center):
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
	return grid.get_slot(0).size * 0.5


# Normalized centre of a local scene slot in the owner's frame, so the travel
# that accompanies a slot always agrees with it.
func _slot_travel(index: int) -> Vector2:
	var grid := _scene_grid()
	if not grid or index < 0 or index >= grid.get_slot_count():
		return Vector2(0.5, 0.5)
	var slot: Control = grid.get_slot(index)
	return _normalize_board_position(slot.global_position \
			+ slot.size * 0.5)


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
	meta["address"] = _board_address_for_index(slot_index)
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
			int(meta.get("slot", -1)), str(meta.get("address", "")))
	card.global_position = target
	card._target_position = target


func _apply_move_request(data: Dictionary) -> void:
	if not _active or not Multiplayer.is_playing():
		return
	var net_id := str(data.get("id", ""))
	var zone := str(data.get("zone", "board"))
	if net_id.is_empty() or not zone in ["board", "scenario"]:
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
	card.global_position = slot.global_position
	card._target_position = card.global_position
	_send_card_state(card, zone)


# The mirror names the slot its drop lined up with. The field address is read
# first because it survives a different column count between the two clients;
# the slot index and the normalized travel are the fallbacks for a drop that
# missed every slot of the opponent band.
func _requested_board_slot(grid: BoardPlacementGrid, data: Dictionary,
		card: Card) -> BoardPlacementSlot:
	var slots := grid.get_all_slots()
	var by_address := _slot_index_for_address(str(data.get("address", "")))
	if by_address >= 0 and by_address < slots.size():
		var named: BoardPlacementSlot = slots[by_address]
		if is_instance_valid(named) \
				and (not named.occupying_card
						or named.occupying_card == card):
			return named
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
	var target := grid.global_position \
			+ Vector2(travel.x * grid.size.x, travel.y * grid.size.y)
	var best: BoardPlacementSlot = null
	var best_distance := INF
	for candidate_slot in slots:
		if candidate_slot.occupying_card \
				and candidate_slot.occupying_card != card:
			continue
		var center: Vector2 = candidate_slot.global_position \
				+ candidate_slot.size * 0.5
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
	if button and not button.pressed.is_connected(_show_remote_zone_cards.bind(zone)):
		button.pressed.connect(_show_remote_zone_cards.bind(zone))


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
	if names.is_empty():
		if board.has_method("show_resource_message"):
			board.show_resource_message(
					"O oponente não tem cartas nesta área.")
		return
	var window = SELECTION_WINDOW_SCENE.instantiate()
	board.add_child(window)
	window.confirmed.connect(window.queue_free)
	window.initiate_selection(names, 0, "display", false)
	window.title = "Prêmios do oponente" if zone == "prizes" \
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
		slot := -1,
		pile := -1,
		offset := -1,
		address := "") -> void:
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
		"pile": pile,
		"offset": offset,
		"address": address,
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
	return _zone_at(_pointer_position())


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
	return Rect2(area.global_position, area.size).has_point(point)


func _place_lens() -> void:
	var target := _lens_target()
	# `_ready` returns before `_build_lens` under the unit harness, so a missing
	# lens is as good a reason to stop here as a missing target.
	if not target or not is_instance_valid(_lens):
		_hide_lens()
		return
	_lens.global_position = target.global_position - Vector2(4, 4)
	_lens.size = target.size + Vector2(8, 8)
	_lens.modulate.a = 1.0
	_lens_time = 0.0
	_lens.visible = true
	_lens.move_to_front()


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

func build_public_card_entries(my_slot: int, opponent_slot: int,
		include_remote := true, include_definitions := true) -> Dictionary:
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
		if include_definitions:
			_add_definition(definitions, card.definition_key())
	if include_remote:
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
				"pile": int(meta.get("pile", -1)),
				"offset": int(meta.get("offset", -1)),
				"address": str(meta.get("address", "")),
			})
			if include_definitions:
				_add_definition(definitions, card_name)
	return {"cards": cards, "definitions": definitions}


# A settled change from the peer arrives as the whole public state, which is the
# same shape the hotseat applies on a seat swap. Mirrors missing from the
# snapshot are dropped, the zone ordering is rebuilt from the snapshot order and
# cards whose state did not change are left alone, so the rebuild does not
# interrupt a running tween or a hover.
func _apply_remote_snapshot(data: Dictionary) -> void:
	if not Multiplayer.is_session_active():
		return
	var opponent_slot := Multiplayer.opponent_slot
	var owner := int(data.get("slot", opponent_slot))
	if owner == Multiplayer.my_slot:
		owner = opponent_slot
	_apply_definitions(data.get("definitions", {}))
	var cards = data.get("cards", [])
	if typeof(cards) != TYPE_ARRAY:
		cards = []
	var wanted := {}
	for entry in cards:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("owner", owner)) != owner:
			continue
		var net_id := str(entry.get("id", ""))
		if not net_id.is_empty():
			wanted[net_id] = entry
	for net_id in _remote_cards.keys():
		if not wanted.has(str(net_id)):
			_discard_remote_card(str(net_id))
	for zone in _remote_zone_order:
		_remote_zone_order[zone] = []
	_apply_snapshot_entries(cards, owner, true)
	if data.has("hand") or data.has("deck"):
		Multiplayer.set_opponent_counts({
			"hand": int(data.get("hand", 0)),
			"deck": int(data.get("deck", 0)),
		})
	if data.has("pins"):
		_apply_remote_pins(data.get("pins", []))
	_update_remote_zone_labels()


func apply_public_snapshot(public_state: Dictionary, opponent_slot: int) -> void:
	_clear_remote_cards()
	_clear_hand_placeholders()
	_apply_definitions(public_state.get("definitions", {}))
	_apply_snapshot_entries(public_state.get("cards", []), opponent_slot, false)
	var hidden = public_state.get("hidden", {})
	var counts = {}
	if typeof(hidden) == TYPE_DICTIONARY:
		counts = hidden.get(str(opponent_slot), {})
	if typeof(counts) != TYPE_DICTIONARY:
		counts = {}
	set_hidden_counts(int(counts.get("hand", 0)), int(counts.get("deck", 0)), true)


# Applies the entries of a public snapshot that belong to the given owner. The
# hotseat rebuilds from scratch (skip_unchanged false); the online snapshot
# keeps the mirrors that already match their entry.
func _apply_snapshot_entries(cards, owner_slot: int, skip_unchanged: bool) -> void:
	if typeof(cards) != TYPE_ARRAY:
		return
	for entry in cards:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("owner", 0)) != owner_slot:
			continue
		var net_id := str(entry.get("id", ""))
		if net_id.is_empty():
			continue
		if skip_unchanged and _snapshot_entry_matches(net_id, entry):
			# The zone ordering was cleared before the rebuild, so an entry that
			# needs no new state still has to reclaim its place in the order.
			_remember_snapshot_order(net_id, str(entry.get("zone", "")))
			continue
		_apply_remote_card(_entry_as_message(entry))


func _remember_snapshot_order(net_id: String, zone: String) -> void:
	if not zone in _remote_zone_order:
		return
	if not net_id in _remote_zone_order[zone]:
		_remote_zone_order[zone].append(net_id)


func _snapshot_entry_matches(net_id: String, entry: Dictionary) -> bool:
	var card = _remote_cards.get(net_id)
	if not is_instance_valid(card):
		return false
	var meta = _remote_meta.get(net_id, {})
	if typeof(meta) != TYPE_DICTIONARY:
		return false
	return str(meta.get("zone", "")) == str(entry.get("zone", "")) \
			and str(meta.get("name", "")) == str(entry.get("name", "")) \
			and int(meta.get("slot", -1)) == int(entry.get("slot", -1)) \
			and int(meta.get("rot", 0)) == int(entry.get("rot", 0)) \
			and int(meta.get("face", 1)) == int(entry.get("face", 1)) \
			and str(meta.get("host", "")) == str(entry.get("host", "")) \
			and int(meta.get("pile", -1)) == int(entry.get("pile", -1)) \
			and int(meta.get("offset", -1)) == int(entry.get("offset", -1)) \
			and str(meta.get("address", "")) == str(entry.get("address", "")) \
			and float(meta.get("x", 0.5)) == float(entry.get("x", 0.5)) \
			and float(meta.get("y", 0.5)) == float(entry.get("y", 0.5))


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
				_mark_snapshot_dirty()
		"card_moved_to_board":
			# The scenario claim has to travel at once: it is what settles which
			# side keeps the arena. Everything else can wait for the snapshot.
			var board_zone := _zone_for_card(card)
			if board_zone == "scenario":
				_send_card_state(card, board_zone)
			_mark_snapshot_dirty()
		"card_rotated", "card_flipped", "card_attached", "card_unattached":
			var visible_zone := _zone_for_card(card)
			if visible_zone in HIDDEN_ZONES:
				_send_hidden_card(card)
			else:
				_mark_snapshot_dirty()


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
	if net_id.is_empty():
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
	if not grid or grid.size.x <= 0 or grid.size.y <= 0:
		return Vector2(
				clamp(global_pos.x / board.size.x, 0.0, 1.0),
				clamp(global_pos.y / board.size.y, 0.0, 1.0))
	var relative: Vector2 = (global_pos - grid.global_position) \
			/ grid.size
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


# Field address of a local scene slot ("p1:campo:frente:2"), or "" when the
# slot is not one of the grid slots. The address is what the other side uses
# to line the mirror up: it names the owner's row and column, so a client whose
# grid has a different number of columns still draws the card in the same place
# of the owner's table.
func _board_address_for_slot(slot) -> String:
	return _board_address_for_index(_slot_index(slot))


func _board_address_for_index(index : int) -> String:
	var grid := _scene_grid()
	if not grid or index < 0 or index >= grid.get_slot_count():
		return ""
	var columns := int(max(1, int(grid.get_node("GridContainer").columns)))
	var row := int(index / columns)
	var row_name := "frente"
	if row == 1:
		row_name = "trás"
	elif row > 1:
		row_name = "linha" + str(row + 1)
	# Outside a match there is no seat to name; the addresses are only compared
	# by row and column on the other side, so seat one keeps them parseable.
	var seat := int(Multiplayer.my_slot)
	if seat <= 0:
		seat = 1
	return _Table.field_address(seat, row_name, index % columns + 1)


# Slot of the local scene grid named by an address, or -1 when the address is
# missing, belongs to another zone or names a column this grid does not have.
# The address comes from the owner's state, which is why it survives a change
# in the column count between the two clients.
func _slot_index_for_address(address : String) -> int:
	if address.is_empty():
		return -1
	var parsed := _Table.parse_address(address)
	if str(parsed.get("kind", "")) != "field":
		return -1
	var row := 0
	match str(parsed.get("row", "frente")):
		"frente":
			row = 0
		"trás":
			row = 1
		_:
			return -1
	var column := int(parsed.get("column", 0)) - 1
	var grid := _scene_grid()
	if not grid or column < 0:
		return -1
	var columns := int(max(1, int(grid.get_node("GridContainer").columns)))
	if column >= columns:
		return -1
	var index := row * columns + column
	if index >= grid.get_slot_count():
		return -1
	return index


# Both halves of the table are the same play area seen from opposite sides, so
# an opponent box is this rectangle turned 180 degrees around the middle line
# and the centre of the board. Every mirrored zone goes through this one
# reflection, so no zone grows a second copy of the geometry that could drift.
func mirror_rect(rect: Rect2) -> Rect2:
	var board: Control = cfc.NMAP.board
	if not board:
		return rect
	var axis_x: float = board.global_position.x + board.size.x * 0.5
	var split_y := _split_line_y(board)
	return Rect2(Vector2(
			axis_x * 2.0 - rect.position.x - rect.size.x,
			split_y * 2.0 - rect.position.y - rect.size.y), rect.size)


# The two field bands meet at the bottom of the opponent visual. Falling back to
# the board centre keeps the reflection usable on a scene that has no band.
func _split_line_y(board: Control) -> float:
	var visual: Control = board.get_node_or_null("OpponentFieldVisual")
	if visual and visual.size.y > 0.0:
		return visual.global_position.y + visual.size.y
	return board.global_position.y + board.size.y * 0.5


# The two scene bands are the same box seen from opposite sides of the table,
# so a slot mirrors by turning 180 degrees around the middle line: the owner's
# front row, nearest the middle line on their screen, lands on the row nearest
# the middle line here, which is what makes the two fields face each other.
# An empty rect means the slot could not be mirrored.
func _mirrored_slot_rect(index: int) -> Rect2:
	var grid := _scene_grid()
	if not grid or index < 0 or index >= grid.get_slot_count():
		return Rect2()
	var slot: Control = grid.get_slot(index)
	if not is_instance_valid(slot) or slot.size.x <= 0.0 \
			or slot.size.y <= 0.0:
		return Rect2()
	return mirror_rect(Rect2(slot.global_position, slot.size))


# A scene card that sits in one of the owner's slots is mirrored into the
# matching slot of the opponent band, so both fields keep the same geometry.
# The owner's field address comes first because it names the row and column
# instead of this client's slot numbering: when the two grids have different
# column counts, the same index is a different place on the table. The index
# and the normalized travel are the fallbacks for older peers that do not send
# an address. A card that is not resting on a slot still lives in the owner's
# table space, so its mirror is the same box turned 180 degrees; only a
# travelling card without any table geometry falls back to the zone stack.
func _target_for_remote(zone: String, travel: Vector2, net_id: String,
		slot_index: int, address := "") -> Vector2:
	if zone == "board":
		var named_slot := _slot_index_for_address(address)
		if named_slot >= 0:
			var named := _mirrored_slot_rect(named_slot)
			if named.size.x > 0.0:
				return named.position
		if slot_index >= 0:
			var mirrored := _mirrored_slot_rect(slot_index)
			if mirrored.size.x > 0.0:
				return mirrored.position
		var point := _mirrored_board_point(travel,
				CFConst.CARD_SIZE * BOARD_SCALE)
		if point != Vector2.INF:
			return point
	return _position_for_remote(zone, travel, net_id)


# Point reflection of a table-space coordinate through the middle line, minus
# the room the drawn card takes on this side of the table. An INF result means
# the scene grid is not laid out yet.
func _mirrored_board_point(travel: Vector2, display_size: Vector2) -> Vector2:
	var grid := _scene_grid()
	if not grid or not is_instance_valid(grid) or grid.size.x <= 0.0 \
			or grid.size.y <= 0.0:
		return Vector2.INF
	var local := Rect2(
			grid.global_position + Vector2(
					travel.x * grid.size.x, travel.y * grid.size.y),
			display_size)
	return mirror_rect(local).position


func _position_for_remote(zone: String, travel: Vector2, net_id: String) -> Vector2:
	var board: Control = cfc.NMAP.board
	if not board:
		return Vector2.ZERO
	var visual: Control = board.get_node_or_null("OpponentFieldVisual")
	if not visual:
		return board.global_position
	match zone:
		"resources":
			var order := _resources_in_pile_order()
			var cell := _resource_cell_rect(max(0, order.find(net_id)))
			if cell.size.x > 0.0:
				return cell.position
		"prizes":
			var prizes: Control = visual.get_node_or_null("OpponentPrizes")
			if prizes:
				return _stack_rect(prizes, "prizes", net_id).position
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
	return board.global_position


# The remote field is the opponent board rotated 180 degrees, so the travel
# coordinate is reversed on both axes. The card display size is reserved so
# the mirror never spills into the local player's half of the board.
func _map_zone_position(
		area: Control,
		travel: Vector2,
		margin_x: float,
		offset_top: float,
		display_size: Vector2,
		offset_bottom := 0.0) -> Vector2:
	var usable := Vector2(
			max(1.0, area.size.x - margin_x * 2.0 - display_size.x),
			max(1.0, area.size.y - offset_top - offset_bottom \
					- display_size.y))
	return area.global_position + Vector2(margin_x, offset_top) \
			+ Vector2((1.0 - travel.x) * usable.x,
					(1.0 - travel.y) * usable.y)


func _center_zone_position(
		area: Control,
		top_margin: float,
		display_size: Vector2,
		bottom_margin := 0.0) -> Vector2:
	var available_y: float = max(
			0.0, area.size.y - top_margin - bottom_margin - display_size.y)
	return area.global_position + Vector2(
			max(0.0, (area.size.x - display_size.x) * 0.5),
			top_margin + available_y * 0.5)


func _stack_rect(area: Control, zone: String, net_id: String) -> Rect2:
	var order: Array = _remote_zone_order.get(zone, [])
	var index := order.find(net_id)
	if index < 0:
		index = 0
	var columns := 4
	var column_step := 26.0
	var row_step := 11.0
	var origin := Vector2(6, 0)
	var column := index % columns
	var row := int(index / columns)
	return Rect2(area.global_position + origin \
			+ Vector2(column * column_step, row * row_step),
			CFConst.CARD_SIZE * PRIZES_SCALE)


# The mirrored resources grid is the local grid reflected through the middle
# line: the column order reverses and every cell lands where the owner's cell
# would if the table were turned around. The local pile exposes the layout, so
# both boxes draw the same mini grid.
func _resource_cell_rect(index: int) -> Rect2:
	if index < 0:
		return Rect2()
	if _local_resources_layout().is_empty():
		var area := _resources_area()
		if not area:
			return Rect2()
		return Rect2(_fallback_resource_slot(area, index),
				CFConst.CARD_SIZE * _resources_grid_scale())
	return mirror_rect(_local_resource_cell_rect(index))


# One cell of the local grid, as it is drawn inside the local resources panel.
# The layout is the pile's own, so the mirror cannot drift from what the player
# sees on their side.
func _local_resource_cell_rect(index: int) -> Rect2:
	var panel: Control = _container_area(cfc.NMAP.get("discard", null))
	if not panel:
		return Rect2()
	var scale := _resources_grid_scale()
	var step: Vector2 = CFConst.CARD_SIZE * scale \
			+ Vector2(RESOURCES_GRID_GAP, RESOURCES_GRID_GAP)
	var origin := Vector2(RESOURCES_GRID_PADDING,
			RESOURCES_GRID_PADDING + RESOURCES_LABEL_BAND)
	var layout := _local_resources_layout()
	if not layout.is_empty():
		origin = layout["origin"]
		step = layout["step"]
	else:
		var grid_width := RESOURCES_GRID_COLUMNS * step.x - RESOURCES_GRID_GAP
		var panel_width: float = max(panel.size.x, _resources_base_width())
		origin.x = max(0.0, (panel_width - grid_width) * 0.5)
	var cell := Vector2(
			index % RESOURCES_GRID_COLUMNS,
			int(index / RESOURCES_GRID_COLUMNS)) * step
	return Rect2(panel.global_position + origin + cell,
			CFConst.CARD_SIZE * scale)


# First-frame fallback: the local panel has not laid itself out yet, so the grid
# is derived from the authored width inside the opponent box. The reflected
# layout replaces this as soon as the pile runs once.
func _fallback_resource_slot(area: Control, index: int) -> Vector2:
	var scale := _resources_grid_scale()
	var cell: Vector2 = CFConst.CARD_SIZE * scale + Vector2(
			RESOURCES_GRID_GAP, RESOURCES_GRID_GAP)
	var grid_width := RESOURCES_GRID_COLUMNS * cell.x - RESOURCES_GRID_GAP
	var origin := Vector2(
			max(0.0, (area.size.x - grid_width) * 0.5),
			RESOURCES_GRID_PADDING + RESOURCES_LABEL_BAND)
	var column := index % RESOURCES_GRID_COLUMNS
	var row := int(index / RESOURCES_GRID_COLUMNS)
	return area.global_position + origin + Vector2(
			column * cell.x, row * cell.y)


# The local resources pile owns the mini-grid layout. A pile that has not laid
# itself out yet reports a zero step, which is what keeps the fallback above in
# use instead of stacking every card on the panel corner.
func _local_resources_layout() -> Dictionary:
	var pile = cfc.NMAP.get("discard", null)
	if not pile or not is_instance_valid(pile) \
			or not pile.has_method("grid_layout"):
		return {}
	var layout: Dictionary = pile.grid_layout()
	if layout.is_empty() \
			or typeof(layout.get("step", null)) != TYPE_VECTOR2 \
			or Vector2(layout["step"]) == Vector2.ZERO:
		return {}
	return layout


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
	var layout := _local_resources_layout()
	if not layout.is_empty():
		return float(layout["scale"])
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
	if not cfc.card_drag_ongoing and not _suppressed \
			and not _local_pile_popup_open():
		hovered = _resource_hover_at(_pointer_position())
	_set_resource_preview(hovered)


# The resource mirror drawn under the point, or null. Split from the pointer so
# a test can drive the same check without moving the OS mouse; the guard that
# keeps the preview off during a drag, a rebuild or the selection popup stays
# in the caller, which is the only path that answers the pointer.
func _resource_hover_at(point: Vector2) -> Card:
	var hovered: Card = null
	for net_id in _resources_in_pile_order():
		var card: Card = _remote_cards.get(net_id)
		if not is_instance_valid(card) or not card.visible:
			continue
		# The rect comes from the layout pass, so the hover answers where the
		# mirror was drawn even before its tween has settled.
		var cell: Rect2 = _remote_layout_rects.get(
				str(net_id), _card_screen_rect(card))
		if cell.has_point(point):
			hovered = card
	return hovered


# The hover has to follow what is actually drawn, not the nominal grid size: a
# miniature whose scale or rotation has not caught up yet would otherwise answer
# the pointer from a different spot than its own artwork.
func _card_screen_rect(card: Card) -> Rect2:
	var origin: Vector2 = card.global_transform * (Vector2.ZERO)
	var opposite: Vector2 = card.global_transform * (CFConst.CARD_SIZE)
	return Rect2(origin, opposite - origin).abs()


# The local grid steps aside while its selection popup is open, and the mirrored
# grid has to do the same: the closeup would otherwise open behind the popup the
# player is picking resources in.
func _local_pile_popup_open() -> bool:
	var pile = cfc.NMAP.get("discard", null)
	if not pile or not is_instance_valid(pile):
		return false
	return pile.pile_popup.visible


func _set_resource_preview(card: Card) -> void:
	if card != _resource_preview:
		if is_instance_valid(_resource_preview):
			_resource_preview.preview_force_front = false
			_resource_preview.preview_locked = false
			if cfc.NMAP.has("main") and cfc.NMAP.main:
				cfc.NMAP.main.unfocus(_resource_preview)
		_resource_preview = card
	var previewed := _resource_preview
	if not is_instance_valid(previewed) or cfc.ut \
			or not cfc.NMAP.has("main") or not cfc.NMAP.main:
		return
	# Asked again every frame on purpose: another hover (a hand card, the pile
	# owner) can take the closeup while the pointer never leaves this miniature.
	# The focus call is a no-op when this card is still the one being previewed.
	previewed.preview_force_front = not previewed.is_faceup
	# Without the lock the mirror's own state machine unfocuses the closeup on
	# the very next frame, which is why the grid hover used to show nothing.
	previewed.preview_locked = true
	cfc.NMAP.main.focus_card(previewed)


# The panel width is authored in CGFBoard.tscn, so the grid never falls back to
# a hardcoded size that the scene would not be able to change.
func _resources_base_width() -> float:
	var board = cfc.NMAP.get("board", null)
	if board and board.has_method("resources_base_width"):
		return board.resources_base_width()
	return 156.0


# A mirror that arrived through a path that did not feed the zone order (a
# restored snapshot, for instance) would stay parked wherever it was dropped,
# over the panel and outside the hoverable grid. Every resource mirror is
# adopted before the grid is laid out, so the panel only ever shows those.
func _adopt_missing_resource_mirrors() -> void:
	var order: Array = _remote_zone_order["resources"]
	for net_id in _remote_cards:
		if net_id in order:
			continue
		var meta = _remote_meta.get(net_id, {})
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		if str(meta.get("zone", "")) == "resources":
			order.append(net_id)


# The local grid puts the top of the pile in the first cell, and the top is the
# highest index because a pile appends every card that arrives. The mirror sorts
# the same way; arrival order only matches that online, where each card is
# reported as it moves, while a hotseat rebuild ships the whole pile in spawn
# order, so the sender includes the pile index with every resource card.
func _resources_in_pile_order() -> Array:
	_adopt_missing_resource_mirrors()
	var entries := []
	var arrival_order: Array = _remote_zone_order["resources"]
	for arrival in range(arrival_order.size()):
		var net_id = arrival_order[arrival]
		var meta = _remote_meta.get(net_id, {})
		var pile := -1
		if typeof(meta) == TYPE_DICTIONARY:
			pile = int(meta.get("pile", -1))
		entries.append({"id": net_id, "pile": pile, "arrival": arrival})
	entries.sort_custom(Callable(self, "_sort_pile_entries"))
	var order := []
	for entry in entries:
		order.append(entry["id"])
	return order


# Entries from a sender that did not ship a pile index keep their arrival order
# and go last, so they never push the ordered ones out of the visible window.
func _sort_pile_entries(a: Dictionary, b: Dictionary) -> bool:
	if int(a["pile"]) == int(b["pile"]):
		return int(a["arrival"]) < int(b["arrival"])
	if int(a["pile"]) < 0:
		return false
	if int(b["pile"]) < 0:
		return true
	return int(a["pile"]) > int(b["pile"])


func _relayout_remote_resources() -> void:
	var area := _resources_area()
	if not area:
		return
	var card_scale := _resources_grid_scale()
	var order := _resources_in_pile_order()
	for index in range(order.size()):
		var card: Card = _remote_cards.get(order[index])
		if not is_instance_valid(card):
			continue
		# The mirror shows the newest cards, exactly like the local grid, which
		# drops the bottom of the pile first. Order index 0 is the pile top.
		if index >= RESOURCES_GRID_MAX:
			card.visible = false
			_remote_layout_rects.erase(str(order[index]))
			continue
		card.visible = true
		var target_scale := Vector2(card_scale, card_scale)
		if not card.scale.is_equal_approx(target_scale):
			card.scale = target_scale
		# Global like the rest of the mirror: the cell is the local grid cell
		# reflected through the middle line, so it must not be read as a position
		# inside the board or the opponent panel.
		var cell := _resource_cell_rect(index)
		card.global_position = cell.position
		_remote_layout_rects[str(order[index])] = cell


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
	_remote_layout_rects.erase(net_id)
	_pending_host_links.erase(net_id)
	for zone in _remote_zone_order:
		_remote_zone_order[zone].erase(net_id)
	_sent_visible.erase(net_id)
	if _remote_drag_card == card:
		_remote_drag_card = null
	_update_remote_zone_labels()


func _remove_remote_card(net_id: String) -> void:
	if net_id.is_empty():
		return
	_discard_remote_card(net_id)


func _clear_remote_cards() -> void:
	_set_resource_preview(null)
	for net_id in _remote_cards.keys():
		_discard_remote_card(net_id)
	_remote_cards.clear()
	_remote_meta.clear()
	_remote_layout_rects.clear()
	_pending_host_links.clear()
	_resolving_hosts = false
	_remote_zone_order = {"resources": [], "prizes": []}
	_update_remote_zone_labels()


#-----------------------------------------------------------------------------
# Hand / deck placeholders
#-----------------------------------------------------------------------------

func _refresh_hand_placeholders(hand_count: int) -> void:
	var target: int = min(hand_count, MAX_HAND_PLACEHOLDERS)
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
	if dummy_name.is_empty() or not cfc.NMAP.has("board"):
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
	if not board or _hand_placeholders.is_empty():
		return
	var background: Control = board.get_node_or_null(
			"OpponentFieldVisual/OpponentHandBackground")
	if not background:
		return
	var count := _hand_placeholders.size()
	var card_width := CFConst.CARD_SIZE.x * HAND_SCALE
	var inner: float = max(card_width, background.size.x - 20.0)
	var spacing := card_width
	if count > 1:
		spacing = min(card_width, (inner - card_width) / float(count - 1))
	var fan_width := card_width + spacing * float(count - 1)
	var origin := background.global_position + Vector2(
			(background.size.x - fan_width) * 0.5, 6)
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
			if opponent.is_empty():
				opponent = "VISUAL"
			field_label.text = "CAMPO DO OPONENTE - " + opponent


#-----------------------------------------------------------------------------
# Definitions
#-----------------------------------------------------------------------------

func _add_definition(definitions: Dictionary, card_name: String) -> void:
	var definition = cfc.card_definitions.get(card_name, {})
	if typeof(definition) == TYPE_DICTIONARY and not definition.is_empty():
		definitions[card_name] = definition


func _apply_definitions(definitions) -> void:
	if typeof(definitions) != TYPE_DICTIONARY:
		return
	for card_name in definitions:
		if typeof(definitions[card_name]) == TYPE_DICTIONARY:
			cfc.card_definitions[str(card_name)] = definitions[card_name]


func _send_definition(card_name: String) -> void:
	if card_name.is_empty():
		return
	var definition = cfc.card_definitions.get(card_name, {})
	if typeof(definition) != TYPE_DICTIONARY or definition.is_empty():
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
		# The edge the owner's attachments peek out of. The mirror flips the
		# vector, so it needs the same edge the owner used to land opposite.
		"offset": int(card.attachment_offset),
	}
	if zone == "board":
		var normalized := _normalize_board_position(card.global_position)
		entry["x"] = normalized.x
		entry["y"] = normalized.y
		# A dragged card has left its slot; the snapshot only names a slot once
		# the card has settled, exactly like the live drag message.
		if cfc.card_drag_ongoing != card:
			entry["slot"] = _slot_index(card._placement_slot)
			var address := _board_address_for_slot(card._placement_slot)
			if not address.is_empty():
				entry["address"] = address
	if zone == "scenario":
		entry["claim"] = int(_scenario_claims.get(net_id, 0))
	if zone == "resources":
		entry["pile"] = card.get_index()
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
		"pile": int(entry.get("pile", -1)),
		"offset": int(entry.get("offset", -1)),
		"address": str(entry.get("address", "")),
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


# What the automatic turn phases (AUTOTURNO.md §3.4) read from the table. The
# acting seat is measured on its real cards; the opponent only exists here as
# mirrors, so its numbers come from the mirrored nodes.
func get_turn_facts() -> Dictionary:
	var scene_cards := []
	var characters_in_play := 0
	for card in get_tree().get_nodes_in_group("cards"):
		if not (card is Card) or not is_instance_valid(card) \
				or card.network_mirror or not card.is_inside_tree():
			continue
		if _zone_for_card(card) != "board" or card.current_host_card != null:
			continue
		var card_type := str(card.properties.get("_tipo", "")).strip_edges()
		if not card_type in ["Personagem", "Suporte"]:
			continue
		if card_type == "Personagem":
			characters_in_play += 1
		var attached := _live_attachments(card)
		scene_cards.append({
			"card": card,
			"name": str(card.canonical_name),
			"attachments": attached,
			"attached": attached.size(),
			"energy": str(card.properties.get("ENERGIA", "0")).to_int(),
		})
	return {
		"characters_in_play": characters_in_play,
		"characters": scene_cards,
		"opponent_characters": _mirror_count("board", "Personagem"),
		"opponent_prizes": _mirror_zone_size("prizes"),
	}


# Mirrors are children of the same board node, so only the recorded zone tells
# an opponent character apart from the energy attached under it.
func _mirror_count(zone: String, card_type: String) -> int:
	var total := 0
	for net_id in _remote_cards:
		var card = _remote_cards[net_id]
		if not is_instance_valid(card):
			continue
		var meta = _remote_meta.get(net_id, {})
		if typeof(meta) != TYPE_DICTIONARY or str(meta.get("zone", "")) != zone:
			continue
		if not str(meta.get("host", "")).is_empty():
			continue
		if card_type != "" \
				and str(card.properties.get("_tipo", "")).strip_edges() != card_type:
			continue
		total += 1
	return total


func _mirror_zone_size(zone: String) -> int:
	return _mirror_count(zone, "")


func _live_attachments(card: Card) -> Array:
	var alive := []
	for attachment in card.attachments:
		if is_instance_valid(attachment):
			alive.append(attachment)
	return alive


func _dummy_card_name() -> String:
	if cfc.card_definitions.has("Test Card 1"):
		return "Test Card 1"
	var names := cfc.card_definitions.keys()
	if names.is_empty():
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
	_lens.add_theme_stylebox_override("panel", style)
	cfc.NMAP.board.add_child(_lens)
