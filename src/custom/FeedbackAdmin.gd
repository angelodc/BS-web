extends Window

# Leitor local dos relatos, aberto por 7 cliques no título do lobby. Não é uma
# tela de produção: serve para revisar o que o ícone do HUD gravou (texto,
# carta, print, log e gravação JSONL) antes de existir um painel remoto.

const PreviewScene = preload("res://src/core/CardViewer/CVPreviewPopup.tscn")
const DeckCatalog = preload("res://src/custom/DeckCatalog.gd")

var _list: ItemList
var _detail: RichTextLabel
var _status: Label
var _card_button: Button
var _screenshot_button: Button
var _files_button: Button
var _reports := []
var _preview: Control = null
var _image_window: Window = null
var _image_texture: TextureRect = null


func _ready() -> void:
	title = "Relatos salvos"
	size = Vector2i(980, 620)
	min_size = Vector2i(820, 520)
	transient = true
	close_requested.connect(hide)
	visibility_changed.connect(_on_visibility_changed)
	_build_ui()
	hide()


func _on_visibility_changed() -> void:
	if not visible:
		_hide_overlays()


func open() -> void:
	_reports = Feedback.list_reports()
	_list.clear()
	for report in _reports:
		var kind := "Sugestão" if str(report.get("kind", "")) \
				== "suggestion" else "Bug"
		var card: Dictionary = report.get("card", {})
		var suffix := ""
		if bool(report.get("auto", false)):
			suffix = " · automático"
		elif not card.is_empty():
			suffix = " · " + str(card.get("display", card.get("name", "")))
		var label := str(report.get("created_label", "sem data")) \
				+ " · " + kind + suffix
		var index := _list.add_item(label)
		_list.set_item_metadata(index, report)
	_status.text = "%d relato%s salvo%s localmente." % [
		_reports.size(), "s" if _reports.size() != 1 else "",
		"s" if _reports.size() != 1 else ""]
	if _reports.is_empty():
		_detail.text = "Nenhum relato ainda.\n\n" \
				+ "Durante a partida, use o ícone de bug na borda direita. " \
				+ "Clique nele ou arraste uma carta para anexá-la."
		_update_buttons({})
	else:
		_list.select(0)
		_on_report_selected(0)
	popup_centered(size)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	box.add_child(split)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(310, 0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_report_selected)
	split.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	split.add_child(right)

	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = false
	_detail.scroll_active = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.custom_minimum_size = Vector2(0, 380)
	right.add_child(_detail)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_card_button = Button.new()
	_card_button.text = "Ver carta"
	_card_button.pressed.connect(_on_card_pressed)
	buttons.add_child(_card_button)
	_screenshot_button = Button.new()
	_screenshot_button.text = "Ver print"
	_screenshot_button.pressed.connect(_on_screenshot_pressed)
	buttons.add_child(_screenshot_button)
	_files_button = Button.new()
	_files_button.text = "Abrir pasta" if not OS.has_feature("web") \
			else "Baixar relato"
	_files_button.pressed.connect(_on_files_pressed)
	buttons.add_child(_files_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var close := Button.new()
	close.text = "Fechar"
	close.pressed.connect(hide)
	buttons.add_child(close)
	right.add_child(buttons)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_status)


func _selected_report() -> Dictionary:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return {}
	return _list.get_item_metadata(selected[0])


func _on_report_selected(index: int) -> void:
	var report: Dictionary = _list.get_item_metadata(index)
	_detail.text = _report_text(report)
	_update_buttons(report)
	_hide_overlays()


# The reader opens the card and the print on top of its own window, so a new
# selection or a closed reader must not leave either of them floating.
func _hide_overlays() -> void:
	if is_instance_valid(_preview) and _preview.visible:
		_preview.hide()
	if is_instance_valid(_image_window) and _image_window.visible:
		_image_window.hide()


func _update_buttons(report: Dictionary) -> void:
	var card: Dictionary = report.get("card", {})
	_card_button.disabled = _card_key(report).is_empty()
	_screenshot_button.disabled = \
			Feedback.report_file(report, "screenshot").is_empty()
	_files_button.disabled = report.is_empty()


func _report_text(report: Dictionary) -> String:
	var lines := []
	var kind := "Sugestão" if str(report.get("kind", "")) == "suggestion" \
			else "Bug"
	lines.append("Tipo: " + kind + (" · automático" \
			if bool(report.get("auto", false)) else ""))
	lines.append("Quando: " + str(report.get("created_label", "")))
	lines.append("Versão: " + str(report.get("app_version", "")) + " · " \
			+ str(report.get("platform", "")) + " · Godot " \
			+ str(report.get("engine", "")))
	var game: Dictionary = report.get("game", {})
	if not game.is_empty():
		lines.append("Sala: " + _or_dash(game.get("room", "")) \
				+ " · modo " + _or_dash(game.get("mode", "")) \
				+ " · assento " + str(game.get("seat", "")) \
				+ " · rodada " + str(game.get("round", "")))
		lines.append("Relay: " + _or_dash(game.get("relay", "")))
		var p1 := str(game.get("p1", ""))
		var p2 := str(game.get("p2", ""))
		if not p1.is_empty() or not p2.is_empty():
			lines.append("Jogadores: " + _or_dash(p1) + " × " + _or_dash(p2))
	var card: Dictionary = report.get("card", {})
	if not card.is_empty():
		lines.append("Carta: " + str(card.get("display", card.get("name", ""))) \
				+ " · chave " + _or_dash(card.get("key", "")) \
				+ " · zona " + _or_dash(card.get("zone", "")))
	var contact := str(report.get("contact", ""))
	if not contact.is_empty():
		lines.append("Contato: " + contact)
	lines.append("")
	lines.append(str(report.get("message", "")))
	var attachments: Dictionary = report.get("attachments", {})
	var attached := []
	if attachments.has("screenshot"):
		attached.append("print")
	if attachments.has("log"):
		attached.append("log (%d linhas)" % int(report.get("log_lines", 0)))
	if attachments.has("recording"):
		var size := int(report.get("recording_bytes", 0))
		attached.append("gravação JSONL (%.1f KB)" % (size / 1024.0))
	lines.append("")
	lines.append("Anexos: " + (" · ".join(PackedStringArray(attached)) \
			if not attached.is_empty() else "nenhum"))
	return "\n".join(PackedStringArray(lines))


