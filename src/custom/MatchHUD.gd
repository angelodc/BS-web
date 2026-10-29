extends Control

const DeckCatalog = preload("res://src/custom/DeckCatalog.gd")
const LinkDeckScene = preload("res://src/custom/BSDBDeckImportDialog.tscn")

const DECK_SIZE := 60
const MAX_LOG_LINES := 200
const MENU_SAVE := 0
const MENU_LEAVE := 1
const CARD_LINK_COLOR := "#ffd479"

onready var _top_bar: PanelContainer = $TopBar
onready var _phase_label: Label = $TopBar/Margin/VBox/PhaseLabel
onready var _info_label: Label = $TopBar/Margin/VBox/InfoLabel
onready var _match_menu: MenuButton = $MatchMenu
onready var _advance_button: Button = $AdvanceButton
onready var _swap_seat_button: Button = $SwapSeatButton
onready var _checkpoint_label: Label = $CheckpointLabel
onready var _log_panel: PanelContainer = $LogPanel
onready var _log_label: RichTextLabel = $LogPanel/Margin/LogLabel
onready var _prepare_panel: PanelContainer = $PreparePanel
onready var _room_label: Label = $PreparePanel/Margin/VBox/RoomLabel
onready var _deck_status: Label = $PreparePanel/Margin/VBox/DeckStatus
onready var _display_label: Label = $PreparePanel/Margin/VBox/DisplayLabel
onready var _hint_label: Label = $PreparePanel/Margin/VBox/Hint
onready var _seat_picker: OptionButton = $PreparePanel/Margin/VBox/SeatPicker
onready var _saved_decks: MenuButton = $PreparePanel/Margin/VBox/DeckButtons/SavedDecks
onready var _link_deck_button: Button = $PreparePanel/Margin/VBox/DeckButtons/LinkDeck
onready var _start_button: Button = $PreparePanel/Margin/VBox/StartButton
onready var _cancel_button: Button = $PreparePanel/Margin/VBox/CancelButton
onready var _overlay: ColorRect = $Overlay
onready var _overlay_title: Label = $Overlay/Center/VBox/OverlayTitle
onready var _overlay_message: Label = $Overlay/Center/VBox/OverlayMessage
onready var _reconnect_button: Button = $Overlay/Center/VBox/Buttons/ReconnectButton
onready var _leave_button: Button = $Overlay/Center/VBox/Buttons/LeaveButton

var _saved_deck_list := []
var _logs := []
var _status_note := ""
var _last_display_summary := ""
var _link_dialog: WindowDialog
var _preview_name := ""
var _preview_card: Card = null
var _preview_owned := {}


func _ready() -> void:
	_saved_decks.get_popup().connect(
			"index_pressed", self, "_on_saved_deck_pressed")
	_saved_decks.connect("about_to_show", self, "_populate_saved_decks")
	var match_popup := _match_menu.get_popup()
	match_popup.clear()
	match_popup.add_item("Salvar jogo", MENU_SAVE)
	match_popup.add_item("Voltar ao menu", MENU_LEAVE)
	match_popup.connect("id_pressed", self, "_on_match_menu_pressed")
	_link_deck_button.connect("pressed", self, "_on_link_deck_pressed")
	_start_button.connect("pressed", self, "_on_start_pressed")
	_cancel_button.connect("pressed", self, "_on_leave_pressed")
	_advance_button.connect("pressed", self, "_on_advance_pressed")
	_swap_seat_button.connect("pressed", self, "_on_swap_seat_pressed")
	_seat_picker.add_item("Deck de P1", 1)
	_seat_picker.add_item("Deck de P2", 2)
	_seat_picker.connect("item_selected", self, "_on_seat_picked")
	_reconnect_button.connect("pressed", self, "_on_reconnect_pressed")
	_leave_button.connect("pressed", self, "_on_leave_pressed")
	_link_dialog = LinkDeckScene.instance()
	add_child(_link_dialog)
	_link_dialog.connect("deck_loaded", self, "_on_link_deck_loaded")
	Multiplayer.connect("session_changed", self, "_refresh")
	Multiplayer.connect("prep_changed", self, "_on_prep_changed")
	Multiplayer.connect("phase_changed", self, "_refresh")
	Multiplayer.connect("match_started", self, "_on_match_started")
	Multiplayer.connect("checkpoint_saved", self, "_on_checkpoint_saved")
	Multiplayer.connect("checkpoint_error", self, "_on_checkpoint_error")
	Multiplayer.connect("resume_status", self, "_on_resume_status")
	Multiplayer.connect("resume_finished", self, "_on_resume_finished")
	Multiplayer.connect("session_ended", self, "_on_session_ended")
	Multiplayer.connect("waiting_changed", self, "_on_waiting_changed")
	Multiplayer.connect("action_logged", self, "_on_action_logged")
	Multiplayer.connect("display_changed", self, "_on_display_changed")
	Rede.connect("status_changed", self, "_on_network_status")
	GameEvents.connect("game_event", self, "_on_game_event")
	_log_label.connect("meta_hover_started", self, "_on_log_meta_hover_started")
	_log_label.connect("meta_hover_ended", self, "_on_log_meta_hover_ended")
	_log_label.connect("mouse_exited", self, "_on_log_mouse_exited")
	if Multiplayer.is_session_active():
		_append_log("Sessão multiplayer iniciada.")
	else:
		_append_log("Modo solo: cada ação sua é registrada aqui.")
	_refresh()
	call_deferred("_apply_last_deck")


