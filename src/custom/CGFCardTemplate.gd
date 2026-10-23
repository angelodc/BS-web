extends Card


func _ready() -> void:
	pass

# Sample code on how to ensure costs are paid when a card
# is dragged from hand to the table
func common_move_scripts(new_container: Node, old_container: Node) -> void:
	if new_container == cfc.NMAP.board and old_container == cfc.NMAP.hand:
		pay_play_costs()


# Sample code on how to figure out costs of a card
func get_modified_credits_cost() -> int:
	var modified_cost : int = properties.get("Cost", 0)
	return(modified_cost)


# This sample function ensures all costs defined by a card are paid.
func pay_play_costs() -> void:
	cfc.NMAP.board.counters.mod_counter("credits", -get_modified_credits_cost())

func is_battle_scenes_character() -> bool:
	return properties.get("_tipo", "") == "Personagem"


func get_incapacitation_stage() -> int:
	match card_rotation:
		-90:
			return -1
		0:
			return 0
		90:
			return 1
	return -2


func set_incapacitation_stage(stage: int) -> int:
	if not stage in [-1, 0, 1] \
			or not is_battle_scenes_character() \
			or not cfc.NMAP.has("board") \
			or get_parent() != cfc.NMAP.board:
		return CFConst.ReturnCode.FAILED
	return set_card_rotation(stage * 90)


func capacitar() -> int:
	var stage := get_incapacitation_stage()
	if stage < -1 or stage >= 1:
		return CFConst.ReturnCode.FAILED
	return set_incapacitation_stage(stage + 1)


func incapacitar() -> int:
	var stage := get_incapacitation_stage()
	if stage < 0 or stage > 1:
		return CFConst.ReturnCode.FAILED
	return set_incapacitation_stage(stage - 1)


func set_card_rotation(
			value: int,
			toggle := false,
			start_tween := true,
			check := false,
			tags := ["Manual"]) -> int:
	if not is_battle_scenes_character() or not value in [-90, 0, 90]:
		return .set_card_rotation(value, toggle, start_tween, check, tags)
	if not cfc.NMAP.has("board") or get_parent() != cfc.NMAP.board:
		return CFConst.ReturnCode.FAILED
	if card_rotation == value:
		if toggle:
			return .set_card_rotation(0, false, start_tween, check, tags)
		return CFConst.ReturnCode.OK
	if check:
		return CFConst.ReturnCode.CHANGED

	card_rotation = value
	$CollisionShape2D.rotation_degrees = value
	_add_tween_rotation($Control.rect_rotation, value)
	if start_tween:
		$Tween.start()
	emit_signal(
			"card_rotated", self,
			"card_rotated",
			{
				"degrees": value,
				"tags": tags,
			}
	)
	return CFConst.ReturnCode.CHANGED


# A signal for whenever the player clicks on a card
func _on_Card_gui_input(event) -> void:
	._on_Card_gui_input(event)
	if event is InputEventMouseButton:
		if event.is_pressed() and event.get_button_index() == 2:
			targeting_arrow.initiate_targeting()
		elif not event.is_pressed() and event.get_button_index() == 2:
			targeting_arrow.complete_targeting()
