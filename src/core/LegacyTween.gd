# Godot 3 Tween node compatibility layer over Godot 4's SceneTreeTween.
#
# The Card Game Framework animation code accumulates property tracks with
# interpolate_property(), gates new batches on is_active(), runs everything
# together with start() and awaits tween_all_completed. Godot 4 removed the Tween
# node in favour of create_tween(), which has no accumulate / remove / is_active
# model, so this adapter reproduces the old surface on a parallel SceneTreeTween
# and keeps every existing call site working unchanged.
class_name LegacyTween
extends RefCounted

signal tween_all_completed

var _host: Node
var _pending: Array = []
var _active: Tween


func _init(host: Node) -> void:
	_host = host


func interpolate_property(
		object: Object,
		property: String,
		from_value,
		to_value,
		duration: float,
		trans_type: int = Tween.TRANS_LINEAR,
		ease_type: int = Tween.EASE_IN) -> void:
	_pending.append({
		"object": object,
		"property": property,
		"from": from_value,
		"to": to_value,
		"duration": duration,
		"trans": trans_type,
		"ease": ease_type,
	})


func remove(object: Object, property: String) -> void:
	for index in range(_pending.size() - 1, -1, -1):
		var track: Dictionary = _pending[index]
		if track["object"] == object and track["property"] == property:
			_pending.remove_at(index)


func remove_all() -> void:
	_pending.clear()
	_kill_active()


func stop_all() -> void:
	_pending.clear()
	_kill_active()


func start() -> void:
	if _pending.is_empty():
		return
	if _host == null or not _host.is_inside_tree():
		_pending.clear()
		return
	_kill_active()
	var tween := _host.create_tween().set_parallel(true)
	_active = tween
	for track in _pending:
		tween.tween_property(
				track["object"], track["property"], track["to"], track["duration"])\
				.from(track["from"])\
				.set_trans(track["trans"])\
				.set_ease(track["ease"])
	_pending.clear()
	tween.finished.connect(_on_active_finished)


func is_active() -> bool:
	return _active != null and _active.is_valid() and _active.is_running()


func get_runtime() -> float:
	var runtime := 0.0
	for track in _pending:
		runtime = max(runtime, track["duration"])
	return runtime


func _kill_active() -> void:
	if _active != null and _active.is_valid():
		_active.kill()
	_active = null


func _on_active_finished() -> void:
	_active = null
	tween_all_completed.emit()
