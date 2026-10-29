extends Node

# Event bus das ações da partida. Cada evento carrega ator, ação, zona e carta,
# e já nasce com a decisão de privacidade tomada: o nome da carta só é divulgado
# quando ela estava ou ficou numa zona pública virada para cima. O log do HUD é
# o primeiro consumidor; a lupa de presença e as ações cruzadas entre assentos
# leem o mesmo evento.

const MAX_ENTRIES := 200
const PUBLIC_ZONES := ["board", "scenario", "resources", "prizes"]
const PRIVATE_ZONES := ["hand", "deck"]
const SCENARIO_TYPE := "Cenário"

const ZONE_LABELS := {
	"board": "campo",
	"scenario": "Cenário",
	"resources": "Recursos",
	"prizes": "Prêmios",
	"opponent_prizes": "Prêmios do adversário",
	"hand": "mão",
	"deck": "Deck",
}

signal game_event(entry)

var enabled := false
var suppressed := false
var entries := []


func _ready() -> void:
	cfc.signal_propagator.connect(
			"signal_received", self, "_on_signal_received")
	Multiplayer.connect("phase_changed", self, "_on_phase_changed")


func set_enabled(value: bool) -> void:
	enabled = value
	if value:
		entries.clear()


#-----------------------------------------------------------------------------
# Local hooks
#-----------------------------------------------------------------------------

func _on_signal_received(source, trigger: String, details: Dictionary) -> void:
	if not enabled or suppressed:
		return
	if source is Card:
		_record_card(source, trigger, details)
	elif trigger == "shuffle_completed":
		record_local("shuffled",
				_zone_from_container(str(details.get("source", "")), null), "")


func _record_card(card: Card, trigger: String, details: Dictionary) -> void:
	if not is_instance_valid(card) or card.network_mirror:
		return
	var tags = details.get("tags", [])
	if typeof(tags) == TYPE_ARRAY and tags.has("net"):
		return
	var destination := zone_for_card(card)
	var source := _zone_from_container(str(details.get("source", "")), card)
	match trigger:
		"card_moved_to_board":
			var action := "played_field"
			if destination == "scenario":
				action = "played_scenario"
			elif _is_character(card):
				action = "played_character"
			record_local(action, destination, card.canonical_name, source,
					card.is_faceup)
		"card_moved_to_pile":
			var action := "moved_pile"
			match destination:
				"prizes":
					action = "placed_prizes"
				"resources":
					action = "placed_resources"
				"deck":
					action = "returned_deck"
			record_local(action, destination, card.canonical_name, source,
					card.is_faceup)
		"card_moved_to_hand":
			var action := "drew" if source in PRIVATE_ZONES else "took_to_hand"
			record_local(action, "hand", card.canonical_name, source,
					card.is_faceup)
		"card_attached", "card_unattached":
			var action := "attached" if trigger == "card_attached" else "detached"
			record_local(action, destination, card.canonical_name, source,
					card.is_faceup, _host_name(details.get("host")))


func _on_phase_changed() -> void:
	if not enabled or suppressed or not Multiplayer.is_playing():
		return
	var actor := Multiplayer.get_actor_username()
	if actor.empty():
		actor = "P" + str(Multiplayer.get_actor_slot())
	record_system("Rodada " + str(Multiplayer.round_number) + " · " \
			+ Multiplayer.get_phase_label() + " · vez de " + actor)


#-----------------------------------------------------------------------------
# Recording
#-----------------------------------------------------------------------------

func record_local(action: String, zone: String, card_name: String,
		source_zone := "", faceup := true, host := "") -> void:
	if not enabled or suppressed:
		return
	_push(_actor_slot(), action, zone, card_name, host,
			_reveals(card_name, zone, source_zone, faceup))


func record_remote_card(zone: String, card_name: String, faceup: bool,
		host := "") -> void:
	if not enabled or suppressed:
		return
	var action := "moved_pile"
	match zone:
		"board":
			action = "played_field"
		"scenario":
			action = "played_scenario"
		"resources":
			action = "placed_resources"
		"prizes":
			action = "placed_prizes"
		"opponent_prizes":
			action = "sent_to_prizes"
	_push(_remote_slot(), action, zone, card_name, host, faceup)


func record_system(text: String) -> void:
	if not enabled or suppressed:
		return
	_push(0, "system", "", "", "", true, text)


func _push(slot: int, action: String, zone: String, card_name: String,
		host: String, revealed: bool, text_override := "") -> void:
	var entry := {
		"slot": slot,
		"actor": actor_name(slot),
		"action": action,
		"zone": zone,
		"card": card_name if revealed else "",
		"host": host if revealed else "",
		"public": revealed,
		"text": text_override,
	}
	if entry["text"].empty():
		entry["text"] = _sentence(entry)
	entries.append(entry)
	while entries.size() > MAX_ENTRIES:
		entries.pop_front()
	emit_signal("game_event", entry)


