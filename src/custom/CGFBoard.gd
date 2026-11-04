# Code for a sample playspace, you're expected to provide your own ;)
extends Board

const PlaymatCatalog = preload("res://src/custom/PlaymatCatalog.gd")
const MatchRecorderScript = preload("res://src/custom/MatchRecorder.gd")
const TableActionsScript = preload("res://src/core/table/TableActions.gd")
const TableRendererScript = preload("res://src/core/table/TableRenderer.gd")
const TableSnapshotScript = preload("res://src/core/table/TableSnapshot.gd")

# The playmat covers the whole play area edge to edge; the TextureRect uses the
# cover stretch mode, so a window whose ratio differs from the artwork's crops a
# little of it instead of leaving empty bands.
const PLAYMAT_FILL := 1.0

var _last_prize_energy := -1
var _last_hand_count := -1
var _last_deck_count := -1
var _victory_slot := 0
var _deck_position := Vector2.ZERO
var _discard_position := Vector2.ZERO
var _prizes_position := Vector2.ZERO
var _deck_control_size := Vector2.ZERO
var _resources_base_width := 156.0
var pending_resource_host: Card
var pending_resource_swap_card: Card
var pending_resource_count := 0
var pending_resource_swap_active := false
# Materializar: the button right of the hand arms the mode and the next click on
# a hand card sends it to the scene with life from the top of the deck.
var materialize_mode := false
var _resource_message_serial := 0
var _resource_selection_completed := false
var _table_actions = null
var _match_recorder = null

# The match is won by the first player whose prize area reaches this much
# printed energy.
const PRIZE_ENERGY_WIN := 15

# Only these two verbs take from the deck, so only they can run it out.
const DECK_CONSUMING_OPS := ["comprar", "mandar_topo_para_recursos"]
# The two ways the table says the deck could not pay for a demand.
const DECK_SHORTFALL_ERRORS := ["deck_insuficiente", "deck_vazio"]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super._ready()
	counters = $Counters
	_capture_authored_layout()
	# The sample credit/research counters are not part of the BS match and were
	# covering the deck corner.
	$Counters.visible = false
	cfc.map_node(self)
	# The field geometry is authored in CGFBoard.tscn (rota B), so there is no
	# per-viewport positioning to derive here; the deferred layout call only
	# syncs the mirrored opponent band to the grid and re-fans the hand.
	# Discard pile goes bottom right
	$FancyMovementToggle.button_pressed = cfc.game_settings.fancy_movement
	$OvalHandToggle.button_pressed = cfc.game_settings.hand_use_oval_shape
	# A SCALED focus style stored by an older build turns off the hover preview
	# on hand, field and pile cards, leaving only the previews the pile grids
	# draw themselves. The option is hidden on this board, so it is normalized
	# here instead of depending on the saved settings file.
	if not cfc.game_settings.focus_style:
		cfc.game_settings.focus_style = CFInt.FocusStyle.BOTH
	$ScalingFocusOptions.selected = cfc.game_settings.focus_style
	$Debug.button_pressed = cfc._debug
	apply_playmat(PlaymatCatalog.selected_id())
	call_deferred("_apply_battle_scenes_layout")
	get_viewport().size_changed.connect(_on_board_viewport_size_changed)
	var multiplayer_session := Multiplayer.is_session_active()
	if not cfc.ut:
		cfc.game_rng_seed = CFUtils.generate_random_seed()
		if not multiplayer_session:
			$SeedLabel.text = "Game Seed is: " + cfc.game_rng_seed
	if not cfc.ut and not multiplayer_session:
		load_test_cards(false)
	# warning-ignore:return_value_discarded
	$DeckBuilderPopup.popup_hide.connect(_on_DeckBuilder_hide)
	# warning-ignore:return_value_discarded
	cfc.NMAP.discard.popup_closed.connect(_on_resource_popup_closed)
	var materialize_button := get_node_or_null("Materializar") as Button
	if materialize_button:
		# warning-ignore:return_value_discarded
		materialize_button.pressed.connect(_on_Materializar_pressed)
		_update_materialize_button()
	_update_prize_energy()
	if not cfc.ut:
		var hud := preload("res://src/custom/MatchHUD.tscn").instantiate()
		hud.name = "MatchHUD"
		add_child(hud)
		if multiplayer_session:
			_setup_multiplayer(hud)
		else:
			var sync := preload("res://src/custom/MultiplayerSync.gd").new()
			sync.name = "MultiplayerSync"
			add_child(sync)
			_setup_solo()
		GameEvents.set_enabled(true)


