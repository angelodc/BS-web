extends "res://tests/UTcommon.gd"

const CheckpointStore = preload("res://src/custom/CheckpointStore.gd")
const DeckCatalog = preload("res://src/custom/DeckCatalog.gd")


func test_match_found_assigns_player_role_and_opponent_name():
	Rede.disconnect_game()
	Rede.is_searching = true
	watch_signals(Rede)
	var packet: PoolByteArray = JSON.print({
		"t": "match_found",
		"role": "H",
		"opponent": "Jogador 2",
	}).to_utf8()

	Rede._handle_packet(packet)

	assert_true(Rede.is_connected)
	assert_false(Rede.is_searching)
	assert_eq(Rede.peer_tag, "H")
	assert_eq(Rede.opponent_username, "Jogador 2")
	assert_signal_emitted_with_parameters(
			Rede, "match_found", ["Jogador 2"])
	assert_signal_emitted(Rede, "peer_connected")
	Rede.disconnect_game()


func test_match_found_keeps_resume_metadata():
	Rede.disconnect_game()
	Rede.is_searching = true

	Rede._handle_packet(JSON.print({
		"t": "match_found",
		"role": "C",
		"opponent": "Alice",
		"room_id": "resume_game_1",
		"mode": "resume",
		"game_id": "game_1",
		"participants": ["Alice", "Bob"],
	}).to_utf8())

	assert_eq(Rede.match_mode, "resume")
	assert_eq(Rede.game_id, "game_1")
	assert_eq(Rede.room_id, "resume_game_1")
	assert_eq(Rede.match_participants, ["Alice", "Bob"])
	Rede.disconnect_game()


func test_match_found_after_cancel_is_ignored():
	Rede.disconnect_game()
	Rede.is_searching = false
	watch_signals(Rede)

	Rede._handle_packet(JSON.print({
		"t": "match_found",
		"role": "C",
		"opponent": "Alice",
	}).to_utf8())

	assert_false(Rede.is_connected)
	assert_eq(Rede.peer_tag, "")
	assert_signal_not_emitted(Rede, "match_found")


func test_private_envelopes_are_pruned():
	var previous: Dictionary = Multiplayer._private_envelopes
	Multiplayer._private_envelopes = {}
	for seq in range(Multiplayer.MAX_CACHED_STATES + 4):
		Multiplayer._private_envelopes[seq] = {"Alice": "x"}
	Multiplayer._prune_private_envelopes()

	assert_eq(Multiplayer._private_envelopes.size(),
			Multiplayer.MAX_CACHED_STATES)
	assert_false(Multiplayer._private_envelopes.has(0))
	assert_true(Multiplayer._private_envelopes.has(
			Multiplayer.MAX_CACHED_STATES + 3))
	Multiplayer._private_envelopes = previous


func test_unreadable_checkpoint_stays_joinable():
	CheckpointStore.ensure_root()
	var game_id := "gtest_corrupt_" + str(OS.get_ticks_usec())
	var game_dir := CheckpointStore.game_directory(game_id)
	var directory := Directory.new()
	directory.make_dir_recursive(game_dir)
	var path := game_dir + "0.json"
	var file := File.new()
	file.open(path, File.WRITE)
	file.store_string("not json")
	file.close()

	var found := {}
	for game in CheckpointStore.list_games():
		if str(game.get("game_id", "")) == game_id:
			found = game

	assert_false(found.empty())
	assert_true(bool(found.get("join_only", false)))
	assert_eq(found.get("participants", []).size(), 0)
	directory.remove(path)
	directory.remove(game_dir.substr(0, game_dir.length() - 1))


func test_display_diagnostics_are_shared():
	var previous: Dictionary = Multiplayer.opponent_display
	var previous_checked: bool = Multiplayer._display_checked
	watch_signals(Multiplayer)

	Multiplayer._store_opponent_display({"display": {
		"screen": [1600, 900],
		"window": [1600, 900],
		"viewport": [1280, 720],
		"stretch": "viewport",
		"aspect": "keep",
	}})

	assert_signal_emitted(Multiplayer, "display_changed")
	assert_eq(Multiplayer.opponent_display["screen"], [1600, 900])
	var summary: String = Multiplayer.get_display_summary()
	assert_true(summary.find("Você:") >= 0)
	assert_true(summary.find("Oponente: tela 1600x900") >= 0)
	assert_true(summary.find("lógico 1280x720") >= 0)
	assert_eq(str(Multiplayer.opponent_display["stretch"]), "viewport",
			"Opponent display diagnostics keep the reported stretch mode")

	Multiplayer.opponent_display = previous
	Multiplayer._display_checked = previous_checked


