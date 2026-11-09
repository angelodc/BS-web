extends Window

signal deck_loaded(deck)

const DeckCatalog = preload("res://src/custom/DeckCatalog.gd")
const ValidationDialogScene = preload(
		"res://src/custom/BSDBDeckValidationDialog.tscn")

const BSDB_BASE_URL := "https://battlescenes.vercel.app/deck/"
const BSDB_CARDS_URL := "https://raw.githubusercontent.com/inimig0r/bsdb-imagens/refs/heads/main/dados/cards.json"
const CARD_CATALOG_CACHE_PATH := "user://BSDB/cards.json"
const SUPABASE_REST_URL := "https://xtdqcfchdqmqlbmkvdit.supabase.co/rest/v1"
const SUPABASE_PUBLIC_KEY := "sb_publishable_mx4QrlcZMx-FgZyGC7Q-uw_w3qbMhd9"
const DECK_CACHE_PATH := "user://Decks/"
# Old cached decks carry card data from the BSDB site; a mismatch forces the
# deck to be imported again from the GitHub catalog.
const DECK_CACHE_VERSION := 2
const VALID_CARD_TYPES := ["Personagem", "Suporte", "Habilidade", "Cenário"]
const ENERGY_CARD_TYPES := ["Personagem", "Suporte"]

enum RequestStage {
	DECK,
	DECK_CARDS,
	CARD_CATALOG,
}

@onready var _deck_url: LineEdit = $VBox/DeckURL
@onready var _status: Label = $VBox/Status
@onready var _import_button: Button = $VBox/Buttons/Import

var _request: HTTPRequest
var _request_stage: int = RequestStage.DECK
var _deck_id := ""
var _deck_record := {}
var _deck_cards := []
var _card_definitions := {}
var _validation_dialog: Window
var _validation_queue := []
var _pending_deck := {}
var _prefetched_deck := {}


func _ready() -> void:
	_request = HTTPRequest.new()
	# Browsers already decompress fetch bodies, so HTTPRequest decompressing
	# again fails with RESULT_BODY_DECOMPRESS_FAILED on the web build.
	if OS.has_feature("web"):
		_request.accept_gzip = false
	add_child(_request)
	# warning-ignore:return_value_discarded
	_request.request_completed.connect(_on_request_completed)
	# warning-ignore:return_value_discarded
	_import_button.pressed.connect(_on_import_pressed)
	_validation_dialog = ValidationDialogScene.instantiate()
	add_child(_validation_dialog)
	# warning-ignore:return_value_discarded
	_validation_dialog.card_confirmed.connect(_on_validation_confirmed)
	# warning-ignore:return_value_discarded
	_validation_dialog.canceled.connect(_on_validation_cancelled)
	if not cfc.card_image_prefetch_progress.is_connected(
			_on_card_image_prefetch_progress):
		# warning-ignore:return_value_discarded
		cfc.card_image_prefetch_progress.connect(
				_on_card_image_prefetch_progress)
	if not cfc.card_image_prefetch_finished.is_connected(
			_on_card_image_prefetch_finished):
		# warning-ignore:return_value_discarded
		cfc.card_image_prefetch_finished.connect(
				_on_card_image_prefetch_finished)


static func get_deck_id_from_url(url: String) -> String:
	var regex := RegEx.new()
	regex.compile(
			"^https://battlescenes\\.vercel\\.app/deck/"
			+ "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
			+ "[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/?$")
	var result = regex.search(url.strip_edges())
	if not result:
		return ""
	return result.get_string(1).to_lower()


func _on_import_pressed() -> void:
	var deck_id := get_deck_id_from_url(_deck_url.text)
	if not deck_id:
		_set_status(
				"Cole um link válido do BSDB, no formato "
				+ BSDB_BASE_URL + "{id}.")
		return
	_deck_id = deck_id
	var cached_deck = _load_cached_deck(deck_id)
	if not cached_deck.is_empty():
		_begin_validation(cached_deck)
		return
	_deck_record = {}
	_deck_cards.clear()
	_card_definitions.clear()
	_prefetched_deck = {}
	_request_stage = RequestStage.DECK
	_import_button.disabled = true
	_set_status("Buscando o deck no BSDB...")
	_request_get(
			SUPABASE_REST_URL + "/decks?select=id,title,description,cards_count"
			+ "&id=eq." + _deck_id, true)


