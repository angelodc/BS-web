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
  IP/conexão, heartbeat e allowlist de `Origin`; 21 testes com clientes `ws`
  reais.
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
