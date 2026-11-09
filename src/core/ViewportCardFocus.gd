# This class is meant to serve as your main scene for your card game
# In that case, it will enable the game to use hovering viewports
# For displaying card information
class_name ViewportCardFocus
extends Node2D

const RenderResolution = preload("res://src/custom/RenderResolution.gd")

@export var board_scene: PackedScene
@export var info_panel_scene: PackedScene
# This array holds all the previously focused cards.
var _previously_focused_cards := {}
# This var hold the currently focused card duplicate.
var _current_focus_source : Card = null
# Hand previews keep following the cursor; every other hover centers on the
# screen, no matter whether the closeup image is shown alongside the panels.
var _current_is_hand := false

@onready var card_focus := $VBC/FocusBox/Focus
@onready var focus_info := $VBC/FocusInfo
@onready var _focus_box := $VBC/FocusBox
@onready var _board_host := $SubViewportContainer
@onready var _board_viewport := $SubViewportContainer/SubViewport
@onready var _focus_viewport := $VBC/FocusBox/Focus/SubViewport
@onready var world_environemt : WorldEnvironment = $WorldEnvironment
@onready var _focus_tween := LegacyTween.new(self)


# Called when the node enters the scene tree for the first time.
func _ready():
	cfc.map_node(self)
	world_environemt.environment.glow_enabled = cfc.game_settings.get('glow_enabled', true)
	_apply_render_density()
	# We use the below while to wait until all the nodes we need have been mapped
	# "hand" should be one of them.
	$SubViewportContainer/SubViewport.add_child(board_scene.instantiate())
	if not cfc.are_all_nodes_mapped:
		await cfc.all_nodes_mapped
	# warning-ignore:return_value_discarded
	get_viewport().size_changed.connect(_on_Viewport_size_changed)
	_on_Viewport_size_changed()
	for container in get_tree().get_nodes_in_group("card_containers"):
		container.re_place()
	focus_info.info_panel_scene = info_panel_scene
	focus_info.setup()


# The board and the preview are rasterised at the chosen density and drawn
# scaled down inside the design rectangles, so the content stays at 1280x720
# coordinates while every pixel on screen comes from the larger render. A
# SubViewportContainer with `stretch` on refuses manual SubViewport sizes (the
# engine warns and keeps the container size), so the containers have it off and
# the script sets both the raster size and the scale that maps it back.
func _apply_render_density() -> void:
	var board_pixels := RenderResolution.board_pixels()
	_board_host.size = Vector2(board_pixels)
	_board_host.scale = Vector2.ONE / RenderResolution.board_factor()
	_board_viewport.size = board_pixels
	_board_viewport.size_2d_override = RenderResolution.DESIGN_SIZE
	_board_viewport.size_2d_override_stretch = true
	var focus_pixels := RenderResolution.focus_pixels()
	card_focus.size = Vector2(focus_pixels)
	card_focus.scale = Vector2.ONE / RenderResolution.focus_factor()
	_focus_viewport.size = focus_pixels
	_focus_viewport.size_2d_override = RenderResolution.FOCUS_DESIGN_SIZE
	_focus_viewport.size_2d_override_stretch = true


# Where the hand's text panel goes: beside the cursor, flipping to the other
# side when the right edge is near, and always fully inside the screen.
static func hand_panel_position(mouse: Vector2, panel: Vector2, area: Vector2) -> Vector2:
	var x := mouse.x + 60.0
	if x + panel.x > area.x:
		x = mouse.x - 60.0 - panel.x
	return Vector2(
			clampf(x, 0.0, maxf(0.0, area.x - panel.x)),
			clampf(mouse.y - panel.y / 2.0, 0.0, maxf(0.0, area.y - panel.y)))


func _process(_delta) -> void:
#	if cfc.game_paused:
#		print_debug(_current_focus_source)
	# This code makes sure that the focus viewport size always matches the size of the card
	# shown into it. Don't know why but it's a bit buggy still, but only in CFG. Works in Hypnagonia.
