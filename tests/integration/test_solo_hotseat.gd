extends "res://tests/UTcommon.gd"


func after_each():
	Multiplayer.leave_session()
	cfc.card_definitions.erase(IMPORTED_KEY)


func _sixty_card_deck(deck_name: String) -> Dictionary:
	var cards := {}
	for index in range(6):
		cards[deck_name + " " + str(index)] = 10
	return {"name": deck_name, "cards": cards}


func test_solo_session_opens_in_preparation_with_both_seats_local():
	var result := Multiplayer.begin_solo("Doug")

	assert_true(result.get("ok", false),
			"The solo session opens without touching the relay")
	assert_true(Rede.is_solo, "The transport marks the session as solo")
	assert_true(Rede.is_host(), "The solo player is the authority of both seats")
	assert_true(Multiplayer.is_solo(), "The session runs in solo mode")
	assert_eq(Multiplayer.my_slot, 1, "The solo player starts on seat one")
	assert_eq(Multiplayer.opponent_slot, 2, "Seat two is the mirrored seat")
	assert_eq(Multiplayer.get_my_username(), "P1", "Seat one reads as P1")
	assert_eq(Multiplayer.get_opponent_username(), "P2", "Seat two reads as P2")
	assert_true(Multiplayer.is_preparing(), "The solo session waits for two decks")


func test_solo_preparation_takes_one_deck_per_seat():
	Multiplayer.begin_solo("Doug")

	Multiplayer.select_deck(_sixty_card_deck("A"))
	assert_eq(Multiplayer.local_deck_name, "A",
			"The picked seat is seat one at the start")
	assert_false(Multiplayer.are_both_decks_ready(),
			"One deck is not enough to start")

	Multiplayer.set_solo_pick_slot(2)
	Multiplayer.select_deck(_sixty_card_deck("B"))
	assert_eq(Multiplayer.opponent_deck_name, "B",
			"The second deck goes to the mirrored seat")
	assert_true(Multiplayer.opponent_deck_ready,
			"A full second deck counts as ready without a peer")
	assert_true(Multiplayer.are_both_decks_ready(),
			"Two full decks let the solo match start")


func test_solo_hidden_payload_splits_the_sixty_cards_of_a_seat():
	var payload: Dictionary = Multiplayer._solo_hidden_payload(
			_sixty_card_deck("A"), 2, "seed")

	assert_eq(payload.get("hand", []).size(), 10,
			"The mirrored seat keeps ten cards in hand")
	assert_eq(payload.get("deck", []).size(), 50,
			"The other fifty stay in its deck")
	var ids := {}
	for entry in payload["hand"] + payload["deck"]:
		ids[str(entry["id"])] = true
	assert_eq(ids.size(), 60, "Every card of the seat keeps a unique id")


func test_solo_hidden_payload_is_seeded_per_seat():
	var deck := _sixty_card_deck("A")
	var seat_two: Dictionary = Multiplayer._solo_hidden_payload(deck, 2, "seed")
	var same_seed: Dictionary = Multiplayer._solo_hidden_payload(deck, 2, "seed")
	var seat_one: Dictionary = Multiplayer._solo_hidden_payload(deck, 1, "seed")

	assert_eq(_hand_names(same_seed), _hand_names(seat_two),
			"The same seed shuffles the same seat the same way")
	assert_ne(_hand_names(seat_one), _hand_names(seat_two),
			"Each seat gets its own shuffle")


# Dictionaries compare by reference in GDScript, so the shuffle is checked by
# the card names instead of the whole entries.
func _hand_names(payload: Dictionary) -> Array:
	var names := []
	for entry in payload.get("hand", []):
		names.append(str(entry["name"]))
	return names


func test_solo_swap_waits_for_a_running_match():
	Multiplayer.begin_solo("Doug")

	assert_false(Multiplayer.swap_solo_seat(),
			"Swapping seats before the match starts changes nothing")
	assert_eq(Multiplayer.my_slot, 1, "The solo player stays on seat one")


#-----------------------------------------------------------------------------
# Swapping seats inside a running match
#-----------------------------------------------------------------------------

func _sixty_test_deck() -> Dictionary:
	return {
		"name": "Teste",
		"cards": {"Test Card 1": 20, "Test Card 2": 20, "Test Card 3": 20},
	}


