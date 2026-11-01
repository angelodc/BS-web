# Draws a `TableState` onto the local table.
#
# F3 of "ações sem mouse": the state owns every address, so the scene no longer
# decides where a card lives. This class reads the addresses of the local seat
# and reconciles the scene with them:
#
#   mão   — the children order follows mão:1 … N, so the existing fan draws the
#           slot order (a draw enters at mão:1);
#   campo — every card sits on the slot of its frente/trás address, and the grid
#           grows or shrinks to the state's column count;
#   cenário — the single shared slot holds the state's scenario card.
#
# Piles are left alone: their stack order comes from the append order of the
# container, and a restack of a pile animates on its own. Cards being dragged
# and cards still tweening keep their animation; only the slot reference is
# settled.
class_name TableRenderer
extends Reference

const _Table = preload("res://src/core/table/TableState.gd")
const _Snapshot = preload("res://src/core/table/TableSnapshot.gd")


# Reconciles every address this renderer can draw. The returned dictionary is a
# diagnostic: the addresses that had to be corrected in each zone.
static func reconcile(board, state, seat := 1) -> Dictionary:
	var changed := {"hand": [], "field": [], "scenario": []}
	if not is_instance_valid(board) or state == null:
		return changed
	var nodes := _nodes_by_id(board)
	changed["hand"] = _reconcile_hand(board, state, int(seat), nodes)
	changed["field"] = _reconcile_field(board, state, int(seat), nodes)
	changed["scenario"] = _reconcile_scenario(board, state, nodes)
	return changed


# Ids of a seat's hand in slot order (mão:1 first). The slots are contiguous,
# so the position in this list plus one is the address slot.
static func hand_order(state, seat := 1) -> Array:
	var ids := []
	if state == null or not state.hand.has(int(seat)):
		return ids
	for id in state.hand[int(seat)]:
		if str(id) != "":
			ids.append(str(id))
	return ids


# Ids of a field row in column order, holes skipped.
static func field_order(state, seat, row : String) -> Array:
	var ids := []
	if state == null or not state.field.has(int(seat)) \
			or not state.field[int(seat)].has(row):
		return ids
	for id in state.field[int(seat)][row]:
		if str(id) != "":
			ids.append(str(id))
	return ids


# -----------------------------------------------------------------------------
# Hand
# -----------------------------------------------------------------------------

# Puts the hand children in the order of their slots. Cards that are not in the
# state (a card being dragged, for instance) keep their place after the listed
# ones.
static func _reconcile_hand(board, state, seat : int, nodes : Dictionary) -> Array:
	var hand = _container(board, "Hand", "hand")
	if not is_instance_valid(hand):
		return []
	var expected := hand_order(state, seat)
	var moved := []
	# The hand keeps its own controls before the cards; the slots start after
	# them. Reading the first card index avoids counting a card being dragged,
	# which the container leaves out of `get_all_cards()`.
	var base := 0
	for child in hand.get_children():
		if child is Card:
			break
		base += 1
	for index in range(expected.size()):
		var card = nodes.get(expected[index], null)
		if not is_instance_valid(card) or card.get_parent() != hand:
			continue
		if card.get_index() != base + index:
			hand.move_child(card, base + index)
			moved.append(expected[index])
	# The fan is drawn from the card index, so a changed order has to reorganize
	# the cards that moved.
	for id in moved:
		var card = nodes.get(id, null)
		if is_instance_valid(card) and card.has_method("reorganize_self"):
			card.interruptTweening()
			card.reorganize_self()
	return moved


# -----------------------------------------------------------------------------
# Field and scenario
# -----------------------------------------------------------------------------

