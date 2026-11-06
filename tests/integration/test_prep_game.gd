extends "res://tests/UTcommon.gd"

const Snapshot = preload("res://src/core/table/TableSnapshot.gd")

# The preparation window (AUTOTURNO.md §3.3, decisão 8a) stands between the
# mulligan and the first turn: each seat throws away as many hand cards as it
# wants and only clicks Pronto when it is done. The turn opens once the two
# answers are in, so the tests read the table the way a player at it would.

const CHAR := "Char Preparacao"


func before_all():
	cfc.game_settings.fancy_movement = false


func after_all():
	cfc.game_settings.fancy_movement = true


func after_each():
	Multiplayer.leave_session()
	cfc.card_definitions.erase(CHAR)


func _definition() -> Dictionary:
	var definition: Dictionary = \
			cfc.card_definitions["Test Card 1"].duplicate(true)
	definition["Name"] = CHAR
	definition["_tipo"] = "Personagem"
	definition["ENERGIA"] = "3"
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
	cfc.card_definitions[CHAR] = _definition()


# --- Table helpers -----------------------------------------------------

func _pile_size(nmap_key: String) -> int:
	var pile = cfc.NMAP.get(nmap_key, null)
	return pile.get_all_cards().size() if pile else 0


func _hand_cards() -> Array:
	var hand = cfc.NMAP.get("hand", null)
	return hand.get_all_cards() if hand else []


# The drag of a hand card onto the Resources band, which is the only move the
# preparation window is about.
func _discard_from_hand(index: int) -> bool:
	var cards := _hand_cards()
	if index >= cards.size():
		return false
	var result: Dictionary = board.apply_intent({
		"op": "descartar",
		"card": Snapshot.id_of(cards[index]),
	})
	return bool(result.get("ok", false))


# --- The match start -----------------------------------------------------

# Walks the mulligan gate and stops on the threshold of the preparation window,
# with the seat that has not answered yet on the table.
func _open_prep_window(entries: Dictionary) -> void:
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
	# In the hotseat the table passes to the seat that still owes an answer, so
	# each call lands on the seat that has to decide.
	assert_true(Multiplayer.accept_local_hand(), "O primeiro assento guarda a mão")
	await yield_for(0.3)
	assert_true(Multiplayer.accept_local_hand(), "O outro assento guarda a mão")
	await yield_for(0.1)
	assert_false(Multiplayer.is_mulligan_open(), "O mulligan fechou")


func _close_prep_window() -> void:
	assert_true(Multiplayer.ready_local_prep_game(), "O assento visível termina")
	await yield_for(0.3)
	assert_true(Multiplayer.ready_local_prep_game(), "O outro assento termina")
	await yield_for(0.1)
	assert_false(Multiplayer.is_prep_game_open(), "As duas respostas fecharam a janela")


# --- The window ----------------------------------------------------------

func test_the_window_opens_when_the_mulligan_closes():
	await _open_prep_window({CHAR: 60})
	assert_true(Multiplayer.is_prep_game_open(), "A preparação abre em seguida")


func test_the_window_holds_the_first_turn():
	await _open_prep_window({CHAR: 60})
	assert_false(Multiplayer.advance_phase(), "Nenhuma fase corre na preparação")
	assert_false(Multiplayer.run_phase_effects(), "O passo fica devendo")
	assert_false(Multiplayer.has_pending_phase_effect(), "Nada está pago")


func test_the_seat_throws_away_as_many_cards_as_it_wants():
	await _open_prep_window({CHAR: 60})
	assert_eq(_hand_cards().size(), TurnRules.HAND_SIZE, "A mão saiu do mulligan")
	for step in range(3):
		assert_true(_discard_from_hand(0), "O descarte " + str(step) + " passou")
	await yield_for(0.2)
	assert_eq(_hand_cards().size(), TurnRules.HAND_SIZE - 3, "A mão emagreceu")
	assert_eq(_pile_size("discard"), 3, "As três cartas viraram Recursos")


# O portão é da sessão, mas mora na regra: jogar antes da Contagem Regressiva
# mudaria a conta dela, então a janela só libera o descarte.
func test_the_window_only_opens_the_discard():
	await _open_prep_window({CHAR: 60})
	var played: Dictionary = board.apply_intent({
		"op": "jogar", "card": Snapshot.id_of(_hand_cards()[0])})
	assert_false(bool(played.get("ok", false)), "Nada entra em cena na preparação")
	assert_eq(str(played.get("error", "")), "fora_da_preparacao",
			"O motivo é a janela de preparação")
	assert_true(_discard_from_hand(0), "Descartar é o que a janela permite")