func _exit_tree() -> void:
	_release_preview()
	for card in _preview_owned.values():
		if is_instance_valid(card):
			card.queue_free()
	_preview_owned.clear()


#-----------------------------------------------------------------------------
# Preparation
#-----------------------------------------------------------------------------

func _apply_last_deck() -> void:
	if not is_inside_tree() or not Multiplayer.is_preparing():
		return
	if Multiplayer.is_local_deck_ready():
		return
	var entry := DeckCatalog.find_auto_deck()
	if entry.empty():
		return
	_choose_deck(entry["deck"], str(entry["path"]))


func _populate_saved_decks() -> void:
	var popup := _saved_decks.get_popup()
	popup.clear()
	_saved_deck_list = DeckCatalog.list_decks()
	if _saved_deck_list.empty():
		popup.add_item("Nenhum deck salvo encontrado")
		return
	for deck in _saved_deck_list:
		popup.add_item("%s (%d cartas)" % [
			str(deck.get("name", "Deck")), int(deck.get("count", 0))])


func _on_saved_deck_pressed(index: int) -> void:
	if index < 0 or index >= _saved_deck_list.size():
		return
	var entry: Dictionary = _saved_deck_list[index]
	_choose_deck(entry["deck"], str(entry["path"]))


func _on_link_deck_pressed() -> void:
	_link_dialog.popup_centered(Vector2(560, 190))


func _on_link_deck_loaded(deck: Dictionary) -> void:
	_choose_deck(deck)


func _choose_deck(deck: Dictionary, path: String = "") -> void:
	var count := DeckCatalog.count_cards(deck)
	if count != DECK_SIZE:
		_hint_label.text = "O deck tem " + str(count) + " cartas. " \
				+ "São necessárias 60 para iniciar."
		_append_log("Deck recusado: " + str(count) + "/60 cartas.")
		return
	var result := Multiplayer.select_deck(deck)
	if not result.get("ok", false):
		_hint_label.text = str(result.get("reason", "Não foi possível usar o deck."))
		return
	if not path.empty():
		DeckCatalog.remember_deck(path)
	_refresh()


func _on_start_pressed() -> void:
	if Multiplayer.request_start():
		return
	if not Multiplayer.is_local_deck_ready():
		_hint_label.text = "Escolha um deck de 60 cartas para iniciar."
	elif not Multiplayer.opponent_deck_ready:
		_hint_label.text = "Escolha o deck de P2." if Multiplayer.is_solo() \
				else "Aguardando o oponente escolher o deck."
	else:
		_hint_label.text = "Não foi possível iniciar a partida agora."


func _on_prep_changed() -> void:
	_refresh()


#-----------------------------------------------------------------------------
# Phases and checkpoints
#-----------------------------------------------------------------------------

