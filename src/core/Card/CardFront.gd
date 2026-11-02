# This class contains details about layout of the card front and the various
# labels which compose it.
#
# It also contains methods to adjust the text of the various labels,
# while keeping it inside its rect area.
class_name CardFront
extends Panel

# Maps the location of the card front labels so that they're findable even when
# The card front is customized for games of different needs
# Each card_front scene should have its own script extending this class
# which set the dictionary to map to the necessary nodes
#
# See "res://src/custom/CGFCardFront.gd" for an example.
var card_labels := {}
# Simply points to the container which holds all the labels
var _card_text
# It stores the font sizes as required by the developer. We keep it stored
# In order to be able to compare against it during scale_to()
#
# This should be set by the develop in the script extending this for the card front
var original_font_sizes : Dictionary
# The font sizes as modified by the scale_to() method
var font_sizes : Dictionary
# The minimum label sizes. This is used by set_label_text() to calculate
# how much to shrink a label to fit within its current rect.
#
# This should be set by the develop in the script extending this for the card front
var card_label_min_sizes : Dictionary
# Stores the amount each font has been scaled to. We use this as a sort of
# boolean in order to avoid scaling the font again and again during process.
var scaled_fonts : Dictionary
var bbcode_texts := {}
var rich_text_font_size_variations := {}
var resizing_labels := []

var font_thread: Thread

# Rich text is never drawn smaller than this. A DynamicFont asked for size 0 or
# less has no glyph in its cache, so the label reports a garbage height and the
# web build aborts. The fitting loop stops here as well.
const MIN_RTL_FONT_SIZE := 6
# A card label measures a few hundred pixels at most. Anything above this is
# the label answering with uninitialised memory while its font cache is being
# rebuilt, so the measurement is thrown away instead of being fitted.
const MAX_RTL_CONTENT_HEIGHT := 10000


# Stores a reference to the Card that is hosting this node
@onready var card_owner = get_parent().get_parent().get_parent()


## Thread must be disposed (or "joined"), for portability.
#func _exit_tree():
#	font_thread.wait_to_finish()

# Set a label node's text.
# As the string becomes longer, the font size becomes smaller
func set_label_text(node: Label, value, scale: float = 1):
#	while font_thread and font_thread.is_active():
#		yield(get_tree(), "idle_frame")
#	font_thread = Thread.new()
## warning-ignore:return_value_discarded
#	font_thread.start(self, "_set_label_text", [node,value], Thread.PRIORITY_LOW)
	if node in resizing_labels:
		return
	resizing_labels.append(node)
	value = _check_for_replacements(node, value)
	var label_font :Font = get_card_label_font(node)
#	print_debug(scaled_fonts.get(node.name, 1))
	var cached_font_size = get_cached_font_size(node,value,scale)
	# No Godot 4 o tamanho da fonte é um override de tema por Control, não uma
	# propriedade do FontFile. Guardamos o tamanho final e o aplicamos via
	# add_theme_font_size_override depois de setar a fonte.
	var final_size : int
	if cached_font_size:
		final_size = max(int(cached_font_size), 1)
	else:
		# We add a yield here to allow the calling function to continue
		# and thus avoid the game waiting for the label to resize
		await get_tree().process_frame
		var working_value: String
		# If the label node has been set to uppercase the text
		# Then we need to work off-of uppercased text value
		# otherwise our calculation will be off and we'll
		# end up extending the rect_size.y anyway
		if node.uppercase:
			working_value = value.to_upper()
		else:
			working_value = value
		_capture_original_font_size(node)
		var line_spacing = node.get("theme_override_constants/line_spacing")
		if not line_spacing:
			line_spacing = 3
		var starting_font_size: int = int(font_sizes[node.name])
		var font_adjustment := _adjust_font_size(label_font, working_value, node.custom_minimum_size, starting_font_size, line_spacing)
	#	if  node.name == "Abilities": font_adjustment = -17
		# We always start shrinking the size, starting from the original size.
