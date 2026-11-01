extends "res://tests/UTcommon.gd"


func after_each():
	Multiplayer.leave_session()
	cfc.card_definitions.erase(IMPORTED_KEY)


func _sixty_card_deck(deck_name: String) -> Dictionary:
	var cards := {}
	for index in range(6):
		cards[deck_name + " " + str(index)] = 10
	return {"name": deck_name, "cards": cards}


func test_solo_session_opens_in_preparation_with_both_seats_local():
	var result := Multiplayer.begin_solo("Doug")

	assert_true(result.get("ok", false),
			"The solo session opens without touching the relay")
	assert_true(Rede.is_solo, "The transport marks the session as solo")
	assert_true(Rede.is_host(), "The solo player is the authority of both seats")
	assert_true(Multiplayer.is_solo(), "The session runs in solo mode")
	assert_eq(Multiplayer.my_slot, 1, "The solo player starts on seat one")
	assert_eq(Multiplayer.opponent_slot, 2, "Seat two is the mirrored seat")
	assert_eq(Multiplayer.get_my_username(), "P1", "Seat one reads as P1")
	assert_eq(Multiplayer.get_opponent_username(), "P2", "Seat two reads as P2")
	assert_true(Multiplayer.is_preparing(), "The solo session waits for two decks")


func test_solo_preparation_takes_one_deck_per_seat():
	Multiplayer.begin_solo("Doug")

	Multiplayer.select_deck(_sixty_card_deck("A"))
	assert_eq(Multiplayer.local_deck_name, "A",
			"The picked seat is seat one at the start")
	assert_false(Multiplayer.are_both_decks_ready(),
			"One deck is not enough to start")

	Multiplayer.set_solo_pick_slot(2)
	Multiplayer.select_deck(_sixty_card_deck("B"))
	assert_eq(Multiplayer.opponent_deck_name, "B",
			"The second deck goes to the mirrored seat")
	assert_true(Multiplayer.opponent_deck_ready,
			"A full second deck counts as ready without a peer")
	assert_true(Multiplayer.are_both_decks_ready(),
			"Two full decks let the solo match start")


func test_solo_deck_can_be_chosen_for_a_specific_seat():
	Multiplayer.begin_solo("Doug")

	Multiplayer.select_solo_deck(2, _sixty_card_deck("B"))
	assert_eq(Multiplayer.get_solo_deck(2).get("name", ""), "B",
			"The deck lands on the requested seat")
	assert_false(Multiplayer.is_solo_deck_ready(1),
			"The other seat stays empty")
	assert_true(Multiplayer.is_solo_deck_ready(2),
			"The chosen seat counts as ready")

	Multiplayer.select_solo_deck(1, _sixty_card_deck("A"))
	assert_true(Multiplayer.are_both_decks_ready(),
			"Each deck lands on its own seat")


func test_solo_hidden_payload_splits_the_sixty_cards_of_a_seat():
	var payload: Dictionary = Multiplayer._solo_hidden_payload(
			_sixty_card_deck("A"), 2, "seed")

	assert_eq(payload.get("hand", []).size(), 10,
			"The mirrored seat keeps ten cards in hand")
	assert_eq(payload.get("deck", []).size(), 50,
			"The other fifty stay in its deck")
	var ids := {}
	for entry in payload["hand"] + payload["deck"]:
		ids[str(entry["id"])] = true
	assert_eq(ids.size(), 60, "Every card of the seat keeps a unique id")


func test_solo_hidden_payload_is_seeded_per_seat():
	var deck := _sixty_card_deck("A")
	var seat_two: Dictionary = Multiplayer._solo_hidden_payload(deck, 2, "seed")
	var same_seed: Dictionary = Multiplayer._solo_hidden_payload(deck, 2, "seed")
	var seat_one: Dictionary = Multiplayer._solo_hidden_payload(deck, 1, "seed")

	assert_eq(_hand_names(same_seed), _hand_names(seat_two),
			"The same seed shuffles the same seat the same way")
	assert_ne(_hand_names(seat_one), _hand_names(seat_two),
			"Each seat gets its own shuffle")


# Dictionaries compare by reference in GDScript, so the shuffle is checked by
# the card names instead of the whole entries.
func _hand_names(payload: Dictionary) -> Array:
	var names := []
	for entry in payload.get("hand", []):
		names.append(str(entry["name"]))
	return names


