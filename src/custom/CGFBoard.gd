# Code for a sample playspace, you're expected to provide your own ;)
extends Board

const PlaymatCatalog = preload("res://src/custom/PlaymatCatalog.gd")

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
var _authored_opponent_scene_rect := Rect2()
var pending_resource_host: Card
var pending_resource_swap_card: Card
var pending_resource_count := 0
var pending_resource_swap_active := false
var _resource_selection_completed := false

# The match is won by the first player whose prize area reaches this much
# printed energy.
const PRIZE_ENERGY_WIN := 15

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	counters = $Counters
	_capture_authored_layout()
	# The sample credit/research counters are not part of the BS match and were
	# covering the deck corner.
	$Counters.visible = false
	cfc.map_node(self)
	# We use the below while to wait until all the nodes we need have been mapped
	# "hand" should be one of them.
	# We're assigning our positions programmatically,
	# instead of defining them on the scene.
	# This way any they will work with any size of viewport in a game.
	# Discard pile goes bottom right
	$FancyMovementToggle.pressed = cfc.game_settings.fancy_movement
	$OvalHandToggle.pressed = cfc.game_settings.hand_use_oval_shape
	# A SCALED focus style stored by an older build turns off the hover preview
	# on hand, field and pile cards, leaving only the previews the pile grids
	# draw themselves. The option is hidden on this board, so it is normalized
	# here instead of depending on the saved settings file.
	if not cfc.game_settings.focus_style:
		cfc.game_settings.focus_style = CFInt.FocusStyle.BOTH
	$ScalingFocusOptions.selected = cfc.game_settings.focus_style
	$Debug.pressed = cfc._debug
	apply_playmat(PlaymatCatalog.selected_id())
	call_deferred("_apply_battle_scenes_layout")
	get_viewport().connect(
			"size_changed", self, "_on_board_viewport_size_changed")
	var multiplayer_session := Multiplayer.is_session_active()
	if not cfc.ut:
		cfc.game_rng_seed = CFUtils.generate_random_seed()
		if not multiplayer_session:
			$SeedLabel.text = "Game Seed is: " + cfc.game_rng_seed
	if not get_tree().get_root().has_node('Gut') and not multiplayer_session:
		load_test_cards(false)
	# warning-ignore:return_value_discarded
	$DeckBuilderPopup.connect('popup_hide', self, '_on_DeckBuilder_hide')
	# warning-ignore:return_value_discarded
	cfc.NMAP.discard.connect(
			"popup_closed", self, "_on_resource_popup_closed")
	_update_prize_energy()
	if not cfc.ut:
		var hud := preload("res://src/custom/MatchHUD.tscn").instance()
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


# The playmat is the local player's own artwork behind the whole board, so the
# mirrored opponent band shows it too and the choice never goes through the relay.
func apply_playmat(playmat_id: String) -> void:
	var playmat: TextureRect = get_node_or_null("Playmat")
	if not playmat:
		return
	var texture: Texture = PlaymatCatalog.texture_for_id(playmat_id)
	playmat.texture = texture
	playmat.visible = texture != null
	_fit_playmat(playmat)


func _fit_playmat(playmat: TextureRect) -> void:
	var area: Vector2 = get_viewport().get_visible_rect().size
	var size: Vector2 = area * PLAYMAT_FILL
	playmat.anchor_right = 0.0
	playmat.anchor_bottom = 0.0
	playmat.rect_size = size
	playmat.rect_position = (area - size) * 0.5


# Solo keeps the deck builder and the way back to the menu, but the dev toggles
# would otherwise sit under the log panel.
func _setup_solo() -> void:
	for control in [
			$FancyMovementToggle, $OvalHandToggle, $ScalingFocusOptions,
			$EnableAttach, $Debug, $SeedLabel]:
		control.visible = false
	$DeckBuilder.rect_position = Vector2(8, 132)
	$BackToMain.rect_position = Vector2(148, 132)


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


