# Pure data model of the table.
#
# `TableSnapshot` reads the scene; `TableState` is the owner of the same
# information in data form: one address per card, zones per seat, a shared
# scenario and no nodes. F1 keeps it behaviour-neutral: it is built from a
# snapshot, can be compared back with the table and already knows the placement
# rules (hand order, field growth, visible resources and prizes), but nothing in
# the game uses it yet.
#
# Addresses:
#   mesa:cenário
#   p1:mão:1 … N
#   p1:campo:frente:1 … N / p1:campo:trás:1 … N
#   p1:recursos:1 … 6 / p1:recursos:pilha:1 … n
#   p1:prêmios:1 … 4
#   p1:deck:1 … N            (1 = topo)
#   anexo:p1:<endereço do hospedeiro>:1 … n
class_name TableState
extends Reference

const _Snapshot = preload("res://src/core/table/TableSnapshot.gd")

const SEATS := [1, 2]
const ROWS := ["frente", "trás"]
const SCENARIO_ADDRESS := "mesa:cenário"
const TRANSIT_ADDRESS := "em_transito"
const VISIBLE_RESOURCES := 6
const VISIBLE_PRIZES := 4

# Number of columns both field rows have. The field grows by adding columns, and
# the count is shared by the seats because the mirrored band follows the local
# layout.
var columns := 2
# id -> {id, name, definition, type, address, zone, seat, face, rotation,
#        shield, host, kind, attachments, cost}
var cards := {}
# seat -> ordered ids (index 0 = mão:1)
var hand := {}
# seat -> {"frente": [ids], "trás": [ids]}
var field := {}
# seat -> top-first ids (index 0 = recursos:1)
var resources := {}
# seat -> slot-first ids (index 0 = prêmios:1)
var prizes := {}
# seat -> top-first ids (index 0 = deck:1)
var deck := {}
# Shared scenario: a card id or "".
var scenario := ""


func _init() -> void:
	for seat in SEATS:
		_clear_seat(seat)


func clear() -> void:
	cards = {}
	columns = 2
	scenario = ""
	for seat in SEATS:
		_clear_seat(seat)


func _clear_seat(seat : int) -> void:
	hand[seat] = []
	field[seat] = {"frente": [], "trás": []}
	resources[seat] = []
	prizes[seat] = []
	deck[seat] = []
	_resize_rows(seat)


func _resize_rows(seat : int) -> void:
	for row in ROWS:
		var slots: Array = field[seat][row]
		while slots.size() < columns:
			slots.append("")
		while slots.size() > columns:
			var last = slots.pop_back()
			if last != "" and cards.has(last):
				cards[last]["address"] = ""
			field[seat][row] = slots


# -----------------------------------------------------------------------------
# Construction
# -----------------------------------------------------------------------------

func load_board(board : Node = null, seat := -1) -> void:
	load_snapshot(_Snapshot.capture(board, seat))


# Rebuilds the state from a snapshot. Attachments are loaded after every other
# zone so their hosts already have an address.
func load_snapshot(snapshot : Dictionary) -> void:
	clear()
	var zones: Dictionary = snapshot.get("zones", {})
	var field_summary: Dictionary = zones.get("field", {})
	if int(field_summary.get("columns", 0)) > 0:
		columns = int(field_summary["columns"])
		for seat in SEATS:
			_resize_rows(seat)
	var snapshot_cards: Dictionary = snapshot.get("cards", {})
	var pending := []
	for id in snapshot_cards:
		var entry: Dictionary = snapshot_cards[id]
		if str(entry.get("zone", "")) == "attachment":
			pending.append(id)
			continue
		_load_card(str(id), entry)
	for id in pending:
		_load_card(str(id), snapshot_cards[id])


