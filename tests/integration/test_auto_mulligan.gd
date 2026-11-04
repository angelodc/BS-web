extends "res://tests/UTcommon.gd"

# The automatic mulligan has to leave a legal hand without ever losing or
# duplicating cards, and it has to stop at the guard when the deck simply has
# no second character to give (AUTOTURNO.md §3.1).

const CHAR := "Char Autoturno"
const SUP := "Suporte Autoturno"
const SWAP_MESSAGE := "foi trocada"

var _logs := []


func after_each():
	if Multiplayer.action_logged.is_connected(_on_log):
		Multiplayer.action_logged.disconnect(_on_log)
	Multiplayer.leave_session()
	cfc.card_definitions.erase(CHAR)
	cfc.card_definitions.erase(SUP)


func _on_log(message) -> void:
	_logs.append(str(message))


func _definition(base_name: String, tipo: String) -> Dictionary:
	var definition: Dictionary = \
			cfc.card_definitions["Test Card 1"].duplicate(true)
	definition["Name"] = base_name
	definition["_tipo"] = tipo
	return definition


func _deck(characters: int, supports: int) -> Dictionary:
	return {"name": "Teste", "cards": {CHAR: characters, SUP: supports}}


func _free_all_cards() -> void:
	for card in get_tree().get_nodes_in_group("cards"):
		if not (card is Card) or not is_instance_valid(card):
			continue
		var parent = card.get_parent()
		if parent:
			parent.remove_child(card)
		card.queue_free()


func before_each():
	await setup_board()
	# The board is reused between tests, so the previous deck has to go first.
	_free_all_cards()
	await yield_for(0.2)
	cfc.card_definitions[CHAR] = _definition(CHAR, "Personagem")
	cfc.card_definitions[SUP] = _definition(SUP, "Suporte")
	_logs = []
	Multiplayer.action_logged.connect(_on_log)
	Multiplayer.begin_solo("Doug")
	var sync = load("res://src/custom/MultiplayerSync.gd").new()
	sync.name = "MultiplayerSync"
	board.add_child(sync)
	autofree(sync)
	Multiplayer.register_board(board, null, sync)
	await yield_for(0.1)


func _start(same_deck: Dictionary, opponent_deck: Dictionary) -> void:
	Multiplayer.select_deck(same_deck)
	Multiplayer.set_solo_pick_slot(2)
	Multiplayer.select_deck(opponent_deck)
	assert_true(Multiplayer.request_start(), "The two full decks start the match")
	await yield_for(0.4)


func _hand_cards() -> Array:
	var cards := []
	for child in cfc.NMAP.hand.get_children():
		if child is Card and is_instance_valid(child):
			cards.append(child)
	return cards


func _hand_characters() -> int:
	return TurnRules.character_count(_hand_cards())


func _swap_count() -> int:
	var total := 0
	for entry in _logs:
		if SWAP_MESSAGE in entry:
			total += 1
	return total


func test_hand_with_characters_is_not_mulliganed():
	await _start(_deck(60, 0), _deck(60, 0))

	assert_eq(_hand_cards().size(), TurnRules.HAND_SIZE,
			"The hand keeps its ten cards")
	assert_eq(_hand_characters(), TurnRules.HAND_SIZE,
			"Every card in hand is a character")
	assert_eq(_swap_count(), 0, "No automatic mulligan was needed")


func test_mixed_deck_always_ends_with_two_characters():
	# With thirty characters the first hand usually is already legal, so the
	# assertion is about the outcome: whatever the shuffle, the hand is legal.
	await _start(_deck(30, 30), _deck(30, 30))

	assert_eq(_hand_cards().size(), TurnRules.HAND_SIZE,
			"The hand always has ten cards")
	assert_gte(_hand_characters(), TurnRules.AUTO_MULLIGAN_MIN_CHARACTERS,
			"The final hand has at least two characters")
	assert_eq(cfc.NMAP.deck.get_all_cards().size(), 60 - TurnRules.HAND_SIZE,
			"The deck keeps the other fifty cards")


func test_guard_stops_when_the_deck_has_no_second_character():
	# A single character in sixty cards: no shuffle can ever satisfy the rule,
	# so only the safety limit ends the loop.
	await _start(_deck(1, 59), _deck(1, 59))

	assert_eq(_hand_cards().size(), TurnRules.HAND_SIZE,
			"The guard still leaves a hand of ten")
	assert_lte(_hand_characters(), 1, "A single character cannot be doubled")
	assert_eq(_swap_count(), TurnRules.AUTO_MULLIGAN_LIMIT,
			"The loop ran exactly up to the guard")


func test_mulligan_never_loses_or_duplicates_cards():
	await _start(_deck(30, 30), _deck(30, 30))

	var ids := {}
	for card in get_tree().get_nodes_in_group("cards"):
		if not (card is Card) or not is_instance_valid(card):
			continue
		var net_id := str(card.network_id)
		if net_id.is_empty():
			continue
		assert_false(ids.has(net_id), "No card id is repeated: " + net_id)
		ids[net_id] = true
	# Only the local seat holds Card nodes in solo mode: the sixty cards of the
	# deck must still exist exactly once after any number of mulligans.
	assert_eq(ids.size(), 60,
			"Every card of the deck still exists exactly once")


# --- Manual mulligan ---------------------------------------------------

func test_mulligan_info_describes_the_next_step():
	await _start(_deck(60, 0), _deck(60, 0))

	var info := Multiplayer.get_mulligan_info()
	assert_eq(info["hand_size"], TurnRules.HAND_SIZE)
	assert_eq(info["cost"], 2)
	assert_eq(info["draw"], 8)
	assert_eq(info["repetition"], 0)
	assert_true(info["can_mulligan"])


func test_manual_mulligan_walks_the_planned_table():
	await _start(_deck(60, 0), _deck(60, 0))

	# AUTOTURNO.md §3.2: hand 8, 6, 4, 2, 0 and resources 2, 4, 6, 8, 10.
	var expected := [[8, 2], [6, 4], [4, 6], [2, 8], [0, 10]]
	for step in expected:
		assert_true(Multiplayer.manual_mulligan_local(), "The mulligan ran")
		assert_eq(_hand_cards().size(), int(step[0]), "Hand after the mulligan")
		assert_eq(cfc.NMAP.discard.get_all_cards().size(), int(step[1]),
				"Resources after the mulligan")

	assert_false(Multiplayer.manual_mulligan_local(),
			"An empty hand cannot be mulliganed again")
	assert_eq(cfc.NMAP.deck.get_all_cards().size(), 50,
			"The deck always keeps the other fifty cards")


func test_manual_mulligan_keeps_resources_out_of_the_shuffle():
	await _start(_deck(60, 0), _deck(60, 0))

	Multiplayer.manual_mulligan_local()
	var first_resources := {}
	for card in cfc.NMAP.discard.get_all_cards():
		first_resources[str(card.network_id)] = true
	assert_eq(first_resources.size(), 2)

	Multiplayer.manual_mulligan_local()
	assert_eq(cfc.NMAP.discard.get_all_cards().size(), 4)
	# The first two cards must still be there: resources never go back to the deck.
	var still_there := 0
	for card in cfc.NMAP.discard.get_all_cards():
		if first_resources.has(str(card.network_id)):
			still_there += 1
	assert_eq(still_there, 2, "The older resources stay put")
