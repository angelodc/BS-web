extends "res://tests/UTcommon.gd"

# F2a of "ações sem mouse": one validated intent per action.
#
# These tests drive the table only through `TableActions.apply()`, which is the
# same path the buttons, the deck, the HUD and keyboard shortcuts will use in
# F2b/F6. Every assertion reads the result back from the scene (through a new
# snapshot), not from the action's own bookkeeping, so a scene/state mismatch
# fails the test.

const Table = preload("res://src/core/table/TableState.gd")
const Snapshot = preload("res://src/core/table/TableSnapshot.gd")
const Rules = preload("res://src/core/table/TableRules.gd")
const Actions = preload("res://src/core/table/TableActions.gd")
const PILE_SCENE = preload("res://src/core/Pile.tscn")
const SCENARIO_GRID_SCENE = preload("res://src/custom/CGFModifiedLabelGrid.tscn")

var actions
var grid: BoardPlacementGrid
var scenario_grid: BoardPlacementGrid


func before_each():
	await setup_board()
	grid = Snapshot.field_grid(board)
	# The test board has no scenario slot, so one is added here the same way the
	# production scene offers it.
	scenario_grid = SCENARIO_GRID_SCENE.instantiate()
	scenario_grid.name = "ModifiedLabelGrid"
	board.add_child(scenario_grid)
	scenario_grid.add_slot()
	actions = Actions.new(board, 1)


func _id(card) -> String:
	return Snapshot.id_of(card)


func _ok(result : Dictionary) -> bool:
	return bool(result.get("ok", false))


func _error(result : Dictionary) -> String:
	return str(result.get("error", ""))


func _scenario_card():
	var card = cfc.instance_card("Demo Scenario")
	hand.add_child(card)
	return card


# -----------------------------------------------------------------------------
# Deck and hand
# -----------------------------------------------------------------------------

func test_draw_takes_the_top_card_to_the_front_of_the_hand():
	var top = actions.state.top_of_deck(1)
	var deck_before := int(actions.state.zone_counts(1)["deck"])

	var result = actions.apply({"op": "comprar"})

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(top), "p1:mão:1")
	assert_eq(int(actions.state.zone_counts(1)["deck"]), deck_before - 1)
	assert_eq(actions.history.size(), 1)
	assert_true(str(actions.history[0]["text"]).begins_with("P1 comprou 1 carta"))


func test_each_new_draw_becomes_the_first_hand_slot():
	var first = actions.state.top_of_deck(1)
	assert_true(_ok(actions.apply({"op": "comprar"})))
	var second = actions.state.top_of_deck(1)
	assert_true(_ok(actions.apply({"op": "comprar"})))

	assert_eq(actions.state.address_of(second), "p1:mão:1")
	assert_eq(actions.state.address_of(first), "p1:mão:2")


func test_draw_refuses_more_cards_than_the_deck():
	var deck_count := int(actions.state.zone_counts(1)["deck"])

	var result = actions.apply({
		"op": "comprar",
		"quantity": deck_count + 1,
	})

	assert_false(_ok(result))
	assert_eq(_error(result), "deck_insuficiente")
	assert_eq(actions.history.size(), 0)
	assert_eq(int(actions.state.zone_counts(1)["deck"]), deck_count)


func test_mill_sends_the_top_card_to_the_top_of_the_resources():
	var top = actions.state.top_of_deck(1)

	var result = actions.apply({"op": "mandar_topo_para_recursos"})

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(top), "p1:recursos:1")
	assert_ne(actions.state.top_of_deck(1), top)


# -----------------------------------------------------------------------------
# Playing cards
# -----------------------------------------------------------------------------

func test_play_fills_the_field_from_the_center_out():
	var cards = draw_test_cards(1)
	actions.sync(1)

	var result = actions.apply({"op": "jogar", "card": _id(cards[0])})

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(_id(cards[0])), "p1:campo:frente:2")
	assert_eq(cards[0].get_parent(), board)
	assert_eq(actions.history.size(), 1)


