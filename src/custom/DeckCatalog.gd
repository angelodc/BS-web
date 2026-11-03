extends RefCounted

const DECKS_PATH := "user://Decks/"
const LAST_DECK_SETTING := "last_deck_path"
const SEAT_DECK_SETTING := "last_solo_deck_path_"
# The published build ships one ready deck so a new player can start without
# importing a link first. It is a plain JSON of about 24 KB, nothing next to the
# HTML5 build; the link in the file is metadata and the card data is what lets
# the deck play without the BSDB.
const DEFAULT_DECK_PATH := "res://data/decks/aliados_homem_aranha.json"
const DEFAULT_DECK_FILE := "aliados_homem_aranha.json"
const DEFAULT_DECK_SEEDED := "default_deck_seeded"


# Copies the bundled deck into the local catalog once, and only when the player
# has no decks at all. The flag makes a later deletion stick instead of bringing
# the deck back on every launch.
static func ensure_default_deck() -> void:
	if bool(cfc.game_settings.get(DEFAULT_DECK_SEEDED, false)):
		return
	if not list_decks().is_empty():
		cfc.set_setting(DEFAULT_DECK_SEEDED, true)
		return
	if not FileAccess.file_exists(DEFAULT_DECK_PATH):
		return
	var source := FileAccess.open(DEFAULT_DECK_PATH, FileAccess.READ)
	if source == null:
		return
	var text := source.get_as_text()
	source.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DECKS_PATH))
	var target := FileAccess.open(DECKS_PATH + DEFAULT_DECK_FILE, FileAccess.WRITE)
	if target == null:
		return
	target.store_string(text)
	target.close()
	cfc.set_setting(DEFAULT_DECK_SEEDED, true)


static func list_decks() -> Array:
	var entries := []
	var directory := DirAccess.open(DECKS_PATH)
	if directory == null:
		return entries
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			var path := DECKS_PATH + file_name
			var deck := load_deck(path)
			var count := count_cards(deck)
			if not deck.is_empty() and count > 0:
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
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var test_json_conv = JSON.new()
	var parse_error := test_json_conv.parse(file.get_as_text())
	var parsed = test_json_conv.get_data()
	file.close()
	if parse_error != OK or typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var deck: Dictionary = parsed
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
	if path.is_empty():
		return {}
	return load_deck(path)


static func find_auto_deck() -> Dictionary:
	var path := last_deck_path()
	if not path.is_empty():
		var deck := load_deck(path)
		if not deck.is_empty():
			return {"path": path, "deck": deck}
	var entries := list_decks()
	if entries.size() == 1:
		return entries[0]
	return {}


static func remember_deck(path: String) -> void:
	if path.is_empty() or last_deck_path() == path:
		return
	cfc.set_setting(LAST_DECK_SETTING, path)


static func seat_deck_path(slot: int) -> String:
	if slot < 1 or slot > 2:
		return ""
	return str(cfc.game_settings.get(SEAT_DECK_SETTING + str(slot), ""))


# The hotseat preparation fills one deck button per seat, so each seat keeps its
# own last deck. Seat two falls back to seat one's pick, which keeps both
# buttons filled on the first run instead of leaving the table half chosen.
static func find_seat_deck(slot: int) -> Dictionary:
	var path := seat_deck_path(slot)
	if not path.is_empty():
		var deck := load_deck(path)
		if not deck.is_empty():
			return {"path": path, "deck": deck}
	if slot == 2:
		var first := find_seat_deck(1)
		if not first.is_empty():
			return first
	return find_auto_deck()


static func remember_seat_deck(slot: int, path: String) -> void:
	if path.is_empty() or seat_deck_path(slot) == path:
		return
	cfc.set_setting(SEAT_DECK_SETTING + str(slot), path)


static func apply_definitions(deck: Dictionary) -> void:
	var definitions = deck.get("definitions", {})
	if typeof(definitions) != TYPE_DICTIONARY:
		return
	for card_name in definitions:
		if typeof(definitions[card_name]) == TYPE_DICTIONARY:
			cfc.card_definitions[str(card_name)] = definitions[card_name]


static func _is_valid_deck(deck: Dictionary) -> bool:
	var cards = deck.get("cards", null)
	if typeof(cards) != TYPE_DICTIONARY or cards.is_empty():
		return false
	for card_name in cards:
		if str(card_name).is_empty() or int(cards[card_name]) <= 0:
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
