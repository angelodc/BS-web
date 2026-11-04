# online/

Pasta de web/deploy do Battle Scenes. O Godot ignora esta pasta por causa do
`.gdignore`; nada aqui é cena ou script do jogo.

```text
online/
├── netlify.toml          base do site Netlify = online, publish = site
├── netlify/
│   ├── functions/        API HTTP: salas.mjs (proxy) e relay.mjs (registro)
│   │   └── package.json  dependência @netlify/blobs (node_modules ignorado)
│   └── lib/relay-url.mjs  fonte única do endereço do relay
├── site/
│   ├── index.html        página /salas (lobby)
│   └── game/             export HTML5 (gerado, não versionado)
└── README.md
```

## Estado

- **Publicado em produção:** https://battle-scenes.netlify.app (deploy manual da
  CLI, sem Git CD; projeto público, previews protegidos). Lobby em `/` e jogo em
  `/game/`.
- A Function `/api/salas` e a página `/salas` estão no ar e funcionando.
- O endereço do relay é **fixo**: `RELAY_URL` aponta para
  `https://129-159-222-25.sslip.io` (VM Oracle), `/api/salas` o devolve e o
  lobby anexa `?relay=` sozinho em “Abrir o jogo” e nos links de sala. O Blob
  `relay/address` está vazio; se algum registro existir, ele vence o
  `RELAY_URL`. O `POST /api/relay` é rota de emergência para túnel temporário.
- O cliente web já tem `join_room` por código, entrada “Entrar com código” no
  menu, leitura de `?room=CODIGO` e `?relay=HOST`, padrão `wss://` e
  `LocalRelay` desativado no navegador. Falta validar dois navegadores em redes
  diferentes pelo endereço novo.
- O endereço web padrão é o placeholder `wss://relay.exemplo.com` em
  [src/custom/Rede.gd](../src/custom/Rede.gd); o lobby sempre passa `?relay=`,
  então ele só aparece quando a página do jogo é aberta direto.

## Exportar o jogo

Instale os templates de exportação do Godot 4.7.2 e use
**Projeto → Exportar → Web**. A saída configurada é
`online/site/game/index.html`.

### PWA (instalar como app)

O site é instalável como app pelo próprio navegador. Os arquivos ficam na raiz
do site, fora do build do jogo:

| Arquivo | Papel |
| --- | --- |
| `site/manifest.webmanifest` | nome, ícones, `start_url` `/` e modo `standalone` |
| `site/sw.js` | service worker: cacheia o lobby e deixa `/game/` sempre na rede |
| `site/pwa.js` | registra o service worker e expõe a ponte `bsPwaCanInstall`/`bsPwaInstall` usada pelo jogo |
| `site/icons/pwa-192.png`, `pwa-512.png` | ícones do manifest (gerados a partir de `icon.png`, placeholders até a arte própria) |

`start_url` é `/` de propósito: o app instalado abre o lobby, que consulta
`/api/salas` e anexa `?relay=` no link do jogo. Os arquivos do jogo **não**
entram no cache do service worker — o `.pck`/`.wasm` continua com
`must-revalidate`, então uma publicação nova não fica presa atrás do SW.
Offline, o lobby abre; a partida precisa de rede.

O lobby carrega o manifest e o `pwa.js` direto no HTML. O jogo recebe as mesmas
tags pelo `html/head_include` do preset Web em
[../export_presets.cfg](../export_presets.cfg), então reexportar não perde a
PWA. O menu do jogo mostra o botão **Instalar app** só na versão web
(`MainMenu.gd`); no iPhone/iPad ele explica o caminho manual (Compartilhar →
Adicionar à Tela de Início).

### Analytics e login (opcionais)

| Arquivo | Papel |
| --- | --- |
| `site/analytics.js` | GA4 enxuto com consent mode v2, banner e `window.bsTrack`/`bsSetUserId` |
| `site/auth.js` | login Google via Supabase Auth no lobby; o jogo só lê a sessão |
| `src/core/Analytics.gd` | autoload que envia `game_open` uma vez com a resolução real do canvas |
| `src/core/Auth.gd` | autoload que lê `bsAuthToken`/`bsAuthUserId` pelo `JavaScriptBridge` |

O GA4 está ativo com `MEASUREMENT_ID = G-Z4YHVSLCRL` em `analytics.js`. Antes
do aceite do banner nenhum script do Google é carregado e `bsTrack` devolve
`false`; o arquivo é servido com `must-revalidate`, então trocar o ID não exige
reexportar o jogo. O `game_open` leva `canvas_w/h`, `window_w/h`, `dpr` e
`mode`, e o `user_id` só aceita o UUID do Supabase — nunca e-mail ou nome. O
link **Cookies** reabre o banner para mudar a escolha.

O login é opcional: sem sessão, solo e multiplayer continuam funcionando pelo
username. Com sessão, o lobby guarda `bs_auth_session` (token, UUID e validade)
e o jogo envia o token nas mensagens de controle; o relay valida pelo JWKS do
Supabase e usa o `sub` como identidade. A chave `sb_publishable_...` é pública
por design; `service_role` e o client secret do Google ficam só no Supabase.

Console já configurado (04/11/2026), no projeto Supabase **battle-scenes**
(`ulchgvwidctalaaxugeg`, região São Paulo), que serve só de Auth — os dados de
deck do editor continuam no projeto antigo (`xtdqcfchdqmqlbmkvdit`):

- provedor **Google** habilitado com o Client ID e o secret do OAuth Client
  `Battle Scenes Login` (`703823413358-sjoao5hc6b7hvc619bv9j49p6qtce242`);
- Site URL `https://battle-scenes.netlify.app` e Redirect URLs
  `https://battle-scenes.netlify.app/**`, `http://localhost:8080/**` e
  `http://localhost:8888/**`;