func test_play_uses_the_requested_field_slot():
	var cards = draw_test_cards(1)
	actions.sync(1)

	var result = actions.apply({
		"op": "jogar",
		"card": _id(cards[0]),
		"to": "p1:campo:trás:1",
	})

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(_id(cards[0])), "p1:campo:trás:1")


func test_play_refuses_an_occupied_slot():
	var cards = draw_test_cards(2)
	actions.sync(1)
	assert_true(_ok(actions.apply({
		"op": "jogar",
		"card": _id(cards[0]),
		"to": "p1:campo:trás:1",
	})))

	var second = actions.apply({
		"op": "jogar",
		"card": _id(cards[1]),
		"to": "p1:campo:trás:1",
	})

	assert_false(_ok(second))
	assert_eq(_error(second), "slot_ocupado")
	assert_eq(actions.state.address_of(_id(cards[1])), "p1:mão:1")
	assert_eq(actions.history.size(), 1)


func test_play_refuses_a_card_outside_the_hand():
	actions.sync(1)
	var top = actions.state.top_of_deck(1)

	var result = actions.apply({"op": "jogar", "card": top})

	assert_false(_ok(result))
	assert_eq(_error(result), "fora_da_mão")


func test_play_grows_the_field_when_both_rows_are_full():
	grid.configure_columns(2)
	var cards = draw_test_cards(5)
	actions.sync(1)
	for index in range(4):
		var result = actions.apply({"op": "jogar", "card": _id(cards[index])})
		assert_true(_ok(result), str(result))
	assert_eq(actions.state.columns, 2)

	var fifth = actions.apply({"op": "jogar", "card": _id(cards[4])})

	assert_true(_ok(fifth), str(fifth))
	assert_eq(actions.state.address_of(_id(cards[4])), "p1:campo:frente:3")
	assert_eq(actions.state.columns, 3)
	# The earlier cards keep their own addresses after the column is added.
	assert_eq(actions.state.address_of(_id(cards[0])), "p1:campo:frente:1")
	assert_eq(actions.state.address_of(_id(cards[1])), "p1:campo:frente:2")
	assert_eq(actions.state.address_of(_id(cards[2])), "p1:campo:trás:1")
	assert_eq(actions.state.address_of(_id(cards[3])), "p1:campo:trás:2")


func test_play_puts_a_scenario_in_the_shared_slot():
	var scenario = _scenario_card()
	actions.sync(1)

	var result = actions.apply({"op": "jogar", "card": _id(scenario)})

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(_id(scenario)), "mesa:cenário")


func test_play_replaces_the_active_scenario():
	var first = _scenario_card()
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(first)})))
	var second = _scenario_card()
	actions.sync(1)

	var result = actions.apply({"op": "jogar", "card": _id(second)})

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(_id(second)), "mesa:cenário")
	assert_eq(actions.state.address_of(_id(first)), "p1:recursos:1")
	# The replacement is not reversible, as the plan says.
	assert_false(bool(actions.history[actions.history.size() - 1]["undoable"]))


# -----------------------------------------------------------------------------
# Attachments
# -----------------------------------------------------------------------------

func test_attach_puts_a_card_under_its_host():
	var cards = draw_test_cards(2)
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))

	var result = actions.apply({
		"op": "anexar",
		"card": _id(cards[1]),
		"host": _id(cards[0]),
	})

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(_id(cards[0])), "p1:campo:frente:2")
	assert_eq(actions.state.address_of(_id(cards[1])),
			"anexo:p1:p1:campo:frente:2:1")
	assert_eq(actions.state.cards[_id(cards[1])]["host"], _id(cards[0]))
	assert_eq(actions.state.cards[_id(cards[0])]["attachments"],
			[_id(cards[1])])


func test_attach_refuses_a_character_already_on_the_field():
	var cards = draw_test_cards(2)
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[1])})))

	var result = actions.apply({
		"op": "anexar",
		"card": _id(cards[1]),
		"host": _id(cards[0]),
	})

	assert_false(_ok(result))
	assert_eq(_error(result), "carta_nao_anexavel")


