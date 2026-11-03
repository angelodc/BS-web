extends Node
# Runs both GUT suites from a scene and quits when they finish, so the runner
# works with or without a window.

const GUT_MAIN = preload("res://addons/gut/gut.gd")
const SUITES := ["res://tests/unit", "res://tests/integration"]

var _gut


func _ready() -> void:
	_gut = GUT_MAIN.new()
	_gut.end_run.connect(_on_tests_finished)
	add_child(_gut)
	for suite in SUITES:
		_gut.add_directory(suite)
	_gut.test_scripts()


func _on_tests_finished() -> void:
	var totals: Dictionary = _gut.get_summary().get_totals()
	get_tree().quit(1 if int(totals["failing"]) > 0 else 0)
