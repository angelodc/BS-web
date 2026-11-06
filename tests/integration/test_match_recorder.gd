extends "res://tests/UTcommon.gd"

# Route B of the match logs: the table writes every intent it validates into a
# JSONL file, one line at a time. These tests check the file layout (header,
# intents, footer), that the snapshot on each line is the table the action
# produced, that refused intents and undos are kept, and that the production
# board hands the same recorder to its intent runner.

const MatchRecorder = preload("res://src/custom/MatchRecorder.gd")
const Snapshot = preload("res://src/core/table/TableSnapshot.gd")

const TEST_DIR := "user://test_matchlogs/"

var _recorder


func before_each():
	await setup_board()
	_cleanup()
	_recorder = MatchRecorder.new()
	_recorder.directory = TEST_DIR


func after_each():
	if is_instance_valid(board) and board.has_method("match_recorder"):
		var live = board.match_recorder()
		if live.is_recording():
			live.stop("teste")
	if _recorder.is_recording():
		_recorder.stop("teste")
	_cleanup()


func _cleanup() -> void:
	var directory := DirAccess.open(TEST_DIR)
	if directory == null:
		return
	for file in directory.get_files():
		directory.remove(file)


func _lines(path: String) -> Array:
	var lines := []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return lines
	while not file.eof_reached():
		var text := file.get_line()
		if text.is_empty():
			continue
		lines.append(JSON.parse_string(text))
	return lines


func _intents(lines: Array) -> Array:
	var intents := []
	for line in lines:
		if line is Dictionary and str(line.get("kind", "")) == "intent":
			intents.append(line)
	return intents


func _last_intent(path: String) -> Dictionary:
	var intents := _intents(_lines(path))
	assert_gt(intents.size(), 0, "nenhuma intenção gravada")
	if intents.is_empty():
		return {}
	return intents.back()


# -----------------------------------------------------------------------------
# File lifecycle
# -----------------------------------------------------------------------------

func test_start_writes_a_header_and_stop_writes_a_footer():
	var started: Dictionary = _recorder.start("teste")
	assert_true(bool(started.get("ok", false)), str(started.get("reason", "")))
	assert_true(_recorder.is_recording())
	var path: String = _recorder.path()
	assert_true(path.ends_with(".jsonl"), path)

	_recorder.stop("fim")

	assert_false(_recorder.is_recording())
	var lines := _lines(path)
	assert_eq(lines.size(), 2)
	assert_eq(str(lines[0]["kind"]), "header")
	assert_eq(int(lines[0]["schema"]), 1)
	assert_true(lines[0].has("game_id"))
	assert_eq(str(lines[1]["kind"]), "footer")
	assert_eq(str(lines[1]["reason"]), "fim")


func test_a_finished_recording_is_closed_and_a_new_start_opens_another_file():
	assert_true(bool(_recorder.start("primeira").get("ok", false)))
	var first: String = _recorder.path()
	_recorder.stop("fim")

	assert_true(bool(_recorder.start("segunda").get("ok", false)))
	var second: String = _recorder.path()
	_recorder.stop("fim")

	assert_ne(first, second)
	assert_true(FileAccess.file_exists(first))
	assert_true(FileAccess.file_exists(second))


func test_discard_closes_and_deletes_a_running_recording():
	assert_true(bool(_recorder.start("descartar").get("ok", false)))
	var path: String = _recorder.path()
	assert_true(FileAccess.file_exists(path))

	_recorder.discard()

	assert_false(_recorder.is_recording())
	assert_eq(_recorder.path(), "")
	assert_false(FileAccess.file_exists(path))


func test_discard_after_stop_deletes_the_finished_file():
	assert_true(bool(_recorder.start("descartar").get("ok", false)))
	var path: String = _recorder.path()
	_recorder.stop("fim")
	assert_true(FileAccess.file_exists(path))

	_recorder.discard()

	assert_eq(_recorder.path(), "")
	assert_false(FileAccess.file_exists(path))


func test_recording_before_start_writes_nothing():
	_recorder.record_intent({"op": "comprar"}, {"ok": true, "entry": {}}, null, 1)

	assert_false(_recorder.is_recording())
	assert_eq(_recorder.path(), "")

	_recorder.stop("sem_start")

	assert_false(_recorder.is_recording())


# -----------------------------------------------------------------------------
# Production wiring
# -----------------------------------------------------------------------------

