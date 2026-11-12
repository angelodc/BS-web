extends "res://tests/UTcommon.gd"

# Pure tests for TurnRules. These never build a board: the whole point of the
# class is that the rule can be checked with plain dictionaries.

const Rules = preload("res://src/custom/TurnRules.gd")


func _character(name := "Char") -> Dictionary:
	return {"Name": name, "_tipo": "Personagem"}


func _support(name := "Sup") -> Dictionary:
	return {"Name": name, "_tipo": "Suporte"}


func _hand(characters: int, supports: int) -> Array:
	var cards := []
	for index in characters:
		cards.append(_character("C%d" % index))
	for index in supports:
		cards.append(_support("S%d" % index))
	return cards


# --- Cards -------------------------------------------------------------

func test_card_type_reads_the_tipo_field():
	assert_eq(Rules.card_type(_character()), "Personagem")
	assert_eq(Rules.card_type({"Name": "x", "_tipo": "  Personagem  "}),
			"Personagem")
	assert_eq(Rules.card_type(_support()), "Suporte")


func test_card_type_tolerates_missing_data():
	assert_eq(Rules.card_type({}), "")
	assert_eq(Rules.card_type(null), "")


func test_character_count_only_counts_characters():
	assert_eq(Rules.character_count(_hand(2, 3)), 2)
	assert_eq(Rules.character_count([]), 0)


# --- Mulligan ----------------------------------------------------------

func test_auto_mulligan_triggers_with_one_or_zero_characters():
	assert_true(Rules.needs_auto_mulligan(_hand(0, 10)))
	assert_true(Rules.needs_auto_mulligan(_hand(1, 9)))
	assert_false(Rules.needs_auto_mulligan(_hand(2, 8)))


func test_auto_mulligan_guard_stops_the_loop():
	assert_false(Rules.auto_mulligan_limit_reached(49))
	assert_true(Rules.auto_mulligan_limit_reached(50))
	assert_true(Rules.auto_mulligan_limit_reached(51))


func test_manual_mulligan_table_matches_the_plan():
	# AUTOTURNO.md §3.2: hand 10 -> 8 -> 6 -> 4 -> 2 -> 0, resources +2 each time.
	var steps := Rules.manual_mulligan_sequence()
	assert_eq(steps.size(), 5)

	var expected_hands := [10, 8, 6, 4, 2]
	var expected_draws := [8, 6, 4, 2, 0]
	var resources := 0
	for index in steps.size():
		var step: Dictionary = steps[index]
		assert_eq(step["hand_before"], expected_hands[index])
		assert_eq(step["to_resources"], 2)
		assert_eq(step["draw"], expected_draws[index])
		assert_eq(step["hand_after"], expected_draws[index])
		resources += int(step["to_resources"])

	assert_eq(resources, 10, "every card ends up split between hand and resources")


func test_manual_mulligan_keeps_the_total_at_ten():
	var resources := 0
	for step in Rules.manual_mulligan_sequence():
		resources += int(step["to_resources"])
		assert_eq(int(step["hand_before"]),
				int(step["hand_after"]) + int(step["to_resources"]))
		assert_eq(int(step["hand_after"]) + resources, Rules.HAND_SIZE,
				"hand plus resources is always the initial ten cards")


func test_manual_mulligan_requires_a_hand():
	assert_true(Rules.can_manual_mulligan(2))
	assert_false(Rules.can_manual_mulligan(0))
	assert_eq(Rules.manual_mulligan_cost(0), 0)
	assert_eq(Rules.manual_mulligan_draw(0), 0)


func test_manual_mulligan_with_an_odd_hand():
	# A hand of 1 should never happen, but the rule must not go negative.
	assert_eq(Rules.manual_mulligan_cost(1), 1)
	assert_eq(Rules.manual_mulligan_draw(1), 0)


# --- Contagem Regressiva -----------------------------------------------

func test_countdown_is_skipped_with_characters_in_play():
	var state := {
		"characters_in_play": 1,
		"opponent_characters": 4,
		"opponent_prizes": 6,
	}
	assert_eq(Rules.countdown_to_resources(state), 0)