- o mesmo OAuth Client autoriza as três origens e o redirect
  `https://ulchgvwidctalaaxugeg.supabase.co/auth/v1/callback`.

O relay lê `SUPABASE_URL` (padrão: `https://ulchgvwidctalaaxugeg.supabase.co`).
A VM ainda tem a URL antiga no `.env` do `bs-relay`; trocar é mudança de
produção e pede reinício do serviço. O app OAuth está em modo **Testing**, então
só contas de teste entram; publicar a tela de consentimento depende das páginas
de termos e privacidade.

## Testar localmente

1. Suba o relay em outro terminal:

```bash
cd relay
npm install   # uma vez
npm start     # http://127.0.0.1:9080
```

2. Suba o site apontando o proxy para o relay:

```bash
cd online
npm install -g netlify-cli              # uma vez
cd netlify/functions && npm install     # uma vez: instala @netlify/blobs
cd ../..
RELAY_URL=http://127.0.0.1:9080 netlify dev
```

Jogo em `http://localhost:8888/game/` (depois do export) e lobby em
`http://localhost:8888/` (funciona sem o export).

Para testar a PWA, `localhost` já conta como contexto seguro: abra
`http://localhost:8888/`, confira **DevTools → Application → Manifest** e
**Service Workers** e use **Instalar app** (Chrome/Edge). O prompt de
instalação só aparece com manifest, service worker controlando a página e
HTTPS (ou localhost); em produção o Netlify serve os dois.

A Function lê `RELAY_URL` **HTTP(S)** (sem barra final), por exemplo
`https://129-159-222-25.sslip.io`. Não use `wss://` aqui: o proxy faz
`fetch("${url}/rooms")`. O `wss://` é o endereço usado pelo cliente do
jogo. Sem a variável **e** sem registro no Blob, `/api/salas` responde 503 com
`relay.online = false`.

No `netlify dev` o store de blobs é uma cópia local isolada: não lê nem escreve
os dados de produção, então localmente quem manda é o `RELAY_URL`.

Para testar o jogo web contra o relay local, abra
`http://localhost:8888/game/?relay=127.0.0.1:9080` (endereços locais usam `ws://`);
sem `?relay=`, o cliente usa o endereço público `wss://`.

## API

### `GET /api/salas`

Proxy de `GET /rooms` do relay, com cache de 3 s e `stale-while-revalidate` de
10 s. Devolve `rooms` (só `code`, `host`, `mode`, `players`, `status`,
`created_at` e `expires_at`, com valores limitados) e `relay.online`/`relay.url`.
Quando o relay não responde, devolve 503 **com a URL mesmo assim**: o lobby usa
esse endereço para montar os links do jogo, então só falta arrumar o relay.

### `GET /api/relay`

`{ "registered": false, "url": "https://129-159-222-25.sslip.io" }`. Sem registro
no Blob, `registered` é `false` e `url` cai no `RELAY_URL` do ambiente (ou
`null`). Com o relay fixo, esse é o estado esperado.

### `POST /api/relay`

Rota de emergência para um túnel temporário: escreve o endereço público do relay
no Blob `relay/address`. Exige o cabeçalho `x-relay-secret` igual ao
`RELAY_REGISTER_SECRET` do site (401 se não bater; 503 se o site não tiver
segredo), aceita apenas `https:` e host dentro de `RELAY_HOST_PATTERN` (padrão
`^[a-z0-9-]+\.trycloudflare\.com$`) e devolve `{ "ok": true, "url": … }`. Sem
segredo válido ou fora da allowlist, nada é gravado — essa Function é a única
porta de escrita do Blob. Enquanto houver valor no Blob, ele vence o
`RELAY_URL`; para voltar ao endereço fixo, apague a chave com
`netlify blobs:delete relay address`.

Quem chama é o registrador do celular
([../relay/tools/register-relay.mjs](../relay/tools/register-relay.mjs)) quando
o fallback é ligado; os detalhes estão no [README do relay](../relay/README.md).

## Publicar

```bash
cd online
netlify deploy --prod --dir site --functions netlify/functions --no-build
```

O build não vai para o git. Deploy por Git exigiria commitar
`site/game/` ou criar uma Action que rode o export do Godot.

Variáveis do site (definidas pela CLI/dashboard, nunca no `netlify.toml`):
`RELAY_URL` (endereço fixo de produção,
`https://129-159-222-25.sslip.io`) e `RELAY_REGISTER_SECRET` (segredo do
registro de emergência). Depois de mudar uma variável é preciso publicar de novo
para as Functions pegarem o valor.

O `index.pck`/`index.wasm` são pedidos pelo shell do Godot sem query de versão,
então o `netlify.toml` os serve com `public, max-age=0, must-revalidate`: o
navegador confere o ETag (304 quando nada mudou) e pega o build novo na hora.
Não troque por `immutable` — quem já jogou ficaria preso ao pacote antigo.

## Relay

O relay de produção fica em [../relay/](../relay/README.md) (Node.js + `ws`),
fora do Netlify, rodando na VM Always Free da Oracle em Frankfurt com IP
reservado `129.159.222.25` (`https://129-159-222-25.sslip.io`), atrás do Caddy.
Ele é a fonte de verdade das salas; o lobby aqui só consulta `GET /rooms` e
guarda o endereço público dele.

## Escopo

- O lobby só lê `GET /rooms` do relay; não guarda sala, não cria TTL e não faz
  claim de entrada.
- O único estado possível do site é o Blob `relay/address` (um endereço
  público, sem TTL próprio e hoje vazio): nada de contadores, saldos ou dados de
  jogador em blobs.
- Detalhes e fases: [../ONLINE_HOSTING.md](../ONLINE_HOSTING.md).