func test_solo_swap_waits_for_a_running_match():
	Multiplayer.begin_solo("Doug")

	assert_false(Multiplayer.swap_solo_seat(),
			"Swapping seats before the match starts changes nothing")
	assert_eq(Multiplayer.my_slot, 1, "The solo player stays on seat one")


#-----------------------------------------------------------------------------
# Swapping seats inside a running match
#-----------------------------------------------------------------------------

func _sixty_test_deck() -> Dictionary:
	return {
		"name": "Teste",
		"cards": {"Test Card 1": 20, "Test Card 2": 20, "Test Card 3": 20},
	}


# An imported deck registers each card under the id of the database, which is
# written without accents, while the definition keeps the accented text shown
# on the card. The clone reproduces that split inside GUT.
const IMPORTED_KEY := "diag-imported-card"


func _imported_name_definition() -> Dictionary:
	var definition: Dictionary = cfc.card_definitions["Test Card 1"].duplicate(true)
	definition["Name"] = "Carta Importada Áé"
	return definition


func _imported_name_deck() -> Dictionary:
	return {
		"name": "Importado",
		"cards": {IMPORTED_KEY: 20, "Test Card 2": 20, "Test Card 3": 20},
	}


func _free_all_cards() -> void:
	for card in get_tree().get_nodes_in_group("cards"):
		if not (card is Card) or not is_instance_valid(card):
			continue
		var parent = card.get_parent()
		if parent:
			parent.remove_child(card)
		card.queue_free()


# The board of a real match starts empty, so the deck the match builds is the
# only source of cards and the hidden counts stay at sixty per seat. With
# opponent_band the test adds the opponent scene box the shipped board lays
# out, because the mirror geometry reads its rect and the UT board has none.
func _start_solo_match(deck: Dictionary = {}, extra_definitions: Dictionary = {},
		opponent_band := false) -> void:
	if deck.empty():
		deck = _sixty_test_deck()
	var setup = setup_board()
	if setup is GDScriptFunctionState:
		setup = yield(setup, "completed")
	var grid = load("res://src/custom/CGFPlacementGridDemo.tscn").instance()
	grid.name = "PlacementGridDemo"
	board.add_child(grid)
	autofree(grid)
	yield(yield_for(0.2), YIELD)
	if opponent_band:
		# The band is laid out like the shipped scene: the opponent visual ends
		# on the middle line and the local grid starts there, so the mirror has
		# the same middle line the production board uses.
		var visual := Control.new()
		visual.name = "OpponentFieldVisual"
		board.add_child(visual)
		autofree(visual)
		visual.rect_size = Vector2(1280, 366.2)
		var scene := Control.new()
		scene.name = "OpponentScene"
		visual.add_child(scene)
		# The resources box sits in the deck column, under the opponent deck. The
		# mirror grid reads its rect, so the test authors the shipped geometry.
		var resources := ColorRect.new()
		resources.name = "OpponentResourcesBackground"
		visual.add_child(resources)
		resources.rect_position = Vector2(1124, 144.2)
		resources.rect_size = Vector2(156, 216)
		yield(yield_for(0.1), YIELD)
		grid.rect_position = Vector2(156, 366.2)
		yield(yield_for(0.1), YIELD)
		scene.rect_size = grid.rect_size
		scene.rect_global_position = Vector2(grid.rect_global_position.x, 80)
		yield(yield_for(0.1), YIELD)
	_free_all_cards()
	yield(yield_for(0.2), YIELD)

	Multiplayer.begin_solo("Doug")
	# A match started from the menu builds its board inside the session, and the
	# board creates the sync node and registers it there; the GUT board has
	# neither, so the test wires them the same way.
	var sync = load("res://src/custom/MultiplayerSync.gd").new()
	sync.name = "MultiplayerSync"
	board.add_child(sync)
	autofree(sync)
	Multiplayer.register_board(board, null, sync)
	yield(yield_for(0.1), YIELD)
	# Setting the board up reloads the set definitions, so a card invented by
	# the test is only registered from here on.
	for card_key in extra_definitions:
		cfc.card_definitions[card_key] = extra_definitions[card_key]
	Multiplayer.select_deck(deck)
	Multiplayer.set_solo_pick_slot(2)
	Multiplayer.select_deck(deck)
	assert_true(Multiplayer.request_start(), "Two full decks start the solo match")
	assert_true(Multiplayer.is_playing(), "The solo match is running")
	# The hand is only laid out after the deferred pass the match schedules.
	yield(yield_for(0.3), YIELD)


