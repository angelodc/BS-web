// Testes de integração do relay com clientes WebSocket reais.
//
// Cada teste sobe um relay próprio em uma porta efêmera e usa sockets de
// verdade, reproduzindo os cenários do relay Python de desenvolvimento
// (tools/ws_relay.py) e os casos novos do modo online: entrada por código,
// protocolo incompatível, limites e Origin.
import assert from "node:assert/strict";
import http from "node:http";
import { test } from "node:test";
import { WebSocket } from "ws";
import { createRelay, PROTOCOL_VERSION } from "../src/relay.js";

const ROOM_CODE = /^[A-Z0-9]{6}$/;

function wait(milliseconds) {
	return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitFor(predicate, description = "condicao", timeoutMs = 2000) {
	const deadline = Date.now() + timeoutMs;
	while (Date.now() < deadline) {
		if (predicate()) return;
		await wait(10);
	}
	throw new Error(`Timeout aguardando ${description}`);
}

async function startRelay(overrides = {}) {
	const relay = createRelay({
		logLevel: "silent",
		// Os testes controlam expiração e heartbeat manualmente.
		reaperIntervalMs: 60 * 60 * 1000,
		heartbeatIntervalMs: 60 * 60 * 1000,
		...overrides,
	});
	await new Promise((resolve, reject) => {
		relay.httpServer.once("error", reject);
		relay.httpServer.listen(0, "127.0.0.1", resolve);
	});
	const { port } = relay.httpServer.address();
	return { relay, port, url: `ws://127.0.0.1:${port}` };
}

function connectClient(url, options = {}) {
	return new Promise((resolve, reject) => {
		const ws = new WebSocket(url, options);
		const messages = [];
		const waiters = [];
		ws.on("message", (raw) => {
			const message = JSON.parse(raw.toString());
			const index = waiters.findIndex(
				(waiter) => waiter.type === null || waiter.type === message.t,
			);
			if (index >= 0) {
				const [waiter] = waiters.splice(index, 1);
				clearTimeout(waiter.timer);
				waiter.resolve(message);
				return;
			}
			messages.push(message);
		});
		ws.on("error", () => {});
		ws.once("open", () => {
			resolve({
				ws,
				messages,
				send: (payload) => ws.send(JSON.stringify(payload)),
				next: (type = null, timeoutMs = 2000) => new Promise((res, rej) => {
					const found = messages.findIndex(
						(message) => type === null || message.t === type,
					);
					if (found >= 0) {
						res(messages.splice(found, 1)[0]);
						return;
					}
					const waiter = { type, resolve: res, timer: null };
					waiter.timer = setTimeout(() => {
						const waiterIndex = waiters.indexOf(waiter);
						if (waiterIndex >= 0) waiters.splice(waiterIndex, 1);
						rej(new Error(`Timeout aguardando mensagem "${type}"`));
					}, timeoutMs);
					waiters.push(waiter);
				}),
				clear: () => {
					messages.length = 0;
				},
				close: () => new Promise((res) => {
					if (ws.readyState === WebSocket.CLOSED) {
						res();
						return;
					}
					ws.once("close", () => res());
					ws.terminate();
				}),
			});
		});
		ws.once("error", reject);
	});
}

function getJson(port, path) {
	return new Promise((resolve, reject) => {
		const request = http.get({ host: "127.0.0.1", port, path }, (response) => {
			let body = "";
			response.setEncoding("utf8");
			response.on("data", (chunk) => {
				body += chunk;
			});
			response.on("end", () => {
				try {
					resolve({ status: response.statusCode, body: JSON.parse(body) });
				} catch (error) {
					reject(error);
				}
			});
		});
		request.on("error", reject);
	});
}

function connectExpectingRejection(url, options) {
	return new Promise((resolve, reject) => {
		const ws = new WebSocket(url, options);
		const timer = setTimeout(() => {
			ws.terminate();
			reject(new Error("A conexao nao foi recusada"));
		}, 2000);
		ws.once("open", () => {
			clearTimeout(timer);
			ws.terminate();
			reject(new Error("A conexao foi aceita indevidamente"));
		});
		ws.once("error", (error) => {
			clearTimeout(timer);
			resolve(error.message);
		});
	});
}

async function pairByCode(context, hostName = "Alice", guestName = "Bob") {
	const host = await connectClient(context.url);
	await host.next("hello");
	host.send({ t: "create_room", username: hostName });
	const waiting = await host.next("waiting");
	const guest = await connectClient(context.url);
	guest.send({ t: "join_room", code: waiting.room_id, username: guestName });
	const [hostMatch, guestMatch] = await Promise.all([
		host.next("match_found"),
		guest.next("match_found"),
	]);
	return { host, guest, waiting, hostMatch, guestMatch };
}

function clientState(relay, username) {
	for (const state of relay.clients.values()) {
		if (state.username === username) return state;
	}
	return null;
}

test("anfitriao cria sala e convidado entra pelo codigo", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const { host, guest, waiting, hostMatch, guestMatch } = await pairByCode(context);

	assert.match(waiting.room_id, ROOM_CODE);
	assert.equal(waiting.mode, "match");
	assert.equal(hostMatch.t, "match_found");
	assert.equal(hostMatch.role, "H");
	assert.equal(hostMatch.opponent, "Bob");
	assert.equal(guestMatch.role, "C");
	assert.equal(guestMatch.opponent, "Alice");
	assert.equal(hostMatch.room_id, guestMatch.room_id);
	assert.equal(context.relay.rooms.size, 1);

	const rooms = await getJson(context.port, "/rooms");
	assert.equal(rooms.status, 200);
	assert.equal(rooms.body.rooms.length, 1);
	assert.equal(rooms.body.rooms[0].code, waiting.room_id);
	assert.equal(rooms.body.rooms[0].host, "Alice");
	assert.equal(rooms.body.rooms[0].players, 2);
	assert.equal(rooms.body.rooms[0].status, "playing");

	await host.close();
	await guest.close();
});

