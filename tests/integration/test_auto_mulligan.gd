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


# A abertura do turno (inclusive a do início da partida) paga Contagem Regressiva
# e Compra sozinha e para na Preparação.
func _wait_for_auto_phase(wanted: String, timeout := 5.0) -> bool:
	var waited := 0.0
	while waited < timeout:
		if Multiplayer.phase == wanted \
				and not Multiplayer.is_auto_turn_running():
			return true
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return false


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
	var expected := [[8, 2], [6, 4], [4, 6], [2, 8]]
	for step in expected:
		assert_true(Multiplayer.manual_mulligan_local(), "The mulligan ran")
		assert_eq(_hand_cards().size(), int(step[0]), "Hand after the mulligan")
		assert_eq(cfc.NMAP.discard.get_all_cards().size(), int(step[1]),
				"Resources after the mulligan")

	# The fifth one empties the hand, which the seat keeps at once, and the
	# hotseat hands the table to the other seat. Bring the empty seat back.
	assert_true(Multiplayer.manual_mulligan_local(), "The last mulligan ran")
	Multiplayer.swap_solo_seat()
	await yield_for(0.3)
	assert_eq(_hand_cards().size(), 0, "Hand after the mulligan")
	assert_eq(cfc.NMAP.discard.get_all_cards().size(), 10,
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


# --- The mulligan window (AUTOTURNO.md §3.2, decision 12) ---------------

func test_the_window_holds_the_first_phase():
	await _start(_deck(60, 0), _deck(60, 0))

	assert_true(Multiplayer.is_mulligan_open(), "The deal opens the window")
	assert_false(Multiplayer.advance_phase(), "No phase runs during the mulligan")

	assert_true(Multiplayer.accept_local_hand(), "The visible seat keeps its hand")
	assert_true(Multiplayer.is_mulligan_open(), "The other seat still has to answer")

	# The hotseat already handed the table to the seat that owes the answer.
	await yield_for(0.3)
	assert_true(Multiplayer.is_mulligan_open(), "The new seat has its own decision")
	assert_true(Multiplayer.accept_local_hand(), "The second seat keeps its hand")

	assert_false(Multiplayer.is_mulligan_open(), "Both seats answered")
	assert_true(Multiplayer.is_prep_game_open(), "The preparation window opens")
	assert_false(Multiplayer.advance_phase(), "The preparation holds the first turn")

	assert_true(Multiplayer.ready_local_prep_game(), "The visible seat is ready")
	await yield_for(0.3)
	assert_true(Multiplayer.ready_local_prep_game(), "The second seat is ready")

	assert_false(Multiplayer.is_prep_game_open(), "Both seats answered")
	# The countdown and the draw of the opening pay themselves; the table stops
	# on Preparação without asking for a click.
	assert_true(await _wait_for_auto_phase("PREP"),
			"The automatic opening reached Preparação")
	assert_eq(Multiplayer.step_index, 2, "REG and DRAW were passed by themselves")


# While a seat has not answered, the table only accepts the hand card going to
# the resources: everything else would change the board before the first turn.
func test_the_mulligan_blocks_every_action_but_hand_to_resources():
	await _start(_deck(60, 0), _deck(60, 0))
	assert_true(Multiplayer.is_mulligan_open(), "The deal opens the window")

	var character = _hand_cards()[0]
	var played: Dictionary = board.apply_intent({
			"op": "jogar", "card": character})
	assert_false(bool(played.get("ok", false)),
			"Nada entra em cena durante o mulligan")
	assert_eq(str(played.get("error", "")), "fora_da_preparacao",
			"O motivo é a janela do mulligan")

	var resources_before: int = cfc.NMAP.discard.get_card_count()
	var discarded: Dictionary = board.apply_intent({
			"op": "descartar", "card": character})
	assert_true(bool(discarded.get("ok", false)),
			"Enviar uma carta da mão para os Recursos continua liberado")
	assert_eq(resources_before + 1, cfc.NMAP.discard.get_card_count(),
			"A carta da mão chegou aos Recursos")


# The hotseat hands the table to the seat that still owes an answer, so the
# player never has to press "Controlar P2" to reach the second panel.
func test_the_hotseat_hands_the_mulligan_to_the_other_seat():
	await _start(_deck(60, 0), _deck(60, 0))

	var first := Multiplayer.my_slot
	assert_true(Multiplayer.accept_local_hand(), "The visible seat keeps its hand")
	assert_eq(Multiplayer.my_slot, 3 - first, "The table passed to the other seat")
	assert_false(bool(Multiplayer.get_mulligan_info()["waiting_for_opponent"]),
			"The other seat has its own answer left")


func test_empty_hand_keeps_itself_and_waits():
	await _start(_deck(60, 0), _deck(60, 0))

	# Decision 6b: the fifth mulligan leaves an empty hand, which is kept at once.
	for _step in range(TurnRules.manual_mulligan_sequence().size()):
		assert_true(Multiplayer.manual_mulligan_local(), "The mulligan ran")

	# The keep already moved the hotseat to the other seat, which still owes its
	# answer, so the empty seat has to be brought back to be inspected.
	Multiplayer.swap_solo_seat()
	await yield_for(0.3)
	var info := Multiplayer.get_mulligan_info()
	assert_eq(int(info["hand_size"]), 0, "The hand went all the way down")
	assert_true(bool(info["waiting_for_opponent"]), "The empty hand is already kept")
	assert_false(Multiplayer.accept_local_hand(), "It answered only once")
	assert_true(Multiplayer.is_mulligan_open(), "Still waiting for the other seat")


func test_mulligan_counter_is_per_seat():
	await _start(_deck(60, 0), _deck(60, 0))

	Multiplayer.manual_mulligan_local()
	var info := Multiplayer.get_mulligan_info()
	assert_eq(int(info["repetition"]), 1, "The seat counted its mulligan")
	assert_eq(int(info["max_repetitions"]), 5, "The counter shows the whole ladder")

	Multiplayer.swap_solo_seat()
	await yield_for(0.3)
	var other := Multiplayer.get_mulligan_info()
	assert_eq(int(other["repetition"]), 0, "The other seat starts its own count")
	assert_eq(int(other["hand_size"]), TurnRules.HAND_SIZE,
			"The seat that took the table has its own ten cards")


# AUTOTURNO.md §4.1, item 5: a player that reconnects has to land on the same
# rung of the ladder, so the per-seat counter travels in the public state.
func test_the_mulligan_ladder_travels_in_the_public_state():
	await _start(_deck(60, 0), _deck(60, 0))

	Multiplayer.manual_mulligan_local()
	var state := Multiplayer._build_public_state(Multiplayer.sequence)
	var counts: Dictionary = state.get("mulligan_counts", {})
	assert_eq(int(counts.get(str(Multiplayer.my_slot), 0)), 1,
			"The seat's repetition is in the state the peers share")

	Multiplayer._mulligan_counts = {}
	assert_eq(int(Multiplayer.get_mulligan_info()["repetition"]), 0,
			"The local count really went away")
	Multiplayer._absorb_turn_state(state)
	assert_eq(int(Multiplayer.get_mulligan_info()["repetition"]), 1,
			"Absorbing the state puts the rung back")

