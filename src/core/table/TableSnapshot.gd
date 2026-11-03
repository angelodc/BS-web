# Read-only snapshot of the table as it exists in the scene tree.
#
# This is the first step of the "actions without mouse" model: before any
# button, drag or script starts sharing an intent API, the current table has to
# be describable as data. The snapshot gives every card one address (zone +
# slot), derives the zone counts from those addresses and reports the places
# where the scene tree disagrees with itself.
#
# It never changes the table: no node is created, moved or freed, and no
# network id is generated. It is meant to be called from tests and from the
# future TableState comparison.
class_name TableSnapshot
extends RefCounted

const SCENARIO_ADDRESS := "mesa:cenário"
const TRANSIT_ADDRESS := "em_transito"
const RESOURCE_VISIBLE_SLOTS := 6
const PRIZE_VISIBLE_SLOTS := 4
const ZONE_ORDER := [
	"hand", "field", "scenario", "resources", "prizes", "deck",
	"attachment", "transit"
]
const ZONE_LABELS := {
	"hand": "mão",
	"field": "campo",
	"scenario": "cenário",
	"resources": "recursos",
	"prizes": "prêmios",
	"deck": "deck",
	"attachment": "anexos",
	"transit": "em trânsito",
}
# Piles keep the English zone name internally (it matches the older scripts),
# but their addresses use the Portuguese name the players type.
const ZONE_ADDRESS_NAMES := {
	"resources": "recursos",
	"prizes": "prêmios",
	"attachment": "anexo",
	"transit": "em_transito",
}


# Builds the snapshot for the local board.
#
# `seat` is the seat the snapshot is written for. Negative values ask the
# current local seat from Multiplayer; outside a match that becomes P1.
static func capture(board : Node = null, seat := -1) -> Dictionary:
	var table : Node = board
	if not is_instance_valid(table):
		table = cfc.NMAP.get("board", null)
	var viewer_seat := seat
	if viewer_seat < 0:
		viewer_seat = int(Multiplayer.my_slot)
		if viewer_seat <= 0:
			viewer_seat = 1
	var prefix := "p" + str(viewer_seat)
	var cards := {}
	var nodes := {}
	var addresses := {}
	var issues := []

	var field_grid := _field_grid(table)
	var scenario_grid := _scenario_grid(table, field_grid)
	var hand := _container(table, "Hand", "hand")
	var deck := _container(table, "Deck", "deck")
	var resources := _container(table, "Discard", "discard")
	var prizes := _container(table, "Prêmios", "prêmios")

	_read_field(
			field_grid, prefix, cards, nodes, addresses, issues)
	_read_scenario(
			scenario_grid, cards, nodes, addresses, issues)
	_read_hand(hand, prefix, cards, nodes, addresses, issues)
	_read_pile(prizes, "prizes", prefix, PRIZE_VISIBLE_SLOTS,
			cards, nodes, addresses, issues)
	_read_pile(resources, "resources", prefix, RESOURCE_VISIBLE_SLOTS,
			cards, nodes, addresses, issues)
	var deck_top := _read_deck(deck, prefix, cards, nodes, addresses, issues)
	_read_attachments(prefix, cards, nodes, addresses, issues)
	_read_transit(table, cards, addresses, issues)

	var zones := {
		"hand": {
			"count": _count_zone(cards, "hand"),
			"slots": _ordered_cards(hand).size(),
		},
		"field": _zone_summary(field_grid, cards),
		"scenario": _scenario_summary(cards),
		"resources": _pile_summary(
				cards, "resources", RESOURCE_VISIBLE_SLOTS, resources),
		"prizes": _pile_summary(
				cards, "prizes", PRIZE_VISIBLE_SLOTS, prizes),
		"deck": {
			"count": _count_zone(cards, "deck"),
			"top": deck_top,
		},
		"attachments": _count_zone(cards, "attachment"),
		"transit": _count_zone(cards, "transit"),
	}

	_check_resource_count(table, zones, issues)
	_check_counts(cards, zones, issues)

	return {
		"seat": viewer_seat,
		"viewer_seat": viewer_seat,
		"mode": "local",
		"cards": cards,
		# id -> Card node. `cards` is enough for the state; actions need the
		# node to move it, and the future renderer needs it to reconcile.
		"nodes": nodes,
		"zones": zones,
		"issues": issues,
		"total": cards.size(),
	}


