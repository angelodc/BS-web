// Relay WebSocket de salas do Battle Scenes.
//
// O relay forma as salas e encaminha mensagens entre os dois jogadores. Ele não
// valida jogadas: a autoridade continua no anfitrião (cliente Godot). Toda a
// configuração de rede/TLS fica a cargo do provedor; este processo fala HTTP e
// WebSocket em texto claro na porta interna.
import { randomBytes, randomUUID } from "node:crypto";
import http from "node:http";
import { WebSocket, WebSocketServer } from "ws";

export const PROTOCOL_VERSION = 1;
export const DEFAULT_VERSION = "1.0.0";
export const ROOM_CODE_LENGTH = 6;
// 32 símbolos: 26 letras menos I/O mais os dígitos 2-9. 256 é divisível por 32,
// então o sorteio por byte não introduz viés.
export const ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
export const DEFAULT_MAX_FRAME_BYTES = 4 * 1024 * 1024;
export const DEFAULT_ROOM_GRACE_MS = 120 * 1000;

const CONTROL_MESSAGES = new Set([
	"find_match",
	"create_room",
	"join_room",
	"cancel_match",
	"rejoin_room",
	"create_resume_room",
	"join_resume_room",
	"leave_room",
]);

const DEFAULTS = {
	version: DEFAULT_VERSION,
	maxFrameBytes: DEFAULT_MAX_FRAME_BYTES,
	roomGraceMs: DEFAULT_ROOM_GRACE_MS,
	reaperIntervalMs: 5 * 1000,
	heartbeatIntervalMs: 30 * 1000,
	maxConnections: 500,
	maxConnectionsPerIp: 10,
	maxRooms: 200,
	maxRoomsPerIp: 3,
	// O cliente envia cursor a 10/s e carta arrastada a ~12,5/s; checkpoints
	// grandes chegam em rajadas de chunks. 40/s com rajada de 120 cobre o jogo
	// sem deixar de limitar abuso.
	messageRatePerSecond: 40,
	messageBurst: 120,
	allowedOrigins: [],
	trustProxy: false,
	logLevel: "info",
};