#		print_debug(scaled_fonts.get(node.name, 1))
		_cache_font_size(node,value,starting_font_size + font_adjustment,scale)
		final_size = starting_font_size + font_adjustment
	set_card_label_font(node, label_font)
	node.add_theme_font_size_override("font_size", final_size)
	node.text = value
	resizing_labels.erase(node)


# Returns the font used by the current label
#
# We use an external function to get the font, to allow it to be overriden
# by classes extending this, to allow them to use their own methods
# (e.g. based on themes)
func get_card_label_font(label: Label) -> Font:
	# get_theme_font já resolve o fallback de tema/pai; não duplicamos porque o
	# tamanho agora é aplicado via override de tema, não no próprio recurso.
	return label.get_theme_font("font")


# Sets the font to be used by the current label
#
# We use an external function to get the font, to allow it to be overriden
# by classes extending this, to allow them to use their own methods
# (e.g. based on themes)
func set_card_label_font(label: Label, font: Font) -> void:
	label.add_theme_font_override("font", font)


# We use this as an alternative to scaling the card using the "scale" property.
# This is typically used in the viewport focus only, to keep the text legible
# because scaling the card starts distoring the font.
#
# For gameplay purposes (i.e. scaling while on the table etc),
# we keep using the .scale property, as that handles the Area2D size as well.
#
# Typically each game would override this function to fit its layout.
func scale_to(scale_multiplier: float) -> void:
	for l in card_labels:
		font_sizes[l] = original_font_sizes.get(l) * scale_multiplier
	for l in card_labels:
		if scaled_fonts.get(l) != scale_multiplier:
			scaled_fonts[l] = scale_multiplier
			while card_labels[l] in resizing_labels:
				await get_tree().process_frame
			if card_labels[l] as RichTextLabel:
				var label : RichTextLabel = card_labels[l]
				call_deferred("set_rich_label_text",label, label.text, true, scale_multiplier)
			else:
				var label : Label = card_labels[l]
				call_deferred("set_label_text",label, label.text, scale_multiplier)



# Set a label node's bbcode text.
# As the string becomes longer, the font size becomes smaller
func set_rich_label_text(node: RichTextLabel, value: String, is_resize := false, scale : float = 1):
	# We need to avoid other functions to trying to resize this label
	# while it's already resizing, as due to all the yields
	# it causes a mess
	if node in resizing_labels:
		return
	resizing_labels.append(node)
	value = _check_for_replacements(node, value)
	# This is used to hide a card with rich text while the rich text is resizing
	# This is because richtext cannot resize properly while invisible
	# Therefore we need to keep the front visible while the rich text label is resizing.
	# To avoid the player seeing the top card of their deck while this is happening
	# Or to see the font resizing in front of their eyes (due to all the yields)
	# we modulate the card front to 0.
	modulate.a = 0
	# I had to add this cache, because I cannot seem to get the bbcode_text
	# out of the label once I set it
	if not bbcode_texts.has(node) and not is_resize:
		bbcode_texts[node] = value
	elif is_resize:
		if not bbcode_texts.has(node):
			return
		value = bbcode_texts[node]
	var label_fonts := _get_card_rtl_fonts(node)
	# We always start shrinking the size, starting from the original size.
	_capture_original_font_size(node)
	_capture_rt_font_size_variations(node)
	var cached_font_size = get_cached_font_size(node,value,scale)
	if cached_font_size:
		# A cache written before the floor existed can name a size that the
		# font cannot draw, so it is raised to the minimum here as well.
		var cached_size: int = max(int(cached_font_size), MIN_RTL_FONT_SIZE)
		_set_card_rtl_fonts(node, label_fonts, cached_size)
		_assign_bbcode_text(node, value, cached_size)
	else:
		var starting_font_size: int = font_sizes[node.name]
		var font_adjustment:= 0
	#	label_font.size = font_sizes[node.name]
		var label_size = node.custom_minimum_size
		_set_card_rtl_fonts(node, label_fonts, starting_font_size + font_adjustment)
		_assign_bbcode_text(node, value, starting_font_size + font_adjustment)
		# Rich Text has no way to grab its total size without setting the bbcode first
		# After we set the bbcode, we need to wait for the next frame for the label to adjust
		# and then we can grab its height
		await get_tree().process_frame
		var _retries := 0
		var bbcode_height = node.get_content_height()
		var measuring_gave_up := false
