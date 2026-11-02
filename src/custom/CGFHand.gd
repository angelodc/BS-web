extends Hand


func _ready() -> void:
	super._ready()
	# The board draws its own hand/deck counter in the left column.
	$Counters.visible = false
	# warning-ignore:return_value_discarded
	$Control/ManipulationButtons/DiscardRandom.pressed.connect(_on_DiscardRandom_Button_pressed)
