# 🦸‍♂️ Battle Scenes Web - Painel de Controle e Tarefas
> **Ambiente de Desenvolvimento do Douglas**
> Caminho do Projeto: Criado a partir do fork de `db0/godot-card-game-framework`
> Caminho das Imagens (Local): `C:\Users\doug\Projetos\bsdb-imagens`
> Documento de Arquitetura e Regras: Ver `BATTLE_SCENES_DESIGN.md`

---

## 🕹️ 1. Diretrizes do Projeto

### Como vamos conduzir o desenvolvimento
*   Antes de cada etapa, alinhar o plano e esclarecer decisões pendentes com o Douglas.
*   Usar este arquivo para acompanhar prioridades, tarefas, decisões e progresso; detalhar regras e decisões técnicas em `BATTLE_SCENES_DESIGN.md`.
*   Atualizar os documentos quando uma decisão ou mudança de progresso justificar, sem registrar suposições como decisões confirmadas.

### A. Filosofia de Controles (Mouse-Only)
O jogo será **100% jogável apenas com o mouse** (ou toque na tela no mobile).
*   **Movimentação:** Mecânica de Arrastar e Soltar (Drag & Drop) nativa do framework.
*   **Ações:** Menu de ações ao passar o mouse sobre personagens em campo; capacitar/incapacitar serão as primeiras opções, sem comandos de teclado.

### B. Arquitetura de Imagens (CDN Comunitária)
*   **Em Desenvolvimento Local:** Os arquivos em `C:\Users\doug\Projetos\bsdb-imagens` servem como referência de IDs, nomes de arquivos e testes rápidos de ícones.
*   **No Jogo Final (Navegador):** A Godot não armazenará imagens localmente para evitar problemas de copyright. O nó `HTTPRequest` fará o download das cartas em tempo real usando a CDN do GitHub:
    `https://raw.githubusercontent.com/inimig0r/bsdb-imagens/refs/heads/main[IMAGEM]`
*   **Dados das cartas:** Usar `dados/cards.json` no repositório local de referência. O campo `TIPO` identifica categorias como `Personagem` e será mapeado para `_tipo` nas propriedades internas do framework; `IMAGEM` fornece o caminho relativo à raiz das imagens para montar a URL da CDN.

---

## 📝 2. Lista de Tarefas (Checklist de Desenvolvimento)

### Inspeção inicial e ordem sugerida
*   O repositório já contém `project.godot`, o framework, um tabuleiro de demonstração e testes automatizados; a etapa de importação não precisa ser presumida como trabalho futuro.
*   O framework já oferece comportamentos de rotação e anexos, e o deck de demonstração já compra uma carta ao clique. A primeira etapa deve adaptar e validar esses recursos para as regras do Battle Scenes, não recriá-los sem necessidade.
*   A primeira tarefa confirmada é a capacitação pelo menu de hover, usando os dados locais: mapear `TIPO` para `_tipo` e preservar a lógica de arraste do framework.
*   Ordem sugerida para a Fase 1: capacitação pelo menu; anexos e contador de energia; dano, nocaute, prêmios e vitória. Multiplayer e deploy ficam para depois da validação do jogo local.
*   A sequência das demais tarefas continua sujeita a alinhamento antes de cada etapa.

