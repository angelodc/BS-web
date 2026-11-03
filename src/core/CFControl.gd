# Card Gaming Framework Control Singleton
#
# Add it to your autoloads with the name 'cfc'
class_name CFControl
extends Node

# Sent when all CGF nodes have been added to the NMAP dictionary
signal all_nodes_mapped
# Sent any time the scripting engine cache is cleared
signal cache_cleared
# Sent when all Card scripts have finished loading the memory from file
signal scripts_loaded
# Sent when a new Card node is instanced
signal new_card_instanced(card)
signal card_image_loaded(image_path, texture)

var load_start_time := Time.get_ticks_msec()

#-----------------------------------------------------------------------------
# BEGIN Unit Testing Variables
#-----------------------------------------------------------------------------

# Unit Testing flag
var ut := false
var _ut_tokens_only_on_board := CFConst.TOKENS_ONLY_ON_BOARD
var _ut_show_token_buttons := CFConst.SHOW_TOKEN_BUTTONS
# This is set to true when tests are running
var is_testing := false

#-----------------------------------------------------------------------------
# END Unit Testing Variables
#-----------------------------------------------------------------------------

# This variable stores all custom settings for each game.
# It is initiated by looking for [CFConst#SETTINGS_FILENAME], but if it
# doesn't exist, defaults to the values specified in CFConst, if applicable.
var game_settings := {}
# This variable stores the font and icon size for each string of text.
# based on the current card size. This allows us to avoid calculating fonts
# on the fly all the time and adding delay to card instancing.
var font_size_cache := {}
var cache_commit_timer: SceneTreeTimer
# If set to true, the player will be prevented from interacting with the game
var game_paused := false: set = set_game_paused
# If this is false, all CardContainers will pause in their ready() scene
# until all other CardContainers have been mapped.
var are_all_nodes_mapped := false
# The games initial Random Number Generator seed.
# When this stays the same, the game randomness will always play the predictable.
var game_rng_seed = "CFC Random Seed": set = set_seed
# This will store all card properties which are placed in the card labels
var card_definitions := {}
var current_deck := {}
# This will store all card scripts
var set_scripts := {}
# This will store all card scripts, including their format placeholders
var unmodified_set_scripts := {}
# A class to propagate script triggers to all cards.
var signal_propagator = SignalPropagator.new()
# A dictionary of all our container nodes for easy access
var NMAP: Dictionary
# The card actively being dragged
var card_drag_ongoing: Card = null
# Switch used for seeing debug info
var _debug := false
# Game random number generator
var game_rng := RandomNumberGenerator.new()
var rng_saved_state = game_rng.state
# We cannot preload the scripting engine as a const for the same reason
# We cannot refer to it via class name.
#
# If we do, it is parsed by the compiler who then considers it
# a cyclic reference as the scripting engine refers back to the Card class.
var scripting_engine = load(CFConst.PATH_SCRIPTING_ENGINE)
# We cannot preload the per script as a const for the same reason
# We cannot refer to it via class name.
#
# If we do, it is parsed by the compiler who then considers it
# a cyclic reference as the scripting engine refers back to the Card class.
var script_per = load(CFConst.PATH_SCRIPT_PER)
# We cannot preload the alterant engine as a const for the same reason
# We cannot refer to it via class name.
#
# If we do, it is parsed by the compiler who then considers it
# a cyclic reference as the scripting engine refers back to the Card class.
var alterant_engine = load(CFConst.PATH_ALTERANT_ENGINE)
# Stores the alterations returned for a specific card-script-value combination.
#
# As the Alterant Engine is scanning all cards in game for alterant scripts
# then those scripts can further scan cards in play and trigger other alterants
# this can be a quite heavy operations, when there's a few alterants in play.
#
# To avoid this, after each alterant operation, we store the results in this
# dictionary, and use them for the next time. This scripts which read properties
# or counters to be placed even in _process() while there's alterants in play.
var alterant_cache: Dictionary
# This is a copy of card.temp_property_modifiers
# We store it globally for games which want to have access to it,
# before subject cards are selected
#
# This dictionary is not used by default anywhere in the framework.
# A game need to explicitly make use of it.
var card_temp_property_modifiers = {}
var ov_utils = load(CFConst.PATH_OVERRIDABLE_UTILS).new()
var curr_scale: float

var scripts_loading := true
const BSDB_IMAGE_BASE_URL := "https://raw.githubusercontent.com/inimig0r/bsdb-imagens/refs/heads/main/cards/oficial"
const CARD_IMAGE_CACHE_PATH := "user://CardImages/"
var _card_image_request: HTTPRequest
var _card_image_queue := []
var _card_image_pending := {}
var _card_image_textures := {}
var _active_card_image_path := ""

