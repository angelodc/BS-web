# Card Gaming Framework ScriptingEngine Utilities
#
# This is a library of static functions we had to separate to avoid
# cyclic dependencies
#
# This class needs to have no references to [ScriptingObject]
class_name CFScriptUtils
extends RefCounted

# Handles modifying the intensity of tasks based on altering scripts on cards
#
# Returns a Dictionary holding two keys
# * value_alteration: The total modification found from all alterants
# * alterants_details: A dictionary where each key is the Card object
# 	of each alterant, and each value is the modification done by that
#	specific alterant.
static func get_altered_value(
		_owner,
		task_name: String,
		task_properties: Dictionary,
		value: int,
		subject = null) -> Dictionary:
	var alterant_cache_key = _alterant_cache_key(
			_owner, task_name, task_properties, value)
	# If we've already performed this alterant engine run, we just
	# use the previously discovered value.
	if cfc.alterant_cache.get(alterant_cache_key):
		return(cfc.alterant_cache[alterant_cache_key])
	var value_alteration := 0
	var alterants_details := {}
	for entry in _find_alterant_scripts(
			_owner, task_name, task_properties, subject):
		var alteng = cfc.alterant_engine.new(
				_owner,
				entry.obj,
				entry.state_scripts,
				entry.task_details,
				subject)
		if not alteng.all_alterations_completed:
			await alteng.alterations_completed
		value_alteration += alteng.alteration
		# We don't want to register alterants which didn't modify the number.
		if alteng.alteration != 0:
			# Each key in the alterants_details dictionary is the
			# card object of each alterant. The value is the alteration
			# this alterant has added to the total.
			alterants_details[entry.obj] = alteng.alteration
	return(_finalize_altered_value(
			alterant_cache_key, value, value_alteration, alterants_details))


# Non-suspending variant of get_altered_value() for synchronous callers
# like Card.get_property().
#
# Returns the same dictionary as get_altered_value() when the value can be
# computed without waiting (cache hit, or no objects with alterant scripts
# on the table). Returns an empty dictionary when alterant scripts exist
# and would need to be executed asynchronously; the caller decides how to
# proceed in that case.
static func get_altered_value_no_wait(
		_owner,
		task_name: String,
		task_properties: Dictionary,
		value: int,
		subject = null) -> Dictionary:
	var alterant_cache_key = _alterant_cache_key(
			_owner, task_name, task_properties, value)
	if cfc.alterant_cache.get(alterant_cache_key):
		return(cfc.alterant_cache[alterant_cache_key])
	var alterant_scripts := _find_alterant_scripts(
			_owner, task_name, task_properties, subject)
	if not alterant_scripts.is_empty():
		return({})
	return(_finalize_altered_value(alterant_cache_key, value, 0, {}))


# The key for the alterant cache is the hash of the
# values passed to this function.
# This is the only way to compare dicts.
static func _alterant_cache_key(
		_owner,
		task_name: String,
		task_properties: Dictionary,
		value: int) -> int:
	return {
		"_owner_card": _owner,
		"task_name": task_name,
		"task_properties": task_properties,
		"value": value,
		"subject": value
	}.hash()


# Returns an array of dictionaries with the keys obj, state_scripts and
# task_details, one for each object on the table which has alterant scripts
# for the requested task.
static func _find_alterant_scripts(
		_owner,
		task_name: String,
		task_properties: Dictionary,
		subject = null) -> Array:
	var entries := []
	var scriptables_array : Array =\
			cfc.get_tree().get_nodes_in_group("cards")\
			+ cfc.get_tree().get_nodes_in_group("scriptables")
	for obj in scriptables_array:
		var scripts = obj.retrieve_scripts(SP.KEY_ALTERANTS)
		# We select which scripts to run from the card, based on it state
		var state_scripts = scripts.get(obj.get_state_exec(), [])
		# To avoid unnecessary operations
		# we evoke the AlterantEngine only if we have something to execute
		if len(state_scripts):
			var task_details = _generate_trigger_details(task_name, task_properties)
			entries.append({
				"obj": obj,
				"state_scripts": state_scripts,
				"task_details": task_details,
			})
	return(entries)


static func _finalize_altered_value(
		alterant_cache_key: int,
		value: int,
		value_alteration: int,
		alterants_details: Dictionary) -> Dictionary:
	# As a general rule, we don't want a positive number to turn
	# negative (and the other way around) due to an alteration
	# For example: if a card says, "decrease all costs by 3",
	# we don't want a card with 1 cost, to end up giving the player 2 money.
	if value < 0 and value + value_alteration > 0:
		# warning-ignore:narrowing_conversion
		value_alteration = abs(value)
	elif value > 0 and value + value_alteration < 0:
		value_alteration = -value
	var return_dict := {
		"value_alteration": value_alteration,
		"alterants_details": alterants_details
	}
	# If this is the first time we discover this alteration value
	# we also store it in our alterant cache
	cfc.alterant_cache[alterant_cache_key] = return_dict
	return(return_dict)

# Parses a [ScriptTask]'s properties and extracts the details a [ScriptAlter]
# needs to check if its allowed to modify that task.
static func _generate_trigger_details(task_name, task_properties) -> Dictionary:
	var details = {
		SP.KEY_TAGS: task_properties.get(SP.KEY_TAGS),
		SP.TRIGGER_TASK_NAME: task_name}
	# This dictionary key is a ScriptEngine task name which can be modified
	# by alterants. The value is an array of task properties we need to pass
	# to the trigger filter, to check if this task is relevant to be altered.
	var details_needed_per_task := {
		"mod_tokens": [SP.KEY_TOKEN_NAME,],
		"mod_counter": [SP.KEY_COUNTER_NAME,],
		"modify_properties": [
			SP.TRIGGER_PROPERTY_NAME,
			SP.KEY_MODIFICATION,
			SP.TRIGGER_PREV_COUNT,
			SP.TRIGGER_NEW_COUNT,
		],
		"spawn_card": [SP.KEY_CARD_NAME,],
		"get_token": [SP.KEY_TOKEN_NAME,],
		"get_property": [SP.KEY_PROPERTY_NAME,],
		"get_counter": [SP.KEY_COUNTER_NAME,],}
	for property in details_needed_per_task.get(task_name,[]):
		details[property] = task_properties.get(property)
	return(details)
