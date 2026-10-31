extends "res://tests/UTcommon.gd"

# The probe reaches the network, so the menu instance is never added to the
# tree: _ready (and with it the first request) does not run. These two helpers
# only turn a typed address into a URL and a reading into a label, which is
# what the player actually sees.
const MENU_SCENE = preload("res://src/custom/MainMenu.tscn")

var menu


func before_each():
	menu = autoqfree(MENU_SCENE.instance())


func test_bare_address_gets_the_default_relay_port():
	assert_eq(menu._relay_health_url("127.0.0.1"), "http://127.0.0.1:9080/healthz")
	assert_eq(menu._relay_health_url("  192.168.1.85  "),
			"http://192.168.1.85:9080/healthz")


func test_typed_port_is_kept():
	assert_eq(menu._relay_health_url("192.168.1.85:9100"),
			"http://192.168.1.85:9100/healthz")


func test_websocket_schemes_become_http_on_the_same_host():
	assert_eq(menu._relay_health_url("ws://127.0.0.1:9080"),
			"http://127.0.0.1:9080/healthz")
	assert_eq(menu._relay_health_url("wss://relay.exemplo.com"),
			"https://relay.exemplo.com/healthz")


func test_explicit_http_is_left_alone():
	assert_eq(menu._relay_health_url("http://localhost:9080"),
			"http://localhost:9080/healthz")
	assert_eq(menu._relay_health_url("https://relay.exemplo.com/"),
			"https://relay.exemplo.com/healthz")


func test_empty_address_has_no_probe_url():
	assert_eq(menu._relay_health_url(""), "")
	assert_eq(menu._relay_health_url("   "), "")


func test_state_text_counts_open_rooms():
	assert_eq(menu._server_state_text(false, 3), "Servidor: indisponível")
	assert_eq(menu._server_state_text(true, 0), "Servidor: online")
	assert_eq(menu._server_state_text(true, 1), "Servidor: online (1 sala)")
	assert_eq(menu._server_state_text(true, 2), "Servidor: online (2 salas)")
