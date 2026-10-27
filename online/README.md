# online/

Pasta de web/deploy do Battle Scenes. O Godot ignora esta pasta por causa do
`.gdignore`; nada aqui é cena ou script do jogo.

```text
online/
├── netlify.toml          base do site Netlify = online, publish = site
├── netlify/functions/    API HTTP do lobby (proxy, sem storage)
├── site/
│   ├── index.html        página /salas
│   └── game/             export HTML5 (gerado, não versionado)
└── README.md
```

## Estado

- A Function `/api/salas` e a página `/salas` estão prontas para uso local.
- O export HTML5 está configurado, mas o build em `site/game/` ainda não foi
  gerado nem publicado.
- O cliente web ainda não tem `join_room` nem leitura de `?room=CODIGO`
  (Fase 4 do [ONLINE_HOSTING.md](../ONLINE_HOSTING.md)).

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
npm install -g netlify-cli   # uma vez
RELAY_URL=http://127.0.0.1:9080 netlify dev
```

Jogo em `http://localhost:8888/game/` (depois do export) e lobby em
`http://localhost:8888/` (funciona sem o export).

A Function lê `RELAY_URL` **HTTP(S)** (sem barra final), por exemplo
`https://relay.exemplo.com`. Não use `wss://` aqui: o proxy faz
`fetch("${RELAY_URL}/rooms")`. O `wss://` é o endereço usado pelo cliente do
jogo, que ainda será integrado na Fase 4. Sem a variável, `/api/salas` responde
503 com `relay.online = false`.

## Publicar

```bash
cd online
netlify deploy --prod
```

O build não vai para o git. Deploy por Git exigiria commitar
`site/game/` ou criar uma Action que rode o export do Godot.

## Relay

O relay de produção fica em [../relay/](../relay/README.md) (Node.js + `ws`),
fora do Netlify. Ele é a fonte de verdade das salas; o lobby aqui só consulta
`GET /rooms`.

## Escopo

- O lobby só lê `GET /rooms` do relay; não guarda sala, não cria TTL e não faz
  claim de entrada.
- Blobs/DB ficam reservados para histórico/ranking, se um dia houver.
- Detalhes e fases: [../ONLINE_HOSTING.md](../ONLINE_HOSTING.md).