func _load_card(id : String, entry : Dictionary) -> void:
	var address := str(entry.get("address", ""))
	var parsed := parse_address(address)
	var seat := int(parsed.get("seat", 0))
	var kind := str(parsed.get("kind", ""))
	var state_entry := {
		"id": id,
		"name": str(entry.get("name", "")),
		"definition": str(entry.get("definition", "")),
		"type": str(entry.get("type", "")),
		"address": address,
		"zone": str(entry.get("zone", "")),
		"seat": seat,
		"face": str(entry.get("face", "up")),
		"rotation": int(entry.get("rotation", 0)),
		"shield": int(entry.get("shield", 0)),
		"cost": int(entry.get("cost", 0)),
		"host": "",
		"kind": "",
		"attachments": [],
	}
	cards[id] = state_entry
	match kind:
		"hand":
			_list_set(hand, seat, int(parsed.get("slot", 0)) - 1, id)
		"field":
			var row := str(parsed.get("row", "frente"))
			if not field[seat].has(row):
				row = "frente"
			var column := int(parsed.get("column", 0)) - 1
			if column >= columns:
				columns = column + 1
				for each in SEATS:
					_resize_rows(each)
			field[seat][row][column] = id
		"resources":
			_list_set(resources, seat, int(parsed.get("slot", 0)) - 1, id)
		"prizes":
			_list_set(prizes, seat, int(parsed.get("slot", 0)) - 1, id)
		"deck":
			_list_set(deck, seat, int(parsed.get("slot", 0)) - 1, id)
		"scenario":
			scenario = id
		"attachment":
			_attach_loaded(id, str(parsed.get("host_address", "")),
					int(parsed.get("index", 0)))
		"transit":
			state_entry["address"] = TRANSIT_ADDRESS


func _attach_loaded(id : String, host_address : String, index : int) -> void:
	var host_id := _id_at_address(host_address)
	var entry: Dictionary = cards[id]
	entry["host"] = host_id
	entry["kind"] = _kind_of(entry)
	if host_id.empty() or not cards.has(host_id):
		# Without a host the attachment has no place in the state; it keeps its
		# card entry so the totals still add up and compare_with reports it.
		entry["zone"] = "attachment"
		return
	var host: Dictionary = cards[host_id]
	if index <= 0:
		index = host["attachments"].size() + 1
	_list_put_array(host["attachments"], index - 1, id)


# -----------------------------------------------------------------------------
# Queries
# -----------------------------------------------------------------------------

func address_of(id : String) -> String:
	if not cards.has(id):
		return ""
	return str(cards[id]["address"])


func zone_of(id : String) -> String:
	if not cards.has(id):
		return ""
	return str(cards[id]["zone"])


# Returns the id of the card at an address, or an empty string. Addresses are
# unique by construction, so this is the reverse of `address_of()`.
func card_at(address : String) -> String:
	return _id_at_address(address)


func type_of(id : String) -> String:
	if not cards.has(id):
		return ""
	return str(cards[id]["type"])


func card_count() -> int:
	return cards.size()


func zone_counts(seat := 1) -> Dictionary:
	return {
		"hand": _seat_zone_count(seat, "hand"),
		"field": _seat_zone_count(seat, "field"),
		"scenario": 0 if scenario.empty() else 1,
		"resources": _seat_zone_count(seat, "resources"),
		"prizes": _seat_zone_count(seat, "prizes"),
		"deck": _seat_zone_count(seat, "deck"),
		"attachments": _count_zone_all("attachment"),
		"transit": _count_zone_all("transit"),
	}


func visible_resources(seat : int) -> Array:
	return _head(resources[seat], VISIBLE_RESOURCES)


func visible_prizes(seat : int) -> Array:
	return _head(prizes[seat], VISIBLE_PRIZES)


func top_of_deck(seat : int) -> String:
	if deck_count(seat) == 0:
		return ""
	return str(deck[seat][0])


# The stacks keep an empty placeholder while they are rebuilt, so a count by
# array size could include holes. These count the ids that really fill a slot.
func deck_count(seat : int) -> int:
	return _filled(deck.get(seat, [])).size()


func resource_count(seat : int) -> int:
	return _filled(resources.get(seat, [])).size()


func prize_count(seat : int) -> int:
	return _filled(prizes.get(seat, [])).size()


func hand_count(seat : int) -> int:
	return _filled(hand.get(seat, [])).size()


func _filled(list : Array) -> Array:
	var ids := []
	for id in list:
		if str(id) != "":
			ids.append(id)
	return ids


func next_prize_slot(seat : int) -> int:
	return prize_count(seat) + 1


