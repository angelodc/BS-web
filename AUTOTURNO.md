# 🕹️ Battle Scenes Web — Turno automático

> Plano da automação das fases do turno. O que já está pronto fica em
> [CONCLUIDOS.md](./CONCLUIDOS.md); o restante do backlog, em [TODO.md](./TODO.md).
> Regras: [BATTLE_SCENES_DESIGN.md](./BATTLE_SCENES_DESIGN.md).

**Status:** planejamento — decisões de regra fechadas (§7), nada implementado.
**Branch:** `autoTurno`.
**Regra de referência:** regulamento oficial Copag (ver §2) + regras do grupo
(ver §3). Onde divergem, a decisão do grupo está em §7.

---

## 1. Objetivo

Automatizar tudo o que hoje o jogador faz na mão: mão inicial, mulligan,
descarte de preparação e os passos obrigatórios das fases de Contagem Regressiva,
Compra e Ajuste. As fases de Preparação e Combate continuam manuais — só ganham
o enquadramento automático (quem age, quando fecha o turno).

No fim, o turno deve andar sozinho: o jogador só clica no que é decisão dele
(mulligan, descarte, ações, passar a fase).

**Fora de escopo desta etapa:** animações novas, regras de PODERES/ESCUDO
(estão no TODO), autoridade por jogada do anfitrião (idem), Ajuste de Mão de
7 cartas (decisão 9b).

---

## 2. Regra oficial (Copag / regras por extenso)

O turno tem 5 fases sequenciais: **Contagem Regressiva → Compra → Preparação →
Ajuste → Combate**.

**Contagem Regressiva** — *somente se você não controla nenhum personagem*:

- coloque 1 card do topo do deck nos seus recursos;
- mais 1 card para cada personagem controlado pelo oponente;
- mais 1 card para cada card que o oponente tiver nos próprios prêmios.

**Compra** — sem personagem em cena: compra 1. Com personagem: compra 2.
O jogador que inicia a partida **não compra** na Compra do primeiro turno.

**Preparação** — passos opcionais, em qualquer ordem: capacitação básica
(descartar 1 card para capacitar +1), capacitação por alter ego, colocar
personagem/EV em cena, colocar suporte, colocar cenário (1 por turno), descartar
card, nocautear personagem desde o início do turno e comprar 1, usar Ação
Imprevista.

**Ajuste** — obrigatório, nesta ordem:

- *Ajuste de Energia:* descarregar de cada personagem/suporte até o número de
  cards carregados igualar a Energia Inicial;
- *Ajuste de Mão:* com mais de 7 cards na mão, descartar até ficar com 7 —
  **não será implementado** (decisão 9b).

**Combate** — duas etapas:

- *Antecipação:* o oponente vira o Jogador Ativo do turno e pode usar Ações de
  Antecipar;
- *Ataque:* o jogador do turno usa ações normais, de Antecipar e Imprevistas.

Cada personagem usa **uma ação por turno**; quem usou Ação Imprevista na
Preparação não age no Ataque.

**Mão inicial (regulamento simplificado):** cada jogador compra 10 cards. Se
tiver **um ou nenhum card de personagem**, pode revelar a mão e trocá-la por
outra do mesmo tamanho — **uma vez**.

---

## 3. Regra do grupo (a que vale no jogo)

### 3.1 Mão inicial e mulligan automático

1. Os dois jogadores compram **10 cartas**.
2. **Mulligan automático:** se a mão tiver **1 ou 0 cartas de Personagem**, o
   log registra *“Mulligan automático”*, as cartas voltam ao deck, embaralha e
   compra 10 de novo. Repete **sem limite** até a mão ter 2+ Personagens
   (decisão 3a). Cada repetição gera uma linha no log.
3. **Guarda de segurança:** limite técnico de 50 repetições (para não travar a
   partida com um deck degenerado); ao atingir, o jogo segue com a mão atual e
   loga um aviso.

### 3.2 Mulligan manual

Depois do automático, aparecem dois botões: **Ficar com a mão** e **Mulligan**.

