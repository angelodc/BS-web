# This handles the mouse pointer collision shape 2D interactions
# It is used for detecting when a card and its elements is being hovered
# As we cannot rely on Control node relevant signals due to Godot bugs
# such as:
# * https://github.com/godotengine/godot/issues/16854
# * https://github.com/godotengine/godot/issues/44138
class_name MousePointer
extends Area2D

# The amount of radius in pixels that the mouse collision area
#
# This const is sometimes looked-up by other nodes to determine
# their own properties
const MOUSE_RADIUS := 2

# The card that is currently highlighted as a result of this
# mouse cursor hovering over it.
var current_focused_card : Card = null
# The amount of cards the cursor is hovering. We're using our own
# Array instead of get_overlapping_areas() because those are updated
# every tick, which causes glitches when the player moves the mouse too fast.
#
# Instead we populate according to signals,which are more immediate
var overlaps := []
# When set to false, prevents the player from disable interacting with the game.
var is_disabled := false: set = set_disabled


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$CollisionShape2D.shape.radius = MOUSE_RADIUS
	# warning-ignore:return_value_discarded
	area_entered.connect(_on_MousePointer_area_entered)
	# warning-ignore:return_value_discarded
	area_exited.connect(_on_MousePointer_area_exited)
	if cfc._debug:
		$DebugShape.visible = true


func _process(_delta: float) -> void:
	_drop_settled_kept_focus()
	if current_focused_card:
		# After a card has been dragged, it generally clears its
		# focused state. This check ensures that if the mouse hovers over
		# the card still after the drag, we focus it again
		if current_focused_card.get_parent() == cfc.NMAP.board \
				and current_focused_card.state == Card.CardState.ON_PLAY_BOARD:
			current_focused_card.state = Card.CardState.FOCUSED_ON_BOARD
		if current_focused_card.get_parent() == cfc.NMAP.hand \
				and current_focused_card.state == Card.CardState.IN_HAND:
			current_focused_card.state = Card.CardState.FOCUSED_IN_HAND
	if cfc.card_drag_ongoing and cfc.card_drag_ongoing != current_focused_card:
		current_focused_card = cfc.card_drag_ongoing
	if cfc._debug:
		$DebugShape/current_focused_card.text = "MOUSE: " + str(current_focused_card)
#	print([position,get_overlapping_areas()])


# Adds the overlapping area to the list of overlaps, and triggers the
# discover_focus()
func _on_MousePointer_area_entered(area: Area2D) -> void:
	if not is_disabled:
		# We add an extra check in case that the card was not cleared from overlaps 
		# through the _on_MousePointer_area_exited function 
		# (sometimes it happens. Haven't figured out what causes it)
		_check_for_stale_overlaps()
		overlaps.append(area)
		#print("enter:",area.name)
		_discover_focus()

func _check_for_stale_overlaps() -> void:
#	print_debug([overlaps])
	var reset_mouse := false
	for a in overlaps:
#		print_debug([a,overlaps_area(a),a.monitorable, a.get_parent()])
		if not a.monitorable:
			overlaps.erase(a)
			reset_mouse = true
	# so, this is a workaround to what seems to be a Godot bug
	# seems to like #https://github.com/godotengine/godot/issues/35927
	# but this is apparently fixed. Well I seem to be catching some sort of edge case of it
	# Sometimes, after playing a card and moving the mouse quickly out of it, the get_overlaping_areas()
	# will get stuck reporting that that card is still overlapping. 
	# Not only that, but the mouse will also stop registering enterring/exiting that area.
	# Nothing we do will fix this except reseting this area's monitoring variable
	# The below workaround does exactly that. As such cards will go first to a pile and have deactivated monitoring
	# The below code ensures that we'll notice if a card with deactivated monitoring is still considered 
	# to be overlaping, and then trigger this workaround
	if reset_mouse:
		set_deferred("monitoring", false)
		await get_tree().create_timer(0.1).timeout
		set_deferred("monitoring", true)
#		call_deferred("set_monitoring", true)
			
	

