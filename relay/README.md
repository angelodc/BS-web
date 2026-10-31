# Relay online do Battle Scenes

Relay WebSocket de salas para partidas online, em Node.js + `ws`. Ele aplica o
plano da [Fase 2 do ONLINE_HOSTING.md](../ONLINE_HOSTING.md): mantém o mesmo
protocolo JSON do relay de desenvolvimento, adiciona entrada por código curto,
descoberta HTTP de salas e os limites necessários para ficar exposto na
internet.

O relay só forma salas e encaminha mensagens. A autoridade da partida continua
no anfitrião (cliente Godot); ele não valida jogadas.

## Estado

- Implementado: salas em memória, código de 6 caracteres, `join_room`,
  handshake de protocolo, `/healthz`, `/rooms`, limite de frame/conexões/salas
  por IP, rate limit, heartbeat, allowlist de Origin, expiração de 120 s e logs
  estruturados. A suíte tem 21 testes com clientes `ws` reais.
- Publicado no S20 FE (Termux + quick tunnel Cloudflare) desde 30/10/2026, com
  `wss://` e `/healthz` acessíveis de fora. É rota de teste: hostname
  efêmero, sem SLA. O `fly.toml` continua um modelo com `app`/`primary_region`
  de exemplo, para quando houver provedor fixo.
- O cliente Godot já envia `join_room` (menu “Entrar com código”), lê
  `?room=CODIGO` no build web e usa `wss://` por padrão. O desktop continua
  podendo usar o relay LAN embutido e o `tools/ws_relay.py`.
- O site está em produção em https://battle-scenes.netlify.app (deploy manual da
  CLI, sem Git CD). O endereço público do relay é **auto-registrado**: o celular
  publica o hostname do túnel em `POST /api/relay`, a Function grava em um Netlify
  Blob e o `/api/salas` devolve esse endereço, que o lobby anexa como `?relay=`
  no link do jogo. O `RELAY_URL` configurado no Netlify ficou só como reserva.
- Pendente: hospedar o relay em um endereço permanente (domínio na conta
  Cloudflare com túnel nomeado, ou Workers + Durable Objects — ver a Fase 4 do
  TODO), tirar o placeholder `wss://relay.exemplo.com` de
  [Rede.gd](../src/custom/Rede.gd) — ele só aparece quando a página é aberta sem
  `?relay=` — e validar dois navegadores em redes diferentes.
- Uma instância basta para a v1. Escalar horizontalmente exigiria estado
  compartilhado (Redis) e não está no escopo.

## Requisitos

- Node.js 20 ou superior (o Dockerfile usa 22).

## Rodar localmente

```bash
cd relay
npm install
npm start
```

Por padrão o relay escuta em `0.0.0.0:9080`, o mesmo endereço que o cliente
desktop usa (`ws://127.0.0.1:9080`). Para conferir:

```bash
curl http://127.0.0.1:9080/healthz
curl http://127.0.0.1:9080/rooms
```

## Testes

```bash
cd relay
npm test
```

A suíte usa clientes WebSocket reais e cobre criar sala, entrar por código,
sala cheia, código inválido, terceiro jogador, encaminhamento de mensagens,
reconexão, expiração, salas de retomada, protocolo incompatível, limites por IP,
rate limit e allowlist de Origin.

## HTTP

As duas rotas são somente leitura e não expõem IP, token ou conteúdo de cartas.

### `GET /healthz`

```json
{
  "status": "ok",
  "version": "1.0.0",
  "protocol": 1,
  "uptime_seconds": 42,
  "rooms": 3,
  "clients": 4,
  "grace_seconds": 120
}
```

### `GET /rooms`

Lista apenas salas de partida (`match`) com o anfitrião conectado. Salas de
retomada são privadas e ficam de fora. O formato alimenta diretamente o proxy
`GET /api/salas` do Netlify.

```json
{
  "version": "1.0.0",
  "protocol": 1,
  "rooms": [
    {
      "code": "K7M2QX",
      "host": "jogador",
      "mode": "match",
      "players": 1,
      "status": "waiting",
      "created_at": "2026-10-26T18:12:00.000Z",
      "expires_at": ""
    }
  ]
}
```

## Protocolo WebSocket

O transporte continua sendo um WebSocket com mensagens de texto JSON, cada uma
com o campo `t`. Ao conectar, o servidor envia:

