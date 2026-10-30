extends Control

const DeckCatalog = preload("res://src/custom/DeckCatalog.gd")
const PlaymatCatalog = preload("res://src/custom/PlaymatCatalog.gd")
const LinkDeckScene = preload("res://src/custom/BSDBDeckImportDialog.tscn")

const DECK_SIZE := 60
const MAX_LOG_LINES := 200
const MENU_SAVE := 0
const MENU_LEAVE := 1
const CARD_LINK_COLOR := "#ffd479"
const ACTIVE_SEAT_COLOR := Color(1.0, 0.85, 0.45)
const IDLE_SEAT_COLOR := Color(0.82, 0.86, 0.92)
const PLAYMAT_UPLOAD_HINT := "Playmat: use uma imagem 16:9, de preferência 1920x1080."
const PLAYMAT_WEB_MAX_BYTES := 12 * 1024 * 1024
# The browser has no file dialog Godot can open, so the artwork is picked by a
# hidden <input type="file"> and handed over as base64. GDScript reads it in
# chunks, which keeps the frames short while a large photo comes across.
const WEB_CHUNK_SIZE := 262144

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
onready var _solo_deck_buttons: HBoxContainer = $PreparePanel/Margin/VBox/SoloDeckButtons
onready var _solo_deck_p1: Button = $PreparePanel/Margin/VBox/SoloDeckButtons/DeckP1
onready var _solo_deck_p2: Button = $PreparePanel/Margin/VBox/SoloDeckButtons/DeckP2
onready var _saved_decks: MenuButton = $PreparePanel/Margin/VBox/DeckButtons/SavedDecks
onready var _link_deck_button: Button = $PreparePanel/Margin/VBox/DeckButtons/LinkDeck
onready var _playmat_options: OptionButton = \
		$PreparePanel/Margin/VBox/PlaymatButtons/PlaymatOptions
onready var _playmat_upload: Button = \
		$PreparePanel/Margin/VBox/PlaymatButtons/PlaymatUpload
onready var _start_button: Button = $PreparePanel/Margin/VBox/StartButton
onready var _cancel_button: Button = $PreparePanel/Margin/VBox/CancelButton
onready var _overlay: ColorRect = $Overlay
onready var _overlay_title: Label = $Overlay/Center/VBox/OverlayTitle
onready var _overlay_message: Label = $Overlay/Center/VBox/OverlayMessage
onready var _reconnect_button: Button = $Overlay/Center/VBox/Buttons/ReconnectButton
onready var _leave_button: Button = $Overlay/Center/VBox/Buttons/LeaveButton

var _saved_deck_list := []
var _playmat_list := []
var _logs := []
var _status_note := ""
var _last_display_summary := ""
var _link_dialog: WindowDialog
var _solo_deck_popup: PopupMenu
var _preview_name := ""
var _preview_card: Card = null
var _preview_owned := {}
var _playmat_dialog: FileDialog
var _playmat_poll: Timer
var _playmat_chunk := ""
var _playmat_offset := 0
var _playmat_total := -1


func _ready() -> void:
	_saved_decks.get_popup().connect(
			"index_pressed", self, "_on_saved_deck_pressed")
	_saved_decks.connect("about_to_show", self, "_populate_saved_decks")
	_solo_deck_popup = PopupMenu.new()
	add_child(_solo_deck_popup)
	_solo_deck_popup.connect("index_pressed", self, "_on_saved_deck_pressed")
	_solo_deck_p1.connect("pressed", self, "_on_solo_deck_pressed", [1])
	_solo_deck_p2.connect("pressed", self, "_on_solo_deck_pressed", [2])
	var match_popup := _match_menu.get_popup()
	match_popup.clear()
	match_popup.add_item("Salvar jogo", MENU_SAVE)
	match_popup.add_item("Voltar ao menu", MENU_LEAVE)
	match_popup.connect("id_pressed", self, "_on_match_menu_pressed")
	_link_deck_button.connect("pressed", self, "_on_link_deck_pressed")
	_playmat_options.connect("item_selected", self, "_on_playmat_selected")
	_playmat_upload.connect("pressed", self, "_on_playmat_upload_pressed")
	_populate_playmats()
	_start_button.connect("pressed", self, "_on_start_pressed")
	_cancel_button.connect("pressed", self, "_on_leave_pressed")
	_advance_button.connect("pressed", self, "_on_advance_pressed")
	_swap_seat_button.connect("pressed", self, "_on_swap_seat_pressed")
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
	# The file dialog hangs off the window, so leaving the tree takes it along.
	if is_instance_valid(_playmat_dialog):
		_playmat_dialog.queue_free()
		_playmat_dialog = null