# A identidade só é divulgada quando a carta já era pública na origem ou quando
# chegou virada para cima numa zona pública. Compra e descarte para o deck
# continuam anónimos, e os prêmios permanecem virados para baixo.
func _reveals(card_name: String, zone: String, source_zone: String,
		faceup: bool) -> bool:
	if card_name.empty():
		return false
	if source_zone in PUBLIC_ZONES:
		return true
	return zone in PUBLIC_ZONES and faceup


func _sentence(entry: Dictionary) -> String:
	var prefix := str(entry["actor"]) + " " if not str(entry["actor"]).empty() \
			else ""
	var card := str(entry["card"])
	var subject := card if not card.empty() else "uma carta"
	var host := str(entry["host"])
	match str(entry["action"]):
		"played_scenario":
			return prefix + "colocou o cenário " + subject
		"played_character":
			return prefix + "colocou o personagem " + subject + " na cena"
		"played_field":
			return prefix + "colocou " + subject + " em campo"
		"placed_resources":
			return prefix + "colocou " + subject + " nos Recursos"
		"placed_prizes":
			return prefix + "colocou " + subject + " nos Prêmios"
		"returned_deck":
			return prefix + "devolveu " + subject + " ao Deck"
		"moved_pile":
			return prefix + "moveu " + subject + " para " \
					+ zone_label(str(entry["zone"]))
		"drew":
			return prefix + "comprou 1 carta"
		"took_to_hand":
			return prefix + "pegou " + subject + " para a mão"
		"attached":
			return prefix + "anexou " + subject \
					+ (" sob " + host if not host.empty() else "")
		"detached":
			return prefix + "removeu " + subject \
					+ (" de " + host if not host.empty() else "")
		"shuffled":
			return prefix + "embaralhou o " + zone_label(str(entry["zone"]))
		"sent_to_prizes":
			return prefix + "enviou " + subject \
					+ " para os Prêmios do adversário"
	return prefix + str(entry["action"])


func zone_label(zone: String) -> String:
	return str(ZONE_LABELS.get(zone, zone))


func actor_name(slot: int) -> String:
	if slot <= 0:
		return ""
	var display := Multiplayer.get_slot_username(slot)
	if display.empty():
		display = "P" + str(slot)
	return display


func _actor_slot() -> int:
	if Multiplayer.is_session_active():
		return Multiplayer.my_slot
	return 1


func _remote_slot() -> int:
	if Multiplayer.is_session_active():
		return Multiplayer.opponent_slot
	return 2


#-----------------------------------------------------------------------------
# Zones
#-----------------------------------------------------------------------------

func zone_for_card(card: Card) -> String:
	if not is_instance_valid(card):
		return ""
	var parent = card.get_parent()
	if not parent or not is_instance_valid(parent):
		return "board"
	if "CardPopUpSlot" in str(parent.name):
		parent = _pile_ancestor(parent)
		if not parent:
			return ""
	if cfc.NMAP.has("hand") and parent == cfc.NMAP.hand:
		return "hand"
	if cfc.NMAP.has("deck") and parent == cfc.NMAP.deck:
		return "deck"
	if cfc.NMAP.has("discard") and parent == cfc.NMAP.discard:
		return "resources"
	if str(parent.name) == "Prêmios":
		return "prizes"
	if cfc.NMAP.has("board") and parent == cfc.NMAP.board:
		return "scenario" if _is_scenario(card) else "board"
	if parent is Pile:
		return _zone_from_container(str(parent.name), card)
	return "board"


func _zone_from_container(container_name: String, card) -> String:
	if container_name.empty():
		return ""
	var lowered := container_name.to_lower()
	if "prêm" in lowered or "prem" in lowered:
		return "prizes"
	if "deck" in lowered:
		return "deck"
	if "mão" in lowered or "mao" in lowered or "hand" in lowered:
		return "hand"
	if "discard" in lowered or "descarte" in lowered:
		return "resources"
	if "board" in lowered:
		return "scenario" if (card is Card and _is_scenario(card)) else "board"
	return ""


func _pile_ancestor(node):
	var current = node
	for _i in range(8):
		if not is_instance_valid(current):
			return null
		if current is Pile:
			return current
		current = current.get_parent()
	return null


func _is_scenario(card: Card) -> bool:
	return str(card.properties.get("_tipo", "")) == SCENARIO_TYPE


func _is_character(card: Card) -> bool:
	return card.has_method("is_battle_scenes_character") \
			and card.is_battle_scenes_character()


func _host_name(host) -> String:
	if host is Card and is_instance_valid(host):
		return host.canonical_name
	return ""
