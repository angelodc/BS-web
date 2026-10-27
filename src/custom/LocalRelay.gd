extends Node

# Embedded LAN relay used when the configured address points to this machine.
# A remote relay (for example tools/ws_relay.py) keeps working unchanged.

const DEFAULT_PORT := 9080
const ROOM_GRACE_SECONDS := 120.0
const REAPER_INTERVAL_SECONDS := 5.0
const CONTROL_MESSAGES := {
	"find_match": true,
	"create_room": true,
	"cancel_match": true,
	"rejoin_room": true,
	"create_resume_room": true,
	"join_resume_room": true,
	"leave_room": true,
}

var _server: WebSocketServer
var _listening := false
var _port := 0
var _clients := {}
var _waiting := []
var _open_rooms := []
var _rooms := {}
var _resume_waiting := {}
var _reaper_elapsed := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_process(false)
	_rng.randomize()


func _exit_tree() -> void:
	if _server:
		_server.stop()
		_server = null
	_listening = false


func _process(delta: float) -> void:
	if not _server:
		return
	_server.poll()
	_reaper_elapsed += delta
	if _reaper_elapsed >= REAPER_INTERVAL_SECONDS:
		_reaper_elapsed = 0.0
		_expire_vacant_rooms()


func ensure_for_address(address: String) -> void:
	var parsed := _parse_local_address(address)
	if parsed.empty():
		return
	var port := int(parsed["port"])
	if _listening:
		if _port == port:
			return
		if _clients.empty() and _rooms.empty():
			_server.stop()
			_server = null
			_listening = false
		else:
			return
	_start(port)


func _parse_local_address(address: String) -> Dictionary:
	var trimmed := address.strip_edges()
	if trimmed.empty():
		trimmed = "ws://127.0.0.1:" + str(DEFAULT_PORT)
	if trimmed.begins_with("wss://"):
		return {}
	if trimmed.begins_with("ws://"):
		trimmed = trimmed.substr(5)
	var slash := trimmed.find("/")
	if slash >= 0:
		trimmed = trimmed.substr(0, slash)
	var host := ""
	var port := DEFAULT_PORT
	if trimmed.begins_with("["):
		var close := trimmed.find("]")
		if close <= 1:
			return {}
		host = trimmed.substr(1, close - 1)
		if trimmed.length() > close + 1 \
				and trimmed.substr(close + 1, 1) == ":":
			var port_text := trimmed.substr(close + 2)
			if port_text.is_valid_integer():
				port = int(port_text)
	else:
		var colon := trimmed.rfind(":")
		if colon >= 0:
			host = trimmed.substr(0, colon)
			var port_text := trimmed.substr(colon + 1)
			if port_text.is_valid_integer():
				port = int(port_text)
		else:
			host = trimmed
	if port <= 0 or port > 65535:
		port = DEFAULT_PORT
	if not _is_local_host(host):
		return {}
	return {"host": host, "port": port}


func _is_local_host(host: String) -> bool:
	var cleaned := host.strip_edges().to_lower()
	if cleaned.empty():
		return false
	if cleaned == "localhost" or cleaned == "127.0.0.1" \
			or cleaned == "0.0.0.0" or cleaned == "::1":
		return true
	var local_addresses := IP.get_local_addresses()
	for local_address in local_addresses:
		if str(local_address).to_lower() == cleaned:
			return true
	var computer_name := OS.get_environment("COMPUTERNAME").to_lower()
	if not computer_name.empty() and cleaned == computer_name:
		return true
	var resolved := IP.resolve_hostname(host, IP.TYPE_INET)
	if resolved.empty():
		return false
	if resolved == "127.0.0.1":
		return true
	for local_address in local_addresses:
		if str(local_address) == resolved:
			return true
	return false