# An imported deck registers each card under the id of the database, which is
# written without accents, while the definition keeps the accented text shown
# on the card. The clone reproduces that split inside GUT.
const IMPORTED_KEY := "diag-imported-card"


func _imported_name_definition() -> Dictionary:
	var definition: Dictionary = cfc.card_definitions["Test Card 1"].duplicate(true)
	definition["Name"] = "Carta Importada Áé"
	return definition


func _imported_name_deck() -> Dictionary:
	return {
		"name": "Importado",
		"cards": {IMPORTED_KEY: 20, "Test Card 2": 20, "Test Card 3": 20},
	}


func _free_all_cards() -> void:
	for card in get_tree().get_nodes_in_group("cards"):
		if not (card is Card) or not is_instance_valid(card):
			continue
		var parent = card.get_parent()
		if parent:
			parent.remove_child(card)
		card.queue_free()


# The board of a real match starts empty, so the deck the match builds is the
# only source of cards and the hidden counts stay at sixty per seat. With
# opponent_band the test adds the opponent scene box the shipped board lays
# out, because the mirror geometry reads its rect and the UT board has none.
func _start_solo_match(deck: Dictionary = {}, extra_definitions: Dictionary = {},
		opponent_band := false) -> void:
	if deck.empty():
		deck = _sixty_test_deck()
	var setup = setup_board()
	if setup is GDScriptFunctionState:
		setup = yield(setup, "completed")
	var grid = load("res://src/custom/CGFPlacementGridDemo.tscn").instance()
	grid.name = "PlacementGridDemo"
	board.add_child(grid)
	autofree(grid)
	yield(yield_for(0.2), YIELD)
	if opponent_band:
		var visual := Control.new()
		visual.name = "OpponentFieldVisual"
		board.add_child(visual)
		autofree(visual)
		var scene := Control.new()
		scene.name = "OpponentScene"
		visual.add_child(scene)
		yield(yield_for(0.1), YIELD)
		scene.rect_size = grid.rect_size
		scene.rect_global_position = Vector2(grid.rect_global_position.x,
				grid.rect_global_position.y - grid.rect_size.y - 40.0)
		yield(yield_for(0.1), YIELD)
	_free_all_cards()
	yield(yield_for(0.2), YIELD)

	Multiplayer.begin_solo("Doug")
	# A match started from the menu builds its board inside the session, and the
	# board creates the sync node and registers it there; the GUT board has
	# neither, so the test wires them the same way.
	var sync = load("res://src/custom/MultiplayerSync.gd").new()
	sync.name = "MultiplayerSync"
	board.add_child(sync)
	autofree(sync)
	Multiplayer.register_board(board, null, sync)
	yield(yield_for(0.1), YIELD)
	# Setting the board up reloads the set definitions, so a card invented by
	# the test is only registered from here on.
	for card_key in extra_definitions:
		cfc.card_definitions[card_key] = extra_definitions[card_key]
	Multiplayer.select_deck(deck)
	Multiplayer.set_solo_pick_slot(2)
	Multiplayer.select_deck(deck)
	assert_true(Multiplayer.request_start(), "Two full decks start the solo match")
	assert_true(Multiplayer.is_playing(), "The solo match is running")
	# The hand is only laid out after the deferred pass the match schedules.
	yield(yield_for(0.3), YIELD)


func _scene_grid() -> BoardPlacementGrid:
	return board.get_node("PlacementGridDemo") as BoardPlacementGrid


func _take_hand_card() -> Card:
	for child in cfc.NMAP.hand.get_children():
		if child is Card and is_instance_valid(child):
			return child
	return null


# Places a card the way a dropped one rests: child of the board, held by the
# scene slot, so the public state records it with its slot index.
func _place_scene_card(slot_index: int) -> Card:
	var slot: BoardPlacementSlot = _scene_grid().get_slot(slot_index)
	var card := _take_hand_card()
	if not card:
		return null
	cfc.NMAP.hand.remove_child(card)
	board.add_child(card)
	card.set_is_faceup(true, true)
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	card.global_position = slot.rect_global_position
	card._placement_slot = slot
	slot.occupying_card = card
	return card