Cada clique em Mulligan:

- devolve **só as cartas da mão** ao deck e embaralha (as cartas que já estão em
  Recursos **não** voltam — decisão do grupo);
- manda **2 cartas do topo** para Recursos/Descarte (é a mesma pilha);
- compra **2 cartas a menos** que a mão anterior;
- devolve os botões.

A conta fecha sempre em 10 cartas (mão + recursos):

| Repetição | Mão antes | Vão p/ Recursos | Compra | Mão depois | Recursos acumulados |
| :---: | :---: | :---: | :---: | :---: | :---: |
| 1ª | 10 | 2 | 8 | 8 | 2 |
| 2ª | 8 | 2 | 6 | 6 | 4 |
| 3ª | 6 | 2 | 4 | 4 | 6 |
| 4ª | 4 | 2 | 2 | 2 | 8 |
| 5ª | 2 | 2 | 0 | **0** | **10** |

Regras de parada:

- o jogador pode parar em qualquer momento clicando **Ficar com a mão**;
- com a mão em **0**, o jogo **começa automaticamente** com 10 cartas em
  Recursos (decisão 6b) — não há mais o que devolver, então o botão Mulligan
  desaparece;
- o contador de repetições aparece na tela (ex.: “Mulligan 3/5”);
- no multiplayer, **cada jogador faz o seu mulligan no seu tempo** e a fase só
  avança quando os dois aceitarem a mão (decisão 12).

### 3.3 Preparação do jogo (nova fase, antes da rodada 1)

- Qualquer jogador pode descartar **qualquer número de cartas** da mão, indo
  para **Recursos/Descarte** (decisão 7 — no projeto é a mesma pilha).
- Botão na tela: **Preparação — descartar cartas da mão**.
- Os dois jogadores decidem **ao mesmo tempo**, sem limite de quantidade
  (decisão 8a). A fase só termina quando **os dois** clicarem em **Pronto**.

### 3.4 Fases automatizadas

- **Contagem Regressiva:** se o jogador do turno tem **0 personagens em cena**,
  “tomba 1” = 1 carta do topo do deck → Recursos; **+1 para cada personagem do
  oponente** em cena; **+1 para cada carta nos prêmios do oponente**
  (decisões 1a e 2a — os extras **só** valem com 0 personagens). Roda também no
  primeiro turno (decisão 11a).
- **Compra:** primeiro turno do jogador inicial compra **0**; sem personagem,
  compra **1**; com personagem, compra **2**.
- **Preparação:** o jogador do turno faz suas ações (manual).
- **Ajuste:** cada personagem/suporte descarrega até a Energia Inicial; se tiver
  mais anexos que energia, **alerta** visual pedindo a retirada do excesso.
- **Antecipação:** o oponente pode usar ações.
- **Ataque:** o jogador usa ações; quando os **dois passarem**, o turno acaba.

### 3.5 Deck vazio

Se uma compra for exigida com o deck vazio, **o jogador perde a partida
imediatamente** (decisão 10c) — **a qualquer momento**: no mulligan, na Contagem
Regressiva, na Compra, no nocaute da Preparação e em efeito de carta. O
adversário recebe a vitória e o motivo vai para o log.

---

## 4. Desenho técnico

### 4.1 Máquina de estados

Proposta:

```
SETUP → MULLIGAN_AUTO → MULLIGAN_MANUAL → PREP_GAME
      → [ REG → DRAW → PREP → ADJ → ANT → ATK ] → (próximo jogador) → REG …
```

- `SETUP`, `MULLIGAN_AUTO`, `MULLIGAN_MANUAL` e `PREP_GAME` acontecem **uma vez**,
  antes da rodada 1, e envolvem os dois jogadores.
- O laço `REG…ATK` alterna por jogador, agora com `DRAW` separado.
- A fase vira **dado serializável** (`phase`, `step_index`, `turn_slot`,
  `first_turn`, `mulligan_count`), porque quem reconecta tem de cair no mesmo
  ponto. `CheckpointList.gd` mapeia os labels e precisa ganhar as fases novas.

