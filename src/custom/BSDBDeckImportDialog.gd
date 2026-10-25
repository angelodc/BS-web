extends WindowDialog

signal deck_loaded(deck)

const BSDB_BASE_URL := "https://battlescenes.vercel.app/deck/"
const SUPABASE_REST_URL := "https://xtdqcfchdqmqlbmkvdit.supabase.co/rest/v1"
const SUPABASE_PUBLIC_KEY := "sb_publishable_mx4QrlcZMx-FgZyGC7Q-uw_w3qbMhd9"
const DECK_CACHE_PATH := "user://Decks/"

enum RequestStage {
	DECK,
	DECK_CARDS,
	CARD_DATA,
}

onready var _deck_url: LineEdit = $VBox/DeckURL
onready var _status: Label = $VBox/Status
onready var _import_button: Button = $VBox/Buttons/Import

var _request: HTTPRequest
var _request_stage: int = RequestStage.DECK
var _deck_id := ""
var _deck_record := {}
var _deck_cards := []
var _card_definitions := {}


func _ready() -> void:
	_request = HTTPRequest.new()
	add_child(_request)
	# warning-ignore:return_value_discarded
	_request.connect("request_completed", self, "_on_request_completed")
	# warning-ignore:return_value_discarded
	_import_button.connect("pressed", self, "_on_import_pressed")


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
	var cached_deck = _load_cached_deck(deck_id)
	if not cached_deck.empty():
		_start_game_with_deck(cached_deck)
		return
	_deck_id = deck_id
	_deck_record = {}
	_deck_cards.clear()
	_card_definitions.clear()
	_request_stage = RequestStage.DECK
	_import_button.disabled = true
	_set_status("Buscando o deck no BSDB...")
	_request_get(
			SUPABASE_REST_URL + "/decks?select=id,title,description,cards_count"
			+ "&id=eq." + _deck_id)


func _request_get(url: String) -> void:
	var headers := PoolStringArray([
		"apikey: " + SUPABASE_PUBLIC_KEY,
		"Accept: application/json",
	])
	var request_error := _request.request(url, headers)
	if request_error != OK:
		_fail_import(
				"Não foi possível iniciar a conexão com o BSDB ("
				+ str(request_error) + ").")


