extends Panel

const PlaymatCatalog = preload("res://src/custom/PlaymatCatalog.gd")
const RedeScript = preload("res://src/custom/Rede.gd")

onready var v_buttons := $MainMenu/VBox/Center/VButtons
onready var main_menu := $MainMenu
onready var backdrop := $MainMenu/Backdrop
onready var checkpoint_list := $CheckpointList
onready var action_error := $ActionError
onready var player_name_input := $MainMenu/VBox/Center/VButtons/PlayerName
onready var relay_address_input := $MainMenu/VBox/Center/VButtons/RelayAddress
onready var room_code_input := $MainMenu/VBox/Center/VButtons/JoinRow/RoomCode
onready var join_room_button := $MainMenu/VBox/Center/VButtons/JoinRow/JoinRoom
onready var match_status := $MainMenu/VBox/Center/VButtons/MatchStatus
onready var server_status := $MainMenu/VBox/Center/VButtons/ServerStatus
onready var server_probe := $ServerProbe
onready var multiplayer_button := $MainMenu/VBox/Center/VButtons/Multiplayer
onready var solo_match_button := $MainMenu/VBox/Center/VButtons/SoloMatch
onready var create_match_button := $MainMenu/VBox/Center/VButtons/CreateMatch
onready var resume_button := $MainMenu/VBox/Center/VButtons/ResumeGame

# O relay pode voltar (o tunel se re-registra sozinho) ou cair com o menu
# aberto, entao o estado e reconsultado. 20 s e bem mais lento que qualquer
# acao do jogador e nao martela o servico com uma aba de lobby deixada aberta.
const SERVER_PROBE_SECONDS := 20.0
# Depois de digitar, uma pausa curta antes de sondar: cada tecla remarca a
# espera, entao a requisicao sai quando o endereco esta completo.
const SERVER_PROBE_AFTER_TYPING := 2.0

var _lobby_busy := false
var _entering_game := false
var _probe_elapsed := SERVER_PROBE_SECONDS
var _probe_pending := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
	join_room_button.connect(
			'pressed', self, 'on_button_pressed', ['JoinRoom'])
	checkpoint_list.connect("resume_requested", self, "_on_resume_requested")
	player_name_input.text = str(cfc.game_settings.get(
			"multiplayer_username", ""))
	_relay_setup()
	room_code_input.text = _read_web_query("room").to_upper()
	server_probe.connect("request_completed", self, "_on_server_probe_done")
	relay_address_input.connect(
			"text_changed", self, "_on_relay_address_changed")
	Rede.connect("status_changed", self, "_on_match_status_changed")
	Rede.connect("join_failed", self, "_on_join_failed")
	action_error.get_label().autowrap = true
	Multiplayer.connect("lobby_ready", self, "_on_lobby_ready")
	Multiplayer.connect("session_ended", self, "_on_session_ended")
	Multiplayer.connect("resume_status", self, "_on_resume_status")
	match_status.text = Rede.get_status()
	_apply_backdrop()
	_update_lobby_controls()
	_probe_server()
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')


# Só o que roda por frame aqui é a cadência da sondagem; enquanto uma resposta
# está na rua o contador fica parado, senão o menu empilha requisições.
func _process(delta: float) -> void:
	if _probe_pending:
		return
	_probe_elapsed += delta
	if _probe_elapsed < SERVER_PROBE_SECONDS:
		return
	_probe_elapsed = 0.0
	_probe_server()


# The menu shows the same artwork that the board uses as its default playmat.
# Loading it here instead of referencing it in the scene keeps working before
# the editor has imported the file, which is the state right after art arrives.
func _apply_backdrop() -> void:
	var texture := PlaymatCatalog.texture_for_path(PlaymatCatalog.BACKDROP_PATH)
	# A missing artwork leaves the plain dark panel instead of breaking the menu.
	if texture == null:
		return
	backdrop.texture = texture