```json
{ "t": "hello", "protocol": 1, "version": "1.0.0",
  "room_grace_seconds": 120, "heartbeat_seconds": 30 }
```

O cliente pode responder com `{ "t": "hello", "protocol": 1 }` (ou
`protocol_version`). Clientes antigos que não anunciam versão continuam
aceitos; uma versão declarada diferente de `1` recebe `error` com
`code: "protocol_mismatch"` e o socket é fechado com código 1002.

Mensagens de controle:

| `t` | Campos | Efeito |
|---|---|---|
| `create_room` | `username` | Cria sala e devolve `waiting` com `room_id` (o código). |
| `find_match` | `username` | Entra na primeira sala aberta ou espera um anfitrião. |
| `join_room` | `code`, `username` | Entra na sala do código. Erros: não encontrada, cheia, anfitrião ausente, username duplicado. |
| `cancel_match` | — | Sai da fila/sala ainda não pareada; responde `search_cancelled`. |
| `rejoin_room` | `room_id`, `username` | Reconecta em uma vaga da sala; responde `rejoin_ok` ou `rejoin_failed`. |
| `create_resume_room` | `game_id`, `username`, `participants` | Abre a sala de retomada de um save. |
| `join_resume_room` | `game_id`, `username`, `participants` | Entra na retomada por `game_id` (não por código). |
| `leave_room` | — | Fecha a sala e avisa o oponente com `opponent_left`. |

Respostas e avisos: `waiting`, `match_found`, `error`, `search_cancelled`,
`rejoin_ok`, `rejoin_failed`, `opponent_reconnected`, `opponent_left`,
`opponent_disconnected` (com `reconnectable` e `grace_seconds`).

Qualquer mensagem que não seja de controle é encaminhada ao oponente com os
campos `from` (`H`/`C`), `username` e `room_id`. O relay não interpreta o
conteúdo.

### Código de sala

O `room_id` das salas de partida é o código de 6 caracteres (`K7M2QX`), sorteado
sem letras ambíguas (`I`, `O`) nem `0`/`1`. Salas de retomada mantêm o
identificador `resume_<game_id>` para preservar a reconexão por save.

## Variáveis de ambiente

| Variável | Padrão | Descrição |
|---|---|---|
| `PORT` | `9080` | Porta HTTP/WebSocket interna. |
| `HOST` | `0.0.0.0` | Endereço de escuta. |
| `RELAY_VERSION` | `1.0.0` | Versão informada em `/healthz` e no `hello`. |
| `ALLOWED_ORIGINS` | vazio | Lista separada por vírgula de origens permitidas no upgrade. Vazio aceita qualquer origem (apenas para desenvolvimento). |
| `TRUST_PROXY` | `0` | Confia em `X-Forwarded-For` para limites por IP. Ative atrás do proxy do provedor. |
| `MAX_CONNECTIONS` | `500` | Conexões simultâneas. |
| `MAX_CONNECTIONS_PER_IP` | `10` | Conexões simultâneas por IP. |
| `MAX_ROOMS` | `200` | Salas em memória. |
| `MAX_ROOMS_PER_IP` | `3` | Salas criadas por IP. |
| `MESSAGE_RATE` | `40` | Mensagens por segundo por conexão. |
| `MESSAGE_BURST` | `120` | Rajada inicial de mensagens (cobre chunks de checkpoint). |
| `ROOM_GRACE_SECONDS` | `120` | Tempo para retomar depois que os dois saem. |
| `REAPER_INTERVAL_SECONDS` | `5` | Intervalo da limpeza de salas expiradas. |
| `HEARTBEAT_SECONDS` | `30` | Intervalo do ping/pong. |
| `LOG_LEVEL` | `info` | `info` ou `silent`. Os logs são JSON e não incluem IPs, mãos, decks nem conteúdo. |

O tamanho máximo de frame é 4 MiB, o mesmo do relay de desenvolvimento, para
acomodar envelopes de checkpoint.

## Deploy

### Fly.io

```bash
cd relay
fly launch --no-deploy          # ajuste app/primary_region no fly.toml
fly secrets set ALLOWED_ORIGINS=https://play.exemplo.com
fly deploy
```