#-----------------------------------------------------------------------------
# Preparation
#-----------------------------------------------------------------------------

func _apply_last_deck() -> void:
	if not is_inside_tree() or not Multiplayer.is_preparing():
		return
	if Multiplayer.is_solo():
		_apply_last_solo_decks()
		return
	if Multiplayer.is_local_deck_ready():
		return
	var entry := DeckCatalog.find_auto_deck()
	if entry.empty():
		return
	_choose_deck(entry["deck"], str(entry["path"]))


# The hotseat keeps one deck button per seat; each one starts with the last deck
# chosen for that seat so the match can begin without picking them again.
func _apply_last_solo_decks() -> void:
	for slot in [1, 2]:
		if Multiplayer.is_solo_deck_ready(slot):
			continue
		var entry := DeckCatalog.find_seat_deck(slot)
		if entry.empty():
			continue
		_choose_deck(entry["deck"], str(entry["path"]), slot)


func _populate_saved_decks() -> void:
	_populate_deck_popup(_saved_decks.get_popup())


func _populate_deck_popup(popup: PopupMenu) -> void:
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


func _on_solo_deck_pressed(slot: int) -> void:
	Multiplayer.set_solo_pick_slot(slot)
	_hint_label.text = "Escolha o deck de " \
			+ Multiplayer.get_slot_username(slot) + " ou importe um link."
	_populate_deck_popup(_solo_deck_popup)
	_solo_deck_popup.popup_centered()


func _on_link_deck_pressed() -> void:
	_link_dialog.popup_centered(Vector2(560, 190))


func _on_link_deck_loaded(deck: Dictionary) -> void:
	_choose_deck(deck)


func _populate_playmats() -> void:
	_playmat_options.clear()
	_playmat_list = PlaymatCatalog.list()
	var selected := PlaymatCatalog.selected_id()
	var selected_index := 0
	for index in range(_playmat_list.size()):
		_playmat_options.add_item(str(_playmat_list[index].get("name", "")))
		if str(_playmat_list[index].get("id", "")) == selected:
			selected_index = index
	_playmat_options.selected = selected_index


# The board is already on screen behind this panel, so applying the choice here
# doubles as the preview.
func _on_playmat_selected(index: int) -> void:
	if index < 0 or index >= _playmat_list.size():
		return
	var playmat_id := str(_playmat_list[index].get("id", ""))
	PlaymatCatalog.remember_id(playmat_id)
	_apply_playmat(playmat_id)


func _apply_playmat(playmat_id: String) -> void:
	var board := get_parent()
	if board and board.has_method("apply_playmat"):
		board.apply_playmat(playmat_id)


#-----------------------------------------------------------------------------
# Own playmat: the artwork comes from the player's machine, which lets the web
# build ship without any bundled image.
#-----------------------------------------------------------------------------

func _on_playmat_upload_pressed() -> void:
	if OS.has_feature("web"):
		_begin_web_playmat_pick()
		return
	_open_playmat_dialog()