func _apply_battle_scenes_layout() -> void:
	if cfc.ut:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var deck: Pile = get_node("Deck")
	var discard: Pile = get_node("Discard")
	var prizes: Pile = get_node("Prêmios")
	var scene_grid: BoardPlacementGrid = get_node("PlacementGridDemo")
	var opponent_visual: Control = get_node("OpponentFieldVisual")
	# The strip height and the column widths are authored in CGFBoard.tscn. The
	# opponent deck box is the mirrored copy of the local left column.
	var strip_bottom: float = opponent_visual.get_node(
			"OpponentFieldBackground").rect_position.y
	var left_column_width: float = opponent_visual.get_node(
			"OpponentDeck").rect_size.x

	scene_grid.configure_width(_prizes_position.x - left_column_width)
	var scene_size: Vector2 = scene_grid.rect_size
	var player_field_y: float = strip_bottom + scene_size.y

	# The deck lies turned 270 degrees in the bottom-left corner; its slot and
	# the two other pile slots are the authored ones.
	deck.rotation_degrees = 270
	deck.position = _deck_position
	discard.position = _discard_position
	prizes.position = _prizes_position
	deck.call_deferred("keep_children_upright")
	scene_grid.rect_position = Vector2(
			(viewport_size.x - scene_size.x) * 0.5, player_field_y)
	# The mirror reads this rect for every slot and floating card, so the
	# opponent scene has to keep matching the real grid.
	if $Debug.pressed:
		_warn_if_opponent_scene_drifted(
				Vector2(scene_grid.rect_position.x, strip_bottom), scene_size)
	var opponent_scene: Control = opponent_visual.get_node("OpponentScene")
	opponent_scene.rect_position = Vector2(
			scene_grid.rect_position.x, strip_bottom)
	opponent_scene.rect_size = scene_size

	# The scenario slot is centred in the right column, the same width as the
	# mirrored deck slot, so it lines up with the prize box below it.
	var scenario_grid: BoardPlacementGrid = get_node("ModifiedLabelGrid")
	scenario_grid.rect_position = Vector2(
			_prizes_position.x \
					+ (left_column_width - scenario_grid.rect_size.x) * 0.5,
			player_field_y + 2)
	var scene_caption: Label = scenario_grid.get_node("Control/Label")
	scene_caption.rect_size = Vector2(left_column_width, 20)
	# Above the card this caption lands on the opponent resources row, so it
	# sits under the scenario card instead.
	scene_caption.rect_global_position = Vector2(
			_prizes_position.x,
			scenario_grid.rect_global_position.y + scenario_grid.rect_size.y + 2)
	scene_caption.align = Label.ALIGN_CENTER

	# The hand cards are drawn above the hand node origin (the oval fan); the
	# margin authored in CGFHand.tscn keeps the fan on the bottom edge.
	var hand: Hand = get_node("Hand")
	# warning-ignore:return_value_discarded
	hand.re_place()


# The pile slots and the mirrored resources width are authored in the scene, so
# they are read once before any restack or hover can move them.
func _capture_authored_layout() -> void:
	var deck: Pile = get_node("Deck")
	var discard: Pile = get_node("Discard")
	var prizes: Pile = get_node("Prêmios")
	_deck_position = deck.position
	_discard_position = discard.position
	_prizes_position = prizes.position
	var resources: Control = get_node(
			"OpponentFieldVisual/OpponentResourcesBackground")
	_resources_base_width = resources.rect_size.x
	var opponent_scene: Control = get_node("OpponentFieldVisual/OpponentScene")
	_authored_opponent_scene_rect = Rect2(
			opponent_scene.rect_position, opponent_scene.rect_size)


# The mirror scales the floating cards by scene/grid, so a stale authored rect
# only shows up once cards are dragged. This warns before the runtime sync hides
# the drift, which means the scene needs a re-bake.
func _warn_if_opponent_scene_drifted(
		expected_position: Vector2, expected_size: Vector2) -> void:
	var drift := _authored_opponent_scene_rect.position.distance_to(
			expected_position)
	drift = max(drift,
			(_authored_opponent_scene_rect.size - expected_size).length())
	if drift <= 1.0:
		return
	print("LAYOUT: OpponentScene/ OpponentSceneLabel divergiram %.1f px do "
			% drift
			+ "grid; re-bake CGFBoard.tscn (cena %s, grid %s)"
			% [_authored_opponent_scene_rect.size, expected_size])


func resources_base_width() -> float:
	return _resources_base_width


func _on_board_viewport_size_changed() -> void:
	var playmat: TextureRect = get_node_or_null("Playmat")
	if playmat and playmat.texture:
		_fit_playmat(playmat)
	call_deferred("_apply_battle_scenes_layout")


func _process(delta: float) -> void:
	._process(delta)
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
	var deck: Pile = get_node("Deck")
	var discard: Pile = get_node("Discard")
	var prizes: Pile = get_node("Prêmios")
	if deck.position != _deck_position or int(deck.rotation_degrees) != 270:
		deck.rotation_degrees = 270
		deck.position = _deck_position
	if discard.position != _discard_position:
		discard.position = _discard_position
	if prizes.position != _prizes_position:
		prizes.position = _prizes_position
	var deck_control: Control = deck.get_node("Control")
	if deck_control.rect_size != _deck_control_size:
		_deck_control_size = deck_control.rect_size
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
	if display.empty():
		display = "P" + str(slot)
	return display