func _on_advance_pressed() -> void:
	if not Multiplayer.advance_phase():
		_append_log("Não é possível avançar a fase agora.")


func _on_seat_picked(index: int) -> void:
	Multiplayer.set_solo_pick_slot(_seat_picker.get_item_id(index))


func _on_swap_seat_pressed() -> void:
	if not Multiplayer.swap_solo_seat():
		_append_log("Não foi possível trocar de assento agora.")


func _on_match_menu_pressed(id: int) -> void:
	if id == MENU_SAVE:
		_append_log(str(Multiplayer.save_current_game().get("message", "")))
	elif id == MENU_LEAVE:
		_on_leave_pressed()


func _on_checkpoint_saved(checkpoint_sequence, _path) -> void:
	_append_log("Checkpoint #" + str(checkpoint_sequence) + " salvo.")
	_refresh()


func _on_checkpoint_error(message: String) -> void:
	_append_log("Checkpoint: " + message)


func _on_match_started() -> void:
	_status_note = ""
	_append_log("A partida começou.")
	_refresh()


func _on_waiting_changed(waiting: bool, message: String) -> void:
	if waiting:
		_append_log(message)
	else:
		_status_note = ""
		_append_log("Conexão restabelecida.")
	_refresh()


func _on_session_ended(message: String) -> void:
	_append_log(message)
	_refresh()


func _on_network_status(_text: String) -> void:
	if _prepare_panel.visible:
		_refresh_prepare()


func _on_resume_status(text: String) -> void:
	_status_note = text
	_append_log(text)
	if _overlay.visible:
		_overlay_message.text = text


func _on_resume_finished(ok: bool, message: String) -> void:
	_status_note = ""
	if not ok:
		_append_log(message)
	_refresh()


#-----------------------------------------------------------------------------
# Reconnection / leaving
#-----------------------------------------------------------------------------

func _on_reconnect_pressed() -> void:
	if not Multiplayer.manual_reconnect():
		_append_log("Não foi possível reconectar. Encerre e tente novamente.")


func _on_leave_pressed() -> void:
	Multiplayer.leave_session("Partida encerrada pelo jogador.")
	cfc.quit_game()
	# warning-ignore:return_value_discarded
	get_tree().change_scene("res://src/custom/MainMenu.tscn")


#-----------------------------------------------------------------------------
# Presentation
#-----------------------------------------------------------------------------

func _refresh() -> void:
	if not is_inside_tree():
		return
	var active := Multiplayer.is_session_active()
	# The log is the one piece of the HUD that also belongs to a solo table.
	_log_panel.visible = true
	_match_menu.visible = active and not Multiplayer.is_preparing()
	_top_bar.visible = active and not Multiplayer.is_preparing() \
			and not Multiplayer.is_starting()
	_prepare_panel.visible = Multiplayer.is_preparing()
	_overlay.visible = Multiplayer.is_frozen()
	_advance_button.visible = Multiplayer.is_playing() \
			and Multiplayer.is_my_phase()
	_swap_seat_button.visible = Multiplayer.is_solo() \
			and Multiplayer.is_playing()
	if _swap_seat_button.visible:
		_swap_seat_button.text = "Controlar " \
				+ Multiplayer.get_opponent_username()
	_checkpoint_label.visible = active and Multiplayer.sequence >= 0 \
			and not Multiplayer.is_solo()
	if _checkpoint_label.visible:
		_checkpoint_label.text = "Checkpoint #" + str(Multiplayer.sequence)
	if Multiplayer.is_ended():
		_status_note = ""
	_refresh_texts()
	_refresh_overlay()


