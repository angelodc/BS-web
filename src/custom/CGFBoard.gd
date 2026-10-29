# Code for a sample playspace, you're expected to provide your own ;)
extends Board

var _last_prize_energy := -1
var _deck_position := Vector2.ZERO
var _discard_position := Vector2.ZERO
var _prizes_position := Vector2.ZERO
var _deck_control_size := Vector2.ZERO
var pending_resource_host: Card
var pending_resource_swap_card: Card
var pending_resource_count := 0
var pending_resource_swap_active := false
var _resource_selection_completed := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	counters = $Counters
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
	# The deck and the resources keep the wide column; the scenario and the
	# prizes never show more than one card side by side, so their column is
	# narrower on both halves of the table.
	var left_column_width := 156.0
	var side_column_width := 156.0
	var prize_column_width := 120.0
	var right_column_x: float = viewport_size.x - prize_column_width
	var resources_column_x: float = viewport_size.x - side_column_width

	# Three horizontal bands: opponent hand strip on top, then the two field
	# rows, then a shorter hand row at the bottom.
	scene_grid.configure_width(right_column_x - left_column_width)
	var scene_size: Vector2 = scene_grid.rect_size
	var opponent_strip_height := 80.0
	var player_field_y: float = opponent_strip_height + scene_size.y
	# The two field rows at the play-area scale nearly fill the viewport, so
	# the hand band is anchored to the bottom edge instead of the leftover
	# space below the field.
	var hand: Hand = get_node("Hand")
	var hand_band_y: float = viewport_size.y - hand.card_size.y * 0.6

	# The deck lies turned 270 degrees in the bottom-left corner of the local
	# half; the discard pile sits above it with the same width as the lying
	# deck, so the field column stays free.
	deck.rotation_degrees = 270
	_deck_position = Vector2(0, viewport_size.y + 2)
	deck.position = _deck_position
	_discard_position = Vector2(0, player_field_y + 6)
	discard.position = _discard_position
	deck.call_deferred("keep_children_upright")
	# The right column holds one full-size card slot for the active scenario
	# and the quarter-size prize minis right below it.
	_prizes_position = Vector2(right_column_x, player_field_y + 218)
	prizes.position = _prizes_position
	scene_grid.rect_position = Vector2(
			(viewport_size.x - scene_size.x) * 0.5, player_field_y)
	var scenario_grid: BoardPlacementGrid = get_node("ModifiedLabelGrid")
	scenario_grid.rect_position = Vector2(
			right_column_x \
					+ (prize_column_width - scenario_grid.rect_size.x) * 0.5,
			player_field_y + 2)
	var scene_caption: Label = scenario_grid.get_node("Control/Label")
	scene_caption.rect_size = Vector2(prize_column_width, 20)
	# Above the card this caption lands on the opponent resources row, so it
	# sits under the scenario card instead.
	scene_caption.rect_global_position = Vector2(
			right_column_x,
			scenario_grid.rect_global_position.y + scenario_grid.rect_size.y + 2)
	scene_caption.align = Label.ALIGN_RIGHT
	$PrizeEnergyLabel.rect_position = Vector2(
			right_column_x, _prizes_position.y + 126)
	$PrizeEnergyLabel.rect_size = Vector2(prize_column_width, 20)

	# The hand cards are drawn above the hand node origin (the oval fan), so
	# the margin keeps the fan leaning on the bottom edge of the viewport.
	hand.bottom_margin = hand.card_size.y * 0.5
	# warning-ignore:return_value_discarded
	hand.re_place()
	$ResourceSelectionLabel.rect_position = Vector2(262, hand_band_y + 2)
	$HandLabel.rect_position = Vector2(610, hand_band_y + 2)
	_layout_opponent_field(scene_grid, player_field_y, right_column_x,
			resources_column_x, discard)