Como está hoje, depois da reestruturação:

- O laço é `TURN_PHASES = ["REG", "DRAW", "PREP", "ADJ", "ANT", "ATK"]` e
  `get_steps_per_round()` devolve `TURN_PHASES.size() * 2` — doze passos, a
  segunda metade sendo o turno do outro jogador. `phase_for_step`, `turn_half`,
  `get_turn_owner_slot` e `get_actor_slot` derivam tudo de `step_index`
  (`ANT` é o passo do adversário do dono do turno).
- O mulligan automático e a janela manual **não** são passos do laço: a partida
  já começa no passo 0 com a bandeira `_mulligan_open`, e `advance_phase` se
  recusa a andar enquanto ela estiver aberta. Isso é o que mantém o passo 0
  (Contagem Regressiva) fiel à decisão 11a: a janela fecha e o primeiro passo é
  pago em seguida.
- `PREP_GAME` é a segunda bandeira (`_prep_game_open`), aberta no fechamento do
  mulligan e fechada quando os dois assentos clicam em Pronto. Ela segura o mesmo
  `advance_phase` e o mesmo `has_pending_phase_effect`, então a Contagem
  Regressiva continua sendo paga pelo primeiro passo, agora por quem fecha a
  preparação. Ficar "sem descartar nada" é o caminho padrão: a janela só exige a
  resposta, nunca um descarte.
- No hotseat a mesa segue quem age: o assento que ainda deve uma resposta
  (`_hand_to_seat_that_owes_an_answer`) ou o ator do passo seguinte
  (`_follow_turn_in_solo`, chamado antes de pagar o efeito automático para que a
  compra saia da mão certa). O jogador não precisa de "Controlar P2" para as
  janelas que já são dele.
- Quem reconecta tem de cair no mesmo ponto: `phase`, `round`, `step`,
  `starting_slot`, `mulligan_open`, `prep_game_open`, `mulligan_counts` e
  `effects_applied` viajam no estado público, e `_absorb_turn_state()` é o único
  lugar que os traz de volta — tanto em `mp_state` quanto no restore de checkpoint.
  As duas bandeiras são **copiadas** (dono é a autoridade); os contadores de
  mulligan e a marca de passos pagos são **fundidos**, porque cada cliente só
  escreve as entradas do próprio assento e um jogador que volta não pode refazer
  um passo que a mesa já pagou. `first_turn` continua derivado de `round`+`step`
  (`is_first_turn_of_match`), não serializado.

### 4.2 Onde cada regra vive

| Regra | Onde |
| :--- | :--- |
| Sequência de fases | `src/custom/Multiplayer.gd` (`PHASES`, `advance_phase`, `_advance_as_authority`) |
| Efeitos automáticos de fase | novo `src/custom/TurnRules.gd` (funções puras: estado → operações) |
| Aplicar movimento de carta | `src/core/table/TableActions.gd` (`_do_phase` em :608 já é o gancho) |
| Compra | `src/core/Hand.gd` (`draw_card` em :100) |
| Embaralhar | `Pile.shuffle_cards()` |
| Log | `src/custom/GameEvents.gd` (`record_system` :135, `record_local` :108) |
| Botões/etiqueta de fase | `src/custom/MatchHUD.gd` (`_on_advance_pressed` :504) |
| Estado público/reconexão | `Multiplayer._broadcast_public_state()` + `_remote_meta` |

`TurnRules.gd` fica **puro e testável**: recebe um dicionário (`personagens em
cena`, `cartas nos prêmios`, `mão`, `energia por personagem`, `primeiro turno`,
`repetições de mulligan`) e devolve operações
(`{"op": "topo_para_recursos", "n": 3}`). O `Multiplayer` (autoridade) aplica e
difunde. A regra passa a ser testável em unidade, sem montar mesa.

### 4.3 Mensagens novas no protocolo

