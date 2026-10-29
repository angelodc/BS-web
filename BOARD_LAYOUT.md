# Planejamento do Layout do Tabuleiro

Este documento registra o plano para tornar `src/custom/CGFBoard.tscn` editável na vista 2D do editor do Godot do mesmo jeito que `src/custom/MainMenu.tscn` já é, em vez de depender da leitura de números dentro do código. As decisões confirmadas estão em [Decisões](#decisões-confirmadas) e o passo a passo em [Plano](#plano-em-etapas).

## Objetivo

Abrir `CGFBoard.tscn` no editor, ver o campo como ele renderiza e arrastar as caixas no layout. Hoje isso não funciona para o tabuleiro, e o motivo é concreto.

## Diagnóstico

- Os nós do lado oponente **já têm rects autorais** na cena: `OpponentFieldVisual` e seus filhos (`ColorRect` de fundo, cenário, prêmios, recursos, deck, mão, mais os Labels e botões) estão gravados com `margin_*` e `anchor_*` normais em [src/custom/CGFBoard.tscn:338](./src/custom/CGFBoard.tscn). Eles aparecem na vista 2D.
- Em runtime, `_layout_opponent_field()` recalcula e **sobrescreve** cada um desses rects ([src/custom/CGFBoard.gd:151](./src/custom/CGFBoard.gd)), e o lado local inteiro é posicionado por código ([src/custom/CGFBoard.gd:91](./src/custom/CGFBoard.gd)) com cerca de 30 literais.
- Os valores gravados na cena ficaram **defasados** do que o código calcula. Exemplo: `OpponentHandBackground` tem `margin_right = 772` no arquivo, mas o código usa `grid_x = (1280 - scene_size.x) / 2` com largura de grid ≈ 672, o que daria ≈ 976. O que o editor mostra é um bake antigo.

Consequência: editar à mão hoje significa caçar constante dentro de duas funções, e a vista 2D do editor mente sobre o resultado.

## Decisões confirmadas

| # | Decisão | Escolha |
|---|---|---|
| a | Largura do `PlacementGridDemo` | **Padrão atual**: continua calculada por `configure_width()` e centralizada; o grid não é arrastado no editor. |
| b | Como gravar as posições no `.tscn` | **Coordenadas absolutas**: remover `anchor_left/right = 1.0` e as margens negativas da coluna direita. Com `window/stretch/mode="2d"` e `aspect="keep"`, a resolução de design é sempre 1280×720, então as âncoras não ganham nada e o Inspector fica legível ao arrastar. |
| c | Dump de medição de rects | **Temporário**, removido antes da entrega. |

## Classificação dos nós

| Grupo | Nós | Destino |
|---|---|---|
| Decorativos do lado oponente | `OpponentFieldBackground`, `OpponentHandBackground`, `OpponentHandLabel`, `OpponentResourcesBackground`, `OpponentResourcesLabel`, `OpponentResourcesView`, `OpponentPrizes`, `OpponentPrizesLabel`, `OpponentPrizesView`, `OpponentPrizesEnergy`, `OpponentScenario`, `OpponentScenarioLabel`, `OpponentDeck`, `OpponentDeckLabel`, `OpponentFieldLabel`, `OpponentSceneLabel` e `OpponentFieldVisual.margin_bottom` | **Autorais** (arrastar no editor) |
| Geometria crítica | `OpponentScene` | **Continua derivado do grid.** `MultiplayerSync._mirrored_slot_rect()` ([src/custom/MultiplayerSync.gd:1302](./src/custom/MultiplayerSync.gd)) e `_mirror_slot_at()` ([:529](./src/custom/MultiplayerSync.gd)) usam esse rect para espelhar os slots e detectar o drop. Se ele deixar de bater com a geometria real do grid, o mirroring quebra em silêncio. |
| Lado local | posições de `Deck` (com `rotation_degrees = 270`), `Discard` e `Prêmios`; `ResourceSelectionLabel`, `HandLabel`, `PrizeEnergyLabel` e o caption `ModifiedLabelGrid/Control/Label` | **Autorais** |
| Intrinsecamente runtime | leque da mão (`hand.re_place()`), reempilhar dos piles (motivo do `_hold_pile_layout()`), altura do grid (2 linhas × slot na escala de jogo) | Ficam em código |

As zonas decorativas também são lidas por `_lens_target()` ([src/custom/MultiplayerSync.gd:884](./src/custom/MultiplayerSync.gd)), que dimensiona a lupa de zona, e por `_center_zone_position()` ([:1383](./src/custom/MultiplayerSync.gd)), que posiciona as miniaturas remotas. Um erro pequeno ali só desloca a miniatura; não quebra regra.

## Plano em etapas

### Etapa 0 — Medição

Adicionar um dump temporário que imprime, rodando a 1280×720, o rect real de cada nó da tabela acima (posição, tamanho, rotação e, nos `Control`, os `margin_*` equivalentes), em `.prints/board_layout.txt`. Executar via **F6** em `CGFMain.tscn`, que cai no modo solo e carrega as cartas de teste — assim os painéis internos dos piles já têm o tamanho real. Sem essa medição, a etapa 1 gravaria o fóssil atual.

### Etapa 1 — Cena autoral

Gravar os números medidos em `src/custom/CGFBoard.tscn`, em coordenadas absolutas, inclusive desfazendo as âncoras à direita da coluna direita. `PlacementGridDemo` não é tocado. `OpponentScene` recebe o valor medido, mas continua sincronizado em runtime.

### Etapa 2 — Runtime burro

Em `src/custom/CGFBoard.gd`: apagar `_layout_opponent_field()` (≈ 90 linhas) e reduzir `_apply_battle_scenes_layout()` para cerca de 20 linhas que

1. mantêm `scene_grid.configure_width()` com o comportamento padrão;
2. leem as posições autorais uma vez para `_deck_position`, `_discard_position` e `_prizes_position`, em vez de calculá-las;
3. sincronizam `OpponentScene` com o rect real do grid;
4. chamam `hand.re_place()`.

`strip_bottom` passa a ser lido do rect autoral (`OpponentFieldBackground.margin_top`) em vez do literal `80.0`. O `_hold_pile_layout()` continua, porque o restack de um pile re-âncora o `CardContainer` e empurraria os piles de volta para o canto do viewport — só que agora ele reafirma os valores autorais.

### Etapa 3 — Mão ajustável no Inspector

`var bottom_margin` em [src/core/Hand.gd:17](./src/core/Hand.gd) vira `export var`, mantendo o mesmo default (`CFConst.BOTTOM_MARGIN_MULTIPLIER = 0.5`, [src/custom/CFConst.gd:154](./src/custom/CFConst.gd)), e o valor literal correspondente é gravado em `src/custom/CGFHand.tscn`. A linha `hand.bottom_margin = hand.card_size.y * 0.5` sai do `CGFBoard.gd`.

### Etapa 4 — Guarda de consistência

Atrás do checkbox `$Debug` que já existe no board ([src/custom/CGFBoard.gd:31](./src/custom/CGFBoard.gd)), comparar o rect derivado do grid com o `OpponentScene` autoral e avisar quando divergir mais de 1 px, listando os nós afetados. É o sinal de que um re-bake é necessário — os únicos casos são mudança de `CFConst.PLAY_AREA_SCALE`, do número de colunas/linhas do grid ou da resolução de design.

### Etapa 5 — Validação e limpeza

Remover o código da etapa 0. Rodar o GUT com um arquivo por processo: `test_placement_grid`, `test_board_use`, `test_solo_hotseat`, `test_multiplayer_lobby`, `test_anchors`. Capturar antes/depois em `.prints/` e comparar — o objetivo é o render ficar **idêntico**, já que a etapa 1 grava os mesmos números medidos. Rodar o roteiro de smoke de multiplayer para conferir o espelhamento slot a slot e a lupa de zona, que são os consumidores sensíveis do `OpponentScene`. Por fim, retomar o jogo do F5 com `restart-godot-game.ps1`, depois de autorizada a reinicialização.

## Arquivos previstos

| Arquivo | Natureza da mudança |
|---|---|
| `src/custom/CGFBoard.tscn` | A maior parte: apenas números de `margin_*`, `anchor_*` e rotação |
| `src/custom/CGFBoard.gd` | ~150 linhas de layout viram ~20; remoção de `_layout_opponent_field()` |
| `src/core/Hand.gd` + `src/custom/CGFHand.tscn` | `bottom_margin` vira `export` e ganha valor na cena |
| `tools/` | Script de dump temporário, apagado na etapa 5 |

Pré-condição: a árvore de trabalho tem alterações não commitadas, inclusive em `CGFBoard.gd`, `CGFBoard.tscn`, `CGFHand.tscn`, `CFConst.gd` e `MultiplayerSync.gd`. Convém commitar ou revisar esse estado antes da etapa 1, para o diff do re-bake sair limpo e revisável.

## Fora deste plano

- **Rota B — prévia no editor com script `tool`.** Extrair a matemática para um helper sem dependência de `cfc` e posicionar os nós na vista 2D sem rodar o jogo. No Godot 3.4 os autoloads não existem no editor, então o `tool` não pode tocar em `cfc`/`Multiplayer`, e cartas reais não aparecem — só caixas. Não é preciso se a cena virar a fonte da verdade.
- **Rota C — reescrever o layout na cena em runtime.** Fazer o jogo gravar o `.tscn` via `ResourceSaver` é frágil no 3.4: `Node.get_scene()` achata a cena e pode perder `ext_resource`, overrides de nós instanciados, grupos e conexões. Se um dia for necessário, o caminho é o despejo dos rects num arquivo fora da cena e um patch de texto nas linhas numéricas.
- **Boot direto no tabuleiro.** Trocar `run/main_scene` ([project.godot:396](./project.godot)) para `CGFMain.tscn` faria o F5 abrir o campo sem passar pelo menu, mas o build HTML5 deixaria de abrir o lobby e o tratamento de `?room=`/`?relay=` do menu nunca rodaria. A alternativa segura é um gate por `OS.has_feature("editor")` mais variável de ambiente, no mesmo padrão de `BS_WINDOWED` ([src/custom/DisplayMode.gd](./src/custom/DisplayMode.gd)).
- **Limitações que permanecem.** Cartas não aparecem na vista 2D (o framework as cria em runtime, só os painéis dos piles são autorais); o leque da mão não é arrastável; e os valores autorais passam a exigir re-bake quando a escala da carta ou a geometria do grid mudarem.