func _start(port: int) -> void:
	_server = WebSocketServer.new()
	_server.connect("client_connected", self, "_on_client_connected")
	_server.connect("client_disconnected", self, "_on_client_disconnected")
	_server.connect("data_received", self, "_on_data_received")
	_server.set_bind_ip("0.0.0.0")
	var error := _server.listen(port, PoolStringArray(), false)
	if error != OK:
		_server = null
		# A second local game is expected to reuse the relay already listening.
		print("Relay embutido: porta ", port,
				" indisponivel; usando o relay existente.")
		return
	_listening = true
	_port = port
	set_process(true)
	print("Relay embutido ouvindo em ws://0.0.0.0:", port)


#-----------------------------------------------------------------------------
# WebSocket server
#-----------------------------------------------------------------------------

func _on_client_connected(id: int, _protocol: String) -> void:
	_clients[id] = _new_client_state()


func _on_client_disconnected(id: int, _was_clean: bool) -> void:
	_disconnect_client(id)


func _on_data_received(id: int) -> void:
	if not _server or not _server.has_peer(id):
		return
	var peer: WebSocketPeer = _server.get_peer(id)
	while peer.get_available_packet_count() > 0:
		var packet := peer.get_packet()
		var parsed := JSON.parse(packet.get_string_from_utf8())
		if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = parsed.result
		_route(id, data)


func _send(id: int, data: Dictionary) -> void:
	if id == 0 or not _server or not _server.has_peer(id):
		return
	var peer: WebSocketPeer = _server.get_peer(id)
	if not peer:
		return
	peer.set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	if peer.put_packet(JSON.print(data).to_utf8()) != OK:
		_disconnect_client(id)


func _send_error(id: int, message: String) -> void:
	_send(id, {"t": "error", "msg": message})


func _send_waiting(
		id: int,
		message: String,
		room_id := "",
		mode := "",
		game_id := "") -> void:
	var payload := {"t": "waiting", "msg": message}
	if not room_id.empty():
		payload["room_id"] = room_id
	if not mode.empty():
		payload["mode"] = mode
	if not game_id.empty():
		payload["game_id"] = game_id
	_send(id, payload)


func _send_match_found(
		id: int,
		role: String,
		opponent_username: String,
		room: Dictionary) -> void:
	var payload := {
		"t": "match_found",
		"role": role,
		"opponent": opponent_username,
	}
	var summary := _room_summary(room)
	for key in summary:
		payload[key] = summary[key]
	_send(id, payload)


#-----------------------------------------------------------------------------
# Client state and routing
#-----------------------------------------------------------------------------

func _new_client_state() -> Dictionary:
	return {
		"username": "",
		"room": "",
		"role": "",
		"opponent": 0,
		"queued": false,
		"mode": "",
		"game_id": "",
		"participants": [],
		"is_host": false,
	}


func _clear_client_state(state: Dictionary) -> void:
	state["room"] = ""
	state["role"] = ""
	state["opponent"] = 0
	state["queued"] = false
	state["mode"] = ""
	state["game_id"] = ""
	state["participants"] = []
	state["is_host"] = false


func _route(id: int, data: Dictionary) -> void:
	var kind := str(data.get("t", ""))
	match kind:
		"create_room":
			_create_room(id, data.get("username", ""))
		"find_match":
			_request_match(id, data.get("username", ""))
		"cancel_match":
			_cancel_match(id)
		"rejoin_room":
			_rejoin_room(id, data.get("room_id", ""), data.get("username", ""))
		"create_resume_room":
			_create_resume_room(
					id,
					data.get("game_id", ""),
					data.get("username", ""),
					data.get("participants", []))
		"join_resume_room":
			_join_resume_room(
					id,
					data.get("game_id", ""),
					data.get("username", ""),
					data.get("participants", []))
		"leave_room":
			_leave_room(id)
		_:
			if CONTROL_MESSAGES.has(kind):
				return
			_forward(id, data)


