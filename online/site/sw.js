// Service worker mínimo: torna o site instalável e guarda o lobby para
// abrir offline. Os arquivos do jogo (/game/) ficam fora do cache de
// propósito: o .pck/.wasm não têm versão na URL e o netlify.toml os serve
// com must-revalidate justamente para o jogador não ficar preso ao build
// antigo. Offline aqui significa "o lobby abre", não "a partida funciona
// sem rede".
const CACHE = "bs-web-shell-v1";
const SHELL = [
  "/",
  "/manifest.webmanifest",
  "/icons/pwa-192.png",
  "/icons/pwa-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Build do jogo: sempre da rede, nunca do cache.
  if (url.pathname.startsWith("/game/")) return;

  if (!SHELL.includes(url.pathname)) return;

  // Shell do lobby: rede primeiro, cache como rede de segurança offline.
  event.respondWith(
    fetch(request)
      .then((response) => {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(request, copy));
        return response;
      })
      .catch(() => caches.match(request).then((hit) => hit || caches.match("/")))
  );
});