# -----------------------------------------------------------------------------
# Moving and discarding
# -----------------------------------------------------------------------------

func test_move_sends_a_card_to_the_top_of_the_resources():
	var cards = draw_test_cards(1)
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))

	var result = actions.apply({
		"op": "mover",
		"card": _id(cards[0]),
		"to": "p1:recursos:1",
	})

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(_id(cards[0])), "p1:recursos:1")


func test_move_sends_a_card_to_the_top_of_the_prizes():
	var cards = draw_test_cards(1)
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))
	var prizes = PILE_SCENE.instantiate()
	prizes.name = "Prêmios"
	autoqfree(prizes)
	board.add_child(prizes)

	var result = actions.apply({
		"op": "mover",
		"card": _id(cards[0]),
		"to": "p1:prêmios:1",
	})

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(_id(cards[0])), "p1:prêmios:1")


func test_discard_always_sends_the_card_to_the_resources():
	var cards = draw_test_cards(1)
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))

	var result = actions.apply({"op": "descartar", "card": _id(cards[0])})

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(_id(cards[0])), "p1:recursos:1")


func test_move_refuses_a_card_still_in_the_deck():
	actions.sync(1)
	var top = actions.state.top_of_deck(1)

	var result = actions.apply({
		"op": "mover",
		"card": top,
		"to": "p1:recursos:1",
	})

	assert_false(_ok(result))
	assert_eq(_error(result), "carta_no_deck")


func test_move_refuses_a_field_row_that_does_not_exist():
	var cards = draw_test_cards(1)
	actions.sync(1)

	var result = actions.apply({
		"op": "mover",
		"card": _id(cards[0]),
		"to": "p1:campo:lado:1",
	})

	assert_false(_ok(result))
	assert_eq(_error(result), "fileira_invalida")


func test_move_refuses_a_hand_slot_beyond_the_last():
	var cards = draw_test_cards(1)
	actions.sync(1)

	var result = actions.apply({
		"op": "mover",
		"card": _id(cards[0]),
		"to": "p1:mão:5",
	})

	assert_false(_ok(result))
	assert_eq(_error(result), "slot_invalido")


# -----------------------------------------------------------------------------
# Materializar
# -----------------------------------------------------------------------------

func _materialize(card, life := 3) -> Dictionary:
	return actions.apply({"op": "materializar", "card": _id(card), "life": life})


func test_materialize_takes_the_hand_card_to_the_field_with_life():
	var cards = draw_test_cards(1)
	actions.sync(1)
	var card_id := _id(cards[0])
	var deck_before := int(actions.state.zone_counts(1)["deck"])
	var life := [
		actions.state.card_at("p1:deck:1"),
		actions.state.card_at("p1:deck:2"),
		actions.state.card_at("p1:deck:3"),
	]

	var result = _materialize(cards[0])

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(card_id), "p1:campo:frente:2")
	assert_eq(cards[0].get_parent(), board)
	assert_eq(int(actions.state.zone_counts(1)["deck"]), deck_before - 3)
	assert_eq(actions.state.cards[card_id]["attachments"], life)
	for index in range(life.size()):
		assert_eq(actions.state.address_of(life[index]),
				"anexo:p1:p1:campo:frente:2:" + str(index + 1))
	assert_eq(cards[0].attachments.size(), 3)
	for attachment in cards[0].attachments:
		assert_true(attachment.is_faceup, attachment.canonical_name)
	assert_eq(actions.history.size(), 1)
	assert_true(str(actions.history[0]["text"]).contains("materializou"))


func test_materialize_uses_the_card_energy_as_life():
	var cards = draw_test_cards(1)
	cards[0].properties["ENERGIA"] = "5"
	actions.sync(1)
	var deck_before := int(actions.state.zone_counts(1)["deck"])

	var result = actions.apply({"op": "materializar", "card": _id(cards[0])})

	assert_true(_ok(result), str(result))
	assert_eq(cards[0].attachments.size(), 5)
	assert_eq(int(actions.state.zone_counts(1)["deck"]), deck_before - 5)


