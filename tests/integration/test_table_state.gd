extends "res://tests/UTcommon.gd"

# F1 of "ações sem mouse": TableState is the data form of the table. These tests
# check that it can be built from the scene, describes the same addresses, knows
# the placement rules (hand order, field growth, six visible resources) and
# reports the places where state and scene disagree. Nothing here changes how the
# game behaves.

const Table = preload("res://src/core/table/TableState.gd")
const Snapshot = preload("res://src/core/table/TableSnapshot.gd")


func before_each():
	await setup_board()


func _new_state():
	return Table.new()


func _id(card) -> String:
	return Snapshot.id_of(card)


func test_state_matches_the_table_addresses():
	var cards := draw_test_cards(4)
	var grid: BoardPlacementGrid = board.get_node("BoardPlacementGrid")
	cards[0].move_to(board, -1, grid.get_slot(0))
	await yield_for(0.1)
	for _i in range(4):
		grid.add_slot()
	cards[1].move_to(board, -1, grid.get_slot(4))
	await yield_for(0.1)
	cards[2].attach_to_host(cards[0])
	await yield_for(0.2)
	await cards[3].move_to(discard)

	var state = _new_state()
	state.load_board(board, 1)

	assert_eq(state.columns, 4)
	assert_eq(state.address_of(_id(cards[0])), "p1:campo:frente:1")
	assert_eq(state.address_of(_id(cards[1])), "p1:campo:trás:1")
	assert_eq(state.address_of(_id(cards[2])),
			"anexo:p1:p1:campo:frente:1:1")
	assert_eq(state.address_of(_id(cards[3])), "p1:recursos:1")
	assert_eq(state.cards[_id(cards[2])]["host"],
			_id(cards[0]))
	assert_eq(state.cards[_id(cards[2])]["kind"], "resource")
	assert_eq(state.card_count(), deck.get_card_count() + 4)
	var issues = state.compare_with(Snapshot.capture(board, 1))
	assert_eq(issues, [], state.describe(1))


func test_state_detects_a_card_that_moved_after_the_capture():
	var cards := draw_test_cards(2)
	var state = _new_state()
	state.load_board(board, 1)
	await cards[0].move_to(discard)

	var issues = state.compare_with(Snapshot.capture(board, 1))

	var found := false
	for issue in issues:
		if str(issue.get("type", "")) == "endereco_divergente" \
				and str(issue.get("card", "")) == _id(cards[0]):
			found = true
	assert_true(found, state.describe(1))


func test_draw_enters_the_start_of_the_hand():
	var cards := draw_test_cards(2)
	var state = _new_state()
	state.load_board(board, 1)
	var top = state.top_of_deck(1)
	var second_top = str(state.deck[1][1])

	var drawn = state.draw_top(1)

	assert_eq(drawn, top)
	assert_eq(state.address_of(top), "p1:mão:1")
	assert_eq(state.address_of(_id(cards[0])), "p1:mão:2")
	assert_eq(state.address_of(_id(cards[1])), "p1:mão:3")
	assert_eq(state.top_of_deck(1), second_top)


func test_field_fills_from_the_center_out():
	var cards := draw_test_cards(5)
	var state = _new_state()
	state.load_board(board, 1)
	state.set_columns(4)

	var addresses := []
	for card in cards:
		var address = state.find_field_slot(1)
		assert_true(state.place(_id(card), address),
				"não colocou " + address)
		addresses.append(state.address_of(_id(card)))

	assert_eq(addresses[0], "p1:campo:frente:2")
	assert_eq(addresses[1], "p1:campo:frente:3")
	assert_eq(addresses[2], "p1:campo:frente:1")
	assert_eq(addresses[3], "p1:campo:frente:4")
	assert_eq(addresses[4], "p1:campo:trás:2")
	assert_eq(int(state.zone_counts(1)["field"]), 5)


func test_field_grows_a_column_when_both_rows_are_full():
	var cards := draw_test_cards(5)
	var state = _new_state()
	state.load_board(board, 1)
	state.set_columns(2)

	for index in range(4):
		assert_true(state.place(_id(cards[index]),
				state.find_field_slot(1)))
	assert_eq(state.columns, 2)

	var fifth := _id(cards[4])
	var address = state.find_field_slot(1)
	assert_eq(address, "p1:campo:frente:3")
	assert_true(state.place(fifth, address))
	assert_eq(state.columns, 3)
	assert_eq(state.address_of(fifth), "p1:campo:frente:3")


func test_supports_prefer_the_back_row_when_the_front_has_character():
	var cards := draw_test_cards(2)
	var state = _new_state()
	state.load_board(board, 1)
	state.set_columns(4)
	var character := _id(cards[0])
	var support := _id(cards[1])
	state.cards[character]["type"] = "Personagem"
	state.cards[support]["type"] = "Suporte"
	state.place(character, "p1:campo:frente:1")

	# The back row also fills from the center, matching the grid behaviour.
	assert_eq(state.find_field_slot(1, true), "p1:campo:trás:2")
	assert_eq(state.find_field_slot(1, false), "p1:campo:frente:2")


func test_resources_show_six_and_keep_the_rest_in_the_pile():
	var cards := draw_test_cards(8)
	var state = _new_state()
	state.load_board(board, 1)

	for card in cards:
		state.place(_id(card), "p1:recursos:1")

	assert_eq(int(state.zone_counts(1)["resources"]), 8)
	assert_eq(state.visible_resources(1).size(), 6)
	assert_eq(state.address_of(_id(cards[7])), "p1:recursos:1")
	assert_eq(state.address_of(_id(cards[2])), "p1:recursos:6")
	assert_eq(state.address_of(_id(cards[1])), "p1:recursos:pilha:1")
	assert_eq(state.address_of(_id(cards[0])), "p1:recursos:pilha:2")


func test_attachment_kind_separates_resources_from_abilities():
	var cards := draw_test_cards(2)
	var state = _new_state()
	state.load_board(board, 1)
	var host := _id(cards[0])
	var ability := _id(cards[1])
	state.place(host, "p1:campo:frente:1")
	state.cards[ability]["type"] = "Habilidade"
	var host_address = state.address_of(host)

	assert_true(state.place(ability,
			"anexo:p1:" + host_address + ":1"))
	assert_eq(state.cards[ability]["kind"], "ability")
	assert_eq(state.address_of(ability),
			"anexo:p1:" + host_address + ":1")
	assert_eq(state.cards[host]["attachments"], [ability])


func test_scenario_is_shared_and_holds_a_single_card():
	var cards := draw_test_cards(2)
	var state = _new_state()
	state.load_board(board, 1)
	var first := _id(cards[0])
	var second := _id(cards[1])

	assert_true(state.place(first, "mesa:cenário"))
	assert_false(state.place(second, "mesa:cenário"))
	assert_eq(state.scenario, first)
	assert_eq(state.address_of(first), "mesa:cenário")
	assert_eq(state.address_of(second), "p1:mão:1")
	assert_eq(int(state.zone_counts(1)["scenario"]), 1)


func test_reorder_hand_renumbers_the_slots():
	var cards := draw_test_cards(3)
	var state = _new_state()
	state.load_board(board, 1)

	assert_true(state.reorder_hand(1, 1, 3))

	assert_eq(state.address_of(_id(cards[1])), "p1:mão:1")
	assert_eq(state.address_of(_id(cards[2])), "p1:mão:2")
	assert_eq(state.address_of(_id(cards[0])), "p1:mão:3")
