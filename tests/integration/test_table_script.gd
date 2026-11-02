extends "res://tests/UTcommon.gd"

# F4 of "ações sem mouse": whole matches described as JSON.
#
# These tests run scripts through `TableScript.run()`, the same entry the F8
# console uses. A script step becomes a validated intent, so what is checked
# here is the path a button, a drop or a shortcut takes as well. Every
# expectation is read back from the table, including the visual order, and a
# failed step must leave the table untouched from that point on.

const Actions = preload("res://src/core/table/TableActions.gd")
const Runner = preload("res://src/core/table/TableScript.gd")
const Snapshot = preload("res://src/core/table/TableSnapshot.gd")
const SCENARIO_GRID_SCENE = preload("res://src/custom/CGFModifiedLabelGrid.tscn")

var actions


func before_each():
	var setup = setup_board()
	if setup is GDScriptFunctionState:
		await setup.completed
	# The test board has no scenario slot; adding it the same way the production
	# scene does keeps the zone counts equivalent.
	var scenario_grid = SCENARIO_GRID_SCENE.instantiate()
	scenario_grid.name = "ModifiedLabelGrid"
	board.add_child(scenario_grid)
	scenario_grid.add_slot()
	actions = Actions.new(board, 1)


func _card(name : String):
	var card = cfc.instance_card(name)
	hand.add_child(card)
	return card


func _ok(result : Dictionary) -> bool:
	return bool(result.get("ok", false))


# A row of the field as the player sees it, with the empty slots kept. The
# column count comes from the state, so the fixture grid size does not leak
# into the expectations.
func _field_row(column : int, card_name : String) -> Array:
	var row := []
	for _index in range(int(actions.state.columns)):
		row.append("")
	row[column] = card_name
	return row


# Puts the deck back in a known order. The deck is a stack, so the last child is
# the top card; the order given by the state starts at the top.
func _restore_deck(order : Array) -> void:
	var nodes := {}
	for child in deck.get_children():
		if child is Card:
			nodes[Snapshot.id_of(child)] = child
	var position := 0
	for index in range(order.size() - 1, -1, -1):
		var node = nodes.get(str(order[index]), null)
		if is_instance_valid(node):
			deck.move_child(node, position)
			position += 1
	actions.sync(1)


# -----------------------------------------------------------------------------
# Whole match
# -----------------------------------------------------------------------------

func test_a_script_plays_the_opening_of_a_match_and_checks_it():
	var script = {
		"seed": "f4-match",
		"seat": 1,
		"steps": [
			{"op": "comprar", "quantity": 2},
			{"expect": {"zones": {"hand": 2, "deck": 15}}},
			{"op": "jogar", "card": "Multiple Choices Test Card",
					"to": "p1:campo:frente:2"},
			{"op": "jogar", "card": "Test Card 3",
					"to": "p1:campo:trás:2"},
			{"expect": {"card": "Multiple Choices Test Card",
					"address": "p1:campo:frente:2"}},
			{"expect": {"card": "Test Card 3",
					"address": "p1:campo:trás:2"}},
			{"expect": {"zones": {"hand": 0, "field": 2, "deck": 15}}},
			{"expect": {"hand": []}},
			{"expect": {"field": {
				"frente": _field_row(1, "Multiple Choices Test Card"),
				"trás": _field_row(1, "Test Card 3"),
			}}},
			{"expect": {"log": "jogou Test Card 3"}},
			{"expect": {"log_count": 3}},
		],
	}

	var result := Runner.run(actions, script, 1)

	assert_true(_ok(result), str(result))
	assert_eq(int(result["failed"]), -1)
	assert_eq(int(result["steps"].size()), 11)
	# The last applied step is the second play, and it is what the HUD shows.
	assert_true(str(result["steps"][3]["text"]).find("jogou Test Card 3") >= 0,
			str(result["steps"][3]))
	assert_true(str(result["log"]).find("comprou 2 carta") >= 0, str(result["log"]))


func test_the_console_text_format_runs_as_typed():
	# The F8 console parses the line with JSON.parse and hands the result over;
	# this is that same text, so the documented format cannot drift silently.
	var text := "{\"seed\": \"f4-console\", \"steps\": [" \
			+ "{\"op\": \"comprar\"}," \
			+ "{\"expect\": {\"zones\": {\"hand\": 1}}}]}"
	var test_json_conv = JSON.new()
	test_json_conv.parse(text)
	var parsed := test_json_conv.get_data()

	assert_eq(parsed.error, OK, str(parsed.error_string))
	var result := Runner.run(actions, parsed.result, 1)
	assert_true(_ok(result), str(result))
	assert_eq(int(actions.state.hand_count(1)), 1)