# First free field slot following the confirmed rule: front row, from the
# center outwards; back row when the front is full; a new column when both rows
# are full. Supports go to the back row when the front already has a character.
#
# `grow` is false for validation: rules must not change the state while only
# asking where a card would go. In that case an empty string means the field is
# full and the caller may grow it as part of the action.
func find_field_slot(seat : int, prefer_back := false, grow := true) -> String:
	var rows := ROWS.duplicate()
	if prefer_back and _front_has_character(seat):
		rows.invert()
	var order := _center_out(columns)
	for row in rows:
		for column in order:
			if str(field[seat][row][column]) == "":
				return field_address(seat, str(row), column + 1)
	if not grow:
		return ""
	grow_field()
	return field_address(seat, "frente", columns)


func grow_field() -> void:
	columns += 1
	for seat in SEATS:
		_resize_rows(seat)


func set_columns(value : int) -> void:
	columns = int(max(1, value))
	for seat in SEATS:
		_resize_rows(seat)


func field_free_slots(seat : int) -> int:
	var free := 0
	for row in ROWS:
		for id in field[seat][row]:
			if id == "":
				free += 1
	return free


# -----------------------------------------------------------------------------
# Mutation primitives
# -----------------------------------------------------------------------------

# Moves a card to an address. The destination must be free, except for the card
# itself; rules that replace or cascade (scenario replacement, prizes, payments)
# belong to TableActions and compose several calls to this primitive.
func place(id : String, address : String) -> bool:
	if not cards.has(id):
		return false
	var parsed := parse_address(address)
	var kind := str(parsed.get("kind", ""))
	if kind.empty():
		return false
	if not _destination_is_free(id, kind, parsed):
		return false
	var seat := int(parsed.get("seat", 0))
	_detach(id)
	match kind:
		"hand":
			_list_put(hand, seat, int(parsed["slot"]) - 1, id)
			_set_zone(id, "hand", seat, address)
			_refresh_hand_addresses(seat)
		"field":
			var row := str(parsed["row"])
			var column := int(parsed["column"]) - 1
			if column >= columns:
				columns = column + 1
				for each in SEATS:
					_resize_rows(each)
			field[seat][row][column] = id
			_set_zone(id, "field", seat, address)
		"resources":
			_list_put(resources, seat, int(parsed["slot"]) - 1, id)
			_set_zone(id, "resources", seat, address)
			_refresh_resource_addresses(seat)
		"prizes":
			_list_put(prizes, seat, int(parsed["slot"]) - 1, id)
			_set_zone(id, "prizes", seat, address)
			_refresh_prize_addresses(seat)
		"deck":
			_list_put(deck, seat, int(parsed["slot"]) - 1, id)
			_set_zone(id, "deck", seat, address)
			_refresh_deck_addresses(seat)
		"scenario":
			scenario = id
			_set_zone(id, "scenario", 0, SCENARIO_ADDRESS)
		"attachment":
			var host_id := _id_at_address(str(parsed["host_address"]))
			if host_id.empty():
				return false
			var host: Dictionary = cards[host_id]
			var index := int(parsed["index"]) - 1
			_list_put_array(host["attachments"], index, id)
			cards[id]["host"] = host_id
			cards[id]["kind"] = _kind_of(cards[id])
			_set_zone(id, "attachment", int(host["seat"]),
					_attachment_address(host_id, index + 1))
			_refresh_attachment_addresses(host_id)
		"transit":
			_set_zone(id, "transit", 0, TRANSIT_ADDRESS)
		_:
			return false
	return true


func draw_top(seat : int) -> String:
	if deck_count(seat) == 0:
		return ""
	var id := str(deck[seat][0])
	place(id, hand_address(seat, 1))
	return id


func mill_top_to_resources(seat : int) -> String:
	if deck_count(seat) == 0:
		return ""
	var id := str(deck[seat][0])
	place(id, resource_address(seat, 1))
	return id


func reorder_hand(seat : int, from_slot : int, to_slot : int) -> bool:
	var ids: Array = hand[seat]
	var from_index := from_slot - 1
	var to_index := to_slot - 1
	if from_index < 0 or from_index >= ids.size() \
			or to_index < 0 or to_index >= ids.size():
		return false
	var id := str(ids[from_index])
	ids.remove(from_index)
	ids.insert(to_index, id)
	_refresh_hand_addresses(seat)
	return true


func remove_card(id : String) -> void:
	if cards.has(id):
		_detach(id)
		cards.erase(id)


# -----------------------------------------------------------------------------
# Comparison with the scene
# -----------------------------------------------------------------------------