func _forward(id: int, data: Dictionary) -> void:
	var state = _clients.get(id)
	if not state or str(state["room"]).empty():
		return
	var opponent := int(state["opponent"])
	var opponent_state = _clients.get(opponent)
	if opponent == 0 or not opponent_state \
			or str(opponent_state["room"]) != str(state["room"]):
		return
	var forwarded := data.duplicate(true)
	forwarded["from"] = state["role"]
	forwarded["username"] = state["username"]
	forwarded["room_id"] = state["room"]
	_send(opponent, forwarded)


#-----------------------------------------------------------------------------
# Matchmaking
#-----------------------------------------------------------------------------

func _create_room(id: int, raw_username) -> void:
	var username := _clean_username(raw_username)
	if username.empty():
		_send_error(id, "Informe um username valido.")
		return
	var state = _clients.get(id)
	if not state:
		return
	if not str(state["room"]).empty():
		_send_error(id, "Voce ja esta em uma partida.")
		return
	if bool(state["queued"]):
		_send_error(id, "Voce ja esta procurando uma partida.")
		return
	var room_id := _random_hex(32)
	var game_id := "m_" + _random_hex(16)
	var room := {
		"id": room_id,
		"mode": "match",
		"game_id": game_id,
		"participants": [],
		"slots": {"H": id, "C": 0},
		"usernames": {"H": username, "C": ""},
		"vacant_since": {"H": null, "C": null},
		"active": false,
		"created_at": _now(),
	}
	state["username"] = username
	state["room"] = room_id
	state["role"] = "H"
	state["opponent"] = 0
	state["queued"] = true
	state["mode"] = "match"
	state["is_host"] = true
	_rooms[room_id] = room
	_open_rooms.append(room_id)
	var guest := 0
	while not _waiting.empty():
		var candidate := int(_waiting.pop_front())
		var candidate_state = _clients.get(candidate)
		if candidate_state and bool(candidate_state["queued"]) \
				and str(candidate_state["room"]).empty():
			guest = candidate
			break
	if guest != 0:
		if _pair_room(room, guest):
			return
		var guest_state = _clients.get(guest)
		if guest_state:
			guest_state["queued"] = false
			guest_state["is_host"] = false
		_send_error(
				guest,
				"Use um username diferente do anfitriao para entrar.")
	_send_waiting(
			id,
			"Sala criada. Aguardando o outro jogador...",
			room_id,
			"match",
			game_id)


func _request_match(id: int, raw_username) -> void:
	var username := _clean_username(raw_username)
	if username.empty():
		_send_error(id, "Informe um username valido.")
		return
	var state = _clients.get(id)
	if not state:
		return
	if not str(state["room"]).empty():
		_send_error(id, "Voce ja esta em uma partida.")
		return
	if bool(state["queued"]):
		return
	state["username"] = username
	state["queued"] = true
	state["is_host"] = false
	var room = _find_open_room_for_guest()
	if room:
		if _pair_room(room, id):
			return
		state["queued"] = false
		_send_error(
				id,
				"Use um username diferente do anfitriao para entrar.")
		return
	if not id in _waiting:
		_waiting.append(id)
	_send_waiting(id, "Procurando partida na rede local...", "", "match", "")


func _find_open_room_for_guest():
	for room_id in _open_rooms.duplicate():
		var room = _rooms.get(room_id)
		if not room:
			_open_rooms.erase(room_id)
			continue
		if str(room["mode"]) == "match" \
				and int(room["slots"]["H"]) != 0 \
				and int(room["slots"]["C"]) == 0:
			return room
	return null


func _pair_room(room: Dictionary, guest: int) -> bool:
	var host := int(room["slots"]["H"])
	if host == 0 or int(room["slots"]["C"]) != 0:
		return false
	var host_state = _clients.get(host)
	var guest_state = _clients.get(guest)
	if not host_state or not guest_state:
		return false
	var host_name := str(host_state["username"])
	var guest_name := str(guest_state["username"])
	if host_name.empty() or guest_name.empty():
		return false
	if host_name.to_lower() == guest_name.to_lower():
		return false
	room["slots"]["C"] = guest
	room["usernames"]["C"] = guest_name
	room["vacant_since"]["C"] = null
	room["active"] = true
	_open_rooms.erase(room["id"])
	_apply_room_state(host_state, room, "H", guest)
	_apply_room_state(guest_state, room, "C", host)
	if str(room["mode"]) == "resume":
		_resume_waiting.erase(room["game_id"])
		_waiting.erase(guest)
	_send_match_found(host, "H", guest_name, room)
	_send_match_found(guest, "C", host_name, room)
	return true


