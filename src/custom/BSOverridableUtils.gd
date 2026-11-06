# Game-specific extension of the core OverridableUtils, plugged in through
# CFConst.PATH_OVERRIDABLE_UTILS. Adds the card text panel (header + ability,
# or errata replacing the ability) to the focus previews.
extends OVUtils

const TEXT_PANEL_SCENE := preload("res://src/custom/CGFTextPanel.tscn")


func populate_info_panels(card: Card, focus_info: DetailPanels) -> void:
	focus_info.hide_all_info()
	var card_illustration = card.get_property("_illustration")
	if card_illustration:
		focus_info.show_illustration("Ilustração: " + str(card_illustration))
	else:
		focus_info.hide_illustration()
	_add_card_text_panel(card, focus_info)
	for tag in card.get_property("Tags"):
		if CardConfig.EXPLANATIONS.has(tag):
			focus_info.add_info(tag, CardConfig.EXPLANATIONS[tag])
	var card_keywords = card.get_property("_keywords")
	if card_keywords:
		for keyword in card_keywords:
			if CardConfig.EXPLANATIONS.has(keyword):
				focus_info.add_info(keyword, CardConfig.EXPLANATIONS[keyword])


func _add_card_text_panel(card: Card, focus_info: DetailPanels) -> void:
	# Menu toggle: "Texto das cartas no hover". When off, the hover shows only
	# the card image (and the illustration line/tags that exist independently).
	if not bool(cfc.game_settings.get("card_text_enabled", true)):
		return
	var abilities := _property_text(card, "Abilities")
	var errata := _property_text(card, "_errata")
	if abilities.is_empty() and errata.is_empty():
		return
	focus_info.add_info("card_text", "", TEXT_PANEL_SCENE, true)
	var panel: Control = focus_info.existing_details["card_text"]
	panel.get_node("Header").text = _property_text(card, "Name")
	panel.get_node("Meta").text = _meta_line(card)
	var details: RichTextLabel = panel.get_node("Details")
	if not errata.is_empty():
		# Cards with an errata show only the errata, flagged as such.
		details.text = "[b]Errata:[/b] " + _escape_bbcode(errata)
	else:
		details.text = _escape_bbcode(abilities)


func _meta_line(card: Card) -> String:
	var bits := []
	var tipo := _property_text(card, "_tipo")
	if not tipo.is_empty():
		bits.append(tipo)
	var energy := _property_text(card, "ENERGIA")
	if not energy.is_empty() and energy != "0":
		bits.append("Energia " + energy)
	var shield := _property_text(card, "_bsdb_shield")
	if not shield.is_empty() and shield != "0":
		bits.append("Escudo " + shield)
	var requirements := _property_text(card, "Requirements")
	if not requirements.is_empty():
		bits.append(requirements)
	var alignment := _property_text(card, "_bsdb_alignment")
	if not alignment.is_empty():
		bits.append(alignment)
	return " • ".join(bits)


func _property_text(card: Card, property_name: String) -> String:
	var value = card.get_property(property_name)
	if value == null:
		return ""
	return str(value).strip_edges()


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")
