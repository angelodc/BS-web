extends CardBackGlow

var font_scaled : float = 1
var _base_font_size : int = 0

func _ready() -> void:
	super._ready()
	viewed_node = $Viewed
	
# Since we have a label on top of our image, we use this to scale the label
# as well
# We don't care about the viewed icon, since it will never be visible
# in the viewport focus.
func scale_to(scale_multiplier: float) -> void:	
	if font_scaled != scale_multiplier:
		var label : Label = $Label
		label.custom_minimum_size *= scale_multiplier
		# No Godot 4 o FontFile não tem `.size`; o tamanho da fonte é um override
		# de tema por Control. Guardamos o tamanho base uma vez e escalamos a
		# partir dele para não compostar em chamadas repetidas.
		if _base_font_size == 0:
			_base_font_size = label.get_theme_font_size("font_size")
		label.add_theme_font_size_override("font_size", int(round(_base_font_size * scale_multiplier)))
		font_scaled = scale_multiplier
	
