# Local checkpoints for LAN matches.
#
# Hidden hand/deck data is protected with a username-derived obfuscation only.
# The username is public and visible to the opponent, so this is NOT secure
# encryption; it only avoids casual exposure, as documented in MULTIPLAYER.md.
extends Reference

const ROOT := "user://Checkpoints/"
const SCHEMA_VERSION := 1
const ENVELOPE_PREFIX := "BSMP1:"


static func ensure_root() -> bool:
	var directory := Directory.new()
	var error := directory.make_dir_recursive(ROOT)
	return error == OK or error == ERR_ALREADY_EXISTS


static func game_directory(game_id: String) -> String:
	return ROOT + _safe_game_id(game_id) + "/"


static func checkpoint_path(game_id: String, sequence: int) -> String:
	return game_directory(game_id) + str(sequence) + ".json"


static func _safe_game_id(game_id: String) -> String:
	var safe := ""
	for character in str(game_id):
		if (character >= "a" and character <= "z") \
				or (character >= "A" and character <= "Z") \
				or (character >= "0" and character <= "9") \
				or character == "-" or character == "_":
			safe += character
	if safe.empty():
		return "sem_id"
	return safe


static func canonical(value) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var keys = value.keys()
			keys.sort()
			var parts := []
			for key in keys:
				parts.append(JSON.print(str(key)) + ":" + canonical(value[key]))
			return "{" + PoolStringArray(parts).join(",") + "}"
		TYPE_ARRAY:
			var parts := []
			for item in value:
				parts.append(canonical(item))
			return "[" + PoolStringArray(parts).join(",") + "]"
		TYPE_STRING:
			return JSON.print(value)
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_NIL:
			return "null"
		TYPE_INT, TYPE_REAL:
			return str(value)
		_:
			return JSON.print(str(value))


static func public_checksum(public_state: Dictionary) -> String:
	return canonical(public_state).sha256_text()


static func private_checksum(payload: Dictionary) -> String:
	var copy = payload.duplicate(true)
	copy.erase("checksum")
	return canonical(copy).sha256_text()


static func _xor_bytes(bytes: PoolByteArray, username: String) -> PoolByteArray:
	var key_bytes := username.sha256_text().to_ascii()
	var output := PoolByteArray()
	output.resize(bytes.size())
	if key_bytes.empty():
		return bytes
	for index in range(bytes.size()):
		output[index] = bytes[index] ^ key_bytes[index % key_bytes.size()]
	return output


static func protect_payload(payload: Dictionary, username: String) -> String:
	var protected = payload.duplicate(true)
	protected.erase("checksum")
	protected["username"] = username
	protected["checksum"] = private_checksum(protected)
	var text := JSON.print(protected)
	var encrypted := _xor_bytes(text.to_utf8(), username)
	return ENVELOPE_PREFIX + Marshalls.raw_to_base64(encrypted)


static func unprotect_payload(envelope: String, username: String) -> Dictionary:
	if not str(envelope).begins_with(ENVELOPE_PREFIX):
		return {}
	var encoded := str(envelope).substr(ENVELOPE_PREFIX.length())
	var encrypted := Marshalls.base64_to_raw(encoded)
	if encrypted.empty():
		return {}
	var text := _xor_bytes(encrypted, username).get_string_from_utf8()
	var parsed := JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return {}
	var payload: Dictionary = parsed.result
	if str(payload.get("username", "")) != username:
		return {}
	if str(payload.get("checksum", "")) != private_checksum(payload):
		return {}
	return payload


