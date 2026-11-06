extends Window

# Formulário de bug/sugestão aberto pelo ícone do HUD. Nesta fase o relato é
# local: o JSON, o print, o log e a gravação JSONL vão para user://reports/ e o
# menu oculto do lobby lê a mesma pasta.

signal saved(message)

const TYPE_BUG := 0
const TYPE_SUGGESTION := 1

var _type: OptionButton
var _message: TextEdit
var _contact: LineEdit
var _screenshot_check: CheckBox
var _log_check: CheckBox
var _recording_check: CheckBox
var _card_label: Label
var _remove_card_button: Button
var _status: Label
var _save_button: Button
var _cancel_button: Button
var _saving := false


func _ready() -> void:
	title = "Relatar bug ou sugerir melhoria"
	size = Vector2i(640, 660)
	min_size = Vector2i(560, 560)
	transient = true
	close_requested.connect(_on_cancel)
	_build_ui()
	hide()


func open() -> void:
	_saving = false
	_status.text = ""
	_save_button.disabled = false
	_cancel_button.disabled = false
	_screenshot_check.button_pressed = true
	_log_check.button_pressed = true
	_refresh_card()
	_refresh_recording()
	popup_centered(size)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var intro := Label.new()
	intro.text = "Descreva o bug ou a melhoria. Se quiser apontar uma carta, " \
			+ "feche este aviso e arraste a carta até o ícone de bug."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)

	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 8)
	var type_label := Label.new()
	type_label.text = "Tipo"
	type_label.custom_minimum_size.x = 70
	type_row.add_child(type_label)
	_type = OptionButton.new()
	_type.add_item("Bug")
	_type.add_item("Sugestão")
	_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(_type)
	box.add_child(type_row)

	var message_label := Label.new()
	message_label.text = "O que aconteceu?"
	box.add_child(message_label)
	_message = TextEdit.new()
	_message.placeholder_text = "Explique o que você esperava e o que aconteceu."
	_message.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_message.custom_minimum_size = Vector2(0, 190)
	_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_message)

	var card_panel := PanelContainer.new()
	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 8)
	_card_label = Label.new()
	_card_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_row.add_child(_card_label)
	_remove_card_button = Button.new()
	_remove_card_button.text = "Remover carta"
	_remove_card_button.pressed.connect(_on_remove_card)
	card_row.add_child(_remove_card_button)
	card_panel.add_child(card_row)
	box.add_child(card_panel)

	var contact_row := HBoxContainer.new()
	contact_row.add_theme_constant_override("separation", 8)
	var contact_label := Label.new()
	contact_label.text = "Contato"
	contact_label.custom_minimum_size.x = 70
	contact_row.add_child(contact_label)
	_contact = LineEdit.new()
	_contact.placeholder_text = "E-mail ou Discord (opcional)"
	_contact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contact_row.add_child(_contact)
	box.add_child(contact_row)

	_screenshot_check = CheckBox.new()
	_screenshot_check.text = "Incluir captura da tela"
	_screenshot_check.button_pressed = true
	_screenshot_check.tooltip_text = "O print sai sem o formulário e sem a " \
			+ "interface do relato."
	box.add_child(_screenshot_check)

	_log_check = CheckBox.new()
	_log_check.text = "Incluir log da partida"
	_log_check.button_pressed = true
	_log_check.tooltip_text = "Últimos eventos da mesa e do aplicativo."
	box.add_child(_log_check)

	_recording_check = CheckBox.new()
	_recording_check.text = "Incluir gravação JSONL da partida"
	_recording_check.button_pressed = true
	box.add_child(_recording_check)

	var privacy := Label.new()
	privacy.text = "O relato fica salvo neste aparelho, em user://reports. " \
			+ "O print, o log e a gravação só entram se estiverem marcados."
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.modulate = Color(1, 1, 1, 0.72)
	box.add_child(privacy)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1.0, 0.72, 0.55)
	box.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	_cancel_button = Button.new()
	_cancel_button.text = "Cancelar"
	_cancel_button.pressed.connect(_on_cancel)
	buttons.add_child(_cancel_button)
	_save_button = Button.new()
	_save_button.text = "Salvar relato"
	_save_button.pressed.connect(_on_save_pressed)
	buttons.add_child(_save_button)
	box.add_child(buttons)


func _refresh_card() -> void:
	var card := Feedback.attached_card()
	if card.is_empty():
		_card_label.text = "Carta anexada: nenhuma"
		_remove_card_button.hide()
		return
	var display := str(card.get("display", ""))
	if display.is_empty():
		display = str(card.get("name", ""))
	var zone := GameEvents.zone_label(str(card.get("zone", "")))
	_card_label.text = "Carta anexada: " + display \
			+ (" · " + zone if not zone.is_empty() else "")
	_remove_card_button.show()


func _refresh_recording() -> void:
	var path := Feedback.current_recording_path()
	if path.is_empty():
		_recording_check.text = "Incluir gravação JSONL (inicie pelo menu " \
				+ "da partida)"
		_recording_check.button_pressed = false
		_recording_check.disabled = true
		_recording_check.modulate = Color(1, 1, 1, 0.55)
		return
	_recording_check.text = "Incluir gravação JSONL da partida"
	_recording_check.button_pressed = true
	_recording_check.disabled = false
	_recording_check.modulate = Color(1, 1, 1, 1)


func _on_remove_card() -> void:
	Feedback.clear_attached_card()
	_refresh_card()


func _on_cancel() -> void:
	if _saving:
		return
	Feedback.clear_attached_card()
	hide()


func _on_save_pressed() -> void:
	if _saving:
		return
	var message := _message.text.strip_edges()
	if message.is_empty():
		_status.text = "Escreva o relato antes de salvar."
		_message.grab_focus()
		return
	_saving = true
	_save_button.disabled = true
	_cancel_button.disabled = true
	_status.text = "Salvando..."
	var include_screenshot := _screenshot_check.button_pressed
	var include_log := _log_check.button_pressed
	var include_recording := _recording_check.button_pressed
	var card := Feedback.attached_card()
	var recording := Feedback.current_recording_path() \
			if include_recording else ""
	hide()
	var image: Image = null
	if include_screenshot:
		image = await _capture_board()
	var log_text := Feedback.match_log_text() if include_log else ""
	var report := {
		"kind": "suggestion" if _type.selected == TYPE_SUGGESTION else "bug",
		"message": message,
		"contact": _contact.text.strip_edges(),
		"card": card,
		"game": Feedback.match_context(),
		"include": {
			"screenshot": include_screenshot,
			"log": include_log,
			"recording": include_recording,
		},
		"auto": false,
	}
	var result := Feedback.save_report(report, image, log_text, recording)
	_saving = false
	_save_button.disabled = false
	_cancel_button.disabled = false
	if not bool(result.get("ok", false)):
		popup_centered(size)
		_status.text = "Não foi possível salvar: " \
				+ str(result.get("reason", "erro desconhecido"))
		return
	Feedback.clear_attached_card()
	_message.text = ""
	_contact.text = ""
	_status.text = ""
	saved.emit("Relato salvo no aparelho.")


func _capture_board() -> Image:
	var board = cfc.NMAP.get("board", null)
	if not is_instance_valid(board):
		return null
	var viewport: Viewport = board.get_viewport()
	if viewport == null:
		return null
	# O formulário é uma Window separada; escondê-lo antes garante que o print
	# mostre só a mesa, inclusive quando a janela é embutida no SubViewport.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var texture := viewport.get_texture()
	if texture == null:
		return null
	return texture.get_image()