- `mp_mulligan_request` / `mp_mulligan_state` (mão nova, recursos, repetição);
- `mp_setup_discard_request` (descartar N cartas da mão);
- `mp_setup_ready` (jogador terminou a preparação do jogo);
- `mp_phase_state` público passa a carregar `phase`, `turn_slot`,
  `mulligan_pending`, `first_turn` e `mulligan_count`.

Como ficou, depois das entregas do §9:

- O mulligan manual só precisa de `mp_mulligan_accept` (a decisão de um assento);
  a mão resultante não viaja, porque o mulligan automático é local e determinista
  pelo seed. A preparação usa `mp_prep_game_ready`, pelo mesmo molde.
- Não há `mp_setup_discard_request`: o descarte da preparação é um intent
  `descartar` comum, que já é validado, logado, desfeito e espelhado pelo
  caminho de sempre.
- O deck vazio é difundido por `mp_result` (assento que devia + quantidade), para
  que o cliente cujo deck acabou declare a própria derrota sem esperar o host.
- O estado público carrega `mulligan_open` e `prep_game_open`; `first_turn` é
  derivado, não serializado.

Regra de ouro: **só o anfitrião embaralha e compra**. O cliente recebe a mão
resultante. Se cada lado embaralhar com a própria semente, a divergência aparece
na primeira reconexão.

### 4.4 Determinismo

`cfc.game_rng` já é semeado por partida (`test_rng_seed`). Embaralhamento e
compras do setup usam o mesmo RNG, para que reconexão e replay reconstruam a
mesma mão.

---

## 5. UI

- **Overlay de mulligan:** botões **Ficar com a mão** / **Mulligan**, com
  contador de repetição e o texto do que vai acontecer (“2 cartas vão para os
  recursos, você compra 8”).
- **Preparação do jogo:** `PrepGamePanel` com mão/recursos do assento e o botão
  **Pronto**. O descarte em si é o arrasto normal da mão para a banda de Recursos
  (nada de seleção múltipla nova), e a janela não obriga descartar nada.
- **Ajuste:** selo de alerta no personagem com excesso de anexos + linha no log.
- **Fase:** `MatchHUD` mostra também `Mulligan`, `Descarte` e `Compra`, com as
  cores de `PHASE_COLORS`.
- **Fim por deck vazio:** overlay de vitória reaproveitada, com o motivo.
- **Hotseat:** a mesa acompanha sozinha o assento que precisa agir. Depois de
  **Ficar com a mão** / **Mulligan**, depois de **Pronto** e a cada mudança de
  passo, o assento que age assume a mesa — o P2 vê o próprio painel sem clicar em
  "Controlar P2". No passo de Antecipação isso troca para o adversário e volta no
  Ataque, porque é ele quem joga aquele passo.
- Tudo **mouse-only**, como manda a diretriz do projeto.

---

## 6. Etapas de implementação

Cada etapa termina com GUT verde e validação no F5. O commit entra na
`autoTurno`; nada vai para a `main` sem PR.

| # | Entrega | Teste |
| :--- | :--- | :--- |
| 1 | `TurnRules.gd` com as funções puras + unit tests | `tests/unit/test_turn_rules.gd` |
| 2 | `SETUP`: mão de 10 e mulligan automático (log, repetição, guarda de 50) | integração com deck fixo |
| 3 | `MULLIGAN_MANUAL`: overlay, tabela 10→8→6→4→2→0, parada em 0 | integração: mão, recursos e deck batem |
| 4 | `PREP_GAME`: descarte livre simultâneo para Recursos/Descarte | integração |
| 5 | `REG` automática (0 personagens, + por oponente, + por prêmio) | unit + integração |
| 6 | `DRAW` automática (0 no 1º turno, 1 sem personagem, 2 com) | integração |
| 7 | `ADJ` automático de energia + alerta de excesso | integração |
| 8 | Deck vazio → derrota | integração |
| 9 | Fechamento de turno (os dois passarem no ATAQUE) e troca de jogador | integração hotseat |
| 10 | Serialização/reconexão do estado novo | teste de reconexão |
| 11 | F5 com duas partidas completas (solo hotseat) | manual |

---

## 7. Decisões tomadas