static func validate_checkpoint(data: Dictionary) -> Dictionary:
	if int(data.get("schema", 0)) != SCHEMA_VERSION:
		return {"ok": false, "reason": "Versao de checkpoint desconhecida."}
	var game_id := str(data.get("game_id", ""))
	var p1 := str(data.get("p1", ""))
	var p2 := str(data.get("p2", ""))
	if game_id.empty() or p1.empty() or p2.empty() or p1 == p2:
		return {"ok": false, "reason": "Checkpoint sem participantes validos."}
	var public_state = data.get("public", {})
	if typeof(public_state) != TYPE_DICTIONARY or public_state.empty():
		return {"ok": false, "reason": "Checkpoint sem estado publico."}
	if str(data.get("public_checksum", "")) \
			!= public_checksum(public_state):
		return {"ok": false, "reason": "Estado publico do checkpoint corrompido."}
	var private_data = data.get("private", {})
	if typeof(private_data) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "Checkpoint sem dados privados."}
	if not private_data.has(p1) or not private_data.has(p2):
		return {"ok": false, "reason": "Checkpoint sem os dados privados dos dois jogadores."}
	var payloads := {}
	for username in [p1, p2]:
		var payload := unprotect_payload(
				str(private_data.get(username, "")), username)
		if payload.empty():
			return {
				"ok": false,
				"reason": "Dados privados de " + username + " estao corrompidos.",
			}
		payloads[username] = payload
	var hidden = public_state.get("hidden", {})
	if typeof(hidden) == TYPE_DICTIONARY:
		var slots := {p1: 1, p2: 2}
		for username in [p1, p2]:
			var slot_key := str(slots[username])
			var counts = hidden.get(slot_key, {})
			if typeof(counts) != TYPE_DICTIONARY:
				return {"ok": false, "reason": "Contagem oculta invalida."}
			var hand = payloads[username].get("hand", [])
			var deck = payloads[username].get("deck", [])
			if typeof(hand) != TYPE_ARRAY or typeof(deck) != TYPE_ARRAY:
				return {"ok": false, "reason": "Mao ou deck privado invalido."}
			if hand.size() != int(counts.get("hand", hand.size())) \
					or deck.size() != int(counts.get("deck", deck.size())):
				return {
					"ok": false,
					"reason": "Mao ou deck privado nao confere com o estado publico.",
				}
	return {"ok": true, "reason": "", "data": data}


static func read_checkpoint(path: String) -> Dictionary:
	var file := File.new()
	if not file.file_exists(path):
		return {"ok": false, "reason": "Checkpoint nao encontrado."}
	if file.open(path, File.READ) != OK:
		return {"ok": false, "reason": "Nao foi possivel ler o checkpoint."}
	var text := file.get_as_text()
	file.close()
	var parsed := JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "Checkpoint em formato invalido."}
	return validate_checkpoint(parsed.result)


static func load_checkpoint(game_id: String, sequence: int) -> Dictionary:
	return read_checkpoint(checkpoint_path(game_id, sequence))


static func save_checkpoint(
		game_id: String,
		sequence: int,
		round_number: int,
		step_index: int,
		starting_slot: int,
		rolls: Array,
		p1: String,
		p2: String,
		public_state: Dictionary,
		private_envelopes: Dictionary) -> Dictionary:
	if not ensure_root():
		return {"ok": false, "reason": "Nao foi possivel criar a pasta de checkpoints."}
	var directory := Directory.new()
	var directory_error := directory.make_dir_recursive(game_directory(game_id))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "reason": "Nao foi possivel criar a pasta do jogo."}
	if not private_envelopes.has(p1) or not private_envelopes.has(p2):
		return {"ok": false, "reason": "Faltam dados privados dos jogadores."}
	# Round-trip before checksumming so both peers hash the exact same bytes
	# they received over the relay, including float representation.
	var normalized := JSON.parse(JSON.print(public_state))
	if normalized.error != OK or typeof(normalized.result) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "Estado publico invalido."}
	public_state = normalized.result
	var data := {
		"schema": SCHEMA_VERSION,
		"game_id": game_id,
		"sequence": sequence,
		"round": round_number,
		"step": step_index,
		"phase": str(public_state.get("phase", "")),
		"starting_slot": starting_slot,
		"rolls": rolls,
		"p1": p1,
		"p2": p2,
		"saved_at": OS.get_unix_time(),
		"public": public_state,
		"public_checksum": public_checksum(public_state),
		"private": {
			p1: str(private_envelopes[p1]),
			p2: str(private_envelopes[p2]),
		},
	}
	var validation := validate_checkpoint(data)
	if not validation.get("ok", false):
		return validation
	var path := checkpoint_path(game_id, sequence)
	var temp_path := path + ".tmp"
	var file := File.new()
	if file.open(temp_path, File.WRITE) != OK:
		return {"ok": false, "reason": "Nao foi possivel gravar o checkpoint."}
	file.store_string(JSON.print(data, "\t"))
	file.close()
	if directory.file_exists(path):
		directory.remove(path)
	var rename_error := directory.rename(temp_path, path)
	if rename_error != OK:
		return {"ok": false, "reason": "Nao foi possivel concluir a gravacao do checkpoint."}
	return {"ok": true, "path": path, "data": data}


