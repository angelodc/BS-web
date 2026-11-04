extends "res://tests/UTcommon.gd"

# F5 of "ações sem mouse": the resource count and the prize send read and write
# through the state, so both are deterministic and testable.
#
# The prize send is one transaction: the network payload goes out first and,
# once it is out, the attachments return to the resources and the card leaves
# the table. The test replaces the network with a sink that only records the
# call, so the transaction is checked without a relay.

const Actions = preload("res://src/core/table/TableActions.gd")
const Snapshot = preload("res://src/core/table/TableSnapshot.gd")

class FakePrizeSink:
	extends RefCounted

	var accepted := true
	var received := []

	func send_card_to_opponent_prizes(card) -> bool:
		received.append(card)
		return accepted

var actions
var sink
var _saved := {}


func before_each():
	await setup_board()
	actions = Actions.new(board, 1)
	sink = FakePrizeSink.new()
	actions.prize_sink = sink
	_saved = {
		"state": Multiplayer.state,
		"mode": Multiplayer.mode,
	}
	Multiplayer.mode = Multiplayer.Mode.MATCH
	Multiplayer.state = Multiplayer.State.PLAYING


func after_each():
	Multiplayer.state = _saved["state"]
	Multiplayer.mode = _saved["mode"]


func _ok(result : Dictionary) -> bool:
	return bool(result.get("ok", false))


func _id(card) -> String:
	return Snapshot.id_of(card)


# Plays a Personagem with the given number of attachments and returns the
# nodes: [host, attachment...] or [host] when there are none.
func _character_in_play(attachments := 0) -> Array:
	var cards = draw_test_cards(1 + attachments)
	cards[0].properties["_tipo"] = "Personagem"
	cards[0].properties["ENERGIA"] = "1"
	for index in range(1, cards.size()):
		cards[index].properties["_tipo"] = "Habilidade"
		cards[index].properties["ENERGIA"] = "1"
	actions.sync(1)
	assert_true(_ok(actions.apply({"op": "jogar", "card": _id(cards[0])})),
			"The character enters the field")
	for index in range(1, cards.size()):
		assert_true(_ok(actions.apply({
			"op": "anexar",
			"card": _id(cards[index]),
			"host": _id(cards[0]),
		})), "The card attaches to the character")
	return cards


# -----------------------------------------------------------------------------
# Sending a character to the opponent's prizes
# -----------------------------------------------------------------------------

func test_the_prize_send_is_one_transaction():
	var cards = _character_in_play(1)
	var host = _id(cards[0])
	var attached = _id(cards[1])

	var result = actions.apply({"op": "enviar_aos_prêmios", "card": host})

	assert_true(_ok(result), str(result))
	assert_eq(sink.received.size(), 1, "The send happens exactly once")
	assert_eq(sink.received[0].get_instance_id(),
			cards[0].get_instance_id(), "The sent card is the character")
	assert_false(actions.state.cards.has(host),
			"The state no longer holds the character")
	assert_eq(actions.state.address_of(host), "")
	assert_eq(actions.state.address_of(attached), "p1:recursos:1",
			"The attachment returns to the owner's resources")
	assert_eq(cards[1].get_parent(), discard)
	assert_eq(cards[1].current_host_card, null)
	assert_eq(cards[0].attachments.size(), 0)
	assert_false(cards[0].visible, "The sent card leaves the table")
	assert_false(cards[0].monitoring)
	assert_false(cards[0].monitorable)
	assert_eq(actions.history.size(), 3, "Play, attach and send are logged")
	assert_eq(actions.history[2]["text"],
			"P1 enviou " + cards[0].canonical_name + " aos prêmios do oponente")


func test_a_refused_send_leaves_the_card_and_the_attachments_alone():
	var cards = _character_in_play(1)
	var host = _id(cards[0])
	var attached = _id(cards[1])
	var address_before = actions.state.address_of(host)
	var attachment_before = actions.state.address_of(attached)
	sink.accepted = false

	var result = actions.apply({"op": "enviar_aos_prêmios", "card": host})

	assert_false(_ok(result))
	assert_eq(str(result.get("error", "")), "premios_indisponiveis")
	assert_eq(sink.received.size(), 1, "The send was attempted")
	assert_eq(actions.history.size(), 2, "A refused send is not logged")
	assert_eq(actions.state.address_of(host), address_before)
	assert_eq(actions.state.address_of(attached), attachment_before)
	# Attachments are siblings of the host on the board, not its children; the
	# host's attachment list is what ties them.
	assert_eq(cards[1].get_parent(), board,
			"The attachment stays on the table")
	assert_eq(cards[1].current_host_card, cards[0])
	assert_eq(cards[0].attachments.size(), 1)
	assert_true(cards[0].visible, "The character stays on the table")


func test_the_prize_send_needs_a_match():
	var cards = _character_in_play(0)
	var host = _id(cards[0])
	Multiplayer.state = Multiplayer.State.IDLE

	var result = actions.apply({"op": "enviar_aos_prêmios", "card": host})

	assert_false(_ok(result))
	assert_eq(str(result.get("error", "")), "sem_partida")
	assert_eq(sink.received.size(), 0,
			"Without a match the network is never asked")
	assert_eq(actions.state.address_of(host), "p1:campo:frente:2",
			"The character stays on the field")


# -----------------------------------------------------------------------------
# Resource count
# -----------------------------------------------------------------------------

func test_the_resource_count_reads_the_stack_the_snapshot_reads():
	assert_true(_ok(actions.apply({"op": "mandar_topo_para_recursos"})))
	assert_true(_ok(actions.apply({"op": "mandar_topo_para_recursos"})))
	var snapshot = Snapshot.capture(board, 1)

	assert_eq(board.get_available_resource_count(), 2)
	assert_eq(snapshot["zones"]["resources"]["count"], 2)
	assert_true(snapshot["issues"].is_empty(), str(snapshot["issues"]))


func test_the_resource_count_survives_the_view_popup():
	assert_true(_ok(actions.apply({"op": "mandar_topo_para_recursos"})))
	assert_true(_ok(actions.apply({"op": "mandar_topo_para_recursos"})))
	discard._on_View_Button_pressed()
	await yield_for(1)

	var snapshot = Snapshot.capture(board, 1)

	assert_true(discard.is_popup_open, "The view popup is open")
	assert_eq(board.get_available_resource_count(), 2,
			"Cards parked in the popup still count as resources")
	assert_eq(snapshot["zones"]["resources"]["count"], 2)
	assert_true(snapshot["issues"].is_empty(), str(snapshot["issues"]))