| # | Pergunta | Decisão |
| :---: | :--- | :--- |
| 1 | “Tomba 1” = topo do deck → Recursos? | **Sim** |
| 2 | Extras da Contagem Regressiva só com 0 personagens? | **Sim, só com 0** |
| 3 | Quantas vezes o mulligan automático repete? | **Sem limite**, até 2+ Personagens |
| 4 | Repetição do manual manda +2 para recursos? | **Sim, +2 a cada repetição** |
| 5 | Quantas cartas compra nas repetições? | **Cai 2 por repetição** (8 → 6 → 4 → 2 → 0) |
| 6 | “Até ficar com a mão zerada” é literal? | **Sim** — em 0, começa com 10 em Recursos |
| 7 | Descarte da preparação vai para recursos ou descarte? | **Recursos e Descarte são a mesma pilha** |
| 8 | Os dois descartam juntos? Há limite? | **Sim, simultâneo, sem limite** |
| 9 | Ajuste de Mão (7 cartas)? | **Não implementar** |
| 10 | Deck vazio ao comprar? | **O jogador perde** |
| 11 | Contagem Regressiva no 1º turno? | **Roda normalmente** |
| 12 | Momento do mulligan no multiplayer | **Cada jogador no seu tempo**; a fase avança quando os dois aceitarem a mão |

---

## 8. Pendências fora deste plano

- Validar visualmente a tabela 10→8→6→4→2→0 no F5 antes de publicar.

---

## 9. Estado da implementação

Entregue na branch `autoTurno`, com testes automatizados verdes:

| Item | Onde | Teste |
| :--- | :--- | :--- |
| Regra pura (mulligan, REG, DRAW, ADJ, deck) | `src/custom/TurnRules.gd` | `tests/unit/test_turn_rules.gd` — 24 testes |
| Mulligan automático, local e assento oculto | `Multiplayer._resolve_auto_mulligan()` | `tests/integration/test_auto_mulligan.gd` |
| Sequência do mulligan manual | `Multiplayer.manual_mulligan_local()` | idem — 7 testes |
| Estado para a UI | `Multiplayer.get_mulligan_info()` | idem |

Detalhes de implementação que divergem do rascunho acima:

- O mulligan automático roda **localmente**, semeado por `seed + "|mulliganN"`,
  sem mensagem nova: os dois clientes chegam à mesma mão porque partem do mesmo
  seed. Só o mulligan **manual** é escolha do jogador.
- O assento oculto do hotseat repete o mesmo laço sobre os nomes das cartas
  (`_names_need_auto_mulligan`), com o RNG próprio daquele assento.
- A guarda de 50 repetições está ativa e loga aviso ao ser atingida.

Ainda não implementado:

nada. Os cinco itens do rascunho estão entregues; o que falta é validação manual
no F5 (item 11 da lista de etapas) e o teste de reconexão com duas janelas.

Entregues desde o rascunho acima:

1. **Overlay do mulligan manual no `MatchHUD`** — dois botões ("Descartar" e
   "Ficar com a mão") com o contador da tabela 10→8→6→4→2→0; o botão de
   descartar some com a mão em 0 (decisão 6b). O assento local responde por si
   (`accept_local_hand`), a janela fecha quando os dois aceitam (decisão 12) e o
   estado espelhado vem de `get_mulligan_info()`.
2. **`PREP_GAME`** — a janela de descarte livre entre o mulligan e a rodada 1. É
   a segunda bandeira da sessão (`_prep_game_open`), de dono a autoridade: o
   convidado só a espelha pelo estado público. Cada assento responde por si em
   `ready_local_prep_game()`; no hotseat a troca de assento limpa a resposta, do
   mesmo jeito que o mulligan. Descartar não pediu regra nova na mesa:
   `_validate_discard` já aceita mão → Recursos sem limite, e a janela é um portão
   da sessão, não uma restrição da tabela. O `PrepGamePanel` do `MatchHUD` mostra
   mão/recursos e o botão "Pronto" por `get_prep_game_info()`. A mensagem
   `mp_prep_game_ready` leva a resposta do convidado à autoridade, que fecha a
   janela e paga a Contagem Regressiva devendida. Dentro da janela a mesa só
   aceita `descartar`, `reordenar_mão` e `desfazer` (`SETUP_ALLOWED_VERBS`,
   alimentado por `setup_only_discard` no contexto): sem isso o titular do turno
   poderia colocar um Personagem em cena antes da Contagem Regressiva e mudar a
   própria conta. Testes:
   `tests/integration/test_prep_game.gd` — 13 testes.
