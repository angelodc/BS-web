# Ações sem mouse: posições fixas, intenções, scripts e teclado

Este documento registra o plano para que toda ação do jogo possa ser disparada
sem o mouse — por botão, por teclado, por script de teste ou por comando de
texto — e para que cada carta tenha uma posição fixa e nomeada na mesa. As fases
F0 a F6 já foram implementadas; o documento segue como contrato e registro do
que foi entregue.

A branch criada para isso é `feat/acoes-sem-mouse`, que nasce do topo de
`feat/solo-hotseat-espelho` (commit `15c0534`) e leva junto a correção ainda não
commitada de `CardFront.gd` e do teste dela.

As perguntas originais estão em
[ACOES_SEM_MOUSE_PERGUNTAS.md](./ACOES_SEM_MOUSE_PERGUNTAS.md); as respostas já
foram incorporadas nas seções de decisões e regras abaixo.

**Fora de escopo: ditado por voz.** O modo ditado não será planejado nem
implementado agora (resposta 24d). Nada neste documento depende de voz; se ele
voltar algum dia, será um projeto separado, com o parser de comandos já pronto.

## Decisões fechadas

Respostas do questionário, agrupadas pelo que elas mudam no plano.

| Tema | Decisão | # |
|---|---|---|
| Mesa | 2 jogadores (P1 e P2) | 1a |
| Turno | Quem age depende da fase | 2c |
| Turno | Termina quando "Avançar fase" volta ao começo | 3b |
| Assento | "Controlar P1/P2" também é comando de texto | 4a |
| Espelho | Informativo hoje; alvo de ação no futuro | 5b |
| Campo | Posição é só organização, sem efeito de regra | 6a |
| Campo | Entra no slot automático; o jogador muda depois | 7c |
| Campo | Personagens e suportes em qualquer fileira | 8b |
| Campo | Frente cheia → coluna de trás; atrás cheia → nova coluna | 9d |
| Campo | Slots crescem conforme as cartas entram | 10c |
| Recursos | A zona de recursos é a pilha de descarte | 11a |
| Recursos | 6 cartas visíveis na grade | 12a |
| Recursos | A ordem dos recursos não importa | 13a |
| Prêmios | Primeiro slot livre, em ordem | 14a |
| Cenário | Um cenário ativo compartilhado pelos dois assentos | 15b |
| Cenário | Cenário substituído vai para os recursos do dono | 16b |
| Mão | Slots nomeados e reordenação manual | 17c |
| Mão | Compra entra no começo da mão | 18b |
| Mão | Sem limite de cartas | 19c |
| Anexos | Recursos embaixo, habilidades em cima | 20c |
| Anexos | Habilidade sem hospedeiro só se a carta permitir | 21b |
| Pagamento | Custo exato paga sozinho, sem popup | 23a |
| Scripts | Formato JSON; cartas pelo id da definição | 25c, 29b |
| Scripts | Nomes duplicados ganham alias automático | 26c |
| Scripts | Podem alterar partida real, com registro no log | 39b |
| Log | Uma ação pode ser desfeita | 27b |
| Log | Log completo fica visível | 28a |
| Testes | Estado + ordem visual + log | 30d |
| Testes | Sempre determinístico (seed e deck fixos) | 31a |
| Testes | Runner no GUT e standalone | 32c |
| Produto | Atalhos de teclado para tudo | 36a |
| Produto | Público: automação e testes | 37c |
| Prioridade | Primeiro posições fixas + ações validadas | 38a |
| Confirmação | Nenhuma ação pede confirmação; quem comanda responde | 22i |
| Regras | Nenhuma regra simplificada precisa voltar agora | 40 |
| Ditado | Fora de escopo agora | 24d |

Todas as perguntas foram respondidas; não há ponto em aberto no plano.

## Objetivo

1. Uma única porta de entrada para cada ação: botão, arrasto, teclado e script
   chamam a mesma função validada.
2. Posições fixas: cada zona (mão, campo, cenário, recursos, prêmios) tem slots
   nomeados; uma carta só sai de um slot por ação, nunca por conta do ponteiro.