#		print_debug([bbcode_height, label_size.y])
		while bbcode_height == 0 or bbcode_height > 1000:
			_retries += 1
#			print_debug("{0} BBcode height:{1} retrying: {2}".format([card_owner.canonical_name, bbcode_height, _retries]))
			await get_tree().process_frame
			bbcode_height = node.get_content_height()
#			print_debug(["Retry", _retries, "Code Height", bbcode_height])
			if bbcode_height > MAX_RTL_CONTENT_HEIGHT:
				measuring_gave_up = true
				break
			if _retries >= 10:
				break
		if measuring_gave_up:
			# No measurement is possible while the font cache is rebuilding;
			# keep the starting size instead of shrinking against a bogus value.
			bbcode_height = label_size.y
		# To save some time, we use the same trick we do in normal labels
		# where we reduce the font size to fits its rect
		# However unlike normal labels, we might have icons and different font sizes
		# which will not be taken into account.
		# Therefore this gives us the starting point, but further reduction might be
		# needed.
		if bbcode_height > label_size.y:
			font_adjustment = max(
					_adjust_font_size(label_fonts["normal_font"], node.text, label_size, starting_font_size),
					MIN_RTL_FONT_SIZE - starting_font_size)
			_set_card_rtl_fonts(node, label_fonts, starting_font_size + font_adjustment)
			await get_tree().process_frame
			bbcode_height = node.get_content_height()
			if bbcode_height > MAX_RTL_CONTENT_HEIGHT:
				measuring_gave_up = true
				bbcode_height = label_size.y
#			print_debug(["Font Adjustment", font_adjustment, "Code Height", bbcode_height])
	#		print_debug(bbcode_height, ':', font_adjustment, ':', label_size.y)
		# If the reduction of font sizes when checking against the normal font
		# was not enough to bring the total rich label height into the rect.y we want
		# we use a while loop where we do the following in order
		# * reduce all rich-text font sizes by 1
		# * reset the bbcode text
		# * Wait for the next frame
		# * grab the new rich text height
		# Unitl the rich text height is smaller than the labels' rect size.
		# The size is never allowed to go under the minimum: without this floor
		# the loop could skip from 6 straight to 5 and never reach the minimum
		# check below, shrinking forever against a height it cannot trust.
		var small_size_retries := 0
		while bbcode_height > label_size.y \
				and starting_font_size + font_adjustment > MIN_RTL_FONT_SIZE:
			font_adjustment -= 1
			_set_card_rtl_fonts(node, label_fonts, starting_font_size + font_adjustment)
			_assign_bbcode_text(node, value, starting_font_size + font_adjustment)
			await get_tree().process_frame
			bbcode_height = node.get_content_height()
#			print_debug(["Font Adjustment", font_adjustment, "Code Height", bbcode_height])
			_retries = 0
			while bbcode_height == 0 or bbcode_height > 1000:
				_retries += 1