func _open_playmat_dialog() -> void:
	if _playmat_dialog == null:
		_playmat_dialog = FileDialog.new()
		_playmat_dialog.name = "PlaymatFileDialog"
		_playmat_dialog.mode = FileDialog.MODE_OPEN_FILE
		_playmat_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_playmat_dialog.filters = PoolStringArray(
				["*.png, *.jpg, *.jpeg, *.webp ; Imagens"])
		_playmat_dialog.connect("file_selected", self,
				"_on_playmat_file_selected")
		# Parented to the window so the dialog opens centered on screen.
		get_tree().root.add_child(_playmat_dialog)
	_playmat_dialog.popup_centered(Vector2(760, 500))


func _on_playmat_file_selected(path: String) -> void:
	var image := Image.new()
	if image.load(path) != OK:
		_playmat_note("Não foi possível ler " + path.get_file() + ".")
		return
	_store_playmat(image)


# Assembled at call time instead of kept as a constant: the size limit stays in
# one place, and a GDScript constant expression cannot call str().
static func web_picker_js() -> String:
	return PoolStringArray([
		"window.__bsPlaymat = window.__bsPlaymat || {",
		"  data: '', name: '', error: '', busy: false };",
		"window.__bsPlaymatStatus = function () {",
		"  var state = window.__bsPlaymat;",
		"  if (state.busy) { return 'busy'; }",
		"  if (state.error) { return state.error; }",
		"  return state.data.length > 0 ? 'ready' : 'idle';",
		"};",
		"window.__bsPlaymatLength = function () {",
		"  return window.__bsPlaymat.data.length;",
		"};",
		"window.__bsPlaymatChunk = function (offset, size) {",
		"  return window.__bsPlaymat.data.substring(offset, offset + size);",
		"};",
		"window.__bsPlaymatReset = function () {",
		"  var state = window.__bsPlaymat;",
		"  state.data = ''; state.name = ''; state.error = ''; state.busy = false;",
		"  return 'ok';",
		"};",
		"window.__bsPlaymatPick = function () {",
		"  var state = window.__bsPlaymat;",
		"  state.data = ''; state.name = ''; state.error = ''; state.busy = true;",
		"  var input = document.createElement('input');",
		"  input.type = 'file';",
		"  input.accept = 'image/png,image/jpeg,image/webp';",
		"  input.style.display = 'none';",
		"  input.onchange = function () {",
		"    var file = input.files && input.files[0];",
		"    if (!file) { state.busy = false; state.error = 'cancel'; return; }",
		"    if (file.size > " + str(PLAYMAT_WEB_MAX_BYTES) + ") {",
		"      state.busy = false; state.error = 'big'; return;",
		"    }",
		"    var reader = new FileReader();",
		"    reader.onload = function () {",
		"      var text = String(reader.result || '');",
		"      var comma = text.indexOf(',');",
		"      state.name = file.name;",
		"      state.data = comma >= 0 ? text.substring(comma + 1) : '';",
		"      state.busy = false;",
		"      if (state.data.length === 0) { state.error = 'read'; }",
		"    };",
		"    reader.onerror = function () {",
		"      state.busy = false; state.error = 'read';",
		"    };",
		"    reader.readAsDataURL(file);",
		"  };",
		"  input.oncancel = function () {",
		"    state.busy = false; state.error = 'cancel';",
		"  };",
		"  document.body.appendChild(input);",
		"  input.click();",
		"  setTimeout(function () {",
		"    if (input.parentNode) { input.parentNode.removeChild(input); }",
		"  }, 300000);",
		"  return 'ok';",
		"};",
	]).join("\n")


func _begin_web_playmat_pick() -> void:
	JavaScript.eval(web_picker_js(), true)
	var started := str(JavaScript.eval("window.__bsPlaymatPick()", true))
	if started != "ok":
		_playmat_note(_web_pick_note(started))
		return
	_playmat_chunk = ""
	_playmat_offset = 0
	_playmat_total = -1
	_playmat_note(PLAYMAT_UPLOAD_HINT)
	if _playmat_poll == null:
		_playmat_poll = Timer.new()
		_playmat_poll.name = "PlaymatPickPoll"
		_playmat_poll.wait_time = 0.2
		add_child(_playmat_poll)
		_playmat_poll.connect("timeout", self, "_poll_web_playmat")
	_playmat_poll.start()


