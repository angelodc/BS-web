# Game-specific extension of the core OverridableUtils, plugged in through
# CFConst.PATH_OVERRIDABLE_UTILS. Adds the card text panel (name, metadata and
# the printed text with one block per action) to the focus previews.
# FAQ and errata are not shown here: they open from the card's "?" button.
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
	var actions := _card_actions(card)
	if abilities.is_empty() and actions.is_empty():
		return
	focus_info.add_info("card_text", "", TEXT_PANEL_SCENE, true)
	var panel: Control = focus_info.existing_details["card_text"]
	panel.get_node("Header").text = _property_text(card, "Name")
	panel.get_node("Meta").text = _meta_line(card)
	var details: RichTextLabel = panel.get_node("Details")
	details.text = _details_bbcode(abilities, actions)


# Errata and FAQ live behind the question-mark button on the card, so the hover
# panel keeps showing only what is printed on the card.
func _card_actions(card: Card) -> Array:
	var value = card.get_property("_actions")
	if typeof(value) != TYPE_ARRAY:
		return []
	var actions: Array = []
	for action in value:
		if typeof(action) == TYPE_DICTIONARY and not _action_bbcode(action).is_empty():
			actions.append(action)
	return actions


func _details_bbcode(abilities: String, actions: Array) -> String:
	var blocks: Array[String] = []
	if not abilities.is_empty():
		blocks.append(_escape_bbcode(break_sentences(abilities)))
	for action in actions:
		blocks.append(_action_bbcode(action))
	return "\n\n".join(blocks)


# One action reads as its own block: name, the metadata chips and the text.
func _action_bbcode(action: Dictionary) -> String:
	var lines: Array[String] = []
	var title := str(action.get("name", "")).strip_edges()
	if not title.is_empty():
		lines.append("[color=#f0c96a][b]"
				+ _escape_bbcode(title) + "[/b][/color]")
	var bits: Array[String] = []
	var action_type := str(action.get("type", "")).strip_edges()
	if not action_type.is_empty():
		bits.append(action_type)
	var cost := str(action.get("cost", "")).strip_edges()
	if not cost.is_empty() and cost != "0":
		bits.append("Custo " + cost)
	var power := str(action.get("power", "")).strip_edges()
	if not power.is_empty():
		bits.append(power)
	if not bits.is_empty():
		lines.append("[color=#8f97a8][font_size=11]"
				+ _escape_bbcode(" • ".join(bits)) + "[/font_size][/color]")
	var text := str(action.get("text", "")).strip_edges()
	if not text.is_empty():
		lines.append(_escape_bbcode(break_sentences(text)))
	return "\n".join(lines)


# Printed card texts arrive as one paragraph, and a single long line is hard to
# follow in the hover panel. Each full stop starts a new line, the way the
# printed cards read. A dot only ends a sentence when whitespace follows it, so
# decimals such as "1.5" stay together.
static func break_sentences(text: String) -> String:
	var broken := ""
	var index := 0
	while index < text.length():
		var character := text[index]
		broken += character
		index += 1
		if character != ".":
			continue
		var spaces := 0
		while index < text.length() \
				and (text[index] == " " or text[index] == "\t"):
			index += 1
			spaces += 1
		if spaces > 0 and index < text.length() and text[index] != "\n":
			broken += "\n"
	return broken


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
	# One pass only: `[lb]` and `[rb]` contain the opposite bracket, so two
	# sequential replaces would escape the escapes.
	var escaped := ""
	for index in text.length():
		var character := text[index]
		if character == "[":
			escaped += "[lb]"
		elif character == "]":
			escaped += "[rb]"
		else:
			escaped += character
	return escaped