#				print_debug("BBcode height:" + str(bbcode_height) + " retrying: " + str(_retries))
				await get_tree().process_frame
				bbcode_height = node.get_content_height()
				if bbcode_height > MAX_RTL_CONTENT_HEIGHT:
					measuring_gave_up = true
					break
				if _retries >= 10:
					break
			if measuring_gave_up:
				bbcode_height = label_size.y
				break
			# If we don't keep the card front face-up while setting the RTL,
			# The bbcode_height will be returned as either 0 or 1000 after setting the
			# bbcode_text. Regardless of how long we wait.
			# The below snipper was debugging code to keep the code waiting to resize
			# until the card was turned face-up
	#		while bbcode_height == 0 or bbcode_height > 1000:
	#			_set_card_rtl_fonts(node, label_fonts, starting_font_size + font_adjustment)
	#			_assign_bbcode_text(node, value, starting_font_size + font_adjustment)
	#			yield(get_tree(), "idle_frame")
	#			bbcode_height = node.get_content_height()
			if starting_font_size + font_adjustment <= MIN_RTL_FONT_SIZE:
				if small_size_retries <= 2:
					print_debug("WARN:CGF:{0} rich text label reached minimum size ({4}).\nRestarting font size calulcations retry: {5}\nstarting_font_size {1}\nbbcode_height: {2} > label_size.y: {3}".format(
							[card_owner.canonical_name, starting_font_size, bbcode_height, label_size.y, MIN_RTL_FONT_SIZE, small_size_retries]))
					small_size_retries += 1
					font_adjustment = max(
							_adjust_font_size(label_fonts["normal_font"], node.text, label_size, starting_font_size),
							MIN_RTL_FONT_SIZE - starting_font_size)
				else:
					break
		_cache_font_size(node,value,
				max(starting_font_size + font_adjustment, MIN_RTL_FONT_SIZE), scale)
	modulate.a = 1
	resizing_labels.erase(node)


func _cache_font_size(label: Control, text: String, font_size: int, scale : float) -> void:
	var text_md5 =  text.md5_text()
	# We will store each label's font size in a key based on the card scale
	# The default scale being 1
	# It has to be a string because the Godot Json print converts ints to
	# Strings when saving to file
	var card_size = str(scale)
	if not cfc.font_size_cache.has(card_size):
		cfc.font_size_cache[card_size] = {}
	if not cfc.font_size_cache[card_size].has(label.name):
		cfc.font_size_cache[card_size][label.name] = {}
	cfc.font_size_cache[card_size][label.name][text_md5] = font_size
	cfc.set_font_cache()


func get_cached_font_size(label: Control, text: String, scale : float):
	var text_md5 =  text.md5_text()
	var card_size = str(scale)
	var cached_font_size = cfc.font_size_cache.get(card_size, {}).get(label.name, {}).get(text_md5)
	return(cached_font_size)

# Stores the original font size this label had.
# We use this to start shrinking the label from this size, which allows us to
# also increase it's size when its text changes to be smaller.
func _capture_original_font_size(label) -> void:
	if not font_sizes.has(label.name):
		font_sizes[label.name] = original_font_sizes[label.name]


func _assign_bbcode_text(rtlabel: RichTextLabel, text : String, font_size: int) -> void:
	var format = _get_bbcode_format()
	rtlabel.clear()
	var bbcode_format := {}
	# A non-positive image size makes the rich text report an absurd content
	# height, so the icon keeps at least one pixel even at the font minimum.
	var icon_size: int = max(font_size - 2, 1)
	bbcode_format["icon_size"] = '{icon_size}x{icon_size}'.format({"icon_size":icon_size})
	for key in format:
		format[key] = format[key].format(bbcode_format)
	if rtlabel == card_labels["Name"]:
		_add_title_bbcode(rtlabel)
	rtlabel.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	# warning-ignore:return_value_discarded
	rtlabel.append_text(text.format(format))
	#	print_debug(bbcode_text.format(format))
	rtlabel.pop()
	if rtlabel == card_labels["Name"]:
		_pop_title_bbcode(rtlabel)


# Overridable function for extra formatting of titles/card names
func _add_title_bbcode(_rtlabel: RichTextLabel):
	pass

# Overridable function for extra formatting of titles/card names
func _pop_title_bbcode(_rtlabel: RichTextLabel):
	pass


func _get_bbcode_format() -> Dictionary:
	return(CardConfig.CARD_BBCODE.duplicate())


# Goes through a rich text label, and retrieves all fonts used to define it.
func _get_card_rtl_fonts(label: RichTextLabel) -> Dictionary:
	var all_rt_fonts := {}
	# "title_font" não existe mais como item de tema no RichTextLabel do Godot 4.
	for font_type in [
			"normal_font",
			"italics_font",
			"bold_font",
			"bold_italics_font",
			"mono_font"]:
		var label_font : Font = label.get_theme_font(font_type)
		if label_font != null:
			all_rt_fonts[font_type] = label_font
	return(all_rt_fonts)