# Removes the overlapping area from the list of overlaps, and triggers the
# discover_focus()
func _on_MousePointer_area_exited(area: Area2D) -> void:
	if not is_disabled:
		# We stop the highlight on any areas we exit with the mouse.
		if area is Card or area is CardContainer:
			area.highlight.set_highlight(false)
		elif area.get_parent() as BoardPlacementSlot:
			area.get_parent().set_highlight(false)
		# A focused hand card that is still growing does not cover the pointer
		# for the whole trip: mid-animation its area is smaller than the one it
		# is heading for, so the pointer can leave it while still being inside
		# the area it will end up covering. Dropping the hover there hands it to
		# whatever card is drawn beyond, skipping the neighbour.
		if _keeps_focus_while_growing(area):
			overlaps.erase(area)
			return
		var hand_exit_side := _get_focused_hand_exit_side(area)
		overlaps.erase(area)
		#print("exit:",area.name)
		_discover_focus()
		# Discover focus clears the hover when the pointer leaves the focused
		# card and no other card is under it. In the hand that happens when the
		# pointer crosses sideways from a focused card into the space under the
		# next one: the fan is an arc, so the neighbour sits higher and the
		# pointer passes below its area. Without this handoff the card only gets
		# the hover once the pointer reaches it, skipping the neighbour.
		if hand_exit_side != 0 and current_focused_card == null:
			_focus_adjacent_hand_card(area, hand_exit_side)


# A hover kept through the focus animation (see _keeps_focus_while_growing) is
# dropped once the card has settled and the pointer is no longer over it.
# Without this the focus would stay on a card the pointer already left without
# ever getting an area_exited for it.
func _drop_settled_kept_focus() -> void:
	var card := current_focused_card
	if card == null or cfc.card_drag_ongoing:
		return
	if card.state != Card.CardState.FOCUSED_IN_HAND:
		return
	var parent := card.get_parent()
	if parent == null or not parent.is_in_group("hands"):
		return
	if card.tokens.are_hovered() and card.tokens.is_drawer_open:
		return
	if card._tween.is_active():
		return
	var mouse := determine_global_mouse_pos()
	var rect := Rect2(card.global_position, card.card_size * card.scale)
	if rect.has_point(mouse) or card.get_focus_target_rect().has_point(mouse):
		return
	card._on_Card_mouse_exited()
	current_focused_card = null


# True while the focused hand card is still animating towards its focus slot
# and the pointer is inside the area that animation is going to cover.
func _keeps_focus_while_growing(area: Area2D) -> bool:
	var card := area as Card
	if card == null or card != current_focused_card:
		return false
	if card.state != Card.CardState.FOCUSED_IN_HAND:
		return false
	var parent := card.get_parent()
	if parent == null or not parent.is_in_group("hands"):
		return false
	if not card._tween.is_active():
		return false
	return card.get_focus_target_rect().has_point(determine_global_mouse_pos())


# Returns -1 or 1 when the pointer left a focused hand card through its left or
# right side, or 0 when it left through the top/bottom (or was not focused).
#
# Only a settled card qualifies: a growing one is handled by
# _keeps_focus_while_growing().
func _get_focused_hand_exit_side(area: Area2D) -> int:
	if cfc.card_drag_ongoing:
		return 0
	var card := area as Card
	if card == null or card != current_focused_card:
		return 0
	if card.state != Card.CardState.FOCUSED_IN_HAND:
		return 0
	var parent := card.get_parent()
	if parent == null or not parent.is_in_group("hands"):
		return 0
	if card._tween.is_active():
		return 0
	var mouse := determine_global_mouse_pos()
	# The card grows from its top-left corner, so its area spans the whole
	# scaled card size from its global position.
	var rect := Rect2(card.global_position, card.card_size * card.scale)
	var dx_left := rect.position.x - mouse.x
	var dx_right := mouse.x - rect.end.x
	var dy := maxf(rect.position.y - mouse.y, mouse.y - rect.end.y)
	var dx := maxf(dx_left, dx_right)
	# The larger overflow tells which side the pointer left through. A corner
	# exit is ambiguous enough that it is left to the normal focus handling.
	if dx <= 0 or dx <= dy:
		return 0
	return 1 if dx_right > dx_left else -1


# Hands the hover to the neighbour in the direction the pointer left. The
# neighbour grows over the pointer, so the hover is not lost in the fan gap.
func _focus_adjacent_hand_card(card: Card, side: int) -> void:
	var parent := card.get_parent()
	var index: int = card.get_my_card_index() + side
	if index < 0 or index >= parent.get_card_count():
		return
	var next_card: Card = parent.get_card(index)
	if current_focused_card:
		current_focused_card._on_Card_mouse_exited()
	next_card._on_Card_mouse_entered()
	current_focused_card = next_card