func _ready() -> void:
	_card_image_request = HTTPRequest.new()
	add_child(_card_image_request)
	_card_image_request.request_completed.connect(
			_on_card_image_request_completed)
	var load_end_time = Time.get_ticks_msec()
	if OS.has_feature("debug") and not cfc.is_testing:
		print_debug("DEBUG INFO:CFControl: instance time = %sms" % [str(load_end_time - load_start_time)])
	
	all_nodes_mapped.connect(_on_all_nodes_mapped)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	_setup()


func request_card_image(image_path: String) -> void:
	var cached_texture: ImageTexture = _load_cached_card_image(image_path)
	if cached_texture:
		_card_image_textures[image_path] = cached_texture
		emit_signal("card_image_loaded", image_path, cached_texture)
		return
	if _card_image_pending.has(image_path):
		return
	_card_image_pending[image_path] = true
	_card_image_queue.append(image_path)
	_start_next_card_image_request()


func _load_cached_card_image(image_path: String) -> ImageTexture:
	if _card_image_textures.has(image_path):
		return _card_image_textures[image_path]
	var file_name := image_path.get_file()
	var cache_path := CARD_IMAGE_CACHE_PATH + file_name
	if not FileAccess.file_exists(cache_path):
		return null
	var image := Image.load_from_file(cache_path)
	if image == null or image.is_empty():
		push_error("Could not load cached BSDB card image: " + cache_path)
		return null
	return ImageTexture.create_from_image(image)


func _start_next_card_image_request() -> void:
	if _active_card_image_path or _card_image_queue.is_empty():
		return
	_active_card_image_path = _card_image_queue.pop_front()
	var image_url := BSDB_IMAGE_BASE_URL + _active_card_image_path
	var request_error := _card_image_request.request(image_url)
	if request_error != OK:
		push_error("Could not request BSDB card image: " + image_url)
		_card_image_pending.erase(_active_card_image_path)
		_active_card_image_path = ""
		_start_next_card_image_request()


func _on_card_image_request_completed(
		result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	var image_path := _active_card_image_path
	_active_card_image_path = ""
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error(
				"BSDB card image request failed (result "
				+ str(result) + ", HTTP " + str(response_code) + "): "
				+ image_path)
		_card_image_pending.erase(image_path)
		_start_next_card_image_request()
		return
	var image := Image.new()
	var image_error := image.load_png_from_buffer(body)
	if image_error != OK:
		push_error("Could not decode BSDB card image: " + image_path)
		_card_image_pending.erase(image_path)
		_start_next_card_image_request()
		return
	var texture := ImageTexture.create_from_image(image)
	_card_image_textures[image_path] = texture
	var directory_error := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(CARD_IMAGE_CACHE_PATH))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("Could not create card image cache directory.")
	else:
		var cache_file := FileAccess.open(
				CARD_IMAGE_CACHE_PATH + image_path.get_file(), FileAccess.WRITE)
		if cache_file == null:
			push_error("Could not cache BSDB card image: " + image_path)
		else:
			cache_file.store_buffer(body)
			cache_file.close()
	_card_image_pending.erase(image_path)
	card_image_loaded.emit(image_path, texture)
	_start_next_card_image_request()


func _setup() -> void:
	init_settings_from_file()
	init_font_cache()
	if not game_settings.has('fancy_movement'):
		game_settings['fancy_movement'] = CFConst.FANCY_MOVEMENT
	if not game_settings.has('focus_style'):
		game_settings['focus_style'] = CFConst.FOCUS_STYLE
	if not game_settings.has('hand_use_oval_shape'):
		game_settings['hand_use_oval_shape'] = CFConst.HAND_USE_OVAL_SHAPE
	# We reset our node mapping variables every time
	# as they repopulate during unit testing many times.
	# warning-ignore:return_value_discarded
	flush_cache()
	# We need to reset these values for UNIT testing
	NMAP = {}
	are_all_nodes_mapped = false
	card_drag_ongoing = null
	# The below takes care that we adjust some settings when testing via Gut
	if is_testing:
		ut = true
		_debug = true
	else:
		# Initialize the game random seed
		set_seed(game_rng_seed)
	card_definitions = load_card_definitions()
	var defs_load_end_time = Time.get_ticks_msec()
	if OS.has_feature("debug") and not cfc.is_testing:
		print_debug("DEBUG INFO:CFControl: card definitions load time = %sms" % [str(defs_load_end_time - load_start_time)])	
	# The script definitions used to load in a thread. Godot 4 refuses signal
	# emission from a worker thread, and every repeated test setup dropped the
	# running thread, so they are loaded up front now.
	load_script_definitions()
	var scripts_load_end_time = Time.get_ticks_msec()
	if OS.has_feature("debug") and not cfc.is_testing:
		print_debug("DEBUG INFO:CFControl: card scripts load time = %sms" % [str(scripts_load_end_time - load_start_time)])	