func _apply_room_state(
		state: Dictionary,
		room: Dictionary,
		role: String,
		opponent: int) -> void:
	state["room"] = room["id"]
	state["role"] = role
	state["opponent"] = opponent
	state["queued"] = false
	state["mode"] = room["mode"]
	state["game_id"] = room["game_id"]
	state["participants"] = room["participants"].duplicate()
	state["is_host"] = role == "H"


func _room_summary(room: Dictionary) -> Dictionary:
	return {
		"room_id": room["id"],
		"mode": room["mode"],
		"game_id": room["game_id"],
		"participants": room["participants"].duplicate(),
	}


func _cancel_match(id: int) -> void:
	var state = _clients.get(id)
	if not state or not bool(state["queued"]):
		return
	var room_id := str(state["room"])
	var room = _rooms.get(room_id) if not room_id.empty() else null
	if room and not bool(room["active"]):
		_rooms.erase(room_id)
		_open_rooms.erase(room_id)
	_waiting.erase(id)
	for game_id in _resume_waiting.keys():
		if int(_resume_waiting[game_id]) == id:
			_resume_waiting.erase(game_id)
	_clear_client_state(state)
	_send(id, {"t": "search_cancelled"})


func _leave_room(id: int) -> void:
	var state = _clients.get(id)
	if not state or str(state["room"]).empty():
		return
	var room_id := str(state["room"])
	var opponent := int(state["opponent"])
	var room = _rooms.get(room_id)
	_rooms.erase(room_id)
	_open_rooms.erase(room_id)
	if room:
		_resume_waiting.erase(room["game_id"])
	_clear_client_state(state)
	if opponent != 0:
		var opponent_state = _clients.get(opponent)
		if opponent_state:
			_clear_client_state(opponent_state)
		_send(opponent, {"t": "opponent_left", "room_id": room_id})


func _disconnect_client(id: int) -> void:
	var state = _clients.get(id)
	if not state:
		return
	_clients.erase(id)
	_waiting.erase(id)
	for game_id in _resume_waiting.keys():
		if int(_resume_waiting[game_id]) == id:
			_resume_waiting.erase(game_id)
	var room_id := str(state["room"])
	if room_id.empty():
		return
	var room = _rooms.get(room_id)
	if not room:
		return
	var role := str(state["role"])
	if not bool(room["active"]):
		_rooms.erase(room_id)
		_open_rooms.erase(room_id)
		_resume_waiting.erase(room["game_id"])
		return
	if int(room["slots"].get(role, 0)) == id:
		room["slots"][role] = 0
		room["vacant_since"][role] = _now()
	var opponent := int(state["opponent"])
	var opponent_state = _clients.get(opponent)
	if opponent != 0 and opponent_state:
		opponent_state["opponent"] = 0
		opponent_state["queued"] = false
		_send(opponent, {
			"t": "opponent_disconnected",
			"room_id": room_id,
			"role": role,
			"username": state["username"],
			"mode": room["mode"],
			"game_id": room["game_id"],
			"reconnectable": true,
			"grace_seconds": int(ROOM_GRACE_SECONDS),
		})