### 🃏 Fase 1: Mecânicas Únicas do Battle Scenes (Singleplayer Local)
*   [x] **Campo de jogo (2 jogadores, oponente visual):** O tabuleiro usa três faixas: exibição do oponente no topo, duas linhas de campo do jogador no meio e a Mão em uma faixa menor embaixo. O campo interativo do jogador atual fica no meio; as cartas públicas do oponente aparecem viradas 180° e as cartas de Cena/Cenário dele podem ser arrastadas. A Cena contém Personagens/Suportes e um único Cenário ativo; um novo Cenário envia o anterior a Recursos/Descarte. Recursos ficam visíveis para todos e, ao clicar, abrem em uma segunda mão para selecionar anexos. Prêmios são uma área de uma carta por jogador, com o mesmo empilhamento de Recursos, apenas o botão **Ver** e contador da soma de `ENERGIA` dos personagens derrotados (sem `ENERGIA_EXTRA`). Limbo segue junto de Recursos/Descarte.
    *   **Estado:** Implementados o layout de três faixas, a grade dinâmica da Cena (3 colunas × 2 linhas por jogador no tamanho atual; mínimo de 2 colunas), as zonas espelhadas do oponente, os botões **Ver** para Recursos e Prêmios remotos e o arraste das cartas de Cena/Cenário do oponente. Os Prêmios usam `120x168` com escala `0,8` e o rótulo `Energia` soma `ENERGIA`. A expansão de Recursos por clique, a exigência de `ENERGIA` para Personagens/Suportes e a seleção automática de anexos seguem implementadas. Cancelar a seleção devolve a carta principal à Mão. Testes automatizados de grade, pilhas e multiplayer passam; a validação visual no Godot com dois clientes ainda está pendente.
*   [x] **Sistema de Capacitação pelo Menu de Ações:** Ao passar o mouse sobre um personagem em campo, exibir apenas as ações válidas de capacitar/incapacitar entre `-90°`, `0°` e `+90°`, conforme `BATTLE_SCENES_DESIGN.md`.
    *   **Estado:** Cartas de demonstração marcadas como personagens; `Capacitar`/`Incapacitar` alternam posições `-90°`/`0°`/`+90°` e mostram apenas a ação oposta nas posições inclinadas; `Escudo` disponível para personagens. Validação concluída no fluxo de uso local.
    *   **Correção adicional:** As duas cenas do tabuleiro apontavam para um caminho incorreto da fonte Comfortaa; os caminhos agora correspondem ao arquivo existente em `fonts/comfortaa/`.
*   [x] **Compra de Cartas por Clique:** Configurar o contêiner do `Deck` para enviar uma carta para a mão sempre que for clicada.
*   [x] **Ações do Deck e da Mão:** Adicionar embaralhar, Clarividência e Procurar no Deck; deixar a Mão sem limite, enviar cartas para Recursos/Descarte com duplo clique e permitir visualizar essa pilha.
*   [x] **Fluxo de Entrada em Cena com Energia e Anexos:** Ao colocar Personagem/Suporte da Mão em Cena, verificar `ENERGIA`, abrir Recursos automaticamente, permitir escolher anexos por clique e cancelar a seleção devolvendo a carta principal à Mão. Validado.
*   [x] **Exibição de Anexos e Troca:** Cartas anexadas empilhadas para baixo sob a carta principal, com 5% da borda inferior de cada anexo visível; a carta principal fica por cima. Anexos não giram com a carta principal. Botão **Trocar** em Recursos/Descarte funcionando para substituir anexos de Personagem.
*   [ ] **Contador de Energia sobre Personagem:** Criar um contador numérico sobre o Personagem mostrando a quantidade de energias carregadas.
*   [ ] **Lógica de Dano, Nocaute e Vitória:**
    *   [ ] Criar função para tirar energias carregadas quando o personagem sofrer dano e mandá-las para o descarte do dono.
    *   [ ] Validar Nocaute: quando as energias zerarem, devolver as cartas anexadas ao descarte do dono e mover a carta do personagem para a área de Prêmios do adversário, não para a do dono.
    *   [ ] Checar Vitória: quando a soma da energia inicial (`ENERGIA`) dos personagens na área de Prêmios de um jogador chegar a 15, disparar a tela de vitória desse jogador.

### ✅ Base Funcional Validada
*   [x] **Deck → Mão → Cena**
*   [x] **Verificação de energia para entrada em cena**
*   [x] **Seleção de anexos**
*   [x] **Cancelar caso falhe**
*   [x] **Capacitação e incapacitação por menu de ações**