func test_opponent_disconnect_clears_connected_state():
	Rede.disconnect_game()
	Rede.is_connected = true
	watch_signals(Rede)

	Rede._handle_packet(JSON.print({
		"t": "opponent_disconnected",
	}).to_utf8())

	assert_false(Rede.is_connected)
	assert_signal_emitted(Rede, "peer_disconnected")


func test_chunked_network_message_is_reassembled():
	Rede.disconnect_game()
	Rede.is_connected = true
	watch_signals(Rede)
	var text := JSON.print({
		"t": "mp_test",
		"payload": "x".repeat(25000),
	})
	var count := int(ceil(float(text.length()) / Rede.MAX_MESSAGE_CHARS))
	for index in range(count):
		Rede._handle_packet(JSON.print({
			"t": "mp_chunk",
			"id": "chunk-test",
			"i": index,
			"n": count,
			"p": text.substr(
					index * Rede.MAX_MESSAGE_CHARS,
					Rede.MAX_MESSAGE_CHARS),
		}).to_utf8())

	assert_true(Rede._incoming_chunks.empty())
	assert_signal_emitted(Rede, "message_received")
	Rede.disconnect_game()


func test_lan_relay_address_defaults_to_port_9080():
	assert_eq(
			Rede._normalize_url("192.168.1.20"),
			"ws://192.168.1.20:9080")
	assert_eq(
			Rede._normalize_url("wss://relay.example.test/socket"),
			"wss://relay.example.test/socket")


func test_main_menu_contains_matchmaking_fields():
	var menu: Control = load("res://src/custom/MainMenu.tscn").instance()

	assert_true(menu.has_node(
			"MainMenu/VBox/Center/VButtons/PlayerName"))
	assert_true(menu.has_node(
			"MainMenu/VBox/Center/VButtons/RelayAddress"))
	assert_true(menu.has_node(
			"MainMenu/VBox/Center/VButtons/Multiplayer"))
	assert_true(menu.has_node(
			"MainMenu/VBox/Center/VButtons/CreateMatch"))
	assert_true(menu.has_node(
			"MainMenu/VBox/Center/VButtons/ResumeGame"))
	assert_true(menu.has_node(
			"MainMenu/VBox/Center/VButtons/SavedDecks"))
	assert_true(menu.has_node("CheckpointList"))
	assert_true(menu.has_node("ActionError"))
	menu.free()


func test_main_menu_error_dialog_has_ok_button():
	var menu: Control = load("res://src/custom/MainMenu.tscn").instance()
	add_child(menu)
	menu._show_action_error("Mensagem de teste")

	assert_true(menu.action_error.visible)
	assert_eq(menu.action_error.dialog_text, "Mensagem de teste")
	assert_true(menu.action_error.get_ok() != null)
	assert_true(menu.action_error.get_label().autowrap)
	menu.action_error.hide()
	menu.free()


func test_deck_catalog_lists_saved_decks():
	var directory := Directory.new()
	var make_error := directory.make_dir_recursive(CFConst.DECKS_PATH)
	assert_true(make_error == OK or make_error == ERR_ALREADY_EXISTS)
	var path: String = CFConst.DECKS_PATH + "gut_deck_catalog.json"
	var file := File.new()
	assert_eq(file.open(path, File.WRITE), OK)
	file.store_string(JSON.print({
		"name": "GUT Catalog",
		"cards": {"BSCA_001": 2, "BSCA_002": 1},
	}))
	file.close()

	var entries := DeckCatalog.list_decks()
	var found := {}
	for entry in entries:
		if str(entry["path"]) == path:
			found = entry
	assert_false(found.empty(), "Saved deck must be listed by the catalog")
	if not found.empty():
		assert_eq(str(found["name"]), "GUT Catalog")
		assert_eq(int(found["count"]), 3)
	directory.remove(path)


func test_deck_catalog_rejects_invalid_saved_decks():
	var path: String = CFConst.DECKS_PATH + "gut_deck_catalog_invalid.json"
	var file := File.new()
	assert_eq(file.open(path, File.WRITE), OK)
	file.store_string(JSON.print({"name": "Incompleto", "cards": {}}))
	file.close()
	assert_true(DeckCatalog.load_deck(path).empty())
	var directory := Directory.new()
	directory.remove(path)


