extends "res://tests/UTcommon.gd"

# The turn is the six official phases and the round is the two turns of the
# match (AUTOTURNO.md §3.4). Who acts on each step comes from the step itself,
# so the sequence has one source of truth instead of a hand written table.

const CHAR := "Char Fases"
const SUP := "Suporte Fases"


func after_each():
	Multiplayer.leave_session()
	cfc.card_definitions.erase(CHAR)
	cfc.card_definitions.erase(SUP)


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
	_free_all_cards()
	await yield_for(0.2)
	cfc.card_definitions[CHAR] = _definition(CHAR, "Personagem")
	cfc.card_definitions[SUP] = _definition(SUP, "Suporte")


# --- The step model, without a table ---------------------------------------

func test_a_round_is_two_turns_of_six_phases():
	assert_eq(Multiplayer.get_steps_per_round(),
			Multiplayer.TURN_PHASES.size() * 2)
	var expected: Array[String] = ["REG", "DRAW", "PREP", "ADJ", "ANT", "ATK"]
	for step in range(Multiplayer.get_steps_per_round()):
		assert_eq(Multiplayer.phase_for_step(step),
				expected[step % expected.size()], "Phase of step " + str(step))


func test_the_turn_owner_acts_except_on_antecipacao():
	Multiplayer.starting_slot = 1
	var starter := 1
	var other := 2
	for step in range(Multiplayer.get_steps_per_round()):
		var owner := starter if step < 6 else other
		var expected := (3 - owner) \
				if Multiplayer.phase_for_step(step) == "ANT" else owner
		Multiplayer.step_index = step
		assert_eq(Multiplayer.get_actor_slot(), expected,
				"Actor of step " + str(step))
	Multiplayer.step_index = 0


func test_only_the_first_turn_of_the_match_does_not_draw():
	Multiplayer.starting_slot = 1
	Multiplayer.round_number = 1
	for step in range(Multiplayer.get_steps_per_round()):
		Multiplayer.step_index = step
		assert_eq(Multiplayer.is_first_turn_of_match(), step < 6,
				"First turn flag of step " + str(step))
	Multiplayer.step_index = 0
	Multiplayer.round_number = 2
	assert_false(Multiplayer.is_first_turn_of_match(),
			"Round two is never the first turn")
	Multiplayer.round_number = 1


# --- The real walk, in the hotseat -------------------------------------------

func _start_and_keep_both_hands() -> void:
	Multiplayer.begin_solo("Doug")
	var sync = load("res://src/custom/MultiplayerSync.gd").new()
	sync.name = "MultiplayerSync"
	board.add_child(sync)
	autofree(sync)
	Multiplayer.register_board(board, null, sync)
	await yield_for(0.1)
	Multiplayer.select_deck(_deck(60, 0))
	Multiplayer.set_solo_pick_slot(2)
	Multiplayer.select_deck(_deck(60, 0))
	assert_true(Multiplayer.request_start(), "The two decks start the match")
	await yield_for(0.4)
	# Every seat has to keep its hand before the first turn opens (§3.2). The
	# hotseat hands the table to the seat that still owes an answer.
	Multiplayer.accept_local_hand()
	await yield_for(0.3)
	Multiplayer.accept_local_hand()
	await yield_for(0.1)
	assert_false(Multiplayer.is_mulligan_open(), "Both seats answered")

	# The preparation window is the second gate before the first turn (§3.3), so
	# each seat discards and answers for itself here too.
	assert_true(Multiplayer.is_prep_game_open(), "The preparation window opened")
	assert_false(Multiplayer.advance_phase(), "The preparation holds the first turn")
	assert_true(Multiplayer.ready_local_prep_game(), "The visible seat is ready")
	assert_true(Multiplayer.is_prep_game_open(), "The other seat still has to answer")
	await yield_for(0.3)
	assert_true(Multiplayer.ready_local_prep_game(), "The second seat is ready")
	assert_false(Multiplayer.is_prep_game_open(), "Both seats answered")
	await yield_for(0.1)


func test_the_turn_walks_the_six_phases_and_alternates():
	await _start_and_keep_both_hands()

	var starter := Multiplayer.starting_slot
	var other := 3 - starter
	var expected: Array[String] = ["REG", "DRAW", "PREP", "ADJ", "ANT", "ATK"]
	assert_eq(Multiplayer.phase, "REG", "The match opens on Contagem Regressiva")
	assert_eq(Multiplayer.round_number, 1)
	assert_eq(Multiplayer.my_slot, Multiplayer.get_actor_slot(),
			"The hotseat opens on the seat that acts")

	for step in range(Multiplayer.get_steps_per_round() - 1):
		assert_true(Multiplayer.advance_phase(), "The step " + str(step) + " ran")
		await yield_for(0.1)
		var wanted := expected[(step + 1) % expected.size()]
		assert_eq(Multiplayer.phase, wanted, "Phase after step " + str(step))
		var owner := starter if (step + 1) < 6 else other
		var wanted_actor := (3 - owner) if wanted == "ANT" else owner
		assert_eq(Multiplayer.get_actor_slot(), wanted_actor,
				"Actor of " + wanted)
		assert_eq(Multiplayer.my_slot, wanted_actor,
				"The hotseat follows the actor of " + wanted)

	# The twelfth step closes the round and the counter starts again at REG.
	assert_true(Multiplayer.advance_phase(), "The round wrapped")
	await yield_for(0.1)
	assert_eq(Multiplayer.step_index, 0, "The round ended on the last step")
	assert_eq(Multiplayer.round_number, 2, "Both turns make one round")
	assert_eq(Multiplayer.phase, "REG", "The next round opens on REG")
