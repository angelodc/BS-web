# Planejamento do Multiplayer

Este documento reúne os requisitos e decisões confirmados para o multiplayer, separa o que já existe do que ainda precisa ser feito e registra as perguntas em aberto. É planejamento: nada descrito como futuro aqui deve ser entendido como implementado.

## Objetivo

Permitir uma partida local entre dois jogadores, em que ambos acompanhem ao vivo as ações um do outro no tabuleiro, vejam o cursor adversário e compartilhem a indicação da fase e do jogador ativo. O jogador que abre/inicia a sala é P1 e deverá atuar como servidor autoritativo do jogo.

## Requisitos confirmados

### Jogadores e partida

- A primeira versão é para dois jogadores, P1 e P2, em rede local.
- O menu deve permitir informar username e procurar ou cancelar uma partida.
- O jogador que abre/inicia a sala é o anfitrião e P1. Ele deverá ser a autoridade do estado e validar as ações, embora isso ainda não esteja implementado.
- O username fica salvo entre execuções. Um menu de opções permitirá alterá-lo.

### Preparação e início

- Depois do pareamento, a partida permanece em preparação até que os dois jogadores tenham um deck com exatamente 60 cartas.
- Antes do início, o botão central mostra **Decks para novos jogos** e abre a lista local de links de decks salvos para o jogador escolher seu deck.
- A lista deve mostrar o nome/título do deck e permitir selecionar um deck pelo link salvo. O título deve ser obtido dos dados do BSDB quando disponível.
- Quando os dois jogadores selecionarem decks com exatamente 60 cartas, o botão central muda para `INICIAR`. Qualquer um dos jogadores pode acioná-lo.
- Ao iniciar, o botão aciona uma função de sorteio no jogo do anfitrião, que gera os dois resultados de d6. Em caso de empate, a função sorteia novamente para ambos.
- Mostrar os dois resultados dos dados e destacar quem começa. Os dois decks são embaralhados e cada jogador compra automaticamente 10 cartas.
- O anfitrião envia os resultados gerados ao outro jogador. O modelo confia no jogo do anfitrião; não impede que alguém modifique o cliente ou falsifique o resultado deliberadamente.
- Se o anfitrião desconectar antes de concluir o sorteio, manter o início pendente e continuar quando ele voltar.

### Visibilidade das cartas

- **Somente o deck e a mão de cada jogador ficam ocultos para o adversário.**
- Todas as outras zonas e cartas são visíveis para os dois jogadores, inclusive Recursos/Descarte e Prêmios.
- Ao movimentar cartas entre zonas, a informação que se torna pública deve aparecer no campo do adversário. A carta não deve ser revelada enquanto estiver na mão ou no deck.
- Ações em zonas ocultas podem continuar sendo comunicadas por texto sem revelar a identidade da carta.

### Acompanhamento ao vivo

- Além do registro textual existente, o adversário deve ver as ações e movimentos no campo espelhado.
- O jogador também deve ver o cursor do adversário movendo-se ao vivo, identificado pelo username.
- O cursor não pode revelar o nome, a face ou outra informação de uma carta que esteja na mão ou no deck.

### Fases e turnos

- Deve haver um botão/indicador central entre os dois jogadores.
- O fluxo completo de cada jogador inclui:
  1. `REG` — Contagem Regressiva: início do turno; verificar vitória/derrota, efeitos de início de turno e presença de personagens em cena para ganho de recursos.
  2. `BUY` — Compra: abastecer a mão comprando cartas do topo do deck. **Adiada para a v2 do multiplayer**; não faz parte da sequência inicial da v1.
  3. `PREP` — Preparação: baixar personagens, suportes e cenários; capacitar personagens existentes.
  4. `ADJ` — Ajuste: validar o estado do jogo e processar efeitos globais automáticos. A mão não tem limite; esta fase não descarta cartas por exceder um máximo.
  5. `COMB` — Combate: bloco que começa com `ANT` do adversário/defensor e depois permite `ATK` do jogador ativo.
- Na v1, a sequência de cliques do indicador é: jogador que começa (definido pelo d6) faz `REG` → `PREP` → `ADJ` → `ANT` do adversário → `ATK` do jogador ativo; em seguida, o outro jogador faz `REG` → `PREP` → `ADJ` → `ANT` do adversário → `ATK` do jogador ativo. `BUY` será inserido na v2.
- `COMB` descreve a fase de combate; `ANT` e `ATK` são as ações/janelas indicadas pelo botão durante esse bloco. As cores já solicitadas são:
  - `PREP` — Preparação, branco.
  - `ANT` — Antecipação, vermelho.
  - `ATK` — Ataque, verde.
