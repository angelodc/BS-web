extends Panel

# The time it takes to switch from one menu tab to another
const menu_switch_time = 0.35

onready var v_buttons := $MainMenu/VBox/Center/VButtons
onready var main_menu := $MainMenu
#onready var settings_menu := $SettingsMenu
onready var deck_builder := $DeckBuilder
onready var card_library := $CardLibrary
onready var deck_import_dialog := $DeckImportDialog
onready var player_name_input := $MainMenu/VBox/Center/VButtons/PlayerName
onready var relay_address_input := $MainMenu/VBox/Center/VButtons/RelayAddress
onready var match_status := $MainMenu/VBox/Center/VButtons/MatchStatus
onready var multiplayer_button := $MainMenu/VBox/Center/VButtons/Multiplayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for option_button in v_buttons.get_children():
		if option_button.has_signal('pressed'):
			option_button.connect('pressed', self, 'on_button_pressed', [option_button.name])
#	settings_menu.rect_position.x = get_viewport().size.x
	deck_builder.rect_position.x = -get_viewport().size.x
	card_library.rect_position.x = -get_viewport().size.x
#	settings_menu.back_button.connect("pressed", self, "_on_Setings_Back_pressed")
#	settings_menu.recover_prebuilts.connect("pressed", self, "_on_PreBuilts_pressed")
	deck_builder.back_button.connect("pressed", self, "_on_DeckBuilder_Back_pressed")
	card_library.back_button.connect("pressed", self, "_on_CardLibrary_Back_pressed")
	deck_import_dialog.connect("deck_loaded", self, "_on_deck_imported")
	deck_import_dialog.get_node("VBox/Buttons/Cancel").connect(
			"pressed", deck_import_dialog, "hide")
	player_name_input.text = str(cfc.game_settings.get(
			"multiplayer_username", ""))
	relay_address_input.text = str(cfc.game_settings.get(
			"multiplayer_relay_address", Rede.DEFAULT_ADDRESS))
	Rede.connect("status_changed", self, "_on_match_status_changed")
	Rede.connect("match_found", self, "_on_match_found")
	match_status.text = Rede.get_status()
	# warning-ignore:return_value_discarded
	get_viewport().connect("size_changed", self, '_on_Menu_resized')


func on_button_pressed(_button_name : String) -> void:
	match _button_name:
		"SinglePlayerDemo":
			Rede.disconnect_game()
			cfc.current_deck = {}
			# warning-ignore:return_value_discarded
			get_tree().change_scene(CFConst.PATH_CUSTOM + 'CGFMain.tscn')
		"DeckFromLink":
			deck_import_dialog.popup_centered(Vector2(560, 190))
		"Multiplayer":
			if Rede.is_searching:
				Rede.disconnect_game()
				multiplayer_button.text = "Procurar Partida"
				return
			var username: String = player_name_input.text.strip_edges()
			if username.empty():
				match_status.text = "Digite um username para procurar partida."
				player_name_input.grab_focus()
				return
			cfc.set_setting("multiplayer_username", username)
			cfc.set_setting(
					"multiplayer_relay_address", relay_address_input.text.strip_edges())
			if Rede.find_match(relay_address_input.text, username):
				multiplayer_button.text = "Cancelar Busca"
		"GUT":
			# warning-ignore:return_value_discarded
			get_tree().change_scene("res://tests/tests.tscn")
		"Deckbuilder":
			switch_to_tab(deck_builder)
		"CardLibrary":
			switch_to_tab(card_library)
		"Exit":
			get_tree().quit()


func _on_deck_imported(_deck: Dictionary) -> void:
	# warning-ignore:return_value_discarded
	get_tree().change_scene(CFConst.PATH_CUSTOM + "CGFMain.tscn")


func _on_match_status_changed(text: String) -> void:
	match_status.text = text
	multiplayer_button.text = \
			"Cancelar Busca" if Rede.is_searching else "Procurar Partida"


func _on_match_found(_opponent_username: String) -> void:
	cfc.current_deck = {}
	# warning-ignore:return_value_discarded
	get_tree().change_scene(CFConst.PATH_CUSTOM + "CGFMain.tscn")


func switch_to_tab(tab: Control) -> void:
	var main_position_x : float
	match tab:
#		settings_menu:
#			main_position_x = -get_viewport().size.x
		deck_builder, card_library:
			main_position_x = get_viewport().size.x
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
#			tab_position_x = get_viewport().size.x
		deck_builder, card_library:
			tab_position_x = -get_viewport().size.x
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
			tab.rect_size = get_viewport().size
			if tab.rect_position.x < 0.0:
					tab.rect_position.x = -get_viewport().size.x
			elif tab.rect_position.x > 0.0:
					tab.rect_position.x = get_viewport().size.x
