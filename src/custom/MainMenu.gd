extends Panel

const PlaymatCatalog = preload("res://src/custom/PlaymatCatalog.gd")
const RedeScript = preload("res://src/custom/Rede.gd")
const RenderResolution = preload("res://src/custom/RenderResolution.gd")
const FeedbackAdminScript = preload("res://src/custom/FeedbackAdmin.gd")

@onready var v_buttons := $MainMenu/VBox/Center/VButtons
@onready var title_label := $MainMenu/VBox/Margin/Label
@onready var main_menu := $MainMenu
@onready var backdrop := $MainMenu/Backdrop
@onready var checkpoint_list := $CheckpointList
@onready var action_error := $ActionError
@onready var player_name_input := $MainMenu/VBox/Center/VButtons/PlayerName
@onready var relay_address_input := $MainMenu/VBox/Center/VButtons/RelayAddress
@onready var room_code_input := $MainMenu/VBox/Center/VButtons/JoinRow/RoomCode
@onready var join_room_button := $MainMenu/VBox/Center/VButtons/JoinRow/JoinRoom
@onready var match_status := $MainMenu/VBox/Center/VButtons/MatchStatus
@onready var server_status := $MainMenu/VBox/Center/VButtons/ServerStatus
@onready var server_probe := $ServerProbe
@onready var version_probe := $VersionProbe
@onready var multiplayer_button := $MainMenu/VBox/Center/VButtons/Multiplayer
@onready var solo_match_button := $MainMenu/VBox/Center/VButtons/SoloMatch
@onready var create_match_button := $MainMenu/VBox/Center/VButtons/CreateMatch
@onready var resume_button := $MainMenu/VBox/Center/VButtons/ResumeGame

# O relay pode voltar (o tunel se re-registra sozinho) ou cair com o menu
# aberto, entao o estado e reconsultado. 20 s e bem mais lento que qualquer
# acao do jogador e nao martela o servico com uma aba de lobby deixada aberta.
const SERVER_PROBE_SECONDS := 20.0
# Depois de digitar, uma pausa curta antes de sondar: cada tecla remarca a
# espera, entao a requisicao sai quando o endereco esta completo.
const SERVER_PROBE_AFTER_TYPING := 2.0
const PWA_BUTTON_SIZE := Vector2(160, 34)
const PWA_BUTTON_MARGIN := 16.0
# O leitor de relatos é escondido: sete cliques no título, sem atalho visível.
const FEEDBACK_CLICKS := 7
const FEEDBACK_CLICK_GAP_MS := 1500

var _lobby_busy := false
var _entering_game := false
var _probe_elapsed := SERVER_PROBE_SECONDS
var _probe_pending := false
var _pwa_button: Button
var _title_clicks := 0
var _last_title_click := 0
var _feedback_admin: Window = null
var _version_label: Label

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.pressed.connect(on_button_pressed.bind(option_button.name))
	join_room_button.pressed.connect(on_button_pressed.bind('JoinRoom'))
	checkpoint_list.resume_requested.connect(_on_resume_requested)
	player_name_input.text = str(cfc.game_settings.get(
			"multiplayer_username", ""))
	_relay_setup()
	room_code_input.text = _read_web_query("room").to_upper()
	server_probe.request_completed.connect(_on_server_probe_done)
	version_probe.request_completed.connect(_on_version_probe_done)
	_setup_version_label()
	_probe_version()
	relay_address_input.text_changed.connect(_on_relay_address_changed)
	Rede.status_changed.connect(_on_match_status_changed)
	Rede.join_failed.connect(_on_join_failed)
	action_error.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Multiplayer.lobby_ready.connect(_on_lobby_ready)
	Multiplayer.session_ended.connect(_on_session_ended)
	Multiplayer.resume_status.connect(_on_resume_status)
	match_status.text = Rede.get_status()
	_apply_backdrop()
	_update_lobby_controls()
	_setup_pwa_entry()
	_setup_render_option()
	_setup_feedback_entry()
	_probe_server()
	# warning-ignore:return_value_discarded
	get_viewport().size_changed.connect(_on_Menu_resized)


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
			if code.is_empty():
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
		relay_address_input.text = web_relay if not web_relay.is_empty() \
				else Rede.get_default_address()
		return
	var saved := str(cfc.game_settings.get("multiplayer_relay_address", ""))
	relay_address_input.text = saved if not saved.is_empty() \
			else Rede.get_default_address()