func _scene_grid() -> BoardPlacementGrid:
	return board.get_node("PlacementGridDemo") as BoardPlacementGrid


func _take_hand_card() -> Card:
	for child in cfc.NMAP.hand.get_children():
		if child is Card and is_instance_valid(child):
			return child
	return null


# Moves a few hand cards into the resources pile, which is how the owner builds
# the mini grid the other seat reads mirrored.
func _fill_discard(count: int) -> Array:
	var moved := []
	for _index in range(count):
		var card := _take_hand_card()
		if not card:
			break
		cfc.NMAP.hand.remove_child(card)
		discard.add_child(card)
		card.state = Card.CardState.IN_PILE
		moved.append(card)
	return moved


# Places a card the way a dropped one rests: child of the board, held by the
# scene slot, so the public state records it with its slot index.
func _place_scene_card(slot_index: int) -> Card:
	var slot: BoardPlacementSlot = _scene_grid().get_slot(slot_index)
	var card := _take_hand_card()
	if not card:
		return null
	cfc.NMAP.hand.remove_child(card)
	board.add_child(card)
	card.set_is_faceup(true, true)
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	card.global_position = slot.rect_global_position
	card._placement_slot = slot
	slot.occupying_card = card
	return card


# The scenario slot lives in the real board, so the card only needs the type
# property that makes the sync layer report it as a scenario.
func _place_scenario_card() -> Card:
	var card := _take_hand_card()
	if not card:
		return null
	cfc.NMAP.hand.remove_child(card)
	board.add_child(card)
	card.properties["_tipo"] = "Cenário"
	card.set_is_faceup(true, true)
	card.set_state(Card.CardState.ON_PLAY_BOARD)
	return card


func _local_field_cards() -> Array:
	var found := []
	for card in get_tree().get_nodes_in_group("cards"):
		if not (card is Card) or not is_instance_valid(card) \
				or not card.is_inside_tree() or card.network_mirror \
				or card.get_parent() != board:
			continue
		found.append(card)
	return found


func _mirrored_field_cards() -> Array:
	var found := []
	# Mirrors leave the cards group when they are built, so the remote group is
	# the one that holds them. The opponent's hand is shown with placeholder
	# mirrors too, and those are not part of the field.
	var sync = Multiplayer._sync
	var placeholders = sync._hand_placeholders if sync else []
	for card in get_tree().get_nodes_in_group("remote_cards"):
		if not (card is Card) or not is_instance_valid(card) \
				or not card.is_inside_tree() or not card.network_mirror:
			continue
		if card in placeholders:
			continue
		found.append(card)
	return found


# Nodes freed by a rebuild only leave the tree at the end of the frame, so the
# counts are taken one frame after the table changed.
func _settle() -> void:
	yield(yield_for(0.1), YIELD)


func _assert_fields(label: String, local_count: int, mirrored_count: int) -> void:
	assert_eq(_local_field_cards().size(), local_count,
			label + " shows the controlled field")
	assert_eq(_mirrored_field_cards().size(), mirrored_count,
			label + " shows the other field")