func test_countdown_sends_one_card_with_an_empty_field():
	var state := {
		"characters_in_play": 0,
		"opponent_characters": 0,
		"opponent_prizes": 0,
	}
	assert_eq(Rules.countdown_to_resources(state), 1)


func test_countdown_adds_opponent_characters_and_prizes():
	var state := {
		"characters_in_play": 0,
		"opponent_characters": 3,
		"opponent_prizes": 2,
	}
	# one base card + three characters + two prize cards
	assert_eq(Rules.countdown_to_resources(state), 6)


func test_countdown_ignores_negative_input():
	var state := {
		"characters_in_play": 0,
		"opponent_characters": -2,
		"opponent_prizes": -1,
	}
	assert_eq(Rules.countdown_to_resources(state), 1)


# --- Fase de Compra ----------------------------------------------------

func test_first_turn_draws_nothing():
	assert_eq(Rules.draw_count({"is_first_turn": true, "characters_in_play": 0}), 0)
	assert_eq(Rules.draw_count({"is_first_turn": true, "characters_in_play": 3}), 0)


func test_draw_without_characters_is_one():
	var state := {"is_first_turn": false, "characters_in_play": 0}
	assert_eq(Rules.draw_count(state), 1)


func test_draw_with_characters_is_two():
	var state := {"is_first_turn": false, "characters_in_play": 2}
	assert_eq(Rules.draw_count(state), 2)


func test_draw_defaults_to_the_character_rule():
	assert_eq(Rules.draw_count({}), 1)


# --- Fase de Ajuste ----------------------------------------------------

func test_excess_attachments():
	assert_eq(Rules.excess_attachments(5, 3), 2)
	assert_eq(Rules.excess_attachments(3, 3), 0)
	assert_eq(Rules.excess_attachments(1, 4), 0)


func test_adjustment_operations_only_lists_the_excess():
	var operations := Rules.adjustment_operations([
		{"name": "A", "attached": 5, "energy": 3},
		{"name": "B", "attached": 2, "energy": 2},
		{"name": "C", "attached": 0, "energy": 0},
	])
	assert_eq(operations.size(), 1)
	assert_eq(operations[0]["op"], "unload")
	assert_eq(operations[0]["target"], "A")
	assert_eq(operations[0]["count"], 2)


# --- Deck --------------------------------------------------------------

func test_deck_can_supply():
	assert_true(Rules.deck_can_supply(5, 5))
	assert_false(Rules.deck_can_supply(4, 5))
	assert_true(Rules.deck_empty_loses())


# --- Phase entry point -------------------------------------------------

func test_reg_operations():
	var state := {"characters_in_play": 0, "opponent_characters": 2,
			"opponent_prizes": 0}
	var operations := Rules.operations_for_phase(Rules.PHASE_REG, state)
	assert_eq(operations.size(), 1)
	assert_eq(operations[0]["op"], "top_to_resources")
	assert_eq(operations[0]["count"], 3)

	assert_eq(Rules.operations_for_phase(Rules.PHASE_REG,
			{"characters_in_play": 2}).size(), 0)


func test_draw_operations():
	var operations := Rules.operations_for_phase(Rules.PHASE_DRAW,
			{"is_first_turn": false, "characters_in_play": 1})
	assert_eq(operations.size(), 1)
	assert_eq(operations[0]["op"], "draw")
	assert_eq(operations[0]["count"], 2)

	assert_eq(Rules.operations_for_phase(Rules.PHASE_DRAW,
			{"is_first_turn": true}).size(), 0)


func test_adj_operations_are_manual():
	# The adjustment no longer pays itself: the phase only opens the gate, so it
	# has no automatic operation even with excess energy.
	var operations := Rules.operations_for_phase(Rules.PHASE_ADJ, {
		"characters": [{"name": "A", "attached": 4, "energy": 1}],
	})
	assert_eq(operations.size(), 0)


func test_unknown_phase_has_no_operations():
	assert_eq(Rules.operations_for_phase("PREP", {}).size(), 0)
	assert_eq(Rules.operations_for_phase("ATK", {}).size(), 0)