func test_match_hud_exposes_preparation_controls():
	var hud: Control = load("res://src/custom/MatchHUD.tscn").instance()

	assert_true(hud.has_node("PreparePanel/Margin/VBox/DeckButtons/SavedDecks"))
	assert_true(hud.has_node("PreparePanel/Margin/VBox/DisplayLabel"))
	assert_true(hud.has_node("PreparePanel/Margin/VBox/DeckButtons/LinkDeck"))
	assert_true(hud.has_node("PreparePanel/Margin/VBox/StartButton"))
	assert_true(hud.has_node("Overlay/Center/VBox/Buttons/ReconnectButton"))
	hud.free()


func test_checkpoint_private_payload_round_trip():
	var payload := {
		"hand": [{"id": "c1", "name": "Test Card 1"}],
		"deck": [{"id": "c2", "name": "Test Card 2"}],
	}
	var envelope := CheckpointStore.protect_payload(payload, "Alice")

	assert_true(envelope.begins_with(CheckpointStore.ENVELOPE_PREFIX))
	var restored := CheckpointStore.unprotect_payload(envelope, "Alice")
	var restored_hand: Array = restored.get("hand", [])
	var restored_deck: Array = restored.get("deck", [])
	assert_eq(restored_hand.size(), 1)
	assert_eq(restored_deck.size(), 1)
	assert_true(CheckpointStore.unprotect_payload(envelope, "Bob").empty())


func test_reprotect_keeps_checkpoint_on_username_collision():
	var suffix := str(OS.get_ticks_usec())
	var host := "gut_host_" + suffix
	var guest := "gut_guest_" + suffix
	var renamed := "gut_renamed_" + suffix
	var game_id := "gtest_reprotect_" + suffix
	var public_state := {
		"phase": "PREP",
		"hidden": {
			"1": {"hand": 1, "deck": 0},
			"2": {"hand": 0, "deck": 1},
		},
	}
	var saved := CheckpointStore.save_checkpoint(
			game_id, 0, 1, 0, 1, [2, 5], host, guest, public_state, {
				host: CheckpointStore.protect_payload({
					"hand": [{"id": "h1"}],
					"deck": [],
				}, host),
				guest: CheckpointStore.protect_payload({
					"hand": [],
					"deck": [{"id": "d1"}],
				}, guest),
			})
	assert_true(saved.get("ok", false), "Checkpoint base deve ser valido")

	var collision := CheckpointStore.reprotect_all(host, guest)
	assert_true(collision.get("ok", false))
	assert_eq(int(collision.get("changed", 0)), 0)
	assert_true(int(collision.get("skipped", 0)) >= 1)
	var still_old := CheckpointStore.load_checkpoint(game_id, 0)
	assert_true(still_old.get("ok", false))
	assert_eq(str(still_old["data"]["p1"]), host)
	assert_eq(str(still_old["data"]["p2"]), guest)

	var renamed_result := CheckpointStore.reprotect_all(host, renamed)
	assert_true(renamed_result.get("ok", false))
	assert_true(int(renamed_result.get("changed", 0)) >= 1)
	var updated := CheckpointStore.load_checkpoint(game_id, 0)
	assert_true(updated.get("ok", false))
	assert_eq(str(updated["data"]["p1"]), renamed)

	var directory := Directory.new()
	directory.remove(CheckpointStore.checkpoint_path(game_id, 0))
	directory.remove(CheckpointStore.game_directory(game_id))


func test_checkpoint_validation_requires_both_players_envelopes():
	var public_state := {
		"phase": "PREP",
		"hidden": {
			"1": {"hand": 1, "deck": 0},
			"2": {"hand": 0, "deck": 0},
		},
	}
	var alice_payload := CheckpointStore.protect_payload({
		"hand": [{"id": "c1", "name": "Test Card 1"}],
		"deck": [],
	}, "Alice")
	var bob_payload := CheckpointStore.protect_payload({
		"hand": [],
		"deck": [],
	}, "Bob")
	var data := {
		"schema": CheckpointStore.SCHEMA_VERSION,
		"game_id": "game_1",
		"p1": "Alice",
		"p2": "Bob",
		"public": public_state,
		"public_checksum": CheckpointStore.public_checksum(public_state),
		"private": {"Alice": alice_payload, "Bob": bob_payload},
	}

	assert_true(CheckpointStore.validate_checkpoint(data).get("ok", false))
	var private_data: Dictionary = data["private"]
	private_data.erase("Bob")
	assert_false(CheckpointStore.validate_checkpoint(data).get("ok", false))