func test_materialize_refuses_a_card_outside_the_hand():
	var cards = draw_test_cards(1)
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))

	var result = _materialize(cards[0])

	assert_false(_ok(result), str(result))
	assert_eq(_error(result), "fora_da_mão")
	assert_eq(cards[0].get_parent(), board)


func test_materialize_refuses_a_card_that_is_not_character_or_support():
	var token = cfc.instance_card("Spawn Card")
	hand.add_child(token)
	token.state = Card.CardState.IN_HAND
	actions.sync(1)

	var result = _materialize(token)

	assert_false(_ok(result), str(result))
	assert_eq(_error(result), "tipo_invalido")
	assert_eq(token.get_parent(), hand)


func test_materialize_refuses_a_deck_without_enough_life():
	var cards = draw_test_cards(1)
	actions.sync(1)
	# Leave a single card in the deck: less than the three life cards.
	for _index in range(int(actions.state.zone_counts(1)["deck"]) - 1):
		assert_true(_ok(actions.apply({"op": "comprar"})))

	var result = _materialize(cards[0])

	assert_false(_ok(result), str(result))
	assert_eq(_error(result), "deck_insuficiente")
	assert_eq(cards[0].get_parent(), hand)


func test_materialize_ignores_the_resource_pile():
	var cards = draw_test_cards(1)
	actions.sync(1)
	var rules = Rules.new()
	var base = {
		"active": false,
		"solo": false,
		"my_slot": 1,
		"my_phase": true,
		"undo_entry": {},
	}
	var enforced = base.duplicate(true)
	enforced["enforce_cost"] = true

	var allowed = rules.validate(actions.state, {
		"op": "materializar",
		"card": _id(cards[0]),
	}, enforced)

	assert_eq(actions.state.resource_count(1), 0)
	assert_true(_ok(allowed), str(allowed))


func test_undo_of_materialize_returns_the_card_and_the_life():
	var cards = draw_test_cards(1)
	actions.sync(1)
	var card_id := _id(cards[0])
	var top = actions.state.top_of_deck(1)
	var deck_before := int(actions.state.zone_counts(1)["deck"])
	assert_true(_ok(_materialize(cards[0])))

	var undone = actions.undo()

	assert_true(_ok(undone), str(undone))
	assert_eq(actions.state.address_of(card_id), "p1:mão:1")
	assert_eq(actions.state.top_of_deck(1), top)
	assert_eq(int(actions.state.zone_counts(1)["deck"]), deck_before)
	assert_eq(cards[0].attachments.size(), 0)
	assert_eq(actions.state.cards[card_id]["attachments"], [])


# -----------------------------------------------------------------------------
# Card state
# -----------------------------------------------------------------------------

func test_flip_turns_a_card_on_the_field():
	var cards = draw_test_cards(1)
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))
	assert_true(cards[0].is_faceup)

	var result = actions.apply({"op": "virar", "card": _id(cards[0])})

	assert_true(_ok(result), str(result))
	assert_false(cards[0].is_faceup)
	assert_eq(actions.state.cards[_id(cards[0])]["face"], "down")

	assert_true(_ok(actions.apply({"op": "virar", "card": _id(cards[0])})))
	assert_true(cards[0].is_faceup)


func test_shield_adjusts_the_token_and_refuses_going_negative():
	var cards = draw_test_cards(1)
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))

	assert_true(_ok(actions.apply({
		"op": "escudo",
		"card": _id(cards[0]),
		"amount": 2,
	})))
	assert_eq(int(actions.state.cards[_id(cards[0])]["shield"]), 2)

	var negative = actions.apply({
		"op": "escudo",
		"card": _id(cards[0]),
		"amount": -3,
	})

	assert_false(_ok(negative))
	assert_eq(_error(negative), "escudo_negativo")
	assert_eq(int(actions.state.cards[_id(cards[0])]["shield"]), 2)
	assert_eq(actions.history.size(), 2)


