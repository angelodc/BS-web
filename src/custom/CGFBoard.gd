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
	# Fill up the deck for demo purposes
	if not cfc.ut:
		cfc.game_rng_seed = CFUtils.generate_random_seed()
		$SeedLabel.text = "Game Seed is: " + cfc.game_rng_seed
	if not get_tree().get_root().has_node('Gut'):
		load_test_cards(false)
	# warning-ignore:return_value_discarded
	$DeckBuilderPopup.connect('popup_hide', self, '_on_DeckBuilder_hide')
	# warning-ignore:return_value_discarded
	cfc.NMAP.discard.connect(
			"popup_closed", self, "_on_resource_popup_closed")
	_update_prize_energy()


func _apply_battle_scenes_layout() -> void:
	if cfc.ut:
		return
	var viewport_size: Vector2 = get_viewport().size
	var player_field_y: float = viewport_size.y / 2
	var deck: Pile = get_node("Deck")
	var prizes: Pile = get_node("Prêmios")

	deck.position = Vector2(0, player_field_y)
	prizes.position = Vector2(viewport_size.x - 156, player_field_y)
	get_node("PlacementGridDemo").rect_position = Vector2(
			viewport_size.x * 155.0 / 1280.0, player_field_y)
	get_node("ModifiedLabelGrid").rect_position = Vector2(
			viewport_size.x * 920.0 / 1280.0, player_field_y)
	$PrizeEnergyLabel.rect_position = Vector2(
			viewport_size.x - 220, player_field_y - 25)


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
		if prize_pile.is_a_parent_of(card):
			total_energy += str(card.properties.get("ENERGIA", "0")).to_int()
	if total_energy != _last_prize_energy:
		$PrizeEnergyLabel.text = "Energia dos Prêmios: " + str(total_energy)
		_last_prize_energy = total_energy


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


# Reshuffles all Card objects created back into the deck
func _on_ReshuffleAllDeck_pressed() -> void:
	reshuffle_all_in_pile(cfc.NMAP.deck)


func _on_ReshuffleAllDiscard_pressed() -> void:
	reshuffle_all_in_pile(cfc.NMAP.discard)

func reshuffle_all_in_pile(pile = cfc.NMAP.deck):
	for c in get_tree().get_nodes_in_group("cards"):
		if c.get_parent() != pile and c.state != Card.CardState.DECKBUILDER_GRID:
			c.move_to(pile)
			yield(get_tree().create_timer(0.1), "timeout")
	# Last card in, is the top card of the pile
	var last_card : Card = pile.get_top_card()
	if last_card._tween.is_active():
		yield(last_card._tween, "tween_all_completed")
	yield(get_tree().create_timer(0.2), "timeout")
	pile.shuffle_cards()


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
	var extras = 11
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
	else:
		var test_cards := []
		for ckey in cfc.card_definitions.keys():
			if ckey != "Spawn Card":
				test_cards.append(ckey)
		for _i in range(extras):
			if not test_cards.empty():
				var random_card_name = \
						test_cards[CFUtils.randi() % len(test_cards)]
				test_card_array.append(cfc.instance_card(random_card_name))
		# 11 is the cards GUT expects. It's the testing standard
		if extras == 11:
		# I ensure there's of each test card, for use in GUT
			for card_name in test_cards:
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
	cfc.quit_game()
	get_tree().change_scene("res://src/custom/MainMenu.tscn")
