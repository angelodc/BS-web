extends ManipulationButtons

# Every button hands the card's id to the same intent the keyboard and the
# scripts will use. The board validates it first, so a click on a state the
# rules refuse changes nothing and tells the player why.


func _ready() -> void:
	# The labels were swapped against what the card does: the button that tilts
	# the character one way read as the other state. The node names stay because
	# the visibility rules and the intent handlers hang off them.
	needed_buttons = {
		"Capacitar": "Incapacitar",
		"Incapacitar": "Capacitar",
		"Escudo": "Escudo",
		"Flip": "Flip",
		"Rot90": "T",
		"Premios": "Prêmios",
		"Nocaute": "Nocaute",
		"Dano": "Dano",
	}
	spawn_manipulation_buttons()
	var shield_menu: PopupMenu = PopupMenu.new()
	shield_menu.name = "ShieldMenu"
	add_child(shield_menu)
	shield_menu.connect("id_pressed", self, "_on_ShieldMenu_id_pressed")
	for button in get_children():
		if button is Button:
			button.hint_tooltip = str(needed_buttons.get(button.name, button.name))
			if button.name in ["Capacitar", "Incapacitar"]:
				button.rect_min_size = Vector2(100, 26)
			elif button.name == "Escudo":
				button.rect_min_size = Vector2(70, 26)
			elif button.name == "Flip":
				button.rect_min_size = Vector2(60, 26)
			elif button.name == "Premios":
				button.rect_min_size = Vector2(80, 26)
			elif button.name == "Nocaute":
				button.rect_min_size = Vector2(80, 26)
			elif button.name == "Dano":
				button.rect_min_size = Vector2(80, 26)


func set_active(value = true) -> void:
	var is_on_board: bool = cfc.NMAP.has("board") \
			and owner_node.get_parent() == cfc.NMAP.board
	_update_action_visibility(
			value and is_on_board,
			owner_node.is_battle_scenes_character())
	.set_active(value and is_on_board)


func _update_action_visibility(is_available: bool, is_character: bool) -> void:
	var stage: int = owner_node.get_incapacitation_stage()
	var is_support: bool = owner_node.is_battle_scenes_support()
	set_button_visible("Rot90", is_available and not is_character)
	set_button_visible("Flip", is_available)
	set_button_visible("Escudo", is_available and is_character)
	set_button_visible("Premios",
			is_available and is_character and Multiplayer.is_session_active())
	set_button_visible("Nocaute", is_available and is_support)
	set_button_visible("Dano", is_available and is_character)
	set_button_visible(
			"Capacitar",
			is_available and is_character and stage >= -1 and stage <= 0)
	set_button_visible(
			"Incapacitar",
			is_available and is_character and stage >= 0 and stage <= 1)


# Runs one intent for the card this menu belongs to. The result is reported on
# the table's message line and, for the state buttons, the menu is refreshed.
func _apply(intent : Dictionary) -> Dictionary:
	var board = cfc.NMAP.get("board", null)
	if not is_instance_valid(board) or not board.has_method("apply_intent"):
		push_warning("A mesa não está disponível para esta ação.")
		return {"ok": false, "error": "mesa_indisponivel"}
	intent["card"] = owner_node
	var result: Dictionary = board.apply_intent(intent)
	board.report_intent(result)
	return result


func _on_Premios_pressed() -> void:
	_apply({"op": "enviar_aos_prêmios"})


func _on_Nocaute_pressed() -> void:
	_apply({"op": "nocautear"})


func _on_Dano_pressed() -> void:
	_apply({"op": "ferir", "amount": 1})


func _on_Rot90_pressed() -> void:
	_apply({"op": "girar", "degree": 90, "toggle": true})


func _on_Flip_pressed() -> void:
	_apply({"op": "virar"})


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
	_apply({"op": "escudo", "amount": amount})


func _on_Capacitar_pressed() -> void:
	_apply({"op": "capacitar"})
	_update_action_visibility(
			owner_node.get_parent() == cfc.NMAP.board,
			owner_node.is_battle_scenes_character())

func _on_Incapacitar_pressed() -> void:
	_apply({"op": "incapacitar"})
	_update_action_visibility(
			owner_node.get_parent() == cfc.NMAP.board,
			owner_node.is_battle_scenes_character())
