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


func is_battle_scenes_scenario() -> bool:
	return properties.get("_tipo", "") == "Cenário"


func move_to(targetHost: Node,
		index := -1,
		board_position = null,
		tags := ["Manual"]) -> void:
	var board: Board = cfc.NMAP.board
	var from_hand: bool = get_parent() == cfc.NMAP.hand
	var required_resources := 0
	var needs_resources: bool = not cfc.ut \
			and targetHost == board \
			and from_hand \
			and (is_battle_scenes_character() \
			or properties.get("_tipo", "") == "Suporte")
	if needs_resources:
		required_resources = \
				str(properties.get("ENERGIA", "0")).to_int()
		if board.get_available_resource_count() < required_resources:
			set_state(CardState.IN_HAND)
			reorganize_self()
			board.show_resource_message(
					"Recursos insuficientes para colocar " + canonical_name
					+ " em Cena.")
			return
	var is_attachment_move: bool = attachment_mode \
			!= Card.AttachmentMode.DO_NOT_ATTACH \
			and typeof(board_position) == TYPE_VECTOR2
	if targetHost == cfc.NMAP.board and not is_attachment_move:
		var placement_slot: BoardPlacementSlot = get_potential_placement_slot()
		var is_scenario_slot := false
		if placement_slot:
			is_scenario_slot = \
					placement_slot.get_grid_name() == "Cenário Ativo"
		if is_battle_scenes_scenario():
			if not is_scenario_slot:
				return
			var previous_scenario: Card = placement_slot.occupying_card
			if previous_scenario and previous_scenario != self:
				var movement = previous_scenario.move_to(cfc.NMAP.discard)
				if movement is GDScriptFunctionState:
					yield(movement, "completed")
			var scenario_movement = \
					.move_to(targetHost, index, placement_slot, tags)
			if scenario_movement is GDScriptFunctionState:
				yield(scenario_movement, "completed")
			return
		if is_scenario_slot:
			return
	var card_movement = .move_to(targetHost, index, board_position, tags)
	if card_movement is GDScriptFunctionState:
		yield(card_movement, "completed")
	if needs_resources and required_resources > 0:
		board.begin_resource_selection(self, required_resources)


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
	if current_host_card:
		return CFConst.ReturnCode.FAILED
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
	if event is InputEventMouseButton \
			and event.is_pressed() \
			and event.get_button_index() == BUTTON_LEFT \
			and cfc.NMAP.has("board") \
			and state == CardState.FOCUSED_IN_POPUP:
		if cfc.NMAP.board.pending_resource_host:
			cfc.NMAP.board.select_resource_for_host(self)
			return
		if cfc.NMAP.board.pending_resource_swap_active \
				and cfc.NMAP.board.select_resource_for_swap(self):
			return
	if event is InputEventMouseButton \
			and event.is_pressed() \
			and event.get_button_index() == BUTTON_LEFT \
			and cfc.NMAP.has("board") \
			and cfc.NMAP.board.pending_resource_swap_card \
			and cfc.NMAP.board.swap_attached_resource(self):
		return
	._on_Card_gui_input(event)
	if event is InputEventMouseButton:
		if event.is_pressed() and event.get_button_index() == 2:
			targeting_arrow.initiate_targeting()
		elif not event.is_pressed() and event.get_button_index() == 2:
			targeting_arrow.complete_targeting()
