# Hospedagem online: Netlify + lobby + relay

Este documento planeja como publicar o Battle Scenes no navegador e oferecer
descoberta de partidas pela internet. Ele registra decisões, limites, uma ordem
de trabalho e o que já está implementado no repositório. **Desde 30/10/2026 o
conjunto está no ar**: o jogo e o lobby em https://battle-scenes.netlify.app e o
relay no S20 FE atrás de um túnel Cloudflare, com o endereço público
auto-registrado no site (ver “Estado atual do projeto”).

## Resposta curta

**O Netlify resolve o jogo e o lobby, mas não o relay em tempo real.**

- **Dá para hospedar no Netlify:** o build HTML5 do Godot (arquivos estáticos),
  a página `/salas` e uma API HTTP de lobby (Netlify Functions). Tudo cabe no
  plano Free para escala pequena.
- **Não dá para hospedar no Netlify:** o relay WebSocket que mantém a partida
  aberta. Funções do Netlify são curtas e sem estado; não suportam conexões
  persistentes nem upgrade de WebSocket. Por isso o relay precisa de um serviço
  sempre ligado (Cloudflare Workers/Durable Objects, Fly.io, Render, Railway,
  VPS etc.) com `wss://`.
- **Versão mais barata (decidida):** o lobby **não guarda estado de sala**. A
  Function apenas repassa `GET /rooms` do relay. Sem DB, sem limpeza agendada e
  sem risco de inconsistência. O relay é dono do ciclo de vida das salas. A única
  exceção é um Blob com **uma chave**: o endereço público do relay
  (`relay/address`), que o celular reescreve quando o túnel muda de hostname.
- **Consequência importante:** com um relay central, os jogadores **não precisam
  trocar IPs**. O lobby mostra um **código de sala**; os dois clientes conectam
  ao mesmo relay público e o relay encaminha as mensagens. Trocar IPs só faz
  sentido no modo LAN/direto em desktop, porque um navegador não consegue abrir
  um servidor WebSocket para outro navegador.

Resumo da arquitetura recomendada:

```text
Navegador A ── HTTPS ──> Netlify CDN (jogo HTML5 + /salas)
      │                        │
      │ wss://                 └── /api/salas ──> Function ──> GET /rooms
      ▼                                  ▲           (sem estado de sala)
Relay WebSocket dedicado                 │ o endereço vem do Blob relay/address
(wss://<host>.trycloudflare.com)         │
      ▲  /rooms, /healthz          /api/relay (POST com segredo)
      │ wss://                           ▲
Navegador B ───────────────────┘   registrador no celular
                                   (relay/tools/register-relay.mjs)
```

O relay continua sendo a única fonte de verdade das salas. O Netlify é CDN do
jogo e fachada HTTP do lobby; ele não guarda estado de sala nem duplica o
estado em tempo real — guarda apenas o endereço público do relay, para o lobby
não depender de uma variável reeditada à mão toda vez que o túnel reinicia.

## Estado atual do projeto

- O cliente Godot usa WebSocket com endereço configurável em
  [src/custom/Rede.gd](./src/custom/Rede.gd); o padrão desktop é
  `127.0.0.1:9080` e o padrão web é `wss://relay.exemplo.com` (placeholder que
  deve ser trocado ao publicar; `?relay=HOST` sobrepõe para testes locais).
- O relay embutido ([src/custom/LocalRelay.gd](./src/custom/LocalRelay.gd)) só
  sobe para endereços locais e serve para LAN/desenvolvimento. Ele não tem TLS,
  autenticação nem persistência, não deve ser exposto à internet e não é
  acionado no build web (`OS.has_feature("web")`).
- O relay externo ([tools/ws_relay.py](./tools/ws_relay.py)) implementa o mesmo
  protocolo de salas em Python puro (sockets + WebSocket manual), também sem TLS.
- O protocolo já separa transporte e mensagens: `create_room`, `join_room`,
  `find_match`, `cancel_match`, `rejoin_room`, `create_resume_room`,
  `join_resume_room` e `leave_room`, além do encaminhamento de mensagens entre
  os dois jogadores.
- O relay Node.js está implementado em [relay/](./relay/README.md): `join_room`
  por código, `hello`/`protocol_version`, `GET /healthz`, `GET /rooms`, limites
  por IP/conexão e mensagem, heartbeat, allowlist de `Origin` e 21 testes com
  clientes `ws` reais. Usa `ws` + `http` no mesmo processo (Opção A).
- O lobby do Netlify está publicado:
  [online/netlify/functions/salas.mjs](./online/netlify/functions/salas.mjs)
  repassa `GET /rooms` com cache de 3 s e devolve `503` quando o relay está
  fora; [online/site/index.html](./online/site/index.html) lista as salas e
  monta links `/game/?room=CODIGO` já com `?relay=` anexado.