# Compares the state with a snapshot of the same table. Both directions are
# checked, so a card missing on either side shows up; a moved card is reported
# even when the totals still match.
func compare_with(snapshot : Dictionary) -> Array:
	var issues := []
	var snapshot_cards: Dictionary = snapshot.get("cards", {})
	for id in snapshot_cards:
		var table_address := str(snapshot_cards[id].get("address", ""))
		if not cards.has(id):
			issues.append({
				"type": "faltando_no_estado",
				"card": str(id),
				"address": table_address,
			})
			continue
		var state_address := address_of(str(id))
		if state_address != table_address:
			issues.append({
				"type": "endereco_divergente",
				"card": str(id),
				"estado": state_address,
				"mesa": table_address,
			})
	for id in cards:
		if not snapshot_cards.has(id):
			issues.append({
				"type": "sobrando_no_estado",
				"card": str(id),
				"address": address_of(str(id)),
			})
	var seat := int(snapshot.get("viewer_seat", snapshot.get("seat", 1)))
	var state_counts := zone_counts(seat)
	var table_zones: Dictionary = snapshot.get("zones", {})
	for zone in ["hand", "field", "scenario", "resources", "prizes", "deck"]:
		var declared := int(table_zones.get(zone, {}).get("count", 0))
		if int(state_counts[zone]) != declared:
			issues.append({
				"type": "contagem_divergente",
				"zone": zone,
				"estado": int(state_counts[zone]),
				"mesa": declared,
			})
	for pair in [["attachments", "attachments"], ["transit", "transit"]]:
		var declared := int(table_zones.get(pair[1], 0))
		if int(state_counts[pair[0]]) != declared:
			issues.append({
				"type": "contagem_divergente",
				"zone": pair[0],
				"estado": int(state_counts[pair[0]]),
				"mesa": declared,
			})
	return issues


func to_snapshot(seat := 0) -> Dictionary:
	var viewer := seat
	if viewer <= 0:
		viewer = _first_seat_with_cards()
	var counts := zone_counts(viewer)
	var zones := {
		"hand": {"count": counts["hand"], "slots": hand[viewer].size()},
		"field": {
			"count": counts["field"],
			"columns": columns,
			"slots": columns * ROWS.size(),
			"free": field_free_slots(viewer),
		},
		"scenario": {"count": counts["scenario"], "id": scenario},
		"resources": {
			"count": counts["resources"],
			"visible": int(min(int(counts["resources"]), VISIBLE_RESOURCES)),
		},
		"prizes": {
			"count": counts["prizes"],
			"visible": int(min(int(counts["prizes"]), VISIBLE_PRIZES)),
		},
		"deck": {"count": counts["deck"], "top": top_of_deck(viewer)},
		"attachments": counts["attachments"],
		"transit": counts["transit"],
	}
	return {
		"seat": viewer,
		"viewer_seat": viewer,
		"mode": "estado",
		"cards": cards,
		"zones": zones,
		"issues": [],
		"total": cards.size(),
	}


func describe(seat := 0) -> String:
	return _Snapshot.describe(to_snapshot(seat))


# -----------------------------------------------------------------------------
# Address helpers
# -----------------------------------------------------------------------------

static func hand_address(seat : int, slot : int) -> String:
	return "p" + str(seat) + ":mão:" + str(slot)


static func field_address(seat : int, row : String, column : int) -> String:
	return "p" + str(seat) + ":campo:" + row + ":" + str(column)


static func resource_address(seat : int, slot : int) -> String:
	if slot <= VISIBLE_RESOURCES:
		return "p" + str(seat) + ":recursos:" + str(slot)
	return "p" + str(seat) + ":recursos:pilha:" \
			+ str(slot - VISIBLE_RESOURCES)


static func prize_address(seat : int, slot : int) -> String:
	return "p" + str(seat) + ":prêmios:" + str(slot)


static func deck_address(seat : int, slot : int) -> String:
	return "p" + str(seat) + ":deck:" + str(slot)


static func _seat_from_prefix(prefix : String) -> int:
	if prefix.begins_with("p") and prefix.substr(1).is_valid_integer():
		return int(prefix.substr(1))
	return 0