# Two players sit across from each other, so the other field is the same box
# seen from the opposite side: the mirror lands on the mirrored slot and reads
# upside down.
func test_mirror_of_a_scene_card_keeps_the_other_side_geometry():
	yield(_start_solo_match({}, {}, true), "completed")

	_place_scene_card(1)
	var free := _take_hand_card()
	var free_id := Multiplayer.ensure_card_id(free)
	cfc.NMAP.hand.remove_child(free)
	board.add_child(free)
	free.set_is_faceup(true, true)
	free.set_state(Card.CardState.ON_PLAY_BOARD)
	free.global_position = _scene_grid().rect_global_position \
			+ _scene_grid().rect_size * 0.35
	yield(_settle(), "completed")
	var placed: Card = _local_field_cards()[0]
	var placed_slot: int = Multiplayer._sync._slot_index(placed._placement_slot)
	var placed_rect := Rect2(placed.global_position,
			CFConst.CARD_SIZE * Multiplayer._sync.BOARD_SCALE)
	var free_rect := Rect2(free.global_position,
			CFConst.CARD_SIZE * Multiplayer._sync.BOARD_SCALE)

	assert_true(Multiplayer.swap_solo_seat(), "The swap shows the other seat")
	yield(yield_for(0.7), YIELD)
	var mirrors := _mirrored_field_cards()
	assert_eq(mirrors.size(), 2, "The other field shows both mirrors")
	for mirror in mirrors:
		assert_almost_eq(float(mirror.get_node("Control").rect_rotation), 180.0,
				0.5, "The mirror is drawn upside down")
	var slotted: Card = null
	var loose: Card = null
	for mirror in mirrors:
		if str(mirror.network_id) == str(free_id):
			loose = mirror
		else:
			slotted = mirror
	assert_not_null(slotted, "The slotted card has a mirror")
	assert_not_null(loose, "The loose card has a mirror")
	if slotted:
		var expected: Rect2 = Multiplayer._sync._mirrored_slot_rect(placed_slot)
		assert_true(expected.size.x > 0.0, "The slot mirrors into the other band")
		assert_almost_eq(slotted.global_position, expected.position,
				Vector2(2, 2), "The mirror sits on the mirrored slot")
		# Parity with the drawn box: the other field is exactly the local box
		# turned around the middle line, not an approximation of it.
		assert_almost_eq(slotted.global_position,
				Multiplayer._sync.mirror_rect(placed_rect).position,
				Vector2(2, 2), "The slotted mirror is the local box reflected")
	if loose:
		var travel: Vector2 = Multiplayer._sync._normalize_board_position(
				free.global_position)
		var point: Vector2 = Multiplayer._sync._mirrored_board_point(
				travel, CFConst.CARD_SIZE * Multiplayer._sync.BOARD_SCALE)
		assert_almost_eq(loose.global_position, point, Vector2(2, 2),
				"A loose card mirrors through the table centre")
		assert_almost_eq(loose.global_position,
				Multiplayer._sync.mirror_rect(free_rect).position,
				Vector2(2, 2), "The loose mirror is the local box reflected")

	assert_true(Multiplayer.swap_solo_seat(), "Swapping back returns the seat")
	yield(_settle(), "completed")
	var own := _local_field_cards()
	assert_eq(own.size(), 2, "The field comes back with both cards")
	for card in own:
		if str(card.network_id) == str(free_id):
			continue
		assert_eq(Multiplayer._sync._slot_index(card._placement_slot),
				placed_slot, "The card returns to the slot it was placed on")
		assert_eq(int(card.get_node("Control").rect_rotation), 0,
				"The card returns upright")


