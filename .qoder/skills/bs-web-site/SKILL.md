---
name: bs-web-site
description: Sobe e para o relay Node.js e o site local do BS-web para testar o jogo exportado no navegador. Use ao validar o build HTML5, o lobby Netlify ou o multiplayer web; inicia os servidores em segundo plano, confere as portas e informa as URLs com ?relay=.
---

# Subir relay e site do BS-web

Sobe o relay de salas (`relay/`) e o site local (`online/`) para testar o jogo
HTML5 no navegador, sem depender do editor Godot.

## Pré-requisitos

- Node.js 20+ e `curl` no PATH.
- Build HTML5 em `online/site/`. O script aceita as duas disposições:
  - `online/site/index.pck` — jogo na raiz (`/`), layout atual do preset;
  - `online/site/game/index.pck` — jogo em `/game/` e lobby na raiz.
- Sem build, o site sobe mas o jogo responde 404. Para gerar, veja
  [ONLINE_HOSTING.md](../../../ONLINE_HOSTING.md) e
  [online/README.md](../../../online/README.md).

## Uso

```bash
bash .qoder/skills/bs-web-site/scripts/start-local.sh both
```

Modos: `both` (padrão), `relay`, `site`, `status`, `stop`.

Variáveis:

- `SITE_MODE=netlify` (padrão) sobe `netlify dev --offline` na pasta `online/`,
  o que também disponibiliza `/api/salas`. A primeira execução baixa o
  `netlify-cli` via `npx --yes` e demora.
- `SITE_MODE=static` (ou `serve`) usa `scripts/serve-static.js`, um servidor
  sem dependências com MIME correto para `.wasm`/`.pck`. O jogo funciona, mas
  a Function do lobby não existe.
- `RELAY_PORT` (padrão `9080`) e `SITE_PORT` (padrão `8888`).

O relay escuta só em `127.0.0.1`. O script instala `relay/node_modules` se
faltar, grava PIDs e logs em `.qoder/skills/bs-web-site/.run/` e só encerra
processos que ele mesmo iniciou.

## URLs

O script imprime o caminho correto do jogo. Em geral:

```text
http://localhost:8888/?relay=127.0.0.1:9080        # build na raiz (ou lobby)
http://localhost:8888/game/?relay=127.0.0.1:9080   # build em /game/
```

Com o build em `/game/`, abra o lobby com `?relay=`: os links "Abrir o jogo"
e "Entrar" repassam o parâmetro para o jogo. Sem ele, o cliente web usa
`Rede.WEB_DEFAULT_ADDRESS` (placeholder `wss://`) e a conexão falha.

O `?relay=` é necessário porque o padrão web em `Rede.WEB_DEFAULT_ADDRESS` é
um placeholder `wss://`; endereços locais usam `ws://` automaticamente. O
código de sala pode ser passado junto: `&room=CODIGO`.

Abra duas janelas/anônimas com usernames diferentes para testar a partida.
Não abra o `index.html` por `file://`; `.wasm`/`.pck` exigem HTTP.

## Verificação

```bash
curl -fsS http://127.0.0.1:9080/healthz
curl -fsS http://127.0.0.1:8888/api/salas   # SITE_MODE=netlify
```

`/api/salas` depende do redirect em `online/netlify.toml` para
`/.netlify/functions/salas`; sem ele o caminho devolve 404.

`status` mostra PIDs e se cada serviço responde. `stop` encerra apenas os PIDs
registrados (primeiro com `kill`, depois `taskkill /T` se algo sobrar); se uma
porta estiver ocupada por outro processo, avisa e não mata nada.

## Diagnóstico

- `.run/relay-9080.log`, `.run/site-8888.log` — saída de cada serviço (nome
  inclui a porta).
- `relay: porta ocupada` — há outro processo na 9080; encerre-o você mesmo.
- `netlify dev` não sobe — veja o log; ele cria `online/.gitignore` com
  `.netlify` na primeira execução.

## Limitações

- `netlify dev --offline` não publica nada; é só servidor local.
- O build é gerado fora do git. `online/site/game/` é ignorado; um export na
  raiz de `online/site/` aparece como não rastreado e sobrescreve o
  `index.html` do lobby.