func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"SoloMatch":
			if _lobby_busy:
				return
			var solo_identity := _prepare_identity()
			if not solo_identity.get("ok", false):
				return
			# begin_solo entra no jogo sozinho: o lobby_ready chega dentro dele.
			var solo_result := Multiplayer.begin_solo(
					solo_identity["username"])
			if not solo_result.get("ok", false):
				_show_action_error(str(solo_result.get("reason", "")))
		"CreateMatch":
			if _lobby_busy:
				return
			var host_identity := _prepare_identity()
			if not host_identity.get("ok", false):
				return
			var host_result := Multiplayer.begin_match(
					host_identity["address"], host_identity["username"], true)
			if not host_result.get("ok", false):
				_show_action_error(str(host_result.get("reason", "")))
				return
			_set_lobby_busy(true)
			match_status.text = Rede.get_status()
			_enter_game()
		"Multiplayer":
			if _lobby_busy:
				_cancel_lobby()
				return
			var guest_identity := _prepare_identity()
			if not guest_identity.get("ok", false):
				return
			var guest_result := Multiplayer.begin_match(
					guest_identity["address"], guest_identity["username"], false)
			if not guest_result.get("ok", false):
				_show_action_error(str(guest_result.get("reason", "")))
				return
			_set_lobby_busy(true)
			match_status.text = Rede.get_status()
		"JoinRoom":
			if _lobby_busy:
				return
			var code: String = room_code_input.text.strip_edges().to_upper()
			if code.empty():
				match_status.text = "Digite o codigo da sala."
				room_code_input.grab_focus()
				return
			var join_identity := _prepare_identity()
			if not join_identity.get("ok", false):
				return
			var join_result := Multiplayer.begin_join(
					join_identity["address"], join_identity["username"], code)
			if not join_result.get("ok", false):
				_show_action_error(str(join_result.get("reason", "")))
				return
			_set_lobby_busy(true)
			match_status.text = Rede.get_status()
		"ResumeGame":
			if _lobby_busy:
				return
			var resume_identity := _prepare_identity()
			if not resume_identity.get("ok", false):
				return
			checkpoint_list.open(resume_identity["username"])
		"Exit":
			Multiplayer.leave_session()
			get_tree().quit()


func _relay_setup() -> void:
	if OS.has_feature("web"):
		# No navegador o relay e o servico publico; o campo so existe para
		# permitir ?relay= em testes locais.
		relay_address_input.visible = false
		var web_relay := _read_web_query("relay")
		relay_address_input.text = web_relay if not web_relay.empty() \
				else Rede.get_default_address()
		return
	var saved := str(cfc.game_settings.get("multiplayer_relay_address", ""))
	relay_address_input.text = saved if not saved.empty() \
			else Rede.get_default_address()


