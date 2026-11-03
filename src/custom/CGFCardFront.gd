extends CardFront

const VALID_TYPES := ["Personagem", "Suporte", "Habilidade", "Cenário"]
const LEGEND_COLOUR := Color(1, 1, 1, 1)
const LEGEND_ERROR_COLOUR := Color(1, 0.35, 0.35, 1)

@onready var card_image: TextureRect = $CardImage
@onready var card_text_container: MarginContainer = $Margin
@onready var type_legend: Label = $TypeLegend

func _ready() -> void:
	_card_text = find_child("CardText")
	# Map your card text label layout here. We use this when scaling
	# The card or filling up its text
	card_labels["Name"] = find_child("Name")
	card_labels["Type"] = find_child("Type")
	card_labels["Tags"] = find_child("Tags")
	card_labels["Requirements"] = find_child("Requirements")
	card_labels["Abilities"] = find_child("Abilities")
	# O slot com ícone de energia (rupee) mostra ENERGIA, o custo real de entrada
	# em Cena. O `Cost` do framework é sempre 0 nestes decks e fica sem exibição
	# (ver CardConfig.PROPERTIES_NOT_DISPLAYED).
	card_labels["ENERGIA"] = find_child("ENERGIA")
	card_labels["Power"] = find_child("Power")

	# These set te max size of each label. This is used to calculate how much
	# To shrink the font when it doesn't fit in the rect.
	card_label_min_sizes["Name"] = Vector2(CFConst.CARD_SIZE.x - 4, 19)
	card_label_min_sizes["Type"] = Vector2(CFConst.CARD_SIZE.x - 4, 13)
	card_label_min_sizes["Tags"] = Vector2(CFConst.CARD_SIZE.x - 4, 17)
	card_label_min_sizes["Requirements"] = Vector2(CFConst.CARD_SIZE.x - 4, 11)
	card_label_min_sizes["Abilities"] = Vector2(
			CFConst.CARD_SIZE.x - 4, CFConst.CARD_SIZE.y - 100)
	card_label_min_sizes["ENERGIA"] = Vector2(16,16)
	card_label_min_sizes["Power"] = Vector2(16,16)

	# This is not strictly necessary, but it allows us to change
	# the card label sizes without editing the scene
	for l in card_label_min_sizes:
		card_labels[l].custom_minimum_size = card_label_min_sizes[l]

	# This stores the maximum size for each label, when the card is at its
	# standard size.
	# This is multiplied when the card is resized in the viewport.
	for label in card_labels:
		match label:
			"ENERGIA","Power":
				original_font_sizes[label] = 15
			"Requirements":
				original_font_sizes[label] = 11
			"Abilities":
				original_font_sizes[label] = 25
			_:
				original_font_sizes[label] = 16

	if not card_owner.is_connected("state_changed", Callable(self, "_on_card_state_changed")):
		# warning-ignore:return_value_discarded
		card_owner.state_changed.connect(_on_card_state_changed)
	call_deferred("_refresh_type_legend")


func _on_card_state_changed(_card, _old_state, _new_state) -> void:
	_refresh_type_legend()


# The legend only exists to spot bad type data on cards while they are in hand.
func _refresh_type_legend() -> void:
	if not is_instance_valid(card_owner):
		return
	var in_hand: bool = cfc.NMAP.has("hand") \
			and card_owner.get_parent() == cfc.NMAP.hand
	type_legend.visible = in_hand
	if not in_hand:
		return
	var card_type := str(card_owner.properties.get("_tipo", "")).strip_edges()
	if card_type in VALID_TYPES:
		type_legend.text = card_type
		type_legend.add_theme_color_override("font_color", LEGEND_COLOUR)
	else:
		type_legend.text = "SEM TIPO" if card_type.is_empty() else card_type
		type_legend.add_theme_color_override("font_color", LEGEND_ERROR_COLOUR)


func load_card_image(image_path: String) -> void:
	if not cfc.is_connected("card_image_loaded", _on_card_image_loaded):
		# warning-ignore:return_value_discarded
		cfc.card_image_loaded.connect(_on_card_image_loaded)
	cfc.request_card_image(image_path)


func _on_card_image_loaded(image_path: String, texture: ImageTexture) -> void:
	if image_path != card_owner.properties.get("_bsdb_image_path", ""):
		return
	card_image.texture = texture
	card_image.visible = true
	card_text_container.visible = false