static func _read_manifest_file(path: String) -> Dictionary:
	var file := File.new()
	if not file.file_exists(path):
		return {}
	if file.open(path, File.READ) != OK:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed := JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parsed.result
	var validation := validate_checkpoint(data)
	var public_state = data.get("public", {})
	return {
		"ok": validation.get("ok", false),
		"reason": validation.get("reason", ""),
		"path": path,
		"game_id": str(data.get("game_id", "")),
		"sequence": int(data.get("sequence", -1)),
		"round": int(data.get("round", 0)),
		"step": int(data.get("step", 0)),
		"phase": str(data.get("phase", "")),
		"starting_slot": int(data.get("starting_slot", 1)),
		"p1": str(data.get("p1", "")),
		"p2": str(data.get("p2", "")),
		"saved_at": int(data.get("saved_at", 0)),
		"checksum": str(data.get("public_checksum", "")),
		"data": data,
	}


static func _checkpoint_files_for_game(game_id: String) -> Array:
	var files := []
	var directory := Directory.new()
	var game_dir := game_directory(game_id)
	if not directory.dir_exists(game_dir):
		return files
	if directory.open(game_dir) != OK:
		return files
	directory.list_dir_begin(true, true)
	var file_name := directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			files.append(game_dir + file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	return files


static func manifests_for_game(game_id: String) -> Array:
	var manifests := []
	for path in _checkpoint_files_for_game(game_id):
		var manifest := _read_manifest_file(path)
		if manifest.empty() or not manifest["ok"]:
			continue
		manifests.append({
			"sequence": manifest["sequence"],
			"checksum": manifest["checksum"],
			"round": manifest["round"],
			"step": manifest["step"],
			"phase": manifest["phase"],
			"saved_at": manifest["saved_at"],
		})
	for index in range(1, manifests.size()):
		var current = manifests[index]
		var position := index - 1
		while position >= 0 \
				and int(manifests[position]["sequence"]) \
				< int(current["sequence"]):
			manifests[position + 1] = manifests[position]
			position -= 1
		manifests[position + 1] = current
	return manifests


static func list_games() -> Array:
	var games := {}
	if not ensure_root():
		return []
	var directory := Directory.new()
	if directory.open(ROOT) != OK:
		return []
	directory.list_dir_begin(true, true)
	var entry := directory.get_next()
	while entry != "":
		if directory.current_is_dir():
			var game_id := entry
			var game_dir := ROOT + entry + "/"
			var game_files := Directory.new()
			if game_files.open(game_dir) == OK:
				var directory_has_json := false
				var directory_has_entry := false
				game_files.list_dir_begin(true, true)
				var file_name := game_files.get_next()
				while file_name != "":
					if not game_files.current_is_dir() \
							and file_name.ends_with(".json"):
						directory_has_json = true
						var manifest := _read_manifest_file(game_dir + file_name)
						if not manifest.empty():
							directory_has_entry = true
							var manifest_game_id := str(manifest["game_id"])
							if manifest_game_id.empty():
								manifest_game_id = game_id
							if not games.has(manifest_game_id):
								games[manifest_game_id] = {
									"game_id": manifest_game_id,
									"p1": "",
									"p2": "",
									"latest": {},
									"valid": [],
									"corrupted": [],
								}
							var game: Dictionary = games[manifest_game_id]
							if str(game["p1"]).empty() and not str(manifest["p1"]).empty():
								game["p1"] = manifest["p1"]
								game["p2"] = manifest["p2"]
							if manifest["ok"]:
								game["valid"].append(manifest)
								var latest = game["latest"]
								if latest.empty() \
										or int(manifest["sequence"]) > int(latest["sequence"]):
									game["latest"] = manifest
							else:
								game["corrupted"].append({
									"sequence": manifest["sequence"],
									"reason": manifest["reason"],
								})
					file_name = game_files.get_next()
				game_files.list_dir_end()
				if directory_has_json and not directory_has_entry:
					# Every file in this directory is unreadable. Keep the game
					# joinable through the opponent's intact copy.
					games[game_id] = {
						"game_id": game_id,
						"p1": "",
						"p2": "",
						"latest": {},
						"valid": [],
						"corrupted": [{
							"sequence": -1,
							"reason": "Checkpoint ilegivel.",
						}],
						"join_only": true,
					}
		entry = directory.get_next()
	directory.list_dir_end()
	var result := []
	for game_id in games:
		var game: Dictionary = games[game_id]
		if game["latest"].empty() and game["corrupted"].empty():
			continue
		var latest: Dictionary = game["latest"]
		game["manifests"] = []
		for manifest in game["valid"]:
			game["manifests"].append({
				"sequence": manifest["sequence"],
				"checksum": manifest["checksum"],
				"round": manifest["round"],
				"step": manifest["step"],
				"phase": manifest["phase"],
				"saved_at": manifest["saved_at"],
			})
		game["latest_sequence"] = int(latest.get("sequence", -1))
		game["round"] = int(latest.get("round", 0))
		game["step"] = int(latest.get("step", 0))
		game["phase"] = str(latest.get("phase", ""))
		game["saved_at"] = int(latest.get("saved_at", 0))
		var join_only := bool(game.get("join_only", false))
		game["join_only"] = join_only
		game["participants"] = [] if join_only else [game["p1"], game["p2"]]
		game["has_intact"] = not latest.empty()
		game.erase("valid")
		result.append(game)
	for index in range(1, result.size()):
		var current = result[index]
		var position := index - 1
		while position >= 0 \
				and int(result[position].get("saved_at", 0)) \
				< int(current.get("saved_at", 0)):
			result[position + 1] = result[position]
			position -= 1
		result[position + 1] = current
	return result


static func get_private_payload(data: Dictionary, username: String) -> Dictionary:
	var private_data = data.get("private", {})
	if typeof(private_data) != TYPE_DICTIONARY:
		return {}
	return unprotect_payload(str(private_data.get(username, "")), username)


static func reprotect_all(old_username: String, new_username: String) -> Dictionary:
	if old_username == new_username:
		return {"ok": true, "changed": 0, "skipped": 0, "errors": []}
	var changed := 0
	var skipped := 0
	var errors := []
	for game in list_games():
		for manifest in game["manifests"]:
			var path := checkpoint_path(
					str(game["game_id"]), int(manifest["sequence"]))
			var loaded := read_checkpoint(path)
			if not loaded.get("ok", false):
				continue
			var data: Dictionary = loaded["data"]
			var p1 := str(data.get("p1", ""))
			var p2 := str(data.get("p2", ""))
			if old_username != p1 and old_username != p2:
				continue
			var other := p2 if p1 == old_username else p1
			if new_username == other:
				# A checkpoint cannot hold two players with the same username.
				# Keep it under the old identity so the other player can still
				# resume instead of blocking the rename.
				skipped += 1
				errors.append("Checkpoint " + path + " mantido com o username anterior.")
				continue
			var payload := get_private_payload(data, old_username)
			if payload.empty():
				skipped += 1
				errors.append("Checkpoint " + path + " nao pode ser reaberto.")
				continue
			var new_p1 := p1
			var new_p2 := p2
			if p1 == old_username:
				new_p1 = new_username
			if p2 == old_username:
				new_p2 = new_username
			var private_data = data.get("private", {})
			var new_envelopes := {}
			for name in [p1, p2]:
				if name == old_username:
					var protected_payload = payload.duplicate(true)
					protected_payload.erase("username")
					protected_payload.erase("checksum")
					new_envelopes[new_username] = protect_payload(
							protected_payload, new_username)
				else:
					new_envelopes[name] = str(private_data.get(name, ""))
			data["p1"] = new_p1
			data["p2"] = new_p2
			data["private"] = new_envelopes
			var validation := validate_checkpoint(data)
			if not validation.get("ok", false):
				skipped += 1
				errors.append("Checkpoint " + path + " ficou invalido.")
				continue
			var file := File.new()
			var temp_path := path + ".tmp"
			if file.open(temp_path, File.WRITE) != OK:
				skipped += 1
				errors.append("Nao foi possivel reproteger " + path + ".")
				continue
			file.store_string(JSON.print(data, "\t"))
			file.close()
			var directory := Directory.new()
			if directory.file_exists(path):
				directory.remove(path)
			if directory.rename(temp_path, path) != OK:
				skipped += 1
				errors.append("Nao foi possivel substituir " + path + ".")
				continue
			changed += 1
	return {
		"ok": true,
		"changed": changed,
		"skipped": skipped,
		"errors": errors,
	}