export function createRelay(overrides = {}) {
	const config = { ...DEFAULTS, ...overrides };
	const clients = new Map();
	const rooms = new Map();
	const openRooms = new Set();
	const waitingQueue = [];
	const resumeWaiting = new Map();
	const startedAt = Date.now();

	const httpServer = http.createServer(handleHttpRequest);
	const wss = new WebSocketServer({
		noServer: true,
		maxPayload: config.maxFrameBytes,
	});

	httpServer.on("upgrade", handleUpgrade);
	wss.on("connection", handleConnection);

	const reaperTimer = setInterval(() => {
		try {
			expireVacantRooms();
		} catch (error) {
			log("reaper_error", { error: String(error) });
		}
	}, config.reaperIntervalMs);
	const heartbeatTimer = setInterval(heartbeat, config.heartbeatIntervalMs);
	reaperTimer.unref?.();
	heartbeatTimer.unref?.();

	function log(event, fields = {}) {
		if (config.logLevel === "silent") return;
		console.log(JSON.stringify({
			ts: new Date().toISOString(),
			event,
			...fields,
		}));
	}

	// ------------------------------------------------------------------
	// Transporte
	// ------------------------------------------------------------------
	function clientIp(req) {
		if (config.trustProxy) {
			const forwarded = req.headers["x-forwarded-for"];
			if (typeof forwarded === "string" && forwarded.length) {
				return forwarded.split(",")[0].trim();
			}
		}
		return req.socket.remoteAddress || "";
	}

	function countClientsForIp(ip) {
		let count = 0;
		for (const state of clients.values()) {
			if (state.ip === ip) count += 1;
		}
		return count;
	}

	function countRoomsForIp(ip) {
		let count = 0;
		for (const room of rooms.values()) {
			if (room.hostIp === ip) count += 1;
		}
		return count;
	}

	function rejectUpgrade(socket, status, message) {
		const body = JSON.stringify({ error: message });
		socket.write(
			`HTTP/1.1 ${status} ${http.STATUS_CODES[status]}\r\n`
			+ "Connection: close\r\n"
			+ "Content-Type: application/json; charset=utf-8\r\n"
			+ `Content-Length: ${Buffer.byteLength(body)}\r\n`
			+ "\r\n"
			+ body,
		);
		socket.destroy();
	}

	function handleUpgrade(req, socket, head) {
		const origin = req.headers.origin;
		if (config.allowedOrigins.length
				&& typeof origin === "string"
				&& origin
				&& !config.allowedOrigins.includes(origin)) {
			rejectUpgrade(socket, 403, "Origem nao permitida.");
			log("upgrade_rejected", { reason: "origin" });
			return;
		}
		const ip = clientIp(req);
		if (clients.size >= config.maxConnections) {
			rejectUpgrade(socket, 503, "Relay cheio. Tente novamente.");
			log("upgrade_rejected", { reason: "max_connections" });
			return;
		}
		if (countClientsForIp(ip) >= config.maxConnectionsPerIp) {
			rejectUpgrade(socket, 503, "Muitas conexoes deste endereco.");
			log("upgrade_rejected", { reason: "max_connections_per_ip" });
			return;
		}
		wss.handleUpgrade(req, socket, head, (ws) => {
			ws.ip = ip;
			wss.emit("connection", ws, req);
		});
	}

	function heartbeat() {
		for (const ws of wss.clients) {
			const state = clients.get(ws);
			if (!state) continue;
			if (!state.alive) {
				ws.terminate();
				continue;
			}
			state.alive = false;
			try {
				ws.ping();
			} catch (_error) {
				// O fechamento já será tratado pelo evento close.
			}
		}
	}

	function handleConnection(ws) {
		const state = newClientState(ws.ip);
		clients.set(ws, state);
		sendJson(ws, {
			t: "hello",
			protocol: PROTOCOL_VERSION,
			version: config.version,
			room_grace_seconds: Math.round(config.roomGraceMs / 1000),
			heartbeat_seconds: Math.round(config.heartbeatIntervalMs / 1000),
		});
		ws.on("pong", () => {
			state.alive = true;
		});
		ws.on("message", (raw) => handleMessage(ws, state, raw));
		ws.on("close", () => disconnectClient(ws));
		ws.on("error", () => disconnectClient(ws));
		log("client_connected", { clients: clients.size });
	}

	function handleMessage(ws, state, raw) {
		if (state.blocked) return;
		if (!consumeToken(state)) {
			state.blocked = true;
			sendJson(ws, {
				t: "error",
				code: "rate_limited",
				msg: "Muitas mensagens em pouco tempo.",
			});
			log("rate_limited", {});
			ws.close(1008, "rate limit");
			return;
		}
		let data;
		try {
			data = JSON.parse(raw.toString("utf8"));
		} catch (_error) {
			return;
		}
		if (!data || typeof data !== "object" || Array.isArray(data)) return;
		routeMessage(ws, state, data);
	}

	function consumeToken(state) {
		const now = Date.now();
		const elapsed = (now - state.tokensUpdatedAt) / 1000;
		state.tokens = Math.min(
			config.messageBurst,
			state.tokens + elapsed * config.messageRatePerSecond,
		);
		state.tokensUpdatedAt = now;
		if (state.tokens < 1) return false;
		state.tokens -= 1;
		return true;
	}

	function handleHello(ws, state, data) {
		const version = data.protocol ?? data.protocol_version;
		if (version === undefined || version === null || version === "") {
			// Clientes antigos não anunciam versão; continuam aceitos.
			return;
		}
		if (Number(version) !== PROTOCOL_VERSION) {
			state.blocked = true;
			sendJson(ws, {
				t: "error",
				code: "protocol_mismatch",
				msg: "Versao de protocolo incompativel. Atualize o jogo.",
			});
			log("protocol_mismatch", { protocol: String(version) });
			ws.close(1002, "protocol mismatch");
		}
	}

	// ------------------------------------------------------------------
	// HTTP
	// ------------------------------------------------------------------
	function handleHttpRequest(req, res) {
		const url = new URL(req.url || "/", "http://relay.local");
		const headers = {
			"Content-Type": "application/json; charset=utf-8",
			"Cache-Control": "no-store",
			"X-Content-Type-Options": "nosniff",
		};
		if (req.method === "GET" && url.pathname === "/healthz") {
			res.writeHead(200, headers);
			res.end(JSON.stringify({
				status: "ok",
				version: config.version,
				protocol: PROTOCOL_VERSION,
				uptime_seconds: Math.floor((Date.now() - startedAt) / 1000),
				rooms: rooms.size,
				clients: clients.size,
				grace_seconds: Math.round(config.roomGraceMs / 1000),
			}));
			return;
		}
		if (req.method === "GET" && url.pathname === "/rooms") {
			res.writeHead(200, headers);
			res.end(JSON.stringify({
				version: config.version,
				protocol: PROTOCOL_VERSION,
				rooms: publicRooms(),
			}));
			return;
		}
		res.writeHead(404, headers);
		res.end(JSON.stringify({ error: "not_found" }));
	}

	function publicRooms() {
		const list = [];
		for (const room of rooms.values()) {
			// Salas de retomada são privadas e salas sem anfitrião conectado não
			// podem receber convidados; nenhuma das duas entra no lobby.
			if (room.mode !== "match") continue;
			if (!room.slots.H) continue;
			list.push({
				code: room.code,
				host: room.usernames.H,
				mode: room.mode,
				players: room.slots.C ? 2 : 1,
				status: room.slots.C ? "playing" : "waiting",
				created_at: new Date(room.createdAt).toISOString(),
				expires_at: "",
			});
		}
		list.sort((left, right) => left.created_at.localeCompare(right.created_at));
		return list;
	}

	// ------------------------------------------------------------------
	// Salas
	// ------------------------------------------------------------------
	function sendJson(ws, payload) {
		if (!ws || ws.readyState !== WebSocket.OPEN) return false;
		try {
			ws.send(JSON.stringify(payload));
			return true;
		} catch (_error) {
			return false;
		}
	}

	function sendError(ws, message, code = undefined) {
		const payload = { t: "error", msg: message };
		if (code) payload.code = code;
		sendJson(ws, payload);
	}

	function sendWaiting(ws, message, options = {}) {
		const payload = { t: "waiting", msg: message };
		if (options.roomId) payload.room_id = options.roomId;
		if (options.mode) payload.mode = options.mode;
		if (options.gameId) payload.game_id = options.gameId;
		sendJson(ws, payload);
	}

	function sendMatchFound(ws, role, opponentUsername, room) {
		sendJson(ws, {
			t: "match_found",
			role,
			opponent: opponentUsername,
			room_id: room.code,
			mode: room.mode,
			game_id: room.gameId,
			participants: [...room.participants],
		});
	}

	function pairRoom(room, guest) {
		const host = room.slots.H;
		if (!host || room.slots.C) return false;
		const hostState = clients.get(host);
		const guestState = clients.get(guest);
		if (!hostState || !guestState) return false;
		if (!hostState.username || !guestState.username) return false;
		if (hostState.username.toLowerCase() === guestState.username.toLowerCase()) {
			return false;
		}

		room.slots.C = guest;
		room.usernames.C = guestState.username;
		room.vacantSince.C = null;
		room.active = true;
		openRooms.delete(room.code);

		Object.assign(hostState, {
			room: room.code,
			role: "H",
			opponent: guest,
			queued: false,
			mode: room.mode,
			gameId: room.gameId,
			participants: [...room.participants],
			isHost: true,
		});
		Object.assign(guestState, {
			room: room.code,
			role: "C",
			opponent: host,
			queued: false,
			mode: room.mode,
			gameId: room.gameId,
			participants: [...room.participants],
			isHost: false,
		});

		if (room.mode === "resume") {
			if (resumeWaiting.get(room.gameId) === guest) {
				resumeWaiting.delete(room.gameId);
			}
			removeFromQueue(guest);
		}

		sendMatchFound(host, "H", guestState.username, room);
		sendMatchFound(guest, "C", hostState.username, room);
		log("match_found", { room: room.code, mode: room.mode });
		return true;
	}

	function findOpenRoom() {
		for (const code of [...openRooms]) {
			const room = rooms.get(code);
			if (!room) {
				openRooms.delete(code);
				continue;
			}
			if (room.mode === "match" && room.slots.H && !room.slots.C) {
				return room;
			}
		}
		return null;
	}

	function createRoom(ws, state, rawUsername) {
		const username = cleanUsername(rawUsername);
		if (!username) {
			sendError(ws, "Informe um username valido.");
			return;
		}
		if (state.room) {
			sendError(ws, "Voce ja esta em uma partida.");
			return;
		}
		if (state.queued) {
			sendError(ws, "Voce ja esta procurando uma partida.");
			return;
		}
		if (rooms.size >= config.maxRooms) {
			sendError(ws, "O relay atingiu o limite de salas. Tente mais tarde.");
			return;
		}
		if (countRoomsForIp(state.ip) >= config.maxRoomsPerIp) {
			sendError(ws, "Voce ja tem salas abertas. Feche uma antes de criar outra.");
			return;
		}

		const code = generateRoomCode();
		const room = {
			code,
			mode: "match",
			gameId: `m_${randomUUID().replace(/-/g, "").slice(0, 16)}`,
			participants: [],
			slots: { H: ws, C: null },
			usernames: { H: username, C: "" },
			vacantSince: { H: null, C: null },
			active: false,
			createdAt: Date.now(),
			hostIp: state.ip,
		};

		Object.assign(state, {
			username,
			room: code,
			role: "H",
			opponent: null,
			queued: true,
			mode: "match",
			gameId: room.gameId,
			participants: [],
			isHost: true,
		});
		rooms.set(code, room);
		openRooms.add(code);

		let guest = null;
		while (waitingQueue.length) {
			const candidate = waitingQueue.shift();
			const candidateState = clients.get(candidate);
			if (candidateState && candidateState.queued && !candidateState.room) {
				guest = candidate;
				break;
			}
		}
		if (guest) {
			if (pairRoom(room, guest)) {
				log("room_created", { room: code, paired: true });
				return;
			}
			const candidateState = clients.get(guest);
			if (candidateState) {
				candidateState.queued = false;
				candidateState.isHost = false;
			}
			sendError(guest, "Use um username diferente do anfitriao para entrar.");
		}

		sendWaiting(ws, "Sala criada. Aguardando o outro jogador...", {
			roomId: code,
			mode: "match",
			gameId: room.gameId,
		});
		log("room_created", { room: code, paired: false });
	}

	function requestMatch(ws, state, rawUsername) {
		const username = cleanUsername(rawUsername);
		if (!username) {
			sendError(ws, "Informe um username valido.");
			return;
		}
		if (state.room) {
			sendError(ws, "Voce ja esta em uma partida.");
			return;
		}
		if (state.queued) return;

		state.username = username;
		state.queued = true;
		state.isHost = false;

		const room = findOpenRoom();
		if (room) {
			if (pairRoom(room, ws)) return;
			state.queued = false;
			sendError(ws, "Use um username diferente do anfitriao para entrar.");
			return;
		}
		if (!waitingQueue.includes(ws)) waitingQueue.push(ws);
		sendWaiting(ws, "Procurando partida...", { mode: "match" });
		log("search_started", {});
	}

	function joinRoom(ws, state, rawCode, rawUsername) {
		const username = cleanUsername(rawUsername);
		if (!username) {
			sendError(ws, "Informe um username valido.");
			return;
		}
		const code = normalizeRoomCode(rawCode);
		if (!code) {
			sendError(ws, "Informe um codigo de sala valido.");
			return;
		}
		if (state.room) {
			sendError(ws, "Voce ja esta em uma partida.");
			return;
		}
		if (state.queued) {
			sendError(ws, "Voce ja esta procurando uma partida.");
			return;
		}
		const room = rooms.get(code);
		if (!room) {
			sendError(ws, "Sala nao encontrada.");
			return;
		}
		if (room.mode !== "match") {
			sendError(ws, "Este codigo pertence a uma sala de retomada.");
			return;
		}
		if (room.slots.C) {
			sendError(ws, "A sala ja esta cheia.");
			return;
		}
		if (!room.slots.H) {
			sendError(ws, "O anfitriao nao esta mais na sala.");
			return;
		}

		state.username = username;
		state.queued = true;
		state.isHost = false;
		if (!pairRoom(room, ws)) {
			state.queued = false;
			sendError(ws, "Use um username diferente do anfitriao para entrar.");
			return;
		}
		log("room_joined", { room: code });
	}

	function createResumeRoom(ws, state, rawGameId, rawUsername, rawParticipants) {
		const gameId = cleanGameId(rawGameId);
		const username = cleanUsername(rawUsername);
		const participants = cleanParticipants(rawParticipants);
		if (!gameId) {
			sendError(ws, "O jogo salvo nao tem um identificador valido.");
			return;
		}
		if (!username) {
			sendError(ws, "Informe um username valido.");
			return;
		}
		if (participants.length !== 2) {
			sendError(ws, "O jogo salvo nao identifica os dois participantes.");
			return;
		}
		if (!participants.includes(username)) {
			sendError(ws, "Seu username nao participou desta partida salva.");
			return;
		}
		if (state.room) {
			sendError(ws, "Voce ja esta em uma partida.");
			return;
		}
		const code = `resume_${gameId}`;
		if (rooms.has(code)) {
			sendError(ws, "Ja existe uma sala de retomada para este jogo.");
			return;
		}
		if (rooms.size >= config.maxRooms) {
			sendError(ws, "O relay atingiu o limite de salas. Tente mais tarde.");
			return;
		}
		if (countRoomsForIp(state.ip) >= config.maxRoomsPerIp) {
			sendError(ws, "Voce ja tem salas abertas. Feche uma antes de criar outra.");
			return;
		}

		const room = {
			code,
			mode: "resume",
			gameId,
			participants,
			slots: { H: ws, C: null },
			usernames: { H: username, C: "" },
			vacantSince: { H: null, C: null },
			active: false,
			createdAt: Date.now(),
			hostIp: state.ip,
		};
		Object.assign(state, {
			username,
			room: code,
			role: "H",
			opponent: null,
			queued: true,
			mode: "resume",
			gameId,
			participants: [...participants],
			isHost: true,
		});
		rooms.set(code, room);

		const waitingGuest = resumeWaiting.get(gameId);
		if (waitingGuest) {
			const guestState = clients.get(waitingGuest);
			if (guestState && guestState.queued && !guestState.room) {
				if (!participants.includes(guestState.username)) {
					guestState.queued = false;
					resumeWaiting.delete(gameId);
					removeFromQueue(waitingGuest);
					sendError(
						waitingGuest,
						"Seu username nao participou desta partida salva.",
					);
				} else if (pairRoom(room, waitingGuest)) {
					log("resume_room_created", { room: code, shared: true });
					return;
				}
			}
		}

		sendWaiting(ws, "Sala de retomada criada. Aguardando o outro jogador...", {
			roomId: code,
			mode: "resume",
			gameId,
		});
		log("resume_room_created", { room: code, shared: false });
	}

	function joinResumeRoom(ws, state, rawGameId, rawUsername, rawParticipants) {
		const gameId = cleanGameId(rawGameId);
		const username = cleanUsername(rawUsername);
		const participants = cleanParticipants(rawParticipants);
		if (!gameId) {
			sendError(ws, "Informe o identificador da partida salva.");
			return;
		}
		if (!username) {
			sendError(ws, "Informe um username valido.");
			return;
		}
		if (state.room) {
			sendError(ws, "Voce ja esta em uma partida.");
			return;
		}
		if (state.queued) return;

		Object.assign(state, {
			username,
			queued: true,
			isHost: false,
			mode: "resume",
			gameId,
			participants: [...participants],
		});

		const room = rooms.get(`resume_${gameId}`);
		if (room && room.slots.H && !room.slots.C) {
			if (participants.length
					&& !sameNames(participants, room.participants)) {
				state.queued = false;
				sendError(ws, "Os participantes deste save nao conferem com a sala.");
				return;
			}
			if (!room.participants.includes(username)) {
				state.queued = false;
				sendError(ws, "Seu username nao participou desta partida salva.");
				return;
			}
			pairRoom(room, ws);
			return;
		}
		if (resumeWaiting.has(gameId)) {
			state.queued = false;
			sendError(ws, "Ja existe um jogador esperando por esta partida.");
			return;
		}
		resumeWaiting.set(gameId, ws);
		if (!waitingQueue.includes(ws)) waitingQueue.push(ws);
		sendWaiting(ws, "Procurando a sala de retomada...", {
			mode: "resume",
			gameId,
		});
		log("resume_search_started", { game_id: gameId });
	}

	function cancelMatch(ws, state) {
		if (!state || !state.queued) return;
		if (state.room) {
			const room = rooms.get(state.room);
			if (room && !room.active) {
				rooms.delete(state.room);
				openRooms.delete(state.room);
			}
		}
		removeFromQueue(ws);
		for (const [gameId, waiting] of [...resumeWaiting.entries()]) {
			if (waiting === ws) resumeWaiting.delete(gameId);
		}
		clearClientRoom(state);
		log("search_cancelled", {});
	}

	function rejoinRoom(ws, state, rawRoomId, rawUsername) {
		const roomId = normalizeRoomId(rawRoomId);
		const username = cleanUsername(rawUsername);
		if (!roomId || !username) {
			sendError(ws, "Nao foi possivel reconectar: dados da sala ausentes.");
			return;
		}
		if (state.room) {
			sendError(ws, "Voce ja esta em uma partida.");
			return;
		}
		const room = rooms.get(roomId);
		if (!room) {
			sendJson(ws, {
				t: "rejoin_failed",
				msg: "A sala nao existe mais. Use Iniciar jogo salvo.",
			});
			return;
		}
		let role = "";
		for (const candidate of ["H", "C"]) {
			const expected = room.usernames[candidate] || "";
			if (expected
					&& expected.toLowerCase() === username.toLowerCase()
					&& room.slots[candidate] === null) {
				role = candidate;
				break;
			}
		}
		if (!role) {
			sendJson(ws, {
				t: "rejoin_failed",
				msg: "Nao ha vaga para este username nesta sala.",
			});
			return;
		}

		room.slots[role] = ws;
		room.usernames[role] = username;
		room.vacantSince[role] = null;
		const opponentRole = role === "H" ? "C" : "H";
		const opponent = room.slots[opponentRole];
		const opponentState = opponent ? clients.get(opponent) : null;
		Object.assign(state, {
			username,
			room: roomId,
			role,
			opponent: opponent || null,
			queued: false,
			mode: room.mode,
			gameId: room.gameId,
			participants: [...room.participants],
			isHost: role === "H",
		});
		if (opponentState) opponentState.opponent = ws;

		sendJson(ws, {
			t: "rejoin_ok",
			room_id: roomId,
			role,
			opponent: opponentState ? opponentState.username : "",
			mode: room.mode,
			game_id: room.gameId,
			participants: [...room.participants],
		});
		if (opponent) {
			sendJson(opponent, {
				t: "opponent_reconnected",
				room_id: roomId,
				role,
				username,
			});
		}
		log("rejoined", { room: roomId, role });
	}

	function leaveRoom(ws, state) {
		if (!state || !state.room) return;
		const roomId = state.room;
		const opponent = state.opponent;
		const room = rooms.get(roomId);
		rooms.delete(roomId);
		openRooms.delete(roomId);
		if (room && room.gameId) resumeWaiting.delete(room.gameId);
		clearClientRoom(state);
		const opponentState = opponent ? clients.get(opponent) : null;
		if (opponentState) clearClientRoom(opponentState);
		if (opponent) {
			sendJson(opponent, { t: "opponent_left", room_id: roomId });
		}
		log("room_left", { room: roomId });
	}

	function routeMessage(ws, state, data) {
		const kind = typeof data.t === "string" ? data.t : "";
		switch (kind) {
			case "create_room":
				createRoom(ws, state, data.username);
				return;
			case "find_match":
				requestMatch(ws, state, data.username);
				return;
			case "join_room":
				joinRoom(ws, state, data.code ?? data.room_id, data.username);
				return;
			case "cancel_match":
				cancelMatch(ws, state);
				sendJson(ws, { t: "search_cancelled" });
				return;
			case "rejoin_room":
				rejoinRoom(ws, state, data.room_id, data.username);
				return;
			case "create_resume_room":
				createResumeRoom(
					ws,
					state,
					data.game_id,
					data.username,
					data.participants,
				);
				return;
			case "join_resume_room":
				joinResumeRoom(
					ws,
					state,
					data.game_id,
					data.username,
					data.participants,
				);
				return;
			case "leave_room":
				leaveRoom(ws, state);
				return;
			case "hello":
				handleHello(ws, state, data);
				return;
			default:
				break;
		}
		if (CONTROL_MESSAGES.has(kind)) return;
		if (!state.room || !state.opponent) return;
		const opponentState = clients.get(state.opponent);
		if (!opponentState || opponentState.room !== state.room) return;
		const forwarded = {
			...data,
			from: state.role,
			username: state.username,
			room_id: state.room,
		};
		if (!sendJson(state.opponent, forwarded)) {
			disconnectClient(state.opponent);
		}
	}

	function disconnectClient(ws) {
		const state = clients.get(ws);
		if (!state) return;
		clients.delete(ws);
		removeFromQueue(ws);
		for (const [gameId, waiting] of [...resumeWaiting.entries()]) {
			if (waiting === ws) resumeWaiting.delete(gameId);
		}

		const roomId = state.room;
		if (!roomId) {
			log("client_disconnected", {
				clients: clients.size,
			});
			return;
		}
		const room = rooms.get(roomId);
		if (!room) {
			log("client_disconnected", {
				room: roomId,
				clients: clients.size,
			});
			return;
		}
		if (!room.active) {
			rooms.delete(roomId);
			openRooms.delete(roomId);
			if (room.gameId) resumeWaiting.delete(room.gameId);
			log("client_disconnected", {
				room: roomId,
				clients: clients.size,
			});
			return;
		}

		if (room.slots[state.role] === ws) {
			room.slots[state.role] = null;
			room.vacantSince[state.role] = Date.now();
		}
		const opponent = state.opponent;
		const opponentState = opponent ? clients.get(opponent) : null;
		let notification = null;
		if (opponent && opponentState) {
			opponentState.opponent = null;
			opponentState.queued = false;
			notification = {
				t: "opponent_disconnected",
				room_id: roomId,
				role: state.role,
				username: state.username,
				mode: room.mode,
				game_id: room.gameId,
				reconnectable: true,
				grace_seconds: Math.round(config.roomGraceMs / 1000),
			};
		}
		if (notification) sendJson(opponent, notification);
		log("client_disconnected", {
			room: roomId,
			role: state.role,
			clients: clients.size,
		});
	}

	function expireVacantRooms(nowValue = Date.now()) {
		for (const [roomId, room] of [...rooms.entries()]) {
			if (!room.active) continue;
			// Enquanto um dos dois estiver conectado a sala é preservada, para que
			// a dupla possa retomar depois de uma ausência longa.
			if (room.slots.H || room.slots.C) continue;
			const vacancies = [room.vacantSince.H, room.vacantSince.C];
			if (vacancies.some((value) => value === null)) continue;
			const lastVacancy = Math.max(...vacancies);
			if (nowValue - lastVacancy <= config.roomGraceMs) continue;
			rooms.delete(roomId);
			openRooms.delete(roomId);
			if (room.gameId) resumeWaiting.delete(room.gameId);
			log("room_expired", { room: roomId });
		}
	}

	function generateRoomCode() {
		for (let attempt = 0; attempt < 20; attempt += 1) {
			const bytes = randomBytes(ROOM_CODE_LENGTH);
			let code = "";
			for (let index = 0; index < ROOM_CODE_LENGTH; index += 1) {
				code += ROOM_CODE_ALPHABET[bytes[index] % ROOM_CODE_ALPHABET.length];
			}
			if (!rooms.has(code)) return code;
		}
		return randomUUID().replace(/-/g, "").slice(0, 12).toUpperCase();
	}

	function removeFromQueue(ws) {
		const index = waitingQueue.indexOf(ws);
		if (index >= 0) waitingQueue.splice(index, 1);
	}

	async function close() {
		clearInterval(reaperTimer);
		clearInterval(heartbeatTimer);
		for (const ws of [...wss.clients]) {
			try {
				ws.terminate();
			} catch (_error) {
				// Ignora sockets já encerrados.
			}
		}
		await new Promise((resolve) => {
			wss.close(() => resolve());
		});
		if (httpServer.listening) {
			await new Promise((resolve) => httpServer.close(() => resolve()));
		}
	}

	return {
		httpServer,
		wss,
		clients,
		rooms,
		openRooms,
		waitingQueue,
		resumeWaiting,
		config,
		expireVacantRooms,
		disconnectClient,
		close,
	};
}

