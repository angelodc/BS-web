extends Node

# Le a sessao do Supabase gravada pelo lobby (online/site/auth.js). Fora da web
# nao existe login: token vazio mantem o fluxo anonimo por username.


func get_access_token() -> String:
	return _eval("window.bsAuthToken ? window.bsAuthToken() : ''")


func get_user_id() -> String:
	return _eval("window.bsAuthUserId ? window.bsAuthUserId() : ''")


func is_logged_in() -> bool:
	return not get_access_token().is_empty()


func _eval(expression: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var value = JavaScriptBridge.eval(expression, true)
	if value == null:
		return ""
	return str(value).strip_edges()
