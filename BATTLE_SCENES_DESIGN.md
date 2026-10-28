# 📓 Caderno de Design - Battle Scenes Web
> Espaço para anotações de lógica, mecânicas e mapeamento técnico.

---

## 🧠 Lógica de Regras Traduzidas para Código

### 0. Campo de jogo (campo visual para 2 jogadores)
*   Organizar o tabuleiro em três faixas horizontais:
    *   Superior: campo espelhado do oponente (Deck, Cena, Cenário, Prêmios, Recursos/Descarte e Mão apenas visuais).
    *   Central: duas linhas de campo do jogador interativo, com `[Deck] [Cena] [Cenário] [Prêmios]` e `[Recursos / Descarte]`.
    *   Inferior: Mão do jogador, em uma faixa menor que as áreas de campo.
*   O espaço superior representa visualmente o campo do oponente; o campo interativo do jogador atual fica na faixa central. A Cena usa uma grade dinâmica (3 colunas × 2 linhas por jogador no tamanho atual, com mínimo de 2 colunas).
*   As zonas do oponente são majoritariamente visuais. As cartas públicas de Cena e o Cenário do oponente podem ser arrastados; Mão, Deck e Recursos/Descarte remotos não aceitam interação direta (Recursos e Prêmios têm apenas **Ver**).
*   Recursos/Descarte ficam visíveis para todos. A pilha não se expande por clique; durante a entrada de um Personagem/Suporte que exige anexos, ela abre automaticamente como uma segunda mão para seleção. A mão normal continua sendo a zona separada de cartas na mão.
*   A Cena contém Personagens/Suportes e um único espaço de Cenário ativo. Ao colocar um Cenário novo, o Cenário ativo anterior vai para Recursos/Descarte.
*   Existe apenas um Cenário ativo por partida, mesmo com os dois campos visuais na mesa. Quando um jogador coloca um Cenário, o Cenário ativo do oponente vai para o Recursos/Descarte do dono. Não há limite de Cenários jogados ao longo da partida: cada novo Cenário substitui o anterior. Na rede, a jogada carrega uma marca de ordem para que a jogada mais recente vença; em empate, o Cenário do anfitrião permanece.
*   O slot de Cenário do jogador tem exatamente o tamanho da carta em campo (`150x210` na escala `0,55`, ou seja, `82,5x115,5`), sem a borda extra usada pelas grades comuns.
*   Cada jogador tem sua própria área de Prêmios, com slot de `120x168` (escala `0,8`), o mesmo empilhamento de Recursos e apenas o botão **Ver**. O contador mostra a soma do campo `ENERGIA` dos personagens derrotados ali, não a quantidade de cartas; `ENERGIA_EXTRA` não entra no cálculo. Os Prêmios são formados pelas cartas de personagem do adversário: quando um personagem é nocauteado, a carta vai para a área de Prêmios do oponente, não para a do dono.
*   Recursos e descarte permanecem juntos; não criar um Limbo separado neste momento.
*   A disposição em três faixas, a reserva visual do oponente, a grade dinâmica e a seleção automática de anexos estão implementadas. A interface e as interações ainda precisam de validação visual no Godot.

### 1. Sistema de Capacitação (Rotação)
No Battle Scenes físico, as cartas inclinam para indicar uso. No jogo, a capacitação será acionada pelo menu de ações exibido ao passar o mouse sobre um personagem em campo (não por um clique direto na carta):
*   **Posição central:** `0°`; os botões **Capacitar** e **Incapacitar** ficam disponíveis.
*   **Inclinada à esquerda:** `-90°`; fica disponível apenas **Capacitar**.
*   **Inclinada à direita:** `+90°`; fica disponível apenas **Incapacitar**.
*   O menu aparece ao passar o mouse sobre personagens em campo. **Incapacitar** move a carta 90° à esquerda e **Capacitar** move 90° à direita; não há rotação além de `-90°` ou `+90°`.
*   Personagens mantêm os botões **Capacitar**, **Incapacitar**, **Flip** e **Escudo**. Escudo abre opções para adicionar `1`, `2` ou `3` e retirar `1`, `2` ou `3`, limitadas à quantidade existente. A contagem é armazenada como token `escudo` na carta. Os demais tipos mantêm **T** e **Flip**; **V** e a rotação **@** foram removidos.
*   A rotação inclinada é tratada pelo código customizado do jogo, pois o framework-base limita sua rotação geral a múltiplos de 90°.
*   As cartas da coleção de demonstração estão marcadas como personagens via `_tipo`, para que os controles apareçam durante a validação local. Os dados de cada carta real também precisarão preencher esse campo.
*   **Validação:** `is_on_board` e o estágio têm tipos explícitos, os caminhos da fonte Comfortaa foram corrigidos e os controles de incapacitação/escudo estão implementados. A mecânica foi validada no fluxo de uso local.