func _exit_tree() -> void:
	GameEvents.set_enabled(false)
	if is_instance_valid(_match_recorder):
		_match_recorder.stop("saiu_da_mesa")


# The playmat is the local player's own artwork behind the whole board, so the
# mirrored opponent band shows it too and the choice never goes through the relay.
func apply_playmat(playmat_id: String) -> void:
	var playmat: TextureRect = get_node_or_null("Playmat")
	if not playmat:
		return
	var texture: Texture2D = PlaymatCatalog.texture_for_id(playmat_id)
	playmat.texture = texture
	playmat.visible = texture != null
	_fit_playmat(playmat)


func _fit_playmat(playmat: TextureRect) -> void:
	var area: Vector2 = get_viewport().get_visible_rect().size
	var size: Vector2 = area * PLAYMAT_FILL
	playmat.anchor_right = 0.0
	playmat.anchor_bottom = 0.0
	playmat.size = size
	playmat.position = (area - size) * 0.5


# Solo keeps the deck builder and the way back to the menu, but the dev toggles
# would otherwise sit under the log panel.
func _setup_solo() -> void:
	for control in [
			$FancyMovementToggle, $OvalHandToggle, $ScalingFocusOptions,
			$EnableAttach, $Debug, $SeedLabel]:
		control.visible = false
	$DeckBuilder.position = Vector2(8, 132)
	$BackToMain.position = Vector2(148, 132)


func _setup_multiplayer(hud: Control) -> void:
	for control in [
			$FancyMovementToggle, $OvalHandToggle, $ScalingFocusOptions,
			$EnableAttach, $DeckBuilder, $BackToMain, $Debug, $SeedLabel]:
		control.visible = false
	var hand_buttons := get_node_or_null("Hand/Control/ManipulationButtons")
	if hand_buttons:
		hand_buttons.visible = false
	var sync := preload("res://src/custom/MultiplayerSync.gd").new()
	sync.name = "MultiplayerSync"
	add_child(sync)
	Multiplayer.register_board(self, hud, sync)


# The scene is the source of truth for the field: the grid, the scenario slot
# and its caption are authored in CGFBoard.tscn and survive F5/F6 untouched.
# The runtime only keeps the mirrored opponent band glued to the real grid and
# re-fans the hand over its authored origin.
func _apply_battle_scenes_layout() -> void:
	if cfc.ut:
		return
	var scene_grid: BoardPlacementGrid = get_node("PlacementGridDemo")
	# Auto-arranged columns follow the authored width: widening the grid in
	# the editor widens the field here, with no recompute from the piles.
	scene_grid.configure_width(scene_grid.size.x)
	# The mirror reads this rect for every slot and floating card, so the
	# opponent scene has to keep matching the real grid.
	var opponent_scene: Control = \
			get_node("OpponentFieldVisual/OpponentScene")
	opponent_scene.position = scene_grid.position
	opponent_scene.size = scene_grid.size
	# The hand cards are drawn above the hand node origin (the oval fan); the
	# margin authored in CGFHand.tscn keeps the fan on the bottom edge.
	var hand: Hand = get_node("Hand")
	# warning-ignore:return_value_discarded
	hand.re_place()


# The pile slots and the mirrored resources width are authored in the scene, so
# they are read once before any restack or hover can move them.
func _capture_authored_layout() -> void:
	# The UT board is a trimmed scene without the prizes pile or the opponent
	# band, so each slot is captured only when the node exists.
	var deck = get_node_or_null("Deck")
	if deck:
		_deck_position = deck.position
	var discard = get_node_or_null("Discard")
	if discard:
		_discard_position = discard.position
	var prizes = get_node_or_null("Prêmios")
	if prizes:
		_prizes_position = prizes.position
	var resources = get_node_or_null(
			"OpponentFieldVisual/OpponentResourcesBackground")
	if resources:
		_resources_base_width = resources.size.x


func resources_base_width() -> float:
	return _resources_base_width


func _on_board_viewport_size_changed() -> void:
	var playmat: TextureRect = get_node_or_null("Playmat")
	if playmat and playmat.texture:
		_fit_playmat(playmat)
	call_deferred("_apply_battle_scenes_layout")


