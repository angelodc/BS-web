extends "res://tests/UTcommon.gd"

const SCENARIO_GRID_SCENE = preload("res://src/custom/CGFModifiedLabelGrid.tscn")


func before_each():
	await setup_board()
	var scenario_grid: BoardPlacementGrid = SCENARIO_GRID_SCENE.instantiate()
	scenario_grid.name = "ModifiedLabelGrid"
	board.add_child(scenario_grid)
	scenario_grid.add_slot()


func _scenario_card() -> Card:
	var card: Card = cfc.instance_card("Demo Scenario")
	card.properties["Name"] = "Cenário de teste"
	deck.add_child(card)
	return card


# A scenario chosen in the deck search is revealed like every other card: it
# shows up at a free spot on the field for three seconds and then joins the
# hand. It never enters the shared scenario slot, so the active scenario on the
# table stays where it is.
func test_searched_scenario_is_revealed_then_reaches_the_hand():
	var slot = board.get_node("ModifiedLabelGrid").get_all_slots()[0]
	var active := _scenario_card()
	await active.move_to(board, -1, slot, ["Manual"])
	await yield_for(0.2)
	assert_eq(slot.occupying_card, active, "The active scenario is on the table")

	var card := _scenario_card()
	deck._on_search_card_picked(card)
	await yield_for(1.0)

	assert_eq(card.get_parent(), board, "The scenario is revealed on the field")
	assert_ne(slot.occupying_card, card,
			"The reveal does not claim the scenario slot")
	assert_false(hand.get_all_cards().has(card),
			"The reveal stays on the field for a moment")

	await yield_for(3.0)
	assert_eq(card.get_parent(), hand, "The searched scenario reaches the hand")
	assert_eq(slot.occupying_card, active, "The active scenario is untouched")
	assert_false(deck._deck_action_in_progress,
			"The search is free for the next action")


# A card that is not a scenario keeps the reveal: it shows up on the field for
# a moment and then joins the hand, which is the search result the other types
# already had.
func test_searched_character_still_reaches_the_hand():
	var card: Card = cfc.instance_card("Test Card 1")
	card.properties["_tipo"] = "Personagem"
	card.properties["ENERGIA"] = "0"
	deck.add_child(card)
	deck._on_search_card_picked(card)
	await yield_for(4.0)

	assert_eq(card.get_parent(), hand, "The searched character reaches the hand")
	assert_false(deck._deck_action_in_progress,
			"The search is free for the next action")
