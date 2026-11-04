extends Node

# Ponte entre o jogo e o GA4 do site. No desktop e nos testes GUT tudo vira
# no-op: o JavaScriptBridge so existe no export web.

var _game_open_sent := false


func _ready() -> void:
	if not _enabled():
		return
	# O canvas do shell so tem tamanho depois dos primeiros frames.
	await get_tree().process_frame
	await get_tree().process_frame
	var user_id := Auth.get_user_id()
	if not user_id.is_empty():
		set_user_id(user_id)
	_emit_game_open()


func track(event_name: String, params: Dictionary = {}) -> void:
	if not _enabled() or event_name.is_empty():
		return
	JavaScriptBridge.eval(
			"window.bsTrack && window.bsTrack(%s, %s);"
			% [JSON.stringify(event_name), JSON.stringify(params)], true)


func set_user_id(uuid: String) -> void:
	if not _enabled():
		return
	JavaScriptBridge.eval(
			"window.bsSetUserId && window.bsSetUserId(%s);"
			% JSON.stringify(uuid), true)


func _enabled() -> bool:
	return OS.has_feature("web") and not cfc.ut


func _emit_game_open() -> void:
	if _game_open_sent:
		return
	_game_open_sent = true
	var metrics := _game_metrics()
	if not metrics.is_empty():
		track("game_open", metrics)


func _game_metrics() -> Dictionary:
	var raw = JavaScriptBridge.eval(
			"window.bsGameMetrics && window.bsGameMetrics()", true)
	if raw == null:
		return {}
	var parsed = JSON.parse_string(str(raw))
	return parsed if parsed is Dictionary else {}
