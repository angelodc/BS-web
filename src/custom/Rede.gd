# Godot 3 WebSocket client for LAN rooms, resume and card-state mirroring.
extends Node

const DEFAULT_PORT := 9080
const DEFAULT_ADDRESS := "127.0.0.1:9080"
# Placeholder do relay publico; troque ao publicar o servico (Fase 4).
const WEB_DEFAULT_ADDRESS := "wss://relay.exemplo.com"
# Godot 3 caps WebSocket messages at 64 KiB; keep each chunk well below it.
const MAX_MESSAGE_CHARS := 12000

signal status_changed(text)
signal peer_connected()
signal peer_disconnected()
signal match_found(opponent_username)
signal opponent_lost(reconnectable, grace_seconds, room_id)
signal opponent_reconnected(username, role)
signal opponent_left()
signal rejoined(role, opponent)
signal connection_lost()
signal room_expired(message)
signal join_failed(message)
signal search_cancelled()
signal message_received(data)

var is_connected := false
var is_searching := false
var peer_tag := ""
var player_username := ""
var opponent_username := ""
var room_id := ""
var match_mode := ""
var game_id := ""
var match_participants := []
var reconnectable := false
var reconnect_grace_seconds := 0
var last_address := DEFAULT_ADDRESS
var _client: WebSocketClient
var _last_status := "Desconectado"
var _pending_action := {}
var _incoming_chunks := {}
var _chunk_counter := 0


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	if _client:
		_client.poll()


func create_room(address: String, username: String) -> bool:
	return _connect_for_action(
			address,
			username,
			{"t": "create_room", "username": username.strip_edges()},
			"Conectando ao relay para criar a sala...")


func find_match(address: String, username: String) -> bool:
	return _connect_for_action(
			address,
			username,
			{"t": "find_match", "username": username.strip_edges()},
			"Conectando ao relay para procurar partida...")


func create_resume_room(
		address: String,
		username: String,
		checkpoint_game_id: String,
		participants: Array) -> bool:
	return _connect_for_action(
			address,
			username,
			{
				"t": "create_resume_room",
				"username": username.strip_edges(),
				"game_id": checkpoint_game_id,
				"participants": participants,
			},
			"Conectando ao relay para hospedar a retomada...")


func join_resume_room(
		address: String,
		username: String,
		checkpoint_game_id: String,
		participants: Array) -> bool:
	return _connect_for_action(
			address,
			username,
			{
				"t": "join_resume_room",
				"username": username.strip_edges(),
				"game_id": checkpoint_game_id,
				"participants": participants,
			},
			"Conectando ao relay para procurar a retomada...")


func reconnect_room(address: String, username: String) -> bool:
	if room_id.empty():
		_set_status("Nao ha sala para reconectar.")
		return false
	return _connect_for_action(
			address,
			username,
			{
				"t": "rejoin_room",
				"room_id": room_id,
				"username": username.strip_edges(),
			},
			"Reconectando a sala...")


func join_room(address: String, username: String, room_code: String) -> bool:
	var code := room_code.strip_edges().to_upper()
	if code.empty():
		_set_status("Informe o codigo da sala.")
		return false
	return _connect_for_action(
			address,
			username,
			{
				"t": "join_room",
				"code": code,
				"username": username.strip_edges(),
			},
			"Entrando na sala " + code + "...")


func cancel_search() -> void:
	if not is_searching and not is_connected:
		return
	if _client:
		_send_packet({"t": "cancel_match"})
	is_searching = false
	_close_socket()
	_reset_match()
	_set_status("Busca cancelada.")


func disconnect_game() -> void:
	var was_connected := is_connected
	if _client:
		if is_connected or not room_id.empty():
			_send_packet({"t": "leave_room"})
		_close_socket()
	is_connected = false
	is_searching = false
	_reset_match()
	if was_connected:
		emit_signal("peer_disconnected")
	_set_status("Desconectado")


func leave_room() -> void:
	disconnect_game()


func send_message(data: Dictionary) -> void:
	if not is_connected or not _client \
			or _client.get_connection_status() \
			!= NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		return
	data["from"] = peer_tag
	data["username"] = player_username
	var text := JSON.print(data)
	if text.length() <= MAX_MESSAGE_CHARS:
		_send_packet(data)
		return
	_chunk_counter += 1
	var chunk_id := str(OS.get_ticks_usec()) + "-" + str(_chunk_counter)
	var count := int(ceil(float(text.length()) / MAX_MESSAGE_CHARS))
	for index in range(count):
		_send_packet({
			"t": "mp_chunk",
			"id": chunk_id,
			"i": index,
			"n": count,
			"p": text.substr(index * MAX_MESSAGE_CHARS, MAX_MESSAGE_CHARS),
		})