func _process(delta: float) -> void:
	super._process(delta)
	_update_prize_energy()
	_refresh_hand_label()
	_hold_pile_layout()


# The opponent field already shows "Mão: N · Deck: M" under the hand; this is
# the same line for the local seat, in the gap above the deck box.
func _refresh_hand_label() -> void:
	var label: Label = get_node_or_null("HandLabel")
	if not label:
		return
	var hand: Hand = get_node_or_null("Hand")
	var deck = cfc.NMAP.get("deck")
	var hand_count = 0
	var deck_count = 0
	if hand:
		hand_count = hand.get_card_count()
	if deck:
		deck_count = deck.get_card_count()
	if hand_count == _last_hand_count and deck_count == _last_deck_count:
		return
	_last_hand_count = hand_count
	_last_deck_count = deck_count
	label.text = "Mão: " + str(hand_count) + " · Deck: " + str(deck_count)


# Restacking a pile runs the anchor based repositioning of CardContainer,
# which would snap these piles back to a viewport corner, so the board keeps
# re-asserting the slots it assigned.
func _hold_pile_layout() -> void:
	if cfc.ut:
		return
	# A bare test board only carries the framework piles.
	var deck: Pile = get_node_or_null("Deck")
	var discard: Pile = get_node_or_null("Discard")
	var prizes: Pile = get_node_or_null("Prêmios")
	if deck and (deck.position != _deck_position
			or int(deck.rotation_degrees) != 270):
		deck.rotation_degrees = 270
		deck.position = _deck_position
	if discard and discard.position != _discard_position:
		discard.position = _discard_position
	if prizes and prizes.position != _prizes_position:
		prizes.position = _prizes_position
	if not deck:
		return
	var deck_control: Control = deck.get_node("Control")
	if deck_control.size != _deck_control_size:
		_deck_control_size = deck_control.size
		deck.call_deferred("keep_children_upright")


func _update_prize_energy() -> void:
	if cfc.ut:
		return
	var total_energy := local_prize_energy()
	var label: Label = get_node_or_null("PrizeEnergyLabel")
	if label and total_energy != _last_prize_energy:
		label.text = "Prêmios: " + str(total_energy)
		_last_prize_energy = total_energy
	if Multiplayer.is_session_active():
		report_prize_energy(Multiplayer.my_slot, total_energy)


# The pile holds the characters this player took from the opponent, so its
# printed energy is the score that wins the match.
func local_prize_energy() -> int:
	var prize_pile: Pile = get_node_or_null("Prêmios")
	if not prize_pile:
		return 0
	var total_energy := 0
	for card in prize_pile.get_all_cards():
		var card_parent = card.get_parent()
		if card_parent == prize_pile \
				or (card_parent and "CardPopUpSlot" in str(card_parent.name)):
			total_energy += str(card.properties.get("ENERGIA", "0")).to_int()
	return total_energy


# Both prize piles are public, so either side can end the match. The first
# total to reach the mark wins and the screens only open once.
func report_prize_energy(slot: int, total: int) -> void:
	if slot < 1 or slot > 2 or total < PRIZE_ENERGY_WIN or _victory_slot != 0:
		return
	_victory_slot = slot
	GameEvents.record_system(prize_owner_name(slot) + " venceu a partida com "
			+ str(total) + " de energia nos Prêmios.")
	if not cfc.ut:
		_build_victory_overlay(slot)


func prize_owner_name(slot: int) -> String:
	var display := Multiplayer.get_slot_username(slot)
	if display.is_empty():
		display = "P" + str(slot)
	return display


# A deck that ran out hands the win to the other side (AUTOTURNO.md §3.5,
# decisão 10c). The prize overlay is reused, with the reason as the detail line.
func report_empty_deck_victory(slot: int, reason: String) -> void:
	if slot < 1 or slot > 2 or _victory_slot != 0:
		return
	_victory_slot = slot
	GameEvents.record_system(reason)
	if not cfc.ut:
		_build_victory_overlay(slot, reason)