> Observação: a regra de “1 recurso por turno” foi removida do escopo atual e não deve permanecer como tarefa ativa.

### 🧱 Fase 2: Infraestrutura Básica & Interface Visual
*   [x] **Importar Projeto:** Fork do framework aberto no Godot Engine, com o tabuleiro customizado em `src/custom/`.
*   [x] **Configurar Resolução (`CFConst.gd`):** Resolução lógica `1280x720`, `CARD_SIZE` `150x210`, escala de campo `0,55` e escala da mão `0,5`.
*   [x] **Criar Conexão HTTP (CDN do Amigo):** `CFControl.gd` monta a URL da CDN (`https://raw.githubusercontent.com/inimig0r/bsdb-imagens/refs/heads/main/cards/oficial`) e baixa as imagens por `HTTPRequest`, com cache em `user://CardImages/`.
*   [x] **Carregar Deck por Link do BSDB:** A opção de importar link (`https://battlescenes.vercel.app/deck/...`) baixa a lista, os dados e as imagens das cartas e salva o deck no catálogo local. O deck Resgate Aracnídeo abaixo continua como lista local de teste.
*   [x] **Montar o Tabuleiro 2D:** Zonas essenciais posicionadas em três faixas (oponente, campo com duas linhas e Mão), incluindo Deck, Recursos/Descarte, Cenário e Prêmios.

### 🌐 Fase 3: Multiplayer Simples (Espelhamento via WebSockets)
*   [x] **Username e busca de partida na LAN:** O menu solicita username e endereço do relay, e o botão **Procurar Partida** coloca o jogador em uma fila de duas pessoas. O relay separa partidas, atribui identidades e cancela a busca pelo mesmo botão.
*   [x] **Relay WebSocket (`Rede.gd`, `LocalRelay.gd` e `tools/ws_relay.py`):** Godot 3 usa mensagens JSON em WebSocket. Na mesma máquina ou na LAN não é preciso iniciar nada: o relay embutido sobe no primeiro cliente que criar/procurar sala (escuta em `0.0.0.0:9080` e o convidado usa o IP da máquina do anfitrião). `python tools/ws_relay.py` continua disponível como relay externo. O relay só encaminha mensagens entre os dois membros de cada partida e não deve ser exposto à internet.
*   [x] **Relay online em Node.js (`relay/`):** Relay dedicado para o modo online, com o mesmo protocolo JSON, `join_room` por código, `hello`/`protocol_version`, `GET /healthz`, `GET /rooms`, limites por IP/conexão, heartbeat e allowlist de `Origin`; 21 testes com clientes `ws` reais passam. Falta publicar em um provedor com TLS (Fase 4). Plano em [ONLINE_HOSTING.md](./ONLINE_HOSTING.md).
*   [x] **Sincronizar ações (espelhamento):**
    *   [x] Arrastar: a posição na Cena replica no campo visual do oponente.
    *   [x] Rotação: capacitação/incapacitação replica no oponente.
    *   [x] Ações ocultas: mão e deck vão virados para baixo; o oponente vê recados como "Comprou carta" e "Baixou recurso". Recursos em cena revelam a carta.
    *   **Estado:** Protótipo LAN para dois jogadores; o relay pareia e isola conexões. O anfitrião é autoritativo para início, d6, semente e fases, mas o jogo ainda não valida cada jogada antes de aplicá-la.