func _request_get(url: String, with_key := false) -> void:
	var headers := PackedStringArray(["Accept: application/json"])
	if with_key:
		headers.append("apikey: " + SUPABASE_PUBLIC_KEY)
	var request_error := _request.request(url, headers)
	if request_error != OK:
		_fail_import(
				"Não foi possível iniciar a conexão com o BSDB ("
				+ str(request_error) + ").")


func _on_request_completed(
		result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	if _request_stage == RequestStage.CARD_CATALOG:
		_handle_card_catalog_response(result, response_code, body)
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_fail_import(
				"Falha ao baixar dados do BSDB (HTTP "
				+ str(response_code) + ", código "
				+ str(result) + "). Verifique a conexão e tente novamente.")
		return
	var test_json_conv = JSON.new()
	var parse_error := test_json_conv.parse(body.get_string_from_utf8())
	var parsed = test_json_conv.get_data()
	if parse_error != OK:
		_fail_import("O BSDB retornou dados em formato inválido.")
		return
	if typeof(parsed) != TYPE_ARRAY:
		_fail_import("A resposta do BSDB não contém uma lista válida.")
		return
	match _request_stage:
		RequestStage.DECK:
			_handle_deck_response(parsed)
		RequestStage.DECK_CARDS:
			_handle_deck_cards_response(parsed)


func _handle_deck_response(records: Array) -> void:
	if records.size() != 1 or typeof(records[0]) != TYPE_DICTIONARY:
		_fail_import("Não foi encontrado um deck público com esse link.")
		return
	_deck_record = records[0]
	_request_stage = RequestStage.DECK_CARDS
	_set_status("Carregando a lista de cartas...")
	_request_get(
			SUPABASE_REST_URL + "/deck_cards?select=card_id,quantity"
			+ "&deck_id=eq." + _deck_id, true)


func _handle_deck_cards_response(records: Array) -> void:
	if records.is_empty():
		_fail_import("O deck encontrado não possui cartas.")
		return
	var total_cards := 0
	for record in records:
		if typeof(record) != TYPE_DICTIONARY:
			_fail_import("A lista do deck contém uma carta inválida.")
			return
		var card_id = str(record.get("card_id", ""))
		var quantity = int(record.get("quantity", 0))
		if not card_id.is_valid_identifier() or quantity <= 0:
			_fail_import("A lista do deck contém uma carta inválida.")
			return
		_deck_cards.append({
			"card_id": card_id,
			"quantity": quantity,
		})
		total_cards += quantity
	if total_cards != int(_deck_record.get("cards_count", total_cards)):
		_fail_import("A quantidade de cartas do deck não confere com o BSDB.")
		return
	_request_stage = RequestStage.CARD_CATALOG
	_set_status("Baixando o catálogo de cartas do GitHub...")
	_request_get(BSDB_CARDS_URL)


func _handle_card_catalog_response(
		result: int, response_code: int, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		_save_card_catalog(body)
		var test_json_conv = JSON.new()
		var parse_error := test_json_conv.parse(body.get_string_from_utf8())
		var parsed = test_json_conv.get_data()
		if parse_error != OK:
			_fail_import("O catálogo do GitHub está em formato inválido.")
			return
		if typeof(parsed) != TYPE_ARRAY:
			_fail_import("O catálogo do GitHub não contém uma lista válida.")
			return
		_handle_card_catalog(parsed)
		return
	var cached := _load_cached_card_catalog()
	if cached.is_empty():
		_fail_import(
				"Não foi possível baixar o catálogo do GitHub (HTTP "
				+ str(response_code) + ", código " + str(result) + ").")
		return
	push_warning("Using the cached BSDB card catalog; GitHub request failed.")
	_handle_card_catalog(cached)


func _handle_card_catalog(records: Array) -> void:
	var catalog := {}
	for record in records:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var card_id := str(record.get("ID_CARD", ""))
		if not card_id.is_empty():
			catalog[card_id] = record
	for card in _deck_cards:
		var entry = catalog.get(card.card_id, null)
		if typeof(entry) != TYPE_DICTIONARY:
			_fail_import(
					"A carta " + str(card.card_id)
					+ " não está no catálogo do GitHub.")
			return
		var card_properties := make_card_properties(repo_card_to_record(entry))
		if card_properties.is_empty():
			_fail_import(
					"Não foi possível interpretar a carta "
					+ str(card.card_id) + " do catálogo do GitHub.")
			return
		_card_definitions[card.card_id] = card_properties
	var cards := {}
	for card in _deck_cards:
		cards[card.card_id] = card.quantity
	var deck := {
		"id": _deck_id,
		"name": _deck_record.get("title", "Deck do BSDB"),
		"cards": cards,
		"definitions": _card_definitions,
		"source_url": BSDB_BASE_URL + _deck_id,
		"cache_version": DECK_CACHE_VERSION,
	}
	_begin_validation(deck)


func _save_card_catalog(body: PackedByteArray) -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(
					CARD_CATALOG_CACHE_PATH.get_base_dir()))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return
	var file := FileAccess.open(CARD_CATALOG_CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(body)
	file.close()


func _load_cached_card_catalog() -> Array:
	if not FileAccess.file_exists(CARD_CATALOG_CACHE_PATH):
		return []
	var file := FileAccess.open(CARD_CATALOG_CACHE_PATH, FileAccess.READ)
	if file == null:
		return []
	var test_json_conv = JSON.new()
	var parse_error := test_json_conv.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return []
	var parsed = test_json_conv.get_data()
	return parsed if typeof(parsed) == TYPE_ARRAY else []


func _begin_validation(deck: Dictionary) -> void:
	_pending_deck = deck
	var definitions = deck.get("definitions", {})
	_card_definitions = definitions if typeof(definitions) == TYPE_DICTIONARY \
			else {}
	_validation_queue.clear()
	var keys := _card_definitions.keys()
	for index in range(keys.size()):
		var definition = _card_definitions[keys[index]]
		if typeof(definition) != TYPE_DICTIONARY:
			continue
		var missing := _missing_essential_fields(definition)
		if not missing.is_empty():
			_validation_queue.append({
				"key": keys[index],
				"card_index": index,
				"missing": missing,
			})
	if _validation_queue.is_empty():
		_finish_import()
		return
	_set_status(
			"Complete os dados essenciais de "
			+ str(_validation_queue.size()) + " carta(s) do deck.")
	_show_next_validation()


func _show_next_validation() -> void:
	if _validation_queue.is_empty():
		_finish_import()
		return
	if not _validation_dialog:
		_fail_import("Não foi possível abrir a correção dos dados do deck.")
		return
	var entry: Dictionary = _validation_queue[0]
	var definition = _card_definitions.get(entry["key"], {})
	_validation_dialog.show_card(
			definition,
			int(entry["card_index"]),
			_card_definitions.size(),
			entry["missing"])


func _on_validation_confirmed(
		card_name: String, category: String, energy: String) -> void:
	if _validation_queue.is_empty():
		return
	var entry: Dictionary = _validation_queue.pop_front()
	var definition = _card_definitions.get(entry["key"], {})
	if typeof(definition) != TYPE_DICTIONARY:
		definition = {}
	definition["Name"] = card_name
	definition["_tipo"] = category
	definition["Type"] = _template_for_category(category)
	if category in ENERGY_CARD_TYPES:
		definition["ENERGIA"] = energy
	elif str(definition.get("ENERGIA", "")).strip_edges().is_empty():
		definition["ENERGIA"] = "0"
	_card_definitions[entry["key"]] = definition
	_show_next_validation()


func _on_validation_cancelled() -> void:
	_validation_queue.clear()
	_pending_deck = {}
	_import_button.disabled = false
	_set_status(
			"Importação cancelada. Importe o deck novamente para completar "
			+ "os dados.")


func _finish_import() -> void:
	_pending_deck["definitions"] = _card_definitions
	if not _save_cached_deck(_pending_deck):
		return
	_start_image_prefetch(_pending_deck)


func _start_image_prefetch(deck: Dictionary) -> void:
	var image_paths := []
	var definitions = deck.get("definitions", {})
	if typeof(definitions) == TYPE_DICTIONARY:
		for definition in definitions.values():
			if typeof(definition) != TYPE_DICTIONARY:
				continue
			var image_path := str(definition.get("_bsdb_image_path", ""))
			if not image_path.is_empty() and not image_paths.has(image_path):
				image_paths.append(image_path)
	_prefetched_deck = deck
	if image_paths.is_empty():
		_prefetched_deck = {}
		_start_game_with_deck(deck)
		return
	_set_status("Baixando imagens das cartas (0/%d)..." % image_paths.size())
	cfc.prefetch_card_images(image_paths)


func _on_card_image_prefetch_progress(done: int, total: int) -> void:
	if _prefetched_deck.is_empty():
		return
	_set_status("Baixando imagens das cartas (%d/%d)..." % [done, total])


func _on_card_image_prefetch_finished(failed: int) -> void:
	if _prefetched_deck.is_empty():
		return
	var deck: Dictionary = _prefetched_deck
	_prefetched_deck = {}
	if failed > 0:
		push_warning(
				"%d card image(s) could not be prefetched." % failed)
	_start_game_with_deck(deck)


static func _missing_essential_fields(definition: Dictionary) -> Array:
	var missing := []
	if str(definition.get("Name", "")).strip_edges().is_empty():
		missing.append("Nome")
	var category := str(definition.get("_tipo", "")).strip_edges()
	if not category in VALID_CARD_TYPES:
		missing.append("Tipo")
	elif category in ENERGY_CARD_TYPES:
		var energy := str(definition.get("ENERGIA", "")).strip_edges()
		if energy.is_empty():
			missing.append("ENERGIA")
	return missing


static func _template_for_category(category: String) -> String:
	match category:
		"Personagem":
			return "Blue"
		"Cenário":
			return "Green"
		"Suporte":
			return "Red"
		"Habilidade":
			return "Purple"
	return ""


# The BSDB has types outside the four canonical ones, like
# "Personagem - EV" (an evolution variant of a character) or an all-caps
# "SUPORTE". Normalize to the canonical spelling/casing so the cards stop
# falling into the import validation dialog.
static func _normalize_category(raw: String) -> String:
	var category := raw.strip_edges()
	var separator := category.find(" - ")
	if separator != -1:
		category = category.substr(0, separator).strip_edges()
	for valid in VALID_CARD_TYPES:
		if category.to_lower() == valid.to_lower():
			return valid
	return category


# The GitHub catalog keeps every field at the top level; make_card_properties
# expects the BSDB site row shape (id_card/nome/tipo/imagem/dados).
static func repo_card_to_record(entry: Dictionary) -> Dictionary:
	return {
		"id_card": _string_or_default(entry, "ID_CARD", ""),
		"nome": _string_or_default(entry, "NOME", ""),
		"tipo": _string_or_default(entry, "TIPO", ""),
		"imagem": _string_or_default(entry, "IMAGEM", ""),
		"dados": entry,
	}


static func make_card_properties(record: Dictionary) -> Dictionary:
	var data = record.get("dados", {})
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var category := _normalize_category(
			str(record.get("tipo", data.get("TIPO", ""))))
	var template_type := _template_for_category(category)
	if template_type.is_empty():
		push_warning("BSDB card without a valid type: " + category)
	var energy_default: String = "" if category in ENERGY_CARD_TYPES else "0"
	var ability_text := _string_or_default(data, "TEXTO", "")
	var actions = data.get("ACOES", [])
	if typeof(actions) == TYPE_NIL:
		actions = []
	elif typeof(actions) != TYPE_ARRAY:
		return {}
	for action in actions:
		if typeof(action) == TYPE_DICTIONARY:
			var action_text := _string_or_default(action, "TEXTO", "")
			if action_text:
				if ability_text:
					ability_text += "\n\n"
				ability_text += action_text
	var evolution_text := _string_or_default(data, "TEXTO_EV", "")
	if evolution_text:
		if ability_text:
			ability_text += "\n\n"
		ability_text += evolution_text
	var image_path := str(record.get("imagem", data.get("IMAGEM", "")))
	if not image_path.begins_with("/") \
			or ".." in image_path \
			or not image_path.to_lower().ends_with(".png"):
		return {}
	var tags = data.get("PODERES", [])
	if typeof(tags) == TYPE_NIL:
		tags = []
	elif typeof(tags) != TYPE_ARRAY:
		return {}
	return {
		"Name": str(record.get("nome", data.get("NOME", ""))),
		"Type": template_type,
		"_tipo": category,
		"ENERGIA": _string_or_default(data, "ENERGIA", energy_default),
		"Tags": tags,
		"Requirements": _string_or_default(data, "AFILIACAO", ""),
		"Abilities": ability_text,
		"Cost": 0,
		"Power": 0,
		"_bsdb_id": str(data.get("ID_CARD", record.get("id_card", ""))),
		"_bsdb_image_path": image_path,
		"_bsdb_shield": _string_or_default(data, "ESCUDO", "0"),
		"_bsdb_alignment": _string_or_default(data, "ALINHAMENTO", ""),
		"_bsdb_extra_energy": _string_or_default(data, "ENERGIA_EXTRA", ""),
		"_errata": _texts_or_default(data, "ERRATA"),
		"_faq": _texts_or_default(data, "FAQ"),
		"_illustration": _string_or_default(data, "ILUSTRADORES", ""),
	}


# ERRATA and FAQ arrive as arrays of paragraphs in the BSDB data.
static func _texts_or_default(data: Dictionary, key: String) -> String:
	var value = data.get(key, null)
	if value == null:
		return ""
	if typeof(value) == TYPE_ARRAY:
		var paragraphs: Array[String] = []
		for item in value:
			var text := str(item)
			if not text.strip_edges().is_empty():
				paragraphs.append(text)
		return "\n\n".join(paragraphs)
	return str(value)


static func _string_or_default(data: Dictionary, key: String, default: String) -> String:
	var value = data.get(key, null)
	if value == null:
		return default
	var text := str(value)
	if text.is_empty():
		return default
	return text


func _save_cached_deck(deck: Dictionary) -> bool:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DECK_CACHE_PATH))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail_import("Não foi possível criar a pasta local dos decks.")
		return false
	var file := FileAccess.open(_get_cache_file_path(_deck_id), FileAccess.WRITE)
	if file == null:
		_fail_import("Não foi possível salvar o deck no armazenamento local.")
		return false
	file.store_string(JSON.stringify(deck, "\t"))
	file.close()
	return true


