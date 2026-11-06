extends Node

# Relatos de bug/sugestão ficam em `user://reports/<id>/`: um report.json com o
# texto e o contexto, o print, o recorte de log da partida e a gravação JSONL
# quando o jogador estava gravando. Nada sai da máquina nesta fase; o menu
# oculto do lobby lê a mesma pasta.
#
# O heartbeat em session.json existe porque o Godot não garante executar código
# depois de um crash: a partida marca a sessão como ativa e só a desmarca numa
# saída normal. Se a próxima abertura encontrar uma sessão ativa, o jogo tratou
# como encerramento inesperado e registra o relato automaticamente.

const ROOT := "user://reports/"
const SESSION_FILE := "session.json"
const RUNTIME_FILE := "runtime.log"
const MAX_RUNTIME_LINES := 400
const MAX_LOG_LINES := 300
const SCREENSHOT_MAX_WIDTH := 1600
const RECORDING_COPY_LIMIT := 24 * 1024 * 1024

var directory := ROOT

var _session := {}
var _boot_notice := ""
var _target: Control = null
var _attached_card := {}


func _ready() -> void:
	if cfc.ut or _running_tests():
		return
	_ensure_directory()
	_trim_runtime_log()
	_check_previous_session()
	log_runtime("aplicativo aberto")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		end_match("fechou_a_janela")


func _exit_tree() -> void:
	end_match("saiu_do_aplicativo")


#-----------------------------------------------------------------------------
# Alvo do arrasto (o ícone no HUD)
#-----------------------------------------------------------------------------

func set_target(target: Control) -> void:
	_target = target


func clear_target(target: Control) -> void:
	if _target == target:
		_target = null


func is_pointer_over_target() -> bool:
	if not is_instance_valid(_target):
		return false
	return _target.get_global_rect().has_point(
			_target.get_global_mouse_position())


func attach_card(card: Card) -> Dictionary:
	_attached_card = {}
	if not is_instance_valid(card):
		return _attached_card
	_attached_card = {
		"key": str(card.definition_key()),
		"name": str(card.canonical_name),
		"display": str(card.properties.get("Name", card.canonical_name)),
		"zone": str(GameEvents.zone_for_card(card)),
		"seat": int(Multiplayer.my_slot),
		"faceup": bool(card.is_faceup),
	}
	# The reader lives in the lobby, outside any match, so the card's definition
	# travels in the report. Without it the preview could not be rebuilt there.
	var definition = JSON.parse_string(JSON.stringify(card.properties))
	if typeof(definition) == TYPE_DICTIONARY and not definition.is_empty():
		_attached_card["definition"] = definition
	return _attached_card.duplicate(true)


func attached_card() -> Dictionary:
	return _attached_card.duplicate(true)


func clear_attached_card() -> void:
	_attached_card = {}


# Chamado pelo override de drop da carta. Só consome a soltura quando o ponteiro
# está sobre o ícone; o restante do tabuleiro continua com o comportamento
# normal.
func try_capture_drop(card: Card) -> bool:
	if not is_pointer_over_target():
		return false
	attach_card(card)
	if is_instance_valid(_target) and _target.has_method("open_with_attached_card"):
		_target.call_deferred("open_with_attached_card")
	return true


#-----------------------------------------------------------------------------
# Sessão e crash
#-----------------------------------------------------------------------------

func begin_match() -> void:
	if cfc.ut:
		return
	_ensure_directory()
	_session = {
		"active": true,
		"clean": false,
		"started_at": _now(),
		"context": match_context(),
		"recording": current_recording_path(),
	}
	_write_json(_path(SESSION_FILE), _session)
	log_runtime("partida iniciada")


func end_match(reason := "") -> void:
	if cfc.ut or _session.is_empty():
		return
	if not bool(_session.get("active", false)):
		return
	_session["active"] = false
	_session["clean"] = true
	_session["ended_at"] = _now()
	_session["end_reason"] = reason
	_write_json(_path(SESSION_FILE), _session)
	log_runtime("partida encerrada: " + reason)


func take_boot_notice() -> String:
	var notice := _boot_notice
	_boot_notice = ""
	return notice


