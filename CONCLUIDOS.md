# 🦸‍♂️ Battle Scenes Web — Planejado e entregue

> Histórico do que foi planejado e concluído. O que falta está em
> [TODO.md](./TODO.md); o que ainda precisa de decisão está em
> [PLANEJAMENTO.md](./PLANEJAMENTO.md).

---

## ⚙️ Base, engine e imagens

- Fork do `db0/godot-card-game-framework`, com o tabuleiro do Battle Scenes em
  `src/custom/`.
- Resolução lógica `1280x720`, `CARD_SIZE` `150x210`, escala de campo `0,55` e
  escala da mão `0,5` ([CFConst.gd](./src/custom/CFConst.gd)).
- Cartas baixadas da CDN do BSDB por `HTTPRequest`, com cache em
  `user://CardImages/`; a Godot não guarda imagem de carta no projeto.
- Importação de deck por link (`https://battlescenes.vercel.app/deck/...`):
  baixa a lista, os dados e as imagens e salva no catálogo local.
- Migração para **Godot 4.7.2 / GDScript 4.x** na branch `migracao`
  (`config/features=PackedStringArray("4.7")`). Menu, preparação, partida solo,
  Recursos, anexos e troca de assento validados em headless.
- **GUT 9.7.1** trazido de volta em 2026-11-02 (commit `db08021`); workflows
  do GitHub Actions já baixam o Godot 4.7.2.

## 🃏 Fase 1 — mecânicas do Battle Scenes

- **Campo de três faixas:** oponente no topo, duas linhas do jogador no meio e
  Mão embaixo. Oponente espelhado, cartas públicas viradas 180°.
- **Grade da Cena dinâmica:** 7 colunas × 2 linhas autoradas na cena (mínimo de
  2), com zonas espelhadas do oponente, botões **Ver** para Recursos e Prêmios
  remotos e arraste das cartas de Cena/Cenário do oponente.
- **Cenário único ativo:** um novo Cenário envia o anterior a
  Recursos/Descarte; o perdedor vai para o descarte do dono.
- **Prêmios:** uma carta por jogador (`120x168`, escala `0,8`), rótulo
  `Energia` somando `ENERGIA`; 15 encerram a partida com a sobreposição de
  vitória.
- **Capacitação pelo menu de hover:** `-90°`/`0°`/`+90°`, ação oposta nas
  posições inclinadas e **Escudo** para Personagens.
- **Deck e Mão:** compra por clique, embaralhar, Clarividência e Procurar;
  mão sem limite; duplo clique envia para Recursos/Descarte e **Ver** abre a
  pilha.
- **Entrada em Cena:** exige `ENERGIA`, abre Recursos automaticamente, permite
  escolher anexos por clique e cancela devolvendo a carta à Mão.
- **Anexos:** empilhados com 5% da borda inferior visível; não giram com a
  carta principal; botão **Trocar** em Recursos/Descarte.
- **Dano, nocaute e vitória:** cada dano retira um anexo para o descarte do
  dono; zerar as energias devolve anexos e manda o Personagem aos Prêmios do
  adversário; a soma `ENERGIA` dos Prêmios dispara a vitória. Coberto por
  `tests/integration/test_damage_knockout.gd` (6/6).
- **Registro de ações:** autoload `GameEvents` alimenta o log do HUD com nomes
  clicáveis que abrem a prévia da carta (em memória, sem disco).
- **Fases e turnos:** `REG` → `PREP` → `ADJ` → `ANT` → `ATK`, com d6, rodada e
  destaque de etapa no `MatchHUD`.
- **Partida solo P1 vs P2 (hotseat):** entrada no menu, um deck por assento,
  assento inativo guardado em `_solo_hidden`, botão **Controlar P1/P2** e
  restauração por checkpoint. O bug do terceiro swap foi corrigido e coberto
  por GUT.
- A regra de “1 recurso por turno” foi removida do escopo.

## 🌐 Multiplayer e hospedagem

