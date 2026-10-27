extends Panel

const DeckCatalog = preload("res://src/custom/DeckCatalog.gd")
const IMPORT_DECK_ID := 1000

# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

onready var v_buttons := $MainMenu/VBox/Center/VButtons
onready var main_menu := $MainMenu
#onready var settings_menu := $SettingsMenu
onready var deck_builder := $DeckBuilder
onready var card_library := $CardLibrary
onready var deck_import_dialog := $DeckImportDialog
onready var checkpoint_list := $CheckpointList
onready var action_error := $ActionError
onready var player_name_input := $MainMenu/VBox/Center/VButtons/PlayerName
onready var relay_address_input := $MainMenu/VBox/Center/VButtons/RelayAddress
onready var match_status := $MainMenu/VBox/Center/VButtons/MatchStatus
onready var multiplayer_button := $MainMenu/VBox/Center/VButtons/Multiplayer
onready var single_player_button := $MainMenu/VBox/Center/VButtons/SinglePlayerDemo
onready var create_match_button := $MainMenu/VBox/Center/VButtons/CreateMatch
onready var resume_button := $MainMenu/VBox/Center/VButtons/ResumeGame
onready var saved_decks_button := $MainMenu/VBox/Center/VButtons/SavedDecks
onready var deckbuilder_button := $MainMenu/VBox/Center/VButtons/Deckbuilder
onready var card_library_button := $MainMenu/VBox/Center/VButtons/CardLibrary
onready var gut_button := $MainMenu/VBox/Center/VButtons/GUT

var _lobby_busy := false
var _entering_game := false
var _saved_deck_list := []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
#	settings_menu.rect_position.x = get_viewport().get_visible_rect().size.x
	deck_builder.rect_position.x = -get_viewport().get_visible_rect().size.x
	card_library.rect_position.x = -get_viewport().get_visible_rect().size.x
#	settings_menu.back_button.connect("pressed", self, "_on_Setings_Back_pressed")
#	settings_menu.recover_prebuilts.connect("pressed", self, "_on_PreBuilts_pressed")
	deck_builder.back_button.connect("pressed", self, "_on_DeckBuilder_Back_pressed")
	card_library.back_button.connect("pressed", self, "_on_CardLibrary_Back_pressed")
	deck_import_dialog.connect("deck_loaded", self, "_on_deck_imported")
	deck_import_dialog.get_node("VBox/Buttons/Cancel").connect(
			"pressed", deck_import_dialog, "hide")
	saved_decks_button.get_popup().connect(
			"id_pressed", self, "_on_saved_deck_selected")
	saved_decks_button.connect("about_to_show", self, "_populate_saved_decks")
	checkpoint_list.connect("resume_requested", self, "_on_resume_requested")
	player_name_input.text = str(cfc.game_settings.get(
			"multiplayer_username", ""))
	relay_address_input.text = str(cfc.game_settings.get(
			"multiplayer_relay_address", Rede.DEFAULT_ADDRESS))
	Rede.connect("status_changed", self, "_on_match_status_changed")
	Rede.connect("join_failed", self, "_on_join_failed")
	action_error.get_label().autowrap = true
	Multiplayer.connect("lobby_ready", self, "_on_lobby_ready")
	Multiplayer.connect("session_ended", self, "_on_session_ended")
	Multiplayer.connect("resume_status", self, "_on_resume_status")
	match_status.text = Rede.get_status()
	_update_lobby_controls()
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')


func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"SinglePlayerDemo":
			if _lobby_busy:
				return
			Multiplayer.leave_session()
			cfc.current_deck = {}
			# warning-ignore:return_value_discarded
			get_tree().change_scene(CFConst.PATH_CUSTOM + 'CGFMain.tscn')
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
		"ResumeGame":
			if _lobby_busy:
				return
			var resume_identity := _prepare_identity()
			if not resume_identity.get("ok", false):
				return
			checkpoint_list.open(resume_identity["username"])
		"GUT":
			if _lobby_busy:
				return
			# warning-ignore:return_value_discarded
			get_tree().change_scene("res://tests/tests.tscn")
		"Deckbuilder":
			if _lobby_busy:
				return
			switch_to_tab(deck_builder)
		"CardLibrary":
			if _lobby_busy:
				return
			switch_to_tab(card_library)
		"Exit":
			Multiplayer.leave_session()
			get_tree().quit()


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
		address = Rede.DEFAULT_ADDRESS
		relay_address_input.text = address
	cfc.set_setting("multiplayer_relay_address", address)
	return {"ok": true, "username": username, "address": address}