*   [x] **Mostrar o cursor do adversário ao vivo:** A posição do ponteiro é enviada a 10 Hz e desenhada espelhada na metade do oponente com o username, usando coordenadas normalizadas (funciona com resoluções diferentes). O cursor some após 3 s sem movimento e não carrega informação da carta sob o ponteiro.
*   [x] **Exibir movimentos do oponente no campo espelhado:** As ações e mudanças de estado do adversário aparecem visualmente na metade espelhada, além do registro textual, com mão e deck preservados como contadores ocultos.
*   [x] **Adicionar indicador central de fases e turnos:** Cada jogador realiza `REG` (início e verificações), `PREP` (baixar cartas e capacitar), `ADJ` (validar estado e efeitos globais) e `COMB` (combate). No bloco `COMB`, o adversário/defensor realiza `ANT` antes do jogador ativo declarar `ATK`. O botão identifica o jogador e a etapa atual; `PREP` é branco, `ANT` vermelho e `ATK` verde.
    *   **Sequência da v1:** jogador que começa pelo d6: `REG` → `PREP` → `ADJ` → `ANT` do oponente → `ATK` do jogador ativo; depois o outro jogador realiza a mesma sequência. A rodada completa quando ambos terminarem `ATK`; o contador aumenta e o ciclo reinicia pelo jogador inicial.
    *   **Compra (`BUY`):** planejada para a v2 do multiplayer; não entra na sequência inicial da v1.
    *   **Limite da mão:** permanece ilimitado; `ADJ` não descarta cartas por tamanho da mão.
    *   **Estado:** Implementado em `MatchHUD.gd`, com os resultados do d6, quem começa, rodada e etapa. O indicador é informativo e não bloqueia ações do jogo.
*   [ ] **Completar a autoridade da partida:** O anfitrião já é autoritativo para início, sorteio do d6, semente, sequência de fases e estado público canônico, e as ações recebidas são validadas estruturalmente. Falta o anfitrião aprovar cada jogada antes de aplicá-la e tratar as próprias ações pelo mesmo fluxo. O relay Node.js continua apenas pareando e transportando mensagens.
    *   **Ordem sugerida:** validar uma partida real com dois clientes; completar a validação de cada ação pelo anfitrião; testar estados divergentes, desconexões e privacidade. Não considerar o multiplayer pronto para partidas competitivas até a autoridade e a privacidade estarem verificadas. Detalhes em [MULTIPLAYER.md](./MULTIPLAYER.md#limitações-conhecidas-da-v1).

### 🚀 Fase 4: Banco de Dados Completo & Deploy (Netlify)
*   [ ] **Integrar Banco de Dados JSON:** A importação de deck já guarda `ENERGIA`, `PODERES`/`Tags`, `AFILIACAO`, `ESCUDO`, `ALINHAMENTO` e `ENERGIA_EXTRA` nas propriedades da carta. Falta o motor validar essas regras (poderes, afiliação, escudo) durante a partida.
*   [ ] **Exportar para HTML5:** O preset HTML5 já existe em `export_presets.cfg` com saída em `online/site/game/index.html`; o build local foi gerado com os templates do Godot 3.4.4 e validado com dois navegadores até o início da partida e com importação de deck por link. A integração do cliente web já está feita: `LocalRelay` bloqueado no navegador, endereço padrão `wss://`, `join_room` por código, entrada “Entrar com código” no menu e leitura de `?room=CODIGO`/`?relay=HOST`. Falta publicar o build.
*   [ ] **Hospedagem no Netlify:** A Function `GET /api/salas` e a página `/salas` estão implementadas em `online/` e rodam localmente com `netlify dev`; falta publicar o site e o relay (Node.js, em `relay/`). Ver [ONLINE_HOSTING.md](./ONLINE_HOSTING.md).

---

## 📊 3. Painel de Progresso Geral

| Módulo do Projeto | Estado Atual | Progresso Estimado |
| :--- | :---: | :---: |
| **Fase 1: Mecânicas Core (BS)** | 🛠️ Em andamento (falta dano/nocaute/vitória) | 75% |
| **Fase 2: Interface & Imagens Web** | ✅ Implementada (falta validação visual) | 85% |
| **Fase 3: Multiplayer (WebSockets)**| 🛠️ LAN implementada; relay online codificado | 75% |
| **Fase 4: Deploy (Netlify)** | 🛠️ Lobby/preset e cliente web prontos; falta build e deploy | 40% |
