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
*   Ordem sugerida para a Fase 1: capacitação pelo menu; regra de baixar recurso por turno; anexos e contador de energia; dano, nocaute, prêmios e vitória. Multiplayer e deploy ficam para depois da validação do jogo local.
*   A sequência das demais tarefas continua sujeita a alinhamento antes de cada etapa.

### 🃏 Fase 1: Mecânicas Únicas do Battle Scenes (Singleplayer Local)
*   [x] **Campo de jogo (2 jogadores, oponente visual):** A metade superior reserva um campo espelhado sem cartas ou interações; o campo interativo do jogador atual fica na metade inferior. A Cena contém Personagens/Suportes e um único Cenário ativo; um novo Cenário envia o anterior a Recursos/Descarte. Recursos ficam visíveis para todos e, ao clicar, abrem em uma segunda mão para selecionar anexos. Prêmios têm marcador da soma de `ENERGIA`, sem `ENERGIA_EXTRA`. Limbo segue junto de Recursos/Descarte.
    *   **Estado:** Implementados o layout dividido, as zonas espelhadas apenas visuais do oponente, a expansão de Recursos por clique, a exigência de `ENERGIA` para Personagens/Suportes e a seleção automática de anexos. Cancelar a seleção devolve a carta principal à Mão. A validação visual da nova divisão ainda está pendente no Godot.
*   [x] **Sistema de Capacitação pelo Menu de Ações:** Ao passar o mouse sobre um personagem em campo, exibir apenas as ações válidas de capacitar/incapacitar entre `-90°`, `0°` e `+90°`, conforme `BATTLE_SCENES_DESIGN.md`.
    *   **Estado:** Cartas de demonstração marcadas como personagens; `Capacitar`/`Incapacitar` alternam posições `-90°`/`0°`/`+90°` e mostram apenas a ação oposta nas posições inclinadas; `Escudo` disponível para personagens. Validação concluída no fluxo de uso local.
    *   **Correção adicional:** As duas cenas do tabuleiro apontavam para um caminho incorreto da fonte Comfortaa; os caminhos agora correspondem ao arquivo existente em `fonts/comfortaa/`.
*   [x] **Compra de Cartas por Clique:** Configurar o contêiner do `Deck` para enviar uma carta para a mão sempre que for clicada.
*   [x] **Ações do Deck e da Mão:** Adicionar embaralhar, Clarividência e Procurar no Deck; deixar a Mão sem limite, enviar cartas para Recursos/Descarte com duplo clique e permitir visualizar essa pilha.
*   [x] **Fluxo de Entrada em Cena com Energia e Anexos:** Ao colocar Personagem/Suporte da Mão em Cena, verificar `ENERGIA`, abrir Recursos automaticamente, permitir escolher anexos por clique e cancelar a seleção devolvendo a carta principal à Mão. Validado.
*   [x] **Exibição de Anexos e Troca:** Cartas anexadas empilhadas para baixo sob a carta principal, com 5% da borda inferior de cada anexo visível; a carta principal fica por cima. Anexos não giram com a carta principal. Botão **Trocar** em Recursos/Descarte funcionando para substituir anexos de Personagem.
*   [ ] **Contador de Energia sobre Personagem:** Criar um contador numérico sobre o Personagem mostrando a quantidade de energias carregadas.
*   [ ] **Lógica de Dano, Nocaute e Vitória:**
    *   [ ] Criar função para tirar energias carregadas quando o personagem sofrer dano e mandá-las para o descarte.
    *   [ ] Validar Nocaute: quando as energias zerarem, mover o herói para os prêmios.
    *   [ ] Checar Vitória: se a soma da energia inicial dos cards na zona de Prêmios chegar a 15, disparar a tela de vitória.

### ✅ Base Funcional Validada
*   [x] **Deck → Mão → Cena**
*   [x] **Verificação de energia para entrada em cena**
*   [x] **Seleção de anexos**
*   [x] **Cancelar caso falhe**
*   [x] **Capacitação e incapacitação por menu de ações**

> Observação: a regra de “1 recurso por turno” foi removida do escopo atual e não deve permanecer como tarefa ativa.

### 🧱 Fase 2: Infraestrutura Básica & Interface Visual
*   [ ] **Importar Projeto:** Clonar o seu fork do framework e abri-lo no Godot Engine.
*   [ ] **Configurar Resolução (`CFConst.gd`):** Ajustar as proporções visuais dos cards para o padrão clássico do Battle Scenes.
*   [ ] **Criar Conexão HTTP (CDN do Amigo):** Programar o nó `HTTPRequest` para gerar a URL dinâmica baseada nas pastas do repositório `inimig0r/bsdb-imagens`.
*   [ ] **Carregar Deck por Link do BSDB:** Permitir que o jogador cole uma URL pública de deck e carregar a lista, os dados e as imagens das cartas diretamente do BSDB/CDN. O deck Resgate Aracnídeo abaixo é apenas a lista local de teste; a importação remota ainda não está implementada.
*   [ ] **Montar o Tabuleiro 2D:** Posicionar na tela as zonas essenciais (Mão, Deck, Recursos, Cenário, Zona de Combate e Prêmios).