func get_default_address() -> String:
	if OS.has_feature("web"):
		return WEB_DEFAULT_ADDRESS
	return DEFAULT_ADDRESS


func get_status() -> String:
	return _last_status


func is_in_room() -> bool:
	return not room_id.empty()


func is_host() -> bool:
	return peer_tag == "H"


func _connect_for_action(
		address: String,
		username: String,
		action: Dictionary,
		status: String) -> bool:
	var cleaned := username.strip_edges()
	if cleaned.empty():
		_set_status("Digite seu username antes de continuar.")
		return false
	LocalRelay.ensure_for_address(address)
	_close_socket()
	_reset_match()
	last_address = address
	player_username = cleaned
	_pending_action = action
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
		_pending_action = {}
		_set_status("Nao foi possivel conectar ao relay em " + url)
		return false
	_set_status(status + " " + url)
	return true


func _normalize_url(address: String) -> String:
	return _normalize_url_for_platform(address, OS.has_feature("web"))


func _normalize_url_for_platform(address: String, web: bool) -> String:
	var trimmed := address.strip_edges()
	if trimmed.empty():
		trimmed = WEB_DEFAULT_ADDRESS if web else DEFAULT_ADDRESS
	if trimmed.begins_with("ws://") or trimmed.begins_with("wss://"):
		return trimmed
	# A pagina HTTPS nao pode abrir ws://, exceto no relay local de
	# desenvolvimento (localhost e considerada origem segura pelo navegador).
	var use_tls := web and not _is_loopback_address(trimmed)
	var host_part := trimmed
	var path := ""
	var slash := trimmed.find("/")
	if slash >= 0:
		host_part = trimmed.substr(0, slash)
		path = trimmed.substr(slash)
	var url := ("wss://" if use_tls else "ws://") + host_part
	if not _has_explicit_port(host_part) and not use_tls:
		url += ":" + str(DEFAULT_PORT)
	return url + path


func _is_loopback_address(address: String) -> bool:
	var host := address
	var slash := host.find("/")
	if slash >= 0:
		host = host.substr(0, slash)
	if host.begins_with("["):
		var close := host.find("]")
		if close > 0:
			host = host.substr(1, close - 1)
	else:
		var colon := host.rfind(":")
		if colon >= 0:
			host = host.substr(0, colon)
	host = host.strip_edges().to_lower()
	return host == "localhost" or host == "127.0.0.1" or host == "::1"


func _has_explicit_port(address: String) -> bool:
	var host := address
	var slash := host.find("/")
	if slash >= 0:
		host = host.substr(0, slash)
	if host.begins_with("["):
		var close := host.find("]")
		return close >= 0 and host.length() > close + 1 \
				and host.substr(close + 1, 1) == ":"
	return ":" in host


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


func _close_socket() -> void:
	if _client:
		_client.disconnect_from_host()
		_client = null


func _reset_match() -> void:
	peer_tag = ""
	opponent_username = ""
	room_id = ""
	match_mode = ""
	game_id = ""
	match_participants = []
	reconnectable = false
	reconnect_grace_seconds = 0
	_pending_action = {}
	_incoming_chunks = {}


func _on_client_connected(_protocol: String) -> void:
	if not _pending_action.empty():
		_send_packet(_pending_action)
		_pending_action = {}


func _on_client_closed(_was_clean: bool) -> void:
	var was_connected := is_connected
	var was_in_room := not room_id.empty()
	is_connected = false
	is_searching = false
	_set_status("Conexao com o relay encerrada.")
	if was_connected:
		emit_signal("peer_disconnected")
	if was_in_room:
		reconnectable = true
		emit_signal("connection_lost")


func _on_client_error() -> void:
	var was_connected := is_connected
	var was_in_room := not room_id.empty()
	is_connected = false
	is_searching = false
	_set_status("Erro ao conectar ao relay. Confira o endereco e se ele esta ativo.")
	if was_connected:
		emit_signal("peer_disconnected")
	if was_in_room:
		reconnectable = true
		emit_signal("connection_lost")


func _on_client_data() -> void:
	if _client and _client.get_peer(1):
		_handle_packet(_client.get_peer(1).get_packet())