func _build_victory_overlay(slot: int, reason: String = "") -> void:
	var area := size
	if area.x <= 0.0 or area.y <= 0.0:
		area = get_viewport().get_visible_rect().size
	var overlay := Control.new()
	overlay.name = "VictoryOverlay"
	overlay.size = area
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.72)
	backdrop.size = area
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(backdrop)
	var title := Label.new()
	title.text = prize_owner_name(slot) + " venceu!"
	title.align = HORIZONTAL_ALIGNMENT_CENTER
	title.valign = VERTICAL_ALIGNMENT_CENTER
	title.position = Vector2(0, area.y * 0.32)
	title.size = Vector2(area.x, 40)
	overlay.add_child(title)
	var detail := Label.new()
	# The prizes win states its target; the deck loss states what happened.
	detail.text = reason if not reason.is_empty() \
			else str(PRIZE_ENERGY_WIN) + " de energia nos Prêmios"
	detail.align = HORIZONTAL_ALIGNMENT_CENTER
	detail.position = Vector2(0, area.y * 0.32 + 42)
	detail.size = Vector2(area.x, 24)
	overlay.add_child(detail)
	var close := Button.new()
	close.text = "Fechar"
	close.custom_minimum_size = Vector2(120, 34)
	close.position = Vector2((area.x - 120.0) * 0.5, area.y * 0.32 + 92)
	overlay.add_child(close)
	# warning-ignore:return_value_discarded
	close.pressed.connect(overlay.queue_free)


# The shared runner for everything the mouse triggers: the manipulation
# buttons, the deck, the match HUD and card drops. One instance per board keeps
# the action log, which is what undo and the script console read.
func table_actions():
	if not is_instance_valid(_table_actions):
		_table_actions = TableActionsScript.new(self)
		_table_actions.recorder = match_recorder()
	return _table_actions


# Created lazily so a match that never records carries no file handle. Starting
# and stopping are driven by the match menu; the runner keeps the reference so
# every intent passes through it.
func match_recorder():
	if not is_instance_valid(_match_recorder):
		_match_recorder = MatchRecorderScript.new()
		if is_instance_valid(_table_actions):
			_table_actions.recorder = _match_recorder
	return _match_recorder


# A drop that took the legacy path (host targeting, popup piles, a table drop
# without a slot) still moves a card. The line is written once the move lands,
# because the address only exists after the card is in place; drops the table
# refused leave the address unchanged and produce no line.
func note_drop(card: Card, destination: Node) -> void:
	if not is_instance_valid(_match_recorder) or not _match_recorder.is_recording():
		return
	if not is_instance_valid(card) or not is_instance_valid(destination):
		return
	var id := TableSnapshotScript.id_of(card)
	if id.is_empty():
		return
	var from_address := _address_of(id)
	var host_id := ""
	if is_instance_valid(card.potential_host):
		host_id = TableSnapshotScript.id_of(card.potential_host)
	# Autoplacement waits 0.1 s before picking a slot, so one frame is not
	# enough to read the destination.
	await get_tree().create_timer(0.35).timeout
	if not is_instance_valid(self) or not is_instance_valid(card):
		return
	if not is_instance_valid(_match_recorder) or not _match_recorder.is_recording():
		return
	var to_address := _address_of(id)
	if to_address.is_empty() or to_address == from_address:
		return
	var actions = table_actions()
	var entry := {
		"op": "arrastar",
		"card": id,
		"name": str(card.canonical_name),
		"from": from_address,
		"to": to_address,
		"seat": int(actions.get_seat()),
		"external": true,
		"undoable": false,
		"undone": false,
	}
	if not host_id.is_empty():
		entry["host"] = host_id
	actions.record_external(entry)


func _address_of(id: String) -> String:
	var actions = table_actions()
	actions.sync()
	return actions.state.address_of(id)


# Runs one validated intent on behalf of the UI. A refused intent changes
# nothing and returns `ok = false` with a message.
func apply_intent(intent : Dictionary) -> Dictionary:
	var actions = table_actions()
	var result : Dictionary = actions.apply(intent)
	if not bool(result.get("ok", false)) \
			and str(intent.get("op", "")) in DECK_CONSUMING_OPS \
			and str(result.get("error", "")) in DECK_SHORTFALL_ERRORS:
		# A demand the deck cannot pay for ends the match on the spot, whoever
		# the actor was (AUTOTURNO.md §3.5, decisão 10c).
		var seat := int(intent.get("seat", actions.get_seat()))
		Multiplayer.declare_empty_deck_loss(seat, int(intent.get("quantity", 1)))
	return result