func test_the_board_hands_its_recorder_to_the_intent_runner():
	var live = board.match_recorder()
	assert_eq(live.get_script(), MatchRecorder)
	assert_eq(board.table_actions().recorder, live)
	assert_eq(board.match_recorder(), live,
			"o tabuleiro reaproveita o mesmo gravador")


func test_the_board_records_a_real_intent_with_the_resulting_snapshot():
	var live = board.match_recorder()
	live.directory = TEST_DIR
	assert_true(bool(live.start("intenção").get("ok", false)))
	var path: String = live.path()
	var before := int(board.table_actions().state.zone_counts(1)["hand"])

	var result: Dictionary = board.apply_intent({"op": "comprar"})

	assert_true(bool(result.get("ok", false)), str(result.get("message", "")))
	live.stop("fim")
	var hand_after := int(board.table_actions().state.zone_counts(1)["hand"])
	assert_eq(hand_after, before + 1)

	var intents := _intents(_lines(path))
	assert_eq(intents.size(), 1)
	assert_true(bool(intents[0]["ok"]))
	assert_eq(str(intents[0]["intent"]["op"]), "comprar")
	assert_eq(int(intents[0]["snapshot"]["zones"]["hand"]["count"]),
			hand_after)


func test_a_refused_intent_is_recorded_as_a_failure():
	var live = board.match_recorder()
	live.directory = TEST_DIR
	assert_true(bool(live.start("recusa").get("ok", false)))
	var path: String = live.path()

	var result: Dictionary = board.apply_intent({"op": "voar"})

	assert_false(bool(result.get("ok", true)))
	live.stop("fim")
	var line := _last_intent(path)
	assert_false(bool(line["ok"]))
	assert_eq(str(line["intent"]["op"]), "voar")
	assert_eq(str(line["error"]), str(result.get("error", "")))
	assert_false(str(line["message"]).is_empty())


func test_an_undo_is_recorded_as_an_undone_intent():
	var live = board.match_recorder()
	live.directory = TEST_DIR
	assert_true(bool(live.start("desfazer").get("ok", false)))
	var path: String = live.path()

	assert_true(bool(board.apply_intent({"op": "comprar"}).get("ok", false)))
	var undone: Dictionary = board.apply_intent({"op": "desfazer"})

	assert_true(bool(undone.get("ok", false)), str(undone.get("message", "")))
	live.stop("fim")
	var line := _last_intent(path)
	assert_eq(str(line["intent"]["op"]), "desfazer")
	assert_true(bool(line["undone"]))
	assert_eq(int(line["snapshot"]["zones"]["hand"]["count"]), 0)


# -----------------------------------------------------------------------------
# Drops that take the legacy path
# -----------------------------------------------------------------------------

func _prepare_grid() -> void:
	var grid = board.get_node("BoardPlacementGrid")
	grid.visible = true
	grid.position = Vector2(200, 200)


func test_a_drop_that_skips_the_intent_runner_is_recorded_as_external():
	var live = board.match_recorder()
	live.directory = TEST_DIR
	assert_true(bool(live.start("arrasto").get("ok", false)))
	var path: String = live.path()
	_prepare_grid()
	var cards := draw_test_cards(1)
	await yield_for(0.1)

	await drag_drop(cards[0], Vector2(250, 300))
	await yield_for(0.6)
	live.stop("fim")

	var line := _last_intent(path)
	assert_true(bool(line["external"]))
	assert_eq(str(line["intent"]["op"]), "arrastar")
	assert_eq(str(line["entry"]["card"]), Snapshot.id_of(cards[0]))
	assert_true(str(line["entry"]["to"]).begins_with("p1:campo:"),
			str(line["entry"]["to"]))
	assert_eq(str(line["entry"]["from"]), "p1:mão:1")
	assert_eq(int(line["snapshot"]["zones"]["hand"]["count"]), 0)


func test_a_drop_that_leaves_the_card_where_it_was_is_not_recorded():
	var live = board.match_recorder()
	live.directory = TEST_DIR
	assert_true(bool(live.start("arrasto").get("ok", false)))
	var path: String = live.path()
	var cards := draw_test_cards(1)
	await yield_for(0.1)

	# The board is told about a drop and nothing moves, so the address stays the
	# same and there is nothing to record.
	board.note_drop(cards[0], board)
	await yield_for(0.6)
	live.stop("fim")

	assert_eq(_intents(_lines(path)).size(), 0)