3. Testes por script: uma partida pode ser descrita como sequência de ações e
   verificada por estado (zona + slot + contagem), ordem visual e log, sem
   simular mouse.
4. Atalhos de teclado equivalentes para todas as ações, com o mesmo caminho de
   validação.

O mouse continua funcionando. Ele deixa de ser a fonte da regra e passa a ser
só mais um jeito de escolher o destino.

## O que existe hoje

### As zonas da mesa

| Zona | Nó | Como a posição é decidida hoje | Observação |
|---|---|---|---|
| Mão | `Hand` (leque oval) | ordem dos filhos + `recalculate_position()`; compras entram no fim | não há slot nomeado; o leque é recalculado a cada mudança |
| Campo | `PlacementGridDemo` (`BoardPlacementGrid`) | 2 linhas × N colunas; a linha de frente é a mais perto do centro; preenche do centro para fora; suporte prefere a linha de trás | `auto_arrange` e `configure_width()` em [src/core/BoardPlacementGrid.gd:104](./src/core/BoardPlacementGrid.gd) |
| Cenário | `ModifiedLabelGrid` | um slot fixo de 120×168; jogar um cenário substitui o ativo | a troca é permitida em `_is_placement_slot_valid()` ([src/core/MousePointer.gd:284](./src/core/MousePointer.gd)) |
| Recursos | `Discard` (`CGFDiscard`) | grade 3×2 das 6 cartas do topo; o resto fica fora da tela | a pilha inteira é a zona de recursos ([src/custom/CGFDiscard.gd:318](./src/custom/CGFDiscard.gd)) |
| Prêmios | `Prêmios` (`CGFPrizes`) | grade 2×2 das 4 miniaturas do topo; o resto invisível | mesma ideia, painel menor ([src/custom/CGFPrizes.gd:64](./src/custom/CGFPrizes.gd)) |
| Deck | `Deck` (`CGFDeck`) | leque de 10, deitado a 270°; metade de cima compra, faixa esquerda manda o topo para Recursos | clique, não botão ([src/custom/CGFDeck.gd:340](./src/custom/CGFDeck.gd)) |
| Espelho do oponente | `OpponentFieldVisual` + `MultiplayerSync` | recriado a partir de mensagens de rede (zona, x/y, slot, host) | cada zona espelhada redesenha a geometria por conta própria ([src/custom/MultiplayerSync.gd:387](./src/custom/MultiplayerSync.gd)) |

### Ações que hoje dependem do mouse

| Ação | Gatilho | Função que executa |
|---|---|---|
| Arrastar qualquer carta | Card | `_start_dragging()` / `move_to()` ([src/core/CardTemplate.gd:1172](./src/core/CardTemplate.gd)) |
| Soltar no campo | `MousePointer` + grid | `get_potential_placement_slot()` + `get_auto_placement_slot()` ([src/core/BoardPlacementGrid.gd:151](./src/core/BoardPlacementGrid.gd)) |
| Soltar sobre personagem/suporte | `MousePointer` | `potential_host` → `attach_to_host()` ([src/core/CardTemplate.gd:1626](./src/core/CardTemplate.gd)) |
| Comprar / mandar o topo para Recursos | clique no deck | sinal `draw_card` → `Hand.draw_card()`; `_mill_top_card_to_resources()` |
| Procurar, embaralhar, clarividência | botões do deck | `CGFDeck` |
| Pagar custo | popup de recursos | `begin_resource_selection()` / `select_resource_for_host()` ([src/custom/CGFBoard.gd:503](./src/custom/CGFBoard.gd)) |
| Trocar recurso anexado | botão "Trocar" | `begin_resource_swap()` / `select_resource_for_swap()` / `swap_attached_resource()` |
| Dano, nocaute, prêmios, escudo, virar, girar, capacitar, incapacitar | botões da carta | `CGFManipulationButtons.gd` → `CGFBoard.damage_character()`, `send_character_to_opponent_prizes()`, `tokens.mod_token()` etc. ([src/custom/CGFManipulationButtons.gd:64](./src/custom/CGFManipulationButtons.gd)) |
| Avançar fase / trocar assento | HUD | `Multiplayer.advance_phase()` / `swap_solo_seat()` ([src/custom/Multiplayer.gd:423](./src/custom/Multiplayer.gd), [:1150](./src/custom/Multiplayer.gd)) |
| Prévia e lupa de zona | mouse | só visual; não mudam estado |

