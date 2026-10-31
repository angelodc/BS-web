extends "res://tests/UTcommon.gd"

# The retry window lives in Multiplayer._process, and a real reconnect opens a
# WebSocket. Rede._connect_for_action bails on an empty username before it
# touches LocalRelay or creates a client, and it reports that through
# status_changed — so an empty username keeps the whole schedule offline and
# turns every attempt into one countable signal.

var _saved := {}


func before_each():
	_saved = {
		"state": Multiplayer.state,
		"mode": Multiplayer.mode,
		"waiting_reason": Multiplayer._waiting_reason,
		"waiting_message": Multiplayer.waiting_message,
		"retry_step": Multiplayer._retry_step,
		"retry_elapsed": Multiplayer._retry_elapsed,
		"resume_state": Multiplayer._resume_state_before_wait,
		"resume_live": Multiplayer._resume_live,
		"resume_manifests": Multiplayer._resume_peer_manifests,
		"resume_peer_manifest": Multiplayer._resume_peer_manifest_received,
		"resume_peer_checkpoint": Multiplayer._resume_peer_checkpoint,
		"resume_waiting_ack": Multiplayer._resume_waiting_ack,
		"resume_expected": Multiplayer._resume_expected_participants,
		"restore_pending": Multiplayer._restore_pending,
		"restore_scheduled": Multiplayer._restore_scheduled,
		"game_paused": cfc.game_paused,
		"room_id": Rede.room_id,
		"username": Rede.player_username,
		"address": Rede.last_address,
		"is_connected": Rede.is_connected,
		"is_searching": Rede.is_searching,
	}
	Multiplayer.mode = Multiplayer.Mode.MATCH
	Multiplayer.state = Multiplayer.State.PLAYING
	Multiplayer._waiting_reason = ""
	Multiplayer.waiting_message = ""
	Multiplayer._retry_step = Multiplayer.RECONNECT_RETRY_SECONDS.size()
	Multiplayer._retry_elapsed = 0.0
	Multiplayer._resume_state_before_wait = Multiplayer.State.PLAYING
	Rede.room_id = "AUTO77"
	Rede.player_username = ""
	Rede.last_address = "127.0.0.1:9080"
	Rede.is_connected = false
	Rede.is_searching = false
	# The engine would run the loop on every yielded frame; the test drives
	# _process by hand so the schedule is exact.
	Multiplayer.set_process(false)


func after_each():
	Multiplayer.set_process(false)
	Multiplayer.state = _saved["state"]
	Multiplayer.mode = _saved["mode"]
	Multiplayer._waiting_reason = _saved["waiting_reason"]
	Multiplayer.waiting_message = _saved["waiting_message"]
	Multiplayer._retry_step = _saved["retry_step"]
	Multiplayer._retry_elapsed = _saved["retry_elapsed"]
	Multiplayer._resume_state_before_wait = _saved["resume_state"]
	Multiplayer._resume_live = _saved["resume_live"]
	Multiplayer._resume_peer_manifests = _saved["resume_manifests"]
	Multiplayer._resume_peer_manifest_received = \
			_saved["resume_peer_manifest"]
	Multiplayer._resume_peer_checkpoint = _saved["resume_peer_checkpoint"]
	Multiplayer._resume_waiting_ack = _saved["resume_waiting_ack"]
	Multiplayer._resume_expected_participants = _saved["resume_expected"]
	Multiplayer._restore_pending = _saved["restore_pending"]
	Multiplayer._restore_scheduled = _saved["restore_scheduled"]
	cfc.game_paused = _saved["game_paused"]
	Rede.room_id = _saved["room_id"]
	Rede.player_username = _saved["username"]
	Rede.last_address = _saved["address"]
	Rede.is_connected = _saved["is_connected"]
	Rede.is_searching = _saved["is_searching"]


# Drives one step of the schedule. Half the wait must not fire and the whole
# wait must: splitting the threshold avoids riding on float equality.
func _run_until_step(step: int) -> void:
	Multiplayer._retry_elapsed = 0.0
	Multiplayer._retry_step = step
	var due: float = Multiplayer.RECONNECT_RETRY_SECONDS[step]
	Multiplayer._process(due * 0.5)
	Multiplayer._process(due * 0.5)


func test_connection_loss_arms_the_retry_window():
	watch_signals(Multiplayer)

	Multiplayer._on_connection_lost()

	assert_eq(Multiplayer.state, Multiplayer.State.WAITING,
			"a queda congela a partida em WAITING")
	assert_eq(Multiplayer._waiting_reason, "local")
	assert_eq(Multiplayer._retry_step, 0, "a janela comeca na primeira espera")
	assert_true(Multiplayer.is_processing(),
			"_process precisa rodar para tentar sozinha")
	assert_true(Multiplayer._auto_reconnect_armed())
	assert_eq(Multiplayer.waiting_message,
			Multiplayer.RECONNECT_RETRYING_MESSAGE)
	assert_signal_emitted_with_parameters(
			Multiplayer, "waiting_changed",
			[true, Multiplayer.RECONNECT_RETRYING_MESSAGE])