- O endereço público do relay é auto-registrado:
  [relay/tools/register-relay.mjs](./relay/tools/register-relay.mjs) roda no
  celular, descobre o hostname do túnel e publica em
  [online/netlify/functions/relay.mjs](./online/netlify/functions/relay.mjs)
  (segredo + allowlist de host), que grava no Blob `relay/address`. As duas
  Functions compartilham
  [online/netlify/lib/relay-url.mjs](./online/netlify/lib/relay-url.mjs).
- O host é autoritativo para início, dados, fases e estado público; o relay não
  valida jogadas. Essa limitação está descrita em [MULTIPLAYER.md](./MULTIPLAYER.md)
  e continua valendo no modo online.
- Já existe um preset HTML5 em [export_presets.cfg](./export_presets.cfg), agora
  com saída em `online/site/game/index.html`. O build local foi gerado com os
  templates do Godot 3.4.4 instalados (`online/site/game/` fica fora do Git).
- A integração do cliente web está implementada: `Rede.join_room` por código,
  leitura de `?room=CODIGO` e `?relay=HOST` no menu, endereço padrão `wss://`
  (com exceção para relay local em desenvolvimento), campo de relay oculto no
  navegador e `LocalRelay` desativado no web. O código da sala aparece no HUD de
  preparação do anfitrião. Foi validada localmente com dois navegadores
  (pareamento, decks 60/60, início e tabuleiro espelhado) e com a importação de
  deck por link do BSDB.
- O [TODO.md](./TODO.md) já prevê “Exportar para HTML5” e “Hospedagem no Netlify”
  na Fase 4.

## O que o Netlify faz e o que não faz

| Necessidade | Netlify | Observação |
|---|---|---|
| Servir o jogo HTML5/WASM | Sim | Deploy estático com CDN e HTTPS automático. |
| API HTTP de lobby | Sim | Netlify Functions (Node/TypeScript), execuções curtas. |
| Salvar informações | Sim (opcional) | Em uso só para o endereço do relay (uma chave); salas continuam no relay. |
| Limpeza agendada | Desnecessária | O relay expira as salas em memória; o Blob não tem TTL e não precisa. |
| WebSocket persistente | **Não** | Functions e Edge Functions não mantêm conexão aberta. |
| Proxy de WebSocket | **Não** | Rewrites do Netlify não fazem upgrade de conexão. |
| Lógica de partida em tempo real | **Não** | Precisa de processo sempre ligado; Functions são stateless. |
| Trocar IPs entre jogadores | Desnecessário | Um relay central evita expor IPs; o código de sala basta. |