# One chunk per tick: a photo can arrive as a few megabytes of base64, and taking
# it all in a single frame would stall the board behind this panel.
func _poll_web_playmat() -> void:
	if _playmat_total < 0:
		var status := str(JavaScript.eval("window.__bsPlaymatStatus()", true))
		if status == "busy":
			return
		if status != "ready":
			_stop_playmat_poll()
			_playmat_note(_web_pick_note(status))
			return
		_playmat_total = int(JavaScript.eval("window.__bsPlaymatLength()", true))
		if _playmat_total <= 0:
			_stop_playmat_poll()
			_playmat_note("A imagem escolhida veio vazia.")
			return
	var chunk := str(JavaScript.eval(
			"window.__bsPlaymatChunk(%d, %d)" % [_playmat_offset, WEB_CHUNK_SIZE],
			true))
	if chunk.empty():
		_stop_playmat_poll()
		_playmat_note("Não foi possível ler a imagem do navegador.")
		return
	_playmat_chunk += chunk
	_playmat_offset += chunk.length()
	if _playmat_offset < _playmat_total:
		return
	_stop_playmat_poll()
	var image := _web_playmat_image(_playmat_chunk)
	JavaScript.eval("window.__bsPlaymatReset()", true)
	_playmat_chunk = ""
	if image == null:
		_playmat_note("Use uma imagem PNG, JPG ou WebP.")
		return
	_store_playmat(image)


func _stop_playmat_poll() -> void:
	if _playmat_poll:
		_playmat_poll.stop()


func _web_pick_note(status: String) -> String:
	match status:
		"cancel", "idle":
			return "Escolha do playmat cancelada."
		"big":
			return "Arquivo grande demais: use uma imagem de até 12 MB."
		"read":
			return "O navegador não conseguiu ler o arquivo."
	return "Não foi possível abrir o seletor de imagens."


# The magic bytes choose the decoder, so a wrong guess does not fill the log
# with loader errors.
func _web_playmat_image(base64: String) -> Image:
	var buffer := Marshalls.base64_to_raw(base64)
	if buffer.size() < 12:
		return null
	var image := Image.new()
	if buffer[0] == 0x89 and buffer[1] == 0x50:
		return image if image.load_png_from_buffer(buffer) == OK else null
	if buffer[0] == 0xFF and buffer[1] == 0xD8:
		return image if image.load_jpg_from_buffer(buffer) == OK else null
	if buffer[0] == 0x52 and buffer[1] == 0x49:
		return image if image.load_webp_from_buffer(buffer) == OK else null
	return null


func _store_playmat(image: Image) -> void:
	var result := PlaymatCatalog.save_custom(image)
	if not result.get("ok", false):
		_playmat_note(str(result.get("reason",
				"Não foi possível salvar o playmat.")))
		return
	# Remembered before the list is rebuilt so the dropdown lands on the upload.
	PlaymatCatalog.remember_id(PlaymatCatalog.CUSTOM_ID)
	_populate_playmats()
	_apply_playmat(PlaymatCatalog.CUSTOM_ID)
	var size: Vector2 = result.get("size", Vector2.ZERO)
	_playmat_note("Playmat salvo com %d x %d px. Ele fica só neste aparelho."
			% [int(size.x), int(size.y)])


func _playmat_note(text: String) -> void:
	_hint_label.text = text
	_append_log(text)


