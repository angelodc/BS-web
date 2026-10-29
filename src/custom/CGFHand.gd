extends Hand


func _ready() -> void:
	# The board draws its own hand/deck counter in the left column.
	$Counters.visible = false
	# warning-ignore:return_value_discarded
	$Control/ManipulationButtons/DiscardRandom.connect("pressed",self,'_on_DiscardRandom_Button_pressed')