func _or_dash(value) -> String:
	if value == null:
		return "—"
	var text := str(value)
	return text if not text.is_empty() else "—"


func _card_key(report: Dictionary) -> String:
	var card: Dictionary = report.get("card", {})
	var key := str(card.get("key", ""))
	if key.is_empty():
		key = str(card.get("name", ""))
	return key


func _on_card_pressed() -> void:
	var report := _selected_report()
	if is_instance_valid(_preview) and _preview.visible:
		_preview.hide()
		return
	if is_instance_valid(_image_window):
		_image_window.hide()
	# The popup keeps the first card it was given, so a new report rebuilds it.
	if is_instance_valid(_preview):
		_preview.queue_free()
		_preview = null
	var card := _card_from_report(report)
	if card == null:
		return
	_preview = PreviewScene.instantiate()
	_preview.z_index = 50
	add_child(_preview)
	_preview.show_preview_card(card)
	_pin_preview()


# The report carries the card definition so the lobby can rebuild the preview
# without a deck loaded. Older reports fall back to the last deck's definitions.
func _card_from_report(report: Dictionary) -> Card:
	var data: Dictionary = report.get("card", {})
	var canonical := str(data.get("name", ""))
	if canonical.is_empty():
		canonical = str(data.get("key", ""))
	if canonical.is_empty():
		return null
	var definition: Dictionary = data.get("definition", {})
	if not definition.is_empty():
		var card := _card_from_definition(canonical, definition)
		if card != null:
			return card
	DeckCatalog.apply_definitions(DeckCatalog.load_last_deck())
	if not cfc.card_definitions.has(canonical):
		_status.text = "A definição desta carta não está carregada."
		return null
	return cfc.instance_card(canonical)


func _card_from_definition(canonical: String, definition: Dictionary) -> Card:
	var scene_name := str(definition.get(CardConfig.SCENE_PROPERTY, ""))
	if scene_name.is_empty():
		return null
	var packed := load(CFConst.PATH_CARDS + scene_name + ".tscn") as PackedScene
	if packed == null:
		return null
	var card := packed.instantiate() as Card
	if card == null:
		return null
	card.canonical_name = canonical
	card.properties = definition.duplicate(true)
	return card


# The preview follows the mouse in the board; here the decisive click is often
# at the bottom of the reader, which would place the card off the window. Pin it
# to the top-left corner once the popup finished its first placement.
func _pin_preview() -> void:
	await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(_preview) or not _preview.visible:
		return
	_preview.set_process(false)
	_preview.position = Vector2(24, 56)


func _on_screenshot_pressed() -> void:
	var report := _selected_report()
	var image := Feedback.load_report_image(report)
	if image == null:
		_status.text = "Este relato não tem print."
		return
	if is_instance_valid(_preview) and _preview.visible:
		_preview.hide()
	_ensure_image_window()
	_image_texture.texture = ImageTexture.create_from_image(image)
	_image_window.popup_centered(Vector2i(1100, 700))


func _ensure_image_window() -> void:
	if is_instance_valid(_image_window):
		return
	_image_window = Window.new()
	_image_window.title = "Print do relato"
	_image_window.size = Vector2i(1100, 700)
	_image_window.transient = true
	_image_window.close_requested.connect(_image_window.hide)
	add_child(_image_window)
	# Clicking anywhere (or the close_requested above) dismisses the print; the
	# window has no title bar of its own to offer a close button.
	var dismiss := Button.new()
	dismiss.flat = true
	dismiss.focus_mode = Control.FOCUS_NONE
	dismiss.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dismiss.pressed.connect(_image_window.hide)
	_image_window.add_child(dismiss)
	_image_texture = TextureRect.new()
	_image_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_image_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_window.add_child(_image_texture)
	var hint := Label.new()
	hint.text = "Clique para fechar"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -150
	hint.offset_top = 10
	hint.offset_right = -14
	hint.offset_bottom = 34
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_image_window.add_child(hint)


# No desktop a pasta mostra o relato inteiro; no navegador o acesso ao
# sistema de arquivos não existe, então o JSON é baixado pelo navegador.
func _on_files_pressed() -> void:
	var report := _selected_report()
	if report.is_empty():
		return
	var id := str(report.get("id", "relato"))
	if OS.has_feature("web"):
		var payload := JSON.stringify(report, "\t").to_utf8_buffer()
		JavaScriptBridge.download_buffer(payload, "relato-" + id + ".json")
		_status.text = "Relato enviado para os downloads do navegador."
		return
	OS.shell_open(ProjectSettings.globalize_path(
			str(report.get("_folder", ""))))
