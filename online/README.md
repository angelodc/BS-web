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

## Exportar o jogo

No editor: **Projeto → Exportar → HTML5**. A saída configurada é
`online/site/game/index.html`.

## Testar localmente

```bash
cd online
npm install -g netlify-cli   # uma vez
netlify dev
```

Jogo em `http://localhost:8888/game/` e lobby em `http://localhost:8888/`.

A Function lê `RELAY_URL` (sem barra final), por exemplo
`wss://relay.exemplo.com`. Sem a variável, `/api/salas` responde 503 com
`relay.online = false`.

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