func _handle_packet(packet: PoolByteArray) -> void:
	var parsed := JSON.parse(packet.get_string_from_utf8())
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed.result
	if str(data.get("t", "")) == "mp_chunk":
		_handle_chunk(data)
		return
	match str(data.get("t", "")):
		"waiting":
			is_searching = true
			if data.has("room_id"):
				room_id = str(data["room_id"])
				# Only the room creator receives a room_id while waiting.
				if peer_tag.empty():
					peer_tag = "H"
			if data.has("mode"):
				match_mode = str(data["mode"])
			if data.has("game_id"):
				game_id = str(data["game_id"])
			_set_status(str(data.get(
					"msg", "Procurando partida na rede local...")))
		"match_found":
			_apply_match_found(data)
		"opponent_disconnected":
			is_connected = false
			reconnectable = bool(data.get("reconnectable", false))
			reconnect_grace_seconds = int(data.get("grace_seconds", 0))
			if data.has("room_id"):
				room_id = str(data["room_id"])
			_set_status("O oponente saiu da partida.")
			emit_signal("peer_disconnected")
			emit_signal(
					"opponent_lost",
					reconnectable,
					reconnect_grace_seconds,
					room_id)
		"opponent_reconnected":
			is_connected = true
			reconnectable = false
			opponent_username = str(data.get("username", "Oponente"))
			_set_status("O oponente voltou a partida.")
			emit_signal("peer_connected")
			emit_signal(
					"opponent_reconnected",
					opponent_username,
					str(data.get("role", "")))
		"rejoin_ok":
			_apply_rejoin(data)
		"rejoin_failed":
			is_searching = false
			_set_status(str(data.get("msg", "Nao foi possivel reconectar.")))
			emit_signal("join_failed", _last_status)
		"opponent_left":
			is_connected = false
			reconnectable = false
			opponent_username = ""
			_set_status("O oponente encerrou a partida.")
			emit_signal("peer_disconnected")
			emit_signal("opponent_left")
		"room_expired":
			is_connected = false
			reconnectable = false
			_set_status(str(data.get(
					"msg", "A sala expirou. Use Iniciar jogo salvo.")))
			emit_signal("room_expired", _last_status)
		"search_cancelled":
			is_searching = false
			_set_status("Busca cancelada.")
			emit_signal("search_cancelled")
		"error":
			is_searching = false
			if not is_connected:
				_close_socket()
				_reset_match()
			_set_status(str(data.get("msg", "Erro no servico de partidas.")))
			emit_signal("join_failed", _last_status)
		_:
			if is_connected:
				emit_signal("message_received", data)


func _handle_chunk(data: Dictionary) -> void:
	var chunk_id := str(data.get("id", ""))
	var index := int(data.get("i", -1))
	var count := int(data.get("n", 0))
	var part := str(data.get("p", ""))
	if chunk_id.empty() or index < 0 or count <= 0 or count > 64 \
			or index >= count:
		return
	if not _incoming_chunks.has(chunk_id):
		if _incoming_chunks.size() >= 8:
			_incoming_chunks.clear()
		_incoming_chunks[chunk_id] = {
			"count": count,
			"parts": {},
			"received": 0,
		}
	var entry: Dictionary = _incoming_chunks[chunk_id]
	if int(entry["count"]) != count:
		_incoming_chunks.erase(chunk_id)
		return
	if not entry["parts"].has(index):
		entry["parts"][index] = part
		entry["received"] = int(entry["received"]) + 1
	if int(entry["received"]) < count:
		return
	var text := ""
	for part_index in range(count):
		text += str(entry["parts"].get(part_index, ""))
	_incoming_chunks.erase(chunk_id)
	var parsed := JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return
	if is_connected:
		emit_signal("message_received", parsed.result)


func _apply_match_found(data: Dictionary) -> void:
	if not is_searching:
		# A match_found that arrives after the search was cancelled must not
		# start a session the player already abandoned.
		return
	is_searching = false
	is_connected = true
	reconnectable = false
	peer_tag = str(data.get("role", ""))
	opponent_username = str(data.get("opponent", "Oponente"))
	room_id = str(data.get("room_id", ""))
	match_mode = str(data.get("mode", "match"))
	game_id = str(data.get("game_id", ""))
	match_participants = data.get("participants", [])
	if typeof(match_participants) != TYPE_ARRAY:
		match_participants = []
	_set_status("Partida encontrada contra " + opponent_username + ".")
	emit_signal("match_found", opponent_username)
	emit_signal("peer_connected")


func _apply_rejoin(data: Dictionary) -> void:
	is_searching = false
	is_connected = true
	reconnectable = false
	peer_tag = str(data.get("role", ""))
	opponent_username = str(data.get("opponent", "Oponente"))
	room_id = str(data.get("room_id", room_id))
	match_mode = str(data.get("mode", match_mode))
	game_id = str(data.get("game_id", game_id))
	var participants = data.get("participants", [])
	if typeof(participants) == TYPE_ARRAY:
		match_participants = participants
	_set_status("Reconectado a partida contra " + opponent_username + ".")
	emit_signal("peer_connected")
	emit_signal("rejoined", peer_tag, opponent_username)


func _set_status(text: String) -> void:
	_last_status = text
	emit_signal("status_changed", text)