### 2. O Fluxo da Pilha de Energia (Mecânica de Anexos)
*   Antes de colocar um Personagem ou Suporte da Mão em Cena, verificar se Recursos/Descarte contém cartas suficientes para o valor de `ENERGIA` da carta. Uma carta de `ENERGIA` 3 exige três cartas anexadas para entrar em Cena; sem recursos suficientes, a entrada não pode ser concluída. A validação foi implementada.
*   Ao colocar um Personagem ou Suporte em Cena, abrir automaticamente a segunda mão de Recursos para o jogador escolher por clique as cartas que serão anexadas sob a carta principal. O popup fecha quando a quantidade exigida for escolhida; cancelar devolve a carta principal à Mão.
*   As cartas anexadas ficam empilhadas para baixo, sob a carta principal, mostrando apenas 5% da borda inferior de cada anexo. O deslocamento visual de cada pilha usa o offset definido na própria carta anexada; a carta principal permanece totalmente visível por cima e mantém os controles normais de jogo.
*   Não há botão dedicado para remover vida no Personagem: os Recursos anexados podem ser retirados manualmente. A pilha Recursos/Descarte tem um botão **Trocar**; ao acioná-lo, o jogador escolhe uma carta disponível da pilha e depois o anexo de um Personagem em Cena que será substituído. O anexo substituído volta para Recursos/Descarte como carta disponível. Os botões genéricos de visualizar, ordenar e embaralhar ficam ocultos nessa pilha, que não abre por clique; a seleção automática de anexos durante a entrada em Cena permanece disponível.
*   Anexos não devem girar 90° junto com a carta principal quando esta for capacitada/incapacitada; a rotação de cartas anexadas é bloqueada.
*   A quantidade de cartas anexadas representa a energia carregada/vida atual do Personagem.
*   **Cálculo de Dano:** quando um herói recebe dano, remover a quantidade correspondente de cartas anexadas e enviá-las ao Recursos/Descarte do dono. **Nocaute:** quando as energias anexadas zerarem, todas as cartas anexadas voltam ao descarte do dono e a carta do personagem vai para a área de Prêmios do adversário. A carta mantém o jogador de origem como dono, mas passa a ser mantida pelo adversário; a soma de `ENERGIA` dessa área usa a energia impressa do personagem, não os anexos. O nocaute de **Suporte** está implementado; o dano e o nocaute de **Personagem** com remoção de anexos e envio aos Prêmios, além da checagem de vitória, permanecem pendentes.
*   A regra de entrada está implementada e validada; a disposição visual ainda precisa de validação no Godot.

### 3. Deck e Mão
*   Os controles de demonstração do topo para reunir cartas no Deck ou em Recursos/Descarte foram removidos. No Deck do jogador, os controles são **Embaralhar**, **Clarividência** e **Procurar**.
*   **Clarividência** abre opções para espiar 1, 2, 3 ou outra quantidade de cartas do topo. As cartas reais aparecem viradas para cima no campo por alguns segundos e retornam ao topo do Deck na ordem original.
*   **Procurar** apresenta as cartas do Deck sem duplicar nomes. Ao escolher uma, a seleção fecha, a carta aparece virada para cima no campo por alguns segundos e depois vai para a Mão.
*   A Mão não tem limite de cartas e seu contador mostra somente a quantidade. Na mão, o clique na metade esquerda da carta a envia para Recursos/Descarte; o clique na metade direita joga a carta conforme o tipo (Personagem/Suporte vão para a Cena, Cenário para o slot de Cenário e Habilidade para o descarte). O clique só age quando não houve arraste.
*   O botão **Ver** em Recursos/Descarte abre a lista de cartas nessa pilha.

