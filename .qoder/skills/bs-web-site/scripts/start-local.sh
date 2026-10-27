#!/usr/bin/env bash
# Sobe/para o relay Node.js e o site local do BS-web para teste no navegador.
# Uso: start-local.sh [both|relay|site|status|stop]
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
RUN_DIR="$SKILL_DIR/.run"
RELAY_DIR="$ROOT/relay"
ONLINE_DIR="$ROOT/online"
SITE_DIR="$ONLINE_DIR/site"

RELAY_PORT="${RELAY_PORT:-9080}"
SITE_PORT="${SITE_PORT:-8888}"
SITE_MODE="${SITE_MODE:-netlify}"
case "$SITE_MODE" in
	serve) SITE_MODE=static ;;
esac

RELAY_PID_FILE="$RUN_DIR/relay-$RELAY_PORT.pid"
SITE_PID_FILE="$RUN_DIR/site-$SITE_PORT.pid"
RELAY_LOG="$RUN_DIR/relay-$RELAY_PORT.log"
SITE_LOG="$RUN_DIR/site-$SITE_PORT.log"

mkdir -p "$RUN_DIR"

port_open() {
	(exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1
}

pid_alive() {
	[ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

# ps -W lista o PID do MSYS e o WINPID; taskkill só entende o segundo.
winpid_of() {
	ps -W 2>/dev/null | awk -v p="$1" '$1 == p { print $4; exit }'
}

read_pid() {
	[ -f "$1" ] && cat "$1" 2>/dev/null || true
}

http_ok() {
	curl -fsS -o /dev/null --max-time 3 "$1" 2>/dev/null
}

wait_http() {
	local url=$1 seconds=$2 label=$3
	local waited=0
	while [ "$waited" -lt "$seconds" ]; do
		if http_ok "$url"; then
			return 0
		fi
		sleep 1
		waited=$((waited + 1))
	done
	echo "$label nao respondeu em ${seconds}s: $url" >&2
	return 1
}

tail_log() {
	echo "--- ultimas linhas de $1 ---" >&2
	tail -n 20 "$1" >&2 2>/dev/null || true
	echo "--- fim $1 ---" >&2
}

game_path() {
	if [ -f "$SITE_DIR/game/index.pck" ]; then
		echo "/game/"
	elif [ -f "$SITE_DIR/index.pck" ]; then
		echo "/"
	else
		echo ""
	fi
}

print_urls() {
	local path
	path="$(game_path)"
	echo
	echo "Relay:  http://127.0.0.1:$RELAY_PORT/healthz"
	echo "Site:   http://localhost:$SITE_PORT/"
	if [ -n "$path" ]; then
		local query="?relay=127.0.0.1:$RELAY_PORT"
		if [ "$path" = "/game/" ]; then
			echo "Lobby:  http://localhost:$SITE_PORT/$query"
		fi
		echo "Jogo:   http://localhost:$SITE_PORT$path$query"
		echo "        (adicione &room=CODIGO para entrar direto em uma sala)"
	else
		echo "Jogo:   build nao encontrado em $SITE_DIR (nem /game/index.pck nem /index.pck)"
	fi
	if [ "$SITE_MODE" = "netlify" ]; then
		echo "API:    http://localhost:$SITE_PORT/api/salas"
	fi
	echo
}

start_relay() {
	if port_open "$RELAY_PORT"; then
		local pid
		pid="$(read_pid "$RELAY_PID_FILE")"
		if pid_alive "$pid"; then
			echo "relay: ja rodando na porta $RELAY_PORT (PID $pid)."
			return 0
		fi
		echo "relay: a porta $RELAY_PORT ja esta ocupada por outro processo; nao vou iniciar nem encerrar nada." >&2
		return 1
	fi

	if [ ! -d "$RELAY_DIR/node_modules/ws" ]; then
		echo "relay: instalando dependencias (npm install)..."
		if ! (cd "$RELAY_DIR" && npm install --omit=dev) >>"$RELAY_LOG" 2>&1; then
			echo "relay: falha no npm install." >&2
			tail_log "$RELAY_LOG"
			return 1
		fi
	fi

	: >"$RELAY_LOG"
	(
		cd "$RELAY_DIR" || exit 1
		PORT="$RELAY_PORT" HOST=127.0.0.1 exec node src/server.js
	) >>"$RELAY_LOG" 2>&1 &
	echo $! >"$RELAY_PID_FILE"

	if ! wait_http "http://127.0.0.1:$RELAY_PORT/healthz" 20 "relay"; then
		tail_log "$RELAY_LOG"
		stop_service relay "$RELAY_PORT"
		return 1
	fi
	echo "relay: ouvindo em ws://127.0.0.1:$RELAY_PORT (PID $(read_pid "$RELAY_PID_FILE"))."
}

start_site() {
	if port_open "$SITE_PORT"; then
		local pid
		pid="$(read_pid "$SITE_PID_FILE")"
		if pid_alive "$pid"; then
			echo "site: ja rodando na porta $SITE_PORT (PID $pid)."
			return 0
		fi
		echo "site: a porta $SITE_PORT ja esta ocupada por outro processo; nao vou iniciar nem encerrar nada." >&2
		return 1
	fi

	if [ -z "$(game_path)" ]; then
		echo "site: aviso: nenhum build HTML5 em $SITE_DIR; o site sobe mas o jogo da 404." >&2
	fi

	: >"$SITE_LOG"
	if [ "$SITE_MODE" = "netlify" ]; then
		echo "site: subindo netlify dev --offline (a primeira execucao baixa o CLI; pode demorar)."
		(
			cd "$ONLINE_DIR" || exit 1
			RELAY_URL="http://127.0.0.1:$RELAY_PORT" exec npx --yes netlify-cli dev --offline --port "$SITE_PORT"
		) >>"$SITE_LOG" 2>&1 &
		echo $! >"$SITE_PID_FILE"

		if ! wait_http "http://127.0.0.1:$SITE_PORT/" 300 "site"; then
			tail_log "$SITE_LOG"
			stop_service site "$SITE_PORT"
			return 1
		fi
	else
		echo "site: subindo servidor estatico em $SITE_DIR."
		(
			exec node "$SKILL_DIR/scripts/serve-static.js" --root "$SITE_DIR" --port "$SITE_PORT"
		) >>"$SITE_LOG" 2>&1 &
		echo $! >"$SITE_PID_FILE"

		if ! wait_http "http://127.0.0.1:$SITE_PORT/" 20 "site"; then
			tail_log "$SITE_LOG"
			stop_service site "$SITE_PORT"
			return 1
		fi
	fi
	echo "site: ouvindo em http://127.0.0.1:$SITE_PORT (PID $(read_pid "$SITE_PID_FILE"), modo $SITE_MODE)."
	echo "$SITE_MODE" >"$RUN_DIR/site-$SITE_PORT.mode"
}

stop_service() {
	local name=$1 port=$2
	local pid_file="$RUN_DIR/$name-$port.pid"
	local pid
	pid="$(read_pid "$pid_file")"

	if [ -z "$pid" ]; then
		echo "$name: nenhum PID registrado."
		return 0
	fi
	if ! pid_alive "$pid"; then
		echo "$name: processo $pid ja nao existe."
		rm -f "$pid_file"
		return 0
	fi

	# No Windows a PID gravada e do MSYS; encerrar a arvore exige o WINPID.
	local winpid=""
	if command -v taskkill >/dev/null 2>&1; then
		winpid="$(winpid_of "$pid")"
		[ -n "$winpid" ] && taskkill //PID "$winpid" //T >/dev/null 2>&1 || true
	fi
	kill "$pid" 2>/dev/null

	local waited=0
	while [ "$waited" -lt 20 ] && pid_alive "$pid"; do
		sleep 0.5
		waited=$((waited + 1))
	done

	if pid_alive "$pid" || port_open "$port"; then
		if [ -n "$winpid" ] && command -v taskkill >/dev/null 2>&1; then
			taskkill //PID "$winpid" //T //F >/dev/null 2>&1 || true
		else
			kill -9 "$pid" 2>/dev/null || true
		fi
		sleep 1
		echo "$name: encerrado a forca junto com os filhos (PID $pid)."
	else
		echo "$name: encerrado (PID $pid)."
	fi
	rm -f "$pid_file" "$RUN_DIR/$name-$port.mode"

	if port_open "$port"; then
		echo "$name: aviso: a porta $port continua ocupada por outro processo; nao vou mexer nele." >&2
	fi
}

show_status() {
	local relay_pid site_pid
	relay_pid="$(read_pid "$RELAY_PID_FILE")"
	site_pid="$(read_pid "$SITE_PID_FILE")"

	if pid_alive "$relay_pid"; then
		printf 'relay: PID %s, porta %s, ' "$relay_pid" "$RELAY_PORT"
		http_ok "http://127.0.0.1:$RELAY_PORT/healthz" && echo "healthz OK" || echo "sem resposta"
	else
		echo "relay: parado"
	fi

	if pid_alive "$site_pid"; then
		local mode="$SITE_MODE"
		[ -f "$RUN_DIR/site-$SITE_PORT.mode" ] && mode="$(cat "$RUN_DIR/site-$SITE_PORT.mode")"
		printf 'site:  PID %s, porta %s, modo %s, ' "$site_pid" "$SITE_PORT" "$mode"
		http_ok "http://127.0.0.1:$SITE_PORT/" && echo "HTTP OK" || echo "sem resposta"
	else
		echo "site:  parado"
	fi

	local path
	path="$(game_path)"
	[ -n "$path" ] && echo "build: $SITE_DIR$path" || echo "build: ausente"
}

mode="${1:-both}"
case "$mode" in
	both)
		start_relay || exit 1
		start_site || exit 1
		print_urls
		;;
	relay)
		start_relay || exit 1
		print_urls
		;;
	site)
		start_site || exit 1
		print_urls
		;;
	status)
		show_status
		;;
	stop)
		stop_service site "$SITE_PORT"
		stop_service relay "$RELAY_PORT"
		;;
	*)
		echo "uso: $0 [both|relay|site|status|stop]" >&2
		exit 2
		;;
esac