- O jogador indicado pela fase/ação clica no botão central para avançar. O indicador é informativo e não bloqueia outras ações do jogo.
- A rodada só é considerada completa quando os dois jogadores terminarem sua sequência, incluindo `ATK` no combate. O contador aumenta então, e a sequência recomeça pelo jogador definido como inicial pelo d6.

### Queda e retomada

- Se um jogador desconectar depois do início, o jogo entra em espera: o jogador restante não pode mexer nas cartas, no deck ou no estado da partida. Ele pode esperar ou encerrar manualmente; não há limite de espera definido.
- A cada troca de fase, ambos os clientes salvam automaticamente um checkpoint local.
- Deve existir a opção **Iniciar jogo salvo**. O jogador que carregar o save cria/hospeda uma sala de retomada; o outro jogador entra nessa sala e carrega seu checkpoint correspondente.
- O save deve identificar os dois usernames da partida original. Se alguém tentar retomá-lo com outro jogador, avisar quais dois usernames devem entrar e não substituir um participante.
- Se os dois saves tiverem checkpoints diferentes, retomar o checkpoint mais recente que ambos compartilham, identificado pela mesma partida, rodada e fase. Se não houver checkpoint comum, não retomar automaticamente; avisar os jogadores e pedir intervenção.
- O anfitrião que carregar o save assume a autoridade da partida retomada.
- O username escolhido por cada jogador também será usado para proteger os próprios dados ocultos (mão/deck) nos saves. Não haverá frase secreta separada nem conta online nesta etapa.
- Ao alterar o username, reproteger os saves locais com o novo username antes de concluir a mudança.
- **Limite de segurança:** username é visível ao adversário e salvo nas configurações do jogo; portanto, não é uma chave secreta e não oferece criptografia segura contra alguém que leia o save ou os dados locais. Registrar como proteção fraca/obfuscação contra exposição casual, não como confidencialidade real.
- Se um checkpoint estiver corrompido, tratar o checkpoint íntegro disponível como oficial e continuar a partir dele. A implementação precisa verificar que esse checkpoint contém ou consegue recuperar os dados privados necessários dos dois jogadores; se não contiver, não pode tratar a retomada como completa.
- Se não houver nenhum checkpoint íntegro, bloquear a retomada, informar que o save não pode ser restaurado e oferecer iniciar uma nova partida.

## Estado técnico observado

- O cliente Godot usa WebSocket para comunicar-se com o relay.
- O relay atual forma partidas de dois clientes, atribui os papéis `H` e `C`, encaminha mensagens ao oponente e avisa sobre desconexão. Esses papéis não implementam autoridade do jogo.
- Atualmente não há sala criada pelo anfitrião: o relay atribui `H` ao jogador que já estava na fila e `C` ao jogador que completa o par. Isso precisa ser alinhado com a definição escolhida de anfitrião/P1.
- O importador de deck atual consulta o título do deck no BSDB e guarda em cache local os dados e a URL de origem. Não foi encontrada uma lista/menu para salvar links e escolher decks importados em partidas futuras.
- O username não é secreto; qualquer proteção derivada dele é fraca. Não apresentar isso como criptografia segura.
- O espelhamento existente envia atualizações de cartas durante o arraste e trata alguns movimentos, rotações e ações ocultas. O cursor do mouse não é enviado.
- O código atual considera `hand`, `deck` **e `prizes`** como zonas ocultas. Isso diverge do requisito confirmado neste documento: no comportamento desejado, **Prêmios são visíveis**. Essa diferença precisa ser corrigida antes de considerar a privacidade alinhada ao requisito.
- O relay encaminha mensagens de sincronização; não valida jogadas, não mantém o estado oficial e não sincroniza completamente RNG/deck.

## Plano sugerido de trabalho

As etapas abaixo são uma proposta de ordem para implementar e validar os requisitos. Não significam que o usuário autorizou começar a implementação.

### 1. Alinhar o modelo da partida

- Fazer a busca/pareamento produzir uma sala cujo anfitrião/P1 seja inequivocamente o jogador que abriu a partida.
- Definir como o segundo jogador se conecta ao anfitrião e qual será a função do relay no transporte.
- Fazer o anfitrião validar as ações dos dois jogadores, inclusive as próprias, e publicar o estado aceito.
- Implementar a geração dos dois d6 no jogo do anfitrião quando o botão de início for acionado; enviar e exibir os resultados para ambos, repetindo o sorteio em empate.
- Documentar que esse sorteio é autoritativo segundo o cliente do anfitrião, mas não resistente à adulteração do cliente.
- Se o anfitrião desconectar durante o sorteio, preservar o início pendente e retomá-lo quando ele voltar.

