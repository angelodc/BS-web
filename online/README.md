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
- O export HTML5 está configurado e o build local foi gerado em `site/game/`
  (ignorado pelo Git); ele já foi validado com dois navegadores, mas ainda não
  foi publicado.
- O cliente web já tem `join_room` por código, entrada “Entrar com código” no
  menu, leitura de `?room=CODIGO` e `?relay=HOST`, padrão `wss://` e
  `LocalRelay` desativado no navegador. Falta publicar e validar em redes
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
npm install -g netlify-cli   # uma vez
RELAY_URL=http://127.0.0.1:9080 netlify dev
```

Jogo em `http://localhost:8888/game/` (depois do export) e lobby em
`http://localhost:8888/` (funciona sem o export).

A Function lê `RELAY_URL` **HTTP(S)** (sem barra final), por exemplo
`https://relay.exemplo.com`. Não use `wss://` aqui: o proxy faz
`fetch("${RELAY_URL}/rooms")`. O `wss://` é o endereço usado pelo cliente do
jogo. Sem a variável, `/api/salas` responde 503 com `relay.online = false`.

Para testar o jogo web contra o relay local, abra
`http://localhost:8888/game/?relay=127.0.0.1:9080` (endereços locais usam `ws://`);
sem `?relay=`, o cliente usa o endereço público `wss://`.

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
