# Optional recorder for building regression fixtures from a real match.
#
# The file is JSONL: one header line, one line per intent the table accepted or
# refused, and a footer. Each intent line carries the resolved intent, the
# action-log entry and the table state view for the acting seat, so a GUT test
# can replay or compare the match without a relay or the GUI.
#
# Recording is off until started from the match menu; the file lives in
# `user://MatchLogs/`. Hidden zones are recorded as the local table sees them,
# so sanitize the file before sharing it.
extends RefCounted

const TableSnapshot = preload("res://src/core/table/TableSnapshot.gd")

const ROOT := "user://MatchLogs/"
const SCHEMA := 1

# Overridable so tests write into their own folder.
var directory := ROOT

var _file: FileAccess = null
var _path := ""


func is_recording() -> bool:
	return _file != null


func path() -> String:
	return _path


func start(note := "") -> Dictionary:
	if is_recording():
		return {"ok": true, "path": _path}
	var error := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(directory))
	if error != OK and error != ERR_ALREADY_EXISTS:
		return {"ok": false, "reason": "Não foi possível criar " + directory}
	_path = _unique_path()
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		_path = ""
		return {"ok": false,
				"reason": "Não foi possível abrir o arquivo de gravação."}
	_write({
		"schema": SCHEMA,
		"kind": "header",
		"at": Time.get_unix_time_from_system(),
		"engine": str(Engine.get_version_info().get("string", "")),
		"game_id": str(Multiplayer.game_id),
		"mode": _mode(),
		"p1": str(Multiplayer.p1_username),
		"p2": str(Multiplayer.p2_username),
		"seat": int(Multiplayer.my_slot),
		"round": int(Multiplayer.round_number),
		"sequence": int(Multiplayer.sequence),
		"note": note,
	})
	return {"ok": true, "path": _path}


func stop(reason := "") -> void:
	if not is_recording():
		return
	_write({
		"schema": SCHEMA,
		"kind": "footer",
		"at": Time.get_unix_time_from_system(),
		"reason": reason,
	})
	_file.close()
	_file = null


# The player chose to throw the recording away; the file leaves no trace.
func discard() -> void:
	if is_recording():
		stop("descartada")
	if _path.is_empty():
		return
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	_path = ""


# Called by TableActions after every validated attempt. `intent` may be a
# refused intent; `result` is the dictionary TableActions returns.
func record_intent(intent: Dictionary, result: Dictionary, state = null,
		seat := 1) -> void:
	if not is_recording():
		return
	var line := {
		"schema": SCHEMA,
		"kind": "intent",
		"at": Time.get_unix_time_from_system(),
		"seat": int(seat),
		"ok": bool(result.get("ok", false)),
		"error": str(result.get("error", "")),
		"message": str(result.get("message", "")),
		"undone": bool(result.get("undone", false)),
		# Drags that took the legacy path did not run through validation, so the
		# line says so instead of passing for a validated intent.
		"external": bool(result.get("external", false)),
		"intent": _json_safe(intent),
		"entry": _json_safe(result.get("entry", {})),
	}
	if state != null and state.has_method("to_snapshot"):
		line["snapshot"] = _json_safe(state.to_snapshot(int(seat)))
	_write(line)


func _write(line: Dictionary) -> void:
	if _file == null:
		return
	_file.store_line(JSON.stringify(line))
	# Flush every line so a crash or a closed window keeps the captured match.
	_file.flush()


func _mode() -> String:
	if Multiplayer.is_solo():
		return "solo"
	if Multiplayer.is_session_active():
		return "multiplayer"
	return "local"


func _unique_path() -> String:
	var base := _sanitize(str(Multiplayer.game_id))
	if base.is_empty():
		base = "local"
	var stamp := Time.get_datetime_string_from_system()
	stamp = stamp.replace("T", "-").replace(":", "-")
	var candidate := directory + base + "-" + stamp
	var path := candidate + ".jsonl"
	var suffix := 2
	while FileAccess.file_exists(path):
		path = candidate + "-" + str(suffix) + ".jsonl"
		suffix += 1
	return path


func _sanitize(text: String) -> String:
	var safe := ""
	for character in text:
		if (character >= "a" and character <= "z") \
				or (character >= "A" and character <= "Z") \
				or (character >= "0" and character <= "9") \
				or character == "-" or character == "_":
			safe += character
		elif character == " " or character == ".":
			safe += "_"
	return safe


# Intents normally arrive already resolved to ids, but a caller may still hold
# a Card node. JSON cannot serialize nodes, so those become their table id.
func _json_safe(value):
	if value is Card:
		return TableSnapshot.id_of(value)
	if value is Dictionary:
		var safe := {}
		for key in value:
			safe[str(key)] = _json_safe(value[key])
		return safe
	if value is Array:
		var safe := []
		for item in value:
			safe.append(_json_safe(item))
		return safe
	if value is Object:
		return str(value)
	return value