func test_capacitar_and_incapacitar_move_the_character_stage():
	var cards = draw_test_cards(1)
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})))

	assert_true(_ok(actions.apply({"op": "capacitar", "card": _id(cards[0])})))
	assert_eq(int(cards[0].card_rotation), 90)

	var again = actions.apply({"op": "capacitar", "card": _id(cards[0])})
	assert_false(_ok(again))
	assert_eq(_error(again), "estado_invalido")

	assert_true(_ok(actions.apply({"op": "incapacitar", "card": _id(cards[0])})))
	assert_eq(int(cards[0].card_rotation), 0)


func test_rotate_refuses_characters_and_turns_other_cards():
	var card = cfc.instance_card("Spawn Card")
	hand.add_child(card)
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(card)})))

	var result = actions.apply({
		"op": "girar",
		"card": _id(card),
		"degree": 90,
	})

	assert_true(_ok(result), str(result))
	assert_eq(int(card.card_rotation), 90)

	var characters = draw_test_cards(1)
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(characters[0])})))
	var refused = actions.apply({
		"op": "girar",
		"card": _id(characters[0]),
		"degree": 90,
	})
	assert_false(_ok(refused))
	assert_eq(_error(refused), "tipo_invalido")


func test_reorder_hand_renumbers_the_slots():
	var cards = draw_test_cards(3)
	actions.sync(1)

	var result = actions.apply({
		"op": "reordenar_mão",
		"from": 1,
		"to_slot": 3,
	})

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(_id(cards[1])), "p1:mão:1")
	assert_eq(actions.state.address_of(_id(cards[2])), "p1:mão:2")
	assert_eq(actions.state.address_of(_id(cards[0])), "p1:mão:3")


# -----------------------------------------------------------------------------
# Undo and log
# -----------------------------------------------------------------------------

func test_undo_returns_a_played_card_to_its_hand_slot():
	var cards = draw_test_cards(2)
	actions.sync(1)
	var played := _id(cards[0])
	assert_true(_ok(actions.apply({"op": "jogar", "card": played})))
	assert_eq(actions.state.address_of(played), "p1:campo:frente:2")
	assert_true(actions.can_undo())

	var undone = actions.undo()

	assert_true(_ok(undone), str(undone))
	assert_eq(actions.state.address_of(played), "p1:mão:1")
	assert_eq(actions.state.address_of(_id(cards[1])), "p1:mão:2")
	assert_true(bool(actions.history[0]["undone"]))
	assert_false(actions.can_undo())
	assert_true(actions.describe_log().begins_with("[desfeito] #1 "))


func test_undo_restores_a_flip_without_moving_the_card():
	var cards = draw_test_cards(1)
	actions.sync(1)
	var card := _id(cards[0])
	assert_true(_ok(actions.apply({"op": "jogar", "card": card})))
	assert_true(_ok(actions.apply({"op": "virar", "card": card})))
	assert_false(cards[0].is_faceup)

	var undone = actions.undo()

	assert_true(_ok(undone), str(undone))
	assert_true(cards[0].is_faceup)
	assert_eq(actions.state.address_of(card), "p1:campo:frente:2")


func test_undo_detaches_an_attached_card():
	var cards = draw_test_cards(2)
	actions.sync(1)
	var host := _id(cards[0])
	var attached := _id(cards[1])
	assert_true(_ok(actions.apply({"op": "jogar", "card": host})))
	assert_true(_ok(actions.apply({
		"op": "anexar",
		"card": attached,
		"host": host,
	})))
	assert_eq(actions.state.address_of(attached),
			"anexo:p1:p1:campo:frente:2:1")

	var undone = actions.undo()

	assert_true(_ok(undone), str(undone))
	assert_eq(actions.state.address_of(attached), "p1:mão:1")
	assert_eq(actions.state.cards[host]["attachments"], [])
	assert_eq(cards[1].current_host_card, null)