func _check_previous_session() -> void:
	var previous := _read_json(_path(SESSION_FILE))
	_session = {
		"active": false,
		"clean": true,
		"started_at": _now(),
	}
	if previous.is_empty():
		_write_json(_path(SESSION_FILE), _session)
		return
	if bool(previous.get("active", false)) \
			and not bool(previous.get("clean", true)):
		var context: Dictionary = previous.get("context", {})
		var report := {
			"kind": "bug",
			"message": "O jogo encerrou inesperadamente durante uma partida.",
			"contact": "",
			"auto": true,
			"game": context,
			"session_started_at": previous.get("started_at", 0),
		}
		var saved := save_report(report, null, match_log_text(),
				str(previous.get("recording", "")))
		if bool(saved.get("ok", false)):
			_boot_notice = "Um relato automático de encerramento inesperado " \
					+ "foi registrado."
	_write_json(_path(SESSION_FILE), _session)


# A suíte sobe antes de cfc.ut ser marcado; sem esta guarda o GUT poderia
# transformar a partida real do desenvolvedor num relato automático.
func _running_tests() -> bool:
	for argument in OS.get_cmdline_args():
		if "gut_cmdln" in argument or "tests/cli/tests.tscn" in argument:
			return true
	return false


#-----------------------------------------------------------------------------
# Relatos
#-----------------------------------------------------------------------------

func save_report(data: Dictionary, screenshot: Image = null, log_text := "",
		recording_path := "") -> Dictionary:
	_ensure_directory()
	var id := _new_id()
	var folder := directory + id + "/"
	var error := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(folder))
	if error != OK and error != ERR_ALREADY_EXISTS:
		return {"ok": false, "reason": "Não foi possível criar " + folder}
	var report: Dictionary = data.duplicate(true)
	var attachments := {}
	if screenshot != null:
		if screenshot.get_width() > SCREENSHOT_MAX_WIDTH:
			var height := int(round(float(screenshot.get_height()) \
					* SCREENSHOT_MAX_WIDTH / screenshot.get_width()))
			screenshot.resize(SCREENSHOT_MAX_WIDTH, max(height, 1),
					Image.INTERPOLATE_LANCZOS)
		var screenshot_path := folder + "screenshot.png"
		if screenshot.save_png(screenshot_path) == OK:
			attachments["screenshot"] = "screenshot.png"
	if not log_text.strip_edges().is_empty():
		var trimmed := _tail_lines(log_text, MAX_LOG_LINES)
		var log_path := folder + "log.txt"
		var log_file := FileAccess.open(log_path, FileAccess.WRITE)
		if log_file != null:
			log_file.store_string(trimmed)
			log_file.close()
			attachments["log"] = "log.txt"
			report["log_lines"] = trimmed.split("\n").size()
	if not recording_path.is_empty() and FileAccess.file_exists(recording_path):
		var recording_copy := folder + "match.jsonl"
		if _copy_file(recording_path, recording_copy):
			attachments["recording"] = "match.jsonl"
			report["recording_bytes"] = _file_size(recording_copy)
	report["schema"] = 1
	report["id"] = id
	report["created_at"] = _now()
	report["created_label"] = Time.get_datetime_string_from_system(
			false, true)
	report["status"] = "local"
	report["app_version"] = app_version()
	report["platform"] = platform_label()
	report["engine"] = str(Engine.get_version_info().get("string", ""))
	report["attachments"] = attachments
	if not report.has("game") or typeof(report["game"]) != TYPE_DICTIONARY:
		report["game"] = match_context()
	if not report.has("card") or typeof(report["card"]) != TYPE_DICTIONARY:
		report["card"] = {}
	_write_json(folder + "report.json", report)
	log_runtime("relato salvo: " + id)
	return {"ok": true, "id": id, "path": folder, "report": report}


# Newest first, so the hidden menu opens on the last report.
func list_reports() -> Array:
	var reports := []
	var folders := DirAccess.open(directory)
	if folders == null:
		return reports
	for name in folders.get_directories():
		var path := directory + name + "/report.json"
		var report := _read_json(path)
		if report.is_empty():
			continue
		report["_folder"] = directory + name + "/"
		reports.append(report)
	reports.sort_custom(func(a, b):
		return float(a.get("created_at", 0)) > float(b.get("created_at", 0)))
	return reports


func report_file(report: Dictionary, name: String) -> String:
	var attachments: Dictionary = report.get("attachments", {})
	if not attachments.has(name):
		return ""
	return str(report.get("_folder", "")) + str(attachments[name])


