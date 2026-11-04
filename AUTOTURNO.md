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

Hoje `PHASES` é um array fixo de 5 fases repetido duas vezes
(`src/custom/Multiplayer.gd:45`) e `_advance_as_authority()`
(`src/custom/Multiplayer.gd:1278`) só incrementa o índice. Proposta:

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
- **Preparação do jogo:** botão **Preparação — descartar cartas da mão**, seleção
  múltipla na mão e **Pronto** para liberar a fase.
- **Ajuste:** selo de alerta no personagem com excesso de anexos + linha no log.
- **Fase:** `MatchHUD` mostra também `Mulligan`, `Descarte` e `Compra`, com as
  cores de `PHASE_COLORS`.
- **Fim por deck vazio:** overlay de vitória reaproveitada, com o motivo.
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

Ainda não implementado (depende de UI e da máquina de estados):

1. Overlay de dois botões do mulligan manual no `MatchHUD`.
2. `PREP_GAME` (descarte livre simultâneo antes da rodada 1).
3. `REG`, `DRAW` e `ADJ` automáticos fiados na sequência de fases.
4. Derrota por deck vazio.
5. Serialização/reconexão dos estados novos.