func test_the_window_does_not_buy_the_discard_back():
	await _open_prep_window({CHAR: 60})
	assert_true(_discard_from_hand(0), "Uma carta foi descartada")
	await yield_for(0.2)
	var hand_size := _hand_cards().size()
	assert_true(Multiplayer.ready_local_prep_game(), "O assento terminou")
	# The table passed to the other seat; coming back shows the seat that already
	# answered with the hand it left behind.
	Multiplayer.swap_solo_seat()
	await yield_for(0.3)
	assert_eq(_hand_cards().size(), hand_size, "A resposta não recompra a mão")
	assert_eq(_pile_size("discard"), 1, "A carta continua nos Recursos")


func test_the_table_moves_to_the_seat_that_owes_an_answer():
	await _open_prep_window({CHAR: 60})
	var first := Multiplayer.my_slot
	assert_true(Multiplayer.ready_local_prep_game(), "O assento visível terminou")
	assert_eq(Multiplayer.my_slot, 3 - first, "A mesa passou para o outro assento")
	var info := Multiplayer.get_prep_game_info()
	assert_false(bool(info["answered"]), "O outro assento ainda não respondeu")
	assert_false(bool(info["waiting_for_opponent"]), "Ele tem o próprio botão")


func test_the_answer_stays_with_the_seat():
	await _open_prep_window({CHAR: 60})
	assert_true(Multiplayer.ready_local_prep_game(), "O assento visível terminou")
	# The swap back is manual here: the table normally stays with the seat that
	# still owes an answer, but the answer already given belongs to its seat.
	Multiplayer.swap_solo_seat()
	await yield_for(0.3)
	assert_true(bool(Multiplayer.get_prep_game_info()["answered"]),
			"A resposta continua com o assento que a deu")
	assert_false(Multiplayer.ready_local_prep_game(), "Ele não responde duas vezes")
	assert_true(Multiplayer.is_prep_game_open(), "Falta o outro assento")


func test_the_info_panel_describes_the_window():
	await _open_prep_window({CHAR: 60})
	var info := Multiplayer.get_prep_game_info()
	assert_eq(int(info["hand_size"]), TurnRules.HAND_SIZE, "A mão do assento")
	assert_eq(int(info["resources"]), 0, "Nada foi descartado ainda")
	assert_false(bool(info["answered"]), "Ele ainda não respondeu")
	assert_false(bool(info["waiting_for_opponent"]), "A janela ainda é dele")


func test_the_public_state_carries_the_window():
	await _open_prep_window({CHAR: 60})
	var state: Dictionary = Multiplayer._build_public_state(Multiplayer.sequence)
	assert_true(bool(state.get("prep_game_open", false)),
			"Quem reconecta herda a janela aberta")


func test_the_first_turn_opens_when_both_have_answered():
	await _open_prep_window({CHAR: 60})
	await _close_prep_window()
	assert_true(Multiplayer.advance_phase(), "A primeira fase está liberada")


# Decisão 11a: the step the match opens on was owed to this window, not to the
# mulligan, so the Contagem Regressiva is paid when the last seat answers.
func test_the_countdown_is_paid_when_the_window_closes():
	await _open_prep_window({CHAR: 60})
	await _close_prep_window()
	if Multiplayer.get_turn_owner_slot() != Multiplayer.my_slot:
		Multiplayer.swap_solo_seat()
		await yield_for(0.3)
	assert_eq(_pile_size("discard"), 1, "A Contagem Regressiva deu 1 recurso")
	assert_eq(_pile_size("deck"), 49, "O topo do deck saiu")


# Item 5 do §9: quem reconecta recebe o estado público e não pode refazer o passo
# que a mesa já pagou. A marca viaja junto com o resto do turno.
func test_a_resumed_seat_does_not_replay_a_paid_step():
	await _open_prep_window({CHAR: 60})
	await _close_prep_window()
	if Multiplayer.get_turn_owner_slot() != Multiplayer.my_slot:
		Multiplayer.swap_solo_seat()
		await yield_for(0.3)
	assert_eq(_pile_size("discard"), 1, "O passo já foi pago")
	var paid := Multiplayer._build_public_state(Multiplayer.sequence)
	Multiplayer._effects_applied = {}
	assert_true(Multiplayer.has_pending_phase_effect(),
			"Sem a marca, o passo parece estar devendo")
	Multiplayer._absorb_turn_state(paid)
	assert_false(Multiplayer.run_phase_effects(), "A marca recebida segura o passo")
	assert_eq(_pile_size("discard"), 1, "Nenhum recurso apareceu duas vezes")


func test_the_windows_travel_in_the_public_state():
	await _open_prep_window({CHAR: 60})
	var state := Multiplayer._build_public_state(Multiplayer.sequence)
	assert_false(bool(state.get("mulligan_open", true)), "O mulligan fechou")
	assert_true(bool(state.get("prep_game_open", false)), "A preparação está aberta")
	Multiplayer._mulligan_open = true
	Multiplayer._prep_game_open = false
	Multiplayer._absorb_turn_state(state)
	assert_false(Multiplayer.is_mulligan_open(), "Quem absorve cai no mulligan fechado")
	assert_true(Multiplayer.is_prep_game_open(), "E cai na janela de preparação")