func _setup_testing() -> void:
	flush_cache()
	NMAP = {}
	are_all_nodes_mapped = false
	card_drag_ongoing = null
	ut = true
	_debug = true
	game_paused = false
	
# Run when all necessary nodes (Board, CardContainers etc) for the game
# have been initialized. Allows them to proceed with their ready() functions.
func _on_all_nodes_mapped() -> void:
	if get_tree().get_root().has_node('Main'):
		# When Unit Testing, we want to always have both scaling options possible
		if ut:
			game_settings['focus_style'] = CFInt.FocusStyle.BOTH
	else:
		# If we're not using the main viewport scene, we need to fallback
		# to the basic focus
		game_settings['focus_style'] = CFInt.FocusStyle.SCALED
		# To prevent accidental switching this option when there's no other
		# viewports active
		if NMAP.board and NMAP.board.has_node("ScalingFocusOptions"): # Needed for UT
			NMAP.board.get_node("ScalingFocusOptions").disabled = true


# The below code allows us to quickly refer to nodes meant to host cards
# (i.e. parents) using an human-readable name.
#
# Since the fully mapped NMAP variable is critical for the good functioning
# of the framework, all CardContainers will wait in their ready() process
# for NMAP to be completed.
func map_node(node) -> void:
#	print_debug("Map Node %s Start: %sms" % [node.name, str(OS.get_ticks_msec() - load_start_time)])
	# The nmap always stores lowercase keys. Each key is a node name
	var node_name: String = node.name.to_lower()
	# I don't know why but suring UT sometimes I get duplicate board nodes.
	# I guess the queue_free is not as fast before the next test
	if 'board' in node_name:
		node_name = 'board'
	NMAP[node_name] = node
	var add_main = 0
	# Since we allow the game to run directly from the board scene,
	# we need to check if a viewport called Main is being used.
	if get_tree().get_root().has_node('Main'):
		add_main = 1
	# The below variable counts how many nodes we're expecting to map inside
	# NMAP. We calculate this by using node groups. For this, the piles
	# and hands have to be added to group from the editor (i.e. not only
	# via code in the ready() method).
	# The amount we're looking for is the sum of all CardContainers
	# +1 for the board, +1 if we're using a focus viewport
	var all_nodes : int = get_tree().get_nodes_in_group("hands").size() \
			+ get_tree().get_nodes_in_group("piles").size() + 1  + add_main
	# If the amount of node maps we have is equal to all nodes in gr
	if NMAP.size() == all_nodes:
		are_all_nodes_mapped = true
		# Once all nodes have been mapped, we emit a signal so that
		# all nodes waiting to complete their ready()  method, can continue.
		emit_signal("all_nodes_mapped")
#	print_debug("Map Node %s End: %sms" % [node.name, str(OS.get_ticks_msec() - load_start_time)])


# Setter for the ranom seed.
func set_seed(_seed) -> void:
	game_rng_seed = str(_seed)
	game_rng.set_seed(hash(game_rng_seed))


func restore_rng_state() -> void:
	game_rng.state = rng_saved_state

# Instances and returns a Card object, based on its name.
func instance_card(card_name: String) -> Card:
	# We discover the template from the "Type"  property defined
	# in each card. Any property can be used
	var template = load(CFConst.PATH_CARDS
			+ card_definitions[card_name][CardConfig.SCENE_PROPERTY] + ".tscn")
	var card = template.instantiate()
	# We set the card_name variable so that it's able to be used later
	card.canonical_name = card_name
	emit_signal("new_card_instanced", card)
	return(card)


# Returns a Dictionary with the combined Card definitions of all set files
func load_card_definitions() -> Dictionary:
	var loaded_definitions : Array
	if "CARD_SETS" in SetPreload and SetPreload.CARD_SETS.size() > 0:
		loaded_definitions = SetPreload.CARD_SETS
	else:
		var set_files = CFUtils.list_files_in_directory(
				CFConst.PATH_SETS, CFConst.CARD_SET_NAME_PREPEND)
		for set_file in set_files:
			loaded_definitions.append(load(CFConst.PATH_SETS + set_file))
	var combined_sets := {}
	for set_def in loaded_definitions:
		if ut and set_def.SET == "Resgate Aracnídeo":
			continue
		for card_name in set_def.CARDS:
			combined_sets[card_name] = set_def.CARDS[card_name]
	return(combined_sets)


