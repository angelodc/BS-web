# Perguntas: jogar sem mouse (posições fixas, comandos e teclado)

Este questionário já foi respondido e as respostas estão incorporadas em
[ACOES_SEM_MOUSE.md](./ACOES_SEM_MOUSE.md). Ele fica no repositório como
registro das perguntas originais.

**Ditado por voz está fora de escopo.** As perguntas 24, 33, 34 e 35 ficam
anuladas: voz não será planejada nem implementada agora. As perguntas 22 e 40
foram respondidas: **22 → i** (nenhuma ação pede confirmação; a confirmação é
sempre do comando) e **40 → nenhuma** (nenhuma regra simplificada do Battle
Scenes precisa voltar agora).

**Contexto em um parágrafo.** É um jogo de cartas em Godot inspirado no Battle
Scenes. Hoje o jogador move tudo arrastando com o mouse. A ideia é dar a cada
carta uma posição fixa e nomeada na mesa (mão, campo, cenário, recursos,
prêmios) e transformar cada movimento em uma ação validada, para que o jogo
possa ser comandado por atalho de teclado, por script de teste e por texto —
sem mouse. As respostas definem as regras e a interface dos comandos.

## A. Mesa, assentos e turno

**1 ★** Quantos jogadores a mesa precisa suportar?
a) 2 jogadores
b) 2 a 4 jogadores
c) 1 contra uma IA
d) outro: ______

**2 ★** Quem pode agir em cada momento?
a) Só o assento do turno
b) Qualquer assento, a qualquer momento
c) Depende da fase (ex.: compra em uma fase, ações em outra)

**3 ★** O que encerra o turno?
a) Um comando/botão "passar"
b) "Avançar fase" até voltar ao começo
c) Acabarem as ações obrigatórias
d) Outro: ______

**4** No modo hotseat (um jogador controlando os dois lados na mesma tela),
"Controlar P1/P2" também deve ser um comando de texto?
a) Sim
b) Não, só o botão
c) Sim, mas com confirmação

**5 ★** O lado espelhado do oponente é só informativo?
a) Sim, nunca é alvo de ação do jogador local
b) Não; algumas ações podem atingir cartas dele (quais? ______)
c) O jogador local pode mexer em tudo do oponente, como um juiz

## B. Zonas e posições fixas

**6 ★** No campo, a posição (coluna e fileira) muda alguma regra ou é só
organização visual?
a) Só organização
b) Muda regra (alcance, linha de frente, alvo)
c) Muda regra só para algumas cartas (quais? ______)

**7 ★** Quando uma carta entra no campo, quem escolhe o slot?
a) O jogador, sempre
b) O jogo, automaticamente do centro para fora
c) O jogo escolhe, mas o jogador pode trocar depois

**8 ★** Personagens sempre na fileira da frente e suportes atrás?
a) Sim, sempre
b) Não, qualquer fileira
c) Depende da carta (ex.: suporte de frente permitido)

**9** Se a fileira da frente estiver cheia e entrar um personagem:
a) A jogada é bloqueada
b) O personagem empurra outro para trás
c) O campo ganha uma coluna nova
d) Outro: ______

**10** Qual o limite de slots do campo?
a) Fixo (quantos? ______)
b) Cresce com a largura da tela
c) Cresce conforme as cartas entram
d) Outro: ______

**11 ★** A zona de Recursos é a mesma pilha do descarte (como hoje)?
a) Sim, uma pilha só, chamada Recursos
b) Não; descarte e recursos são zonas separadas
c) Outro: ______

**12** Quantas cartas de recursos devem ficar visíveis na grade?
a) 6 (como hoje: 3×2)
b) 8 ou mais
c) Todas, com rolagem
d) Outro: ______

**13 ★** A ordem dos recursos importa?
a) Não, só a quantidade
b) Sim; o topo é o próximo a ser pago
c) Sim, mas a ordem é fixa por outro critério: ______

**14 ★** Quando uma carta vai para os Prêmios do oponente, em qual slot ela
entra?
a) Primeiro slot livre, em ordem
b) Sempre no topo da pilha
c) No slot que o jogador escolher
d) Outro: ______

**15 ★** Cenário:
a) Um ativo por jogador
b) Um ativo para a mesa toda (os dois disputam o mesmo)
c) Vários simultâneos
d) Outro: ______

**16 ★** O que acontece com o cenário substituído ou derrotado?
a) Vai para o descarte do dono
b) Vai para os recursos do dono
c) Vira prêmio do oponente
d) Outro: ______

**17 ★** A mão tem posições fixas e nomeadas (1..N da esquerda para a direita)?
a) Sim; o jogador pode dizer "mão 3" no console de texto
b) Não; a mão é só uma quantidade e o jogador escolhe pelo nome
c) Sim, e o jogador pode reordenar manualmente

**18** Ao comprar, a carta entra:
a) No fim da mão
b) No começo
c) Em ordem por custo/tipo
d) Outro: ______