func _read_web_query(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var value = JavaScript.eval(
			"new URLSearchParams(window.location.search).get('%s') || ''" % key,
			true)
	if value == null:
		return ""
	return str(value).strip_edges()


#-----------------------------------------------------------------------------
# Estado do servidor, para o jogador saber antes de tentar entrar
#-----------------------------------------------------------------------------

# Na web a sonda e no proprio site (mesma origem, entao sem CORS): /api/salas
# acabou de consultar o relay e devolve relay.online. No desktop o campo de
# endereco e a fonte, e o relay expoe /healthz na mesma porta em http.
func _probe_server() -> void:
	if _probe_pending:
		return
	# No desktop, 127.0.0.1 e o relay que o proprio jogo levanta na hora de
	# criar a sala (LocalRelay). Dizer "indisponivel" antes disso seria uma
	# mentira, entao o rotulo fica de fora enquanto o endereco e local.
	if _is_local_relay_address():
		server_status.visible = false
		return
	server_status.visible = true
	var url := _server_probe_url()
	if url.empty():
		_show_server_state(false, "Servidor: sem endereco para checar")
		return
	server_status.text = "Servidor: checando..."
	server_status.modulate = Color(1, 1, 1)
	_probe_pending = true
	if server_probe.request(url) != OK:
		_probe_pending = false
		_probe_elapsed = 0.0
		_show_server_state(false, "Servidor: indisponível")


func _is_local_relay_address() -> bool:
	return not OS.has_feature("web") \
			and Rede._is_loopback_address(relay_address_input.text)


func _server_probe_url() -> String:
	if OS.has_feature("web"):
		var origin := _web_origin()
		return origin + "/api/salas" if not origin.empty() else ""
	return _relay_health_url(relay_address_input.text)


func _web_origin() -> String:
	if not OS.has_feature("web"):
		return ""
	var value = JavaScript.eval("window.location.origin", true)
	if value == null:
		return ""
	return str(value).strip_edges().rstrip("/")


# Aceita o que o campo aceita: "host:porta", "host", "ws://..." e "wss://...".
func _relay_health_url(address: String) -> String:
	var trimmed := address.strip_edges()
	if trimmed.empty():
		return ""
	var target := trimmed
	var bare := not trimmed.begins_with("ws://") \
			and not trimmed.begins_with("wss://") \
			and not trimmed.begins_with("http://") \
			and not trimmed.begins_with("https://")
	if target.begins_with("ws://"):
		target = "http://" + target.substr(5)
	elif target.begins_with("wss://"):
		target = "https://" + target.substr(6)
	elif bare:
		target = "http://" + target
	var host := target.substr(target.find("://") + 3)
	var slash := host.find("/")
	if slash >= 0:
		host = host.substr(0, slash)
	# "192.168.1.85" sem porta significa o relay padrao da rede local; quem
	# escreveu o esquema escolhe a porta, nao inventamos por cima.
	if bare and host.find(":") == -1:
		target += ":" + str(RedeScript.DEFAULT_PORT)
	return target.rstrip("/") + "/healthz"


func _on_server_probe_done(
		result: int,
		response_code: int,
		_headers: PoolStringArray,
		body: PoolByteArray) -> void:
	_probe_pending = false
	_probe_elapsed = 0.0
	if result != HTTPRequest.RESULT_SUCCESS:
		_show_server_state(false, "Servidor: indisponível")
		return
	var parsed := JSON.parse(body.get_string_from_utf8())
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		_show_server_state(false, "Servidor: resposta inesperada")
		return
	var data: Dictionary = parsed.result
	if OS.has_feature("web"):
		var relay: Dictionary = data.get("relay", {})
		var online := bool(relay.get("online", false))
		var rooms: Array = data.get("rooms", [])
		_show_server_state(online, _server_state_text(online, rooms.size()))
		return
	var healthy := response_code == 200 and str(data.get("status", "")) == "ok"
	_show_server_state(healthy,
			_server_state_text(healthy, int(data.get("rooms", 0))))


func _server_state_text(online: bool, room_count: int) -> String:
	if not online:
		return "Servidor: indisponível"
	if room_count <= 0:
		return "Servidor: online"
	return "Servidor: online (%d sala%s)" % [
		room_count, "s" if room_count > 1 else ""]


# A cor faz a leitura de relance; o numero de salas so confirma que o servidor
# esta do lado certo do tunel.
func _show_server_state(online: bool, text: String) -> void:
	server_status.text = text
	server_status.modulate = Color(0.55, 0.9, 0.55) if online \
			else Color(0.95, 0.55, 0.5)


func _on_relay_address_changed(_new_text: String) -> void:
	# Cada tecla remarca a pausa, entao a sonda espera o endereco ficar pronto.
	_probe_elapsed = SERVER_PROBE_SECONDS - SERVER_PROBE_AFTER_TYPING
	if _is_local_relay_address():
		server_status.visible = false
		return
	server_status.visible = true
	server_status.text = "Servidor: checando..."
	server_status.modulate = Color(1, 1, 1)


func _prepare_identity() -> Dictionary:
	var username: String = player_name_input.text.strip_edges()
	if username.empty():
		match_status.text = "Digite um username antes de continuar."
		player_name_input.grab_focus()
		return {"ok": false}
	var renamed := Multiplayer.change_username(username)
	if not renamed.get("ok", false):
		_show_action_error(str(renamed.get("reason", "")))
		return {"ok": false}
	var address: String = relay_address_input.text.strip_edges()
	if address.empty():
		address = Rede.get_default_address()
		relay_address_input.text = address
	if not OS.has_feature("web"):
		cfc.set_setting("multiplayer_relay_address", address)
	return {"ok": true, "username": username, "address": address}


func _set_lobby_busy(busy: bool) -> void:
	_lobby_busy = busy
	player_name_input.editable = not busy
	relay_address_input.editable = not busy
	room_code_input.editable = not busy
	for button in [
			solo_match_button, create_match_button, join_room_button,
			resume_button]:
		button.disabled = busy
	_update_lobby_controls()


func _update_lobby_controls() -> void:
	multiplayer_button.text = "Cancelar" if _lobby_busy else "Procurar Partida"


func _cancel_lobby() -> void:
	Multiplayer.leave_session("Busca cancelada.")


func _enter_game() -> void:
	if _entering_game:
		return
	_entering_game = true
	cfc.current_deck = {}
	# warning-ignore:return_value_discarded
	get_tree().change_scene(CFConst.PATH_CUSTOM + "CGFMain.tscn")


func _on_match_status_changed(text: String) -> void:
	match_status.text = text
	if _lobby_busy and not Rede.is_searching and not Rede.is_connected:
		_set_lobby_busy(false)


func _on_join_failed(message: String) -> void:
	if not message.empty():
		_show_action_error(message)


func _show_action_error(message: String) -> void:
	match_status.text = message
	action_error.dialog_text = message
	action_error.popup_centered(Vector2(520, 170))


func _on_lobby_ready() -> void:
	_enter_game()


func _on_session_ended(message: String) -> void:
	match_status.text = message
	_set_lobby_busy(false)


func _on_resume_status(text: String) -> void:
	match_status.text = text
	if checkpoint_list.visible:
		checkpoint_list.set_status(text)


func _on_resume_requested(
		game_id: String, participants: Array, as_host: bool) -> void:
	var identity := _prepare_identity()
	if not identity.get("ok", false):
		checkpoint_list.set_status(match_status.text)
		return
	var result := Multiplayer.begin_resume(
			identity["address"], identity["username"], game_id,
			participants, as_host)
	if not result.get("ok", false):
		checkpoint_list.set_status(str(result.get("reason", "")))
		return
	checkpoint_list.hide()
	_set_lobby_busy(true)
	if as_host:
		match_status.text = "Sala de retomada criada. Aguardando o outro jogador..."
	else:
		match_status.text = "Entrando na sala de retomada do oponente..."


func _on_Menu_resized() -> void:
	main_menu.rect_size = get_viewport().get_visible_rect().size