func load_report_image(report: Dictionary) -> Image:
	var path := report_file(report, "screenshot")
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return image


#-----------------------------------------------------------------------------
# Contexto e log
#-----------------------------------------------------------------------------

func match_context() -> Dictionary:
	return {
		"game_id": str(Multiplayer.game_id),
		"mode": _mode(),
		"room": str(Rede.room_id),
		"relay": str(Rede.last_address),
		"p1": str(Multiplayer.p1_username),
		"p2": str(Multiplayer.p2_username),
		"seat": int(Multiplayer.my_slot),
		"round": int(Multiplayer.round_number),
		"phase": str(Multiplayer.get_phase_label()),
	}


# The file belongs to the match, not only to the moment it is open: after the
# end-of-match choice it is still there and can be attached to a report.
func current_recording_path() -> String:
	var board = cfc.NMAP.get("board", null)
	if not is_instance_valid(board) or not board.has_method("match_recorder"):
		return ""
	var recorder = board.match_recorder()
	if not is_instance_valid(recorder):
		return ""
	var path := str(recorder.path())
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	return path


func runtime_log_excerpt(max_lines := MAX_LOG_LINES) -> String:
	var path := _path(RUNTIME_FILE)
	if not FileAccess.file_exists(path):
		return ""
	return _tail_lines(FileAccess.get_file_as_string(path), max_lines)


func match_log_text() -> String:
	var lines := ["== Eventos da partida =="]
	for entry in GameEvents.entries:
		if entry is Dictionary:
			lines.append(str(entry.get("text", "")))
	lines.append("== Registro do aplicativo ==")
	var runtime := runtime_log_excerpt(MAX_LOG_LINES)
	if not runtime.is_empty():
		lines.append(runtime)
	return _tail_lines("\n".join(PackedStringArray(lines)), MAX_LOG_LINES)


func log_runtime(text: String) -> void:
	var line := text.strip_edges()
	if line.is_empty():
		return
	_ensure_directory()
	var path := _path(RUNTIME_FILE)
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("[%s] %s" % [Time.get_time_string_from_system(), line])
	file.flush()
	file.close()


func app_version() -> String:
	var version := str(ProjectSettings.get_setting(
			"application/config/version", ""))
	return version if not version.is_empty() \
			else str(Engine.get_version_info().get("string", "desconhecida"))


func platform_label() -> String:
	if OS.has_feature("web"):
		return "web"
	if OS.has_feature("windows"):
		return "windows"
	if OS.has_feature("linux"):
		return "linux"
	if OS.has_feature("macos"):
		return "macos"
	return OS.get_name().to_lower()


#-----------------------------------------------------------------------------
# Arquivos
#-----------------------------------------------------------------------------

func _ensure_directory() -> void:
	DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(directory))


func _path(name: String) -> String:
	return directory + name


func _new_id() -> String:
	var stamp := Time.get_datetime_string_from_system()
	stamp = stamp.replace("T", "_").replace(":", "-")
	var suffix := 1
	var candidate := directory + stamp + "-1"
	while DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(candidate + "/")):
		suffix += 1
		candidate = directory + stamp + "-" + str(suffix)
	return candidate.get_file()


func _now() -> float:
	return Time.get_unix_time_from_system()


func _mode() -> String:
	if Multiplayer.is_solo():
		return "solo"
	if Multiplayer.is_session_active():
		return "multiplayer"
	return "local"


func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _tail_lines(text: String, max_lines: int) -> String:
	var lines := text.replace("\r\n", "\n").split("\n")
	if lines.size() <= max_lines:
		return text
	return "\n".join(PackedStringArray(
			lines.slice(lines.size() - max_lines)))


func _trim_runtime_log() -> void:
	var path := _path(RUNTIME_FILE)
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	var lines := text.replace("\r\n", "\n").split("\n")
	if lines.size() <= MAX_RUNTIME_LINES:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("\n".join(PackedStringArray(
			lines.slice(lines.size() - MAX_RUNTIME_LINES))))
	file.close()


func _copy_file(source: String, destination: String) -> bool:
	if _file_size(source) > RECORDING_COPY_LIMIT:
		return false
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return false
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		input.close()
		return false
	output.store_buffer(input.get_buffer(input.get_length()))
	output.close()
	input.close()
	return true


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size