# -----------------------------------------------------------------------------
# Card references
# -----------------------------------------------------------------------------

func test_duplicate_cards_get_stable_numbered_aliases():
	var first = _card("Test Card 2")
	var second = _card("Test Card 2")
	actions.sync(1)
	var first_id := Snapshot.id_of(first)
	var second_id := Snapshot.id_of(second)
	assert_eq(actions.state.address_of(first_id), "p1:mão:1")
	assert_eq(actions.state.address_of(second_id), "p1:mão:2")

	var script = {
		"steps": [
			{"op": "jogar", "card": "Test Card 2 2"},
			{"expect": {"card": "Test Card 2 2",
					"address": "p1:campo:frente:2"}},
			{"expect": {"card": "Test Card 2 1", "address": "p1:mão:1"}},
		],
	}

	var result := Runner.run(actions, script, 1)

	assert_true(_ok(result), str(result))
	# The alias picked the second copy, the one that was in mão:2, and the other
	# card slid into mão:1.
	assert_eq(actions.state.address_of(second_id), "p1:campo:frente:2")
	assert_eq(actions.state.address_of(first_id), "p1:mão:1")


func test_a_name_resolves_by_definition_when_it_is_unique():
	var card = cfc.instance_card("Multiple Choices Test Card")
	hand.add_child(card)
	actions.sync(1)

	var result := Runner.run(actions, {
		"steps": [{"op": "jogar", "card": "Multiple Choices Test Card"}],
	}, 1)

	assert_true(_ok(result), str(result))
	assert_eq(actions.state.address_of(Snapshot.id_of(card)),
			"p1:campo:frente:2")


# -----------------------------------------------------------------------------
# Failure stops the script
# -----------------------------------------------------------------------------

func test_a_failed_step_stops_the_script_and_keeps_what_came_before():
	var result := Runner.run(actions, {
		"steps": [
			{"op": "comprar"},
			{"op": "jogar", "card": "Carta Que Não Existe"},
		],
	}, 1)

	assert_false(_ok(result))
	assert_eq(str(result["error"]), "carta_desconhecida")
	assert_eq(int(result["failed"]), 1)
	assert_eq(actions.history.size(), 1)
	# The draw stays applied; the refused play changed nothing after it.
	assert_eq(int(actions.state.hand_count(1)), 1)


func test_a_failed_expectation_stops_the_script():
	var result := Runner.run(actions, {
		"steps": [
			{"op": "comprar"},
			{"expect": {"zones": {"field": 99}}},
			{"op": "comprar"},
		],
	}, 1)

	assert_false(_ok(result))
	assert_eq(str(result["error"]), "espera_falhou")
	assert_eq(int(result["failed"]), 1)
	assert_true(str(result["message"]).find("field") >= 0,
			str(result["message"]))
	# Only the first draw ran; the step after the expectation never applied.
	assert_eq(actions.history.size(), 1)


# -----------------------------------------------------------------------------
# Seed
# -----------------------------------------------------------------------------

func test_the_same_seed_replays_the_same_deck_order():
	actions.sync(1)
	var initial: Array = actions.state.deck[1].duplicate()
	var seeded := {"seed": "f4-seed", "steps": [{"op": "embaralhar"}]}

	var first := Runner.run(actions, seeded, 1)
	assert_true(_ok(first), str(first))
	var first_order: Array = actions.state.deck[1].duplicate()
	assert_ne(first_order, initial, "o embaralhamento mudou a ordem")

	_restore_deck(initial)
	assert_eq(actions.state.deck[1], initial, "a ordem inicial voltou")

	var second := Runner.run(actions, seeded, 1)
	assert_true(_ok(second), str(second))
	assert_eq(actions.state.deck[1], first_order, "mesma semente, mesma ordem")

	_restore_deck(initial)
	var other := Runner.run(actions, {
		"seed": "f4-outra", "steps": [{"op": "embaralhar"}],
	}, 1)
	assert_true(_ok(other), str(other))
	assert_ne(actions.state.deck[1], first_order, "outra semente, outra ordem")