# Stores the difference of each RT font, compared to the "normal_font"
# We use the normal_font as the baseline. So if normal font was 15 and italic is 14
# if we resize normal font to 10. Italic should be resized to 9
func _capture_rt_font_size_variations(label: RichTextLabel) -> void:
	if rich_text_font_size_variations.has(label):
		return
	var fvars := {}
	var label_fonts := _get_card_rtl_fonts(label)
	var normal_size := label.get_theme_font_size("normal_font_size")
	# Iteramos sobre as fontes realmente presentes para que fvars tenha as mesmas
	# chaves de fonts_dict (usado por _set_card_rtl_fonts).
	for font_type in label_fonts:
		fvars[font_type] = label.get_theme_font_size(font_type + "_size") - normal_size
	rich_text_font_size_variations[label] = fvars


# Sets all fonts by the current rich text label
# adjusted in relation to the normal font.
func _set_card_rtl_fonts(label: RichTextLabel, fonts_dict: Dictionary, new_size: int) -> void:
	for font_type in fonts_dict:
		# Each font keeps its difference from the normal font, but never goes
		# under the minimum: a size of 0 leaves the DynamicFont without a
		# cache entry and the label without a usable measurement.
		var font_size: int = new_size + rich_text_font_size_variations[label][font_type]
		font_size = max(font_size, MIN_RTL_FONT_SIZE)
		label.add_theme_font_override(font_type, fonts_dict[font_type])
		label.add_theme_font_size_override(font_type + "_size", font_size)


# figures out how much a font size has to be reduced, in order to fit
# in the specified rect.
#
# Returns the reductio from the provided font size that will have to be applied.
func _adjust_font_size(
		font: Font,
		text: String,
		label_size: Vector2,
		base_font_size: int,
		line_spacing := 3) -> int:
	# No Godot 4 a medição leva o tamanho como argumento; não mutamos o recurso.
	var current_size : int = base_font_size
	var line_height = font.get_height(current_size)
	# A font without a cache reports no line height; dividing by it would give
	# an infinite measure and shrink the text to nothing.
	if line_height <= 0.0:
		return 0
	var adjustment := 0
	# line_spacing should be calculated into rect_size
	# This calculates the amount of vertical pixels the text would take
	# once it was word-wrapped.
	var label_rect_y = _wrapped_text_height(font, text, label_size.x, current_size) \
			/ line_height \
			* (line_height + line_spacing) \
			- line_spacing
	# If the y-size of the wordwrapped text would be bigger than the current
	# available y-size foir this label, we reduce the text, until we
	# it's small enough to stay within the boundaries
	while label_rect_y > label_size.y:
		adjustment -= 1
		current_size = base_font_size + adjustment
		line_height = font.get_height(current_size)
		if line_height <= 0.0:
			break
		label_rect_y = _wrapped_text_height(font, text, label_size.x, current_size) \
				/ line_height \
				* (line_height + line_spacing) \
				- line_spacing
		if current_size < 5:
			break
	return(adjustment)


# Mede a altura de um texto com quebra de linha. No Godot 4.7 a Font não tem
# mais get_wordwrap_string_size; usamos TextParagraph, que faz o wordwrap real.
func _wrapped_text_height(font: Font, text: String, width: float, font_size: int) -> float:
	var para := TextParagraph.new()
	para.set_width(width)
	para.add_string(text, font, font_size)
	return para.get_size().y


# Overridable function which allows values to be replaced on the fly
# when placed in the card front.
func _check_for_replacements(node, value):
	for repl_key in CardConfig.REPLACEMENTS:
		if node == card_labels[repl_key]:
			# This command will try to find a replacement for this value in the replacements
			# But will keep the existing value if none is found.
			value = CardConfig.REPLACEMENTS[repl_key].get(value, value)
	return(value)
