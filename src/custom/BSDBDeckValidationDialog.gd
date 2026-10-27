extends WindowDialog

signal card_confirmed(card_name, category, energy)
signal cancelled

const VALID_TYPES := ["Personagem", "Suporte", "Habilidade", "Cenário"]
const ENERGY_TYPES := ["Personagem", "Suporte"]

onready var progress_label: Label = $VBox/Progress
onready var card_image: TextureRect = $VBox/Content/ImageFrame/CardImage
onready var name_field: LineEdit = $VBox/Content/Fields/NameField
onready var type_field: OptionButton = $VBox/Content/Fields/TypeField
onready var energy_label: Label = $VBox/Content/Fields/EnergyLabel
onready var energy_field: SpinBox = $VBox/Content/Fields/EnergyField
onready var hint_label: Label = $VBox/Content/Fields/Hint
onready var error_label: Label = $VBox/Content/Fields/Error
onready var confirm_button: Button = $VBox/Buttons/Confirm
onready var cancel_button: Button = $VBox/Buttons/Cancel

var _accepted := false
var _pending_image_path := ""


func _ready() -> void:
	for card_type in VALID_TYPES:
		type_field.add_item(card_type)
	type_field.connect("item_selected", self, "_on_type_selected")
	confirm_button.connect("pressed", self, "_on_confirm_pressed")
	cancel_button.connect("pressed", self, "_on_cancel_pressed")
	connect("popup_hide", self, "_on_popup_hide")
	if not cfc.is_connected("card_image_loaded", self, "_on_card_image_loaded"):
		# warning-ignore:return_value_discarded
		cfc.connect("card_image_loaded", self, "_on_card_image_loaded")


func show_card(
		definition: Dictionary,
		index: int,
		total: int,
		missing: Array) -> void:
	_accepted = false
	progress_label.text = "Carta %d de %d" % [index + 1, total]
	name_field.text = str(definition.get("Name", ""))
	name_field.placeholder_text = "Nome da carta"
	var category := str(definition.get("_tipo", "")).strip_edges()
	var type_index := VALID_TYPES.find(category)
	type_field.select(type_index if type_index >= 0 else 0)
	var energy_text := str(definition.get("ENERGIA", "")).strip_edges()
	energy_field.value = float(energy_text.to_int()) if not energy_text.empty() else 0.0
	if missing.empty():
		hint_label.text = "Revise os dados essenciais da carta."
	else:
		hint_label.text = "Preencha: " + PoolStringArray(missing).join(", ")
	error_label.text = ""
	_update_energy_visibility()
	_load_card_image(str(definition.get("_bsdb_image_path", "")))
	popup_centered(Vector2(600, 400))


func _load_card_image(image_path: String) -> void:
	_pending_image_path = image_path
	card_image.texture = null
	if image_path.empty():
		return
	cfc.request_card_image(image_path)


func _on_card_image_loaded(image_path: String, texture: ImageTexture) -> void:
	if image_path != _pending_image_path:
		return
	card_image.texture = texture


func _on_type_selected(_index: int) -> void:
	_update_energy_visibility()


func _update_energy_visibility() -> void:
	var needs_energy: bool = _selected_category() in ENERGY_TYPES
	energy_label.visible = needs_energy
	energy_field.visible = needs_energy


func _selected_category() -> String:
	var index := type_field.selected
	if index < 0 or index >= VALID_TYPES.size():
		return VALID_TYPES[0]
	return VALID_TYPES[index]


func _on_confirm_pressed() -> void:
	var card_name := name_field.text.strip_edges()
	if card_name.empty():
		error_label.text = "Informe o nome da carta."
		name_field.grab_focus()
		return
	var category := _selected_category()
	var energy := ""
	if category in ENERGY_TYPES:
		energy = str(max(0, int(round(energy_field.value))))
	_accepted = true
	hide()
	emit_signal("card_confirmed", card_name, category, energy)


func _on_cancel_pressed() -> void:
	_accepted = true
	hide()
	emit_signal("cancelled")


func _on_popup_hide() -> void:
	if not _accepted:
		emit_signal("cancelled")
	_accepted = false