- **LAN:** username e busca de partida; relay embutido sobe em `0.0.0.0:9080`
  no primeiro cliente que cria/procura sala; `tools/ws_relay.py` como relay
  externo.
- **Relay online em Node.js (`relay/`):** mesmo protocolo JSON, `join_room` por
  código, `hello`/`protocol_version`, `/healthz`, `/rooms`, limites por
  IP/conexão, heartbeat e allowlist de `Origin`; 25 testes com clientes `ws`
  reais.
- **JWT do Supabase no relay (2026-11-02):** as mensagens de controle aceitam
  `token`; o relay valida pelo JWKS (`iss`/`aud`, ES256/RS256) e usa o `sub`
  como identidade. A mesma conta não ocupa os dois assentos e a reconexão
  procura o assento pelo `sub` antes do username. Sem token válido a partida
  segue anônima, como antes; `SUPABASE_URL` vazio desliga a validação. Publicado
  na VM Oracle em 02/11/2026; o `/healthz` mostra `auth: true`.
- **Produção do relay:** S20 FE + túnel Cloudflare em 30/10/2026; desde
  01/11/2026 roda na VM Always Free da Oracle em Frankfurt, com IP público
  reservado `129.159.222.25`, TLS do Caddy em `129-159-222-25.sslip.io` e
  `TRUST_PROXY=1`. O hostname fixo resolveu a rotação de endereço.
- **Espelhamento:** arrasto, rotação, cartas ocultas, recados (“Comprou
  carta”), Recursos públicos, movimentos do oponente e lupa pulsando na zona
  remota sem revelar posição/conteúdo.
- **Paridade da banda de cena:** slot espelhado por rect, carta solta refletida
  pelo centro da mesa, restauração de slot/rotação/anexos ao voltar de assento;
  coberto por `tests/integration/test_solo_hotseat.gd`.
- **Reconexão automática:** backoff `2 → 5 → 10 → 20 → 40 s` em
  `Multiplayer.gd`, encerrando no rejoin/fim de sessão; 9 testes.
- **“Servidor: online / indisponível”** no menu, com sonda no `/api/salas` na
  web e `/healthz` no desktop; 6 testes.
- **Netlify:** `https://battle-scenes.netlify.app` publicado em 30/10/2026
  (deploy `6ae4f75944d360a9d0f5f8f3`, `index.pck` de 7,8 MB), deploy manual da
  CLI, projeto público com previews protegidos; `/api/salas` e `/api/relay`
  no ar; Blob `relay/address` vazio e `RELAY_URL` como fonte do endereço.

## 📈 Analytics e login (2026-11-02)

- **GA4 enxuto (`online/site/analytics.js`):** consent mode v2, banner com
  Aceitar/Recusar e link **Cookies**, gtag só depois do aceite, fila de eventos
  antes da escolha e `user_id` restrito ao UUID do Supabase. O autoload
  `Analytics.gd` envia `game_open` uma vez com `canvas_w/h`, `window_w/h`, `dpr`
  e `mode`. Enquanto `MEASUREMENT_ID` estiver vazio, tudo fica inerte.
- **Login Google opcional (`online/site/auth.js` + `Auth.gd`):** PKCE via
  Supabase Auth no lobby, sessão enxuta em `bs_auth_session`, refresh silencioso
  ao voltar com a cópia vencida e logout local. O jogo lê token/UUID pelo
  `JavaScriptBridge` e envia o token nas mensagens de controle. Sem sessão, solo
  e multiplayer continuam por username.
- **Ativado no console (04/11/2026):** GA4 `G-Z4YHVSLCRL` preenchido em
  `analytics.js`; projeto Supabase **battle-scenes** (`ulchgvwidctalaaxugeg`,
  São Paulo) criado só para Auth, com provedor Google habilitado, Site URL e
  Redirect URLs (`netlify.app`, `localhost:8080`, `localhost:8888`); OAuth Client
  `Battle Scenes Login` em Google Cloud com o callback do projeto. Validado no
  navegador: login → `bs_auth_session` com UUID → `user_id` do GA4 igual ao UUID
  → relay local aceita o JWT e rejeita token forjado. Falta só o próximo export
  web para o `head_include` chegar ao jogo e o deploy de `online/site`.