# Returns a Dictionary with the combined Script definitions of all set files
func load_script_definitions() -> void:
	var loaded_script_definitions := []
	if "CARD_SCRIPTS" in SetPreload and SetPreload.CARD_SCRIPTS.size() > 0:
		for preload_set_scripts in SetPreload.CARD_SCRIPTS:
			loaded_script_definitions.append(preload_set_scripts.new())
	else:
		var script_definition_files := CFUtils.list_files_in_directory(
					CFConst.PATH_SETS, CFConst.SCRIPT_SET_NAME_PREPEND)
		for script_file in script_definition_files:
			loaded_script_definitions.append(load(CFConst.PATH_SETS + script_file).new())
	var combined_scripts := {}
	for card_name in card_definitions.keys():
		for scripts_obj in loaded_script_definitions:
			if combined_scripts.get(card_name):
				break
			var card_script = scripts_obj.get_scripts(card_name)
			var unmodified_card_script = scripts_obj.get_scripts(card_name, false)
#			print(unmodified_card_script)
			if not card_script.is_empty():
				combined_scripts[card_name] = card_script
				set_scripts[card_name] = card_script
				unmodified_set_scripts[card_name] = unmodified_card_script
	emit_signal("scripts_loaded")
	scripts_loading = false


# Setter for game_paused
func set_game_paused(value: bool) -> void:
	# The mapped board can be a freed instance after a scene teardown; the key
	# alone still exists in NMAP, so validity has to be checked explicitly.
	var board = NMAP.get("board")
	if is_instance_valid(board) and board.mouse_pointer:
		board.mouse_pointer.is_disabled = value
	game_paused = value


# Whenever a setting is changed via this function, it also stores it
# permanently on-disk.
func set_setting(setting_name: String, value) -> void:
	game_settings[setting_name] = value
	var file := FileAccess.open(CFConst.SETTINGS_FILENAME, FileAccess.WRITE)
	if file == null:
		push_error("Could not write settings file: " + CFConst.SETTINGS_FILENAME)
		return
	file.store_string(JSON.stringify(game_settings, '\t'))
	file.close()


# Initiates game_settings from the contents of CFConst.SETTINGS_FILENAME
func init_settings_from_file() -> void:
	if not FileAccess.file_exists(CFConst.SETTINGS_FILENAME):
		return
	var file := FileAccess.open(CFConst.SETTINGS_FILENAME, FileAccess.READ)
	if file == null:
		push_error("Could not read settings file: " + CFConst.SETTINGS_FILENAME)
		return
	var test_json_conv = JSON.new()
	test_json_conv.parse(file.get_as_text())
	var data = test_json_conv.get_data()
	file.close()
	if typeof(data) == TYPE_DICTIONARY:
		game_settings = data.duplicate()


func set_font_cache() -> void:
#	var timer = Timer.new()
#	timer.connect("timeout", self, "_commit_font_cache", [timer])
#	timer.wait_time = 1
#	timer.start()
	if not cache_commit_timer:
		cache_commit_timer = get_tree().create_timer(1.0)
		# warning-ignore:return_value_discarded
		cache_commit_timer.timeout.connect(_commit_font_cache)


# Whenever a setting is changed via this function, it also stores it
# permanently on-disk.
func _commit_font_cache() -> void:
#	timer.disconnect("timeout", self, "_commit_font_cache")
#	timer.queue_free()
	var file := FileAccess.open(CFConst.FONT_SIZE_CACHE, FileAccess.WRITE)
	if file == null:
		push_error("Could not write font cache: " + CFConst.FONT_SIZE_CACHE)
	else:
		file.store_string(JSON.stringify(font_size_cache, '\t'))
		file.close()
	cache_commit_timer = null


# Initiates game_settings from the contents of CFConst.SETTINGS_FILENAME
func init_font_cache() -> void:
	if FileAccess.file_exists(CFConst.FONT_SIZE_CACHE):
		var file = FileAccess.open(CFConst.FONT_SIZE_CACHE, FileAccess.READ)
		if file == null:
			return
		var test_json_conv = JSON.new()
		test_json_conv.parse(file.get_as_text())
		var data = test_json_conv.get_data()
		file.close()
		if typeof(data) == TYPE_DICTIONARY:
			if font_size_cache.get('version') == CFConst.GAME_VERSION:
				font_size_cache = data.duplicate()
			else:
				# If the version of the game has increased, we wipe the
				# font size cache and a new one will start being populated
				font_size_cache['version'] = CFConst.GAME_VERSION


