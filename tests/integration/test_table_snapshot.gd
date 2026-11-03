extends "res://tests/UTcommon.gd"

# TableSnapshot is the read-only first step of the fixed-positions model. These
# tests check that it describes the table without changing it: every card gets
# one address, the counts are derived from those addresses, and loose cards show
# up as diagnostics instead of being silently ignored.
#
# The script is preloaded because a newly created class_name only enters
# project.godot after the editor rescans it; the preload keeps the test runnable
# from a fresh checkout and from the headless GUT process.

const Table = preload("res://src/core/table/TableSnapshot.gd")

const PREFIX := "p1"


func before_each():
	await setup_board()


func test_fresh_table_describes_the_deck_without_changing_it():
	var top: Card = deck.get_top_card()
	var bottom: Card = deck.get_bottom_card()
	var deck_count := deck.get_card_count()
	var network_id := str(top.network_id)

	var snapshot = Table.capture(board, 1)

	assert_eq(int(snapshot["zones"]["deck"]["count"]), deck_count)
	assert_eq(int(snapshot["total"]), deck_count)
	assert_eq(str(snapshot["zones"]["deck"]["top"]),
			Table.id_of(top))
	assert_eq(
			str(snapshot["cards"][Table.id_of(top)]["address"]),
			PREFIX + ":deck:1")
	assert_eq(
			str(snapshot["cards"][Table.id_of(bottom)]["address"]),
			PREFIX + ":deck:" + str(deck_count))
	assert_eq(str(top.network_id), network_id,
			"The snapshot does not create a network id as a side effect")
	assert_true(snapshot["issues"].is_empty(), Table.describe(snapshot))


func test_drawn_cards_receive_hand_slots_in_order():
	var initial_deck := deck.get_card_count()
	var cards := draw_test_cards(5)

	var snapshot = Table.capture(board, 1)

	assert_eq(int(snapshot["zones"]["hand"]["count"]), 5)
	assert_eq(int(snapshot["zones"]["deck"]["count"]), initial_deck - 5)
	assert_eq(int(snapshot["total"]), initial_deck)
	for index in range(cards.size()):
		var entry: Dictionary = snapshot["cards"][Table.id_of(cards[index])]
		assert_eq(str(entry["address"]), PREFIX + ":mão:" + str(index + 1))
		assert_eq(str(entry["zone"]), "hand")
	assert_true(snapshot["issues"].is_empty(), Table.describe(snapshot))


func test_field_slot_sets_the_card_address():
	var cards := draw_test_cards(2)
	var grid: BoardPlacementGrid = board.get_node("BoardPlacementGrid")
	cards[0].move_to(board, -1, grid.get_slot(0))
	await yield_for(0.1)

	# The test grid starts with a single row; adding four slots creates the
	# back row without changing the four columns.
	for _i in range(4):
		grid.add_slot()
	cards[1].move_to(board, -1, grid.get_slot(4))
	await yield_for(0.1)

	var snapshot = Table.capture(board, 1)

	assert_eq(int(snapshot["zones"]["field"]["count"]), 2)
	assert_eq(int(snapshot["zones"]["field"]["columns"]), 4)
	assert_eq(int(snapshot["zones"]["field"]["slots"]), 8)
	assert_eq(int(snapshot["zones"]["field"]["free"]), 6)
	assert_eq(
			str(snapshot["cards"][Table.id_of(cards[0])]["address"]),
			PREFIX + ":campo:frente:1")
	assert_eq(
			str(snapshot["cards"][Table.id_of(cards[1])]["address"]),
			PREFIX + ":campo:trás:1")
	assert_true(snapshot["issues"].is_empty(), Table.describe(snapshot))