# We're using this helper function, to allow our mouse-position relevant code
# to work during integration testing
# Returns either the adjusted global mouse position
# or a fake mouse position provided by integration testing
func determine_global_mouse_pos() -> Vector2:
	if cfc.ut and cfc.NMAP.get("board"):
		return cfc.NMAP.board._UT_mouse_position
	var current_scene = get_tree().current_scene
	if not current_scene:
		return global_position
	var zoom = Vector2(1,1)
	# We have to do the below offset hack due to godotengine/godot#30215
	# This is caused because we're using a viewport node and
	# scaling the game in full-creen.
	if get_viewport() and get_viewport().has_node("Camera2D"):
		zoom = get_viewport().get_node("Camera2D").zoom
	var offset_mouse_position = current_scene.get_global_mouse_position() \
			- get_viewport_transform().origin
	offset_mouse_position *= zoom
	#var scaling_offset = get_tree().get_root().get_node('Main').get_viewport().get_size_override() * OS.window_size
	return offset_mouse_position


# Disables the mouse from interacting with the board
func disable() -> void:
	is_disabled = true
	for area in overlaps:
		# We stop the highlight on any areas we were currently highlighting
		if area is Card or area is CardContainer:
			area.highlight.set_highlight(false)
		elif area.get_parent() as BoardPlacementSlot:
			area.get_parent().set_highlight(false)
	overlaps.clear()


# Re-enables the mouse interacting with the board
func enable() -> void:
	is_disabled = false
	overlaps = get_overlapping_areas().duplicate()
	_discover_focus()


func forget_focus() -> void:
	current_focused_card = null


func set_disabled(value) -> void:
	forget_focus()
	overlaps.clear()
	is_disabled = value

# Parses all collided objects and figures out which card, if any, to focus on and
# also while a card is being dragged, figures out which potential area to highlight
# for the drop effect.
#
# For dropping dragged cards, there is a general priority which is used
#  when figuring out which area to highlight
# * CardContainers have priority over potential hosts and placement slots.
#	This means if a card is being dragged and the mouse is over a CardContainer,
#	then the CardContainer will be highlighted.
# * Potential Hosts have priority over placement slots.
# * Potential board grid placement slots have the lowest priority. They
#	will only be highlighted if a the mouse is not over a CardContainer or
#	potential host.
func _discover_focus() -> void:
	var potential_cards := []
	var potential_slots := []
	var potential_containers := []
	var potential_hosts := []
	# We might overlap cards or their token drawers, but we hihglight
	# only cards.
	for area in overlaps:
		if area as Card:
			potential_cards.append(area)
			# To check for potential hosts, the card has to be dragged
			# And it has to be an attachment
			# and the checked area has to not be the dragged card
			# and the checked area has to not be an attachment to the
			# dragged card
			# and the checked area has to be on the board
			if current_focused_card \
					and current_focused_card == cfc.card_drag_ongoing \
					and (current_focused_card.attachment_mode != Card.AttachmentMode.DO_NOT_ATTACH) \
					and area != current_focused_card \
					and not area in current_focused_card.attachments \
					and area.state == Card.CardState.ON_PLAY_BOARD:
						potential_hosts.append(area)
		if area.get_parent() as BoardPlacementSlot \
				and _is_placement_slot_valid(area.get_parent(),potential_cards):
			potential_slots.append(area.get_parent())
