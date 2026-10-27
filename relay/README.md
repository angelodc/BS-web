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
  estruturados.
- Pendente (Fase 4): o cliente Godot ainda não envia `join_room` nem lê
  `?room=CODIGO`. Até lá, o desktop continua usando o relay LAN embutido e o
  `tools/ws_relay.py`.
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
      "host": "doug",
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