# Rewrites the scene from the current state, which is what a script uses after
# changing something outside an intent. It is the same reconcile every intent
# already runs at the end.
func render_state() -> void:
	var actions = table_actions()
	actions.sync()
	TableRendererScript.reconcile(self, actions.state, actions.get_seat())


# Tells the player why a click did nothing, using the same line the resource
# payment already uses.
func report_intent(result : Dictionary) -> void:
	if bool(result.get("ok", false)):
		return
	show_resource_message(str(result.get("message", "")))


# Attached cards are the character's energy, so damage takes them away one by
# one and the owner recovers them in the Resources/Discard pile. Losing the
# last one knocks the character out.
func damage_character(card: Card, amount := 1) -> int:
	if not is_instance_valid(card) or card.get_parent() != self \
			or not card.is_battle_scenes_character() or amount <= 0:
		return CFConst.ReturnCode.FAILED
	var removed := 0
	while removed < amount and not card.attachments.is_empty():
		var attachment: Card = card.attachments.back()
		card.attachments.erase(attachment)
		attachment.current_host_card = null
		attachment.move_to(cfc.NMAP.discard)
		removed += 1
	card._organize_attachments()
	if removed > 0:
		GameEvents.record_local("damaged", "board", card.canonical_name,
				"board", true, "", removed)
	if card.attachments.is_empty():
		knockout_character(card)
	return CFConst.ReturnCode.CHANGED


# A character with no energy left leaves the field: the cards still attached go
# to its owner's discard and the card itself becomes a prize of the opponent.
func knockout_character(card: Card) -> void:
	if not is_instance_valid(card) or card.get_parent() != self \
			or not card.is_battle_scenes_character():
		return
	GameEvents.record_local("knocked_out", "prizes", card.canonical_name,
			"board", true)
	send_character_to_opponent_prizes(card)


# Sends a character on the scene to the opponent's prize area. Attached cards
# return to their owner's Resources/Discard, as the character leaves the field.
# The whole thing is the intent, so the button, the knockout and a script share
# the same validation and the same transaction.
func send_character_to_opponent_prizes(card: Card) -> void:
	if not is_instance_valid(card) or card.get_parent() != self \
			or not card.is_battle_scenes_character():
		return
	var card_name := card.canonical_name
	var result := apply_intent({"op": "enviar_aos_prêmios", "card": card})
	if not result.get("ok", false):
		show_resource_message(str(result.get("message", "")))
		return
	show_resource_message(card_name + " foi para os Prêmios do adversário.")


# The network half of the prize send. The intent is what takes the card off the
# table, so this only builds and queues the payload.
func send_card_to_opponent_prizes(card: Card) -> bool:
	var sync = get_node_or_null("MultiplayerSync")
	if not sync or not sync.has_method("send_card_to_opponent_prizes"):
		return false
	return bool(sync.send_card_to_opponent_prizes(card))


# Removes a support from the scene together with the cards attached under it.
func knockout_support(card: Card) -> void:
	if not is_instance_valid(card) or card.get_parent() != self \
			or not card.is_battle_scenes_support():
		return
	_release_card_attachments_to_discard(card)
	card.move_to(cfc.NMAP.discard)
	show_resource_message(card.canonical_name + " foi nocauteado.")


func _release_card_attachments_to_discard(card: Card) -> void:
	for attachment in card.attachments.duplicate():
		attachment.current_host_card = null
		card.attachments.erase(attachment)
		attachment.move_to(cfc.NMAP.discard)
	card.attachments.clear()


func get_available_resource_count() -> int:
	return TableSnapshotScript.resource_count(cfc.NMAP.discard)


func show_resource_message(message: String) -> void:
	var label: Label = get_node_or_null("ResourceSelectionLabel")
	if not label:
		return
	# A newer message cancels the auto-clear of the older one.
	_resource_message_serial += 1
	label.text = message


# Shows a message that clears itself. `seconds` 0 keeps it until the next
# message; the serial makes an older timer give up when a newer line appears.
func show_transient_resource_message(message: String, seconds := 3.0) -> void:
	var label: Label = get_node_or_null("ResourceSelectionLabel")
	if not label:
		return
	_resource_message_serial += 1
	var serial: int = _resource_message_serial
	label.text = message
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout
	if not is_instance_valid(self) or serial != _resource_message_serial:
		return
	label.text = ""


