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
- O endereço do relay é **auto-registrado** pelo celular em `POST /api/relay`;
  `/api/salas` o lê de um Netlify Blob e o lobby anexa `?relay=` sozinho em
  “Abrir o jogo” e nos links de sala. O `RELAY_URL` do Netlify é só reserva.
- O cliente web já tem `join_room` por código, entrada “Entrar com código” no
  menu, leitura de `?room=CODIGO` e `?relay=HOST`, padrão `wss://` e
  `LocalRelay` desativado no navegador. Falta validar dois navegadores em redes
  diferentes.
- O endereço web padrão é o placeholder `wss://relay.exemplo.com` em
  [src/custom/Rede.gd](../src/custom/Rede.gd); troque-o pelo domínio publicado
  ou use `?relay=` ao testar.

## Exportar o jogo

Instale os templates de exportação do Godot 3.4.4 e use
**Projeto → Exportar → HTML5**. A saída configurada é
`online/site/game/index.html`.

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

A Function lê `RELAY_URL` **HTTP(S)** (sem barra final), por exemplo
`https://relay.exemplo.com`. Não use `wss://` aqui: o proxy faz
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

`{ "registered": true, "url": "https://<host>.trycloudflare.com" }`. Sem registro,
`registered` é `false` e `url` cai no `RELAY_URL` do ambiente (ou `null`).

### `POST /api/relay`

Escreve o endereço público do relay no Blob `relay/address`. Exige o cabeçalho
`x-relay-secret` igual ao `RELAY_REGISTER_SECRET` do site (401 se não bater; 503
se o site não tiver segredo), aceita apenas `https:` e host dentro de
`RELAY_HOST_PATTERN` (padrão `^[a-z0-9-]+\.trycloudflare\.com$`) e devolve
`{ "ok": true, "url": … }`. Sem segredo válido ou fora da allowlist, nada é
gravado — essa Function é a única porta de escrita do Blob.

Quem chama é o registrador do celular
([../relay/tools/register-relay.mjs](../relay/tools/register-relay.mjs)); os
detalhes estão no [README do relay](../relay/README.md).

## Publicar

```bash
cd online
netlify deploy --prod --dir site --functions netlify/functions --no-build
```

O build não vai para o git. Deploy por Git exigiria commitar
`site/game/` ou criar uma Action que rode o export do Godot.

Variáveis do site (definidas pela CLI/dashboard, nunca no `netlify.toml`):
`RELAY_URL` (reserva) e `RELAY_REGISTER_SECRET` (segredo do registro). Depois de
mudar uma variável é preciso publicar de novo para as Functions pegarem o valor.

O `index.pck`/`index.wasm` são pedidos pelo shell do Godot sem query de versão,
então o `netlify.toml` os serve com `public, max-age=0, must-revalidate`: o
navegador confere o ETag (304 quando nada mudou) e pega o build novo na hora.
Não troque por `immutable` — quem já jogou ficaria preso ao pacote antigo.

## Relay

O relay de produção fica em [../relay/](../relay/README.md) (Node.js + `ws`),
fora do Netlify, publicado no S20 FE atrás de um túnel Cloudflare. Ele é a fonte
de verdade das salas; o lobby aqui só consulta `GET /rooms` e guarda o endereço
público dele.

## Escopo

- O lobby só lê `GET /rooms` do relay; não guarda sala, não cria TTL e não faz
  claim de entrada.
- O único estado do site é o Blob `relay/address` (um endereço público, sem TTL
  próprio): nada de contadores, saldos ou dados de jogador em blobs.
- Detalhes e fases: [../ONLINE_HOSTING.md](../ONLINE_HOSTING.md).