# Returns a compact text dump of a snapshot, for test failures and the future
# text console.
static func describe(snapshot := {}) -> String:
	if not (snapshot is Dictionary) or snapshot.is_empty():
		return "(snapshot vazio)"
	var cards: Dictionary = snapshot.get("cards", {})
	var zones: Dictionary = snapshot.get("zones", {})
	var lines := []
	lines.append("Mesa — visão P" + str(snapshot.get("viewer_seat", "?")))
	for zone in ZONE_ORDER:
		var ids := _sorted_ids_in_zone(cards, zone)
		if ids.is_empty() and zone != "scenario":
			continue
		var header: String = str(ZONE_LABELS.get(zone, zone)) \
				+ " (" + str(ids.size()) + ")"
		match zone:
			"field":
				var field_summary: Dictionary = zones.get("field", {})
				header += " · " + str(field_summary.get("free", 0)) \
						+ " livres · " + str(field_summary.get("columns", 0)) \
						+ " colunas"
			"resources":
				var resource_summary: Dictionary = zones.get("resources", {})
				header += " · " + str(resource_summary.get("visible", 0)) \
						+ " na grade"
			"prizes":
				var prize_summary: Dictionary = zones.get("prizes", {})
				header += " · " + str(prize_summary.get("visible", 0)) \
						+ " na grade"
			"deck":
				var deck_summary: Dictionary = zones.get("deck", {})
				header += " · topo " + _describe_top(
						cards, str(deck_summary.get("top", "")))
		if ids.is_empty():
			lines.append(header + ": —")
			continue
		var entries := PackedStringArray()
		for id in ids:
			entries.append(_describe_card(cards[id]))
		lines.append(header + ": " + " | ".join(entries))
	var issues: Array = snapshot.get("issues", [])
	if not issues.is_empty():
		lines.append("avisos (" + str(issues.size()) + "):")
		for issue in issues:
			lines.append("  - " + _describe_issue(issue))
	return "\n".join(PackedStringArray(lines))


static func _describe_card(entry: Dictionary) -> String:
	var text := str(entry.get("address", "?")) + " " \
			+ str(entry.get("name", "?"))
	var flags := []
	if str(entry.get("face", "up")) == "down":
		flags.append("virada")
	var rotation := int(entry.get("rotation", 0))
	if rotation != 0:
		flags.append(str(rotation) + "°")
	if int(entry.get("shield", 0)) > 0:
		flags.append("escudo " + str(entry.get("shield")))
	if bool(entry.get("in_transit", false)):
		flags.append("arrastando")
	if not flags.is_empty():
		text += " (" + ", ".join(PackedStringArray(flags)) + ")"
	return text