# The resource popup is drawn over the field, so the card under the pointer is a
# field card: if the board keeps chasing the pointer it steals both the preview
# and the click from the popup. The pointer is switched off for the duration of
# the pick; `enable()` re-discovers whatever sits under the mouse on the way
# back, so the hover is not left stuck.
func _set_board_pointer_active(active: bool) -> void:
	if cfc.ut:
		return
	var board = cfc.NMAP.get("board", null)
	if not board or not is_instance_valid(board):
		return
	var pointer = board.mouse_pointer
	if not pointer or not is_instance_valid(pointer):
		return
	if active:
		if pointer.has_method("enable"):
			pointer.enable()
		return
	if pointer.has_method("disable"):
		pointer.disable()
	# The popup sits over the field, but the closeup of the card that was under
	# the pointer would stay open behind it for the whole pick. `disable()` does
	# not release it, so the release is done the same way the pointer does when
	# the mouse leaves a card.
	var focused = pointer.current_focused_card
	if focused and is_instance_valid(focused) \
			and focused.state != Card.CardState.DRAGGED:
		focused._on_Card_mouse_exited()
	if pointer.has_method("forget_focus"):
		pointer.forget_focus()


func begin_resource_selection(host: Card, required_count: int) -> void:
	pending_resource_host = host
	pending_resource_count = required_count
	_resource_selection_completed = false
	# When the available resources match the cost exactly there is nothing to
	# choose, so the payment happens without opening the selection popup.
	if required_count > 0 \
			and get_available_resource_count() == required_count:
		_auto_pay_resources()
		return
	show_resource_message(
			"Escolha recursos: 0/" + str(pending_resource_count))
	_set_board_pointer_active(false)
	cfc.NMAP.discard.populate_popup()


func _auto_pay_resources() -> void:
	cfc.NMAP.discard.populate_popup()
	var payment := []
	for slot in cfc.NMAP.discard.get_node("ViewPopup/CardView").get_children():
		for node in slot.get_children():
			if node is Card:
				payment.append(node)
	for resource in payment:
		if pending_resource_count <= 0:
			break
		select_resource_for_host(resource)


func select_resource_for_host(resource: Card) -> void:
	if not pending_resource_host \
			or resource.current_host_card \
			or not "CardPopUpSlot" in resource.get_parent().name:
		return
	resource.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
	resource.attachment_offset = \
			Card.AttachmentOffset.BATTLE_SCENES_BOTTOM
	resource.attach_to_host(pending_resource_host)
	# The resource comes from the popup, so it lands as the newest child and
	# would draw over the character it pays for. Put the pile back in card
	# order right away: the character on top, one strip per resource below.
	pending_resource_host._organize_attachments()
	cfc.NMAP.discard.pre_sorted_order.erase(resource)
	cfc.NMAP.discard.card_count_label.text = \
			str(get_available_resource_count())
	var selected_count := pending_resource_host.attachments.size()
	show_resource_message(
			"Escolha recursos: " + str(selected_count) + "/"
			+ str(pending_resource_count))
	if selected_count >= pending_resource_count:
		_resource_selection_completed = true
		pending_resource_host = null
		pending_resource_count = 0
		show_resource_message("")
		cfc.NMAP.discard.pile_popup.hide()
		_set_board_pointer_active(true)


func begin_resource_swap() -> void:
	if pending_resource_swap_active:
		pending_resource_swap_active = false
		pending_resource_swap_card = null
		show_resource_message("Troca cancelada.")
		_set_board_pointer_active(true)
		return
	if pending_resource_host or cfc.NMAP.discard.is_popup_open:
		return
	if get_available_resource_count() == 0:
		show_resource_message("Não há cartas disponíveis para a troca.")
		return
	pending_resource_swap_active = true
	pending_resource_swap_card = null
	show_resource_message("Escolha uma carta da pilha para a troca.")
	_set_board_pointer_active(false)
	cfc.NMAP.discard.populate_popup()


func select_resource_for_swap(resource: Card) -> bool:
	if not pending_resource_swap_active \
			or pending_resource_swap_card \
			or resource.current_host_card \
			or not "CardPopUpSlot" in resource.get_parent().name:
		return false
	pending_resource_swap_card = resource
	cfc.NMAP.discard.pile_popup.hide()
	# The next click names the resource to replace, and it lands on the field,
	# so the pointer has to come back before the popup finishes closing.
	_set_board_pointer_active(true)
	return true