func test_undo_sends_a_milled_card_back_to_the_top_of_the_deck():
	var top = actions.state.top_of_deck(1)
	assert_true(_ok(actions.apply({"op": "mandar_topo_para_recursos"})))
	assert_eq(actions.state.address_of(top), "p1:recursos:1")

	var undone = actions.undo()

	assert_true(_ok(undone), str(undone))
	assert_eq(actions.state.top_of_deck(1), top)


func test_log_records_sequence_and_addresses():
	var cards = draw_test_cards(1)
	actions.sync(1)
	var card := _id(cards[0])
	assert_true(_ok(actions.apply({"op": "jogar", "card": card})))

	var entry: Dictionary = actions.history[0]

	assert_eq(int(entry["seq"]), 1)
	assert_eq(str(entry["op"]), "jogar")
	assert_eq(int(entry["seat"]), 1)
	assert_eq(str(entry["from"]), "p1:mão:1")
	assert_eq(str(entry["to"]), "p1:campo:frente:2")
	assert_eq(str(entry["name"]), str(cards[0].canonical_name))
	assert_true(str(entry["text"]).begins_with("P1 jogou "))
	assert_true(str(entry["text"]).ends_with(
			"(p1:mão:1 → p1:campo:frente:2)"))


func test_a_refused_action_changes_nothing():
	var cards = draw_test_cards(1)
	actions.sync(1)

	var result = actions.apply({
		"op": "mover",
		"card": _id(cards[0]),
		"to": "p1:campo:lado:1",
	})

	assert_false(_ok(result))
	assert_eq(actions.history.size(), 0)
	assert_eq(cards[0].get_parent(), hand)
	assert_eq(str(actions.last_error), str(result.get("message", "")))


func test_check_does_not_change_the_table():
	var cards = draw_test_cards(1)
	actions.sync(1)
	var card := _id(cards[0])

	var decision = actions.check({"op": "jogar", "card": card})

	assert_true(_ok(decision), str(decision))
	assert_eq(actions.state.address_of(card), "p1:mão:1")
	assert_eq(actions.history.size(), 0)
	assert_eq(cards[0].get_parent(), hand)


func test_undo_without_history_is_refused():
	var result = actions.apply({"op": "desfazer"})

	assert_false(_ok(result))
	assert_eq(_error(result), "nada_para_desfazer")


# -----------------------------------------------------------------------------
# Context rules
# -----------------------------------------------------------------------------

func test_actions_of_another_seat_are_refused():
	var result = actions.apply({"op": "comprar", "seat": 2})

	assert_false(_ok(result))
	assert_eq(_error(result), "fora_do_seu_assento")
	assert_eq(actions.history.size(), 0)


func test_passar_fase_requires_a_match():
	var result = actions.apply({"op": "passar_fase"})

	assert_false(_ok(result))
	assert_eq(_error(result), "sem_partida")


func test_trocar_assento_is_solo_only():
	var result = actions.apply({"op": "trocar_assento"})

	assert_false(_ok(result))
	assert_eq(_error(result), "apenas_hotseat")


func test_play_cost_is_checked_when_enforced():
	var cards = draw_test_cards(1)
	actions.sync(1)
	var rules = Rules.new()
	var context = {
		"active": false,
		"solo": false,
		"my_slot": 1,
		"my_phase": true,
		"enforce_cost": true,
		"undo_entry": {},
	}

	var decision = rules.validate(actions.state, {
		"op": "jogar",
		"card": _id(cards[0]),
	}, context)

	assert_false(_ok(decision))
	assert_eq(_error(decision), "recursos_insuficientes")
	# The same intent passes when the cost is not enforced (as in GUT).
	var free = rules.validate(actions.state, {
		"op": "jogar",
		"card": _id(cards[0]),
	}, {
		"active": false,
		"solo": false,
		"my_slot": 1,
		"my_phase": true,
		"enforce_cost": false,
		"undo_entry": {},
	})
	assert_true(_ok(free), str(free))