func _rejoin_room(id: int, raw_room_id, raw_username) -> void:
	var room_id := str(raw_room_id)
	var username := _clean_username(raw_username)
	if room_id.empty() or username.empty():
		_send_error(id, "Nao foi possivel reconectar: dados da sala ausentes.")
		return
	var state = _clients.get(id)
	if not state:
		return
	if not str(state["room"]).empty():
		_send_error(id, "Voce ja esta em uma partida.")
		return
	var room = _rooms.get(room_id)
	if not room:
		_send(id, {
			"t": "rejoin_failed",
			"msg": "A sala nao existe mais. Use Iniciar jogo salvo.",
		})
		return
	var role := ""
	for candidate in ["H", "C"]:
		var expected := str(room["usernames"].get(candidate, ""))
		if not expected.empty() \
				and expected.to_lower() == username.to_lower() \
				and int(room["slots"].get(candidate, 0)) == 0:
			role = candidate
			break
	if role.empty():
		_send(id, {
			"t": "rejoin_failed",
			"msg": "Nao ha vaga para este username nesta sala.",
		})
		return
	room["slots"][role] = id
	room["usernames"][role] = username
	room["vacant_since"][role] = null
	state["username"] = username
	state["room"] = room_id
	state["role"] = role
	state["queued"] = false
	state["mode"] = room["mode"]
	state["game_id"] = room["game_id"]
	state["participants"] = room["participants"].duplicate()
	state["is_host"] = role == "H"
	var opponent_role := "C" if role == "H" else "H"
	var opponent := int(room["slots"].get(opponent_role, 0))
	state["opponent"] = opponent
	var opponent_state = _clients.get(opponent)
	if opponent_state:
		opponent_state["opponent"] = id
	var payload := {
		"t": "rejoin_ok",
		"room_id": room_id,
		"role": role,
		"opponent": "",
		"mode": room["mode"],
		"game_id": room["game_id"],
		"participants": room["participants"].duplicate(),
	}
	if opponent_state:
		payload["opponent"] = opponent_state["username"]
	_send(id, payload)
	if opponent_state:
		_send(opponent, {
			"t": "opponent_reconnected",
			"room_id": room_id,
			"role": role,
			"username": username,
		})


#-----------------------------------------------------------------------------
# Resume rooms
#-----------------------------------------------------------------------------

func _create_resume_room(
		id: int,
		raw_game_id,
		raw_username,
		raw_participants) -> void:
	var game_id := _clean_game_id(raw_game_id)
	var username := _clean_username(raw_username)
	var participants := _clean_participants(raw_participants)
	if game_id.empty():
		_send_error(id, "O jogo salvo nao tem um identificador valido.")
		return
	if username.empty():
		_send_error(id, "Informe um username valido.")
		return
	if participants.size() != 2:
		_send_error(id, "O jogo salvo nao identifica os dois participantes.")
		return
	if not username in participants:
		_send_error(id, "Seu username nao participou desta partida salva.")
		return
	var state = _clients.get(id)
	if not state:
		return
	if not str(state["room"]).empty():
		_send_error(id, "Voce ja esta em uma partida.")
		return
	var room_id := "resume_" + game_id
	if _rooms.has(room_id):
		_send_error(id, "Ja existe uma sala de retomada para este jogo.")
		return
	var room := {
		"id": room_id,
		"mode": "resume",
		"game_id": game_id,
		"participants": participants,
		"slots": {"H": id, "C": 0},
		"usernames": {"H": username, "C": ""},
		"vacant_since": {"H": null, "C": null},
		"active": false,
		"created_at": _now(),
	}
	state["username"] = username
	state["room"] = room_id
	state["role"] = "H"
	state["opponent"] = 0
	state["queued"] = true
	state["mode"] = "resume"
	state["game_id"] = game_id
	state["participants"] = participants.duplicate()
	state["is_host"] = true
	_rooms[room_id] = room
	var waiting_guest := int(_resume_waiting.get(game_id, 0))
	if waiting_guest != 0:
		var guest_state = _clients.get(waiting_guest)
		if guest_state and bool(guest_state["queued"]) \
				and str(guest_state["room"]).empty():
			if not str(guest_state["username"]) in participants:
				guest_state["queued"] = false
				_resume_waiting.erase(game_id)
				_waiting.erase(waiting_guest)
				_send_error(
						waiting_guest,
						"Seu username nao participou desta partida salva.")
			else:
				_pair_room(room, waiting_guest)
				return
	_send_waiting(
			id,
			"Sala de retomada criada. Aguardando o outro jogador...",
			room_id,
			"resume",
			game_id)