O `fly.toml` aponta o health check para `/healthz`, força HTTPS e usa uma única
instância. O TLS do provedor termina a conexão; o cliente usa
`wss://relay.exemplo.com` e o processo escuta em HTTP/WS na porta interna.
Antes do primeiro deploy, troque `app` e `primary_region` no `fly.toml` (os
valores atuais, `bs-web-relay` e `gru`, são apenas um exemplo).

O lobby do Netlify precisa da URL **HTTP(S)** do relay em `RELAY_URL`
(`https://relay.exemplo.com`), porque a Function chama `GET /rooms`; o cliente
do jogo usa a mesma máquina com `wss://`. Com um provedor de hostname fixo o
registrador do celular deixa de ser necessário: basta `RELAY_URL` apontar para o
endereço permanente (ele é a reserva quando não há registro no Blob).

### Celular (Termux + cloudflared) — rota em uso hoje

O relay roda em um Samsung S20 FE (aarch64, sem root) servindo como servidor
sempre ligado. Não há mudança de código: `src/server.js` roda no Node nativo do
Termux (v24) e o TLS público vem de um túnel Cloudflare.

Decisões que só valem nesse ambiente:

- **Processo persistente mora no Termux, não no container.** `tmux` dentro de
  `proot-distro` morre junto com o processo `proot` que o iniciou. O relay e as
  sessões tmux rodam nativos no Termux; apenas binários glibc (o `cloudflared`)
  executam dentro do Debian 13.
- **Loopback é compartilhado** entre Termux e Debian: o túnel no container vê
  `127.0.0.1:9080` do relay nativo.
- **`--protocol http2` é obrigatório.** Com QUIC (padrão) o túnel nunca
  registrava e o handshake WebSocket devolvia erro 1033/530.
- **Não dá para listar portas.** `ss -ltn` e `netstat -ltn` retornam vazio no
  Termux e no Debian; a checagem é por sonda (`curl /healthz`).
- **Sem `TRUST_PROXY=1` o túnel colapsa todos os jogadores no IP `127.0.0.1`.**
  O relay vê o socket do `cloudflared`, não o do jogador, então os tetos por IP
  viram tetos globais: com `MAX_CONNECTIONS_PER_IP=10` e duas janelas já
  conectadas, a 9ª conexão pública recebeu `HTTP 503` e a 3ª sala do mesmo
  endereço recebeu “Você já tem salas abertas” — medido em 30/10/2026 pela URL
  pública. Confirmei no mesmo aparelho que o `cloudflared` repassa
  `x-forwarded-for` (com o IP real) tanto em GET quanto no upgrade de
  WebSocket, inclusive com `--protocol http2`. Portanto **publique com
  `TRUST_PROXY=1`** quando o túnel for a frente do relay; atrás dele o cabeçalho
  é escrito pela Cloudflare e não é forjável. Clientes desktop sem `X-Forwarded-For`
  caem no endereço do socket e continuam funcionando em LAN.

Layout no aparelho:

```text
~/projetos/bs-relay/
├── package.json  src/  test/   copiado do repo (LF preservado)
├── node_modules/               npm install dentro do Termux
├── iniciar-tudo.sh             sobe relay + tuneis + registrador, idempotente
├── register-relay.mjs          publica o hostname do tunel no site
├── relay.log  cf-relay.log  registrar.log  boot.log
~/.bs-relay-secret              segredo do registro (modo 600, fora do repo)
~/.termux/boot/bs-relay.sh      Termux:Boot: wake-lock + sshd + iniciar-tudo
```

Sessões tmux: `bs-relay` (Node na 9080), `cf-relay` (túnel do relay),
`bs-register` (registrador em modo `--watch`) e `cf-site` (túnel do site, só para
testar o build local quando a 8888 está alcançável por `ssh -R 8888:localhost:8888`;
a produção é o Netlify).

```bash
ssh <alias-do-celular>                        # alias do Termux no seu ~/.ssh/config
tmux attach -t bs-relay
bash ~/projetos/bs-relay/iniciar-tudo.sh      # idempotente
curl -sS http://127.0.0.1:9080/healthz
curl -sS https://battle-scenes.netlify.app/api/relay
```

### Auto-registro do endereço público

O quick tunnel troca de hostname a cada reinício, então o endereço não é
configurado à mão em lugar nenhum: `register-relay.mjs` faz o caminho inteiro.