func _on_request_completed(
		result: int, response_code: int, _headers: PoolStringArray,
		body: PoolByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_fail_import(
				"Falha ao baixar dados do BSDB (HTTP "
				+ str(response_code) + ", código "
				+ str(result) + "). Verifique a conexão e tente novamente.")
		return
	var parsed := JSON.parse(body.get_string_from_utf8())
	if parsed.error != OK:
		_fail_import("O BSDB retornou dados em formato inválido.")
		return
	if typeof(parsed.result) != TYPE_ARRAY:
		_fail_import("A resposta do BSDB não contém uma lista válida.")
		return
	match _request_stage:
		RequestStage.DECK:
			_handle_deck_response(parsed.result)
		RequestStage.DECK_CARDS:
			_handle_deck_cards_response(parsed.result)
		RequestStage.CARD_DATA:
			_handle_card_data_response(parsed.result)


func _handle_deck_response(records: Array) -> void:
	if records.size() != 1 or typeof(records[0]) != TYPE_DICTIONARY:
		_fail_import("Não foi encontrado um deck público com esse link.")
		return
	_deck_record = records[0]
	_request_stage = RequestStage.DECK_CARDS
	_set_status("Carregando a lista de cartas...")
	_request_get(
			SUPABASE_REST_URL + "/deck_cards?select=card_id,quantity"
			+ "&deck_id=eq." + _deck_id)


func _handle_deck_cards_response(records: Array) -> void:
	if records.empty():
		_fail_import("O deck encontrado não possui cartas.")
		return
	var card_ids := []
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
		card_ids.append(card_id)
		total_cards += quantity
	if total_cards != int(_deck_record.get("cards_count", total_cards)):
		_fail_import("A quantidade de cartas do deck não confere com o BSDB.")
		return
	var ids_filter := PoolStringArray(card_ids).join(",")
	_request_stage = RequestStage.CARD_DATA
	_set_status("Baixando dados de " + str(card_ids.size()) + " cartas...")
	_request_get(
			SUPABASE_REST_URL
			+ "/cards?select=id_card,nome,tipo,imagem,dados"
			+ "&id_card=in.(" + ids_filter + ")")


func _handle_card_data_response(records: Array) -> void:
	for record in records:
		if typeof(record) != TYPE_DICTIONARY:
			_fail_import("O BSDB retornou dados de carta inválidos.")
			return
		var card_id := str(record.get("id_card", ""))
		var card_properties := make_card_properties(record)
		if not card_id or card_properties.empty():
			_fail_import("Não foi possível interpretar uma carta do deck.")
			return
		_card_definitions[card_id] = card_properties
	if _card_definitions.size() != _deck_cards.size():
		_fail_import(
				"Não foi possível encontrar os dados de todas as cartas "
				+ "desse deck no BSDB.")
		return
	var cards := {}
	for card in _deck_cards:
		cards[card.card_id] = card.quantity
	var deck := {
		"id": _deck_id,
		"name": _deck_record.get("title", "Deck do BSDB"),
		"cards": cards,
		"definitions": _card_definitions,
		"source_url": BSDB_BASE_URL + _deck_id,
	}
	if not _save_cached_deck(deck):
		return
	_start_game_with_deck(deck)


static func make_card_properties(record: Dictionary) -> Dictionary:
	var data = record.get("dados", {})
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var category := str(record.get("tipo", data.get("TIPO", "")))
	var template_type := ""
	match category:
		"Personagem":
			template_type = "Blue"
		"Cenário":
			template_type = "Green"
		"Suporte":
			template_type = "Red"
		"Habilidade":
			template_type = "Purple"
		_:
			push_error("Unsupported BSDB card category: " + category)
			return {}
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
		"ENERGIA": _string_or_default(data, "ENERGIA", "0"),
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
	}


static func _string_or_default(data: Dictionary, key: String, default: String) -> String:
	var value = data.get(key, null)
	if value == null:
		return default
	var text := str(value)
	if text.empty():
		return default
	return text


func _save_cached_deck(deck: Dictionary) -> bool:
	var directory := Directory.new()
	var directory_error := directory.make_dir_recursive(DECK_CACHE_PATH)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail_import("Não foi possível criar a pasta local dos decks.")
		return false
	var file := File.new()
	var file_error := file.open(_get_cache_file_path(_deck_id), File.WRITE)
	if file_error != OK:
		_fail_import("Não foi possível salvar o deck no armazenamento local.")
		return false
	file.store_string(JSON.print(deck, "\t"))
	file.close()
	return true


func _load_cached_deck(deck_id: String) -> Dictionary:
	var file := File.new()
	var cache_path := _get_cache_file_path(deck_id)
	if not file.file_exists(cache_path):
		return {}
	var file_error := file.open(cache_path, File.READ)
	if file_error != OK:
		_fail_import("Não foi possível ler o deck salvo localmente.")
		return {}
	var parsed := JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		_fail_import("O arquivo local do deck está corrompido.")
		return {}
	var deck: Dictionary = parsed.result
	if deck.get("id", "") != deck_id \
			or typeof(deck.get("cards", null)) != TYPE_DICTIONARY \
			or typeof(deck.get("definitions", null)) != TYPE_DICTIONARY \
			or deck.cards.empty():
		_fail_import("O arquivo local do deck está incompleto.")
		return {}
	return deck


func _get_cache_file_path(deck_id: String) -> String:
	return DECK_CACHE_PATH + "BSDB_" + deck_id + ".json"


func _start_game_with_deck(deck: Dictionary) -> void:
	_import_button.disabled = false
	cfc.current_deck = deck
	for card_id in deck.definitions:
		cfc.card_definitions[card_id] = deck.definitions[card_id]
	_set_status("Deck pronto. Abrindo a partida...")
	hide()
	emit_signal("deck_loaded", deck)


func _fail_import(message: String) -> void:
	_import_button.disabled = false
	_set_status(message)
	push_error(message)


func _set_status(message: String) -> void:
	_status.text = message