func _choose_deck(deck: Dictionary, path: String = "", slot: int = 0) -> void:
	var count := DeckCatalog.count_cards(deck)
	if count != DECK_SIZE:
		_hint_label.text = "O deck tem " + str(count) + " cartas. " \
				+ "São necessárias 60 para iniciar."
		_append_log("Deck recusado: " + str(count) + "/60 cartas.")
		return
	# A deck picked from the list or from a link goes to the seat whose button
	# was pressed last; the match prefill passes its seat explicitly.
	var target := slot
	if Multiplayer.is_solo() and target <= 0:
		target = int(Multiplayer.solo_pick_slot)
	var result := {}
	if target > 0:
		result = Multiplayer.select_solo_deck(target, deck)
	else:
		result = Multiplayer.select_deck(deck)
	if not result.get("ok", false):
		_hint_label.text = str(result.get("reason", "Não foi possível usar o deck."))
		return
	if not path.empty():
		DeckCatalog.remember_deck(path)
		if target > 0:
			DeckCatalog.remember_seat_deck(target, path)
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
	call_deferred("_apply_last_deck")


#-----------------------------------------------------------------------------
# Phases and checkpoints
#-----------------------------------------------------------------------------

func _on_advance_pressed() -> void:
	if not Multiplayer.advance_phase():
		_append_log("Não é possível avançar a fase agora.")


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
	_solo_deck_buttons.visible = solo
	_saved_decks.visible = not solo
	if solo:
		_refresh_solo_deck_buttons()
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
			_hint_label.text = "Clique em P1 e em P2 para escolher " \
					+ "60 cartas para cada assento."
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


# Both seat buttons show the deck they will use and which seat the next deck or
# link import goes to.
func _refresh_solo_deck_buttons() -> void:
	var active := int(Multiplayer.solo_pick_slot)
	_solo_deck_p1.text = _solo_deck_button_text(1)
	_solo_deck_p2.text = _solo_deck_button_text(2)
	_solo_deck_p1.add_color_override("font_color",
			ACTIVE_SEAT_COLOR if active == 1 else IDLE_SEAT_COLOR)
	_solo_deck_p2.add_color_override("font_color",
			ACTIVE_SEAT_COLOR if active == 2 else IDLE_SEAT_COLOR)


func _solo_deck_button_text(slot: int) -> String:
	var label := Multiplayer.get_slot_username(slot) + " · "
	var deck := Multiplayer.get_solo_deck(slot)
	if deck.empty():
		return label + "Escolher deck"
	return label + str(deck.get("name", "Deck")) + " (" \
			+ str(DeckCatalog.count_cards(deck)) + "/60)"


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
	_log_label.scroll_to_line(max(_log_label.get_line_count() - 1, 0))


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
	card.preview_force_front = not card.is_faceup and card.was_public
	# The detached previews and the mirrors run the card state machine, which
	# would unfocus the closeup again on the next frame.
	card.preview_locked = true
	cfc.NMAP.main.focus_card(card)


func _release_preview() -> void:
	if is_instance_valid(_preview_card):
		_preview_card.preview_force_front = false
		_preview_card.preview_locked = false
		if cfc.NMAP.has("main") and cfc.NMAP.main:
			cfc.NMAP.main.unfocus(_preview_card)
	_preview_card = null
	_preview_name = ""


# The log names a card, but the table can hold several copies of it, and the
# first one found is often face down inside the deck, which would preview its
# back. Only a copy the player is allowed to read is used; anything else falls
# back to a detached preview that always shows the front.
func _find_preview_card(card_name: String) -> Card:
	for group in ["cards", "remote_cards"]:
		for candidate in get_tree().get_nodes_in_group(group):
			if candidate is Card and is_instance_valid(candidate) \
					and candidate.is_inside_tree() \
					and candidate.canonical_name == card_name \
					and _is_readable_preview(candidate):
				return candidate
	return _instance_preview_card(card_name)


func _is_readable_preview(card: Card) -> bool:
	return card.visible and (card.is_faceup or card.was_public)


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
