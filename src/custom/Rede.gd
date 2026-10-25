# Godot 3 WebSocket client for LAN matchmaking and card-state mirroring.
extends Node

const DEFAULT_PORT := 9080
const DEFAULT_ADDRESS := "127.0.0.1:9080"

signal status_changed(text)
signal peer_connected()
signal peer_disconnected()
signal message_received(data)
signal match_found(opponent_username)

var is_connected := false
var is_searching := false
var peer_tag := ""
var player_username := ""
var opponent_username := ""
var _client: WebSocketClient
var _last_status := "Desconectado"


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	if _client:
		_client.poll()


func find_match(address: String, username: String) -> bool:
	disconnect_game()
	player_username = username.strip_edges()
	if player_username.empty():
		_set_status("Digite seu username antes de procurar uma partida.")
		return false
	is_searching = true
	_client = WebSocketClient.new()
	# warning-ignore:return_value_discarded
	_client.connect("connection_established", self, "_on_client_connected")
	# warning-ignore:return_value_discarded
	_client.connect("connection_closed", self, "_on_client_closed")
	# warning-ignore:return_value_discarded
	_client.connect("connection_error", self, "_on_client_error")
	# warning-ignore:return_value_discarded
	_client.connect("data_received", self, "_on_client_data")
	var url := _normalize_url(address)
	var connect_error := _client.connect_to_url(url, PoolStringArray(), false)
	if connect_error != OK:
		_client = null
		is_searching = false
		_set_status("Não foi possível conectar ao relay em " + url)
		return false
	_set_status("Conectando ao relay " + url + "...")
	return true


func disconnect_game() -> void:
	var was_connected := is_connected
	is_connected = false
	is_searching = false
	peer_tag = ""
	opponent_username = ""
	if _client:
		_client.disconnect_from_host()
		_client = null
	if was_connected:
		emit_signal("peer_disconnected")
	_set_status("Desconectado")


func send_message(data: Dictionary) -> void:
	if not is_connected or not _client \
			or _client.get_connection_status() \
			!= NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		return
	data["from"] = peer_tag
	data["username"] = player_username
	_send_packet(data)


func get_status() -> String:
	return _last_status


func _normalize_url(address: String) -> String:
	var trimmed := address.strip_edges()
	if trimmed.empty():
		trimmed = DEFAULT_ADDRESS
	if trimmed.begins_with("ws://") or trimmed.begins_with("wss://"):
		return trimmed
	if not ":" in trimmed:
		trimmed += ":" + str(DEFAULT_PORT)
	return "ws://" + trimmed


func _send_packet(data: Dictionary) -> void:
	if not _client or _client.get_connection_status() \
			!= NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		return
	var peer: WebSocketPeer = _client.get_peer(1)
	if not peer:
		return
	peer.set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	var packet_error := peer.put_packet(JSON.print(data).to_utf8())
	if packet_error != OK:
		_set_status("Falha ao enviar mensagem ao relay.")


func _on_client_connected(_protocol: String) -> void:
	_send_packet({
		"t": "find_match",
		"username": player_username,
	})
	_set_status("Procurando partida na rede local...")


func _on_client_closed(_was_clean: bool) -> void:
	var was_connected := is_connected
	is_connected = false
	is_searching = false
	_set_status("Conexão com o relay encerrada.")
	if was_connected:
		emit_signal("peer_disconnected")


func _on_client_error() -> void:
	var was_connected := is_connected
	is_connected = false
	is_searching = false
	_set_status("Erro ao conectar ao relay. Confira o endereço e se ele está ativo.")
	if was_connected:
		emit_signal("peer_disconnected")


func _on_client_data() -> void:
	if _client and _client.get_peer(1):
		_handle_packet(_client.get_peer(1).get_packet())


func _handle_packet(packet: PoolByteArray) -> void:
	var parsed := JSON.parse(packet.get_string_from_utf8())
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed.result
	match str(data.get("t", "")):
		"waiting":
			_set_status(str(data.get(
					"msg", "Procurando partida na rede local...")))
		"match_found":
			is_searching = false
			is_connected = true
			peer_tag = str(data.get("role", ""))
			opponent_username = str(data.get("opponent", "Oponente"))
			_set_status("Partida encontrada contra " + opponent_username + ".")
			emit_signal("match_found", opponent_username)
			emit_signal("peer_connected")
		"opponent_disconnected":
			is_connected = false
			is_searching = false
			_set_status("O oponente saiu da partida.")
			emit_signal("peer_disconnected")
		"error":
			is_searching = false
			_set_status(str(data.get("msg", "Erro no serviço de partidas.")))
		_:
			if is_connected:
				emit_signal("message_received", data)


func _set_status(text: String) -> void:
	_last_status = text
	emit_signal("status_changed", text)
