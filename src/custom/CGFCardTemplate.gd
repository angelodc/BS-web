extends Card


func _ready() -> void:
	._ready()
	var image_path: String = properties.get("_bsdb_image_path", "")
	if image_path and not cfc.ut:
		card_front.load_card_image(image_path)

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


func is_battle_scenes_support() -> bool:
	return properties.get("_tipo", "") == "Suporte"


func is_battle_scenes_ability() -> bool:
	return properties.get("_tipo", "") == "Habilidade"


func is_battle_scenes_scenario() -> bool:
	return properties.get("_tipo", "") == "Cenário"


func _restore_after_invalid_board_drop(tags: Array) -> void:
	var original_parent: Node = get_parent()
	var original_position = _placement_slot \
			if original_parent == cfc.NMAP.board else null
	var movement = .move_to(original_parent, -1, original_position, tags)
	if movement is GDScriptFunctionState:
		yield(movement, "completed")


func is_battle_scenes_energy() -> bool:
	for property_name in ["_tipo", "Type"]:
		var category := str(properties.get(property_name, "")).strip_edges().to_lower()
		if category in ["energia", "energy"]:
			return true
	return false


func move_to(targetHost: Node,
		index := -1,
		board_position = null,
		tags := ["Manual"]) -> void:
	var board: Board = cfc.NMAP.board
	# Only the active scenario is shown at full card size; anything else goes
	# back to the regular board scale.
	play_area_scale = CFConst.PLAY_AREA_SCALE
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
		var placement_slot: BoardPlacementSlot = board_position \
				if board_position is BoardPlacementSlot \
				else get_potential_placement_slot()
		var is_scenario_slot := false
		if placement_slot:
			is_scenario_slot = \
					placement_slot.get_grid_name() == "Cenário Ativo"
		if is_battle_scenes_scenario():
			if not is_scenario_slot:
				var restore_scenario = \
						_restore_after_invalid_board_drop(tags)
				if restore_scenario is GDScriptFunctionState:
					yield(restore_scenario, "completed")
				return
			var previous_scenario: Card = placement_slot.occupying_card
			if previous_scenario and previous_scenario != self:
				var movement = previous_scenario.move_to(cfc.NMAP.discard)
				if movement is GDScriptFunctionState:
					yield(movement, "completed")
			play_area_scale = 1.0
			var scenario_movement = \
					.move_to(targetHost, index, placement_slot, tags)
			if scenario_movement is GDScriptFunctionState:
				yield(scenario_movement, "completed")
			return
		if is_scenario_slot:
			var restore_card = _restore_after_invalid_board_drop(tags)
			if restore_card is GDScriptFunctionState:
				yield(restore_card, "completed")
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
	if network_mirror:
		return
	if event is InputEventMouseButton and cfc.NMAP.has("board"):
		if cfc.NMAP.board.mouse_pointer.current_focused_card \
				and cfc.NMAP.board.mouse_pointer.current_focused_card != self:
			cfc.NMAP.board.mouse_pointer.current_focused_card\
					._on_Card_gui_input(event)
			return
	if event is InputEventMouseButton \
			and event.get_button_index() == BUTTON_LEFT \
			and not event.is_pressed() \
			and cfc.NMAP.has("hand") \
			and get_parent() == cfc.NMAP.hand \
			and state in [CardState.IN_HAND, CardState.FOCUSED_IN_HAND] \
			and not buttons.are_hovered() \
			and not tokens.are_hovered():
		var control: Control = get_node("Control")
		var left_half: bool = event.position.x < control.rect_size.x * 0.5
		cfc.card_drag_ongoing = null
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		control.set_default_cursor_shape(Input.CURSOR_ARROW)
		_handle_hand_half_click(left_half)
		return
	if event is InputEventMouseButton \
			and not event.is_pressed() \
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


# Left half sends the card to Resources, right half plays it according to its
# type. The click only acts when no drag started.
func _handle_hand_half_click(left_half: bool) -> void:
	if left_half:
		move_to(cfc.NMAP.discard)
		return
	var category := str(properties.get("_tipo", "")).strip_edges()
	match category:
		"Personagem", "Suporte":
			_play_card_to_scene()
		"Cenário":
			_play_card_to_scenario_area()
		"Habilidade":
			move_to(cfc.NMAP.discard)
		_:
			if cfc.NMAP.board.has_method("show_resource_message"):
				cfc.NMAP.board.show_resource_message(
						"Tipo de carta desconhecido: " + canonical_name)


func _play_card_to_scene() -> void:
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_node_or_null(
			"PlacementGridDemo")
	if not grid:
		return
	var slot: BoardPlacementSlot = grid.get_auto_placement_slot(self)
	if not slot:
		cfc.NMAP.board.show_resource_message("A Cena está cheia.")
		return
	move_to(cfc.NMAP.board, -1, slot)


func _play_card_to_scenario_area() -> void:
	var grid: BoardPlacementGrid = cfc.NMAP.board.get_node_or_null(
			"ModifiedLabelGrid")
	if not grid or grid.get_slot_count() == 0:
		return
	move_to(cfc.NMAP.board, -1, grid.get_slot(0))


func send_to_opponent_prizes() -> void:
	if cfc.NMAP.has("board"):
		cfc.NMAP.board.send_character_to_opponent_prizes(self)


func knockout() -> void:
	if cfc.NMAP.has("board"):
		cfc.NMAP.board.knockout_support(self)
