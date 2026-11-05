extends Node

# Fonte unica da versao: online/site/version.json. O mesmo arquivo e servido
# pelo site em /version.json e entra no PCK pelo include_filter do preset Web.

const VERSION_PATH := "res://online/site/version.json"
const FALLBACK := "0.0.0"

var semver: String = FALLBACK


func _ready() -> void:
	semver = _read_version()


func _read_version() -> String:
	if not FileAccess.file_exists(VERSION_PATH):
		return FALLBACK
	var file := FileAccess.open(VERSION_PATH, FileAccess.READ)
	if file == null:
		return FALLBACK
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return FALLBACK
	if typeof(json.data) != TYPE_DICTIONARY:
		return FALLBACK
	return str(json.data.get("version", FALLBACK))


func display_text(commit: String = "") -> String:
	var text := "v" + semver
	if not commit.is_empty():
		text += " (" + commit.substr(0, 7) + ")"
	return text
