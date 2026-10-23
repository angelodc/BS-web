extends ManipulationButtons


func _ready() -> void:
	needed_buttons = {
		"Capacitar": "Capacitar",
		"Incapacitar": "Incapacitar",
		"Escudo": "Escudo",
		"Flip": "Flip",
		"Rot90": "T",
	}
	spawn_manipulation_buttons()
	var shield_menu: PopupMenu = PopupMenu.new()
	shield_menu.name = "ShieldMenu"
	add_child(shield_menu)
	shield_menu.connect("id_pressed", self, "_on_ShieldMenu_id_pressed")
	for button in get_children():
		if button is Button:
			button.hint_tooltip = button.name
			if button.name in ["Capacitar", "Incapacitar"]:
				button.rect_min_size = Vector2(100, 26)
			elif button.name == "Escudo":
				button.rect_min_size = Vector2(70, 26)
			elif button.name == "Flip":
				button.rect_min_size = Vector2(60, 26)


func set_active(value = true) -> void:
	var is_on_board: bool = cfc.NMAP.has("board") \
			and owner_node.get_parent() == cfc.NMAP.board
	_update_action_visibility(
			value and is_on_board,
			owner_node.is_battle_scenes_character())
	.set_active(value and is_on_board)


func _update_action_visibility(is_available: bool, is_character: bool) -> void:
	var stage: int = owner_node.get_incapacitation_stage()
	set_button_visible("Rot90", is_available and not is_character)
	set_button_visible("Flip", is_available)
	set_button_visible("Escudo", is_available and is_character)
	set_button_visible(
			"Capacitar",
			is_available and is_character and stage >= -1 and stage <= 0)
	set_button_visible(
			"Incapacitar",
			is_available and is_character and stage >= 0 and stage <= 1)


func _on_Rot90_pressed() -> void:
	owner_node.set_card_rotation(90, true)


func _on_Flip_pressed() -> void:
	owner_node.set_is_faceup(not owner_node.is_faceup)


func _on_Escudo_pressed() -> void:
	var shield_menu: PopupMenu = get_node("ShieldMenu")
	shield_menu.clear()
	for amount in range(1, 4):
		shield_menu.add_item("+" + str(amount), amount)
	shield_menu.add_separator()
	var shield_count: int = owner_node.tokens.get_token_count("escudo")
	for amount in range(1, 4):
		shield_menu.add_item("-" + str(amount) + " escudo", amount + 3)
		shield_menu.set_item_disabled(
				shield_menu.get_item_count() - 1,
				shield_count < amount)
	var shield_button: Button = get_node("Escudo")
	shield_menu.popup(Rect2(
			shield_button.rect_global_position + Vector2(shield_button.rect_size.x, 0),
			Vector2(1, 1)))


func _on_ShieldMenu_id_pressed(id: int) -> void:
	var amount: int = id if id <= 3 else -(id - 3)
	var result: int = owner_node.tokens.mod_token("escudo", amount)
	if result == CFConst.ReturnCode.FAILED:
		push_warning("The shield counter cannot be reduced below zero.")


func _on_Capacitar_pressed() -> void:
	var result = owner_node.capacitar()
	if result == CFConst.ReturnCode.FAILED:
		push_warning("The character cannot be capacitated in its current state.")
	_update_action_visibility(
			owner_node.get_parent() == cfc.NMAP.board,
			owner_node.is_battle_scenes_character())


func _on_Incapacitar_pressed() -> void:
	var result = owner_node.incapacitar()
	if result == CFConst.ReturnCode.FAILED:
		push_warning("The character cannot be incapacitated in its current state.")
	_update_action_visibility(
			owner_node.get_parent() == cfc.NMAP.board,
			owner_node.is_battle_scenes_character())
