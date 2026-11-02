extends CLListCardObject

var abilities_label : RichTextLabel

func _ready() -> void:
	super._ready()
	# warning-ignore:return_value_discarded
	get_viewport().size_changed.connect(_on_viewport_resized)

func setup(_card_name: String) -> void:
	super.setup(_card_name)
	abilities_label = get_node("Abilities")
	abilities_label.custom_minimum_size.x = get_viewport().get_visible_rect().size.x / 2

# Resizes the abilities to match the window size.
# So that the abilities have the most space to show.
func _on_viewport_resized() -> void:
	abilities_label.custom_minimum_size.x = get_viewport().get_visible_rect().size.x / 2
	
