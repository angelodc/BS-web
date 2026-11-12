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


func _wait_for_auto_phase(wanted: String, timeout := 5.0) -> bool:
	var waited := 0.0
	while waited < timeout:
		if Multiplayer.phase == wanted \
				and not Multiplayer.is_auto_turn_running():
			return true
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return false


var _logged_lines := []


func _on_action_logged(text: String) -> void:
	_logged_lines.append(text)


func test_the_turn_walks_the_six_phases_and_alternates():
	await _start_and_keep_both_hands()

	var starter := Multiplayer.starting_slot
	var other := 3 - starter
	# The preparation window closes on the countdown and the draw; the match
	# pays both and stops on Preparação like any other turn opening.
	assert_true(await _wait_for_auto_phase("PREP"),
			"A abertura da partida chegou a Preparação")
	assert_eq(Multiplayer.step_index, 2, "REG e DRAW passaram sozinhos")
	assert_eq(Multiplayer.round_number, 1)
	assert_eq(Multiplayer.phase, "PREP")
	assert_eq(Multiplayer.get_actor_slot(), starter)
	assert_eq(Multiplayer.my_slot, starter, "O hotseat segue quem age")

	# The Ajuste has nothing to adjust on this turn, so it passes by itself;
	# Antecipação is the first step that needs the human again.
	assert_true(Multiplayer.advance_phase(), "A Preparação avançou")
	await yield_for(0.1)
	assert_eq(Multiplayer.phase, "ADJ", "O Ajuste abriu")
	assert_true(await _wait_for_auto_phase("ANT"), "O Ajuste vazio passou sozinho")
	assert_eq(Multiplayer.step_index, 4, "O Ajuste foi pulado")
	assert_eq(Multiplayer.get_actor_slot(), other, "Antecipação é do oponente")
	assert_eq(Multiplayer.my_slot, other, "O hotseat segue o oponente")

	assert_true(Multiplayer.advance_phase(), "A Antecipação passou")
	await yield_for(0.1)
	assert_eq(Multiplayer.phase, "ATK", "O primeiro turno chega a Ataque")
	assert_eq(Multiplayer.my_slot, starter)

	# Ataque closes the first turn; the other seat's countdown and draw are paid
	# and passed on their own, and the table stops on Preparação.
	assert_true(Multiplayer.advance_phase(), "Ataque fecha o primeiro turno")
	assert_true(await _wait_for_auto_phase("PREP"), "A abertura automática chegou a PREP")
	assert_eq(Multiplayer.step_index, 8, "REG e DRAW foram passados por si")
	assert_eq(Multiplayer.phase, "PREP", "A mesa para na Preparação")
	assert_eq(Multiplayer.round_number, 1)
	assert_eq(Multiplayer.get_actor_slot(), other)
	assert_eq(Multiplayer.my_slot, other, "O hotseat segue o outro assento")

	# The rest of the turn walks the same way up to the round wrap.
	assert_true(Multiplayer.advance_phase(), "A Preparação do outro assento passou")
	await yield_for(0.1)
	assert_true(await _wait_for_auto_phase("ANT"), "O Ajuste vazio passou sozinho")
	assert_eq(Multiplayer.get_actor_slot(), starter, "Antecipação é do oponente")
	assert_true(Multiplayer.advance_phase(), "A Antecipação passou")
	await yield_for(0.1)
	assert_eq(Multiplayer.phase, "ATK", "O segundo turno chega a Ataque")

	# The twelfth step closes the round; the next round opens with the same
	# automatic countdown and draw.
	assert_true(Multiplayer.advance_phase(), "A rodada virou")
	assert_true(await _wait_for_auto_phase("PREP"), "A rodada nova chegou a PREP")
	assert_eq(Multiplayer.step_index, 2, "REG e DRAW foram passados")
	assert_eq(Multiplayer.round_number, 2, "Os dois turnos fazem uma rodada")
	assert_eq(Multiplayer.phase, "PREP", "A rodada nova para na Preparação")
	assert_eq(Multiplayer.get_actor_slot(), starter,
			"O iniciante abre a rodada nova")


func test_the_automatic_opening_logs_both_phases_in_one_line():
	_logged_lines = []
	Multiplayer.action_logged.connect(_on_action_logged)
	await _start_and_keep_both_hands()
	assert_true(await _wait_for_auto_phase("PREP"),
			"A abertura da partida chegou a Preparação")
	# The first turn of the match draws nothing, so only the countdown moves a
	# card — and the two phases still share one line.
	assert_true(_logged_lines.has(
			"Contagem Regressiva e Compra: 1 carta para os Recursos + 0 compras."),
			"A abertura da partida é uma linha só")

	# The next opening pays the draw of a seat without characters in play.
	_logged_lines = []
	assert_true(Multiplayer.advance_phase(), "A Preparação passou")
	await yield_for(0.1)
	assert_true(await _wait_for_auto_phase("ANT"), "O Ajuste vazio passou")
	assert_true(Multiplayer.advance_phase(), "A Antecipação passou")
	await yield_for(0.1)
	assert_true(Multiplayer.advance_phase(), "Ataque fecha o primeiro turno")
	assert_true(await _wait_for_auto_phase("PREP"), "A segunda abertura chegou a PREP")
	Multiplayer.action_logged.disconnect(_on_action_logged)
	assert_true(_logged_lines.has(
			"Contagem Regressiva e Compra: 1 carta para os Recursos + 1 compra."),
			"A abertura é uma linha com as duas contagens")
