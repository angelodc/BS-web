// Entrada do relay público. Lê a configuração do ambiente, sobe HTTP +
// WebSocket na mesma porta e encerra de forma limpa em SIGINT/SIGTERM.
import { createRelay, DEFAULT_VERSION, PROTOCOL_VERSION } from "./relay.js";

function numberFromEnv(name, fallback) {
	const raw = process.env[name];
	if (raw === undefined || raw === "") return fallback;
	const value = Number(raw);
	return Number.isFinite(value) ? value : fallback;
}

function boolFromEnv(name, fallback) {
	const raw = process.env[name];
	if (raw === undefined || raw === "") return fallback;
	return ["1", "true", "yes", "on"].includes(raw.toLowerCase());
}

function listFromEnv(name) {
	return (process.env[name] || "")
		.split(",")
		.map((value) => value.trim())
		.filter(Boolean);
}

const relay = createRelay({
	version: process.env.RELAY_VERSION || DEFAULT_VERSION,
	allowedOrigins: listFromEnv("ALLOWED_ORIGINS"),
	trustProxy: boolFromEnv("TRUST_PROXY", false),
	maxConnections: numberFromEnv("MAX_CONNECTIONS", 500),
	maxConnectionsPerIp: numberFromEnv("MAX_CONNECTIONS_PER_IP", 10),
	maxRooms: numberFromEnv("MAX_ROOMS", 200),
	maxRoomsPerIp: numberFromEnv("MAX_ROOMS_PER_IP", 3),
	messageRatePerSecond: numberFromEnv("MESSAGE_RATE", 40),
	messageBurst: numberFromEnv("MESSAGE_BURST", 120),
	roomGraceMs: numberFromEnv("ROOM_GRACE_SECONDS", 120) * 1000,
	reaperIntervalMs: numberFromEnv("REAPER_INTERVAL_SECONDS", 5) * 1000,
	heartbeatIntervalMs: numberFromEnv("HEARTBEAT_SECONDS", 30) * 1000,
	logLevel: process.env.LOG_LEVEL || "info",
});

const port = numberFromEnv("PORT", 9080);
const host = process.env.HOST || "0.0.0.0";

function log(event, fields = {}) {
	if (relay.config.logLevel === "silent") return;
	console.log(JSON.stringify({ ts: new Date().toISOString(), event, ...fields }));
}

relay.httpServer.listen(port, host, () => {
	log("relay_listening", {
		host,
		port,
		protocol: PROTOCOL_VERSION,
		version: relay.config.version,
	});
});

relay.httpServer.on("error", (error) => {
	log("relay_error", { error: String(error) });
	process.exitCode = 1;
});

let shuttingDown = false;
async function shutdown(signal) {
	if (shuttingDown) return;
	shuttingDown = true;
	log("relay_shutdown", { signal });
	await relay.close();
	process.exit(0);
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