func _read_web_query(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var value = JavaScriptBridge.eval(
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
	if url.is_empty():
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
		return origin + "/api/salas" if not origin.is_empty() else ""
	return _relay_health_url(relay_address_input.text)


func _web_origin() -> String:
	if not OS.has_feature("web"):
		return ""
	var value = JavaScriptBridge.eval("window.location.origin", true)
	if value == null:
		return ""
	return str(value).strip_edges().rstrip("/")


# Aceita o que o campo aceita: "host:porta", "host", "ws://..." e "wss://...".
func _relay_health_url(address: String) -> String:
	var trimmed := address.strip_edges()
	if trimmed.is_empty():
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
		_headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_probe_pending = false
	_probe_elapsed = 0.0
	if result != HTTPRequest.RESULT_SUCCESS:
		_show_server_state(false, "Servidor: indisponível")
		return
	var test_json_conv = JSON.new()
	var parse_error := test_json_conv.parse(body.get_string_from_utf8())
	var parsed = test_json_conv.get_data()
	if parse_error != OK or typeof(parsed) != TYPE_DICTIONARY:
		_show_server_state(false, "Servidor: resposta inesperada")
		return
	var data: Dictionary = parsed
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


# O rotulo e criado por codigo, como o botao PWA: o editor nao tem como move-lo
# para dentro de outro no ao salvar a cena.
func _setup_version_label() -> void:
	_version_label = Label.new()
	_version_label.name = "VersionLabel"
	_version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version_label.add_theme_font_size_override("font_size", 13)
	_version_label.add_theme_color_override(
			"font_color", Color(0.72, 0.74, 0.78, 0.85))
	_version_label.text = Version.display_text()
	add_child(_version_label)
	_place_version_label()
	get_viewport().size_changed.connect(_place_version_label)
	# Os containers so fecham o layout no primeiro frame; o titulo ainda tem
	# tamanho provisorio durante o _ready.
	await get_tree().process_frame
	_place_version_label()


func _place_version_label() -> void:
	if not is_instance_valid(_version_label):
		return
	var title := get_node_or_null("MainMenu/VBox/Margin/Label")
	if title == null:
		var area: Vector2 = get_viewport().get_visible_rect().size
		_version_label.position = Vector2(area.x - 240.0, area.y - 32.0)
		_version_label.size = Vector2(224.0, 22.0)
		return
	var rect: Rect2 = title.get_global_rect()
	_version_label.position = Vector2(rect.position.x, rect.end.y + 4.0)
	_version_label.size = Vector2(rect.size.x, 24.0)


# A versao semantica vem no PCK; o commit so existe no deploy do site, entao a
# sondagem roda apenas na web e uma falha deixa o rotulo so com "v0.1.0".
func _probe_version() -> void:
	if not OS.has_feature("web"):
		return
	var origin := _web_origin()
	if origin.is_empty():
		return
	# warning-ignore:return_value_discarded
	version_probe.request(origin + "/api/version")


func _on_version_probe_done(
		result: int,
		response_code: int,
		_headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	if typeof(json.data) != TYPE_DICTIONARY:
		return
	var data: Dictionary = json.data
	var commit := str(data.get("game", "")).strip_edges()
	if not commit.is_empty() and is_instance_valid(_version_label):
		_version_label.text = Version.display_text(commit)


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
	if username.is_empty():
		match_status.text = "Digite um username antes de continuar."
		player_name_input.grab_focus()
		return {"ok": false}
	var renamed := Multiplayer.change_username(username)
	if not renamed.get("ok", false):
		_show_action_error(str(renamed.get("reason", "")))
		return {"ok": false}
	var address: String = relay_address_input.text.strip_edges()
	if address.is_empty():
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
	get_tree().change_scene_to_file(CFConst.PATH_CUSTOM + "CGFMain.tscn")


func _on_match_status_changed(text: String) -> void:
	match_status.text = text
	if _lobby_busy and not Rede.is_searching and not Rede.is_connected:
		_set_lobby_busy(false)


func _on_join_failed(message: String) -> void:
	if not message.is_empty():
		_show_action_error(message)


func _show_action_error(message: String) -> void:
	match_status.text = message
	action_error.dialog_text = message
	action_error.popup_centered(Vector2(520, 170))


# No navegador o jogo pode ser instalado como app (manifest + service worker
# em online/site). O botao so aparece quando a pagina ofereceu a instalacao ou
# quando o aparelho e iOS, onde o navegador nao expoe o prompt.
func _setup_pwa_entry() -> void:
	if not OS.has_feature("web"):
		return
	if not _js_flag("typeof window.bsPwaCanInstall === 'function'"):
		return
	if _js_flag("window.bsPwaIsInstalled()"):
		return
	_pwa_button = Button.new()
	_pwa_button.name = "PwaInstall"
	_pwa_button.text = "Instalar app"
	_pwa_button.tooltip_text = \
			"Abrir o BS Web em uma janela propria, sem a barra do navegador."
	_pwa_button.pressed.connect(_on_pwa_install_pressed)
	add_child(_pwa_button)
	_place_pwa_button()
	get_viewport().size_changed.connect(_place_pwa_button)


func _place_pwa_button() -> void:
	if not is_instance_valid(_pwa_button):
		return
	var area: Vector2 = get_viewport().get_visible_rect().size
	_pwa_button.position = Vector2(
			area.x - PWA_BUTTON_SIZE.x - PWA_BUTTON_MARGIN, PWA_BUTTON_MARGIN)
	_pwa_button.size = PWA_BUTTON_SIZE


func _on_pwa_install_pressed() -> void:
	if _js_flag("window.bsPwaCanInstall()"):
		JavaScriptBridge.eval("window.bsPwaInstall();", true)
		# O dialogo e do navegador; esconde o botao para nao ficar atras dele.
		_pwa_button.hide()
		return
	if _js_flag("window.bsPwaIsIos()"):
		_show_action_error("No iPhone/iPad: toque em Compartilhar e depois em "
				+ "\"Adicionar a Tela de Inicio\".")
		return
	_show_action_error("No menu do navegador, escolha Instalar aplicativo "
			+ "(Chrome/Edge) ou Adicionar a Tela de Inicio.")


func _js_flag(expression: String) -> bool:
	var value = JavaScriptBridge.eval("String(%s)" % expression, true)
	if value == null:
		return false
	return str(value).strip_edges().to_lower() == "true"


# A densidade do tabuleiro e da prévia só é escolhida no desktop: no navegador
# o build renderiza sempre em HD+ e quem manda no tamanho é o canvas. A escolha
# vale a partir da próxima partida, porque o board lê o ajuste ao abrir.
func _setup_render_option() -> void:
	if RenderResolution.is_web():
		return
	var hint := "Densidade de renderização do tabuleiro e da prévia de carta. " \
			+ "Vale a partir da próxima partida."
	var row := HBoxContainer.new()
	row.name = "RenderResolution"
	var caption := Label.new()
	caption.text = "Tabuleiro"
	caption.tooltip_text = hint
	row.add_child(caption)
	var options := OptionButton.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.tooltip_text = hint
	options.add_item(RenderResolution.label(RenderResolution.HD))
	options.add_item(RenderResolution.label(RenderResolution.FULL_HD))
	options.selected = 1 if RenderResolution.current_choice() \
			== RenderResolution.FULL_HD else 0
	options.item_selected.connect(_on_render_option_selected)
	row.add_child(options)
	v_buttons.add_child(row)
	# Above the Exit button, so the way out stays the last row.
	v_buttons.move_child(row, v_buttons.get_child_count() - 2)


func _on_render_option_selected(index: int) -> void:
	var choice := RenderResolution.FULL_HD if index == 1 else RenderResolution.HD
	RenderResolution.set_choice(choice)
	DisplayMode.apply_render_choice()


# O leitor de relatos não aparece em nenhum botão: só sete cliques rápidos no
# título. Um clique isolado não deixa rastro visual.
func _setup_feedback_entry() -> void:
	title_label.mouse_filter = Control.MOUSE_FILTER_STOP
	title_label.gui_input.connect(_on_title_gui_input)
	var notice := Feedback.take_boot_notice()
	if not notice.is_empty():
		match_status.text = notice
		match_status.modulate = Color(1.0, 0.85, 0.6)


func _on_title_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.is_pressed() \
			or event.get_button_index() != MOUSE_BUTTON_LEFT:
		return
	var now := Time.get_ticks_msec()
	if now - _last_title_click > FEEDBACK_CLICK_GAP_MS:
		_title_clicks = 0
	_last_title_click = now
	_title_clicks += 1
	if _title_clicks < FEEDBACK_CLICKS:
		return
	_title_clicks = 0
	_open_feedback_admin()


func _open_feedback_admin() -> void:
	if not is_instance_valid(_feedback_admin):
		_feedback_admin = FeedbackAdminScript.new()
		add_child(_feedback_admin)
	_feedback_admin.open()


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
	main_menu.size = get_viewport().get_visible_rect().size