# The owner sees the attachment peeking below the character, so the other side
# of the table has to see it peeking above: the stack mirrors with the field
# instead of covering its own host.
func test_mirror_stacks_the_attachment_on_the_opposite_edge():
	yield(_start_solo_match({}, {}, true), "completed")

	var host := _place_scene_card(0)
	assert_not_null(host, "A character reaches the slot")
	var stack := []
	var stack_ids := []
	for _i in range(3):
		var attached := _take_hand_card()
		assert_not_null(attached, "A card is available to attach")
		cfc.NMAP.hand.remove_child(attached)
		board.add_child(attached)
		attached.set_is_faceup(true, true)
		attached.set_state(Card.CardState.ON_PLAY_BOARD)
		# Resources paid onto a character use this edge in the real game.
		attached.attachment_offset = Card.AttachmentOffset.BATTLE_SCENES_BOTTOM
		attached.attach_to_host(host)
		attached.global_position = host.global_position \
				+ CFConst.CARD_SIZE * attached._attachment_offset_vector() \
				* float(host.attachments.find(attached) + 1)
		attached._target_position = attached.global_position
		stack.append(attached)
		stack_ids.append(str(Multiplayer.ensure_card_id(attached)))
		host._organize_attachments()
	assert_eq(host.attachments.size(), 3, "The host holds the stack")
	var host_id := str(Multiplayer.ensure_card_id(host))
	var local_gaps := []
	for index in range(stack.size()):
		local_gaps.append(stack[index].global_position.y - host.global_position.y)
		assert_true(local_gaps[index] > 0.0,
				"The owner sees the stack below the host")
		if index > 0:
			assert_true(local_gaps[index] > local_gaps[index - 1],
					"Each attachment peeks further below the previous one")
	yield(_settle(), "completed")

	assert_true(Multiplayer.swap_solo_seat(), "The swap shows the other seat")
	yield(yield_for(0.7), YIELD)
	var mirrored_host: Card = null
	var mirrored_stack := []
	for _i in range(stack_ids.size()):
		mirrored_stack.append(null)
	for card in _mirrored_field_cards():
		if str(card.network_id) == host_id:
			mirrored_host = card
			continue
		var stack_index: int = stack_ids.find(str(card.network_id))
		if stack_index >= 0:
			mirrored_stack[stack_index] = card
	assert_not_null(mirrored_host, "The host has a mirror")
	for index in range(mirrored_stack.size()):
		var mirrored_attach: Card = mirrored_stack[index]
		assert_not_null(mirrored_attach, "Attachment %s has a mirror" % index)
		if not mirrored_attach:
			continue
		var mirrored_gap: float = mirrored_attach.global_position.y \
				- mirrored_host.global_position.y
		assert_almost_eq(mirrored_gap, -local_gaps[index], 2.0,
				"The mirror stacks the attachment on the opposite edge")
		# Later siblings draw on top, so the attachment has to sit before the
		# host in the board children or it covers the card it belongs to.
		assert_true(mirrored_attach.get_index() < mirrored_host.get_index(),
				"The mirrored attachment is drawn behind its host")
		# The nearest attachment draws last, exactly like the owner's stack,
		# so both sides show the same card in the same strip.
		if index > 0 and mirrored_stack[index - 1]:
			assert_true(mirrored_stack[index - 1].get_index() \
					> mirrored_attach.get_index(),
					"The mirrored stack keeps the owner's strip order")

	assert_true(Multiplayer.swap_solo_seat(), "The swap returns to the owner")
	yield(yield_for(0.7), YIELD)
	var restored_host: Card = null
	var restored_stack := []
	for _i in range(stack_ids.size()):
		restored_stack.append(null)
	for card in _local_field_cards():
		if str(card.network_id) == host_id:
			restored_host = card
			continue
		var stack_index: int = stack_ids.find(str(card.network_id))
		if stack_index >= 0:
			restored_stack[stack_index] = card
	assert_not_null(restored_host, "The host returns to its seat")
	for index in range(restored_stack.size()):
		var restored_attach: Card = restored_stack[index]
		assert_not_null(restored_attach, "Attachment %s returns" % index)
		if not restored_attach:
			continue
		assert_almost_eq(restored_attach.global_position.y \
				- restored_host.global_position.y, local_gaps[index], 2.0,
				"The restored stack keeps the owner's edges")
		assert_true(restored_attach.get_index() < restored_host.get_index(),
				"The restored attachment is drawn behind its host")
		if index > 0 and restored_stack[index - 1]:
			assert_true(restored_stack[index - 1].get_index() \
					> restored_attach.get_index(),
					"The restored stack keeps the owner's strip order")


# A rebuilt table can reach the board with the resources already behind the
# character in the children list instead of after it (a snapshot follows the
# cards group, not the drop order). The plain organize only pulls cards that
# sit above the host, so rebuilding the pile has to work from either side.
func test_arrange_attachment_stack_recovers_a_pile_listed_before_its_host():
	yield(_start_solo_match({}, {}, true), "completed")

	var host := _place_scene_card(0)
	assert_not_null(host, "A character reaches the slot")
	var stack := []
	for _i in range(3):
		var attached := _take_hand_card()
		assert_not_null(attached, "A card is available to attach")
		cfc.NMAP.hand.remove_child(attached)
		board.add_child(attached)
		attached.set_is_faceup(true, true)
		attached.set_state(Card.CardState.ON_PLAY_BOARD)
		attached.attachment_mode = Card.AttachmentMode.ATTACH_BEHIND
		attached.attachment_offset = Card.AttachmentOffset.BATTLE_SCENES_BOTTOM
		attached.attach_to_host(host)
		# List the resource before its character, as the snapshot does when the
		# resource re-entered the tree after the character was dealt.
		board.move_child(attached, 0)
		stack.append(attached)
	assert_eq(host.attachments.size(), 3, "The host holds the stack")
	for card in stack:
		assert_true(card.get_index() < host.get_index(),
				"The resources sit behind the character before the rebuild")

	host.arrange_attachment_stack()

	assert_eq(host.get_index(), board.get_child_count() - 1,
			"The rebuild leaves the character on top of the table")
	for index in range(stack.size()):
		var card: Card = stack[index]
		assert_eq(card.get_index(), host.get_index() - (index + 1),
				"The nearest resource draws last, one strip per card")
		assert_almost_eq(card.global_position.y - host.global_position.y,
				float(index + 1) * CFConst.CARD_SIZE.y \
				* CFConst.ATTACHMENT_OFFSET[
						Card.AttachmentOffset.BATTLE_SCENES_BOTTOM].y, 1.0,
				"Each resource peeks out below the one before it")


