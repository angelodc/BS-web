extends "res://tests/UTcommon.gd"

# The automatic steps of a turn are played by the client that owns the cards
# (AUTOTURNO.md §3.4), so these tests read the piles exactly like a player at
# the table would and only poke the step to reach the phase being tested.

const CHAR := "Char Efeitos"
const CHEAP_CHAR := "Char Um"
const SUP := "Suporte Efeitos"


func before_all():
	cfc.game_settings.fancy_movement = false


func after_all():
	cfc.game_settings.fancy_movement = true


func after_each():
	Multiplayer.leave_session()
	cfc.card_definitions.erase(CHAR)
	cfc.card_definitions.erase(CHEAP_CHAR)
	cfc.card_definitions.erase(SUP)


func _definition(base_name: String, tipo: String, energy: int) -> Dictionary:
	var definition: Dictionary = \
			cfc.card_definitions["Test Card 1"].duplicate(true)
	definition["Name"] = base_name
	definition["_tipo"] = tipo
	definition["ENERGIA"] = str(energy)
	return definition


func _deck(entries: Dictionary) -> Dictionary:
	return {"name": "Teste", "cards": entries}


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
	cfc.card_definitions[CHAR] = _definition(CHAR, "Personagem", 3)
	cfc.card_definitions[CHEAP_CHAR] = _definition(CHEAP_CHAR, "Personagem", 1)
	cfc.card_definitions[SUP] = _definition(SUP, "Suporte", 1)


# --- Table helpers -----------------------------------------------------

func _pile_size(nmap_key: String) -> int:
	var pile = cfc.NMAP.get(nmap_key, null)
	return pile.get_all_cards().size() if pile else 0


func _hand_cards() -> Array:
	var hand = cfc.NMAP.get("hand", null)
	return hand.get_all_cards() if hand else []


# Reaches a step of the current turn without walking the whole match. The
# starter becomes the seat on the table, so half zero always belongs to the
# seat whose automatic step the test is checking.
func _open_phase(step: int, match_round := 2) -> void:
	Multiplayer.starting_slot = Multiplayer.my_slot
	Multiplayer.round_number = match_round
	Multiplayer.step_index = step
	Multiplayer.phase = Multiplayer.phase_for_step(step)
	Multiplayer._effects_applied = {}


func _play_from_hand(card) -> bool:
	var played: Dictionary = board.apply_intent({"op": "jogar", "card": card})
	return bool(played.get("ok", false))


# --- The match start -----------------------------------------------------

func _start_match(entries: Dictionary) -> void:
	Multiplayer.begin_solo("Doug")
	var sync = load("res://src/custom/MultiplayerSync.gd").new()
	sync.name = "MultiplayerSync"
	board.add_child(sync)
	autofree(sync)
	Multiplayer.register_board(board, null, sync)
	await yield_for(0.1)
	Multiplayer.select_deck(_deck(entries))
	Multiplayer.set_solo_pick_slot(2)
	Multiplayer.select_deck(_deck(entries))
	assert_true(Multiplayer.request_start(), "Os dois decks iniciam a partida")
	await yield_for(0.4)
	Multiplayer.accept_local_hand()
	await yield_for(0.3)
	Multiplayer.accept_local_hand()
	await yield_for(0.1)
	assert_false(Multiplayer.is_mulligan_open(), "A janela de mulligan fechou")
	# The preparation window stands between the mulligan and the first turn
	# (AUTOTURNO.md §3.3), so each seat closes it for itself too. The table
	# follows the seat that still owes an answer.
	assert_true(Multiplayer.is_prep_game_open(), "A preparação abriu")
	Multiplayer.ready_local_prep_game()
	await yield_for(0.3)
	Multiplayer.ready_local_prep_game()
	await yield_for(0.1)
	assert_false(Multiplayer.is_prep_game_open(), "A preparação fechou")


func test_the_countdown_runs_when_the_prep_window_closes():
	await _start_match({CHAR: 60})
	# Whoever started the match owns the countdown; taking their seat is what
	# lets the pending step be played in the hotseat.
	if Multiplayer.get_turn_owner_slot() != Multiplayer.my_slot:
		Multiplayer.swap_solo_seat()
		await yield_for(0.3)
	assert_eq(_pile_size("discard"), 1, "A Contagem Regressiva deu 1 recurso")
	assert_eq(_pile_size("deck"), 49, "O topo do deck saiu")
	assert_eq(_hand_cards().size(), 10, "A contagem não compra para a mão")


func test_the_countdown_runs_only_once_per_step():
	await _start_match({CHAR: 60})
	if Multiplayer.get_turn_owner_slot() != Multiplayer.my_slot:
		Multiplayer.swap_solo_seat()
		await yield_for(0.3)
	assert_eq(_pile_size("discard"), 1, "O passo já tinha sido jogado")
	assert_false(Multiplayer.run_phase_effects(), "O mesmo passo não se repete")
	assert_eq(_pile_size("discard"), 1, "Nada foi entregue duas vezes")