func _join_resume_room(
		id: int,
		raw_game_id,
		raw_username,
		raw_participants) -> void:
	var game_id := _clean_game_id(raw_game_id)
	var username := _clean_username(raw_username)
	var participants := _clean_participants(raw_participants)
	if game_id.empty():
		_send_error(id, "Informe o identificador da partida salva.")
		return
	if username.empty():
		_send_error(id, "Informe um username valido.")
		return
	var state = _clients.get(id)
	if not state:
		return
	if not str(state["room"]).empty():
		_send_error(id, "Voce ja esta em uma partida.")
		return
	if bool(state["queued"]):
		return
	state["username"] = username
	state["queued"] = true
	state["is_host"] = false
	state["mode"] = "resume"
	state["game_id"] = game_id
	state["participants"] = participants.duplicate()
	var room = _rooms.get("resume_" + game_id)
	if room and int(room["slots"]["H"]) != 0 \
			and int(room["slots"]["C"]) == 0:
		if not participants.empty() \
				and not _same_participants(participants, room["participants"]):
			state["queued"] = false
			_send_error(
					id,
					"Os participantes deste save nao conferem com a sala.")
			return
		if not username in room["participants"]:
			state["queued"] = false
			_send_error(id, "Seu username nao participou desta partida salva.")
			return
		_pair_room(room, id)
		return
	if _resume_waiting.has(game_id):
		state["queued"] = false
		_send_error(id, "Ja existe um jogador esperando por esta partida.")
		return
	_resume_waiting[game_id] = id
	if not id in _waiting:
		_waiting.append(id)
	_send_waiting(
			id,
			"Procurando a sala de retomada...",
			"",
			"resume",
			game_id)


func _expire_vacant_rooms() -> void:
	var now := _now()
	for room_id in _rooms.keys():
		var room = _rooms[room_id]
		if not bool(room["active"]):
			continue
		if int(room["slots"]["H"]) != 0 or int(room["slots"]["C"]) != 0:
			continue
		var host_vacancy = room["vacant_since"]["H"]
		var guest_vacancy = room["vacant_since"]["C"]
		if host_vacancy == null or guest_vacancy == null:
			continue
		if now - max(float(host_vacancy), float(guest_vacancy)) \
				<= ROOM_GRACE_SECONDS:
			continue
		_rooms.erase(room_id)
		_open_rooms.erase(room_id)
		var game_id := str(room["game_id"])
		if not game_id.empty():
			_resume_waiting.erase(game_id)


#-----------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------

func _clean_username(value) -> String:
	return str(value).strip_edges().substr(0, 24)


func _clean_game_id(value) -> String:
	var text := str(value).strip_edges()
	var cleaned := ""
	for index in range(text.length()):
		var character := text.substr(index, 1)
		if (character >= "a" and character <= "z") \
				or (character >= "A" and character <= "Z") \
				or (character >= "0" and character <= "9") \
				or character == "-" or character == "_":
			cleaned += character
	return cleaned.substr(0, 64)


func _clean_participants(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	var cleaned := []
	for participant in value:
		var name := _clean_username(participant)
		if not name.empty() and not name in cleaned:
			cleaned.append(name)
	return cleaned


func _same_participants(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for name in first:
		if not name in second:
			return false
	return true


func _random_hex(length: int) -> String:
	var digits := "0123456789abcdef"
	var result := ""
	for _index in range(length):
		var position := int(_rng.randf() * 16.0)
		result += digits.substr(position, 1)
	return result


func _now() -> float:
	return float(OS.get_ticks_msec()) / 1000.0