test("jeito antigo: convidado procura e depois o anfitriao cria", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const guest = await connectClient(context.url);
	await guest.next("hello");
	guest.send({ t: "find_match", username: "Bob" });
	assert.equal((await guest.next("waiting")).t, "waiting");

	const host = await connectClient(context.url);
	host.send({ t: "create_room", username: "Alice" });

	const [hostMatch, guestMatch] = await Promise.all([
		host.next("match_found"),
		guest.next("match_found"),
	]);
	assert.equal(hostMatch.role, "H");
	assert.equal(guestMatch.role, "C");
	assert.equal(hostMatch.room_id, guestMatch.room_id);

	await host.close();
	await guest.close();
});

test("terceiro jogador aguarda fora da partida existente", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const { host, guest } = await pairByCode(context);
	const third = await connectClient(context.url);
	third.send({ t: "find_match", username: "Carol" });

	assert.equal((await third.next("waiting")).t, "waiting");
	assert.equal(clientState(context.relay, "Carol").room, null);

	await host.close();
	await guest.close();
	await third.close();
});

test("username duplicado nao entra na mesma sala", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const host = await connectClient(context.url);
	await host.next("hello");
	host.send({ t: "create_room", username: "Alice" });
	const waiting = await host.next("waiting");

	const duplicated = await connectClient(context.url);
	duplicated.send({
		t: "join_room",
		code: waiting.room_id,
		username: "alice",
	});
	const error = await duplicated.next("error");
	assert.match(error.msg, /username diferente/i);
	assert.equal(host.messages.filter((m) => m.t === "match_found").length, 0);

	const secondDuplicate = await connectClient(context.url);
	secondDuplicate.send({ t: "find_match", username: "ALICE" });
	assert.match((await secondDuplicate.next("error")).msg, /username diferente/i);

	await host.close();
	await duplicated.close();
	await secondDuplicate.close();
});

test("mensagens sao encaminhadas apenas para o oponente", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const { host, guest, guestMatch } = await pairByCode(context);
	const third = await connectClient(context.url);
	third.send({ t: "find_match", username: "Carol" });
	await third.next("waiting");
	host.clear();
	guest.clear();
	third.clear();

	guest.send({ t: "phase", round: 1 });
	const forwardedToHost = await host.next("phase");
	assert.equal(forwardedToHost.from, "C");
	assert.equal(forwardedToHost.username, "Bob");
	assert.equal(forwardedToHost.room_id, guestMatch.room_id);

	host.send({ t: "cursor", x: 0.5, y: 0.5 });
	const forwardedToGuest = await guest.next("cursor");
	assert.equal(forwardedToGuest.from, "H");
	assert.equal(forwardedToGuest.username, "Alice");
	assert.equal(forwardedToGuest.room_id, guestMatch.room_id);

	assert.equal(third.messages.length, 0);

	await host.close();
	await guest.close();
	await third.close();
});

test("desconexao mantem a sala e permite reconectar", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const { host, guest, guestMatch } = await pairByCode(context);
	const roomId = guestMatch.room_id;
	await guest.close();

	const notice = await host.next("opponent_disconnected");
	assert.equal(notice.room_id, roomId);
	assert.equal(notice.reconnectable, true);
	assert.equal(notice.grace_seconds, 120);
	assert.equal(notice.username, "Bob");
	assert.equal(context.relay.rooms.has(roomId), true);

	const reconnected = await connectClient(context.url);
	reconnected.send({
		t: "rejoin_room",
		room_id: roomId,
		username: "Bob",
	});
	const rejoined = await reconnected.next("rejoin_ok");
	assert.equal(rejoined.role, "C");
	assert.equal(rejoined.room_id, roomId);

	const reconnectedNotice = await host.next("opponent_reconnected");
	assert.equal(reconnectedNotice.username, "Bob");

	reconnected.send({ t: "mp_ping" });
	const ping = await host.next("mp_ping");
	assert.equal(ping.from, "C");

	await host.close();
	await reconnected.close();
});