func _refresh_texts() -> void:
	if Multiplayer.is_preparing():
		_refresh_prepare()
	if Multiplayer.is_playing() or Multiplayer.is_waiting():
		var actor := Multiplayer.get_actor_username()
		var turn := "Sua vez" if Multiplayer.is_my_phase() \
				else "Vez de " + actor
		if Multiplayer.is_solo():
			turn = "Você é " + Multiplayer.get_my_username() \
					+ " · vez de " + actor
		_phase_label.text = Multiplayer.get_phase_label().to_upper()
		_phase_label.add_color_override(
				"font_color", Multiplayer.get_phase_color())
		var lines := ["R" + str(Multiplayer.round_number) + " · E" \
				+ str(Multiplayer.step_index + 1) + "/10 · " + turn]
		var extras := []
		var starter := Multiplayer.get_slot_username(Multiplayer.starting_slot)
		if not starter.empty():
			extras.append("Começa: " + starter)
		var rolls := Multiplayer.get_rolls_text()
		if not rolls.empty():
			extras.append("Dados: " + rolls)
		if not extras.empty():
			lines.append(PoolStringArray(extras).join(" · "))
		_info_label.text = PoolStringArray(lines).join("\n")


func _refresh_prepare() -> void:
	var solo := Multiplayer.is_solo()
	_seat_picker.visible = solo
	if solo:
		_seat_picker.select(clamp(int(Multiplayer.solo_pick_slot) - 1, 0, 1))
	var role := "Você controla os dois assentos" if solo \
			else ("Anfitrião" if Multiplayer.is_authority() else "Convidado")
	var opponent := Multiplayer.get_opponent_username()
	if opponent.empty():
		opponent = "aguardando oponente"
	var room := "Mesa local" if solo else "Conectando ao relay..."
	if not solo and not Rede.room_id.empty():
		room = "Sala " + Rede.room_id
	_room_label.text = room + " · " + role \
			+ " · " + Multiplayer.get_my_username() + " vs " + opponent
	_deck_status.text = Multiplayer.get_deck_summary()
	_display_label.visible = not solo
	if not solo:
		_display_label.text = Multiplayer.get_display_summary()
		_last_display_summary = _display_label.text
	_cancel_button.text = "Voltar ao menu" if solo else "Sair da sala"
	var both_ready := Multiplayer.are_both_decks_ready()
	_start_button.disabled = not both_ready
	_start_button.text = "INICIAR" if both_ready \
			else ("Escolha os dois decks" if solo else "Aguardando decks")
	if solo:
		if both_ready:
			_hint_label.text = "Os dois decks estão prontos. Inicie a partida."
		else:
			_hint_label.text = "Escolha o deck de P1 e o de P2, " \
					+ "60 cartas cada."
	elif Multiplayer.is_local_deck_ready() and Multiplayer.opponent_deck_ready:
		_hint_label.text = "Os dois decks estão prontos. Inicie a partida."
	elif Multiplayer.is_local_deck_ready():
		_hint_label.text = "Seu deck está pronto. Aguardando o oponente."
	elif not Multiplayer.get_opponent_username().empty():
		_hint_label.text = "Escolha um deck salvo de 60 cartas ou importe um link do BSDB."
	elif Rede.room_id.empty():
		_hint_label.text = Rede.get_status()
	else:
		_hint_label.text = "Aguardando um oponente entrar na sala."


func _refresh_overlay() -> void:
	if not _overlay.visible:
		return
	_reconnect_button.visible = false
	if Multiplayer.is_waiting():
		_overlay_title.text = "Jogo congelado"
		_reconnect_button.visible = Multiplayer.can_manual_reconnect()
		var message := Multiplayer.waiting_message
		if not _status_note.empty():
			message = _status_note
		_overlay_message.text = message
	elif Multiplayer.is_ended():
		_overlay_title.text = "Partida encerrada"
		_overlay_message.text = Multiplayer.ended_message \
				if not Multiplayer.ended_message.empty() \
				else "A sessão terminou."
	else:
		_overlay_title.text = "Iniciando partida"
		_overlay_message.text = "Embaralhando e distribuindo as cartas..."


func _on_display_changed() -> void:
	var summary := Multiplayer.get_display_summary()
	if summary != _last_display_summary:
		_last_display_summary = summary
		if Multiplayer.is_preparing():
			_append_log(summary.replace("\n", " · "))
	_refresh()


func _on_action_logged(text: String) -> void:
	_append_log(text)


func _on_game_event(entry) -> void:
	if typeof(entry) != TYPE_DICTIONARY:
		return
	_append_log(str(entry.get("text", "")), str(entry.get("card", "")))