#	if _current_focus_source:
#		pass
##		card_focus.rect_min_size = _current_focus_source.canonical_size * _current_focus_source.focused_scale * cfc.curr_scale
#		card_focus.rect_min_size.y *= 1.25
#		card_focus.rect_size = _current_focus_source.canonical_size * _current_focus_source.focused_scale * cfc.curr_scale
#		card_focus.rect_size.y *= 1.25
#		_focus_viewport.size = _current_focus_source.canonical_size * _current_focus_source.focused_scale * cfc.curr_scale
#		focus_info.rect_size.x = _current_focus_source.canonical_size.x * _current_focus_source.focused_scale * cfc.curr_scale
	# The below positions the preview: hand previews keep following the
	# cursor, everything else is centered on the screen.
	if _current_focus_source and is_instance_valid(_current_focus_source):
		if _current_is_hand:
			$VBC.position = hand_panel_position(
					get_global_mouse_position(), focus_info.size,
					get_viewport().get_visible_rect().size)
		else:
			$VBC.position = (get_viewport().get_visible_rect().size \
					- $VBC.size) / 2
	# The below performs some garbage collection on previously focused cards.
	for c in _previously_focused_cards:
		if not is_instance_valid(_previously_focused_cards[c]):
			continue
		var current_dupe_focus: Card = _previously_focused_cards[c]
		# We don't delete old dupes, to avoid overhead to the engine
		# insteas, we just hide them.
		if _current_focus_source != c\
				and not _focus_tween.is_active():
			current_dupe_focus.visible = false
	if not is_instance_valid(_current_focus_source)\
			and card_focus.modulate.a != 0\
			and not _focus_tween.is_active():
		card_focus.modulate.a = 0


# A card known to both players can be previewed face up even while its copy on
# the table is face down, which is what the log preview asks for. A viewed card
# is known to both players, so an already existing dupe must not be flipped
# back down when the focus is restarted over it.
func _preview_faceup(card: Card) -> bool:
	return card.is_faceup or card.is_viewed or card.preview_force_front


# Displays the card closeup in the Focus viewport
func focus_card(card: Card, show_preview := true) -> void:
	_current_is_hand = card.get_parent() and \
			card.get_parent().is_in_group("hands")
	# A different card taking over (for instance a hand card after hovering a
	# pile miniature) releases the current focus, otherwise the preview would
	# stay stuck on the previous card until the mouse leaves everything.
	if _current_focus_source and _current_focus_source != card:
		_current_focus_source = null
	# We check if we're already focused on this card, to avoid making duplicates
	# the whole time
	if not _current_focus_source:
		# We make a duplicate of the card to display and add it on its own in
		# our viewport world
		# This way we can standardize its scale and look and not worry about
		# what happens on the table.
		var dupe_focus: Card
		if _previously_focused_cards.has(card) and is_instance_valid(_previously_focused_cards[card]):
			dupe_focus = _previously_focused_cards[card]
			# Not sure why, but sometimes the dupe card will report is_faceup
			# while having the card back visible. Workaround until I figure it out.
			if dupe_focus.get_node('Control/Back').visible == dupe_focus.is_faceup:
				# warning-ignore:return_value_discarded
				dupe_focus.set_is_faceup(!dupe_focus.is_faceup, true)
			# warning-ignore:return_value_discarded
			dupe_focus.set_is_faceup(_preview_faceup(card), true)
			dupe_focus.is_viewed = card.is_viewed
		else:
			dupe_focus = card.duplicate(Node.DUPLICATE_USE_INSTANTIATION)
			dupe_focus.remove_from_group("cards")
			_extra_dupe_preparation(dupe_focus, card)
			# We display a "pure" version of the card
			# This means we hide buttons, tokens etc
			dupe_focus.state = Card.CardState.VIEWPORT_FOCUS
			_focus_viewport.add_child(dupe_focus)
			_extra_dupe_ready(dupe_focus, card)
			dupe_focus.is_faceup = _preview_faceup(card)
			dupe_focus.is_viewed = card.is_viewed
			# We check that the card front was not left half-visible because it was duplicated
			# in the middle of the flip animation
			if dupe_focus._card_front_container.scale.x != 1:
				if dupe_focus.is_viewed:
					dupe_focus._flip_card(dupe_focus._card_back_container, dupe_focus._card_front_container,true)
				else:
					dupe_focus._flip_card(dupe_focus._card_front_container,dupe_focus._card_back_container, true)
		# Mirrors are drawn upside down on the table; the closeup is always
		# upright so it reads like the owner's own preview. The setter queues a
		# rotation tween, which would spin the dupe, so it is dropped here.
		dupe_focus.card_rotation = 0
		dupe_focus._tween.remove_all()
		dupe_focus.get_node("Control").rotation = 0
		_current_focus_source = card
		# We store all our previously focused cards in an array, and clean them
		# up when they're not focused anymore. The new dupe is registered first
		# so the loop below shows it even when its source sits hidden in a pile.
		_previously_focused_cards[card] = dupe_focus
		for c in _previously_focused_cards.values():
			if not is_instance_valid(c):
				continue
			if c != dupe_focus:
				c.visible = false
			else:
				c.visible = true
		# If the card is facedown, we don't want the info panels
		# giving away information
		if not dupe_focus.is_faceup:
			focus_info.visible = false
		else:
			cfc.ov_utils.populate_info_panels(card,focus_info)
			focus_info.visible = true
		# We have to copy these internal vars because they are reset
		# see https://github.com/godotengine/godot/issues/3393
		# We make the viewport camera focus on the card center, so the
		# closeup sits centered in the focus area at a uniform zoom.
		$VBC/FocusBox/Focus/SubViewport/Camera2D.position =\
				dupe_focus.global_position + dupe_focus.card_size / 2
		# We always make sure to clean tweening conflicts
		_focus_tween.remove_all()
		# We do a nice alpha-modulate tween
		_focus_tween.interpolate_property(card_focus,'modulate',
				card_focus.modulate, Color(1,1,1,1), 0.25,
				Tween.TRANS_SINE, Tween.EASE_IN)
		if focus_info.visible_details > 0:
			_focus_tween.interpolate_property(focus_info,'modulate',
					focus_info.modulate, Color(1,1,1,1), 0.25,
					Tween.TRANS_SINE, Tween.EASE_IN)
		else:
			_focus_tween.interpolate_property(focus_info,'modulate',
					focus_info.modulate, Color(1,1,1,0), 0.25,
					Tween.TRANS_SINE, Tween.EASE_IN)
		_focus_tween.start()
		# The box hides with the closeup so the hand, which only shows the text
		# panel, is not pushed aside by an empty 300x450 slot.
		_focus_box.visible = show_preview
		card_focus.visible = show_preview
		# Now that the display panels can expand horizontally
		# we need to set their parent container size to 0 here
		# To ensure they are shown as expected on the screen
		# I.e. the card doesn't appear mid-screen for no reason etc
		$VBC.size = Vector2(0,0)