func test_second_loss_does_not_restart_the_window():
	Multiplayer._on_connection_lost()
	Multiplayer.set_process(false)
	_run_until_step(0)
	assert_eq(Multiplayer._retry_step, 1)

	# Uma tentativa que falha chega por connection_lost de novo. Rearmar o passo
	# inicial dobraria o tempo total e estouraria a graca de 120 s do relay.
	Multiplayer._on_connection_lost()

	assert_eq(Multiplayer._retry_step, 1,
			"a sequencia continua, nao recomeca")


func test_backoff_follows_the_published_schedule():
	Multiplayer._on_connection_lost()
	Multiplayer.set_process(false)
	watch_signals(Rede)
	var total := 0.0

	for step in Multiplayer.RECONNECT_RETRY_SECONDS.size():
		var due: float = Multiplayer.RECONNECT_RETRY_SECONDS[step]
		total += due
		Multiplayer._retry_elapsed = 0.0
		Multiplayer._process(due * 0.5)
		assert_eq(get_signal_emit_count(Rede, "status_changed"), step,
				"nada antes de vencer a espera de %s s" % str(due))
		Multiplayer._process(due * 0.5)
		assert_eq(get_signal_emit_count(Rede, "status_changed"), step + 1,
				"a tentativa %d sai na hora de %s s" % [step + 1, str(due)])
		assert_eq(Multiplayer._retry_step, step + 1)
		assert_eq(Multiplayer._retry_elapsed, 0.0)

	# Os 77 s somados cabem nos 120 s de graca do relay.
	assert_lt(total, 120.0)


func test_attempt_in_flight_does_not_spend_a_step():
	Multiplayer._on_connection_lost()
	Multiplayer.set_process(false)
	watch_signals(Rede)
	# O socket ainda conectando: abrir outro fecharia o proprio rejoin.
	Rede.is_searching = true
	_run_until_step(0)

	assert_eq(Multiplayer._retry_step, 0, "a etapa espera sem ser gasta")
	assert_eq(get_signal_emit_count(Rede, "status_changed"), 0)

	Rede.is_searching = false
	Multiplayer._process(0.0)
	assert_eq(get_signal_emit_count(Rede, "status_changed"), 1)
	assert_eq(Multiplayer._retry_step, 1)


func test_hotseat_never_opens_a_reconnect_attempt():
	Multiplayer.mode = Multiplayer.Mode.SOLO
	Multiplayer._on_connection_lost()
	Multiplayer.set_process(false)
	watch_signals(Rede)

	Multiplayer._process(60.0)

	assert_eq(get_signal_emit_count(Rede, "status_changed"), 0,
			"solo nao falou com relay: nao ha o que reconectar")
	assert_false(Multiplayer._auto_reconnect_armed())


func test_exhausted_window_points_at_the_button_once():
	Multiplayer._on_connection_lost()
	Multiplayer.set_process(false)
	Multiplayer._retry_step = Multiplayer.RECONNECT_RETRY_SECONDS.size() - 1
	Multiplayer._retry_elapsed = 0.0
	watch_signals(Multiplayer)

	# A ultima tentativa sai, e a volta do _process fecha a janela.
	Multiplayer._process(
			Multiplayer.RECONNECT_RETRY_SECONDS[Multiplayer._retry_step])
	Multiplayer._process(0.1)
	Multiplayer._process(0.1)

	assert_eq(Multiplayer.state, Multiplayer.State.WAITING,
			"o jogador continua na partida, agora com o botao")
	assert_eq(Multiplayer.waiting_message,
			Multiplayer.RECONNECT_GIVEUP_MESSAGE)
	assert_false(Multiplayer.is_processing())
	assert_signal_emit_count(Multiplayer, "waiting_changed", 1,
			"o aviso de derrota aparece uma sola vez")
	assert_true(Multiplayer.can_manual_reconnect(),
			"o botao continua valido depois de desistir")


func test_rejoin_closes_the_window():
	Multiplayer._on_connection_lost()
	Multiplayer.set_process(false)
	watch_signals(Multiplayer)

	Multiplayer._on_rejoined("H", "Doug")

	assert_eq(Multiplayer._retry_step,
			Multiplayer.RECONNECT_RETRY_SECONDS.size(),
			"voltou para a sala: nada mais a tentar")
	assert_false(Multiplayer._auto_reconnect_armed())
	assert_false(Multiplayer.is_processing())
	assert_signal_emitted(Multiplayer, "session_changed")


func test_room_expiry_closes_the_window():
	Multiplayer._on_connection_lost()
	Multiplayer.set_process(false)

	Multiplayer._on_room_expired("A sala expirou.")

	assert_eq(Multiplayer.state, Multiplayer.State.ENDED)
	assert_false(Multiplayer._auto_reconnect_armed())
	assert_false(Multiplayer.is_processing())


func test_new_session_starts_without_a_window():
	Multiplayer._on_connection_lost()
	Multiplayer.set_process(false)

	Multiplayer.leave_session()

	assert_eq(Multiplayer.state, Multiplayer.State.IDLE)
	assert_eq(Multiplayer._retry_step,
			Multiplayer.RECONNECT_RETRY_SECONDS.size())
	assert_false(Multiplayer._auto_reconnect_armed())
	assert_false(Multiplayer.is_processing())