# The opponent half is the local half seen from across the table: the side
# columns swap left and right, and every box is derived from the same numbers
# the local side uses instead of the fixed rects saved in the scene.
func _layout_opponent_field(
		scene_grid: BoardPlacementGrid,
		player_field_y: float,
		right_column_x: float,
		resources_column_x: float,
		discard: Pile) -> void:
	var visual: Control = get_node("OpponentFieldVisual")
	var grid_size: Vector2 = scene_grid.rect_size
	var grid_x: float = scene_grid.rect_position.x
	var strip_bottom := 80.0
	var available := player_field_y - strip_bottom
	var column_width := 120.0
	var side_width := 156.0

	visual.margin_bottom = player_field_y
	var background: Control = visual.get_node("OpponentFieldBackground")
	background.rect_position = Vector2(0, strip_bottom)
	background.rect_size = Vector2(
			visual.rect_size.x, player_field_y - strip_bottom)

	var hand_bg: Control = visual.get_node("OpponentHandBackground")
	hand_bg.rect_position = Vector2(grid_x, 2)
	hand_bg.rect_size = Vector2(grid_size.x, strip_bottom - 4)
	var hand_label: Label = visual.get_node("OpponentHandLabel")
	hand_label.rect_position = Vector2(grid_x, strip_bottom - 24)
	hand_label.rect_size = Vector2(grid_size.x, 22)

	var scene: Control = visual.get_node("OpponentScene")
	scene.rect_position = Vector2(grid_x, strip_bottom)
	scene.rect_size = grid_size
	var scene_label: Label = visual.get_node("OpponentSceneLabel")
	scene_label.rect_size = Vector2(120, 20)
	scene_label.rect_position = scene.rect_position + Vector2(10, 4)

	# Left column mirrors the local right column: scenario above prizes.
	var scenario_height := available * 0.48
	var scenario: Control = visual.get_node("OpponentScenario")
	scenario.rect_position = Vector2(0, strip_bottom)
	scenario.rect_size = Vector2(column_width, scenario_height)
	var scenario_label: Label = visual.get_node("OpponentScenarioLabel")
	scenario_label.rect_size = Vector2(column_width - 4, 20)
	scenario_label.rect_position = scenario.rect_position \
			+ Vector2(2, scenario_height - 22)
	var prizes: Control = visual.get_node("OpponentPrizes")
	prizes.rect_position = Vector2(0, strip_bottom + scenario_height + 4)
	prizes.rect_size = Vector2(column_width, available - scenario_height - 22)
	var prizes_label: Label = visual.get_node("OpponentPrizesLabel")
	prizes_label.rect_size = Vector2(56, 16)
	prizes_label.rect_position = prizes.rect_position \
			+ Vector2(4, prizes.rect_size.y - 46)
	var prizes_energy: Label = visual.get_node("OpponentPrizesEnergy")
	prizes_energy.rect_size = Vector2(56, 16)
	prizes_energy.rect_position = prizes.rect_position \
			+ Vector2(60, prizes.rect_size.y - 46)

	# Right column mirrors the local left column: resources under the deck box.
	var resources: Control = visual.get_node("OpponentResourcesBackground")
	resources.anchor_left = 0.0
	resources.anchor_right = 0.0
	var resources_height: float = discard.get_node("Control").rect_size.y
	resources.rect_position = Vector2(resources_column_x,
			2.0 * player_field_y - (discard.position.y + resources_height))
	resources.rect_size = Vector2(side_width, resources_height)
	var resources_label: Label = visual.get_node("OpponentResourcesLabel")
	resources_label.anchor_left = 0.0
	resources_label.anchor_right = 0.0
	resources_label.rect_size = Vector2(148, 18)
	resources_label.rect_position = resources.rect_position \
			+ Vector2(4, resources.rect_size.y - 22)
	resources_label.align = Label.ALIGN_RIGHT
	resources_label.autowrap = false
	var resources_view: Button = visual.get_node("OpponentResourcesView")
	resources_view.rect_size = Vector2(60, 22)
	resources_view.rect_position = resources.rect_position \
			+ Vector2(92, resources.rect_size.y - 24)
	var deck_box: Control = visual.get_node("OpponentDeck")
	deck_box.rect_position = Vector2(resources_column_x, 2)
	deck_box.rect_size = Vector2(
			side_width, max(24.0, resources.rect_position.y - 6))
	var deck_label: Label = visual.get_node("OpponentDeckLabel")
	deck_label.rect_size = Vector2(148, 22)
	deck_label.rect_position = deck_box.rect_position \
			+ Vector2(4, deck_box.rect_size.y - 24)
	var prizes_view: Button = visual.get_node("OpponentPrizesView")
	prizes_view.rect_size = Vector2(59, 20)
	prizes_view.rect_position = prizes.rect_position \
			+ Vector2(4, prizes.rect_size.y - 24)
	var field_label: Label = visual.get_node("OpponentFieldLabel")
	field_label.rect_size = Vector2(grid_size.x, 20)
	field_label.rect_position = Vector2(grid_x, player_field_y - 22)


func _on_board_viewport_size_changed() -> void:
	call_deferred("_apply_battle_scenes_layout")


func _process(delta: float) -> void:
	._process(delta)
	_update_prize_energy()
	_hold_pile_layout()


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
	# When the available resources match the cost exactly there is nothing to
	# choose, so the payment happens without opening the selection popup.
	if required_count > 0 \
			and get_available_resource_count() == required_count:
		_auto_pay_resources()
		return
	show_resource_message(
			"Escolha recursos: 0/" + str(pending_resource_count))
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
