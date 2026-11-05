import { registeredUrl } from "../lib/relay-url.mjs";

const CACHE_SECONDS = 60;
const TIMEOUT_MS = 2500;

function reply(body) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": `public, max-age=${CACHE_SECONDS}, stale-while-revalidate=30`,
    },
  });
}

function toIso(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

// O semver e a data do deploy saem do version.json publicado: o arquivo e
// reenviado a cada deploy, entao o Last-Modified marca quando o build entrou.
async function publishedVersion(origin) {
  if (!origin) return { version: null, deployedAt: null };
  try {
    const response = await fetch(`${origin}/version.json`, {
      signal: AbortSignal.timeout(3000),
      headers: { Accept: "application/json" },
      cache: "no-store",
    });
    if (!response.ok) return { version: null, deployedAt: null };
    const body = await response.json();
    return {
      version: String(body.version || ""),
      deployedAt: toIso(response.headers.get("last-modified")),
    };
  } catch (error) {
    console.error("version: falha ao ler version.json", error);
    return { version: null, deployedAt: null };
  }
}

async function relayInfo() {
  const url = await registeredUrl();
  if (!url) return { online: false, url: null, version: null };
  try {
    const response = await fetch(`${url}/healthz`, {
      signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: { Accept: "application/json" },
    });
    if (!response.ok) return { online: false, url, version: null };
    const data = await response.json();
    return { online: true, url, version: String(data.version || "") };
  } catch (error) {
    return { online: false, url, version: null };
  }
}

// Quem publica troca o conteudo do deploy, nao o nome do site. O commit e o
// unico dado que identifica o build mesmo quando o service worker e o cache do
// navegador ainda estao entre o jogador e o servidor.
export default async () => {
  const origin = (process.env.DEPLOY_PRIME_URL || process.env.URL || "")
    .replace(/\/+$/, "");
  const [game, relay] = await Promise.all([
    publishedVersion(origin),
    relayInfo(),
  ]);
  return reply({
    game: String(process.env.COMMIT_REF || "").slice(0, 7) || null,
    version: game.version,
    deployedAt: game.deployedAt,
    relay,
  });
};