### 2. Implementar preparação e início

- Persistir username localmente e adicionar a opção de alterá-lo.
- Criar uma biblioteca local de links de decks salvos, exibindo o título obtido do BSDB e permitindo escolher um deck para um novo jogo.
- No período de preparação, mostrar o botão **Decks para novos jogos** para abrir essa biblioteca; após ambos escolherem decks válidos de 60 cartas, mudar o botão para `INICIAR`.
- Validar que ambos os decks tenham exatamente 60 cartas antes de habilitar `INICIAR`; qualquer jogador pode iniciar após essa condição.
- Implementar o sorteio dos dois d6 no jogo do anfitrião, repetição em empate, apresentação dos resultados, embaralhamento dos dois decks e compra automática de 10 cartas para cada jogador.

### 3. Corrigir e validar a visibilidade

- Ajustar a política de zonas para ocultar somente mão e deck.
- Garantir que Prêmios e todas as demais zonas sejam representados com suas cartas visíveis.
- Validar que a identidade da carta só seja transmitida ao sair de mão/deck para uma zona pública.
- Cobrir os estados iniciais da partida e mudanças de zona, evitando que snapshots revelem cartas ocultas.

### 4. Completar o espelhamento visual e adicionar cursor remoto

- Fazer com que movimentos e mudanças visíveis apareçam no tabuleiro espelhado, além da caixa de texto.
- Enviar a posição do cursor enquanto ele se move e desenhá-lo no tabuleiro do oponente com o username.
- Mapear coordenadas para o tabuleiro em resoluções diferentes; definir frequência de atualização e tratamento de cursor fora do tabuleiro e desconexão.
- Não transmitir informações da carta sob o ponteiro.

### 5. Adicionar fases, turnos e contador de rodadas

- Após o início e a compra das mãos, o indicador passa de `INICIAR` para a fase inicial do vencedor do dado.
- Exibir e sincronizar a fase e o jogador ativo. O jogador indicado pela fase clica para avançar.
- Por enquanto, fases são informativas: não bloqueiam ações do jogo.
- Começar a rodada 1 na Preparação do vencedor do dado; incrementar a rodada quando a sequência retornar à Preparação desse jogador.
- Testar o ciclo sem adicionar regras de ação específicas às fases.

### 6. Tornar o anfitrião autoritativo e validar a partida

- Implementar um fluxo em que ações propostas sejam validadas pelo anfitrião e o estado aprovado seja refletido nos dois clientes.
- Evitar que mensagens do cliente sejam tratadas como estado oficial antes da validação.
- Em caso de desconexão depois do início, congelar o jogo para o jogador restante até ele encerrar ou o oponente retornar; não permitir ações de jogo enquanto estiver sozinho.
- Testar ações simultâneas, estado divergente, alterações de informações ocultas, desconexão e retomada.

### 7. Salvar e retomar

- Salvar automaticamente um checkpoint local para cada jogador em toda troca de fase.
- Criar a opção `Iniciar jogo salvo`: quem carregar o save hospeda a sala de retomada e o outro entra com seu checkpoint correspondente.
- Identificar no save os dois usernames originais; se outro jogador tentar entrar, mostrar os participantes esperados e não substituir ninguém.
- Se um checkpoint estiver corrompido, usar o checkpoint íntegro disponível como oficial, desde que os dados privados necessários dos dois jogadores possam ser recuperados.
- Usar o username como proteção fraca/obfuscação dos dados ocultos; ele é público e não oferece criptografia segura.
- Localizar o checkpoint mais recente compartilhado pelos dois jogadores originais usando identificador da partida, rodada e fase; se nenhum existir, parar e pedir intervenção.
- Se não houver checkpoint íntegro, bloquear a retomada, explicar que o save não pode ser restaurado e oferecer iniciar uma nova partida.
- Testar encerramento manual durante a espera, queda durante a gravação e retomada dos dois clientes.

Só considerar a partida pronta após testes reais com dois clientes e confirmação de sincronização e privacidade.

## Decisões ainda necessárias antes da implementação

- **Checkpoint íntegro:** projetar como o checkpoint íntegro disponível contém ou recupera os dados privados dos dois jogadores quando a cópia do outro estiver corrompida.

## Fora do escopo confirmado

Não foram definidos neste planejamento: partidas pela internet, autenticação de contas, reconexão automática, transferência do anfitrião durante uma partida ativa, espectadores ou limite/frequência exatos de mensagens do cursor. Essas decisões devem ser discutidas antes de serem tratadas como requisitos.