# This function resets the game to the same state as when
# the board loads for the first time. Only works when you're running
# off of the Main scene.
func reset_game() -> void:
	var main = cfc.NMAP.main
	clear()
	await get_tree().create_timer(0.1).timeout
	main._ready()


# This function clears out the usual game nodes
# and prepares to either quit the game or reset.
func clear() -> void:
	flush_cache()
	are_all_nodes_mapped = false
	card_drag_ongoing = null
	if cfc.NMAP.has("board") and is_instance_valid(cfc.NMAP.get("board")):
		cfc.NMAP.board.queue_free()
	# We need to give Godot time to deinstance all nodes.
	await get_tree().create_timer(0.1).timeout
	NMAP.clear()


# This function exits the card-game part of the framework
# for example as preparation for returning to the main menu.
func quit_game() -> void:
	var main = null
	if cfc.NMAP.has("main"):
		main = cfc.NMAP.main
	clear()
	if main:
		main.queue_free()


# Empties the alterants cache (only thing cached for now) which will cause
# all the alterants engine fire anew for all requests.
#
# This is called after most game-state changes, but there's one notable exception:
# if you add an alterant to a card's `scripts` variable manually, then you need
# to flush the cache afterwards using this function.
func flush_cache() -> void:
	alterant_cache.clear()
	emit_signal("cache_cleared")


func hide_all_previews() -> void:
	for card_preview_node in cfc.get_tree().get_nodes_in_group("card_preview"):
		card_preview_node.hide_preview_card()
	for card_preview_node in cfc.get_tree().get_nodes_in_group("info_popup"):
		card_preview_node.hide()


func _on_viewport_resized() -> void:
	var pix = CFConst.DESIGN_RESOLUTION.x * CFConst.DESIGN_RESOLUTION.y
	var curr_pix = get_viewport().get_visible_rect().size.x * get_viewport().get_visible_rect().size.y
	curr_scale = curr_pix / pix
	if curr_scale > 1:
		curr_scale = 1


# The SignalPropagator is responsible for collecting all card signals
# and asking all cards to check if there's any automation they need to perform
class SignalPropagator:

	# This propagates a signal generally, so everything else knows to pick it up from here.
	# This means signals caught by the signal propagator can be used by anything else, not just cards.
	signal signal_received(trigger_card, trigger, details)
	# The working signals cards might send depending on their status changes
	# this array can be extended by signals added by other games
	var known_card_signals := [
		"card_rotated",
		"card_flipped",
		"card_viewed",
		"card_moved_to_board",
		"card_moved_to_pile",
		"card_moved_to_hand",
		"card_token_modified",
		"card_attached",
		"card_unattached",
		"card_targeted",
		"card_properties_modified",
		]

	# When a new card is instanced, it connects all its known signals
	# to the SignalPropagator
	func connect_new_card(card):
		for sgn in known_card_signals:
			if not card.is_connected(sgn, Callable(self, "_on_signal_received")):
				card.connect(sgn, Callable(self, "_on_signal_received"))


	# When a known signal is received, it asks all existing cards to check
	# If this triggers an automation for them
	#
	# This method requirses that each signal also passes its own name in the
	# trigger variable, is this is the key sought in the CardScriptDefinitions
	func _on_signal_received(
			trigger_card, trigger: String, details: Dictionary):
		# We use Godot groups to ask every card to check if they
		# have [ScriptingEngine] triggers for this signal.
		#
		# I don't know why, but if I use simply call_group(), this will
		# not execute on a "self" subject
		# when the trigger card has a grid_autoplacement set, and the player
		# drags the card on the grid itself. If the player drags the card
		# To an empty spot, it works fine
		# It also fails to execute if I use any other flag than GROUP_CALL_UNIQUE
		var tags = details.get("tags", [])
		var is_network_update: bool = \
				typeof(tags) == TYPE_ARRAY and tags.has("net")
		if not is_network_update:
			for card in cfc.get_tree().get_nodes_in_group("cards"):
				card.execute_scripts(trigger_card,trigger,details)
			# If we need other objects than cards to trigger signals,
			# add them to the 'scriptables' group and ensure they have
			# an "execute_scripts" function.
			for card in cfc.get_tree().get_nodes_in_group("scriptables"):
				card.execute_scripts(trigger_card,trigger,details)
#		cfc.get_tree().call_group_flags(SceneTree.GROUP_CALL_UNIQUE  ,"cards",
#				"execute_scripts",trigger_card,trigger,details)
		emit_signal("signal_received", trigger_card, trigger, details)
