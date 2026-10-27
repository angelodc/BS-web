# Planejamento do Multiplayer

Este documento reúne os requisitos e decisões confirmados para o multiplayer, separa o que já existe do que ainda precisa ser feito e registra as perguntas em aberto. As seções de requisitos e plano registram o planejamento original; o estado real da v1 está em [Implementação v1](#implementação-v1).

## Objetivo

Permitir uma partida local entre dois jogadores, em que ambos acompanhem ao vivo as ações um do outro no tabuleiro, vejam o cursor adversário e compartilhem a indicação da fase e do jogador ativo. O jogador que abre/inicia a sala é P1 e deverá atuar como servidor autoritativo do jogo.

## Requisitos confirmados

### Jogadores e partida

- A primeira versão é para dois jogadores, P1 e P2, em rede local.
- O menu deve permitir informar username e procurar ou cancelar uma partida.
- O jogador que abre/inicia a sala é o anfitrião e P1. Ele é a autoridade do estado para início, dados, fases e estado público; a validação de cada ação pelo anfitrião ainda não está implementada.
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

## Implementação v1

Implementada na branch `feature/multiplayer-v1` (a partir de `main`). A partida é LAN, para dois jogadores, e o anfitrião é quem cria a sala.

### Transporte e salas

- O relay é embutido no jogo ([src/custom/LocalRelay.gd](./src/custom/LocalRelay.gd)) e inicia automaticamente quando o endereço configurado aponta para a própria máquina (por exemplo `127.0.0.1:9080`). Em rede local, a instância do anfitrião escuta em `0.0.0.0:9080` e o convidado usa o IP da máquina do anfitrião. Não é necessário instalar Python para jogar na mesma máquina ou em LAN. Esse relay é um adaptador de desenvolvimento/LAN e não deve ser exposto à internet.
- O relay [tools/ws_relay.py](./tools/ws_relay.py) continua disponível como alternativa externa. Se já houver um relay escutando na porta local, o jogo reutiliza esse relay em vez de abrir outra porta.
- Para o modo online existe um relay dedicado em Node.js ([relay/](./relay/README.md)), com `join_room` por código, `protocol_version`, `GET /healthz`, `GET /rooms`, limites por IP/conexão, heartbeat e allowlist de `Origin`. Ele usa o mesmo protocolo JSON e ainda não foi publicado; o plano está em [ONLINE_HOSTING.md](./ONLINE_HOSTING.md).
- Ambos aceitam `create_room`, `join_room`, `find_match`, `cancel_match`, `rejoin_room`, `create_resume_room`, `join_resume_room` e `leave_room`, atribuem `H` (anfitrião/P1) a quem cria a sala e `C` (convidado/P2) a quem entra.
- No build web o relay embutido não sobe (`LocalRelay` retorna cedo com `OS.has_feature("web")`). O cliente usa `wss://relay.exemplo.com` por padrão (placeholder de deploy), aceita `?relay=HOST` para testes e trata `localhost`/`127.0.0.1` como relay local via `ws://`.
- Mensagens acima de 12.000 caracteres são divididas em partes `mp_chunk` pelo cliente e remontadas pelo destinatário; o relay externo aceita frames de até 4 MiB.
- Uma sala com pelo menos um jogador conectado não expira, atendendo à espera sem limite. Quando os dois se desconectam, a sala fica disponível para `rejoin_room` por 120 segundos.
- O relay não valida jogadas nem mantém estado oficial: ele apenas forma salas e encaminha mensagens.

### Menu, preparação e início

- O menu permite informar username e endereço do relay (padrão desktop `127.0.0.1:9080`), criar sala, **entrar com código**, procurar partida, cancelar e abrir **Iniciar jogo salvo**. Username e endereço ficam salvos entre execuções no desktop.
- No build web o campo de endereço do relay fica oculto e o padrão é `wss://`; `?room=CODIGO` preenche o campo **Entrar com código** e `?relay=HOST` sobrescreve o endereço do relay para testes locais. O código da sala do anfitrião aparece no HUD de preparação.
- Os dois jogadores precisam de usernames diferentes. O relay recusa entrar na sala de um anfitrião com o mesmo username, comparando sem diferenciar maiúsculas e minúsculas. Erros de identidade e de sala aparecem em um diálogo com botão **OK** e também no status do menu.
- O botão **Decks salvos** no menu principal lista os decks locais e inicia o jogo com o escolhido; a importação por link continua disponível como a última opção do menu.
- A preparação mostra a biblioteca local de decks salvos e seleciona automaticamente o último deck usado. Se ainda não houver um último deck memorizado e existir apenas um deck salvo, ele é usado. Decks importados do BSDB ficam em cache e são reutilizados sem baixar novamente. O botão `INICIAR` só habilita quando os dois jogadores escolheram decks com exatamente 60 cartas; qualquer um dos dois pode iniciá-lo.
- Ao iniciar, o anfitrião sorteia dois d6 (repetindo em empate), publica os resultados e quem começa, gera uma semente de embaralhamento e envia tudo ao convidado. Cada cliente monta o próprio deck de forma determinística, embaralha e compra 10 cartas.
- Se a preparação falhar em um dos clientes, o anfitrião envia `mp_abort` para que os dois encerrem a sessão em vez de um ficar preso no início.
- O jogo usa uma resolução lógica fixa de `1280x720` em 16:9 (`window/stretch/mode="2d"` com `aspect keep`), então os dois clientes compartilham a mesma geometria de tabuleiro mesmo com janelas ou monitores de tamanhos diferentes. A cena é renderizada em 1280x720 e escalada para a janela; em telas fora de 16:9 aparecem barras pretas. No desktop a janela abre em 1280x720 sem bordas (não em fullscreen); `F11` alterna para fullscreen. Para abrir a segunda instância em 960x540, use `run-second-instance.cmd` ou `BS_WINDOWED=1`.
- O handshake troca tamanho de tela, janela e viewport lógica dos dois jogadores. A preparação mostra essas medidas e o log registra ambas; se as proporções de tela forem diferentes, o log avisa que o jogo vai letterboxar em vez de desalinhar cartas e cursor.

### Autoridade, fases e desconexão

- O anfitrião é autoritativo para início, dados, semente, sequência de fases e estado público canônico. As ações recebidas são validadas estruturalmente antes de serem aplicadas; não há aprovação do anfitrião para cada jogada (ver limitações).
- A v1 usa a sequência por jogador `REG → PREP → ADJ → ANT → ATK`, sem `BUY`. A rodada conta 10 passos e só incrementa depois que os dois completam a sequência; o ciclo recomeça por quem venceu o d6.
- O indicador central mostra rodada, etapa, jogador ativo, quem começa, resultados dos dados e as cores `PREP` (branco), `ANT` (vermelho) e `ATK` (verde).
- Após o início, se um jogador cair, o cliente restante congela o jogo e mostra a espera sem limite. Ele pode encerrar manualmente ou aguardar a reconexão do oponente na mesma sala.

### Visibilidade e acompanhamento

- Apenas `hand` e `deck` são ocultos. `board`, `scenario`, `resources` e `prizes` são públicos e espelhados em coordenadas normalizadas. As cartas do oponente são invertidas em 180° e mantidas dentro da área do campo superior; o Cenário remoto fica centralizado no slot de Cenário.
- Só pode existir um Cenário ativo entre os dois campos. Ao colocar um Cenário, o Cenário ativo do oponente vai para o Recursos/Descarte do dono. Cada jogada leva uma marca de ordem (relógio lógico) para que a jogada mais recente vença, inclusive quando os dois jogadores jogam quase ao mesmo tempo; em empate, o Cenário do anfitrião permanece. A regra também é reaplicada na retomada de checkpoints, quando o Cenário local é devolvido ao slot `Cenário Ativo`.
- O slot de Cenário do jogador ocupa exatamente a área de uma carta em campo (`150x210` × `0,55` = `82,5x115,5`), sem a borda extra das grades comuns.
- Cartas ocultas do oponente são representadas por contadores e posições sem identidade, face ou nome; a identidade só é transmitida quando a carta passa para uma zona pública.
- O cursor do oponente é enviado a 10 Hz, desenhado espelhado (rotação de 180°) na metade superior, some após 3 segundos sem movimento e exibe apenas o username, sem informação da carta sob o ponteiro.
- O tabuleiro espelhado exibe o rótulo `CAMPO DO OPONENTE - <username>` e ignora interação do jogador local.

### Checkpoints e retomada

- A cada troca de fase, os dois clientes salvam um checkpoint local em `user://Checkpoints/<game_id>/<sequência>.json`.
- Cada checkpoint contém o estado público e dois envelopes privados (mão e deck de cada jogador), ofuscados com uma chave derivada de SHA-256 do username. Isso é proteção fraca contra leitura casual, **não criptografia**.
- **Iniciar jogo salvo** lista as partidas locais. Quem hospeda cria a sala de retomada; o outro entra com o username participante. Se o save não identificar os dois usernames, a sala é recusada em vez de trocar participante.
- Os clientes trocam manifestos e retomam a sequência mais recente presente e íntegra nos dois lados (mesma partida, sequência e checksum público).
- Se a cópia escolhida estiver corrompida, o outro cliente envia a cópia íntegra. Se a cópia falhar no carregamento, o convidado pede a cópia do anfitrião. Se não houver checkpoint íntegro comum, a retomada é abortada com explicação e a opção de iniciar uma nova partida.
- Se todos os arquivos locais de uma partida estiverem ilegíveis, a lista mostra a entrada como somente entrada (`join_only`): o jogador pode entrar na sala de retomada do oponente, mas não pode hospedar.
- Alterar o username tenta reproteger os checkpoints locais com o novo nome. Checkpoints que não puderem acompanhar a mudança — por exemplo, quando o novo nome já identifica o outro jogador ou o envelope está ilegível — permanecem com o username anterior e não bloqueiam a alteração.

### Arquivos principais

- [src/custom/Multiplayer.gd](./src/custom/Multiplayer.gd) — sessão, autoridade, início, fases e retomada.
- [src/custom/MultiplayerSync.gd](./src/custom/MultiplayerSync.gd) — espelhamento, privacidade e cursor remoto.
- [src/custom/LocalRelay.gd](./src/custom/LocalRelay.gd) — relay embutido para endereços locais.
- [src/custom/Rede.gd](./src/custom/Rede.gd) — WebSocket, pareamento, reconexão e divisão de mensagens.
- [src/custom/CheckpointStore.gd](./src/custom/CheckpointStore.gd) — gravação, envelopes e validação.
- [src/custom/CheckpointList.gd](./src/custom/CheckpointList.gd) — lista de saves para hospedar ou entrar.
- [src/custom/DeckCatalog.gd](./src/custom/DeckCatalog.gd) — listagem, validação e memória do último deck salvo.
- [src/custom/MatchHUD.gd](./src/custom/MatchHUD.gd) — preparação, indicador de fases, dados, resoluções e status.
- [src/custom/DisplayMode.gd](./src/custom/DisplayMode.gd) — janela desktop em 1280x720 (sem bordas quando necessário), 960x540 para o segundo cliente (`BS_WINDOWED=1`) e alternância de fullscreen com `F11`.
- [tools/ws_relay.py](./tools/ws_relay.py) — relay LAN de salas em Python.
- [relay/](./relay/README.md) — relay Node.js para o modo online (`join_room`, limites, `/healthz`, `/rooms`).
- [online/](./online/README.md) — Function e página de lobby do Netlify (proxy de `/rooms`).

## Como testar

### Automatizado

- Suite GUT do multiplayer: `tests/integration/test_multiplayer_lobby.gd`, com 17 testes e 72 asserções. Execute pelo painel GUT do editor ou pela cena `tests/cli/tests.tscn` com janela (a execução completa com `--no-window` pode travar neste ambiente).
- Testes do relay Node.js: `cd relay && npm test` (21 testes com clientes `ws` reais, incluindo `join_room`, sala cheia, código inválido, expiração, protocolo errado, limites e reconexão). Executados e passando em 27/10/2026.
- Testes do relay Python (legado): `python tools/test_ws_relay.py` (14 testes). Neste ambiente não há Python instalado, então eles foram revisados estaticamente, mas não executados.
- O relay embutido foi validado em headless com dois clientes WebSocket reais: criação/busca de sala, encaminhamento, queda e reconexão, além da sala de retomada e recusa de terceiro.
- `src/custom/CGFMain.tscn` foi aberto em modo headless sem erros de script nos módulos de multiplayer.

### Manual, com dois clientes

1. Para testar na mesma máquina, não é preciso iniciar nada: o relay embutido sobe no primeiro cliente que criar ou procurar a sala. Para jogar em máquinas diferentes, use o IP da máquina do anfitrião e deixe a porta 9080 liberada no firewall. Opcionalmente, execute `python tools/ws_relay.py` em uma máquina central.
2. Abra duas instâncias do jogo. Na mesma máquina, use `run-second-instance.cmd`, que define `BS_WINDOWED=1` e abre a segunda em 960x540. O primeiro cliente (`F5`) abre em 1280x720 sem bordas; `F11` alterna para fullscreen. No menu, informe usernames diferentes e o mesmo endereço (`127.0.0.1:9080` na mesma máquina).
3. Jogador 1 usa **Criar Sala**; jogador 2 usa **Procurar Partida**. Confirme que ambos entram na mesma partida e que o indicador mostra os usernames corretos.
4. Ao entrar na preparação, confirme que o último deck usado já está selecionado e que **Decks salvos** lista o deck importado. Escolham decks de 60 cartas. Confirme que `INICIAR` só habilita com os dois decks válidos, que qualquer jogador consegue iniciar e que os dois veem os mesmos dados, o mesmo vencedor e as mesmas 10 cartas iniciais (cada um vê a própria mão).
5. Avancem as fases e confirme rodada, jogador ativo, cores e incremento de rodada após os dois completarem a sequência.
6. Movimentem cartas entre zonas públicas e confirme o espelhamento; mantenham cartas na mão/deck e confirme que o oponente vê apenas contadores, nunca a identidade. Confira o cursor remoto com username e o desaparecimento após 3 segundos.
7. Derrube um cliente e confirme o congelamento do outro e a reconexão na mesma sala. Encerre manualmente para testar a saída durante a espera.
8. Fechem os dois clientes e usem **Iniciar jogo salvo** para retomar: teste a cópia íntegra, uma cópia local corrompida e o caso sem checkpoint íntegro comum.

## Limitações conhecidas da v1

- As jogadas são enviadas diretamente entre os clientes e validadas apenas estruturalmente pelo receptor. O anfitrião não aprova cada ação antes de ela ser aplicada; ele é autoritativo para início, dados, fases e estado público canônico.
- O modelo confia no cliente do anfitrião: um cliente modificado pode falsificar dados, semente ou estado.
- A proteção dos dados ocultos nos saves é obfuscação derivada do username, não criptografia. O username é público.
- Alterar o username reprotege apenas as cópias locais; as cópias do oponente continuam com o username antigo, então a retomada após renomear um jogador não é reconciliada automaticamente. Saves que não podem ser renomeados sem conflito continuam válidos apenas com o username anterior.
- Se todos os checkpoints locais de uma partida estiverem ilegíveis, o jogador só pode entrar na sala de retomada do oponente, não hospedar.
- O relay embutido só inicia para endereços locais; um endereço remoto continua exigindo um relay externo. Se outro processo já ocupa a porta, o jogo tenta usá-lo; se ele não falar este protocolo, a conexão falha com aviso no HUD.
- O relay Node.js e o lobby do Netlify existem no repositório, mas ainda não foram publicados; o build HTML5 local já foi gerado. A integração do cliente web (`join_room`, `?room=`, `?relay=`, padrão `wss://` e bloqueio do `LocalRelay` no navegador) está implementada e foi validada localmente com dois navegadores até o início da partida (Fase 4 de [ONLINE_HOSTING.md](./ONLINE_HOSTING.md)).
- Não há transferência de anfitrião, reconexão automática, espectadores nem limite configurável da frequência do cursor (fixo em 10 Hz).

## Roadmap para o modo online

A v1 é LAN, mas o código deve ser tratado como a base de um jogo online; o relay embutido é apenas o adaptador de desenvolvimento. O cliente já usa um endereço WebSocket configurável e o protocolo de mensagens é separado do transporte, então o modo online não exige reescrever o cliente. O que muda é quem hospeda o relay e quem é a autoridade da partida.

### Princípios

- Nenhuma lógica de partida pode depender de `127.0.0.1`, de o relay rodar no cliente do anfitrião ou de os dois jogadores estarem na mesma rede.
- O protocolo deve ser versionado e independente do transporte local; mensagens de estado precisam sobreviver a reconexão e reenvio.
- Online não reutiliza a confiança no cliente do anfitrião nem a proteção de saves derivada do username.

### Etapas

1. **Protocolo e sessão**
   - Incluir `protocol_version` no handshake e recusar versões incompatíveis com mensagem clara.
   - Usar IDs de sessão/jogador atribuídos pelo servidor, token de reconexão rotativo e códigos de erro estáveis.
   - Numerar ou confirmar mensagens de estado para reaplicar após queda e limitar a frequência por conexão.
2. **Relay/servidor dedicado**
   - Serviço `wss://` com TLS no proxy reverso, matchmaking, salas, presença, reconexão e expiração.
   - Modelo relay-only: os dois clientes conectam para fora; para este jogo de cartas não é necessário P2P/STUN.
   - Autenticação de conta ou sessão assinada, username único e rate limiting.
   - Persistência de sessões/partidas para sobreviver a reinício do servidor.
3. **Autoridade**
   - O servidor passa a ser autoritativo para dados, semente, ordem de fases, estado canônico e validação de jogadas.
   - O cliente envia intenções; o servidor responde com estado e projeções. O anfitrião deixa de ser confiável.
   - Mão e deck continuam privados, mas o servidor envia a cada jogador apenas a própria projeção, em vez de manter as duas mãos nos clientes.
4. **Retomada**
   - Checkpoints canônicos no servidor, retomada por sessão/token e não por manifestos locais.
   - Saves locais com envelopes continuam como fallback offline/LAN.
5. **Identidade e privacidade**
   - Contas/username verificado; a chave derivada do username não serve para internet.
   - Definir política de dados e logs para não expor mãos, decks ou checkpoints.
6. **Operação**
   - Relay dedicado local para desenvolvimento, depois staging e produção; métricas, logs, limites e reconexão.
   - Testar dois clientes contra esse relay em localhost, além dos testes atuais do relay embutido.

### O que já está alinhado

- Cliente WebSocket configurável para `ws://` e `wss://`, sem URL fixa no código; no web o padrão é `wss://` e o `LocalRelay` não sobe.
- Protocolo JSON separado do transporte e relay que apenas forma salas/encaminha mensagens.
- `LocalRelay` só inicia para endereço local; um relay remoto continua sendo usado sem alterações.
- Checkpoints locais e retomada já existem para o modo LAN/offline.
- Relay Node.js ([relay/](./relay/README.md)) com `join_room` por código, `protocol_version`, `/healthz`, `/rooms`, limites por IP/conexão, heartbeat, allowlist de `Origin` e 21 testes com clientes reais.
- Function e página de lobby do Netlify ([online/](./online/README.md)) prontas para rodar localmente; o lobby só repassa `/rooms` e não guarda estado.

### O que precisa mudar antes de abrir para internet

- Publicar o relay com TLS/`wss://` e validar dois navegadores em redes diferentes.
- Publicar o build HTML5 já gerado e validar a integração (`join_room`, `?room=`, `?relay=`, `wss://` e bloqueio do `LocalRelay`) com navegadores em redes diferentes, além de publicar o relay e o lobby.
- Autoridade no servidor: hoje o anfitrião continua autoritativo e as jogadas são validadas apenas estruturalmente no receptor.
- Identidade verificada (username é público) e proteção real dos dados ocultos, não obfuscação.
- Persistência de sessões/partidas para sobreviver a reinício do relay. O relay atual mantém as salas apenas em memória.

## Estado técnico observado antes da implementação (histórico)

> Registro do que existia antes da v1; foi superado por [Implementação v1](#implementação-v1). Mantido apenas como histórico.

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

## Decisões de projeto

- **Checkpoint íntegro (resolvido na v1):** cada checkpoint contém os dois envelopes privados e é validado antes do uso; se uma cópia estiver corrompida, a cópia íntegra do outro jogador é transferida. Se nenhuma cópia íntegra comum existir, a retomada é bloqueada com explicação.

## Fora do escopo confirmado

Não foram definidos neste planejamento: partidas pela internet, autenticação de contas, reconexão automática, transferência do anfitrião durante uma partida ativa, espectadores ou limite/frequência exatos de mensagens do cursor. A direção para o modo online está no roadmap acima; essas decisões continuam fora do escopo da v1 e devem ser detalhadas antes de serem tratadas como requisitos.
