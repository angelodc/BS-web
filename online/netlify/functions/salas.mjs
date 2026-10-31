import { registeredUrl } from "../lib/relay-url.mjs";

const CACHE_SECONDS = 3;
const TIMEOUT_MS = 2500;

function reply(statusCode, body) {
  return new Response(JSON.stringify(body), {
    status: statusCode,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": `public, max-age=${CACHE_SECONDS}, stale-while-revalidate=10`,
    },
  });
}

// O endereço vai junto mesmo quando o relay não responde: o lobby usa essa URL
// para montar os links do jogo, e assim só falta arrumar o relay, não o link.
function offline(url) {
  return reply(503, { rooms: [], relay: { online: false, url } });
}

function sanitize(room) {
  return {
    code: String(room.code || "").slice(0, 12),
    host: String(room.host || "").slice(0, 32),
    mode: room.mode === "resume" ? "resume" : "match",
    players: Math.max(0, Math.min(2, Number(room.players) || 0)),
    status: room.status === "waiting" ? "waiting" : "playing",
    created_at: String(room.created_at || ""),
    expires_at: String(room.expires_at || ""),
  };
}

export default async () => {
  const url = await registeredUrl();
  if (!url) {
    return offline("");
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const response = await fetch(`${url}/rooms`, {
      signal: controller.signal,
      headers: { Accept: "application/json" },
    });
    if (!response.ok) {
      return offline(url);
    }
    const data = await response.json();
    const rooms = Array.isArray(data.rooms) ? data.rooms.map(sanitize) : [];
    return reply(200, {
      rooms,
      relay: { online: true, url, version: String(data.version || "") },
    });
  } catch (error) {
    console.error("salas: falha ao consultar o relay", error);
    return offline(url);
  } finally {
    clearTimeout(timer);
  }
};