# --- Contagem Regressiva -------------------------------------------------

func test_the_countdown_is_skipped_with_a_character_in_play():
	await _start_match({CHAR: 60})
	_open_phase(0)
	var before := _pile_size("discard")
	assert_true(_play_from_hand(_hand_cards()[0]), "O personagem entrou em cena")
	assert_eq(Multiplayer._turn_facts().get("characters_in_play", 0), 1,
			"A cena tem um personagem")
	assert_false(Multiplayer.run_phase_effects(), "Nada a fazer na contagem")
	assert_eq(_pile_size("discard"), before, "O deck não foi tocado")


func test_the_countdown_counts_the_opponent_characters():
	await _start_match({CHAR: 60})
	assert_true(_play_from_hand(_hand_cards()[0]), "P1 colocou um personagem")
	Multiplayer.swap_solo_seat()
	await yield_for(0.3)
	# Now the character of P1 is a mirror on this side of the table.
	assert_eq(Multiplayer._turn_facts().get("opponent_characters", 0), 1,
			"O espelho conta como personagem do oponente")
	var before := _pile_size("discard")
	_open_phase(0)
	assert_true(Multiplayer.run_phase_effects(), "A contagem rodou")
	# 1 by "tomba 1" plus 1 for the character the opponent controls.
	assert_eq(_pile_size("discard") - before, 2, "A contagem deu 2 recursos")


# --- Fase de Compra ------------------------------------------------------

func test_the_first_turn_of_the_match_does_not_draw():
	await _start_match({CHAR: 60})
	var hand := _hand_cards().size()
	var deck := _pile_size("deck")
	_open_phase(1, 1)
	assert_true(Multiplayer.is_first_turn_of_match(),
			"O passo 1 ainda é o primeiro turno")
	assert_false(Multiplayer.run_phase_effects(), "A compra está dispensada")
	assert_eq(_hand_cards().size(), hand, "A mão não cresceu")
	assert_eq(_pile_size("deck"), deck, "O deck não foi tocado")


func test_a_player_without_a_character_draws_one():
	await _start_match({CHAR: 60})
	var hand := _hand_cards().size()
	var deck := _pile_size("deck")
	_open_phase(1)
	assert_true(Multiplayer.run_phase_effects(), "A compra rodou")
	assert_eq(_hand_cards().size() - hand, 1, "Sem personagem se compra 1")
	assert_eq(deck - _pile_size("deck"), 1, "Uma carta saiu do deck")


func test_a_player_with_a_character_draws_two():
	await _start_match({CHAR: 60})
	assert_true(_play_from_hand(_hand_cards()[0]), "O personagem entrou em cena")
	var hand := _hand_cards().size()
	var deck := _pile_size("deck")
	_open_phase(1)
	assert_true(Multiplayer.run_phase_effects(), "A compra rodou")
	assert_eq(_hand_cards().size() - hand, 2, "Com personagem se compra 2")
	assert_eq(deck - _pile_size("deck"), 2, "Duas cartas saíram do deck")


# --- Fase de Ajuste ------------------------------------------------------

func test_the_adjustment_unloads_the_excess_energy():
	await _start_match({CHEAP_CHAR: 30, SUP: 30})
	var host = _hand_cards()[0]
	assert_true(_play_from_hand(host), "O personagem entrou em cena")
	assert_true(_attach_to(host), "O primeiro anexo entrou")
	assert_true(_attach_to(host), "O segundo anexo entrou")
	assert_eq(host._live_attachments().size(), 2, "Dois anexos sobre a energia 1")
	var before := _pile_size("discard")
	_open_phase(3)
	assert_true(Multiplayer.run_phase_effects(), "O ajuste descarregou")
	# The card template only clears the host link when the move finishes.
	await yield_for(0.6)
	assert_eq(host._live_attachments().size(), 1,
			"O excesso voltou para os recursos")
	assert_eq(_pile_size("discard") - before, 1,
			"A carta excedente está em Recursos")


func test_the_adjustment_leaves_a_legal_stack_alone():
	await _start_match({CHEAP_CHAR: 30, SUP: 30})
	var host = _hand_cards()[0]
	assert_true(_play_from_hand(host), "O personagem entrou em cena")
	assert_true(_attach_to(host), "Um anexo igual à energia entrou")
	assert_eq(host._live_attachments().size(), 1, "A pilha está legal")
	var before := _pile_size("discard")
	_open_phase(3)
	assert_false(Multiplayer.run_phase_effects(), "Nada a descarregar")
	assert_eq(host._live_attachments().size(), 1, "O anexo ficou")
	assert_eq(_pile_size("discard"), before, "Nada foi descartado")


func _attach_to(host) -> bool:
	var attach = _hand_cards()[0]
	var result: Dictionary = board.apply_intent(
			{"op": "anexar", "card": attach, "host": host})
	return bool(result.get("ok", false))