func _append_log(text: String, card_name := "") -> void:
	if text.empty():
		return
	_logs.append({"text": text, "card": card_name})
	while _logs.size() > MAX_LOG_LINES:
		_logs.pop_front()
	_render_logs()
	call_deferred("_scroll_log_to_bottom")


func _render_logs() -> void:
	var lines := PoolStringArray()
	for index in range(_logs.size()):
		lines.append(_line_bbcode(index))
	_log_label.bbcode_text = lines.join("\n")


# The card name becomes a link keyed by its line index, so the value never
# carries spaces or brackets that the BBCode parser would choke on.  Godot 3
# exposes its meta payload through [url], not the [meta] tag.
func _line_bbcode(index: int) -> String:
	var entry: Dictionary = _logs[index]
	var text := str(entry["text"])
	var card_name := str(entry.get("card", ""))
	if card_name.empty():
		return _escape_bbcode(text)
	var position := text.find(card_name)
	if position < 0:
		return _escape_bbcode(text)
	return _escape_bbcode(text.substr(0, position)) \
			+ "[color=" + CARD_LINK_COLOR + "][url=" + str(index) + "]" \
			+ _escape_bbcode(card_name) + "[/url][/color]" \
			+ _escape_bbcode(text.substr(position + card_name.length()))


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _scroll_log_to_bottom() -> void:
	_log_label.scroll_to_line(_log_label.get_paragraph_count())


#-----------------------------------------------------------------------------
# Card preview from the log
#-----------------------------------------------------------------------------

func _on_log_meta_hover_started(meta) -> void:
	_show_card_preview(_card_name_for_meta(str(meta)))


func _on_log_meta_hover_ended(_meta = null) -> void:
	_show_card_preview("")


func _on_log_mouse_exited() -> void:
	_show_card_preview("")


func _card_name_for_meta(meta: String) -> String:
	var index := int(meta)
	if index < 0 or index >= _logs.size():
		return ""
	return str(_logs[index].get("card", ""))


func _show_card_preview(card_name: String) -> void:
	if card_name == _preview_name:
		return
	_release_preview()
	if card_name.empty():
		return
	_preview_name = card_name
	var card := _find_preview_card(card_name)
	if not card or cfc.ut or not cfc.NMAP.has("main") or not cfc.NMAP.main:
		return
	_preview_card = card
	cfc.NMAP.main.focus_card(card)


func _release_preview() -> void:
	if is_instance_valid(_preview_card) and cfc.NMAP.has("main") and cfc.NMAP.main:
		cfc.NMAP.main.unfocus(_preview_card)
	_preview_card = null
	_preview_name = ""


func _find_preview_card(card_name: String) -> Card:
	for group in ["cards", "remote_cards"]:
		for candidate in get_tree().get_nodes_in_group(group):
			if candidate is Card and is_instance_valid(candidate) \
					and candidate.is_inside_tree() \
					and candidate.canonical_name == card_name:
				return candidate
	return _instance_preview_card(card_name)


# Cards that already left the table still deserve a preview, so a detached copy
# is instanced by name and kept until the HUD goes away.
func _instance_preview_card(card_name: String) -> Card:
	if _preview_owned.has(card_name) and is_instance_valid(_preview_owned[card_name]):
		return _preview_owned[card_name]
	var key := _definition_key_for_display(card_name)
	if key.empty():
		return null
	if not cfc.NMAP.has("board") or not cfc.NMAP.board:
		return null
	var card = cfc.instance_card(key)
	if not card:
		return null
	cfc.NMAP.board.add_child(card)
	card.network_mirror = true
	if card.is_in_group("cards"):
		card.remove_from_group("cards")
	card.monitoring = false
	card.monitorable = false
	card.set_control_mouse_filters(false)
	if card.buttons:
		card.buttons.set_active(false)
	card.position = Vector2(-6000, -6000)
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	_preview_owned[card_name] = card
	return card


# The log shows the display Name, but an imported deck registers each card under
# its definition id, which can be spelled without the accents.
func _definition_key_for_display(card_name: String) -> String:
	if cfc.card_definitions.has(card_name):
		return card_name
	for key in cfc.card_definitions:
		if str(cfc.card_definitions[key].get("Name", "")) == card_name:
			return str(key)
	return ""