func _set_lobby_busy(busy: bool) -> void:
	_lobby_busy = busy
	player_name_input.editable = not busy
	relay_address_input.editable = not busy
	for button in [
			single_player_button, create_match_button, resume_button,
			saved_decks_button, deckbuilder_button, card_library_button,
			gut_button]:
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


func _populate_saved_decks() -> void:
	var popup: PopupMenu = saved_decks_button.get_popup()
	popup.clear()
	_saved_deck_list = DeckCatalog.list_decks()
	if _saved_deck_list.empty():
		popup.add_item("Nenhum deck salvo")
		popup.set_item_disabled(0, true)
	else:
		for index in range(_saved_deck_list.size()):
			var entry: Dictionary = _saved_deck_list[index]
			popup.add_item("%s (%d cartas)" % [
				str(entry["name"]), int(entry["count"])], index)
	popup.add_separator()
	popup.add_item("Importar deck por link...", IMPORT_DECK_ID)


func _on_saved_deck_selected(id: int) -> void:
	if _lobby_busy or _entering_game:
		return
	if id == IMPORT_DECK_ID:
		deck_import_dialog.popup_centered(Vector2(560, 190))
		return
	if id < 0 or id >= _saved_deck_list.size():
		return
	var entry: Dictionary = _saved_deck_list[id]
	DeckCatalog.remember_deck(str(entry["path"]))
	_enter_game_with_deck(entry["deck"])


func _enter_game_with_deck(deck: Dictionary) -> void:
	if _entering_game:
		return
	_entering_game = true
	Multiplayer.leave_session()
	cfc.current_deck = deck
	DeckCatalog.apply_definitions(deck)
	# warning-ignore:return_value_discarded
	get_tree().change_scene(CFConst.PATH_CUSTOM + "CGFMain.tscn")


func _on_deck_imported(deck: Dictionary) -> void:
	_enter_game_with_deck(deck)


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


func switch_to_tab(tab: Control) -> void:
	var main_position_x : float
	match tab:
#		settings_menu:
#			main_position_x = -get_viewport().get_visible_rect().size.x
		deck_builder, card_library:
			main_position_x = get_viewport().get_visible_rect().size.x
	$MenuTween.interpolate_property(main_menu,'rect_position:x',
			main_menu.rect_position.x, main_position_x, menu_switch_time,
			Tween.TRANS_BACK, Tween.EASE_IN_OUT)
	$MenuTween.interpolate_property(tab,'rect_position:x',
			tab.rect_position.x, 0, menu_switch_time,
			Tween.TRANS_BACK, Tween.EASE_IN_OUT)
	$MenuTween.start()


func switch_to_main_menu(tab: Control) -> void:
	var tab_position_x : float
	match tab:
#		settings_menu:
#			tab_position_x = get_viewport().get_visible_rect().size.x
		deck_builder, card_library:
			tab_position_x = -get_viewport().get_visible_rect().size.x
	$MenuTween.interpolate_property(tab,'rect_position:x',
			tab.rect_position.x, tab_position_x, menu_switch_time,
			Tween.TRANS_BACK, Tween.EASE_IN_OUT)
	$MenuTween.interpolate_property(main_menu,'rect_position:x',
			main_menu.rect_position.x, 0, menu_switch_time,
			Tween.TRANS_BACK, Tween.EASE_IN_OUT)
	$MenuTween.start()

func _on_DeckBuilder_Back_pressed() -> void:
	switch_to_main_menu(deck_builder)
	
func _on_CardLibrary_Back_pressed() -> void:
	switch_to_main_menu(card_library)
	
func _on_Menu_resized() -> void:
	for tab in [main_menu, deck_builder, card_library]:
		if is_instance_valid(tab):
			tab.rect_size = get_viewport().get_visible_rect().size
			if tab.rect_position.x < 0.0:
					tab.rect_position.x = -get_viewport().get_visible_rect().size.x
			elif tab.rect_position.x > 0.0:
					tab.rect_position.x = get_viewport().get_visible_rect().size.x
