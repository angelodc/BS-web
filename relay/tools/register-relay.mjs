#!/usr/bin/env node
// Registra o endereço público do relay no site publicado.
//
// O túnel rápido do cloudflared sorteia um hostname novo a cada reinício. Este
// script descobre o nome atual no log do túnel, confirma que o relay responde e
// publica em /api/relay, que grava o endereço num Blob do Netlify. O lobby passa
// então a entregar o endereço certo sem nenhum redeploy.
//
// Uso:
//   node register-relay.mjs            # uma tentativa
//   node register-relay.mjs --watch    # confere a cada INTERVAL_MS (60 s)
//
// O segredo fica fora do repositório: $RELAY_SECRET_FILE (padrão
// ~/.bs-relay-secret, modo 600). Roda no Node do Termux, sem dependências.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const SITE = process.env.SITE || "https://battle-scenes.netlify.app";
const TUNNEL_LOG =
  process.env.TUNNEL_LOG || join(homedir(), "projetos/bs-relay/cf-relay.log");
const HEALTH_URL = process.env.HEALTH_URL || "http://127.0.0.1:9080/healthz";
const SECRET_FILE =
  process.env.RELAY_SECRET_FILE || join(homedir(), ".bs-relay-secret");
const INTERVAL_MS = Number(process.env.INTERVAL_MS || 60000);
// Mesmo padrão que a Function aceita; um host fora dele nunca é publicado.
const HOST = /^[a-z0-9-]+\.trycloudflare\.com$/;

function log(message) {
  console.log(`${new Date().toISOString()} ${message}`);
}

function currentUrl() {
  let text = "";
  try {
    text = readFileSync(TUNNEL_LOG, "utf8");
  } catch (_error) {
    return "";
  }
  const found = text.match(/[a-z0-9-]+\.trycloudflare\.com/g) || [];
  const host = found[found.length - 1] || "";
  return HOST.test(host) ? `https://${host}` : "";
}

async function healthy() {
  try {
    const response = await fetch(HEALTH_URL, {
      signal: AbortSignal.timeout(8000),
    });
    return response.ok;
  } catch (_error) {
    return false;
  }
}

// O que o site está entregando agora. Sem isso o script republicaria o mesmo
// endereço a cada minuto.
async function remoteUrl() {
  try {
    const response = await fetch(`${SITE}/api/relay`, {
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) return "";
    const data = await response.json();
    return data.registered ? String(data.url || "") : "";
  } catch (_error) {
    return "";
  }
}

async function publish(url) {
  const secret = readFileSync(SECRET_FILE, "utf8").trim();
  const response = await fetch(`${SITE}/api/relay`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-relay-secret": secret,
    },
    body: JSON.stringify({ url }),
    signal: AbortSignal.timeout(20000),
  });
  const body = await response.text();
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} ${body}`);
  }
}

async function syncOnce() {
  const url = currentUrl();
  if (!url) {
    log(`sem hostname de túnel em ${TUNNEL_LOG}`);
    return false;
  }
  if ((await remoteUrl()) === url) {
    return true;
  }
  // Endereço novo com o relay caído só espalharia um link morto.
  if (!(await healthy())) {
    log("relay fora do ar, registro adiado");
    return false;
  }
  try {
    await publish(url);
    log(`registrado ${url}`);
    return true;
  } catch (error) {
    log(`falha ao registrar: ${error.message}`);
    return false;
  }
}

if (process.argv.includes("--watch")) {
  for (;;) {
    await syncOnce();
    await new Promise((resolve) => setTimeout(resolve, INTERVAL_MS));
  }
} else {
  process.exit((await syncOnce()) ? 0 : 1);
}