# Hides the focus viewport when we're done looking at it
func unfocus(card: Card) -> void:
	if _current_focus_source == card:
		_current_focus_source = null
		_focus_tween.remove_all()
		_focus_tween.interpolate_property(card_focus,'modulate',
				card_focus.modulate, Color(1,1,1,0), 0.25,
				Tween.TRANS_SINE, Tween.EASE_IN)
		if focus_info.modulate != Color(1,1,1,0):
			_focus_tween.interpolate_property(focus_info,'modulate',
					focus_info.modulate, Color(1,1,1,0), 0.25,
					Tween.TRANS_SINE, Tween.EASE_IN)
		_focus_tween.start()


# Tells the currently focused card to stop focusing.
func unfocus_all() -> void:
	if _current_focus_source:
		_current_focus_source.set_to_idle()


# Overridable function for games to extend preprocessing of dupe card
# before adding it to the scene
func _extra_dupe_preparation(dupe_focus: Card, card: Card) -> void:
	dupe_focus.canonical_name = card.canonical_name
	dupe_focus.properties = card.properties.duplicate()
	focus_info.hide_all_info()


# Overridable function for games to extend processing of dupe card
# after adding it to the scene
# warning-ignore:unused_argument
# warning-ignore:unused_argument
func _extra_dupe_ready(dupe_focus: Card, card: Card) -> void:
	if CFConst.VIEWPORT_FOCUS_ZOOM_TYPE == "scale":
		dupe_focus.scale = Vector2(1,1) * dupe_focus.focused_scale * cfc.curr_scale
	else:
		dupe_focus.resize_recursively(dupe_focus._control, dupe_focus.focused_scale * cfc.curr_scale)
		dupe_focus.card_front.scale_to(dupe_focus.focused_scale * cfc.curr_scale)


func _input(event):
	# We use this to allow the developer to take card screenshots
	# for any number of purposes
	if event.is_action_pressed("screenshot_card"):
		var img = _focus_viewport.get_texture().get_image()
		await get_tree().process_frame
		await get_tree().process_frame
		img.convert(Image.FORMAT_RGBA8)
		img.flip_y()
		img.save_png("user://" + _current_focus_source.canonical_name + ".png")


# Takes care to resize the child viewport, when the main viewport is resized
func _on_Viewport_size_changed() -> void:
	if ProjectSettings.get("display/window/stretch/mode") == "disabled" and is_instance_valid(get_viewport()):
		$SubViewportContainer.size = get_viewport().get_visible_rect().size
#		for c in _previously_focused_cards.values().duplicate():
#			c.queue_free()

func toggle_glow(is_enabled := true) -> void:
	world_environemt.environment.glow_enabled = is_enabled