func _load_cached_deck(deck_id: String) -> Dictionary:
	var cache_path := _get_cache_file_path(deck_id)
	if not FileAccess.file_exists(cache_path):
		return {}
	var file := FileAccess.open(cache_path, FileAccess.READ)
	if file == null:
		_fail_import("Não foi possível ler o deck salvo localmente.")
		return {}
	var test_json_conv = JSON.new()
	var parse_error := test_json_conv.parse(file.get_as_text())
	var parsed = test_json_conv.get_data()
	file.close()
	if parse_error != OK or typeof(parsed) != TYPE_DICTIONARY:
		_fail_import("O arquivo local do deck está corrompido.")
		return {}
	var deck: Dictionary = parsed
	if int(deck.get("cache_version", 0)) != DECK_CACHE_VERSION:
		return {}
	if deck.get("id", "") != deck_id \
			or typeof(deck.get("cards", null)) != TYPE_DICTIONARY \
			or typeof(deck.get("definitions", null)) != TYPE_DICTIONARY \
			or deck.cards.is_empty():
		_fail_import("O arquivo local do deck está incompleto.")
		return {}
	return deck


func _get_cache_file_path(deck_id: String) -> String:
	return DECK_CACHE_PATH + "BSDB_" + deck_id + ".json"


func _start_game_with_deck(deck: Dictionary) -> void:
	_import_button.disabled = false
	cfc.current_deck = deck
	DeckCatalog.apply_definitions(deck)
	if not _deck_id.is_empty():
		DeckCatalog.remember_deck(_get_cache_file_path(_deck_id))
	_set_status("Deck pronto. Abrindo a partida...")
	hide()
	emit_signal("deck_loaded", deck)


func _fail_import(message: String) -> void:
	_import_button.disabled = false
	_set_status(message)
	push_error(message)


func _set_status(message: String) -> void:
	_status.text = message