### Por que a posição "se perde"

A mesma informação tem hoje cinco donos: a carta guarda `_target_position` e
`_placement_slot`, o slot guarda `occupying_card`, o pile guarda a ordem dos
filhos, o popup guarda uma cópia visual e o espelho guarda
`_remote_cards`/`_remote_meta`. Quando uma ação mexe em mais de uma zona ao
mesmo tempo, nada garante que os cinco concordem.

O botão **Prêmios** mostra o padrão: `send_character_to_opponent_prizes()`
([src/custom/CGFBoard.gd:411](./src/custom/CGFBoard.gd)) libera os anexos para
o descarte, zera o slot, apaga o nó local, manda a carta pela rede e, no
hotseat, cria uma miniatura no prêmio do outro assento. A contagem de recursos,
por sua vez, não lê slot nenhum: conta cartas pelo pai do nó
([src/custom/CGFBoard.gd:455](./src/custom/CGFBoard.gd)). Qualquer carta em
trânsito ou dentro do popup entra na conta.

Esse é o bug que ficou para depois. O modelo abaixo é o que dá um lugar único
para corrigi-lo sem remendo em cada tela.

## Modelo proposto

### 1. Estado da mesa como fonte da verdade

Uma estrutura de dados pura, sem nós: `TableState`. Para cada assento (P1/P2)
ela guarda as zonas e, para cada carta, **um** endereço. O cenário é da mesa,
não de um assento: só existe um ativo, compartilhado.

```text
mesa:cenário                 0 ou 1 carta ativa, compartilhada por P1 e P2
p1:mão:1 … N                 reordenação manual; compra entra no começo
p1:campo:frente:1 … N        linha da frente; N cresce com a mesa
p1:campo:trás:1 … N          linha de trás; N cresce com a mesa
p1:recursos:1 … 6            topo = 1; a pilha guarda o resto
p1:prêmios:1 … 4             primeiro slot livre em ordem
p1:deck:topo                 topo do monte
anexo:p1:<hospedeiro>:1 … n  recursos embaixo (1..n), habilidades em cima
```

Regras estruturais:

- Toda carta tem exatamente um endereço. Não existe "carta solta".
- Anexos (recursos e habilidades) não ocupam slot de campo: pertencem a um
  hospedeiro e a posição visual deles é derivada do hospedeiro + índice. É a
  regra "habilidade só existe embaixo de um personagem ou suporte", salvo quando
  a própria carta permitir ficar sem hospedeiro (21b).
- A ordem dos anexos é por tipo: recursos abaixo, habilidades acima (20c).
- Pixels não entram no estado. O renderer calcula o rect de cada slot a partir
  da zona e do layout; mover a carta é mudar o endereço, não o `position`.
- O campo cresce de verdade: novas colunas entram quando frente e trás estão
  cheias (9d, 10c), em vez de a grade ter um tamanho fixo.
- A posição no campo não altera regra nenhuma: é só organização (6a).
- O espelho do oponente lê o mesmo estado com outro ponto de vista: zonas
  ocultas (mão, deck) mostram só a contagem; o resto mostra o endereço real,
  girado para a banda de cima. Hoje o espelho é informativo; torná-lo alvo de
  ação fica para o futuro (5b).

### 2. Ação = intenção validada

Cada ação vira uma `Intent`: verbo, assento que age, carta, destino, alvos e
custo. O fluxo é sempre o mesmo:

```text
intent → TableRules.validate(intent) → TableActions.apply(intent)
       → TableState muda → renderer + log + rede (diff)
```