# The resource mini grid is the local grid reflected through the middle line, so
# each miniature turns with its cell: what reads upright on the owner's side has
# to read upside down on the other side, like a card held across the table.
func test_mirror_of_a_resource_card_turns_with_the_grid():
	yield(_start_solo_match({}, {}, true), "completed")
	discard.position = Vector2(0, 372.2)
	discard._layout_panel()
	var card := _take_hand_card()
	assert_not_null(card, "A card reaches the hand")
	var card_id := str(Multiplayer.ensure_card_id(card))
	cfc.NMAP.hand.remove_child(card)
	discard.add_child(card)
	card.state = Card.CardState.IN_PILE
	yield(_settle(), "completed")

	assert_true(Multiplayer.swap_solo_seat(), "The swap shows the other seat")
	yield(yield_for(0.7), YIELD)
	var mirror: Card = null
	for candidate in get_tree().get_nodes_in_group("remote_cards"):
		if candidate is Card and is_instance_valid(candidate) \
				and str(candidate.network_id) == card_id:
			mirror = candidate
	assert_not_null(mirror, "The other side shows the resource mirror")
	if mirror:
		assert_almost_eq(float(mirror.get_node("Control").rect_rotation), 180.0,
				0.5, "The resource mirror is drawn upside down")
		var sync = Multiplayer._sync
		var index: int = sync._resources_in_pile_order().find(card_id)
		assert_true(index >= 0, "The mirror keeps its place in the pile")
		if index >= 0:
			var cell: Rect2 = sync._resource_cell_rect(index)
			assert_almost_eq(mirror.global_position, cell.position,
					Vector2(2, 2),
					"The upside-down card stays in the reflected cell")
			var label_band := Rect2(Vector2(1124, 144.2), Vector2(156, 22))
			assert_false(cell.intersects(label_band),
					"The cell never reaches into the resources label")


# The mirrored grid answers the pointer exactly where it draws each miniatures:
# no dead spot over the artwork and no preview over the empty part of the box.
# The cells come from the local pile, so both sides share one layout.
func test_mirror_resource_hover_follows_the_drawn_mini():
	yield(_start_solo_match({}, {}, true), "completed")
	cfc.NMAP.board._discard_position = Vector2(0, 372.2)
	discard.position = Vector2(0, 372.2)
	discard._layout_panel()
	var moved := _fill_discard(4)
	yield(_settle(), "completed")
	assert_true(moved.size() >= 2, "The pile holds cards to mirror")

	assert_true(Multiplayer.swap_solo_seat(), "The swap mirrors the pile")
	yield(yield_for(0.7), YIELD)

	var sync = Multiplayer._sync
	var order: Array = sync._resources_in_pile_order()
	assert_eq(order.size(), moved.size(), "Every resource keeps a mirrored cell")
	var box := Rect2(Vector2(1124, 144.2), Vector2(156, 216))
	var visible := int(min(order.size(), sync.RESOURCES_GRID_MAX))
	for index in range(visible):
		var mirror: Card = sync._remote_cards.get(order[index])
		assert_not_null(mirror, "The pile order names a live mirror")
		if not mirror:
			continue
		var cell: Rect2 = sync._resource_cell_rect(index)
		var drawn: Rect2 = sync._card_screen_rect(mirror)
		assert_almost_eq(drawn.position, cell.position, Vector2(2, 2),
				"The mini is drawn inside its own hover cell")
		assert_almost_eq(drawn.size, cell.size, Vector2(2, 2),
				"The hover cell is the size of the drawn mini")
		assert_eq(sync._resource_hover_at(cell.position + cell.size * 0.5), mirror,
				"The middle of the mini answers with that card")
		# Three pixels above is the six pixel gap between the mirrored rows, or
		# the free strip above the top row, so no other mini can answer there.
		assert_null(sync._resource_hover_at(Vector2(
				cell.position.x + cell.size.x * 0.5, cell.position.y - 3)),
				"Just above a mini is not a hover")
	# The box has room above the grid, which must stay inert: a hover there
	# opened the preview far above the cards.
	var empty_top := Vector2(box.position.x + box.size.x * 0.5,
			box.position.y + 10)
	assert_false(sync._resources_in_pile_order().empty(),
			"The mirrored grid is laid out")
	for index in range(visible):
		var cell: Rect2 = sync._resource_cell_rect(index)
		assert_false(cell.has_point(empty_top),
				"No cell reaches the empty top of the box")
	assert_null(sync._resource_hover_at(empty_top),
			"The empty top of the box is not a hover")