1. Lê o último host `*.trycloudflare.com` do `cf-relay.log` (o túnel imprime a URL
   ao registrar).
2. Compara com o que o site já tem em `GET /api/relay`; se for igual, não faz nada.
3. Confere o relay local com `GET http://127.0.0.1:9080/healthz` — endereço de um
   relay morto não é publicado.
4. Publica `POST /api/relay` com o corpo `{"url":"https://<host>"}` e o cabeçalho
   `x-relay-secret` lido de `~/.bs-relay-secret`.

Do lado do site, a Function [`relay`](../online/netlify/functions/relay.mjs)
exige o segredo (`RELAY_REGISTER_SECRET`, definido no Netlify e nunca impresso),
aceita apenas `https:` e host dentro da allowlist
(`RELAY_HOST_PATTERN`, padrão `^[a-z0-9-]+\.trycloudflare\.com$`) e grava em
`relay/address` no Netlify Blobs com consistência forte. `GET /api/relay` devolve
`{ "registered": true, "url": "…" }` e cai no `RELAY_URL` do ambiente quando não
há registro — útil antes do primeiro registro ou se o registrador parar.

```bash
node register-relay.mjs               # uma sincronização; exit 0 se publicou ou já batia
node register-relay.mjs --watch       # repete a cada INTERVAL_MS (padrão 60 s)
```

| Variável | Padrão | Descrição |
|---|---|---|
| `SITE` | `https://battle-scenes.netlify.app` | Site que recebe o registro. |
| `TUNNEL_LOG` | `~/projetos/bs-relay/cf-relay.log` | Log do `cloudflared` onde está o hostname. |
| `HEALTH_URL` | `http://127.0.0.1:9080/healthz` | Sonda local antes de publicar. |
| `RELAY_SECRET_FILE` | `~/.bs-relay-secret` | Arquivo com o segredo do `x-relay-secret`. |
| `INTERVAL_MS` | `60000` | Intervalo do modo `--watch`. |

O script não tem dependências (só `node:` nativo) e roda tanto no Termux quanto
no desktop. Trocar o segredo é `netlify env:set RELAY_REGISTER_SECRET …` seguido
da gravação do mesmo valor em `~/.bs-relay-secret`.

O player abre o site em https://battle-scenes.netlify.app e clica em “Abrir o
jogo”; o lobby já monta o link com
`?relay=<relay>.trycloudflare.com`. Um link direto para `/game/` continua
funcionando, mas precisa desse parâmetro, porque o padrão web em
`Rede.WEB_DEFAULT_ADDRESS` ainda é placeholder.

Limites dessa rota: o hostname `*.trycloudflare.com` **muda a cada reinício do
túnel** — o registrador cobre isso em até um minuto, mas nada mais funciona se a
sessão `bs-register` morrer; o quick tunnel não tem SLA e o Android pode matar o
processo em Doze (`termux-wake-lock` atenua, não resolve). Um hostname fixo exige
um domínio na conta Cloudflare e `cloudflared tunnel --config` com túnel nomeado.
Reiniciar o celular hoje só recupera os serviços se o APK **Termux:Boot** estiver
instalado na mesma fonte do Termux (o hook já está escrito em `~/.termux/boot/`).
Para produção estável, a rota continua sendo Fly.io/Docker acima ou a migração
para Workers + Durable Objects (v3 no TODO).

### Docker

```bash
cd relay
docker build -t bs-web-relay .
docker run --rm -p 9080:9080 -e ALLOWED_ORIGINS=https://play.exemplo.com bs-web-relay
```

Para o navegador, use sempre `wss://` em página HTTPS. Clientes desktop sem
cabeçalho `Origin` continuam aceitos para LAN/relay próprio.

## Limites e segurança

- Estado só em memória: reiniciar o relay derruba as salas abertas.
- A sala expira 120 s depois que **os dois** jogadores saíram; enquanto um
  estiver conectado ela é preservada para permitir retomada longa.
- O username não é identidade: a reconexão casa username + vaga vazia. Tokens de
  sessão por jogador ficam no roadmap da Fase 5.
- O relay não valida jogadas. Enquanto o host for autoritativo, o modo online é
  recreativo.
- Não registre mãos, decks ou conteúdo de mensagens; os logs atuais trazem só
  eventos e códigos de sala.
