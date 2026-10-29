extends "res://tests/UTcommon.gd"

var cards := []


func before_each():
	var confirm_return = setup_board()
	if confirm_return is GDScriptFunctionState:
		confirm_return = yield(confirm_return, "completed")
	cards = draw_test_cards(3)
	yield(yield_for(0.1), YIELD)
	GameEvents.set_enabled(true)


func after_each():
	GameEvents.set_enabled(false)
	GameEvents.entries.clear()


func test_move_to_board_logs_the_card_name():
	var card: Card = cards[0]
	card.properties["_tipo"] = "Habilidade"
	card.move_to(board)
	yield(yield_for(0.3), YIELD)
	assert_eq(GameEvents.entries.size(), 1, "One entry for the move")
	var entry: Dictionary = GameEvents.entries.back()
	assert_eq(entry["action"], "played_field", "A plain field play is classified")
	assert_eq(entry["card"], card.canonical_name,
			"A face up card on the field reveals its name")
	assert_true(str(entry["text"]).find(card.canonical_name) >= 0,
			"The sentence carries the card name")


func test_character_play_is_classified():
	var card: Card = cards[0]
	card.properties["_tipo"] = "Personagem"
	card.move_to(board)
	yield(yield_for(0.3), YIELD)
	var entry: Dictionary = GameEvents.entries.back()
	assert_eq(entry["action"], "played_character", "Characters get their own action")
	assert_true(str(entry["text"]).find("na cena") >= 0,
			"The sentence says the character went to the scene")


func test_scenario_play_is_classified_separately():
	var card: Card = cards[1]
	card.properties["_tipo"] = "Cenário"
	card.move_to(board)
	yield(yield_for(0.3), YIELD)
	var entry: Dictionary = GameEvents.entries.back()
	assert_eq(entry["action"], "played_scenario", "Scenario cards get their own action")
	assert_true(str(entry["text"]).find("cenário") >= 0,
			"The sentence says a scenario was placed")


func test_move_to_resources_reveals_the_name():
	var card: Card = cards[2]
	card.move_to(discard)
	yield(yield_for(0.3), YIELD)
	var entry: Dictionary = GameEvents.entries.back()
	assert_eq(entry["action"], "placed_resources",
			"The discard pile is the resource zone")
	assert_eq(entry["card"], card.canonical_name, "Resources stay public")


func test_draw_from_deck_hides_the_card_identity():
	var card: Card = deck.get_top_card()
	card.move_to(hand)
	yield(yield_for(0.3), YIELD)
	var entry: Dictionary = GameEvents.entries.back()
	assert_eq(entry["action"], "drew", "Drawing from the deck is classified")
	assert_eq(entry["card"], "", "The drawn card keeps its identity private")
	assert_eq(entry["public"], false, "A draw is not a public event")
	assert_true(str(entry["text"]).find("comprou 1 carta") >= 0,
			"The sentence only says a card was drawn")


func test_privacy_rules():
	assert_false(GameEvents._reveals("X", "hand", "deck", true),
			"A draw never reveals the card")
	assert_false(GameEvents._reveals("X", "prizes", "hand", false),
			"A face down card reaching a public zone stays hidden")
	assert_true(GameEvents._reveals("X", "prizes", "board", false),
			"A card that was already public keeps its name")
	assert_true(GameEvents._reveals("X", "board", "", true),
			"A face up card played to the field is public")
	assert_false(GameEvents._reveals("", "board", "", true),
			"An unnamed event reveals nothing")


func test_net_tagged_changes_are_ignored():
	var card: Card = cards[0]
	card.move_to(board, -1, null, ["net"])
	yield(yield_for(0.3), YIELD)
	assert_eq(GameEvents.entries.size(), 0,
			"A network replay does not log the same move twice")


func test_remote_entry_uses_the_opponent_slot():
	GameEvents.record_remote_card("board", "Carta Remota", true)
	var entry: Dictionary = GameEvents.entries.back()
	assert_eq(entry["slot"], 2, "Without a session the remote seat is P2")
	assert_eq(entry["actor"], "P2", "The actor falls back to the slot name")
	assert_eq(entry["card"], "Carta Remota", "A face up remote card keeps its name")


func test_remote_face_down_entry_hides_the_name():
	GameEvents.record_remote_card("prizes", "Prêmio Remoto", false)
	var entry: Dictionary = GameEvents.entries.back()
	assert_eq(entry["action"], "placed_prizes", "The prize zone is classified")
	assert_eq(entry["card"], "", "A face down remote card stays anonymous")


func test_entries_are_capped():
	var total := GameEvents.MAX_ENTRIES + 20
	for index in range(total):
		GameEvents.record_system("Linha " + str(index))
	assert_eq(GameEvents.entries.size(), GameEvents.MAX_ENTRIES,
			"The log stops growing at the cap")
	assert_eq(str(GameEvents.entries.back()["text"]), "Linha " + str(total - 1),
			"The newest entry is the one kept")


func test_disabled_bus_records_nothing():
	GameEvents.set_enabled(false)
	GameEvents.record_system("Ignorado")
	GameEvents.record_remote_card("board", "Carta", true)
	assert_eq(GameEvents.entries.size(), 0, "A disabled bus stays silent")


func test_log_line_links_the_card_name():
	var hud = add_child_autofree(load("res://src/custom/MatchHUD.tscn").instance())
	yield(yield_for(0.1), YIELD)
	hud._append_log("P1 colocou Carta X nos Recursos", "Carta X")
	var index: int = hud._logs.size() - 1
	var line := str(hud._line_bbcode(index))
	assert_true(line.find("[url=" + str(index) + "]") >= 0,
			"The card name becomes a meta link keyed by its line")
	assert_true(line.find("Carta X") >= 0, "The name stays readable")
	assert_eq(hud._card_name_for_meta(str(index)), "Carta X",
			"The meta index resolves back to the card name")


func test_log_line_without_card_has_no_meta():
	var hud = add_child_autofree(load("res://src/custom/MatchHUD.tscn").instance())
	yield(yield_for(0.1), YIELD)
	hud._append_log("P2 comprou 1 carta")
	var line := str(hud._line_bbcode(hud._logs.size() - 1))
	assert_eq(line.find("[url="), -1, "A private line carries no link")