# The grid has to read the pointer the GUI receives, not the window position
# CanvasItem reports under a stretched window: the mirrored box sits far from
# the origin, where the two spaces disagree by almost a hundred pixels.
func test_mirror_resource_hover_reads_the_gui_pointer():
	yield(_start_solo_match({}, {}, true), "completed")
	cfc.NMAP.board._discard_position = Vector2(0, 372.2)
	discard.position = Vector2(0, 372.2)
	discard._layout_panel()
	var moved := _fill_discard(3)
	yield(_settle(), "completed")
	assert_true(moved.size() >= 1, "The pile holds a card to mirror")

	assert_true(Multiplayer.swap_solo_seat(), "The swap mirrors the pile")
	yield(yield_for(0.7), YIELD)
	var sync = Multiplayer._sync
	var order: Array = sync._resources_in_pile_order()
	assert_true(order.size() >= 1, "There is a mirrored mini")
	var mirror: Card = sync._remote_cards.get(order[0])
	var cell: Rect2 = sync._resource_cell_rect(0)
	sync._pointer_known = true
	sync._pointer_pos = cell.position + cell.size * 0.5
	sync._update_resource_preview()
	assert_eq(sync._resource_preview, mirror,
			"The pointer the GUI reported picks the drawn mini")
	sync._pointer_pos = cell.position - Vector2(80, 30)
	sync._update_resource_preview()
	assert_null(sync._resource_preview,
			"A pointer away from the mini keeps the preview clear")
	sync._pointer_known = false


func test_three_solo_swaps_keep_both_fields_populated():
	yield(_start_solo_match(), "completed")

	_place_scene_card(0)
	yield(_settle(), "completed")
	_assert_fields("P1 opening", 1, 0)

	assert_true(Multiplayer.swap_solo_seat(), "Swap one changes the seat")
	assert_eq(Multiplayer.my_slot, 2, "Swap one moves to P2")
	yield(_settle(), "completed")
	_assert_fields("After swap one", 0, 1)

	_place_scene_card(1)
	yield(_settle(), "completed")
	_assert_fields("After P2 plays", 1, 1)

	assert_true(Multiplayer.swap_solo_seat(), "Swap two changes the seat")
	assert_eq(Multiplayer.my_slot, 1, "Swap two returns to P1")
	yield(_settle(), "completed")
	_assert_fields("After swap two", 1, 1)

	assert_true(Multiplayer.swap_solo_seat(), "Swap three changes the seat")
	assert_eq(Multiplayer.my_slot, 2, "Swap three moves to P2 again")
	yield(_settle(), "completed")
	_assert_fields("After swap three", 1, 1)