- Botão, arrasto, teclado e script chamam a mesma intenção; o arrasto só
  calcula qual slot está sob o ponteiro.
- Toda intenção devolve `{ok, erro, estado}`. Se falhar, nada muda.
- Ações compostas são uma transação. "Enviar para os prêmios do oponente", por
  exemplo, libera os anexos, limpa o slot, acrescenta a carta ao prêmio do outro
  assento e atualiza a contagem de uma vez; se um passo falhar, a mesa fica como
  estava.
- O turno e o assento ativo são validados na `TableRules`, não espalhados pelos
  botões. Como quem age depende da fase (2c), a regra lê a fase atual em vez de
  assumir "só o assento do turno".
- O fim do turno é o ciclo de "Avançar fase" voltar ao começo (3b).
- Uma ação pode ser desfeita (27b) e cada mudança entra no log visível (28a).
- Nenhuma ação pede confirmação (22i): a tecla, o botão ou o comando aplica na
  hora, e quem comanda responde pelo que mandou.

### 3. Catálogo inicial de verbos

| Verbo | Parâmetros | Implementação atual por trás |
|---|---|---|
| `comprar` | assento, quantidade | `Hand.draw_card()` (entra no começo da mão) |
| `mandar_topo_para_recursos` | — | `CGFDeck._mill_top_card_to_resources()` |
| `jogar` | carta, fileira + coluna, ou "automático" | `Card.move_to()` + `BoardPlacementGrid` |
| `jogar_cenário` | carta | `ModifiedLabelGrid` (cenário compartilhado) |
| `jogar_como_recurso` | carta, hospedeiro | `attach_to_host()` |
| `anexar` | carta, hospedeiro | `attach_to_host()` |
| `pagar` | hospedeiro, quantidade, recursos[] | `begin_resource_selection()` / `_auto_pay_resources()` |
| `trocar_recurso` | recurso anexado, substituto | `swap_attached_resource()` |
| `mover` | carta, slot de destino | `Card.move_to(..., board_position)` |
| `descartar` | carta | `Card.move_to(discard)` |
| `ferir` | carta, quantidade | `CGFBoard.damage_character()` |
| `nocautear` | carta | `knockout_character()` / `knockout_support()` |
| `enviar_aos_prêmios` | carta | `send_character_to_opponent_prizes()` |
| `escudo` | carta, ±quantidade | `tokens.mod_token("escudo", n)` |
| `virar` | carta | `set_is_faceup()` |
| `girar` | carta, 90/180/270 | `set_card_rotation()` |
| `capacitar` / `incapacitar` | carta | `capacitar()` / `incapacitar()` |
| `embaralhar` | pilha | `Pile.shuffle_cards()` |
| `revelar_topo` | quantidade | `CGFDeck._show_top_cards()` |
| `buscar` | carta, deck | `CGFDeck._on_search_pressed()` |
| `usar_habilidade` | carta, habilidade, alvos[] | scripting engine (o trigger ainda não é exposto por fora) |
| `passar_fase` | — | `Multiplayer.advance_phase()` |
| `trocar_assento` | — | `Multiplayer.swap_solo_seat()` (só hotseat; também via texto) |
| `desfazer` | — | última ação do log |

### 4. Renderização e espelho

- O renderer deixa de ser dono de posição: ele reconcilia nós a partir do
  estado (cria, remove, move para o rect do slot).
- O espelho deixa de recalcular geometria por conta própria: desenha o mesmo
  estado para o assento adversário. As mensagens de rede passam a ser intenções
  ou diffs de estado, não `x/y` de cada carta.
- O hotseat vira um caso especial de ponto de vista: trocar de assento é só
  trocar `viewer_seat`.

### 5. Scripts, log e teclado

- Script de teste em JSON, com ids de slot e o id da definição da carta, por
  exemplo:
  `{"op":"play","card":"Electro","zone":"field","slot":"front:2"}`.
- Cartas com nome duplicado ganham um alias automático, estável, para o script
  não depender da posição na lista.
- O executor roda dentro do GUT e também standalone, e é sempre determinístico:
  a mesma seed e o mesmo deck produzem o mesmo estado final.