static func _describe_issue(issue: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in issue:
		parts.append(str(key) + "=" + str(issue[key]))
	return " ".join(parts)


static func _describe_top(cards : Dictionary, top_id : String) -> String:
	if top_id.is_empty():
		return "—"
	if not cards.has(top_id):
		return top_id
	var entry: Dictionary = cards[top_id]
	return str(entry.get("name", top_id)) \
			+ " (" + str(entry.get("address", top_id)) + ")"


# Addresses carry their slot number at the end, so a plain string sort would put
# deck:10 before deck:2. The key zero-pads every numeric part and gives the
# field rows an explicit rank, since "frente" sorts after "trás" as text.
static func _address_sort_key(address : String) -> String:
	var key := ""
	for part in address.split(":"):
		key += _address_part_key(part)
		key += "\u0001"
	return key


static func _address_part_key(part : String) -> String:
	if part.is_valid_int():
		return part.pad_zeros(6)
	if part == "frente":
		return "r000000"
	if part == "trás":
		return "r000001"
	if part.begins_with("linha") and part.substr(5).is_valid_int():
		return "r" + str(int(part.substr(5)) - 1).pad_zeros(6)
	return part


# Godot 3.4 sorts arrays of arrays backwards, so the ordering is done here with
# a plain insertion sort over the (small) zone lists.
static func _sorted_ids_in_zone(cards : Dictionary, zone : String) -> Array:
	var ids := []
	for id in cards:
		if str(cards[id].get("zone", "")) != zone:
			continue
		ids.append(str(id))
	for index in range(1, ids.size()):
		var current: String = ids[index]
		var key := _address_sort_key(str(cards[current].get("address", "")))
		var position := index - 1
		while position >= 0 and _address_sort_key(
				str(cards[ids[position]].get("address", ""))) > key:
			ids[position + 1] = ids[position]
			position -= 1
		ids[position + 1] = current
	return ids


# -----------------------------------------------------------------------------
# Zone discovery
# -----------------------------------------------------------------------------

# Public entry points for the same discovery the snapshot uses. Actions need
# the grids to turn an address into a slot, and the renderer will need them in
# F3, so both keep reading the table through this one place.
static func field_grid(board : Node = null) -> BoardPlacementGrid:
	if not is_instance_valid(board):
		board = cfc.NMAP.get("board", null)
	return _field_grid(board)


static func scenario_grid(board : Node = null) -> BoardPlacementGrid:
	if not is_instance_valid(board):
		board = cfc.NMAP.get("board", null)
	return _scenario_grid(board, _field_grid(board))


# Address of a board slot as seen by `seat`, or "" when the node is not a slot
# of a placement grid. The mouse drop uses it to turn the highlighted slot into
# the destination of an intent.
static func slot_address(slot, seat := 1) -> String:
	return _slot_address(slot, "p" + str(int(seat)))


# The field and the scenario are both BoardPlacementGrids. The field is the
# auto-arranged grid (or the node explicitly named PlacementGridDemo); the
# scenario is the single-slot grid outside it.
static func _field_grid(board : Node) -> BoardPlacementGrid:
	if not is_instance_valid(board):
		return null
	var named = board.get_node_or_null("PlacementGridDemo")
	if named and named is BoardPlacementGrid:
		return named
	for grid in _placement_grids(board):
		if not grid.auto_arrange:
			continue
		if _is_scenario_grid(grid):
			continue
		return grid
	for grid in _placement_grids(board):
		if not _is_scenario_grid(grid):
			return grid
	return null


static func _scenario_grid(board : Node, field_grid: BoardPlacementGrid) \
		-> BoardPlacementGrid:
	if not is_instance_valid(board):
		return null
	var named = board.get_node_or_null("ModifiedLabelGrid")
	if named and named is BoardPlacementGrid:
		return named
	for grid in _placement_grids(board):
		if grid == field_grid:
			continue
		if _is_scenario_grid(grid):
			return grid
	return null


static func _placement_grids(board : Node) -> Array:
	var grids := []
	for grid in board.get_tree().get_nodes_in_group("placement_grid"):
		if grid is BoardPlacementGrid and board.is_ancestor_of(grid):
			grids.append(grid)
	return grids


static func _is_scenario_grid(grid : BoardPlacementGrid) -> bool:
	if grid.name == "ModifiedLabelGrid":
		return true
	if is_instance_valid(grid.name_label) \
			and grid.name_label.text == "Cenário Ativo":
		return true
	return false


static func _container(board : Node, node_name : String, nmap_key : String) \
		-> Node:
	if is_instance_valid(board):
		var direct = board.get_node_or_null(node_name)
		if is_instance_valid(direct):
			return direct
	return cfc.NMAP.get(nmap_key, null)


# Returns the cards of a pile in the order they are stacked, bottom to top.
# While the view popup is open the cards are reparented into it, so the pile's
# remembered order is the only one that still describes the stack.
static func _ordered_cards(container : Node) -> Array:
	var cards := []
	if not is_instance_valid(container):
		return cards
	if container is Pile and container.is_popup_open \
			and not container.pre_sorted_order.is_empty():
		for card in container.pre_sorted_order:
			if is_instance_valid(card) and card is Card:
				cards.append(card)
		return cards
	for child in container.get_children():
		if is_instance_valid(child) and child is Card:
			cards.append(child)
	return cards


# The resource count follows the same stack the snapshot reads, so a card
# parked in the view popup still counts and a card in transit does not. The
# board used to count by node parent, which let the popup and the transit
# disagree with the state.
static func resource_count(pile) -> int:
	return _ordered_cards(pile).size()


# -----------------------------------------------------------------------------
# Zone readers
# -----------------------------------------------------------------------------

static func _read_field(grid, prefix : String, cards : Dictionary,
		nodes : Dictionary, addresses : Dictionary, issues : Array) -> void:
	if not is_instance_valid(grid):
		return
	var slots := _grid_slots(grid)
	var columns := _grid_columns(grid)
	if slots.is_empty():
		return
	for index in range(slots.size()):
		var slot = slots[index]
		if not is_instance_valid(slot):
			continue
		var row := int(index / columns)
		var column := index % columns
		var row_name := "frente"
		if row == 1:
			row_name = "trás"
		elif row > 1:
			row_name = "linha" + str(row + 1)
		var address := prefix + ":campo:" + row_name + ":" + str(column + 1)
		var occupying = slot.occupying_card
		if occupying == null:
			continue
		if not is_instance_valid(occupying) or not (occupying is Card):
			issues.append({
				"type": "slot_com_carta_invalida",
				"slot": address,
			})
			continue
		_register(occupying, address, "field", cards, nodes, addresses, issues)
		if occupying._placement_slot != slot:
			issues.append({
				"type": "slot_divergente",
				"card": _card_id(occupying),
				"slot": address,
				"card_slot": _slot_address(occupying._placement_slot, prefix),
			})


static func _read_scenario(grid, cards : Dictionary, nodes : Dictionary,
		addresses : Dictionary, issues : Array) -> void:
	if not is_instance_valid(grid):
		return
	var slots := _grid_slots(grid)
	var found := 0
	for slot in slots:
		if not is_instance_valid(slot):
			continue
		var occupying = slot.occupying_card
		if occupying == null:
			continue
		if not is_instance_valid(occupying) or not (occupying is Card):
			issues.append({"type": "cenario_invalido"})
			continue
		if found == 0:
			_register(occupying, SCENARIO_ADDRESS, "scenario",
					cards, nodes, addresses, issues)
		else:
			issues.append({
				"type": "cenario_multiplo",
				"card": _card_id(occupying),
			})
		found += 1


static func _read_hand(hand, prefix : String, cards : Dictionary,
		nodes : Dictionary, addresses : Dictionary, issues : Array) -> void:
	var ordered := _ordered_cards(hand)
	for index in range(ordered.size()):
		var card: Card = ordered[index]
		var address := prefix + ":mão:" + str(index + 1)
		_register(card, address, "hand", cards, nodes, addresses, issues)


# Reads a pile from its top down. The visible grid shows the first N cards;
# the rest of the stack keeps an address under the pile name.
static func _read_pile(pile, zone : String, prefix : String,
		visible_slots : int, cards : Dictionary, nodes : Dictionary,
		addresses : Dictionary, issues : Array) -> void:
	var address_name: String = str(ZONE_ADDRESS_NAMES.get(zone, zone))
	var ordered := _ordered_cards(pile)
	for index in range(ordered.size()):
		var card: Card = ordered[index]
		var from_top := ordered.size() - 1 - index
		var address := ""
		if from_top < visible_slots:
			address = prefix + ":" + address_name + ":" + str(from_top + 1)
		else:
			address = prefix + ":" + address_name + ":pilha:" \
					+ str(from_top - visible_slots + 1)
		_register(card, address, zone, cards, nodes, addresses, issues)
		if cards.has(_card_id(card)):
			cards[_card_id(card)]["visible"] = from_top < visible_slots


# Returns the id of the card at the top of the deck, or an empty string.
static func _read_deck(deck, prefix : String, cards : Dictionary,
		nodes : Dictionary, addresses : Dictionary, issues : Array) -> String:
	var top_id := ""
	var ordered := _ordered_cards(deck)
	for index in range(ordered.size()):
		var card: Card = ordered[index]
		var from_top := ordered.size() - 1 - index
		var address := prefix + ":deck:" + str(from_top + 1)
		if _register(card, address, "deck", cards, nodes, addresses, issues) \
				and from_top == 0:
			top_id = _card_id(card)
	return top_id


static func _read_attachments(prefix : String, cards : Dictionary,
		nodes : Dictionary, addresses : Dictionary, issues : Array) -> void:
	var host_ids := nodes.keys()
	for host_id in host_ids:
		var host: Card = nodes[host_id]
		if not is_instance_valid(host):
			continue
		var host_address: String = addresses.get(host_id, "")
		if host_address.is_empty():
			continue
		var seen := []
		for index in range(host.attachments.size()):
			var attachment = host.attachments[index]
			if not is_instance_valid(attachment) or not (attachment is Card):
				issues.append({
					"type": "anexo_invalido",
					"host": host_id,
					"index": index + 1,
				})
				continue
			var attachment_id := _card_id(attachment)
			if seen.has(attachment_id):
				issues.append({
					"type": "anexo_duplicado",
					"host": host_id,
					"card": attachment_id,
				})
				continue
			seen.append(attachment_id)
			var address := "anexo:" + prefix + ":" + host_address \
					+ ":" + str(index + 1)
			if _register(attachment, address, "attachment",
					cards, nodes, addresses, issues):
				cards[attachment_id]["host"] = host_id
				cards[host_id]["attachments"].append(attachment_id)


# A card that lives on the board without a slot and without a host is not on
# any zone: it is the "loose card" the model wants to eliminate.
static func _read_transit(board : Node, cards : Dictionary,
		addresses : Dictionary, issues : Array) -> void:
	if not is_instance_valid(board):
		return
	for child in board.get_children():
		if not is_instance_valid(child) or not (child is Card):
			continue
		# A card sent to the opponent prizes is taken out of the table before
		# queue_free runs: it becomes invisible and stops monitoring. It is not
		# in transit; it is already gone.
		if not child.visible and not child.monitoring:
			continue
		var id := _card_id(child)
		if addresses.has(id):
			continue
		issues.append({
			"type": "sem_endereco",
			"card": id,
			"name": str(child.canonical_name),
		})
		cards[id] = {
			"id": id,
			"name": str(child.canonical_name),
			"definition": str(child.definitions_key),
			"type": str(child.properties.get("_tipo", "")).strip_edges(),
			"address": TRANSIT_ADDRESS,
			"zone": "transit",
			"face": "up" if child.is_faceup else "down",
			"rotation": int(child.card_rotation),
			"shield": _shield_count(child),
			"cost": _energy_cost(child),
			"host": "",
			"attachments": [],
			"in_transit": true,
		}


# -----------------------------------------------------------------------------
# Registration and summaries
# -----------------------------------------------------------------------------

static func _register(card: Card, address : String, zone : String,
		cards : Dictionary, nodes : Dictionary, addresses : Dictionary,
		issues : Array) -> bool:
	var id := _card_id(card)
	if addresses.has(id):
		issues.append({
			"type": "endereco_duplicado",
			"card": id,
			"address": addresses[id],
			"other": address,
		})
		return false
	addresses[id] = address
	nodes[id] = card
	cards[id] = {
		"id": id,
		"name": str(card.canonical_name),
		"definition": str(card.definitions_key),
		"type": str(card.properties.get("_tipo", "")).strip_edges(),
		"address": address,
		"zone": zone,
		"face": "up" if card.is_faceup else "down",
		"rotation": int(card.card_rotation),
		"shield": _shield_count(card),
		"cost": _energy_cost(card),
		"host": "",
		"attachments": [],
		"visible": zone != "deck",
		"in_transit": cfc.card_drag_ongoing == card,
	}
	return true


# The resources a character or support needs to enter the play area, read the
# same way the card template reads it. Other cards have no play cost.
static func _energy_cost(card : Card) -> int:
	var card_type := str(card.properties.get("_tipo", "")).strip_edges()
	if not card_type in ["Personagem", "Suporte"]:
		return 0
	return int(str(card.properties.get("ENERGIA", "0")).to_int())


static func _zone_summary(grid, cards : Dictionary) -> Dictionary:
	var summary := {
		"count": _count_zone(cards, "field"),
		"columns": 0,
		"slots": 0,
		"free": 0,
	}
	if not is_instance_valid(grid):
		return summary
	var slots := _grid_slots(grid)
	summary["columns"] = _grid_columns(grid)
	summary["slots"] = slots.size()
	for slot in slots:
		if is_instance_valid(slot) and slot.occupying_card == null:
			summary["free"] += 1
	return summary


static func _scenario_summary(cards : Dictionary) -> Dictionary:
	var id := _first_id_in_zone(cards, "scenario")
	return {"count": 0 if id.is_empty() else 1, "id": id}


static func _pile_summary(cards : Dictionary, zone : String,
		visible_slots : int, pile) -> Dictionary:
	var count := _count_zone(cards, zone)
	var summary := {
		"count": count,
		"visible": int(min(count, visible_slots)),
	}
	if is_instance_valid(pile) and pile is Pile:
		summary["popup_open"] = pile.is_popup_open
	return summary


static func _count_zone(cards : Dictionary, zone : String) -> int:
	var count := 0
	for id in cards:
		if str(cards[id].get("zone", "")) == zone:
			count += 1
	return count


static func _first_id_in_zone(cards : Dictionary, zone : String) -> String:
	for id in cards:
		if str(cards[id].get("zone", "")) == zone:
			return str(id)
	return ""


# -----------------------------------------------------------------------------
# Diagnostics
# -----------------------------------------------------------------------------

# The board counts resources by node parent, which includes cards returned from
# a popup or still in transit. The snapshot counts addresses; a difference here
# is the resources bug showing its face.
static func _check_resource_count(board : Node, zones : Dictionary,
		issues : Array) -> void:
	if not is_instance_valid(board) \
			or not board.has_method("get_available_resource_count"):
		return
	var board_count := int(board.get_available_resource_count())
	var snapshot_count := int(zones["resources"]["count"])
	if board_count != snapshot_count:
		issues.append({
			"type": "contagem_recursos_divergente",
			"board": board_count,
			"snapshot": snapshot_count,
		})


static func _check_counts(cards : Dictionary, zones : Dictionary,
		issues : Array) -> void:
	var zona_total := 0
	for zone in ["hand", "field", "scenario", "resources", "prizes", "deck"]:
		zona_total += int(zones[zone]["count"])
	zona_total += int(zones["attachments"])
	zona_total += int(zones["transit"])
	if zona_total != cards.size():
		issues.append({
			"type": "contagem_inconsistente",
			"cards": cards.size(),
			"zones": zona_total,
		})
	for zone in zones:
		if not (zones[zone] is Dictionary):
			continue
		var declared := int(zones[zone].get("count", 0))
		var found := _count_zone(cards, zone)
		if zone == "attachments":
			found = _count_zone(cards, "attachment")
		elif zone == "transit":
			found = _count_zone(cards, "transit")
		if declared != found:
			issues.append({
				"type": "zona_divergente",
				"zone": zone,
				"declared": declared,
				"found": found,
			})


# -----------------------------------------------------------------------------
# Small helpers
# -----------------------------------------------------------------------------

static func id_of(card: Card) -> String:
	return _card_id(card)


static func _card_id(card: Card) -> String:
	if not is_instance_valid(card):
		return ""
	var net_id := str(card.network_id)
	if not net_id.is_empty():
		return net_id
	return "local:" + str(card.get_instance_id())


static func _shield_count(card: Card) -> int:
	var drawer = card.get_node_or_null("Control/Tokens")
	if drawer and drawer.has_method("get_token_count"):
		return int(drawer.get_token_count("escudo"))
	return 0


static func _grid_slots(grid) -> Array:
	if is_instance_valid(grid) and grid.has_method("get_all_slots"):
		return grid.get_all_slots()
	var grid_container = grid.get_node_or_null("GridContainer")
	if is_instance_valid(grid_container):
		return grid_container.get_children()
	return []


static func _grid_columns(grid) -> int:
	if not is_instance_valid(grid):
		return 1
	var grid_container = grid.get_node_or_null("GridContainer")
	if not is_instance_valid(grid_container):
		return 1
	return int(max(1, int(grid_container.columns)))


static func _slot_address(slot, prefix : String) -> String:
	if not is_instance_valid(slot):
		return ""
	var tree: SceneTree = slot.get_tree()
	if not tree:
		return ""
	for grid in tree.get_nodes_in_group("placement_grid"):
		if not (grid is BoardPlacementGrid):
			continue
		var slots := _grid_slots(grid)
		var index := slots.find(slot)
		if index < 0:
			continue
		if _is_scenario_grid(grid):
			return SCENARIO_ADDRESS
		var columns := _grid_columns(grid)
		var row := int(index / columns)
		var row_name := "frente"
		if row == 1:
			row_name = "trás"
		elif row > 1:
			row_name = "linha" + str(row + 1)
		return prefix + ":campo:" + row_name + ":" + str(index % columns + 1)
	return ""
