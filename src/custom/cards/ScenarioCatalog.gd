# Catálogo dos cenários reais do BS.
#
# Os dados ficam em `ScenarioCatalogData.gd`, gerado do BSDB por
# `.run/gen_scenario_catalog.js`. Este script é a API: resolve a entrada de uma
# carta, o nome impresso e os trechos que a mesa ainda não automatiza.
class_name ScenarioCatalog
extends RefCounted

const Data = preload("res://src/custom/cards/ScenarioCatalogData.gd")

const BY_ID = Data.BY_ID

# The printed name is the fallback for a card whose definition arrived without
# the `_bsdb_id`. Nine duplicated names carry different texts, so the index only
# answers for names that point to a single entry.
static var _name_index := {}


static func entry_for(card) -> Dictionary:
	if not is_instance_valid(card):
		return {}
	var properties: Dictionary = card.properties
	var id := str(properties.get("_bsdb_id", ""))
	if not id.is_empty() and BY_ID.has(id):
		return BY_ID[id]
	var printed := str(properties.get("Name", ""))
	if printed.is_empty():
		return {}
	var index := _name_map()
	if index.has(printed) and index[printed] != null:
		return BY_ID[str(index[printed])]
	return {}


static func _name_map() -> Dictionary:
	if not _name_index.is_empty():
		return _name_index
	for key in BY_ID:
		var printed := str(BY_ID[key].get("name", ""))
		if printed.is_empty():
			continue
		if _name_index.has(printed):
			_name_index[printed] = null
		else:
			_name_index[printed] = key
	return _name_index


static func display_name(card, entry := {}) -> String:
	var data: Dictionary = entry
	if data.is_empty():
		data = entry_for(card)
	if not data.is_empty():
		return str(data.get("name", ""))
	if is_instance_valid(card):
		var printed := str(card.properties.get("Name", ""))
		if not printed.is_empty():
			return printed
		return str(card.canonical_name)
	return ""


static func is_negation(card) -> bool:
	return bool(entry_for(card).get("negation", false))


static func pending_of(card) -> Array:
	return entry_for(card).get("pending", [])


# The pending fragments that belong to the exit: only the ones that name the
# scenario leaving. The rest was already shown when it entered.
static func pending_leave_of(card) -> Array:
	var found := []
	for fragment in pending_of(card):
		if str(fragment).to_lower().find("sair") >= 0:
			found.append(fragment)
	return found