#		if area.get_parent() as BoardPlacementSlot and cfc.card_drag_ongoing and cfc.card_drag_ongoing.is_attachment and not potential_cards.empty():
#			print_debug(potential_cards)
		if area as CardContainer and cfc.card_drag_ongoing:
		# If disable_dropping_to_cardcontainers is set to true, we still
		# Allow the player to return the card where they got it.
			if not cfc.card_drag_ongoing.disable_dropping_to_cardcontainers\
					or (cfc.card_drag_ongoing.disable_dropping_to_cardcontainers
					and cfc.card_drag_ongoing.get_parent() == area):
				potential_containers.append(area)
	# Dragging into containers takes priority over draggging onto board
	if not potential_containers.is_empty():
		cfc.card_drag_ongoing.potential_container = \
				Highlight.highlight_potential_container(
				CFConst.TARGET_HOVER_COLOUR,
				potential_containers,
				potential_cards,
				potential_slots)
	# Dragging onto cards, takes priority over board placement grid slots
	elif not potential_cards.is_empty():
		if cfc.card_drag_ongoing:
			cfc.card_drag_ongoing.potential_container = null
		# We sort the potential cards by the order they are actually drawn in
		potential_cards.sort_custom(Callable(CFUtils, "sort_draw_order_ascending"))
		# The candidate is drawn last, so it's on top of the others.
		var card : Card = potential_cards.back()
		# if this card was not already focused...
		if current_focused_card != card:
			# We don't want to change focus while we're either dragging
			# a card around, or we're hovering over a previously
			# focused card's token drawer.
			if not (current_focused_card
					and current_focused_card.state == Card.CardState.DRAGGED) \
				and not (current_focused_card
					and current_focused_card.tokens.are_hovered()
					and current_focused_card.tokens.is_drawer_open):
				# If we already highlighted a card that is lower in index
				# we remove it's focus state
				if current_focused_card:
					current_focused_card._on_Card_mouse_exited()
				if not cfc.card_drag_ongoing:
					card._on_Card_mouse_entered()
					current_focused_card = card
		# If we have potential hosts, then we highlight the highest index one
		if not potential_hosts.is_empty():
			cfc.card_drag_ongoing.potential_host = \
					current_focused_card.highlight.highlight_potential_card(
					CFConst.HOST_HOVER_COLOUR,potential_hosts,potential_slots)
		# If we have potential placements, then there should be only 1
		# as their placement should not allow the mouse to overlap more than 1
		# We also clear potential hosts since there potential_hosts was emty
		elif not potential_slots.is_empty():
			cfc.card_drag_ongoing.potential_host = null
			potential_slots.back().set_highlight(true)
		# If card is being dragged, but has no potential target
		# We ensure we clear potential hosts
		elif cfc.card_drag_ongoing:
			cfc.card_drag_ongoing.potential_host = null
	# If we don't collide with any objects, but we have been focusing until
	# now, we make sure we're not hovering over the card drawer.
	# if not, then we remove focus.
	#
	# Because sometimes the mouse moves faster than a dragged card,
	# We make sure we don't try to change the current_focused_card while
	# in the process of dragging one.
	elif current_focused_card and current_focused_card.state != Card.CardState.DRAGGED:
		if not current_focused_card.tokens.are_hovered() \
				or not current_focused_card.tokens.is_drawer_open:
			current_focused_card._on_Card_mouse_exited()
			current_focused_card = null

# A number of checks to see if a hovered grid placement slot is a valid target
# to highlight.
#
# We only populate potential_slots if the card is not hovering over
# potential hosts.
#
# There is a lot of checks to consider a BoardPlacementHost a
# potential drop point.
# * A card has to be currently dragged
# * It has to not be occupied by another card
# * The card being dragged cannot be an attachment
# or if it is an attachment, there have to be no potential hosts
# currently highlighted
func _is_placement_slot_valid(slot: BoardPlacementSlot, potential_cards := []) -> bool:
	var is_valid := true
	# We only hihglight slots if a card is not currently being dragged
	if not cfc.card_drag_ongoing:
		is_valid = false
	else:
		# We only hihglight a slot if it is not hosting a different card.
		if slot.occupying_card and slot.occupying_card != cfc.card_drag_ongoing:
			var can_replace_scenario: bool = \
					cfc.card_drag_ongoing.has_method(
					"is_battle_scenes_scenario") \
					and cfc.card_drag_ongoing.is_battle_scenes_scenario() \
					and slot.get_grid_name() == "Cenário Ativo"
			if not can_replace_scenario:
				is_valid = false
		# We only hihglight a slot if the dragged card is not an attachment
		# with a potential host highlighted.
		if cfc.card_drag_ongoing.attachment_mode != Card.AttachmentMode.DO_NOT_ATTACH \
			and not potential_cards.is_empty():
			# The card being dragged is usually part of the potential_cards
			# So we want to make sure we still highlight a potential slot
			# if it's only the dragged card in there.
			if potential_cards.size() == 1 \
					and not cfc.card_drag_ongoing in potential_cards:
				is_valid = false
			# If the card is an attachment and the mouse is hovering over
			# more than one card, there's is definitielly a potential host
			# TODO: The logic of this check has to be improved when
			# a game specifies not all cards are potential hosts.
			elif potential_cards.size() > 1:
				is_valid = false
		# If a card is only allowed to be placed on specific grids,
		# We do not highlight slots in other grids when it's hovering them
		if cfc.card_drag_ongoing.board_placement in [
				Card.BoardPlacement.GRID_AUTOPLACEMENT,
				Card.BoardPlacement.SPECIFIC_GRID]:
			if slot.get_grid_name() != cfc.card_drag_ongoing.mandatory_grid_name:
				is_valid = false
		# If a card is not allowed on the board
		# We do not highlight grid slots when it's hovering them
		if cfc.card_drag_ongoing.board_placement in [Card.BoardPlacement.NONE]:
				is_valid = false
	return(is_valid)
