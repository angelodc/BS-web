extends Panel

const PlaymatCatalog = preload("res://src/custom/PlaymatCatalog.gd")

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
onready var multiplayer_button := $MainMenu/VBox/Center/VButtons/Multiplayer
onready var solo_match_button := $MainMenu/VBox/Center/VButtons/SoloMatch
onready var create_match_button := $MainMenu/VBox/Center/VButtons/CreateMatch
onready var resume_button := $MainMenu/VBox/Center/VButtons/ResumeGame

var _lobby_busy := false
var _entering_game := false

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
	Rede.connect("status_changed", self, "_on_match_status_changed")
	Rede.connect("join_failed", self, "_on_join_failed")
	action_error.get_label().autowrap = true
	Multiplayer.connect("lobby_ready", self, "_on_lobby_ready")
	Multiplayer.connect("session_ended", self, "_on_session_ended")
	Multiplayer.connect("resume_status", self, "_on_resume_status")
	match_status.text = Rede.get_status()
	_apply_backdrop()
	_update_lobby_controls()
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')


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