Fontes: documentação do Netlify sobre
[Blobs](https://docs.netlify.com/build/data-and-storage/netlify-blobs/) e
[Functions](https://docs.netlify.com/functions/overview/), além da resposta
oficial de que [WebSocket não é suportado](https://answers.netlify.com/t/does-netlify-support-websocket-programming/4213).
Limites de plano mudam; conferir os valores atuais antes de fechar custos.

## Custos no plano Free

O Netlify Free (2026) é cobrado por créditos: **300 créditos/mês com corte
rígido** — ao acabar, os serviços medidos param até o próximo ciclo.

| Consumo | Créditos | Equivalente a 300 créditos |
|---|---|---|
| Banda do site | 20/GB | ≈15 GB/mês |
| Requisições | 2/10k | 1,5 milhão/mês |
| Functions (compute) | 10/GB-hora | 30 GB-hora/mês |
| Blobs | incluído | — |
| Netlify DB | incluído | consome compute/banda |

Consequências práticas:

- **O lobby por proxy custa quase nada.** Uma lista de salas atualizada a cada
  poucos segundos em dezenas de sessões fica na casa de milhares de
  requisições — fração dos 1,5 milhão — e as Functions respondem em milissegundos.
- **O gargalo é o download do jogo.** O `index.pck` publicado mede 7,8 MB, o que
  dá ~1900 primeiros carregamentos por mês; o `.wasm` vem da CDN e quase não
  muda. Com `must-revalidate` em `.pck`/`.wasm`, visitas repetidas gastam só o
  `304` quando nada mudou.
- **Blobs/DB são irrelevantes em custo.** O único uso atual é uma chave com o
  endereço do relay; histórico/ranking (Fase 5) continuaria barato.
- O relay é a única peça fora do Netlify; o custo dele depende do provedor
  (Cloudflare Workers tem plano Free com WebSocket via Durable Objects).

## Estrutura de pastas

Tudo fica no mesmo repositório; os arquivos de web/deploy vivem em uma pasta
separada do projeto Godot.

```text
BS-web/
├── project.godot  src/  assets/  tests/  addons/
├── tools/ws_relay.py          relay de desenvolvimento (LAN)
├── online/                    ← pasta separada, ignorada pelo Godot
│   ├── .gdignore              impede o editor de varrer esta pasta
│   ├── netlify.toml           base do site Netlify = online
│   ├── netlify/functions/     API: salas.mjs (proxy) e relay.mjs (registro)
│   ├── netlify/lib/           relay-url.mjs, fonte única do endereço
│   ├── site/
│   │   ├── index.html         página /salas
│   │   └── game/              export HTML5 (gerado, gitignored)
│   └── README.md              como exportar e publicar
└── relay/                     relay de produção (Node.js + ws)
    ├── src/relay.js           salas, protocolo e limites
    ├── src/server.js          entrada e configuração por ambiente
    ├── test/relay.test.js     testes com clientes ws reais
    ├── tools/register-relay.mjs   publica o hostname do túnel no site
    ├── tools/iniciar-tudo.sh      sobe relay + túneis + registrador no celular
    ├── Dockerfile  fly.toml
    └── README.md
```

Regras:

- **Nada de web dentro de `src/`**: cenas e scripts do jogo continuam isolados.
- `.gdignore` faz o Godot ignorar `online/` inteiro, inclusive o build em
  `online/site/game/`; por isso o export não precisa ficar fora do repo.
- **Publish = `site`** com base `online` no Netlify, sem caminhos `..`.
- O build **não vai para o git**: publica-se com
  `netlify deploy --prod --dir site --functions netlify/functions --no-build`
  a partir de `online/`. Deploy por Git exigiria commitar o build ou criar uma
  Action que rode o export.
- O relay fica fora do Netlify, em `relay/`, e roda como processo próprio
  (Docker/Fly). `<relay>/.gdignore` impede o Godot de varrer `node_modules`.

## Como testar

Teste local do site antes do deploy, em dois terminais:

```bash
cd relay
npm install   # uma vez
npm start     # relay em http://127.0.0.1:9080
```

```bash
cd online
npm install -g netlify-cli              # uma vez
cd netlify/functions && npm install     # uma vez: instala @netlify/blobs
cd ../..
RELAY_URL=http://127.0.0.1:9080 netlify dev
```

`RELAY_URL` precisa ser **HTTP(S)**: a Function faz
`fetch("${url}/rooms")`. Sem ele **e** sem registro no Blob, `/api/salas`
responde `503` com `relay.online = false`. O `wss://` é o endereço usado pelo
**cliente do jogo**, não pelo proxy. Confira o relay em
`http://127.0.0.1:9080/healthz` e `/rooms`.

No `netlify dev` o store de blobs é uma cópia local isolada (não lê nem escreve
produção), então localmente o endereço vem sempre do `RELAY_URL`.

Depois do export no editor (`Projeto → Exportar → HTML5`), o jogo fica em
`online/site/game/` e responde em `http://localhost:8888/game/`.

## Decisões de produto recomendadas

1. **Código de sala curto** (6 caracteres, por exemplo `K7M2QX`) em vez de IP.
   O código é exibido ao criar a sala e pode virar link:
   `https://play.exemplo.com/?room=K7M2QX`.
2. **Um único endereço público de relay** (`wss://relay.exemplo.com`) embutido
   no build web. O jogador não digita IP no navegador; no desktop o campo de
   endereço continua disponível para LAN/relay próprio.
3. **Lobby público opcional**: uma página no Netlify lista salas abertas (host,
   modo, jogadores, status, criação/expiração). Entrar continua acontecendo no
   jogo, via WebSocket. A página só descobre a sala; não transporta a partida.
4. **Salas privadas por código** continuam possíveis mesmo sem aparecer no lobby.
5. **Não mostrar IPs** no lobby nem nos logs públicos. O relay é o ponto de
   contato; IPs ficam no provedor do relay.
6. **Salvar apenas dados públicos**: metadados de sala, resultado da partida,
   catálogo de decks e estatísticas. Nunca mãos, decks ocultos, envelopes de
   checkpoint ou tokens de sessão em texto claro.
7. **Modo LAN continua existindo** no desktop. No build web, o relay embutido e
   o endereço local devem ser escondidos/desativados.

## Plano por fases

### Fase 0 — Decisões e infraestrutura (0,5–1 dia)

- Escolher o provedor do relay. Free para começar: Cloudflare Workers com
  Durable Objects (WebSocket + SQLite, plano Free com limites diários) ou
  Fly.io/Render com TLS automático. O relay Node.js já está escrito para um
  processo sempre ligado (Fly/Render/VPS); Cloudflare Workers exigiria adaptar
  a hospedagem, sem mudar o protocolo JSON.
- Definir domínios: `play.exemplo.com` (Netlify) e `relay.exemplo.com` (relay).
- Definir o código de sala e o campo `protocol_version` no handshake.
- Confirmar que o jogo pode ficar público antes de a autoridade do servidor
  existir. Enquanto o host for autoritativo, o modo online é recreativo, não
  competitivo.
- Decidir se o lobby será público desde o início ou só por código.

Critério de aceite: domínios e provedor definidos, protocolo versionado e
decisão registrada neste documento.

**Status (30/10/2026): decidido e em operação.** O provedor inicial é o
**S20 FE (Termux) com túnel Cloudflare**, não Workers nem Fly. A razão é de
custo de migração: o relay Node já roda como processo sempre ligado e só
precisa de `wss://` na frente; Workers/Durable Objects exigiriam reescrever a
hospedagem, e Supabase/AWS serverless não sustentam WebSocket. O transporte é
`cloudflared tunnel --protocol http2 --url http://127.0.0.1:9080`
(`*.trycloudflare.com`, sem conta e sem domínio). Consequências aceitas por
enquanto: hostname efêmero, sem SLA e risco de Doze — ver a seção
“Celular (Termux + cloudflared)” em [relay/README.md](./relay/README.md).
Domínios próprios (`play.` / `relay.`) e túnel nomeado ficam para quando houver
contas externas. O site de produção está no Netlify (deploy manual da CLI,
`battle-scenes.netlify.app`); o `ssh -R 8888` só serve para testar o build local
pelo túnel.

### Fase 1 — Build web funcional (1–2 dias)

- Verificar os templates de exportação do Godot 3.4.4 e gerar o build HTML5 em
  `online/site/game/`. (feito localmente)
- Servir `online/site` em um servidor estático local antes do deploy. (feito com
  `netlify dev` e com um servidor estático de desenvolvimento)
- Ajustes de web necessários no código (feitos):
  - `WebSocketServer` não existe no HTML5. `LocalRelay.ensure_for_address()`
    retorna sem fazer nada com `OS.has_feature("web")`, então o relay embutido
    nunca sobe no navegador.
  - Endereço padrão de web (`Rede.WEB_DEFAULT_ADDRESS`, placeholder
    `wss://relay.exemplo.com`) separado do padrão LAN; `?relay=HOST` sobrepõe
    para desenvolvimento. O padrão web não é persistido como
    `127.0.0.1:9080` no IndexedDB.
  - O campo de endereço do relay é oculto no build web; o valor interno vem do
    deploy ou de `?relay=`. O status de servidor online/offline ainda não é
    consultado pelo cliente.
  - `user://` no navegador vira IndexedDB: decks, configurações e checkpoints
    ficam presos àquele navegador/origem. Avisar o jogador e prever
    exportar/importar saves.
  - Áudio e fullscreen dependem de gesto do usuário; validar o primeiro clique.
  - Verificar CORS das imagens do BSDB e da importação de decks. O jogo busca
    imagens por `HTTPRequest` em [src/core/CFControl.gd](./src/core/CFControl.gd);
    se o servidor de imagens não liberar CORS, usar um proxy/rewrite do Netlify
    para `/bsdb/*` ou um cache próprio.
  - Reduzir o filtro de exportação: o preset atual usa `all_resources` e inclui
    testes, addons e ferramentas. Excluir `tests/`, `addons/gut/` e `tools/`
    do pacote web e medir o tamanho final do `.pck`.
- Adicionar `netlify.toml` em `online/` com pasta de publicação e cabeçalhos
  (o arquivo já existe com o conteúdo abaixo). Exemplo:

```toml
[build]
  publish = "site"
  functions = "netlify/functions"

[[redirects]]
  from = "/api/salas"
  to = "/.netlify/functions/salas"
  status = 200

[[redirects]]
  from = "/api/relay"
  to = "/.netlify/functions/relay"
  status = 200

[[headers]]
  for = "/*"
  [headers.values]
    Referrer-Policy = "strict-origin-when-cross-origin"
    X-Content-Type-Options = "nosniff"
    Permissions-Policy = "fullscreen=(self)"

[[headers]]
  for = "/game/*.wasm"
  [headers.values]
    Content-Type = "application/wasm"
    Cache-Control = "public, max-age=0, must-revalidate"

[[headers]]
  for = "/game/*.pck"
  [headers.values]
    Content-Type = "application/octet-stream"
    Cache-Control = "public, max-age=0, must-revalidate"

[[headers]]
  for = "/game/index.html"
  [headers.values]
    Cache-Control = "no-cache"
```

O cache **não é** `immutable`: o shell do Godot 3.4 pede `index.pck` e
`index.wasm` sem query de versão e toda exportação reescreve esses nomes, então
quem já jogou ficaria preso ao pacote antigo. Com `must-revalidate` o navegador
confere o ETag (`304` quando nada mudou) e pega o build novo na hora.

- Não ativar threads no template web nesta etapa. Threads exigem
  `Cross-Origin-Opener-Policy`/`Cross-Origin-Embedder-Policy`, o que pode
  bloquear as imagens remotas do BSDB sem cabeçalhos CORP.
- Automação: para uso individual, exportar localmente e rodar
  `cd online && netlify deploy --prod --dir site --functions netlify/functions --no-build`.
  Para CI, criar um GitHub Action que baixa Godot 3.4.4 + templates, executa o
  export e publica; cachear os templates porque são grandes. O build em
  `online/site/game/` não é versionado.

Critério de aceite: jogo abre no navegador via HTTPS, multiplayer LAN
desabilitado no web sem erros, e uma partida local desktop continua funcionando.

### Fase 2 — Relay público com TLS (2–4 dias)

O `tools/ws_relay.py` atual é útil como referência, mas não deve ir para
produção como está: usa sockets crus, sem TLS, sem autenticação e sem limites
de abuso. A Opção A já está implementada em `relay/`; falta publicá-la. O
provedor escolhido na Fase 0 define a forma: Cloudflare Workers/Durable Objects
exige adaptar o relay à API de objetos duráveis; Fly.io/Render/VPS permite
manter Node + `ws`. As opções abaixo pressupõem um processo sempre ligado.

**Opção A (recomendada): relay Node.js com `ws` + `http`.**

- Manter o mesmo protocolo JSON e as mesmas mensagens de controle.
- Subir HTTP e WebSocket na mesma porta, atrás do TLS do provedor.
- Endpoints HTTP:
  - `GET /healthz` — status do processo, versão do protocolo e contagem de salas.
  - `GET /rooms` — lista sanitizada de salas públicas (sem IPs, sem tokens).
- Adicionar `join_room` com código curto, mantendo `find_match` para fila
  rápida e `rejoin_room` para reconexão.
- Adicionar `protocol_version` no handshake e recusar cliente incompatível com
  mensagem clara.
- Limites: tamanho máximo de frame (4 MiB, como hoje), máximo de salas por IP,
  máximo de conexões, heartbeat/ping-pong e timeout, rate limit por conexão.
- Validar `Origin` para o domínio do jogo; aceitar cliente desktop sem Origin
  apenas se o protocolo exigir. Em produção, considerar token de sessão curto.
- Sala em memória com expiração após os dois saírem (hoje 120 s) e limpeza
  periódica. Uma instância basta para a v1; escalar horizontalmente exigiria
  estado compartilhado (Redis) e não é necessário agora.
- Logs estruturados sem mãos/decks; métricas básicas (conexões, salas, erros).
- Testes automatizados com dois clientes `ws` reais cobrindo criar, entrar por
  código, sala cheia, código inválido, expiração, protocolo errado e reconexão.

**Opção B: manter Python atrás de um proxy TLS.** Possível com Caddy/nginx e
um processo sempre ligado, mas o relay atual precisaria de um servidor HTTP
separado para `/healthz` e `/rooms`, além de limites e logs. Só vale a pena se
já houver experiência operacional com Python.

Deploy sugerido:

- `Dockerfile` com `node:22-slim` (ou equivalente) e `CMD ["node", "src/server.js"]`.
- `fly.toml`/`render.yaml` com `internal_port` do relay, health check em
  `/healthz` e TLS automático.
- Uma única instância, região próxima dos jogadores.
- Segredo/allowlist e limites configuráveis por ambiente.
- Domínio `relay.exemplo.com` com `wss://` funcionando em navegador.

Critério de aceite: dois navegadores em redes diferentes criam/entram por
código, trocam mensagens e reconectam dentro da janela de tolerância; health
check responde; limites e protocolo inválido são recusados.

**Status:** a Opção A está implementada em [relay/](./relay/README.md), com
`join_room` por código, `hello`/`protocol`, `/healthz`, `/rooms`, limites,
heartbeat, allowlist de Origin, expiração e 21 testes com clientes `ws` reais.
O deploy saiu do papel em 30/10/2026, mas no celular: o relay roda no S20 FE
(Termux, Node v24, tmux `bs-relay`, porta 9080) atrás de um quick tunnel
Cloudflare, com `wss://` funcionando no navegador e `/healthz` respondendo pelo
hostname público. Dois navegadores abriram o jogo pelo túnel do site,
parearam por sala e jogaram sem erro de console.

Faltam para fechar o critério de aceite: o mesmo teste entre **redes
diferentes** (4G/fora do Wi-Fi), `rejoin_room` no meio de uma partida dentro da
janela de 120 s e recusa de terceiro jogador/código inválido pela URL pública. A
página de lobby já aponta para o relay publicado (via `/api/salas` +
auto-registro).

### Fase 3 — Lobby no Netlify (1–3 dias)

**Decidido: opção A, proxy do relay, sem storage.**

**A. Proxy do relay (decidida).**

- Netlify Function `GET /api/salas` chama `<endereço do relay>/rooms`
  no servidor e devolve uma lista sanitizada.
- Cache curto de 3 s para reduzir chamadas; se o relay estiver fora, devolver
  `503` com status offline **e a URL mesmo assim**, para o lobby continuar
  montando os links do jogo.
- Nenhum estado de sala é gravado no Netlify; o relay continua sendo a verdade.
- A Function está implementada em
  [online/netlify/functions/salas.mjs](./online/netlify/functions/salas.mjs) e
  lê o endereço por
  [online/netlify/lib/relay-url.mjs](./online/netlify/lib/relay-url.mjs):
  primeiro o registro no Blob (`POST /api/relay`, escrito pelo celular), com a
  variável de ambiente `RELAY_URL` (HTTP/HTTPS, sem `wss://`) como reserva.

**Registro do endereço (acrescentado em 30/10/2026).**

- `POST /api/relay` em
  [online/netlify/functions/relay.mjs](./online/netlify/functions/relay.mjs)
  aceita `{"url":"https://…"}` com o cabeçalho `x-relay-secret` igual ao
  `RELAY_REGISTER_SECRET` do site, valida `https:` e host contra
  `RELAY_HOST_PATTERN` (padrão `^[a-z0-9-]+\.trycloudflare\.com$`) e grava em
  `relay/address` no Blob `relay`, com consistência forte. `GET /api/relay`
  devolve `{ registered, url }` e nunca expõe o segredo.
- Essa Function é a única porta de escrita do Blob: sem segredo válido e host
  permitido, nada é gravado. O Blob não tem controle de acesso próprio.
- Quem chama é
  [relay/tools/register-relay.mjs](./relay/tools/register-relay.mjs), no celular,
  em sessão tmux própria (`bs-register`, modo `--watch` a cada 60 s): ele só
  publica quando o hostname do túnel difere do registrado e o `/healthz` local
  responde.

**B. Diretório em Netlify Blobs (adiada, só se precisar de histórico).**

- O relay registraria a sala via `POST`, e o Netlify guardaria `code`, `host`,
  `mode`, `status`, `players`, `created_at` e `expires_at`.
- **Não serve como trava de sala.** Blobs não tem controle de concorrência:
  a última escrita vence. Dois convidados clicando no mesmo link ao mesmo tempo
  poderiam ambos "entrar"; o claim atômico tem que ser do relay.
- **Não tem TTL nativo.** A expiração exigiria metadata + limpeza agendada
  (Scheduled Function), repetindo no Netlify o que o relay já faz em memória.
- **Consistência eventual por padrão** (propaga em até 60 s), então a lista
  poderia mostrar sala recém-criada como fechada ou vice-versa.
- Só compensa se o lobby precisar sobreviver a reinícios/restart do relay ou
  guardar histórico.

API mínima (exemplo):

```http
GET /api/salas
```

```json
{
  "rooms": [
    {
      "code": "K7M2QX",
      "host": "doug",
      "mode": "match",
      "players": 1,
      "status": "waiting",
      "created_at": "2026-10-26T18:12:00Z",
      "expires_at": ""
    }
  ],
  "relay": { "online": true, "version": "1.0.0" }
}
```

Observações sobre o formato real:

- `protocol` não vai por sala; ele aparece no topo de `GET /rooms` (junto de
  `version`) e em `GET /healthz`.
- `expires_at` hoje vem como string vazia: uma sala com o anfitrião conectado
  não expira. Só depois que os dois saem é que o relay aplica a janela de 120 s
  para `rejoin_room`, e nesse estado a sala não aparece no lobby.
- O lobby só lista salas `match` com o anfitrião conectado; salas de retomada
  (`resume`) são privadas e não aparecem.

Regras do lobby:

- Não devolver IP, porta interna, token de reconexão ou dados de cartas.
- A Function é somente leitura e não recebe parâmetros: não valida `code`,
  `username` ou `mode` nem aplica rate limit próprio. O relay valida esses
  campos nas mensagens WebSocket e aplica limites por IP/conexão.
- CORS restrito ao domínio do jogo (a página é mesma origem).
- Página `/salas` no Netlify com lista, atualização automática a cada 5 s,
  botão “Entrar” que abre `/game/?room=CODIGO` e botão “Copiar link”.
- Página inicial deve continuar funcionando sem lobby; se a API falhar, o jogo
  cria/entra por código normalmente.

**Por que o cliente não administra as salas.** A ideia de o jogo avisar a página
ao criar/entrar/fechar e apagar links órfãos não se sustenta como está:

- Página estática não guarda estado; precisaria de Blobs/Functions de qualquer
  forma, e aí o estado já não é do cliente.
- Cliente não pode ser autoridade de `DELETE`: qualquer um apagaria a sala de
  outro. Seria preciso token de dono, que o relay já teria de emitir.
- `beforeunload`/fechar aba não é confiável em navegador (celular, crash, rede);
  sempre sobra lixo que exige TTL no servidor.
- Claim de sala precisa ser atômico; Blobs é last-write-wins.

O relay já mantém a sala em memória e já tem a regra de 120 s após o último
jogador sair. O lobby só lê. Isso elimina CRUD, limpeza e corrida de entrada.

Critério de aceite: página lista salas reais, remove expiradas, não vaza IPs e
o link abre o jogo já com o código preenchido.

**Status:** Function `GET /api/salas`, página `/salas`, `POST/GET /api/relay` e
`netlify.toml` estão publicados em https://battle-scenes.netlify.app (deploy
manual da CLI). O endereço do relay vem do registro automático feito pelo
celular, com `RELAY_URL` como reserva, e o `/api/salas` o devolve para o lobby
anexar `?relay=` sozinho ao link do jogo; o cliente Godot segue lendo
`/game/?room=CODIGO` e preenchendo o código no menu. Validado em produção com
uma deriva proposital do endereço (lobby fora do ar até o registrador publicar o
hostname certo, em uma execução) e com sala real listada.

### Fase 4 — Integração no cliente (2–5 dias)

- Menu ([src/custom/MainMenu.gd](./src/custom/MainMenu.gd)):
  - Em web: esconder endereço do relay e mostrar “Servidor: online/offline”.
  - “Criar sala” passa a exibir o código e o link de convite.
  - “Entrar com código” para o convidado.
  - “Salas públicas” opcional, consumindo `/api/salas`.
  - Desktop mantém o campo de endereço para LAN e relay próprio.
- Rede ([src/custom/Rede.gd](./src/custom/Rede.gd)):
  - Adicionar `join_room` com código.
  - Definir padrão web `wss://` e nunca tentar `ws://` em página HTTPS
    (mixed content é bloqueado pelo navegador).
  - Garantir que o `LocalRelay` não seja acionado no web.
- Link profundo `?room=CODIGO`:
  - No build web, ler `window.location.search` via `JavaScript.eval` (guardado
    por `OS.has_feature("web")`) e preencher o campo de código.
  - No desktop, aceitar `--room=CODIGO` se for útil para testes.
- Reconexão: reutilizar `rejoin_room`; exibir o código e o status no HUD.
- Retomada: na v1 online, checkpoints continuam locais. Retomada entre
  dispositivos/navegadores exige checkpoints canônicos no servidor e está no
  roadmap do [MULTIPLAYER.md](./MULTIPLAYER.md), não nesta etapa.
- Avisar no menu que saves do navegador podem ser perdidos ao limpar dados do
  site e oferecer exportar/importar.

Critério de aceite: criar sala no navegador mostra código/link; outro navegador
entra pelo link; uma partida completa funciona; desktop LAN continua intacto.

**Status:** o essencial está implementado em 27/10/2026: `Rede.join_room`,
`Multiplayer.begin_join`, campo “Entrar com codigo” no menu, leitura de
`?room=CODIGO` e `?relay=HOST` via `JavaScript.eval`, padrão `wss://` no web
(`ws://` apenas para loopback), `LocalRelay` bloqueado no navegador e campo de
relay oculto. O código da sala já aparece no HUD de preparação. Faltam: status
“Servidor: online/offline” no menu, “Salas públicas” consumindo `/api/salas`,
link de convite copiável dentro do jogo e o aviso de saves no IndexedDB. O
essencial foi validado localmente com dois navegadores: criar sala, entrar por
código, decks 60/60, início da partida e tabuleiro espelhado. Falta validar em
redes diferentes depois de publicar.

### Fase 5 — Persistência, operação e segurança (contínuo, opcional)

- Netlify Blobs/DB **somente se** houver histórico/ranking:
  - resultados de partidas e estatísticas agregadas (sem mãos/decks);
  - catálogo de decks públicos, se for desejado;
  - retenção definida, remoção a pedido, política de privacidade.
- Não usar Blobs/DB para o lobby em tempo real (ver Fase 3). O único registro
  atual é o endereço do relay: uma chave, escrita por quem tem o segredo.
- Monitoramento: uptime do relay, health check, logs de Functions, alertas de
  erro; manter o relay e o jogo com versões/protocolo compatíveis. No celular,
  conferir também se as sessões tmux `bs-relay`, `cf-relay` e `bs-register`
  continuam vivas — sem o registrador o site perde o endereço quando o túnel
  reinicia.
- Custos: os 300 créditos/mês são consumidos principalmente pela banda do build
  (ver “Custos no plano Free”). Blobs/DB e Functions do lobby são residuais.
- Abuso: rate limit, limite de salas, tamanho de frame, Origin, timeout de
  inatividade e bloqueio de códigos inválidos.
- Autoridade: enquanto o host validar o estado, assumir que um cliente
  modificado pode trapacear. Não promover ranking competitivo antes das etapas
  de autoridade do roadmap.

## Segurança e privacidade

- Usar somente `wss://` no navegador; nunca `ws://` em página HTTPS.
- O relay não deve confiar em username como identidade. Para reconexão, emitir
  um token aleatório por jogador/sala e guardá-lo apenas em memória.
- Não registrar mãos, decks, envelopes de checkpoint ou conteúdo de mensagens
  privadas em logs.
- Limitar taxa e tamanho de mensagens; validar JSON e tipos no relay.
- Aplicar CORS restrito nas Functions; não expor o relay como proxy aberto.
- Não usar o relay embutido (`LocalRelay`) em produção web.
- Avisar que checkpoints locais no navegador são obfuscação, não criptografia,
  e que o modelo atual confia no host.

## Alternativas comparadas

| Opção | Prós | Contras |
|---|---|---|
| Netlify + relay dedicado (recomendada) | Usa o protocolo atual; controle do relay; CDN do Netlify; custo baixo | Mais um serviço para operar |
| Netlify + Supabase Realtime/Ably/Pusher | Sem operar relay; WebSocket gerenciado | Adaptar transporte/protocolo; limites e custo do fornecedor; dependência externa |
| Netlify apenas | Simples | **Não joga online**: não há WebSocket persistente nem host no navegador |
| VPS única (jogo + relay + banco) | Menos fornecedores | Gerir TLS, deploy e disponibilidade; perde a CDN pronta |
| Fly.io para tudo | Um provedor; relay e estático juntos | Menos conveniência de deploy/preview que o Netlify |

## Testes de aceite online

1. Dois navegadores em redes diferentes: criar sala, copiar link, entrar,
   escolher decks de 60 cartas, iniciar e completar uma rodada.
2. Confirmar que mão e deck do oponente continuam ocultos; lupa de zona e
   espelhamento funcionam.
3. Recarregar a aba no meio da partida e reconectar na mesma sala dentro da
   janela de tolerância; se não for possível, encerrar com mensagem clara.
4. Fechar um cliente e confirmar congelamento do outro, sem ações indevidas.
5. Testar código inválido, sala cheia, terceiro jogador, protocolo antigo e
   relay offline.
6. Verificar HTTPS/wss, sem erros de mixed content no console.
7. Confirmar que o lobby remove salas expiradas e não mostra IPs.
8. Repetir o fluxo LAN no desktop para garantir que nada regrediu.

## Perguntas em aberto

- ~~Provedor e região do relay; quem opera e paga.~~ Decidido em 30/10/2026:
  S20 FE do Douglas (Termux + túnel Cloudflare), sem custo; migração para um
  endereço permanente fica na v3 do TODO.
- Quando trocar o relay de endereço fixo, o registrador do celular é desligado e
  só o `RELAY_URL` passa a valer?
- Lobby público desde o início ou somente por código.
- Contas e ranking entram em qual versão.
- Quais estatísticas salvar e por quanto tempo (privacidade/LGPD).
- O jogo pode ser publicado enquanto o host ainda é autoritativo?
- O catálogo de decks do BSDB permite CORS ou precisará de proxy no Netlify?

## Próximos passos concretos

1. Guardas de web no `LocalRelay`, endereço padrão `wss://` e campo de relay
   oculto no build HTML5. (implementado)
2. PR: export HTML5 para `online/site/game/` + primeira publicação do
   `netlify.toml` + página `/salas` lendo o proxy. (publicado em 30/10/2026)
3. PR: relay público (Node/`ws`) com `join_room` por código, `/healthz` e
   `/rooms`, além dos testes de relay. (publicado no S20 FE em 30/10/2026)
4. Link `?room=` e entrada por código no menu do jogo. (implementado; falta
   “Salas públicas” no menu)
5. Auto-registro do endereço do relay: `POST /api/relay` + Blob +
   `register-relay.mjs` no celular. (implementado e validado em 30/10/2026)
6. Validação manual com dois navegadores **em redes diferentes** e atualização do
   [MULTIPLAYER.md](./MULTIPLAYER.md) e do [TODO.md](./TODO.md).
7. Só depois: endereço permanente para o relay (domínio + túnel nomeado ou
   Workers/Durable Objects) e Blobs/DB para histórico, se houver demanda.
