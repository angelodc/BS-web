extends "res://tests/UTcommon.gd"

# The local report store behind the bug icon. These tests keep the folder
# overridden so the real user://reports/ used by the developer is untouched.

const FeedbackScript = preload("res://src/custom/Feedback.gd")
const FeedbackButtonScript = preload("res://src/custom/FeedbackButton.gd")
const FeedbackDialogScript = preload("res://src/custom/FeedbackDialog.gd")
const FeedbackAdminScript = preload("res://src/custom/FeedbackAdmin.gd")
const TEST_DIR := "user://test_feedback/"

var _feedback


func before_each():
	_cleanup()
	DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(TEST_DIR))
	_feedback = FeedbackScript.new()
	_feedback.directory = TEST_DIR


func after_each():
	_cleanup()
	if is_instance_valid(_feedback):
		_feedback.free()


func _cleanup() -> void:
	var root := DirAccess.open(TEST_DIR)
	if root == null:
		return
	for folder in root.get_directories():
		var path := TEST_DIR + folder
		var nested := DirAccess.open(path)
		if nested != null:
			for file in nested.get_files():
				nested.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + "/"))
	for file in root.get_files():
		root.remove(file)


func _picture(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.8))
	return image


func test_the_three_ui_scripts_build_their_nodes():
	var button = add_child_autofree(FeedbackButtonScript.new())
	await get_tree().process_frame
	assert_true(button is Control)

	var dialog = add_child_autofree(FeedbackDialogScript.new())
	await get_tree().process_frame
	assert_true(dialog is Window)
	assert_true(dialog.get_child_count() > 0, "o formulário monta os campos")

	var admin = add_child_autofree(FeedbackAdminScript.new())
	await get_tree().process_frame
	admin.open()
	assert_true(admin.get_child_count() > 0, "o leitor monta a lista")


func test_the_hint_is_complete_on_the_first_hover():
	var button = add_child_autofree(FeedbackButtonScript.new())
	await get_tree().process_frame
	button._show_hint()
	var hint: Label = button._hint
	await get_tree().process_frame

	assert_eq(hint.text, FeedbackButtonScript.HINT_TEXT)
	assert_false(hint.text.strip_edges().is_empty())
	assert_eq(hint.size, FeedbackButtonScript.HINT_SIZE,
			"o primeiro hover já abre no tamanho final")
	assert_true(hint.get_combined_minimum_size().y
			<= FeedbackButtonScript.HINT_SIZE.y,
			"o texto cabe na altura sem estourar o mínimo medido")
	assert_eq(hint.get_visible_line_count(), hint.get_line_count(),
			"todas as linhas quebradas aparecem na primeira vez")


func test_a_report_keeps_its_json_print_log_and_recording():
	var recording := TEST_DIR + "partida.jsonl"
	var recorder := FileAccess.open(recording, FileAccess.WRITE)
	recorder.store_line("{\"kind\":\"header\"}")
	recorder.store_line("{\"kind\":\"intent\"}")
	recorder.close()

	var result: Dictionary = _feedback.save_report({
		"kind": "bug",
		"message": "A carta não virou.",
		"contact": "doug@example.com",
		"card": {"key": "carta_1", "display": "Carta 1", "zone": "board"},
	}, _picture(2000, 1000), "primeira\nsegunda\nterceira", recording)

	assert_true(bool(result.get("ok", false)), str(result.get("reason", "")))
	var folder := str(result.get("path", ""))
	assert_true(FileAccess.file_exists(folder + "report.json"))
	assert_true(FileAccess.file_exists(folder + "screenshot.png"))
	assert_true(FileAccess.file_exists(folder + "log.txt"))
	assert_true(FileAccess.file_exists(folder + "match.jsonl"))

	var saved := Image.new()
	assert_eq(saved.load(folder + "screenshot.png"), OK)
	assert_eq(saved.get_size(), Vector2i(1600, 800),
			"o print é reduzido a 1600 px de largura")


func test_list_reports_returns_the_newest_first():
	var first: Dictionary = _feedback.save_report(
			{"kind": "bug", "message": "antigo"})
	assert_true(bool(first.get("ok", false)))
	OS.delay_msec(5)
	var second: Dictionary = _feedback.save_report(
			{"kind": "suggestion", "message": "novo"})
	assert_true(bool(second.get("ok", false)))

	var reports: Array = _feedback.list_reports()

	assert_eq(reports.size(), 2)
	assert_eq(str(reports[0].get("message")), "novo")
	assert_eq(str(reports[1].get("message")), "antigo")
	assert_eq(str(reports[0].get("status")), "local")
	assert_true(str(reports[0].get("app_version", "")).length() > 0)


func test_reports_with_the_same_timestamp_keep_their_sequence():
	for suffix in [1, 2]:
		var folder := TEST_DIR + "2026-01-01_10-00-00-" + str(suffix) + "/"
		DirAccess.make_dir_recursive_absolute(
				ProjectSettings.globalize_path(folder))
		var file := FileAccess.open(folder + "report.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({
			"message": "relato " + str(suffix),
			"created_at": 1000.5,
		}))
		file.close()

	var reports: Array = _feedback.list_reports()

	assert_eq(reports.size(), 2)
	assert_eq(str(reports[0].get("message")), "relato 2")
	assert_eq(str(reports[1].get("message")), "relato 1")


func test_the_runtime_log_excerpt_is_capped_to_the_tail():
	for index in range(10):
		_feedback.log_runtime("linha " + str(index))

	var excerpt: String = _feedback.runtime_log_excerpt(3)

	assert_true(excerpt.contains("linha 9"), excerpt)
	assert_false(excerpt.contains("linha 6"), excerpt)


func test_an_active_session_from_the_last_boot_becomes_a_crash_report():
	var path := TEST_DIR + "session.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"active": true,
		"clean": false,
		"started_at": Time.get_unix_time_from_system() - 60,
		"context": {"room": "ABC123", "mode": "multiplayer"},
		"recording": "",
	}))
	file.close()

	_feedback._check_previous_session()

	assert_false(_feedback.take_boot_notice().is_empty())
	var reports: Array = _feedback.list_reports()
	assert_eq(reports.size(), 1)
	assert_true(bool(reports[0].get("auto", false)))
	assert_eq(str(reports[0].get("kind")), "bug")
	assert_eq(str(reports[0]["game"].get("room")), "ABC123")


func test_a_clean_session_does_not_create_a_report():
	var path := TEST_DIR + "session.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"active": false,
		"clean": true,
		"started_at": Time.get_unix_time_from_system(),
	}))
	file.close()

	_feedback._check_previous_session()

	assert_true(_feedback.take_boot_notice().is_empty())
	assert_eq(_feedback.list_reports().size(), 0)