- O script pode alterar uma partida real; toda ação fica no log.
- O log é completo e visível, e guarda o suficiente para desfazer uma ação.
- Atalhos de teclado cobrem todas as ações e passam pelo mesmo caminho de
  validação. Nenhuma delas pede confirmação (22i).
- Testes conferem estado, ordem visual e log.
- Ditado por voz não faz parte desta fase nem das seguintes (24d).

## Regras confirmadas

- **Assentos.** A mesa suporta 2 jogadores. No hotseat, "Controlar P1/P2" é um
  botão e também um comando de texto.
- **Quem age.** Depende da fase; a compra pode ser de um momento e as ações de
  outro. A validação usa a fase atual.
- **Fim do turno.** Quando "Avançar fase" completa o ciclo e volta ao começo.
- **Campo.** Personagens e suportes podem ocupar qualquer fileira, mas a posição
  não tem efeito de regra. A carta entra no slot automático e o jogador pode
  mudar depois. A ordem de ocupação é: frente, centro para fora; frente cheia,
  coluna de trás; atrás cheia, nova coluna. A grade cresce com a mesa.
- **Cenário.** Um único cenário ativo, compartilhado pelos dois assentos. O
  cenário substituído vai para os recursos do dono.
- **Recursos.** A zona de recursos é a pilha de descarte. Seis cartas ficam
  visíveis na grade; o resto fica na pilha. A ordem dos recursos não importa.
- **Pagamento.** Quando o número de recursos disponíveis é exatamente o custo, o
  pagamento acontece sozinho, sem popup.
- **Prêmios.** A carta ocupa o primeiro slot livre, em ordem.
- **Mão.** Tem slots nomeados e reordenação manual. A compra entra no começo da
  mão. Não há limite de cartas.
- **Anexos.** Nunca ocupam slot de campo; a ordem é por tipo — recursos abaixo,
  habilidades acima. Habilidade sem hospedeiro só quando a carta permitir.
- **Contagens.** Recursos disponíveis, mão, deck, prêmios e energia são
  derivados do estado, nunca do parentesco dos nós.
- **Confirmação.** Nenhuma ação pede confirmação antes de aplicar; a tecla ou o
  comando aplica na hora e quem comanda responde pelo que mandou.
- **Regras simplificadas.** Nenhuma das simplificações do Battle Scenes
  (pagamento automático no custo exato, fileiras sem efeito de regra, sem limite
  de recursos, prêmios valendo energia) precisa voltar junto com o modelo agora.

## Fases

- **F0 — Contrato.** Este documento + respostas do questionário. Sem código.
  Concluída.
- **F1 — Estado.** `TableState`, ids de zona/slot e um snapshot de leitura;
  testes comparam o estado com a mesa atual, sem mudar comportamento.
  Concluída.
- **F2 — Intenções.** API de intenções para as ações que já existem; botões e
  arrasto passam a chamar as intenções; testes GUT por verbo; log e desfazer.
  Concluída para as ações que mudam a mesa: comprar, topo para recursos, jogar
  (campo e cenário, com troca), anexar, mover, descartar, ferir, nocautear,
  enviar aos prêmios, escudo, virar, girar, capacitar, incapacitar, reordenar,
  embaralhar, passar fase, trocar assento e desfazer. Botões de manipulação,
  deck, HUD e o arrasto (campo, mão, recursos, prêmios e descarte) chamam as
  mesmas intenções. Ficam para F4/F5 os verbos de revelar, buscar, pagar,
  trocar recurso e usar habilidade.
- **F3 — Posições fixas.** Mão e campo dirigidos pelo estado; grade do campo
  cresce; renderer deriva posições; espelho lê o estado. Concluída: o endereço
  do estado decide o slot, inclusive com buracos na fileira; a grade cresce
  mantendo cada carta na sua própria coluna; e o espelho viaja com o endereço
  `campo:fileira:coluna` ao lado do índice de slot antigo, então clientes
  antigos continuam lendo a posição pelo índice.