# The scenario slot lives in the real board, so the card only needs the type
# property that makes the sync layer report it as a scenario.
func _place_scenario_card() -> Card:
	var card := _take_hand_card()
	if not card:
		return null
	cfc.NMAP.hand.remove_child(card)
	board.add_child(card)
	card.properties["_tipo"] = "Cenário"
	card.set_is_faceup(true, true)
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	return card


func _local_field_cards() -> Array:
	var found := []
	for card in get_tree().get_nodes_in_group("cards"):
		if not (card is Card) or not is_instance_valid(card) \
				or not card.is_inside_tree() or card.network_mirror \
				or card.get_parent() != board:
			continue
		found.append(card)
	return found


func _mirrored_field_cards() -> Array:
	var found := []
	# Mirrors leave the cards group when they are built, so the remote group is
	# the one that holds them. The opponent's hand is shown with placeholder
	# mirrors too, and those are not part of the field.
	var sync = Multiplayer._sync
	var placeholders = sync._hand_placeholders if sync else []
	for card in get_tree().get_nodes_in_group("remote_cards"):
		if not (card is Card) or not is_instance_valid(card) \
				or not card.is_inside_tree() or not card.network_mirror:
			continue
		if card in placeholders:
			continue
		found.append(card)
	return found


# Nodes freed by a rebuild only leave the tree at the end of the frame, so the
# counts are taken one frame after the table changed.
func _settle() -> void:
	yield(yield_for(0.1), YIELD)


func _assert_fields(label: String, local_count: int, mirrored_count: int) -> void:
	assert_eq(_local_field_cards().size(), local_count,
			label + " shows the controlled field")
	assert_eq(_mirrored_field_cards().size(), mirrored_count,
			label + " shows the other field")


# Two players sit across from each other, so the other field is the same box
# seen from the opposite side: the mirror lands on the mirrored slot and reads
# upside down.
func test_mirror_of_a_scene_card_keeps_the_other_side_geometry():
	yield(_start_solo_match({}, {}, true), "completed")

	_place_scene_card(1)
	var free := _take_hand_card()
	var free_id := Multiplayer.ensure_card_id(free)
	cfc.NMAP.hand.remove_child(free)
	board.add_child(free)
	free.set_is_faceup(true, true)
	free.set_state(Card.CardState.ON_PLAY_BOARD)
	free.global_position = _scene_grid().rect_global_position \
			+ _scene_grid().rect_size * 0.35
	yield(_settle(), "completed")
	var placed: Card = _local_field_cards()[0]
	var placed_slot: int = Multiplayer._sync._slot_index(placed._placement_slot)

	assert_true(Multiplayer.swap_solo_seat(), "The swap shows the other seat")
	yield(yield_for(0.7), YIELD)
	var mirrors := _mirrored_field_cards()
	assert_eq(mirrors.size(), 2, "The other field shows both mirrors")
	for mirror in mirrors:
		assert_almost_eq(float(mirror.get_node("Control").rect_rotation), 180.0,
				0.5, "The mirror is drawn upside down")
	var slotted: Card = null
	var loose: Card = null
	for mirror in mirrors:
		if str(mirror.network_id) == str(free_id):
			loose = mirror
		else:
			slotted = mirror
	assert_not_null(slotted, "The slotted card has a mirror")
	assert_not_null(loose, "The loose card has a mirror")
	if slotted:
		var expected: Rect2 = Multiplayer._sync._mirrored_slot_rect(placed_slot)
		assert_true(expected.size.x > 0.0, "The slot mirrors into the other band")
		assert_almost_eq(slotted.global_position, expected.position,
				Vector2(2, 2), "The mirror sits on the mirrored slot")
	if loose:
		var travel: Vector2 = Multiplayer._sync._normalize_board_position(
				free.global_position)
		var point: Vector2 = Multiplayer._sync._mirrored_board_point(
				travel, CFConst.CARD_SIZE * Multiplayer._sync.BOARD_SCALE)
		assert_almost_eq(loose.global_position, point, Vector2(2, 2),
				"A loose card mirrors through the table centre")

	assert_true(Multiplayer.swap_solo_seat(), "Swapping back returns the seat")
	yield(_settle(), "completed")
	var own := _local_field_cards()
	assert_eq(own.size(), 2, "The field comes back with both cards")
	for card in own:
		if str(card.network_id) == str(free_id):
			continue
		assert_eq(Multiplayer._sync._slot_index(card._placement_slot),
				placed_slot, "The card returns to the slot it was placed on")
		assert_eq(int(card.get_node("Control").rect_rotation), 0,
				"The card returns upright")