test("sair da sala avisa o oponente e fecha a sala", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const { host, guest } = await pairByCode(context);
	host.send({ t: "leave_room" });

	const notice = await guest.next("opponent_left");
	assert.equal(notice.t, "opponent_left");
	assert.equal(clientState(context.relay, "Bob").room, null);
	assert.equal(context.relay.rooms.size, 0);

	await host.close();
	await guest.close();
});

test("sala com um jogador conectado nao expira", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const { host, guest, guestMatch } = await pairByCode(context);
	const roomId = guestMatch.room_id;
	await host.close();
	await guest.next("opponent_disconnected");
	guest.clear();

	context.relay.expireVacantRooms(Date.now() + 60 * 60 * 1000);

	assert.equal(context.relay.rooms.has(roomId), true);
	assert.equal(clientState(context.relay, "Bob").room, roomId);
	assert.equal(guest.messages.length, 0);

	await guest.close();
});

test("sala com os dois jogadores ausentes expira apos a carencia", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const { host, guest, guestMatch } = await pairByCode(context);
	const roomId = guestMatch.room_id;
	await host.close();
	await guest.close();
	await waitFor(() => {
		const room = context.relay.rooms.get(roomId);
		return room && room.slots.H === null && room.slots.C === null;
	}, "os dois slots vazios");

	context.relay.expireVacantRooms(Date.now() + 121 * 1000);

	assert.equal(context.relay.rooms.has(roomId), false);
});

test("sala de retomada junta os dois participantes pelo game_id", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const participants = ["Alice", "Bob"];
	const host = await connectClient(context.url);
	await host.next("hello");
	host.send({
		t: "create_resume_room",
		game_id: "abc123",
		username: "Alice",
		participants,
	});
	const waiting = await host.next("waiting");
	assert.equal(waiting.mode, "resume");
	assert.equal(waiting.game_id, "abc123");

	const guest = await connectClient(context.url);
	guest.send({
		t: "join_resume_room",
		game_id: "abc123",
		username: "Bob",
		participants,
	});
	const [hostMatch, guestMatch] = await Promise.all([
		host.next("match_found"),
		guest.next("match_found"),
	]);
	assert.equal(hostMatch.mode, "resume");
	assert.equal(guestMatch.game_id, "abc123");
	assert.deepEqual(guestMatch.participants, participants);

	const lobby = await getJson(context.port, "/rooms");
	assert.equal(lobby.body.rooms.length, 0);

	await host.close();
	await guest.close();
});

test("participantes divergentes sao recusados na retomada", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const host = await connectClient(context.url);
	await host.next("hello");
	host.send({
		t: "create_resume_room",
		game_id: "abc123",
		username: "Alice",
		participants: ["Alice", "Bob"],
	});
	await host.next("waiting");

	const guest = await connectClient(context.url);
	guest.send({
		t: "join_resume_room",
		game_id: "abc123",
		username: "Carol",
		participants: ["Alice", "Carol"],
	});
	const error = await guest.next("error");
	assert.match(error.msg, /participantes/i);
	assert.equal(clientState(context.relay, "Carol").room, null);

	await host.close();
	await guest.close();
});

test("convidado da retomada pode esperar o anfitriao", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const participants = ["Alice", "Bob"];
	const guest = await connectClient(context.url);
	await guest.next("hello");
	guest.send({
		t: "join_resume_room",
		game_id: "abc123",
		username: "Bob",
		participants,
	});
	assert.equal((await guest.next("waiting")).mode, "resume");

	const host = await connectClient(context.url);
	host.send({
		t: "create_resume_room",
		game_id: "abc123",
		username: "Alice",
		participants,
	});
	const [hostMatch, guestMatch] = await Promise.all([
		host.next("match_found"),
		guest.next("match_found"),
	]);
	assert.equal(hostMatch.role, "H");
	assert.equal(guestMatch.role, "C");

	await host.close();
	await guest.close();
});

test("convidado sem participantes locais entra na copia intacta", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const guest = await connectClient(context.url);
	await guest.next("hello");
	guest.send({
		t: "join_resume_room",
		game_id: "abc123",
		username: "Bob",
		participants: [],
	});
	await guest.next("waiting");

	const host = await connectClient(context.url);
	host.send({
		t: "create_resume_room",
		game_id: "abc123",
		username: "Alice",
		participants: ["Alice", "Bob"],
	});
	const guestMatch = await guest.next("match_found");
	assert.deepEqual(guestMatch.participants, ["Alice", "Bob"]);

	await host.close();
	await guest.close();
});

