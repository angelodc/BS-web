extends "res://tests/UTcommon.gd"

# An empty deck is not a blocked action: the seat that owed the cards loses the
# match on the spot and the opponent is credited with the victory
# (AUTOTURNO.md §3.5, decisão 10c). The tests drain the deck on the table and
# then ask for cards the way a phase, a click or an effect would.

const CHAR := "Char Deck Vazio"
const SUP := "Suporte Deck Vazio"


func before_all():
	cfc.game_settings.fancy_movement = false


func after_all():
	cfc.game_settings.fancy_movement = true


func after_each():
	Multiplayer.leave_session()
	cfc.card_definitions.erase(CHAR)
	cfc.card_definitions.erase(SUP)


func _definition(tipo: String, energy: int) -> Dictionary:
	var definition: Dictionary = \
			cfc.card_definitions["Test Card 1"].duplicate(true)
	definition["Name"] = CHAR if tipo == "Personagem" else SUP
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
	cfc.card_definitions[CHAR] = _definition("Personagem", 3)
	cfc.card_definitions[SUP] = _definition("Suporte", 1)


# --- Table helpers -----------------------------------------------------

func _pile_size(nmap_key: String) -> int:
	var pile = cfc.NMAP.get(nmap_key, null)
	return pile.get_all_cards().size() if pile else 0


# Empties the deck of the seat on the table, card by card, into the pool.
func _drain_deck(keep := 0) -> void:
	var deck = cfc.NMAP.get("deck", null)
	if not deck:
		return
	var cards: Array = deck.get_all_cards()
	for index in range(keep, cards.size()):
		if is_instance_valid(cards[index]):
			cards[index].move_to(cfc.NMAP.discard)


# Reaches a step of the turn of the seat that is on the table.
func _open_phase(step: int, match_round := 2) -> void:
	Multiplayer.starting_slot = Multiplayer.my_slot
	Multiplayer.round_number = match_round
	Multiplayer.step_index = step
	Multiplayer.phase = Multiplayer.phase_for_step(step)
	Multiplayer._effects_applied = {}


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
	# Each seat also closes the preparation window that follows the mulligan
	# (AUTOTURNO.md §3.3); only then does the first turn start owing its step.
	Multiplayer.ready_local_prep_game()
	await yield_for(0.3)
	Multiplayer.ready_local_prep_game()
	await yield_for(0.1)
	assert_false(Multiplayer.is_prep_game_open(), "A preparação fechou")


# --- The automatic steps -------------------------------------------------

func test_the_countdown_of_an_empty_deck_ends_the_match():
	await _start_match({CHAR: 60})
	_open_phase(0)
	_drain_deck()
	await yield_for(0.3)
	assert_eq(_pile_size("deck"), 0, "O deck foi esvaziado")
	Multiplayer.run_phase_effects()
	assert_true(Multiplayer.is_ended(), "A Contagem Regressiva cobrou um deck vazio")


func test_the_draw_of_an_empty_deck_ends_the_match():
	await _start_match({CHAR: 60})
	_open_phase(1)
	_drain_deck()
	await yield_for(0.3)
	Multiplayer.run_phase_effects()
	assert_true(Multiplayer.is_ended(), "A Compra cobrou um deck vazio")


func test_a_deck_that_cannot_pay_the_whole_draw_ends_the_match():
	await _start_match({CHAR: 60})
	_open_phase(1)
	# With a character in play the phase owes two cards, and one is not enough.
	var hand: Array = _hand_cards()
	assert_true(bool(board.apply_intent(
			{"op": "jogar", "card": hand[0]}).get("ok", false)),
			"Um personagem foi para a cena")
	_drain_deck(1)
	await yield_for(0.3)
	assert_eq(_pile_size("deck"), 1, "O deck ficou com uma carta")
	Multiplayer.run_phase_effects()
	assert_true(Multiplayer.is_ended(), "Faltar uma carta já é deck vazio")
	assert_eq(_pile_size("deck"), 1, "Nada foi comprado de um deck insuficiente")


func test_the_match_is_not_ended_while_the_deck_can_pay():
	await _start_match({CHAR: 60})
	_open_phase(1)
	_drain_deck(1)
	await yield_for(0.3)
	Multiplayer.run_phase_effects()
	assert_false(Multiplayer.is_ended(), "Uma carta no deck paga a Compra")
	assert_eq(_pile_size("deck"), 0, "A Compra saiu do deck")


# --- Any other moment ----------------------------------------------------

func test_a_hand_draw_of_an_empty_deck_ends_the_match():
	await _start_match({CHAR: 60})
	_drain_deck()
	await yield_for(0.3)
	var seat := Multiplayer.my_slot
	var result: Dictionary = board.apply_intent({"op": "comprar"})
	assert_false(bool(result.get("ok", false)), "A compra foi recusada pela mesa")
	assert_true(Multiplayer.is_ended(), "O clique num deck vazio também encerra")
	assert_true(Multiplayer.ended_message.find(
			Multiplayer.get_slot_username(3 - seat)) != -1,
			"A vitória ficou com o outro assento")


func test_the_opponent_is_credited_with_the_victory():
	await _start_match({CHAR: 60})
	var loser := Multiplayer.my_slot
	var winner := 3 - loser
	_drain_deck()
	await yield_for(0.3)
	board.apply_intent({"op": "mandar_topo_para_recursos"})
	assert_true(Multiplayer.is_ended(), "O topo do deck cobrado não existia")
	var message := Multiplayer.ended_message
	assert_true(message.find(Multiplayer.get_slot_username(winner)) != -1,
			"A vitória é do adversário: " + message)
	assert_true(message.find(Multiplayer.get_slot_username(loser)) != -1,
			"O motivo cita quem ficou sem deck: " + message)


func test_the_result_is_declared_only_once():
	await _start_match({CHAR: 60})
	_drain_deck()
	await yield_for(0.3)
	board.apply_intent({"op": "comprar"})
	assert_true(Multiplayer.is_ended(), "A primeira cobrança encerrou a partida")
	var message := Multiplayer.ended_message
	Multiplayer.declare_empty_deck_loss(Multiplayer.my_slot, 1)
	assert_eq(Multiplayer.ended_message, message, "A segunda cobrança é ouvida")


func _hand_cards() -> Array:
	var hand = cfc.NMAP.get("hand", null)
	return hand.get_all_cards() if hand else []