3. **`REG`, `DRAW` e `ADJ` automáticos** — `TURN_PHASES` ganhou `DRAW` e o laço
   passou a ter 12 passos por rodada. Quem paga o passo é o cliente dono das
   cartas (`run_phase_effects`), marcado por `round:step` para nunca repetir;
   os gatilhos são o avanço de passo, a troca de assento no hotseat, o fechamento
   da janela de mulligan e a recepção do estado público. As operações vêm de
   `TurnRules.operations_for_phase` (puro) e cada movimento é um intent
   (`mandar_topo_para_recursos`, `comprar`, `descartar`), então tudo é validado,
   logado, desfeito e espelhado como numa jogada manual. O `Ajuste` descarrega o
   excesso (regra oficial: é obrigatório) em vez de só alertar.
   Testes: `tests/integration/test_turn_phases.gd` e `test_phase_effects.gd`.
4. **Derrota por deck vazio** — a mesa avisa `Multiplayer.declare_empty_deck_loss`
   quando um `comprar`/`mandar_topo_para_recursos` falha por `deck_insuficiente`
   ou `deck_vazio`. O assento que devia as cartas perde na hora, o adversário
   recebe a vitória no mesmo overlay usado pelos Prêmios (com o motivo na linha
   de baixo) e a partida termina nos dois clientes pela mensagem `mp_result`.
   Como `apply_intent` é o funil de clique, de fase automática e de script, a
   regra vale "a qualquer momento" (§3.5). Testes:
   `tests/integration/test_empty_deck.gd`.
5. **Serialização dos estados novos** — `mulligan_open`, `prep_game_open`,
   `mulligan_counts` e `effects_applied` entraram no estado público, e
   `_absorb_turn_state()` aplica tudo nos dois caminhos que devolvem um jogador à
   partida: o `mp_state` ao vivo e o restore de checkpoint. As bandeiras são
   copiadas (a autoridade é dona delas); contadores e marcas de passo são fundidos
   chave a chave, porque o cliente do outro assento é quem escreve as suas. Isso
   fecha o buraco de o passo automático ser pago duas vezes depois de uma
   reconexão. Testes: `tests/integration/test_prep_game.gd`
   (`test_a_resumed_seat_does_not_replay_a_paid_step`,
   `test_the_windows_travel_in_the_public_state`) e
   `test_auto_mulligan.gd` (`test_the_mulligan_ladder_travels_in_the_public_state`).
6. **Hotseat acompanha o assento que age** — `_hand_to_seat_that_owes_an_answer()`
   roda no fim de `accept_local_hand()` e `ready_local_prep_game()` e passa a mesa
   ao assento que ainda deve resposta; era o que faltava para o P2 ver o painel
   de mulligan/preparação sem apertar "Controlar P2". `_follow_turn_in_solo()`
   roda em `_advance_as_authority()` e `_record_prep_game_ready()` e passa a mesa
   ao ator do passo seguinte antes de pagar o efeito automático, então a compra e
   a contagem saem da mão certa. `swap_solo_seat()` deriva a resposta do assento
   (`_mulligan_accepts`/`_prep_game_accepts`) em vez de zerá-la, para um assento
   não responder duas vezes. Antecipação alterna duas vezes por turno, como manda
   a regra. Testes: `test_auto_mulligan.gd`
   (`test_the_hotseat_hands_the_mulligan_to_the_other_seat`) e
   `test_turn_phases.gd` (o passeio dos doze passos confere `my_slot` = ator).