- **F4 — Scripts.** Runner JSON + console de texto; testes de partida inteira
  por seed, conferindo estado, ordem visual e log. Concluída: `TableScript`
  aceita uma lista de passos ou `{seed, seat, steps}`, resolve a carta pelo id,
  pelo nome ou pelo apelido numerado das cópias ("Test Card 2 2"), e roda cada
  passo como uma intenção; `expect` confere carta+endereço, contagens por zona,
  mão, fileiras do campo, última linha do log e total de entradas. O primeiro
  passo que falha interrompe o script sem aplicar o resto e informa o índice. O
  F8 abre um console de texto no HUD: `mesa`, `log` e `ajuda`, um objeto JSON
  para uma ação e um script JSON para uma sequência. Mesma seed e mesma ordem
  inicial do deck produzem a mesma ordem final; outra seed, outra ordem.
- **F5 — Bug dos recursos.** Corrigir posição e contagem usando o estado único;
  o envio aos prêmios vira uma transação testável. Concluída: a contagem de
  recursos lê a mesma pilha do snapshot (`TableSnapshot.resource_count`), então
  cartas dentro do popup continuam contando e cartas em trânsito não entram; a
  conferência de divergência do snapshot e o número que o tabuleiro usa não
  podem mais discordar. O envio aos prêmios virou uma intenção só: o payload vai
  pela rede primeiro e, apenas depois de aceito, os anexos voltam aos recursos
  do dono, o slot é liberado e a carta sai do tabuleiro. Sem partida ou com a
  rede recusando, nada muda. `send_character_to_opponent_prizes()` delega para a
  intenção e `send_card_to_opponent_prizes()` ficou só com a rede, então botão,
  nocaute e script passam pelo mesmo caminho; `TableActions.prize_sink` permite
  testar a transação sem relay.
- **F6 — Teclado.** Atalhos para todas as ações, sem confirmação (22i: a
  tecla aplica na hora, inclusive as irreversíveis). Concluída:
  `TableKeyboard` mantém uma carta selecionada (`,`/`.` ou Tab/Shift+Tab quando
  nenhum controle tem foco), anda na ordem mão → campo (com anexos) → cenário →
  recursos → prêmios e converte cada tecla numa intenção, então o caminho é o
  mesmo do botão e do script. `A` anexa em dois passos (origem, depois
  hospedeiro) e `N` move a carta para a outra fileira. O mapa completo aparece
  no console com `teclas`. Com o console F8 ou um campo de texto em foco nenhum
  atalho dispara; `Esc` limpa seleção e anexo pendente; `Ctrl+Z` desfaz.

A ordem entre F3 e F4 pode inverter: se o console de texto ajudar a encontrar o
bug mais cedo, ele vem antes das posições fixas.

Ditado por voz: fora do plano. Se voltar, começa depois de F6 e reaproveita o
parser de F4.

## Critérios de aceite

- Nenhuma carta em dois lugares; toda mudança de zona é uma intenção.
- Botão, arrasto, teclado e script exercitam a mesma função; um teste de
  intenção cobre o caminho.
- Contagens (mão, deck, recursos, prêmios, energia) são derivadas do estado,
  nunca do parentesco dos nós.
- O campo cresce além das colunas iniciais quando frente e trás enchem.
- Uma transcrição com a mesma seed produz o mesmo estado final, a mesma ordem
  visual e o mesmo log.
- Toda ação registrada no log pode ser desfeita uma vez.

## Riscos

- Regressão na sensação do mouse e nas animações: o renderer mantém os tweens,
  só deixa de decidir posição.
- `move_to()` é corrotina (usa `yield`): as intenções precisam de um modo
  headless que não espere animação.
- Protocolo de rede: trocar geometria por intenção quebra compatibilidade com
  clientes antigos; precisa de versão.
- Teclado: os atalhos disputam foco com campos de texto e com a busca do deck;
  o mapa de teclas precisa de um contexto explícito.
- Escopo: a mesa cresce, então F3 mexe no layout do campo; convém validar a
  grade antes de migrar o espelho.