func swap_attached_resource(resource: Card) -> bool:
	var host: Card = resource.current_host_card
	if not pending_resource_swap_active \
			or not pending_resource_swap_card \
			or not host \
			or host.get_parent() != self \
			or not host.is_battle_scenes_character() \
			or resource.attachment_offset \
			!= Card.AttachmentOffset.BATTLE_SCENES_BOTTOM:
		return false

	var replacement: Card = pending_resource_swap_card
	pending_resource_swap_active = false
	pending_resource_swap_card = null
	show_resource_message("")
	resource._clear_attachment_status()
	resource.move_to(cfc.NMAP.discard)
	replacement.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
	replacement.attachment_offset = \
			Card.AttachmentOffset.BATTLE_SCENES_BOTTOM
	replacement.attach_to_host(host)
	# Same as select_resource_for_host: the replacement also comes from the
	# popup and lands above the pile until the host is organized again.
	host._organize_attachments()
	cfc.NMAP.discard.card_count_label.text = \
			str(get_available_resource_count())
	return true


# -----------------------------------------------------------------------------
# Materializar
# -----------------------------------------------------------------------------

# The button right of the hand arms the mode: every hand card glows green and
# the next left click on one of them materializes it. Cancelling is the button
# again or Esc.
func start_materialize() -> void:
	if materialize_mode:
		return
	materialize_mode = true
	_set_materialize_highlight(true)
	_update_materialize_button()
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	show_transient_resource_message(
			"Materializar: clique numa carta da mão.", 0)


func stop_materialize() -> void:
	if not materialize_mode:
		return
	materialize_mode = false
	_set_materialize_highlight(false)
	_update_materialize_button()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	show_resource_message("")


func _on_Materializar_pressed() -> void:
	if materialize_mode:
		stop_materialize()
	else:
		start_materialize()


func _unhandled_input(event : InputEvent) -> void:
	if not materialize_mode:
		return
	if event.is_action_pressed("ui_cancel"):
		stop_materialize()
		get_viewport().set_input_as_handled()


func _update_materialize_button() -> void:
	var button := get_node_or_null("Materializar") as Button
	if not button:
		return
	button.set_pressed_no_signal(materialize_mode)
	button.text = "Cancelar" if materialize_mode else "Materializar"
	button.tooltip_text = "Escolha uma carta da mão ou cancele" \
			if materialize_mode else "Materializa uma carta da mão com vida do topo do deck"


# The green is not one of the CostsState colours on purpose: set_focus() only
# clears a highlight painted in those, so hovering a card does not wipe the
# mode colour and unhovering does not either. The mode has to clear it itself.
func _set_materialize_highlight(enabled : bool) -> void:
	var hand = cfc.NMAP.get("hand", null)
	if not is_instance_valid(hand):
		return
	for card in hand.get_all_cards():
		if not is_instance_valid(card):
			continue
		var control: Control = card.get_node_or_null("Control")
		if control:
			control.set_default_cursor_shape(
					Control.CURSOR_POINTING_HAND if enabled
					else Control.CURSOR_ARROW)
		if enabled:
			card.highlight.set_highlight(true,
					CFConst.MATERIALIZE_HOVER_COLOUR)
		else:
			var focused: bool = card.state == Card.CardState.FOCUSED_IN_HAND
			card.highlight.set_highlight(focused, CFConst.FOCUS_HOVER_COLOUR)


# Called by the card when a hand card is clicked while the mode is armed. A
# card the table refuses stays in the hand and the mode stays armed, so another
# one can be picked; the warning clears itself.
func materialize_hand_card(card: Card) -> Dictionary:
	if not materialize_mode or not is_instance_valid(card):
		return {"ok": false, "error": "modo_inativo", "message": ""}
	var result := apply_intent({"op": "materializar", "card": card})
	if bool(result.get("ok", false)):
		# The card left the hand still glowing; from here the board owns it.
		card.highlight.set_highlight(false)
		stop_materialize()
		return result
	var error := str(result.get("error", ""))
	if error == "tipo_invalido":
		show_transient_resource_message(str(result.get("message", "")), 3.0)
		return result
	stop_materialize()
	report_intent(result)
	return result


