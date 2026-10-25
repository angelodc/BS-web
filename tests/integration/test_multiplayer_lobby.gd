extends "res://tests/UTcommon.gd"


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


func test_opponent_disconnect_clears_connected_state():
	Rede.disconnect_game()
	Rede.is_connected = true
	watch_signals(Rede)

	Rede._handle_packet(JSON.print({
		"t": "opponent_disconnected",
	}).to_utf8())

	assert_false(Rede.is_connected)
	assert_signal_emitted(Rede, "peer_disconnected")


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
	menu.free()
