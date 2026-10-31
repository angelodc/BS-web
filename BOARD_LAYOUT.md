# Planejamento do Layout do Tabuleiro

Este documento registra o plano para tornar `src/custom/CGFBoard.tscn` editável na vista 2D do editor do Godot do mesmo jeito que `src/custom/MainMenu.tscn` já é, em vez de depender da leitura de números dentro do código. As decisões confirmadas estão em [Decisões](#decisões-confirmadas) e o passo a passo em [Plano](#plano-em-etapas).

## Objetivo

Abrir `CGFBoard.tscn` no editor, ver o campo como ele renderiza e arrastar as caixas no layout. Hoje isso não funciona para o tabuleiro, e o motivo é concreto.

## Diagnóstico

- Os nós do lado oponente **já têm rects autorais** na cena: `OpponentFieldVisual` e seus filhos (`ColorRect` de fundo, cenário, prêmios, recursos, deck, mão, mais os Labels e botões) estão gravados com `margin_*` e `anchor_*` normais em [src/custom/CGFBoard.tscn:338](./src/custom/CGFBoard.tscn). Eles aparecem na vista 2D.
- Em runtime, `_layout_opponent_field()` recalcula e **sobrescreve** cada um desses rects ([src/custom/CGFBoard.gd:166](./src/custom/CGFBoard.gd)), e o lado local inteiro é posicionado por código ([src/custom/CGFBoard.gd:91](./src/custom/CGFBoard.gd)) com cerca de 30 literais. As duas funções somam ~165 linhas.
- Há um segundo sobrescritor fora dessas funções: `_update_remote_resources()` devolvia `OpponentResourcesBackground.rect_size.x` ao literal `156.0` toda vez que o mouse saía da caixa ([src/custom/MultiplayerSync.gd](./src/custom/MultiplayerSync.gd)). Sem tratá-lo, o primeiro hover apagava qualquer largura autoral. Hoje a caixa não muda de largura: o grid espelhado escala a partir da largura autoral (ver Etapa 2).
- A cena já mudou desde a primeira versão deste plano: o `Deck` passou a `card_size = 150x210`, `card_display_scale = 0.66` e `show_manipulation_buttons = false`, com o `VBoxContainer` interno oculto. A medição da etapa 0 precisa ser feita **neste estado**, que é o render aprovado.
- Os valores gravados na cena ficaram **defasados** do que o código calcula. Exemplo: `OpponentHandBackground` tem `margin_right = 772` no arquivo, mas o código usa `grid_x = (1280 - scene_size.x) / 2` com largura de grid ≈ 672, o que daria ≈ 976. O que o editor mostra é um bake antigo.

Consequência: editar à mão hoje significa caçar constante dentro de duas funções, e a vista 2D do editor mente sobre o resultado.

## Decisões confirmadas

| # | Decisão | Escolha |
|---|---|---|
| a | Largura do `PlacementGridDemo` | **Padrão atual**: continua calculada por `configure_width()` e centralizada; o grid não é arrastado no editor. |
| b | Como gravar as posições no `.tscn` | **Coordenadas absolutas**: remover `anchor_left/right = 1.0` e as margens negativas da coluna direita. Com `window/stretch/mode="2d"` e `aspect="keep"`, a resolução de design é sempre 1280×720, então as âncoras não ganham nada e o Inspector fica legível ao arrastar. |
| c | Dump de medição de rects | **Temporário**, removido antes da entrega. |
| d | Rotação e área do deck | **Como está**: o monte continua deitado a 270° e a área do deck atual é preservada. A rotação segue reafirmada em código; só posição e tamanho vão para a cena. A pendência antiga de "monte em pé" está cancelada. |

## Classificação dos nós

| Grupo | Nós | Destino |
|---|---|---|
| Decorativos do lado oponente | `OpponentFieldBackground`, `OpponentHandBackground`, `OpponentHandLabel`, `OpponentResourcesBackground`, `OpponentResourcesLabel`, `OpponentResourcesView`, `OpponentPrizes`, `OpponentPrizesLabel`, `OpponentPrizesView`, `OpponentPrizesEnergy`, `OpponentScenario`, `OpponentScenarioLabel`, `OpponentDeck`, `OpponentDeckLabel`, `OpponentFieldLabel`, `OpponentSceneLabel` e `OpponentFieldVisual.margin_bottom` | **Autorais** (arrastar no editor) |
| Geometria crítica | `OpponentScene` | **Continua derivado do grid.** Três consumidores leem esse rect: `_mirrored_slot_rect()` ([src/custom/MultiplayerSync.gd:1303](./src/custom/MultiplayerSync.gd)) e `_mirror_slot_at()` ([:530](./src/custom/MultiplayerSync.gd)) espelham os slots e detectam o drop; `_mirrored_board_point()` ([:1342](./src/custom/MultiplayerSync.gd)), chamado por `_target_for_remote()` ([:1325](./src/custom/MultiplayerSync.gd)), posiciona as cartas soltas e **escala o tamanho da carta pela razão `scene/grid`**. Se o rect deixar de bater com a geometria real do grid, o espelhamento quebra em silêncio — hoje isso vale também para o solo/hotseat, não só para o multiplayer. |
| Lado local | posição e tamanho de `Deck`, `Discard` e `Prêmios`; `ResourceSelectionLabel`, `HandLabel`, `PrizeEnergyLabel` e o caption `ModifiedLabelGrid/Control/Label` | **Autorais**, exceto a rotação do `Deck` (decisão d): ela continua em código |
| Intrinsecamente runtime | leque da mão (`hand.re_place()`), reempilhar dos piles (motivo do `_hold_pile_layout()`), altura do grid (2 linhas × slot na escala de jogo) | Ficam em código |

As zonas decorativas também são lidas por `_lens_target()` ([src/custom/MultiplayerSync.gd:881](./src/custom/MultiplayerSync.gd)), que dimensiona a lupa de zona, e por `_center_zone_position()` ([:1409](./src/custom/MultiplayerSync.gd)), que posiciona as miniaturas remotas. Um erro pequeno ali só desloca a miniatura; não quebra regra.

## Plano em etapas

### ✅ Etapa 0 — Medição

Adicionar um dump temporário que imprime o rect real de cada nó da tabela acima (posição, tamanho, rotação e, nos `Control`, os `margin_*` equivalentes) em `.prints/board_layout.txt`, junto com o tamanho do viewport para confirmar que o layout roda em 1280×720 mesmo com a janela maior. Executar via **F6** em `CGFMain.tscn`, que cai no modo solo e carrega as cartas de teste — assim os painéis internos dos piles já têm o tamanho real.

A medição é do **estado atual aprovado** (o que o Doug viu e disse que ficou bom), não de um render futuro. Ela precisa registrar também:

- o rect autoral gravado no `.tscn` ao lado do derivado do grid para `OpponentScene`, que é onde a defasagem aparece (858 gravado contra 1004 calculado em 2026-10-29);
- as duas larguras do `OpponentResourcesBackground` (156 colapsada e 176 no hover), porque esse é o único rect que o runtime altera depois do layout;
- `deck.position` e `deck.rotation_degrees` reais, para confirmar que a posição vai para a cena e a rotação fica em código.

Sem essa medição, a etapa 1 gravaria o fóssil atual.

### ✅ Etapa 1 — Cena autoral

Gravar os números medidos em `src/custom/CGFBoard.tscn`, em coordenadas absolutas, inclusive desfazendo as âncoras à direita da coluna direita. `PlacementGridDemo` não é tocado. `OpponentScene` recebe o valor medido, mas continua sincronizado em runtime. O `Deck` recebe posição e tamanho atuais e **mantém `rotation_degrees = 270` reafirmado em código** (decisão d) — a área do deck não muda.

### ✅ Etapa 2 — Runtime burro

Em `src/custom/CGFBoard.gd`: apagar `_layout_opponent_field()` (≈ 90 linhas) e reduzir `_apply_battle_scenes_layout()` para cerca de 20 linhas que

1. mantêm `scene_grid.configure_width()` com o comportamento padrão;
2. leem as posições autorais uma vez para `_deck_position`, `_discard_position` e `_prizes_position`, em vez de calculá-las;
3. sincronizam `OpponentScene` com o rect real do grid;
4. chamam `hand.re_place()`;
5. capturam a largura autoral do `OpponentResourcesBackground` uma vez (`_resources_base_width`) e usam essa largura no grid espelhado de recursos (`_resources_grid_scale()`), que segue as mesmas colunas e o mesmo vão do grid local do descarte e não redimensiona mais a caixa.

`strip_bottom` passa a ser lido do rect autoral (`OpponentFieldBackground.margin_top`) em vez do literal `80.0`. O `_hold_pile_layout()` continua, porque o restack de um pile re-âncora o `CardContainer` e empurraria os piles de volta para o canto do viewport — só que agora ele reafirma os valores autorais e segue reafirmando `rotation_degrees = 270` do deck.

### ✅ Etapa 3 — Mão ajustável no Inspector

`var bottom_margin` em [src/core/Hand.gd:17](./src/core/Hand.gd) vira `export var`, mantendo o mesmo default (`CFConst.BOTTOM_MARGIN_MULTIPLIER = 0.5`, [src/custom/CFConst.gd:154](./src/custom/CFConst.gd)), e o valor literal correspondente é gravado em `src/custom/CGFHand.tscn`. A linha `hand.bottom_margin = hand.card_size.y * 0.5` sai do `CGFBoard.gd`.

### ✅ Etapa 4 — Guarda de consistência

Atrás do checkbox `$Debug` que já existe no board ([src/custom/CGFBoard.gd:31](./src/custom/CGFBoard.gd)), comparar o rect derivado do grid com o `OpponentScene` e avisar quando divergir mais de 1 px, listando os nós afetados. A comparação é de **posição e tamanho**: `_mirrored_board_point()` escala o tamanho da carta pela razão `scene/grid`, então um `OpponentScene` redimensionado encolhe ou cresce as cartas soltas do espelho mesmo que o canto continue alinhado. Esse é o sinal de que um re-bake é necessário — os únicos casos são mudança de `CFConst.PLAY_AREA_SCALE`, do número de colunas/linhas do grid ou da resolução de design.

### ✅ Etapa 5 — Validação e limpeza

Remover o código da etapa 0. Rodar o GUT com um arquivo por processo: `test_placement_grid`, `test_board_use`, `test_solo_hotseat`, `test_multiplayer_lobby`, `test_anchors`. Capturar antes/depois em `.prints/` e comparar — o objetivo é o render ficar **idêntico**, já que a etapa 1 grava os mesmos números medidos. Rodar o roteiro de smoke de multiplayer para conferir o espelhamento slot a slot e a lupa de zona, que são os consumidores sensíveis do `OpponentScene`. Por fim, retomar o jogo do F5 com `restart-godot-game.ps1`, depois de autorizada a reinicialização.

## Arquivos previstos

| Arquivo | Natureza da mudança |
|---|---|
| `src/custom/CGFBoard.tscn` | A maior parte: apenas números de `margin_*`, `anchor_*` e rotação |
| `src/custom/CGFBoard.gd` | ~150 linhas de layout viram ~20; remoção de `_layout_opponent_field()` |
| `src/core/Hand.gd` + `src/custom/CGFHand.tscn` | `bottom_margin` vira `export` e ganha valor na cena |
| `tools/` | Script de dump temporário, apagado na etapa 5 |

Pré-condição: **cumprida em 2026-10-29** no commit `261e074` (solo hotseat, log de ações e paridade do espelho), com a árvore limpa. O diff do re-bake deve continuar saindo limpo: nada de código novo entra entre a etapa 0 e a etapa 1.

## Pendências visuais depois do bake

Estes ajustes estavam na lista de layout por código e passam a ser **arrasto no Inspector**, depois das etapas 1 e 2 — fazer antes seria retrabalho e sujaria a comparação "render idêntico" da etapa 5:

- Cenário ativo do mesmo tamanho das cartas em jogo;
- rótulo de quantidade/energia dos Prêmios em outra posição;
- rótulos do lado do oponente ("Cenário", "Prêmios", "Energia", "Recursos/D", "CAMPO DO OPONENTE") que hoje se espalham sobre o campo — o de "Recursos/D" já foi resolvido em 2026-10-30, movido para o topo do box (ver [Ajustes do espelho de recursos](#ajustes-do-espelho-de-recursos-2026-10-30)).

O deck **não** está nesta lista: a decisão d manteve o monte deitado a 270° e a área como está.

## Fora deste plano

- **Rota B — prévia no editor com script `tool`.** Extrair a matemática para um helper sem dependência de `cfc` e posicionar os nós na vista 2D sem rodar o jogo. No Godot 3.4 os autoloads não existem no editor, então o `tool` não pode tocar em `cfc`/`Multiplayer`, e cartas reais não aparecem — só caixas. Não é preciso se a cena virar a fonte da verdade.
- **Rota C — reescrever o layout na cena em runtime.** Fazer o jogo gravar o `.tscn` via `ResourceSaver` é frágil no 3.4: `Node.get_scene()` achata a cena e pode perder `ext_resource`, overrides de nós instanciados, grupos e conexões. Se um dia for necessário, o caminho é o despejo dos rects num arquivo fora da cena e um patch de texto nas linhas numéricas.
- **Boot direto no tabuleiro.** Trocar `run/main_scene` ([project.godot:396](./project.godot)) para `CGFMain.tscn` faria o F5 abrir o campo sem passar pelo menu, mas o build HTML5 deixaria de abrir o lobby e o tratamento de `?room=`/`?relay=` do menu nunca rodaria. A alternativa segura é um gate por `OS.has_feature("editor")` mais variável de ambiente, no mesmo padrão de `BS_WINDOWED` ([src/custom/DisplayMode.gd](./src/custom/DisplayMode.gd)).
- **Limitações que permanecem.** Cartas não aparecem na vista 2D (o framework as cria em runtime, só os painéis dos piles são autorais); o leque da mão não é arrastável; e os valores autorais passam a exigir re-bake quando a escala da carta ou a geometria do grid mudarem.

## Execução (2026-10-29)

O bake foi feito no mesmo dia, com o render medido em 1280×720 e `PLAY_AREA_SCALE = 0.66`.

- **Etapa 0:** dump temporário em `.prints/board_layout.txt` (posição, tamanho, rotação, `margin_*`, valores autorais do `.tscn`, larguras do `OpponentResourcesBackground` e o rect real do deck). Medição: grid em `(159.5, 366.2)` com `961×286.2`, `OpponentScene` autorado em `858×248` contra `961×286.2` derivado, coluna de prêmios em `x = 1160`, deck em `(0, 722)` com `rotation = 270` e `bottom_margin` da mão em `105`.
- **Etapa 1:** `CGFBoard.tscn` recebeu os valores medidos em coordenadas absolutas; as âncoras da coluna direita foram removidas. `Deck`, `Discard` e `Prêmios`, `PrizeEnergyLabel`, `ResourceSelectionLabel` e `HandLabel` também passaram a ter posição autoral.
- **Etapa 2:** `_layout_opponent_field()` apagada; `_apply_battle_scenes_layout()` ficou com ~55 linhas lendo a cena (`_capture_authored_layout()` guarda os slots dos piles e a largura de recursos antes de qualquer restack). `OpponentScene` continua sincronizado com o grid. O grid espelhado de recursos usa `board.resources_base_width()` para calcular a escala das miniaturas, sem alterar a largura da caixa.
- **Etapa 3:** `Hand.bottom_margin` virou `export` e o valor `105` foi gravado em `CGFHand.tscn`; a linha que recalculava a margem saiu do board.
- **Etapa 4:** com `$Debug` marcado, `_warn_if_opponent_scene_drifted()` compara posição **e** tamanho do `OpponentScene` autorado com o grid e avisa quando a divergência passa de 1 px.
- **Etapa 5:** dump removido; GUT com `test_placement_grid` (32), `test_board_use` (7), `test_anchors` (5), `test_solo_hotseat` (9), `test_multiplayer_lobby` (21), `test_damage_knockout` (6), `test_game_events` (13) e `test_battle_scenes_capacity` (4) — 97 testes, 0 falhas. O dump de runtime antes e depois do bake saiu idêntico, confirmando que o render não mudou.

## Ajustes do espelho de recursos (2026-10-30)

O box do oponente ainda diferia do painel local de `Recursos / Descarte` em quatro pontos, todos corrigidos:

- **Rótulo no topo.** `OpponentResourcesVeil` (144.2→166.2) e `OpponentResourcesLabel` (146.2→164.2) saíram da faixa de baixo para o topo do `OpponentResourcesBackground` (144.2→360.2), como o rótulo "Recursos" do painel local. O fundo e o botão `OpponentResourcesView` (canto inferior direito) não mudaram.
- **Um grid só.** `CGFDiscard.grid_layout()` expõe `origin`, `step` e `scale` do grid local; `MultiplayerSync._resource_slot_position()` consome esses números em vez de repetir a conta (só cai nas constantes enquanto `_layout_panel()` não rodou). O `origin.y` usa `max()` com a faixa do rótulo para a primeira linha nunca cobrir o texto.
- **Posição e orientação.** As miniaturas espelhadas não recebem mais +180° (um grid de pilha se lê igual dos dois lados) e são posicionadas por `card.global_position` — antes um valor global era gravado em `position`, o que deslocava o grid conforme o tabuleiro crescia.
- **Ordem e contagem.** A pilha local põe o topo (último índice) na primeira célula; o espelho agora ordena pelo índice da pilha, que viaja em cada carta de recursos, porque um rebuild de hotseat entrega a pilha inteira na ordem de spawn. O rótulo "Recursos/Descarte (n)" é atualizado no `start_mirroring()`, então o hotseat não abre mais com zeros de placeholder. O hover usa a mesma regra do grid local: retângulo sob o ponteiro, não `Area2D`.