func test_three_solo_swaps_keep_both_fields_populated():
	yield(_start_solo_match(), "completed")

	_place_scene_card(0)
	yield(_settle(), "completed")
	_assert_fields("P1 opening", 1, 0)

	assert_true(Multiplayer.swap_solo_seat(), "Swap one changes the seat")
	assert_eq(Multiplayer.my_slot, 2, "Swap one moves to P2")
	yield(_settle(), "completed")
	_assert_fields("After swap one", 0, 1)

	_place_scene_card(1)
	yield(_settle(), "completed")
	_assert_fields("After P2 plays", 1, 1)

	assert_true(Multiplayer.swap_solo_seat(), "Swap two changes the seat")
	assert_eq(Multiplayer.my_slot, 1, "Swap two returns to P1")
	yield(_settle(), "completed")
	_assert_fields("After swap two", 1, 1)

	assert_true(Multiplayer.swap_solo_seat(), "Swap three changes the seat")
	assert_eq(Multiplayer.my_slot, 2, "Swap three moves to P2 again")
	yield(_settle(), "completed")
	_assert_fields("After swap three", 1, 1)


# cfc.ut is what keeps the sync layer from running the production reconciliation
# under GUT, so the swap loop clears it to reach the same code the game runs.
func test_solo_swaps_with_a_scenario_keep_both_fields():
	yield(_start_solo_match(), "completed")

	_place_scene_card(0)
	var scenario := _place_scenario_card()
	assert_not_null(scenario, "A scenario reaches the field")
	yield(_settle(), "completed")
	_assert_fields("P1 with a scenario", 2, 0)

	cfc.ut = false
	assert_true(Multiplayer.swap_solo_seat(), "Swap one changes the seat")
	yield(_settle(), "completed")
	_assert_fields("After swap one", 0, 2)

	assert_true(Multiplayer.swap_solo_seat(), "Swap two changes the seat")
	yield(_settle(), "completed")
	_assert_fields("After swap two", 2, 0)

	assert_true(Multiplayer.swap_solo_seat(), "Swap three changes the seat")
	yield(_settle(), "completed")
	_assert_fields("After swap three", 0, 2)
	cfc.ut = true


# Imported decks are the case that broke the hotseat: a card saved under an
# id-only key but labelled with the accented name cannot be found again by the
# restore path, and the seat came back empty.
func test_solo_swap_restores_cards_imported_under_another_key():
	yield(_start_solo_match(_imported_name_deck(),
			{IMPORTED_KEY: _imported_name_definition()}), "completed")

	_place_scene_card(0)
	yield(_settle(), "completed")
	assert_gt(_live_hidden_count("hand"), 0, "The opening hand holds cards")

	assert_true(Multiplayer.swap_solo_seat(), "Swap one changes the seat")
	yield(_settle(), "completed")
	_assert_payloads_are_restorable("After swap one")
	assert_gt(_live_hidden_count("hand") + _live_hidden_count("deck"), 50,
			"Swap one restores the other seat with its cards")

	assert_true(Multiplayer.swap_solo_seat(), "Swap two returns to P1")
	yield(_settle(), "completed")
	_assert_payloads_are_restorable("After swap two")
	assert_gt(_live_hidden_count("hand") + _live_hidden_count("deck"), 50,
			"Swap two restores the first seat with its cards")


func _live_hidden_count(map_key: String) -> int:
	var pile = cfc.NMAP.get(map_key, null)
	if not pile:
		return 0
	var count := 0
	for child in pile.get_children():
		if child is Card and is_instance_valid(child) and not child.network_mirror:
			count += 1
	return count


func _assert_payloads_are_restorable(label: String) -> void:
	for slot in [1, 2]:
		var payload: Dictionary = Multiplayer._solo_hidden.get(slot, {})
		var entries = payload.get("hand", []) + payload.get("deck", [])
		for entry in entries:
			assert_true(cfc.card_definitions.has(str(entry.get("name", ""))),
					label + " keeps seat " + str(slot) + " restorable")