func _build_victory_overlay(slot: int) -> void:
	var area := rect_size
	if area.x <= 0.0 or area.y <= 0.0:
		area = get_viewport().get_visible_rect().size
	var overlay := Control.new()
	overlay.name = "VictoryOverlay"
	overlay.rect_size = area
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.72)
	backdrop.rect_size = area
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(backdrop)
	var title := Label.new()
	title.text = prize_owner_name(slot) + " venceu!"
	title.align = Label.ALIGN_CENTER
	title.valign = Label.VALIGN_CENTER
	title.rect_position = Vector2(0, area.y * 0.32)
	title.rect_size = Vector2(area.x, 40)
	overlay.add_child(title)
	var detail := Label.new()
	detail.text = str(PRIZE_ENERGY_WIN) + " de energia nos Prêmios"
	detail.align = Label.ALIGN_CENTER
	detail.rect_position = Vector2(0, area.y * 0.32 + 42)
	detail.rect_size = Vector2(area.x, 24)
	overlay.add_child(detail)
	var close := Button.new()
	close.text = "Fechar"
	close.rect_min_size = Vector2(120, 34)
	close.rect_position = Vector2((area.x - 120.0) * 0.5, area.y * 0.32 + 92)
	overlay.add_child(close)
	# warning-ignore:return_value_discarded
	close.connect("pressed", overlay, "queue_free")


# Attached cards are the character's energy, so damage takes them away one by
# one and the owner recovers them in the Resources/Discard pile. Losing the
# last one knocks the character out.
func damage_character(card: Card, amount := 1) -> int:
	if not is_instance_valid(card) or card.get_parent() != self \
			or not card.is_battle_scenes_character() or amount <= 0:
		return CFConst.ReturnCode.FAILED
	var removed := 0
	while removed < amount and not card.attachments.empty():
		var attachment: Card = card.attachments.back()
		card.attachments.erase(attachment)
		attachment.current_host_card = null
		attachment.move_to(cfc.NMAP.discard)
		removed += 1
	card._organize_attachments()
	if removed > 0:
		GameEvents.record_local("damaged", "board", card.canonical_name,
				"board", true, "", removed)
	if card.attachments.empty():
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
func send_character_to_opponent_prizes(card: Card) -> void:
	if not is_instance_valid(card) or card.get_parent() != self \
			or not card.is_battle_scenes_character():
		return
	if not Multiplayer.is_session_active():
		show_resource_message(
				"Prêmios do adversário só estão disponíveis em partidas multiplayer.")
		return
	var sync = get_node_or_null("MultiplayerSync")
	if not sync or not sync.has_method("send_card_to_opponent_prizes") \
			or not sync.send_card_to_opponent_prizes(card):
		show_resource_message(
				"Não foi possível enviar a carta para os Prêmios.")
		return
	_release_card_attachments_to_discard(card)
	if card._placement_slot:
		card._placement_slot.occupying_card = null
		card._placement_slot = null
	card.remove_from_group("cards")
	card.monitoring = false
	card.monitorable = false
	card.visible = false
	card.queue_free()
	show_resource_message(card.canonical_name + " foi para os Prêmios do adversário.")


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
	var resource_pile: Pile = cfc.NMAP.discard
	var available_count := 0
	for card in resource_pile.get_all_cards():
		if card.get_parent() == resource_pile \
				or "CardPopUpSlot" in card.get_parent().name:
			available_count += 1
	return available_count


func show_resource_message(message: String) -> void:
	if cfc.ut:
		return
	$ResourceSelectionLabel.text = message


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
	cfc.NMAP.discard.card_count_label.text = \
			str(get_available_resource_count())
	return true


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
func _on_FancyMovementToggle_toggled(_button_pressed) -> void:
#	cfc.game_settings.fancy_movement = $FancyMovementToggle.pressed
	cfc.set_setting('fancy_movement', $FancyMovementToggle.pressed)


func _on_OvalHandToggle_toggled(_button_pressed: bool) -> void:
	cfc.set_setting("hand_use_oval_shape", $OvalHandToggle.pressed)
	for c in cfc.NMAP.hand.get_all_cards():
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
	elif not cfc.current_deck.empty():
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
	$DeckBuilderPopup.popup_centered_minsize()

func _on_DeckBuilder_hide() -> void:
	cfc.game_paused = false


func _on_BackToMain_pressed() -> void:
	if Multiplayer.is_session_active():
		Multiplayer.leave_session("Partida encerrada pelo jogador.")
	cfc.quit_game()
	get_tree().change_scene("res://src/custom/MainMenu.tscn")