# Assigns every field address to its slot and grows the grid to the state's
# column count. A slot whose card is no longer in the field is freed, so a card
# that left the board stops answering to its old address.
static func _reconcile_field(board, state, seat : int, nodes : Dictionary) -> Array:
	var grid = _Snapshot.field_grid(board)
	if not is_instance_valid(grid) or state == null:
		return []
	_apply_columns(grid, int(state.columns))
	var columns : int = int(max(1, int(grid.get_node("GridContainer").columns)))
	var wanted := {}
	for row_index in range(_Table.ROWS.size()):
		var row := str(_Table.ROWS[row_index])
		if not state.field.has(seat) or not state.field[seat].has(row):
			continue
		# The column is the index in the row, holes included: the rules place
		# the first character on the centre column, so frente:2 has to land on
		# slot 2 and not on the first free slot of the row.
		var ids: Array = state.field[seat][row]
		for index in range(ids.size()):
			var id := str(ids[index])
			if id.empty():
				continue
			var slot_index : int = row_index * columns + index
			while grid.get_slot_count() <= slot_index:
				grid.add_slot()
			wanted[id] = {
				"slot": grid.get_slot(slot_index),
				"address": _Table.field_address(seat, row, index + 1),
			}
	for slot in grid.get_all_slots():
		var occupant = slot.occupying_card
		if not is_instance_valid(occupant):
			continue
		var occupant_id := _Snapshot.id_of(occupant)
		if wanted.has(occupant_id) and wanted[occupant_id]["slot"] == slot:
			continue
		slot.occupying_card = null
		if occupant._placement_slot == slot:
			occupant._placement_slot = null
	var changed := []
	for id in wanted:
		var card = nodes.get(str(id), null)
		if not is_instance_valid(card) or card.get_parent() != board:
			continue
		var slot = wanted[id]["slot"]
		if slot.occupying_card == card and card._placement_slot == slot:
			continue
		_settle(card, slot)
		changed.append(str(wanted[id]["address"]))
	return changed


# The scenario is shared by both seats and has a single slot.
static func _reconcile_scenario(board, state, nodes : Dictionary) -> Array:
	var grid = _Snapshot.scenario_grid(board)
	if not is_instance_valid(grid) or state == null \
			or grid.get_slot_count() == 0:
		return []
	var id := str(state.scenario)
	if id.empty():
		return []
	var card = nodes.get(id, null)
	if not is_instance_valid(card) or card.get_parent() != board:
		return []
	var slot = grid.get_slot(0)
	if slot.occupying_card == card and card._placement_slot == slot:
		return []
	_settle(card, slot)
	return [id]


# Grows or shrinks the grid to the state's column count keeping every card on
# its own row and column.
static func _apply_columns(grid, columns : int) -> void:
	if int(columns) <= 0:
		return
	if int(grid.get_node("GridContainer").columns) == int(columns):
		return
	grid.set_columns_keeping_cards(int(columns))


# Points the card and the slot at each other and keeps the card heading to the
# slot. A settled card is placed at once; a card that is animating keeps its
# tween, which already targets the slot.
static func _settle(card, slot) -> void:
	var previous = card._placement_slot
	if is_instance_valid(previous) and previous != slot \
			and previous.occupying_card == card:
		previous.occupying_card = null
	slot.occupying_card = card
	card._placement_slot = slot
	card._target_position = slot.rect_global_position
	if card.state == Card.CardState.ON_PLAY_BOARD \
			and card != cfc.card_drag_ongoing \
			and not card._tween.is_active():
		card.global_position = slot.rect_global_position


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# One id -> node map for the whole table, built from the same id the snapshot
# uses. Mirrors are not in the "cards" group, so they never answer here.
static func _nodes_by_id(board) -> Dictionary:
	var nodes := {}
	if not is_instance_valid(board):
		return nodes
	for card in board.get_tree().get_nodes_in_group("cards"):
		if not is_instance_valid(card):
			continue
		var id := _Snapshot.id_of(card)
		if not id.empty():
			nodes[id] = card
	return nodes


static func _container(board, node_name : String, nmap_key : String):
	if is_instance_valid(board):
		var direct = board.get_node_or_null(node_name)
		if is_instance_valid(direct):
			return direct
	return cfc.NMAP.get(nmap_key, null)