### 🌐 Fase 3: Multiplayer Simples (Espelhamento via WebSockets)
*   [x] **Username e busca de partida na LAN:** O menu solicita username e endereço do relay, e o botão **Procurar Partida** coloca o jogador em uma fila de duas pessoas. O relay separa partidas, atribui identidades e cancela a busca pelo mesmo botão.
*   [x] **Relay WebSocket (`Rede.gd` e `tools/ws_relay.py`):** Godot 3 usa mensagens JSON em WebSocket. Para jogar na LAN, iniciar `python tools/ws_relay.py` em uma máquina e informar seu IP privado e a porta 9080 nos dois jogos; o relay só encaminha mensagens entre os dois membros de cada partida. Não abrir a porta para a internet.
*   [x] **Sincronizar ações (espelhamento):**
    *   [x] Arrastar: a posição na Cena replica no campo visual do oponente.
    *   [x] Rotação: capacitação/incapacitação replica no oponente.
    *   [x] Ações ocultas: mão e deck vão virados para baixo; o oponente vê recados como "Comprou carta" e "Baixou recurso". Recursos em cena revelam a carta.
    *   **Estado:** Protótipo LAN para dois jogadores; o relay pareia e isola conexões, mas o jogo ainda não tem autoridade de regras nem sincronização de RNG/deck remoto.
*   [ ] **Mostrar o cursor do adversário ao vivo:** Enviar a posição do ponteiro enquanto se move e desenhá-lo no tabuleiro do oponente, identificado pelo username. Converter as coordenadas do tabuleiro para que funcionem com resoluções diferentes; limitar a frequência de envio, ocultar o cursor ao desconectar e não enviar informações das cartas sob o ponteiro. Este recurso é separado do espelhamento de cartas.
*   [ ] **Exibir movimentos do oponente no campo espelhado:** Além de registrar as ações na caixa de texto existente, mostrar visualmente na metade espelhada os movimentos e mudanças de estado que o adversário realiza, preservando ocultas as informações de mão e deck.
*   [ ] **Adicionar indicador central de fases e turnos:** Cada jogador realiza `REG` (início e verificações), `PREP` (baixar cartas e capacitar), `ADJ` (validar estado e efeitos globais) e `COMB` (combate). No bloco `COMB`, o adversário/defensor realiza `ANT` antes do jogador ativo declarar `ATK`. O botão identifica o jogador e a etapa atual; `PREP` é branco, `ANT` vermelho e `ATK` verde.
    *   **Sequência da v1:** jogador que começa pelo d6: `REG` → `PREP` → `ADJ` → `ANT` do oponente → `ATK` do jogador ativo; depois o outro jogador realiza a mesma sequência. A rodada completa quando ambos terminarem `ATK`; o contador aumenta e o ciclo reinicia pelo jogador inicial.
    *   **Compra (`BUY`):** planejada para a v2 do multiplayer; não entra na sequência inicial da v1.
    *   **Limite da mão:** permanece ilimitado; `ADJ` não descarta cartas por tamanho da mão.
    *   **Estado:** planejado; por enquanto, o indicador informa a etapa e não bloqueia ações do jogo.
*   [ ] **Definir e implementar a autoridade da partida:** O relay atual apenas forma partidas e encaminha mensagens; não torna o jogador que abriu a partida o servidor autoritativo. Evoluir para que o jogador anfitrião valide as ações e publique o estado oficial, enquanto o relay mantém o pareamento e o transporte na LAN. Tratar entradas dos dois jogadores pelo mesmo fluxo de validação, inclusive as do anfitrião.
    *   **Ordem sugerida:** primeiro validar uma partida local real com dois clientes; depois implementar o cursor remoto e completar/validar o espelhamento visual; então sincronizar turnos e fases; por fim, estabelecer a autoridade do anfitrião e testar estados divergentes, desconexões e informações ocultas. Não considerar o multiplayer pronto para partidas competitivas até a autoridade e a privacidade estarem verificadas.

### 🚀 Fase 4: Banco de Dados Completo & Deploy (Netlify)
*   [ ] **Integrar Banco de Dados JSON:** Adicionar o arquivo de dados com os atributos das cartas (poderes, afiliação, escudo) para o motor do jogo validar as regras.
*   [ ] **Exportar para HTML5:** Gerar os arquivos de build web dentro da Godot.
*   [ ] **Hospedagem no Netlify:** Vincular seu GitHub ao Netlify para publicar o jogo gratuitamente no navegador.

---

## 📊 3. Painel de Progresso Geral

| Módulo do Projeto | Estado Atual | Progresso Estimado |
| :--- | :---: | :---: |
| **Fase 1: Mecânicas Core (BS)** | ⏳ Planejado | 0% |
| **Fase 2: Interface & Imagens Web** | ⏳ Planejado | 0% |
| **Fase 3: Multiplayer (WebSockets)**| 🛠️ Espelhamento local | 40% |
| **Fase 4: Deploy (Netlify)** | ⏳ Planejado | 0% |