static func parse_address(address : String) -> Dictionary:
	var parts := Array(address.split(":"))
	if parts[0] == "em_transito":
		return {"kind": "transit"}
	if parts.size() < 2:
		return {}
	if parts[0] == "mesa" and parts[1] == "cenário":
		return {"kind": "scenario"}
	if parts[0] == "anexo" and parts.size() >= 3:
		var index := int(parts[parts.size() - 1])
		var host_parts := []
		# Godot 3's Array.slice includes the end index; the loop is explicit so
		# the host address keeps exactly the parts between the prefix and index.
		for position in range(2, parts.size() - 1):
			host_parts.append(str(parts[position]))
		return {
			"kind": "attachment",
			"seat": _seat_from_prefix(parts[1]),
			"host_address": PoolStringArray(host_parts).join(":"),
			"index": index,
		}
	var seat := _seat_from_prefix(parts[0])
	if seat <= 0 or parts.size() < 2:
		return {}
	match parts[1]:
		"mão":
			if parts.size() < 3:
				return {}
			return {"kind": "hand", "seat": seat, "slot": int(parts[2])}
		"campo":
			if parts.size() < 4:
				return {}
			return {
				"kind": "field",
				"seat": seat,
				"row": parts[2],
				"column": int(parts[3]),
			}
		"recursos":
			if parts.size() == 4 and parts[2] == "pilha":
				return {
					"kind": "resources",
					"seat": seat,
					"slot": VISIBLE_RESOURCES + int(parts[3]),
				}
			if parts.size() < 3:
				return {}
			return {"kind": "resources", "seat": seat, "slot": int(parts[2])}
		"prêmios":
			if parts.size() < 3:
				return {}
			return {"kind": "prizes", "seat": seat, "slot": int(parts[2])}
		"deck":
			if parts.size() < 3:
				return {}
			var slot_text := str(parts[2])
			if slot_text == "topo":
				return {"kind": "deck", "seat": seat, "slot": 1}
			return {"kind": "deck", "seat": seat, "slot": int(slot_text)}
	return {}


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------

func _destination_is_free(id : String, kind : String, parsed : Dictionary) \
		-> bool:
	match kind:
		"field":
			var seat := int(parsed["seat"])
			var row := str(parsed["row"])
			if not field.has(seat) or not field[seat].has(row):
				return false
			var column := int(parsed["column"]) - 1
			if column < 0:
				return false
			if column >= columns:
				return true
			var occupant = field[seat][row][column]
			return occupant == "" or str(occupant) == id
		"prizes":
			var seat := int(parsed["seat"])
			var index := int(parsed["slot"]) - 1
			var slots: Array = prizes[seat]
			if index < 0 or index >= slots.size():
				return true
			return str(slots[index]) == id or str(slots[index]) == ""
		"scenario":
			return scenario.empty() or scenario == id
		"attachment":
			var host_id := _id_at_address(str(parsed.get("host_address", "")))
			return not host_id.empty()
	return true


func _detach(id : String) -> void:
	if not cards.has(id):
		return
	var entry: Dictionary = cards[id]
	var zone := str(entry["zone"])
	var seat := int(entry["seat"])
	match zone:
		"hand":
			if hand.has(seat):
				hand[seat].erase(id)
				_refresh_hand_addresses(seat)
		"field":
			if field.has(seat):
				for row in ROWS:
					var slots: Array = field[seat][row]
					var index := slots.find(id)
					if index >= 0:
						slots[index] = ""
		"resources":
			if resources.has(seat):
				resources[seat].erase(id)
				_refresh_resource_addresses(seat)
		"prizes":
			if prizes.has(seat):
				prizes[seat].erase(id)
				_refresh_prize_addresses(seat)
		"deck":
			if deck.has(seat):
				deck[seat].erase(id)
				_refresh_deck_addresses(seat)
		"scenario":
			if scenario == id:
				scenario = ""
		"attachment":
			var host_id := str(entry["host"])
			if cards.has(host_id):
				var host: Dictionary = cards[host_id]
				host["attachments"].erase(id)
				_refresh_attachment_addresses(host_id)
			entry["host"] = ""
			entry["kind"] = ""
	entry["address"] = ""


func _set_zone(id : String, zone : String, seat : int, address : String) -> void:
	var entry: Dictionary = cards[id]
	entry["zone"] = zone
	entry["seat"] = seat
	entry["address"] = address