test("terceiro jogador sem participantes locais e recusado na retomada", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const guest = await connectClient(context.url);
	await guest.next("hello");
	guest.send({
		t: "join_resume_room",
		game_id: "abc123",
		username: "Carol",
		participants: [],
	});
	await guest.next("waiting");

	const host = await connectClient(context.url);
	host.send({
		t: "create_resume_room",
		game_id: "abc123",
		username: "Alice",
		participants: ["Alice", "Bob"],
	});
	const waiting = await host.next("waiting");
	assert.equal(waiting.mode, "resume");
	assert.match((await guest.next("error")).msg, /nao participou/i);
	assert.equal(host.messages.filter((m) => m.t === "match_found").length, 0);

	await host.close();
	await guest.close();
});

test("codigo invalido e sala cheia devolvem erro", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const outsider = await connectClient(context.url);
	await outsider.next("hello");
	outsider.send({ t: "join_room", code: "ZZZZZZ", username: "Bob" });
	assert.match((await outsider.next("error")).msg, /nao encontrada/i);
	outsider.send({ t: "join_room", code: "abc", username: "Bob" });
	assert.match((await outsider.next("error")).msg, /codigo de sala/i);

	const { host, guest, waiting } = await pairByCode(context);
	outsider.send({
		t: "join_room",
		code: waiting.room_id,
		username: "Carol",
	});
	assert.match((await outsider.next("error")).msg, /cheia/i);

	await host.close();
	await guest.close();
	await outsider.close();
});

test("handshake informa a versao do protocolo", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const client = await connectClient(context.url);
	const hello = await client.next("hello");
	assert.equal(hello.protocol, PROTOCOL_VERSION);
	assert.equal(hello.version, "1.0.0");
	assert.equal(hello.room_grace_seconds, 120);

	await client.close();
});

test("protocolo incompativel e recusado com mensagem clara", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const client = await connectClient(context.url);
	const closed = new Promise((resolve) => {
		client.ws.once("close", (code) => resolve(code));
	});
	client.send({ t: "hello", protocol: PROTOCOL_VERSION + 1 });

	const error = await client.next("error");
	assert.equal(error.code, "protocol_mismatch");
	assert.match(error.msg, /protocolo/i);
	assert.equal(await closed, 1002);
});

test("healthz responde com status e contagens", async (t) => {
	const context = await startRelay();
	t.after(() => context.relay.close());

	const health = await getJson(context.port, "/healthz");
	assert.equal(health.status, 200);
	assert.equal(health.body.status, "ok");
	assert.equal(health.body.protocol, PROTOCOL_VERSION);
	assert.equal(health.body.rooms, 0);
	assert.equal(health.body.clients, 0);

	const missing = await getJson(context.port, "/desconhecido");
	assert.equal(missing.status, 404);
});

test("limite de mensagens por conexao encerra o cliente", async (t) => {
	const context = await startRelay({
		messageBurst: 2,
		messageRatePerSecond: 0,
	});
	t.after(() => context.relay.close());

	const client = await connectClient(context.url);
	await client.next("hello");
	const closed = new Promise((resolve) => {
		client.ws.once("close", (code) => resolve(code));
	});
	client.send({ t: "unknown", index: 1 });
	client.send({ t: "unknown", index: 2 });
	client.send({ t: "unknown", index: 3 });

	const error = await client.next("error");
	assert.equal(error.code, "rate_limited");
	assert.equal(await closed, 1008);
});

test("limite de salas por IP e aplicado", async (t) => {
	const context = await startRelay({ maxRoomsPerIp: 1 });
	t.after(() => context.relay.close());

	const first = await connectClient(context.url);
	await first.next("hello");
	first.send({ t: "create_room", username: "Alice" });
	await first.next("waiting");

	const second = await connectClient(context.url);
	await second.next("hello");
	second.send({ t: "create_room", username: "Bob" });
	assert.match((await second.next("error")).msg, /salas abertas/i);

	await first.close();
	await second.close();
});

test("Origin fora da allowlist e recusado; desktop sem Origin passa", async (t) => {
	const context = await startRelay({
		allowedOrigins: ["https://play.example.com"],
	});
	t.after(() => context.relay.close());

	const desktop = await connectClient(context.url);
	await desktop.next("hello");

	const allowed = await connectClient(context.url, {
		origin: "https://play.example.com",
	});
	await allowed.next("hello");

	const rejection = await connectExpectingRejection(context.url, {
		origin: "https://evil.example.com",
	});
	assert.match(rejection, /403/);

	await desktop.close();
	await allowed.close();
});
