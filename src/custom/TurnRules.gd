class_name TurnRules
extends RefCounted
## Pure Battle Scenes turn rules.
##
## Nothing here touches the scene tree, the network or the RNG: every function
## takes plain data and returns what the turn has to do. Multiplayer (the
## authority) is the one that actually moves cards.
##
## The decisions encoded here are the group rules recorded in AUTOTURNO.md §3
## and §7, not the official Copag wording (see §2 for the differences).

const CHARACTER_TYPE := "Personagem"

# Setup
const HAND_SIZE := 10
const MULLIGAN_COST := 2
const AUTO_MULLIGAN_MIN_CHARACTERS := 2
## Technical guard: a degenerate deck could keep the auto mulligan looping
## forever, so the game gives up after this many attempts and logs a warning.
const AUTO_MULLIGAN_LIMIT := 50

# Turn phases with automated steps
const PHASE_REG := "REG"
const PHASE_DRAW := "DRAW"
const PHASE_ADJ := "ADJ"

const COUNTDOWN_FIRST_CARD := 1
const DRAW_WITHOUT_CHARACTER := 1
const DRAW_WITH_CHARACTER := 2


# --- Cards -------------------------------------------------------------

## Reads the Battle Scenes type. Accepts a card definition dictionary or a
## [Card] instance, so the rule can be tested without building a table.
static func card_type(card) -> String:
	if card == null:
		return ""
	if typeof(card) == TYPE_DICTIONARY:
		return str(card.get("_tipo", "")).strip_edges()
	if card is Card:
		return str(card.properties.get("_tipo", "")).strip_edges()
	return ""


static func is_character(card) -> bool:
	return card_type(card) == CHARACTER_TYPE


## How many character cards a hand holds. The auto mulligan looks at this.
static func character_count(cards: Array) -> int:
	var total := 0
	for card in cards:
		if is_character(card):
			total += 1
	return total


# --- Mulligan ----------------------------------------------------------

## A hand with one or zero characters is mulliganed automatically.
static func needs_auto_mulligan(cards: Array) -> bool:
	return character_count(cards) < AUTO_MULLIGAN_MIN_CHARACTERS


static func auto_mulligan_limit_reached(attempts: int) -> bool:
	return attempts >= AUTO_MULLIGAN_LIMIT


## With an empty hand there is nothing left to shuffle back.
static func can_manual_mulligan(hand_size: int) -> bool:
	return hand_size > 0


## Cards moved from the top of the deck to Resources by one manual mulligan.
static func manual_mulligan_cost(hand_size: int) -> int:
	return mini(MULLIGAN_COST, maxi(0, hand_size))


## Cards drawn after one manual mulligan: the hand loses two cards per
## repetition, so 10 -> 8 -> 6 -> 4 -> 2 -> 0 and the resources go 2 power each.
static func manual_mulligan_draw(hand_size: int) -> int:
	return maxi(0, hand_size - MULLIGAN_COST)


## The full manual mulligan sequence, for the UI counter and the tests.
## Returns one dictionary per repetition, stopping when the hand empties.
static func manual_mulligan_sequence(hand_size: int = HAND_SIZE) -> Array:
	var steps := []
	var hand := hand_size
	while can_manual_mulligan(hand):
		var cost := manual_mulligan_cost(hand)
		var draw := manual_mulligan_draw(hand)
		steps.append({
			"hand_before": hand,
			"to_resources": cost,
			"draw": draw,
			"hand_after": draw,
		})
		hand = draw
	return steps


# --- Contagem Regressiva (REG) -----------------------------------------

## Cards sent from the top of the deck to Resources at the start of the turn.
## The two extras only apply when the turn player has no characters in play.
static func countdown_to_resources(state: Dictionary) -> int:
	if int(state.get("characters_in_play", 0)) > 0:
		return 0
	var total := COUNTDOWN_FIRST_CARD
	total += maxi(0, int(state.get("opponent_characters", 0)))
	total += maxi(0, int(state.get("opponent_prizes", 0)))
	return total


# --- Fase de Compra (DRAW) ---------------------------------------------

## The starting player draws nothing on the first turn of the match.
static func draw_count(state: Dictionary) -> int:
	if bool(state.get("is_first_turn", false)):
		return 0
	if int(state.get("characters_in_play", 0)) == 0:
		return DRAW_WITHOUT_CHARACTER
	return DRAW_WITH_CHARACTER


# --- Fase de Ajuste (ADJ) ----------------------------------------------

## Cards a character or support must unload to go back to its energy.
static func excess_attachments(attached: int, energy: int) -> int:
	return maxi(0, attached - energy)


## Adjustment operations for a list of
## `{"name": String, "attached": int, "energy": int}` dictionaries.
static func adjustment_operations(characters: Array) -> Array:
	var operations := []
	for entry in characters:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var excess := excess_attachments(
				int(entry.get("attached", 0)), int(entry.get("energy", 0)))
		if excess > 0:
			operations.append({
				"op": "unload",
				"target": str(entry.get("name", "")),
				"count": excess,
			})
	return operations


# --- Deck --------------------------------------------------------------

## An empty deck means the player loses, at any moment (AUTOTURNO.md §3.5).
static func deck_empty_loses() -> bool:
	return true


static func deck_can_supply(deck_count: int, needed: int) -> bool:
	return deck_count >= needed


# --- Phase entry point -------------------------------------------------

## Operations the authority has to apply when a phase opens.
## Empty array means the phase has nothing automatic to do.
static func operations_for_phase(phase: String, state: Dictionary) -> Array:
	match phase:
		PHASE_REG:
			var count := countdown_to_resources(state)
			if count > 0:
				return [{"op": "top_to_resources", "count": count}]
		PHASE_DRAW:
			var draws := draw_count(state)
			if draws > 0:
				return [{"op": "draw", "count": draws}]
		PHASE_ADJ:
			return adjustment_operations(state.get("characters", []))
	return []
