extends CardFront

onready var card_image: TextureRect = $CardImage
onready var card_text_container: MarginContainer = $Margin

func _ready() -> void:
	_card_text = find_node("CardText")
	# Map your card text label layout here. We use this when scaling
	# The card or filling up its text
	card_labels["Name"] = find_node("Name")
	card_labels["Type"] = find_node("Type")
	card_labels["Tags"] = find_node("Tags")
	card_labels["Requirements"] = find_node("Requirements")
	card_labels["Abilities"] = find_node("Abilities")
	card_labels["Cost"] = find_node("Cost")
	card_labels["Power"] = find_node("Power")

	# These set te max size of each label. This is used to calculate how much
	# To shrink the font when it doesn't fit in the rect.
	card_label_min_sizes["Name"] = Vector2(CFConst.CARD_SIZE.x - 4, 19)
	card_label_min_sizes["Type"] = Vector2(CFConst.CARD_SIZE.x - 4, 13)
	card_label_min_sizes["Tags"] = Vector2(CFConst.CARD_SIZE.x - 4, 17)
	card_label_min_sizes["Requirements"] = Vector2(CFConst.CARD_SIZE.x - 4, 11)
	card_label_min_sizes["Abilities"] = Vector2(CFConst.CARD_SIZE.x - 4, 120)
	card_label_min_sizes["Cost"] = Vector2(16,16)
	card_label_min_sizes["Power"] = Vector2(16,16)

	# This is not strictly necessary, but it allows us to change
	# the card label sizes without editing the scene
	for l in card_label_min_sizes:
		card_labels[l].rect_min_size = card_label_min_sizes[l]

	# This stores the maximum size for each label, when the card is at its
	# standard size.
	# This is multiplied when the card is resized in the viewport.
	for label in card_labels:
		match label:
			"Cost","Power":
				original_font_sizes[label] = 15
			"Requirements":
				original_font_sizes[label] = 11
			"Abilities":
				original_font_sizes[label] = 25
			_:
				original_font_sizes[label] = 16


func load_card_image(image_path: String) -> void:
	if not cfc.is_connected(
				"card_image_loaded", self, "_on_card_image_loaded"):
		# warning-ignore:return_value_discarded
		cfc.connect("card_image_loaded", self, "_on_card_image_loaded")
	cfc.request_card_image(image_path)


func _on_card_image_loaded(image_path: String, texture: ImageTexture) -> void:
	if image_path != card_owner.properties.get("_bsdb_image_path", ""):
		return
	card_image.texture = texture
	card_image.visible = true
	card_text_container.visible = false
