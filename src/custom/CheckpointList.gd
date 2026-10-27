extends WindowDialog

signal resume_requested(game_id, participants, as_host)

const CheckpointStore = preload("res://src/custom/CheckpointStore.gd")

const PHASE_LABELS := {
	"REG": "Regressiva",
	"PREP": "Preparação",
	"ADJ": "Ajuste",
	"ANT": "Antecipação",
	"ATK": "Ataque",
}

onready var _games: ItemList = $VBox/Games
onready var _status: Label = $VBox/Status
onready var _host_button: Button = $VBox/Buttons/Host
onready var _join_button: Button = $VBox/Buttons/Join
onready var _refresh_button: Button = $VBox/Buttons/Refresh

var _entries := []
var _username := ""
var _selected := -1


func _ready() -> void:
	_games.connect("item_selected", self, "_on_game_selected")
	_games.connect("nothing_selected", self, "_on_nothing_selected")
	_host_button.connect("pressed", self, "_on_host_pressed")
	_join_button.connect("pressed", self, "_on_join_pressed")
	_refresh_button.connect("pressed", self, "_reload")
	connect("about_to_show", self, "_reload")
	_update_buttons()


func open(username: String) -> void:
	_username = username.strip_edges()
	_set_status("")
	popup_centered(Vector2(660, 470))
	_reload()


func set_status(message: String) -> void:
	_set_status(message)


func _reload() -> void:
	_selected = -1
	_entries = []
	_games.clear()
	var games := CheckpointStore.list_games()
	var shown := 0
	var corrupted := 0
	for game in games:
		var participants: Array = game.get("participants", [])
		var join_only := bool(game.get("join_only", false))
		if not join_only \
				and (participants.size() != 2 \
				or (not _username.empty() and not _username in participants)):
			continue
		_entries.append(game)
		var index := _entries.size() - 1
		var intact := bool(game.get("has_intact", false))
		if not intact:
			corrupted += 1
		_games.add_item(_format_game(game, intact))
		shown += 1
	if shown == 0:
		_set_status("Nenhum checkpoint local encontrado para este username.")
	elif corrupted == shown:
		_set_status("Os checkpoints locais estão corrompidos. "
				+ "Tente entrar na sala do outro jogador; se ele tiver "
				+ "um checkpoint íntegro, a retomada pode ser concluída.")
	else:
		_set_status("Escolha uma partida salva para hospedar ou entrar "
				+ "na sala de retomada do outro jogador.")
	_update_buttons()


func _format_game(game: Dictionary, intact: bool) -> String:
	var participants: Array = game.get("participants", [])
	var join_only := bool(game.get("join_only", false))
	var label := "Partida"
	if join_only:
		label = "Partida com save local ilegível"
	elif participants.size() == 2:
		if _username == str(participants[0]):
			label = "vs " + str(participants[1])
		elif _username == str(participants[1]):
			label = "vs " + str(participants[0])
		else:
			label = str(participants[0]) + " vs " + str(participants[1])
	var phase := str(game.get("phase", ""))
	var phase_label := str(PHASE_LABELS.get(phase, phase))
	var text := label
	if not join_only:
		text += " · Rodada " + str(game.get("round", 0)) \
				+ " · " + phase_label \
				+ " · seq #" + str(game.get("latest_sequence", -1)) \
				+ " · " + _format_time(int(game.get("saved_at", 0)))
	if join_only:
		text += " · entre na sala de retomada do oponente"
	elif not intact:
		text += " · checkpoint local corrompido"
	return text


func _format_time(unix_time: int) -> String:
	if unix_time <= 0:
		return "data desconhecida"
	var date := OS.get_datetime_from_unix_time(unix_time)
	return "%02d/%02d/%04d %02d:%02d" % [
		int(date["day"]), int(date["month"]), int(date["year"]),
		int(date["hour"]), int(date["minute"]),
	]


func _on_game_selected(index: int) -> void:
	_selected = index
	_update_buttons()


func _on_nothing_selected() -> void:
	_selected = -1
	_update_buttons()


func _update_buttons() -> void:
	var valid := _selected >= 0 and _selected < _entries.size()
	var join_only := valid and bool(_entries[_selected].get("join_only", false))
	_host_button.disabled = not valid or join_only
	_join_button.disabled = not valid


func _on_host_pressed() -> void:
	_request_resume(true)


func _on_join_pressed() -> void:
	_request_resume(false)


func _request_resume(as_host: bool) -> void:
	if _selected < 0 or _selected >= _entries.size():
		return
	var game: Dictionary = _entries[_selected]
	var join_only := bool(game.get("join_only", false))
	if as_host and join_only:
		_set_status("Este save local está ilegível; entre na sala do oponente.")
		return
	var participants: Array = game.get("participants", [])
	if not join_only and participants.size() != 2:
		_set_status("Este checkpoint não identifica os dois jogadores.")
		return
	_set_status("Conectando ao relay...")
	emit_signal(
			"resume_requested",
			str(game.get("game_id", "")),
			participants,
			as_host)


func _set_status(message: String) -> void:
	_status.text = message