func _refresh_hand_addresses(seat : int) -> void:
	var ids: Array = hand[seat]
	for index in range(ids.size()):
		var id = ids[index]
		if id != "" and cards.has(id):
			cards[id]["address"] = hand_address(seat, index + 1)


func _refresh_resource_addresses(seat : int) -> void:
	var ids: Array = resources[seat]
	for index in range(ids.size()):
		var id = ids[index]
		if id != "" and cards.has(id):
			cards[id]["address"] = resource_address(seat, index + 1)


func _refresh_prize_addresses(seat : int) -> void:
	var ids: Array = prizes[seat]
	for index in range(ids.size()):
		var id = ids[index]
		if id != "" and cards.has(id):
			cards[id]["address"] = prize_address(seat, index + 1)


func _refresh_deck_addresses(seat : int) -> void:
	var ids: Array = deck[seat]
	for index in range(ids.size()):
		var id = ids[index]
		if id != "" and cards.has(id):
			cards[id]["address"] = deck_address(seat, index + 1)


func _refresh_attachment_addresses(host_id : String) -> void:
	if not cards.has(host_id):
		return
	var host: Dictionary = cards[host_id]
	var host_address := str(host["address"])
	var seat := int(host["seat"])
	var attachments: Array = host["attachments"]
	for index in range(attachments.size()):
		var id = attachments[index]
		if id == "" or not cards.has(id):
			continue
		cards[id]["address"] = "anexo:p" + str(seat) + ":" + host_address \
				+ ":" + str(index + 1)


func _attachment_address(host_id : String, index : int) -> String:
	var host: Dictionary = cards[host_id]
	return "anexo:p" + str(host["seat"]) + ":" + str(host["address"]) \
			+ ":" + str(index)


func _kind_of(entry : Dictionary) -> String:
	if str(entry.get("type", "")) == "Habilidade":
		return "ability"
	return "resource"


func _id_at_address(address : String) -> String:
	if address.empty():
		return ""
	for id in cards:
		if str(cards[id]["address"]) == address:
			return str(id)
	return ""


func _seat_zone_count(seat : int, zone : String) -> int:
	var count := 0
	for id in cards:
		if int(cards[id]["seat"]) == seat and str(cards[id]["zone"]) == zone:
			count += 1
	return count


func _count_zone_all(zone : String) -> int:
	var count := 0
	for id in cards:
		if str(cards[id]["zone"]) == zone:
			count += 1
	return count


func _first_seat_with_cards() -> int:
	for seat in SEATS:
		for id in cards:
			if int(cards[id]["seat"]) == seat:
				return seat
	return 1


func _front_has_character(seat : int) -> bool:
	for id in field[seat]["frente"]:
		if id != "" and cards.has(id) \
				and str(cards[id]["type"]) == "Personagem":
			return true
	return false


func _center_out(columns_count : int) -> Array:
	var order := []
	var left := int(floor((columns_count - 1) * 0.5))
	var right := int(ceil((columns_count - 1) * 0.5))
	var offset := 0
	while order.size() < columns_count:
		var left_column := left - offset
		var right_column := right + offset
		if left_column >= 0 and not order.has(left_column):
			order.append(left_column)
		if right_column < columns_count and not order.has(right_column):
			order.append(right_column)
		offset += 1
	return order


func _list_put(store : Dictionary, seat : int, index : int, id : String) -> void:
	if not store.has(seat):
		store[seat] = []
	_list_put_array(store[seat], index, id)


# Used while building the state from a snapshot. The snapshot numbers piles
# from the top, so a pile's cards arrive in descending slot order; inserting
# them would shift the cards already loaded and leave empty holes. Loading is a
# placement, not an insertion: every slot holds exactly the address it names.
func _list_set(store : Dictionary, seat : int, index : int, id : String) -> void:
	if not store.has(seat):
		store[seat] = []
	var list: Array = store[seat]
	if index < 0:
		index = list.size()
	while list.size() <= index:
		list.append("")
	list[index] = id


func _head(list : Array, limit : int) -> Array:
	var result := []
	for index in range(int(min(list.size(), limit))):
		result.append(list[index])
	return result


func _list_put_array(list : Array, index : int, id : String) -> void:
	if index < 0:
		index = list.size()
	while list.size() < index:
		list.append("")
	if index >= list.size():
		list.append(id)
	else:
		list.insert(index, id)
