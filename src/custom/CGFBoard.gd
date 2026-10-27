# Code for a sample playspace, you're expected to provide your own ;)
extends Board

var _last_prize_energy := -1
var pending_resource_host: Card
var pending_resource_swap_card: Card
var pending_resource_count := 0
var pending_resource_swap_active := false
var _resource_selection_completed := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	counters = $Counters
	cfc.map_node(self)
	# We use the below while to wait until all the nodes we need have been mapped
	# "hand" should be one of them.
	# We're assigning our positions programmatically,
	# instead of defining them on the scene.
	# This way any they will work with any size of viewport in a game.
	# Discard pile goes bottom right
	$FancyMovementToggle.pressed = cfc.game_settings.fancy_movement
	$OvalHandToggle.pressed = cfc.game_settings.hand_use_oval_shape
	$ScalingFocusOptions.selected = cfc.game_settings.focus_style
	$Debug.pressed = cfc._debug
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
		if multiplayer_session:
			_setup_multiplayer()
		else:
			var sync := preload("res://src/custom/MultiplayerSync.gd").new()
			sync.name = "MultiplayerSync"
			add_child(sync)


func _setup_multiplayer() -> void:
	for control in [
			$FancyMovementToggle, $OvalHandToggle, $ScalingFocusOptions,
			$EnableAttach, $DeckBuilder, $BackToMain, $Debug, $SeedLabel]:
		control.visible = false
	var hud := preload("res://src/custom/MatchHUD.tscn").instance()
	hud.name = "MatchHUD"
	add_child(hud)
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
	var right_column_x: float = viewport_size.x - 141
	var scene_grid: BoardPlacementGrid = get_node("PlacementGridDemo")
	var left_column_width := 156.0

	# Three horizontal bands: opponent hand strip on top, then the two field
	# rows, then a shorter hand row at the bottom.
	scene_grid.configure_width(right_column_x - left_column_width)
	var scene_size: Vector2 = scene_grid.rect_size
	var opponent_strip_height := 80.0
	var player_field_y: float = opponent_strip_height + scene_size.y
	var hand_band_y: float = player_field_y + scene_size.y

	deck.position = Vector2(0, player_field_y)
	discard.position = Vector2(0, player_field_y + 115)
	prizes.position = Vector2(right_column_x, player_field_y + 180)
	scene_grid.rect_position = Vector2(
			(viewport_size.x - scene_size.x) * 0.5, player_field_y)
	get_node("ModifiedLabelGrid").rect_position = Vector2(
			right_column_x, player_field_y)
	$PrizeEnergyLabel.rect_position = Vector2(
			right_column_x, viewport_size.y - 40)

	# The hand cards are drawn above the hand node origin (the oval fan), so
	# the margin is computed from the top of the hand band.
	var hand: Hand = get_node("Hand")
	hand.bottom_margin = hand_band_y + hand.card_size.y * 0.25 \
			- (viewport_size.y - hand.card_size.y)
	# warning-ignore:return_value_discarded
	hand.re_place()
	$ResourceSelectionLabel.rect_position = Vector2(165, hand_band_y + 2)
	$HandLabel.rect_position = Vector2(610, hand_band_y + 2)

	var opponent_scene: ColorRect = get_node(
			"OpponentFieldVisual/OpponentScene")
	opponent_scene.rect_position = Vector2(
			scene_grid.rect_position.x, opponent_strip_height)
	opponent_scene.rect_size = scene_size
	var opponent_scene_label: Label = get_node(
			"OpponentFieldVisual/OpponentSceneLabel")
	opponent_scene_label.rect_position = opponent_scene.rect_position \
			+ Vector2(10, 4)


func _on_board_viewport_size_changed() -> void:
	call_deferred("_apply_battle_scenes_layout")


func _process(delta: float) -> void:
	._process(delta)
	_update_prize_energy()


func _update_prize_energy() -> void:
	if cfc.ut:
		return
	var prize_pile: Pile = get_node("Prêmios")
	var total_energy := 0
	for card in prize_pile.get_all_cards():
		var card_parent = card.get_parent()
		if card_parent == prize_pile \
				or (card_parent and "CardPopUpSlot" in str(card_parent.name)):
			total_energy += str(card.properties.get("ENERGIA", "0")).to_int()
	if total_energy != _last_prize_energy:
		$PrizeEnergyLabel.text = "Energia: " + str(total_energy)
		_last_prize_energy = total_energy


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


func begin_resource_selection(host: Card, required_count: int) -> void:
	pending_resource_host = host
	pending_resource_count = required_count
	_resource_selection_completed = false
	show_resource_message(
			"Escolha recursos: 0/" + str(pending_resource_count))
	cfc.NMAP.discard.populate_popup()


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


func begin_resource_swap() -> void:
	if pending_resource_swap_active:
		pending_resource_swap_active = false
		pending_resource_swap_card = null
		show_resource_message("Troca cancelada.")
		return
	if pending_resource_host or cfc.NMAP.discard.is_popup_open:
		return
	if get_available_resource_count() == 0:
		show_resource_message("Não há cartas disponíveis para a troca.")
		return
	pending_resource_swap_active = true
	pending_resource_swap_card = null
	show_resource_message("Escolha uma carta da pilha para a troca.")
	cfc.NMAP.discard.populate_popup()


func select_resource_for_swap(resource: Card) -> bool:
	if not pending_resource_swap_active \
			or pending_resource_swap_card \
			or resource.current_host_card \
			or not "CardPopUpSlot" in resource.get_parent().name:
		return false
	pending_resource_swap_card = resource
	cfc.NMAP.discard.pile_popup.hide()
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