### 4. Multiplayer (LAN v1 e preparação do modo online)
*   O menu solicita username e endereço do relay, oferece **Criar Sala**, **Entrar com código**, **Procurar Partida** (cancelável pelo mesmo botão) e **Iniciar jogo salvo**. Quem cria a sala é o anfitrião/P1 (`H`); quem entra é o convidado/P2 (`C`). No build web o campo de endereço fica oculto, o padrão é `wss://` e `?room=CODIGO` preenche o código da sala.
*   Na mesma máquina ou na LAN não é preciso iniciar nada: o relay embutido sobe automaticamente no primeiro cliente que criar/procurar sala e escuta em `0.0.0.0:9080`. Para jogar em máquinas diferentes, use o IP privado da máquina do anfitrião com a porta `9080` (`127.0.0.1:9080` funciona apenas na mesma máquina). `python tools/ws_relay.py` continua disponível como relay externo opcional.
*   O relay pareia dois jogadores por partida e encaminha mensagens somente ao oponente daquela partida. Ao sair um jogador, o outro recebe o aviso de desconexão. Se um cair depois do início, o cliente restante congela a partida e espera sem limite, podendo encerrar manualmente; a reconexão usa `rejoin_room` na mesma sala.
*   O espelhamento replica posições durante o arraste, rotação, movimentos e estados visíveis no campo do oponente. Apenas Mão e Deck ficam ocultos (contadores sem identidade); Cena, Cenário, Recursos/Descarte e Prêmios são públicos. O cursor do oponente é enviado a 10 Hz, desenhado espelhado com o username, some após 3 s sem movimento e não transmite a identidade de cartas ocultas.
*   **Autoridade da partida:** o anfitrião é autoritativo para início, sorteio do d6, semente, sequência de fases e estado público canônico; as ações recebidas são validadas estruturalmente. Ainda não há aprovação de cada jogada pelo anfitrião, então um cliente modificado pode falsificar dados ou estado. O relay Node.js (`relay/`) apenas pareia e transporta; o plano de evolução está em [ONLINE_HOSTING.md](./ONLINE_HOSTING.md) e o estado detalhado em [MULTIPLAYER.md](./MULTIPLAYER.md).
*   **Fases e rodadas:** cada jogador realiza `REG` (verificações de início), `PREP` (baixar cartas/capacitar), `ADJ` (validar o estado e processar efeitos globais) e `COMB`. Em `COMB`, o adversário/defensor faz `ANT` antes de o jogador ativo declarar `ATK`. Na v1, o indicador percorre a sequência completa do jogador inicial definido pelo d6 e depois a do outro; a rodada termina quando ambos concluírem `ATK`. A compra `BUY` fica para a v2. A mão continua sem limite, portanto `ADJ` não descarta cartas por exceder um máximo. O indicador é informativo e não bloqueia ações por fase.
*   **Checkpoints:** a cada troca de fase os dois clientes salvam um checkpoint local em `user://Checkpoints/`. **Iniciar jogo salvo** cria uma sala de retomada e os clientes usam o checkpoint íntegro mais recente comum aos dois. A proteção dos dados ocultos é ofuscação derivada do username, não criptografia.
*   **Modo online:** o relay Node.js dedicado já existe em [relay/](./relay/README.md) (mesmo protocolo, `join_room` por código, limites, `/healthz`, `/rooms`, 21 testes), mas ainda não foi publicado. O lobby no Netlify e a integração do cliente web (`join_room`, `?room=`, `?relay=`, padrão `wss://` e bloqueio do `LocalRelay` no navegador) estão implementados e o build HTML5 local foi validado com dois navegadores; faltam a partida completa e a publicação (Fase 4 de [ONLINE_HOSTING.md](./ONLINE_HOSTING.md)).

---

## 🔗 Notas da API e Banco de Dados (BSDB)

### Padrão de Nomenclatura das Pastas Locais
Para testar os IDs locais na pasta `C:\Users\doug\Projetos\bsdb-imagens`, as siglas das coleções oficiais são:
*   `bsca` = Confronto Aracnídeo (Ex: *Aberração Klyntar* é `BSCA_004.png`)
*   `bsaq` = Ascensão e Queda
*   `bsds` = Despertar Sombrio
*   `bset` = Evolução Tática

### Estrutura dos Dados de Cartas (BSDB)
*   A referência local dos dados é `C:\Users\doug\Projetos\bsdb-imagens\dados\cards.json`.
*   O campo `TIPO` identifica a categoria da carta (por exemplo, `Personagem`); mapear esse valor para `_tipo` nas propriedades internas do framework. Não confundir com `Type` nas cartas de demonstração, que escolhe uma cena/cor.
*   O campo `IMAGEM` contém o caminho relativo à raiz do repositório de imagens. Para a CDN, concatenar esse valor a `https://raw.githubusercontent.com/inimig0r/bsdb-imagens/refs/heads/main`.
*   As cartas do deck de teste usam o valor `IMAGEM` como caminho relativo e carregam o scan completo da carta em tempo de execução pela CDN; o cache local fica em `user://CardImages/`. Os arquivos de imagem não são copiados para este repositório.
*   **Importação futura por URL:** Dentro do jogo, o jogador poderá informar a URL pública de um deck no formato `https://battlescenes.vercel.app/deck/{id}`. O jogo deverá resolver a lista do deck e carregar os dados e as imagens das cartas diretamente do BSDB/CDN, sem depender de uma cópia local completa da coleção. A lista local de teste atual guarda os IDs BSDB das cartas para facilitar essa integração. O formato da API/resposta remota ainda precisa ser confirmado na implementação.

### Ideias de Melhorias Futuras (Backlog)
*   [ ] Adicionar um efeito sonoro de papel/carta sendo arrastada.
*   [ ] Criar um botão "Girar Mesa" para o jogador poder ver o campo sob a perspectiva do oponente.
*   [ ] Colocar um efeito visual de brilho (Glow) ao redor das cartas que têm ações disponíveis no turno atual.
