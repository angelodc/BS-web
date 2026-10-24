extends Pile


func _ready() -> void:
	$Control/ManipulationButtons/View.hide()
	$Control/ManipulationButtons/ViewSorted.hide()
	$Control/ManipulationButtons/Shuffle.hide()
	var swap_button := Button.new()
	swap_button.name = "SwapResource"
	swap_button.text = "Trocar"
	swap_button.rect_min_size = Vector2(92, 27)
	swap_button.mouse_filter = Control.MOUSE_FILTER_PASS
	swap_button.modulate.a = 0
	swap_button.add_to_group("manipulation_button")
	$Control/ManipulationButtons.add_child(swap_button)
	swap_button.connect("pressed", self, "_on_SwapResource_pressed")


func _on_SwapResource_pressed() -> void:
	cfc.NMAP.board.begin_resource_swap()