func _on_resource_popup_closed() -> void:
	if pending_resource_swap_active:
		if pending_resource_swap_card:
			show_resource_message(
					"Clique no Recurso do Personagem que deseja trocar.")
		else:
			pending_resource_swap_active = false
			show_resource_message("Troca cancelada.")
			_set_board_pointer_active(true)
		return
	if not pending_resource_host or _resource_selection_completed:
		return
	var host := pending_resource_host
	pending_resource_host = null
	pending_resource_count = 0
	for resource in host.attachments.duplicate():
		resource._clear_attachment_status()
		resource.move_to(cfc.NMAP.discard)
	host.set_state(Card.CardState.IN_HAND)
	host.move_to(cfc.NMAP.hand)
	show_resource_message("Seleção cancelada; carta devolvida à Mão.")
	_set_board_pointer_active(true)



# This function is to avoid relating the logic in the card objects
# to a node which might not be there in another game
# You can remove this function and the FancyMovementToggle button
# without issues
func _on_FancyMovementToggle_toggled(button_pressed: bool) -> void:
	# No Godot 4 a propriedade bool do Button é `button_pressed`; `pressed` é o
	# signal. Usar o argumento do `toggled` evita salvar o Signal como string.
	cfc.set_setting('fancy_movement', button_pressed)


func _on_OvalHandToggle_toggled(button_pressed: bool) -> void:
	cfc.set_setting("hand_use_oval_shape", button_pressed)
	# Durante o _ready o sinal `toggled` dispara antes de o nó "hand" estar
	# mapeado no NMAP; sem a chave, o acesso dava erro no Godot 4.
	var hand = cfc.NMAP.get("hand")
	if hand == null:
		return
	for c in hand.get_all_cards():
		c.reorganize_self()


# Button to change focus mode
func _on_ScalingFocusOptions_item_selected(index) -> void:
	cfc.set_setting('focus_style', index)


# Button to make all cards act as attachments
func _on_EnableAttach_toggled(button_pressed: bool) -> void:
	for c in get_tree().get_nodes_in_group("cards"):
		if button_pressed:
			c.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
		else:
			c.attachment_mode = Card.AttachmentMode.DO_NOT_ATTACH


func _on_Debug_toggled(button_pressed: bool) -> void:
	cfc._debug = button_pressed

# Loads a sample set of cards to use for testing
func load_test_cards(gut := true) -> void:
	# Hardcoded the card order because for some reason, GUT on low-powered VMs
	# ends up with a different card order, even when the seed is the same.
	var gut_cards := [
		"Multiple Choices Test Card",
		"Test Card 2",
		"Test Card 3",
		"Test Card 2",
		"Test Card 2",
		"Test Card 1",
		"Test Card 2",
		"Multiple Choices Test Card",
		"Test Card 3",
		"Multiple Choices Test Card",
		"Multiple Choices Test Card",
		"Rich Text Card",
		"Shaking Card",
		"Test Card 1",
		"Test Card 2",
		"Test Card 3",
		"Multiple Choices Test Card",
	]
	var test_card_array := []
	if gut:
		for card in gut_cards:
			test_card_array.append(cfc.instance_card(card))
	elif not cfc.current_deck.is_empty():
		for card_name in cfc.current_deck.cards:
			for _i in range(cfc.current_deck.cards[card_name]):
				test_card_array.append(cfc.instance_card(card_name))
	else:
		var spider_deck = load(
				"res://src/custom/cards/sets/"
				+ "SetDefinition_ResgateAracnideo.gd").TEST_DECK
		for card_name in spider_deck:
			for _i in range(spider_deck[card_name]):
				test_card_array.append(cfc.instance_card(card_name))
	for card in test_card_array:
		cfc.NMAP.deck.add_child(card)
		#card.set_is_faceup(false,true)
		card._determine_idle_state()

func _on_DeckBuilder_pressed() -> void:
	cfc.game_paused = true
	$DeckBuilderPopup.popup_centered_clamped()

func _on_DeckBuilder_hide() -> void:
	cfc.game_paused = false


func _on_BackToMain_pressed() -> void:
	if Multiplayer.is_session_active():
		Multiplayer.leave_session("Partida encerrada pelo jogador.")
	cfc.quit_game()
	get_tree().change_scene_to_file("res://src/custom/MainMenu.tscn")