func test_attachment_belongs_to_its_host_address():
	var initial_deck := deck.get_card_count()
	var cards := draw_test_cards(2)
	var grid: BoardPlacementGrid = board.get_node("BoardPlacementGrid")
	cards[0].move_to(board, -1, grid.get_slot(0))
	cards[1].attach_to_host(cards[0])
	await yield_for(0.2)

	var snapshot = Table.capture(board, 1)
	var host_id = Table.id_of(cards[0])
	var attachment_id = Table.id_of(cards[1])

	assert_eq(str(snapshot["cards"][attachment_id]["zone"]), "attachment")
	assert_eq(str(snapshot["cards"][attachment_id]["host"]), host_id)
	assert_eq(
			str(snapshot["cards"][attachment_id]["address"]),
			"anexo:" + PREFIX + ":" + PREFIX + ":campo:frente:1:1")
	assert_eq(snapshot["cards"][host_id]["attachments"], [attachment_id])
	assert_eq(int(snapshot["zones"]["attachments"]), 1)
	assert_eq(int(snapshot["zones"]["field"]["count"]), 1)
	assert_eq(int(snapshot["total"]), initial_deck)
	assert_true(snapshot["issues"].is_empty(), Table.describe(snapshot))


func test_resources_are_numbered_from_the_top_of_the_discard():
	var cards := draw_test_cards(3)
	for card in cards:
		await card.move_to(discard)

	var snapshot = Table.capture(board, 1)

	assert_eq(int(snapshot["zones"]["resources"]["count"]), 3)
	assert_eq(int(snapshot["zones"]["resources"]["visible"]), 3)
	assert_eq(
			str(snapshot["cards"][Table.id_of(cards[2])]["address"]),
			PREFIX + ":recursos:1")
	assert_eq(
			str(snapshot["cards"][Table.id_of(cards[0])]["address"]),
			PREFIX + ":recursos:3")
	assert_true(snapshot["issues"].is_empty(), Table.describe(snapshot))


func test_prizes_number_the_first_free_slot_from_the_top():
	var prizes = load("res://src/core/Pile.tscn").instantiate()
	prizes.name = "Prêmios"
	board.add_child(prizes)
	autofree(prizes)
	await yield_for(0.1)
	var cards := draw_test_cards(2)
	for card in cards:
		await card.move_to(prizes)

	var snapshot = Table.capture(board, 1)

	assert_eq(int(snapshot["zones"]["prizes"]["count"]), 2)
	assert_eq(
			str(snapshot["cards"][Table.id_of(cards[1])]["address"]),
			PREFIX + ":prêmios:1")
	assert_eq(
			str(snapshot["cards"][Table.id_of(cards[0])]["address"]),
			PREFIX + ":prêmios:2")
	assert_true(snapshot["issues"].is_empty(), Table.describe(snapshot))


func test_a_loose_card_is_reported_as_a_problem():
	var card: Card = draw_test_cards(1)[0]
	hand.remove_child(card)
	board.add_child(card)

	var snapshot = Table.capture(board, 1)

	assert_eq(int(snapshot["zones"]["transit"]), 1)
	assert_eq(str(snapshot["cards"][Table.id_of(card)]["address"]),
			Table.TRANSIT_ADDRESS)
	var has_loose_issue := false
	for issue in snapshot["issues"]:
		if str(issue.get("type", "")) == "sem_endereco":
			has_loose_issue = true
	assert_true(has_loose_issue, Table.describe(snapshot))


func test_describe_lists_zones_and_addresses():
	var initial_deck := deck.get_card_count()
	var cards := draw_test_cards(2)
	var snapshot = Table.capture(board, 1)
	var text = Table.describe(snapshot)

	assert_string_contains(text, "visão P1")
	assert_string_contains(text, "mão (2)")
	assert_string_contains(text, "p1:mão:1 " + cards[0].canonical_name)
	assert_string_contains(text, "deck (" + str(initial_deck - 2) + ")")
	var top: Card = deck.get_top_card()
	assert_string_contains(text, "topo " + top.canonical_name)
	assert_string_contains(text, "p1:deck:1 " + top.canonical_name)
