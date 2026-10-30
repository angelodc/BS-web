const RELAY_URL = (process.env.RELAY_URL || "").replace(/\/+$/, "");
const CACHE_SECONDS = 3;
const TIMEOUT_MS = 2500;

function reply(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": `public, max-age=${CACHE_SECONDS}, stale-while-revalidate=10`,
    },
    body: JSON.stringify(body),
  };
}

// O endereco vai junto mesmo quando o relay nao responde: o lobby usa essa URL
// para montar os links do jogo, e assim so falta arrumar o relay, nao o link.
function offline() {
  return reply(503, { rooms: [], relay: { online: false, url: RELAY_URL } });
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

exports.handler = async () => {
  if (!RELAY_URL) {
    return offline();
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const response = await fetch(`${RELAY_URL}/rooms`, {
      signal: controller.signal,
      headers: { Accept: "application/json" },
    });
    if (!response.ok) {
      return offline();
    }
    const data = await response.json();
    const rooms = Array.isArray(data.rooms) ? data.rooms.map(sanitize) : [];
    return reply(200, {
      rooms,
      relay: {
        online: true,
        url: RELAY_URL,
        version: String(data.version || ""),
      },
    });
  } catch (_error) {
    return offline();
  } finally {
    clearTimeout(timer);
  }
};
