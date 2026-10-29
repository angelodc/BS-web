extends "res://tests/UTcommon.gd"

# Damage removes the attached energies, knockout hands the character to the
# opponent prizes, and the first prize area to reach fifteen wins.

const CHAR_NAME := "Char Energia 10"


func after_each():
	Multiplayer.leave_session()
	cfc.card_definitions.erase(CHAR_NAME)


func _character_deck() -> Dictionary:
	return {"name": "Teste", "cards": {CHAR_NAME: 60}}


func _character_definition() -> Dictionary:
	var definition: Dictionary = \
			cfc.card_definitions["Test Card 1"].duplicate(true)
	definition["Name"] = CHAR_NAME
	definition["_tipo"] = "Personagem"
	definition["ENERGIA"] = "10"
	return definition


func _free_all_cards() -> void:
	for card in get_tree().get_nodes_in_group("cards"):
		if not (card is Card) or not is_instance_valid(card):
			continue
		var parent = card.get_parent()
		if parent:
			parent.remove_child(card)
		card.queue_free()


func _add_prize_pile() -> void:
	var prizes = load("res://src/core/Pile.tscn").instance()
	prizes.name = "Prêmios"
	board.add_child(prizes)
	autofree(prizes)


func _start_match() -> void:
	var setup = setup_board()
	if setup is GDScriptFunctionState:
		setup = yield(setup, "completed")
	_add_prize_pile()
	_free_all_cards()
	yield(yield_for(0.2), YIELD)

	Multiplayer.begin_solo("Doug")
	var sync = load("res://src/custom/MultiplayerSync.gd").new()
	sync.name = "MultiplayerSync"
	board.add_child(sync)
	autofree(sync)
	Multiplayer.register_board(board, null, sync)
	yield(yield_for(0.1), YIELD)
	# The board setup reloads the set definitions, so the character is only
	# known from here on.
	cfc.card_definitions[CHAR_NAME] = _character_definition()
	Multiplayer.select_deck(_character_deck())
	Multiplayer.set_solo_pick_slot(2)
	Multiplayer.select_deck(_character_deck())
	assert_true(Multiplayer.request_start(), "Two full decks start the solo match")
	yield(yield_for(0.3), YIELD)


func _take_hand_card() -> Card:
	for child in cfc.NMAP.hand.get_children():
		if child is Card and is_instance_valid(child):
			return child
	return null


func _place_character() -> Card:
	var card := _take_hand_card()
	if not card:
		return null
	cfc.NMAP.hand.remove_child(card)
	board.add_child(card)
	card.set_is_faceup(true, true)
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	card.global_position = board.rect_size * 0.5
	return card


# Attachments only need to be on the board: from there the host takes them into
# its own array without asking the placement grid for a slot.
func _attach_energy(host: Card) -> Card:
	var energy := _place_character()
	if not energy:
		return null
	energy.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
	energy.attachment_offset = Card.AttachmentOffset.BATTLE_SCENES_BOTTOM
	energy.attach_to_host(host, false, ["net"])
	return energy


func _mirror_meta(net_id: String) -> Dictionary:
	var sync = Multiplayer._sync
	if not sync:
		return {}
	var meta = sync._remote_meta.get(net_id, {})
	return meta if typeof(meta) == TYPE_DICTIONARY else {}


func test_damage_takes_one_attached_card_to_the_discard():
	yield(_start_match(), "completed")

	var card := _place_character()
	assert_true(card.is_battle_scenes_character(),
			"The placed card is a character")
	_attach_energy(card)
	_attach_energy(card)
	var discard_before: int = discard.get_all_cards().size()
	assert_eq(card.attachments.size(), 2, "The character carries two energies")

	assert_eq(board.damage_character(card, 1), CFConst.ReturnCode.CHANGED,
			"Damage applies to a character on the field")
	assert_eq(card.attachments.size(), 1, "One energy leaves the character")
	assert_eq(discard.get_all_cards().size(), discard_before + 1,
			"The energy goes to the owner's Resources/Discard")
	assert_eq(card.get_parent(), board, "The character stays on the field")
	assert_eq(board._victory_slot, 0, "One damage does not end the match")


func test_cards_outside_the_field_take_no_damage():
	yield(_start_match(), "completed")

	var in_hand := _take_hand_card()
	assert_eq(board.damage_character(in_hand, 1), CFConst.ReturnCode.FAILED,
			"A card in hand is not damaged")
	assert_eq(board.damage_character(null, 1), CFConst.ReturnCode.FAILED,
			"A missing card is not damaged")


func test_last_energy_knocks_the_character_into_the_opponent_prizes():
	yield(_start_match(), "completed")

	var card := _place_character()
	var card_id := Multiplayer.ensure_card_id(card)
	_attach_energy(card)
	assert_eq(card.attachments.size(), 1, "The character carries one energy")

	board.damage_character(card, 1)
	yield(yield_for(0.1), YIELD)

	assert_true(not is_instance_valid(card) or not card.is_inside_tree(),
			"The knocked out character leaves the field")
	var meta := _mirror_meta(card_id)
	assert_eq(str(meta.get("zone", "")), "prizes",
			"The hotseat keeps the card in the opponent prize area")
	var mirror = Multiplayer._sync.find_remote_card(card_id)
	assert_true(is_instance_valid(mirror),
			"The prize card is drawn as a mirror")
	if mirror:
		assert_eq(str(mirror.definition_key()), CHAR_NAME,
				"The mirror keeps the knocked out card")


func test_prizes_reaching_fifteen_win_the_match():
	yield(_start_match(), "completed")

	var first := _place_character()
	_attach_energy(first)
	board.damage_character(first, 1)
	yield(yield_for(0.1), YIELD)
	assert_eq(board._victory_slot, 0,
			"Ten energy in the prizes does not win yet")

	var second := _place_character()
	_attach_energy(second)
	board.damage_character(second, 1)
	yield(yield_for(0.1), YIELD)
	assert_eq(board._victory_slot, 2,
			"Twenty energy in the seat two prizes wins the match for seat two")


func test_only_the_first_side_to_reach_fifteen_wins():
	var setup = setup_board()
	if setup is GDScriptFunctionState:
		setup = yield(setup, "completed")

	board.report_prize_energy(1, 14)
	assert_eq(board._victory_slot, 0, "Fourteen energy is not enough")
	board.report_prize_energy(1, 15)
	assert_eq(board._victory_slot, 1, "Fifteen energy wins for that side")
	board.report_prize_energy(2, 16)
	assert_eq(board._victory_slot, 1, "The match keeps its first winner")
	assert_eq(board.prize_owner_name(1), "P1",
			"The winner is named after the seat")


# The knocked out character belongs to the other seat, so the swap turns the
# mirror into a real card of the controlled player's prize pile.
func test_swapping_seats_moves_the_prize_card_to_the_other_pile():
	yield(_start_match(), "completed")

	var card := _place_character()
	var card_id := Multiplayer.ensure_card_id(card)
	_attach_energy(card)
	board.damage_character(card, 1)
	yield(yield_for(0.1), YIELD)

	assert_true(Multiplayer.swap_solo_seat(), "The swap changes the seat")
	yield(yield_for(0.3), YIELD)

	var prizes = board.get_node_or_null("Prêmios")
	var found := false
	if prizes:
		for child in prizes.get_children():
			if child is Card and str(child.network_id) == str(card_id):
				found = true
	assert_true(found, "The prize card belongs to the new controlled seat")
	assert_eq(board.local_prize_energy(), 10,
			"The prize pile scores the printed energy of the card")