function newClientState(ip) {
	return {
		ip,
		username: "",
		room: null,
		role: "",
		opponent: null,
		queued: false,
		mode: "",
		gameId: "",
		participants: [],
		isHost: false,
		alive: true,
		tokens: 0,
		tokensUpdatedAt: 0,
		// Deixa de processar mensagens depois de um rate limit ou de um
		// protocolo incompatível, enquanto o socket termina de fechar.
		blocked: false,
	};
}

function clearClientRoom(state) {
	state.room = null;
	state.role = "";
	state.opponent = null;
	state.queued = false;
	state.mode = "";
	state.gameId = "";
	state.participants = [];
	state.isHost = false;
}

function cleanUsername(value) {
	const text = typeof value === "string" ? value : String(value ?? "");
	const cleaned = text.trim().replace(/[\p{Cc}\p{Cf}]/gu, "");
	return Array.from(cleaned).slice(0, 24).join("");
}

function cleanGameId(value) {
	return String(value ?? "").trim().replace(/[^A-Za-z0-9_-]/g, "").slice(0, 64);
}

function cleanParticipants(value) {
	if (!Array.isArray(value)) return [];
	const cleaned = [];
	for (const participant of value) {
		const name = cleanUsername(participant);
		if (name && !cleaned.includes(name)) cleaned.push(name);
	}
	return cleaned;
}

function normalizeRoomCode(value) {
	const code = String(value ?? "").trim().toUpperCase();
	return /^[A-Z0-9]{6}$/.test(code) ? code : "";
}

function normalizeRoomId(value) {
	const roomId = String(value ?? "").trim();
	if (!roomId) return "";
	const upper = roomId.toUpperCase();
	return /^[A-Z0-9]{6}$/.test(upper) ? upper : roomId;
}

function sameNames(left, right) {
	if (left.length !== right.length) return false;
	const set = new Set(left);
	return right.every((name) => set.has(name));
}