# cfc.ut is what keeps the sync layer from running the production reconciliation
# under GUT, so the swap loop clears it to reach the same code the game runs.
func test_solo_swaps_with_a_scenario_keep_both_fields():
	yield(_start_solo_match(), "completed")

	_place_scene_card(0)
	var scenario := _place_scenario_card()
	assert_not_null(scenario, "A scenario reaches the field")
	yield(_settle(), "completed")
	_assert_fields("P1 with a scenario", 2, 0)

	cfc.ut = false
	assert_true(Multiplayer.swap_solo_seat(), "Swap one changes the seat")
	yield(_settle(), "completed")
	_assert_fields("After swap one", 0, 2)

	assert_true(Multiplayer.swap_solo_seat(), "Swap two changes the seat")
	yield(_settle(), "completed")
	_assert_fields("After swap two", 2, 0)

	assert_true(Multiplayer.swap_solo_seat(), "Swap three changes the seat")
	yield(_settle(), "completed")
	_assert_fields("After swap three", 0, 2)
	cfc.ut = true


# The hotseat has no peer to send to, so the scenario claim is registered
# locally: the play on the current turn takes the arena and the opponent's
# mirror has to leave it, exactly like the relay does for a real client.
func test_solo_scenario_pushes_the_opponent_mirror_to_its_discard():
	yield(_start_solo_match({}, {}, true), "completed")

	var first := _place_scenario_card()
	assert_not_null(first, "Seat one plays a scenario")
	_announce_scenario(first)
	var first_id := str(Multiplayer.ensure_card_id(first))
	yield(_settle(), "completed")

	assert_true(Multiplayer.swap_solo_seat(), "Swap one changes the seat")
	yield(_settle(), "completed")

	var second := _place_scenario_card()
	assert_not_null(second, "Seat two answers with a scenario")
	_announce_scenario(second)
	yield(_settle(), "completed")

	var sync = Multiplayer._sync
	var older: Dictionary = sync._remote_meta.get(first_id, {})
	assert_eq(str(older.get("zone", "")), "resources",
			"The older scenario leaves the other field")

	assert_true(Multiplayer.swap_solo_seat(), "Swap two returns to P1")
	yield(_settle(), "completed")
	assert_true(_is_in_discard(first_id),
			"The older scenario reaches its owner's discard")
	assert_eq(_mirrored_field_cards().size(), 1,
			"The arena keeps only the newer scenario mirrored")


# The sync node skips the signal bus under GUT, so the test delivers the same
# event the board delivers after a scenario drop.
func _announce_scenario(card: Card) -> void:
	Multiplayer._sync._on_card_signal(card, "card_moved_to_board", {"tags": []})


func _is_in_discard(net_id: String) -> bool:
	var discard = cfc.NMAP.get("discard", null)
	if not discard:
		return false
	for card in discard.get_children():
		if card is Card and is_instance_valid(card) \
				and str(card.network_id) == net_id:
			return true
	return false


# Imported decks are the case that broke the hotseat: a card saved under an
# id-only key but labelled with the accented name cannot be found again by the
# restore path, and the seat came back empty.
func test_solo_swap_restores_cards_imported_under_another_key():
	yield(_start_solo_match(_imported_name_deck(),
			{IMPORTED_KEY: _imported_name_definition()}), "completed")

	_place_scene_card(0)
	yield(_settle(), "completed")
	assert_gt(_live_hidden_count("hand"), 0, "The opening hand holds cards")

	assert_true(Multiplayer.swap_solo_seat(), "Swap one changes the seat")
	yield(_settle(), "completed")
	_assert_payloads_are_restorable("After swap one")
	assert_gt(_live_hidden_count("hand") + _live_hidden_count("deck"), 50,
			"Swap one restores the other seat with its cards")

	assert_true(Multiplayer.swap_solo_seat(), "Swap two returns to P1")
	yield(_settle(), "completed")
	_assert_payloads_are_restorable("After swap two")
	assert_gt(_live_hidden_count("hand") + _live_hidden_count("deck"), 50,
			"Swap two restores the first seat with its cards")


func _live_hidden_count(map_key: String) -> int:
	var pile = cfc.NMAP.get(map_key, null)
	if not pile:
		return 0
	var count := 0
	for child in pile.get_children():
		if child is Card and is_instance_valid(child) and not child.network_mirror:
			count += 1
	return count


func _assert_payloads_are_restorable(label: String) -> void:
	for slot in [1, 2]:
		var payload: Dictionary = Multiplayer._solo_hidden.get(slot, {})
		var entries = payload.get("hand", []) + payload.get("deck", [])
		for entry in entries:
			assert_true(cfc.card_definitions.has(str(entry.get("name", ""))),
					label + " keeps seat " + str(slot) + " restorable")
