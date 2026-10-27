extends Reference

const DECKS_PATH := "user://Decks/"
const LAST_DECK_SETTING := "last_deck_path"


static func list_decks() -> Array:
	var entries := []
	var directory := Directory.new()
	if directory.open(DECKS_PATH) != OK:
		return entries
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			var path := DECKS_PATH + file_name
			var deck := load_deck(path)
			var count := count_cards(deck)
			if not deck.empty() and count > 0:
				entries.append({
					"path": path,
					"deck": deck,
					"name": str(deck.get("name", file_name)),
					"count": count,
				})
		file_name = directory.get_next()
	directory.list_dir_end()
	_sort_by_name(entries)
	return entries


static func load_deck(path: String) -> Dictionary:
	if not path.begins_with(DECKS_PATH) or not path.ends_with(".json"):
		return {}
	var file := File.new()
	if not file.file_exists(path):
		return {}
	if file.open(path, File.READ) != OK:
		return {}
	var parsed := JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return {}
	var deck: Dictionary = parsed.result
	if not _is_valid_deck(deck):
		return {}
	return deck


static func count_cards(deck: Dictionary) -> int:
	var cards = deck.get("cards", null)
	if typeof(cards) == TYPE_DICTIONARY:
		var total := 0
		for card_name in cards:
			total += int(cards[card_name])
		return total
	return int(deck.get("total", 0))


static func last_deck_path() -> String:
	return str(cfc.game_settings.get(LAST_DECK_SETTING, ""))


static func load_last_deck() -> Dictionary:
	var path := last_deck_path()
	if path.empty():
		return {}
	return load_deck(path)


static func find_auto_deck() -> Dictionary:
	var path := last_deck_path()
	if not path.empty():
		var deck := load_deck(path)
		if not deck.empty():
			return {"path": path, "deck": deck}
	var entries := list_decks()
	if entries.size() == 1:
		return entries[0]
	return {}


static func remember_deck(path: String) -> void:
	if path.empty() or last_deck_path() == path:
		return
	cfc.set_setting(LAST_DECK_SETTING, path)


static func apply_definitions(deck: Dictionary) -> void:
	var definitions = deck.get("definitions", {})
	if typeof(definitions) != TYPE_DICTIONARY:
		return
	for card_name in definitions:
		if typeof(definitions[card_name]) == TYPE_DICTIONARY:
			cfc.card_definitions[str(card_name)] = definitions[card_name]


static func _is_valid_deck(deck: Dictionary) -> bool:
	var cards = deck.get("cards", null)
	if typeof(cards) != TYPE_DICTIONARY or cards.empty():
		return false
	for card_name in cards:
		if str(card_name).empty() or int(cards[card_name]) <= 0:
			return false
	var definitions = deck.get("definitions", null)
	if definitions != null and typeof(definitions) != TYPE_DICTIONARY:
		return false
	return true


static func _sort_by_name(entries: Array) -> void:
	for index in range(1, entries.size()):
		var current: Dictionary = entries[index]
		var position := index - 1
		while position >= 0 and str(entries[position]["name"]).to_lower() \
				> str(current["name"]).to_lower():
			entries[position + 1] = entries[position]
			position -= 1
		entries[position + 1] = current