**19** Limite de mão e excedente:
a) 10; descarta a carta comprada
b) 10; descarta a mais antiga
c) Sem limite
d) Outro: ______

**20 ★** Recursos e habilidades anexados a um personagem: a ordem importa?
a) Sim; o topo é o último anexado
b) Não
c) Sim, mas por tipo (ex.: recursos embaixo, habilidades em cima): ______

**21 ★** Uma Habilidade pode ser jogada sem estar sob um personagem ou suporte?
a) Nunca
b) Só se a própria carta permitir
c) Sim, fica no campo como qualquer carta
d) Outro: ______

## C. Ações, custos e alvos

**22 ★** Quais ações devem pedir confirmação antes de aplicar? (marque quantas
quiser)
a) Ferir
b) Nocautear
c) Enviar aos Prêmios do oponente
d) Trocar recurso
e) Embaralhar
f) Descartar
g) Passar fase
h) Todas
i) Nenhuma; a confirmação é sempre do comando

**Resposta: i.** Nenhuma ação pede confirmação antes de aplicar; quem comanda
responde pelo comando que mandou.

**23 ★** Pagamento de custo:
a) Automático quando o número de recursos é exatamente o custo (como hoje)
b) O jogador sempre escolhe quais recursos
c) Automático, mas com opção de desfazer
d) Outro: ______

**24 — anulada.** Pergunta sobre ditado; o modo ditado não será planejado nem
implementado agora.

**25** Nos scripts de teste, as cartas são referenciadas por:
a) Nome canônico
b) Apelido/abreviação
c) Id da definição (ex.: "electro_001")
d) Os três, com o nome como padrão

**26** Duas cartas com o mesmo nome na mão:
a) O jogo pergunta qual posição
b) Usa sempre a primeira
c) Cria apelidos automáticos ("Electro 1", "Electro 2")
d) Outro: ______

**27** Desfazer:
a) Não precisa
b) Uma ação (o último comando)
c) Qualquer ação até o fim do turno
d) Outro: ______

**28** O log de ações deve aparecer para os jogadores?
a) Sim, completo
b) Sim, mas só o que o próprio lado vê
c) Só em modo debug
d) Outro: ______

## D. Testes e automação

**29 ★** Formato do script de teste:
a) Português legível: `jogar "Electro" no campo frente 2`
b) JSON com ids de slot: `{"op":"play","card":"Electro","zone":"field","slot":"front:2"}`
c) Os dois; o português vira JSON por baixo
d) Outro: ______

**30 ★** O que um teste deve verificar?
a) O estado final (zona, slot e contagem de cada carta)
b) Também a ordem visual na tela
c) Também o texto do log
d) Tudo acima

**31** A partida de teste precisa ser sempre determinística (deck fixo e seed)?
a) Sim, sempre
b) Só quando o teste pedir
c) Não importa

**32** O executor de scripts precisa rodar dentro do GUT?
a) Sim, para aproveitar os testes atuais
b) Não; pode ser um script separado
c) Os dois

## E. Comandos e produto

**33–35 — anuladas.** Perguntas sobre ditado por voz; o modo ditado não será
planejado nem implementado agora.

**36** Deve haver atalhos de teclado equivalentes aos comandos?
a) Sim, para tudo
b) Só para navegação e confirmação
c) Não

**37** Quem é o público do modo sem mouse?
a) Acessibilidade (jogar sem mouse por limitação física)
b) Jogar sem olhar para a tela
c) Automação e testes
d) Todos

## F. Prioridade e regras do jogo

**38 ★** O que vem primeiro?
a) Posições fixas + ações validadas
b) Console de comandos de texto
c) Teclado para todas as ações
d) Corrigir o bug de posição/contagem dos recursos

**39** O modo script pode alterar uma partida real (e servir de "trapaça") ou só
roda em modo de teste?
a) Só em modo de teste
b) Pode em partida real, mas fica registrado no log
c) Pode em partida real, sem restrição

**40** Alguma regra do Battle Scenes que este jogo simplificou precisa voltar
junto com o modelo sem mouse? (ex.: custo, alvos, linha de frente, limite de
recursos)
Resposta livre: **nenhuma por agora.** As simplificações atuais (pagamento
automático no custo exato, fileiras sem efeito de regra, sem limite de recursos,
prêmios valendo energia) ficam como estão.

## Folha de respostas

Preenchida com as respostas que foram incorporadas ao plano:

```text
1: a   2: c   3: b   4: a   5: b
6: a   7: c   8: b   9: d  10: c
11: a 12: a  13: a  14: a  15: b
16: b 17: c  18: b  19: c  20: c
21: b 22: i  23: a  24: d  25: c
26: c 27: b  28: a  29: b  30: d
31: a 32: c  33: —  34: —  35: —
36: a 37: c  38: a  39: b  40: nenhuma

Observações: 33–35 anuladas (ditado fora de escopo).
```