- **Dois Supabases convivem:** o projeto novo é só Auth/login; os dados de deck
  do editor (`BSDBDeckImportDialog.gd`) continuam no projeto antigo
  (`xtdqcfchdqmqlbmkvdit`), que não tem acesso pela conta atual.

## 🧭 Fase 5 — layout autoral do tabuleiro

- **Etapas 0–5 entregues** ([BOARD_LAYOUT.md](./BOARD_LAYOUT.md)): dump de
  medição, valores gravados em coordenadas absolutas na cena, runtime burro
  (posições autorais lidas uma vez), `bottom_margin` da mão virou `export`,
  guarda de divergência do `OpponentScene` atrás do checkbox **Debug** e
  limpeza.
- As ~165 linhas de layout de `CGFBoard.gd` viraram ~20; o deck continua
  deitado a 270° e mantém a área atual.
- **Rota B (2026-11-02):** a cena passou a ser a fonte da verdade — grid 7×2,
  cenário, legenda e giro do deck assados em `CGFBoard.tscn`; o runtime só
  sincroniza o `OpponentScene` com o grid, chama `configure_width()` com a
  largura autoral e refaz o leque da mão. F6 mostra o mesmo campo que o F5, e
  alargar o grid no editor alarga o campo em jogo.
- **Resolução (2026-11-02):** o tabuleiro e a prévia renderizam em **HD+
  1600×900 na web**; no desktop o menu oferece **HD 1280×720** (padrão) e
  **Full HD 1920×1080**. As coordenadas de design continuam 1280×720 via
  `size_2d_override` (`src/custom/RenderResolution.gd` + `DisplayMode`).

## 🕹️ Turno automático (branch `autoTurno`)

- **Regra pura do turno** em `src/custom/TurnRules.gd`: mulligan automático e
  manual, Contagem Regressiva, Compra, Ajuste e deck vazio, sem depender de cena
  ou rede. Coberta por `tests/unit/test_turn_rules.gd` (24 testes).
- **Mulligan automático em partida:** a mão com menos de dois Personagens volta
  ao deck e é recomprada, com log, no assento local e no oculto do hotseat.
  Embaralhamento semeado por `seed + "|mulliganN"` e guarda de 50 repetições.
- **Mulligan manual** exposto como API (`manual_mulligan_local`,
  `get_mulligan_info`): mão `10→8→6→4→2→0`, dois cards por repetição para
  Recursos/Descarte e os recursos antigos preservados. Coberto por
  `tests/integration/test_auto_mulligan.gd` (7 testes).
- Plano e decisões de regra em [AUTOTURNO.md](./AUTOTURNO.md).

## 🩹 Correções entregues

- Sinais duplicados em `CGFDiscard`/`CGFPrizes` (10 erros de `Signal already
  connected` no arranque da mesa no 3.4).
- Rolagem do log no HUD usando `get_line_count()` no lugar de
  `get_paragraph_count()`.
- Prévia das cartas espelhadas e do log: hover com `preview_locked` e escolha de
  uma cópia legível; foco registrado antes do laço de visibilidade.
- Terceiro swap no solo esvaziando os dois campos.
- Caminho da fonte Comfortaa nas duas cenas do tabuleiro.

## 📦 Publicação

- Preset `Web` com saída em `online/site/game/index.html`, incluindo
  `data/decks/*.json` e excluindo `addons/gut`, `tests/`, `tutorial/`,
  screenshots do README e artes de playmat/vibe_images.
- Regra de publicação: acumular mudanças de cliente e subir uma vez quando
  houver algo que pague a rebaixa do `.pck`; relay e Functions podem subir sem
  reexportar o jogo.
