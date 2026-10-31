import { ADDRESS_KEY, ENV_URL, relayStore } from "../lib/relay-url.mjs";

const SECRET = process.env.RELAY_REGISTER_SECRET || "";
// O celular publica um túnel *.trycloudflare.com; quando houver domínio fixo o
// padrão muda por variável de ambiente, sem tocar no jogo nem no lobby.
const HOST_PATTERN = new RegExp(
  process.env.RELAY_HOST_PATTERN || "^[a-z0-9-]+\\.trycloudflare\\.com$",
);

function reply(statusCode, body) {
  return new Response(JSON.stringify(body), {
    status: statusCode,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

// Quem escreve aqui decide para onde todos os jogadores apontam, então a rota só
// aceita o segredo compartilhado com o celular e hosts do padrão combinado.
export default async (request) => {
  if (request.method === "GET") {
    try {
      const url = (await relayStore().get(ADDRESS_KEY)) || "";
      return reply(200, {
        registered: Boolean(url),
        url: url || ENV_URL || null,
      });
    } catch (error) {
      console.error("relay: falha ao ler o registro", error);
      return reply(500, { registered: false, reason: "registro indisponível" });
    }
  }

  if (request.method !== "POST" && request.method !== "PUT") {
    return reply(405, { ok: false, reason: 'use POST com {"url":"https://..."}' });
  }
  if (!SECRET) {
    return reply(503, { ok: false, reason: "registro desabilitado neste site" });
  }
  if (request.headers.get("x-relay-secret") !== SECRET) {
    return reply(401, { ok: false, reason: "segredo inválido" });
  }

  let payload;
  try {
    payload = await request.json();
  } catch (error) {
    return reply(400, { ok: false, reason: "corpo inválido" });
  }

  const raw = String(payload.url || "").trim().replace(/\/+$/, "");
  let parsed;
  try {
    parsed = new URL(raw);
  } catch (error) {
    return reply(400, { ok: false, reason: "url inválida" });
  }
  if (parsed.protocol !== "https:" || !HOST_PATTERN.test(parsed.host)) {
    return reply(400, { ok: false, reason: "host fora do padrão permitido" });
  }

  try {
    await relayStore().set(ADDRESS_KEY, parsed.origin, {
      metadata: { host: parsed.host, updated_at: new Date().toISOString() },
    });
  } catch (error) {
    console.error("relay: falha ao gravar o registro", error);
    return reply(500, { ok: false, reason: "não foi possível gravar o registro" });
  }
  return reply(200, { ok: true, url: parsed.origin });
};
