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
*   [ ] **Sistema de Capacitação pelo Menu de Ações:** Ao passar o mouse sobre um personagem em campo, exibir apenas as ações válidas de capacitar/incapacitar entre -90°, 0° e +90°, conforme `BATTLE_SCENES_DESIGN.md`.
    *   **Estado:** Cartas de demonstração marcadas como personagens; Capacitar/Incapacitar alternam posições -90°/0°/+90° e mostram apenas a ação oposta nas posições inclinadas; Escudo disponível para personagens. Ainda não validada. A execução anterior do teste foi interrompida após travamentos do VS Code; usar a instância atual do Godot para uma verificação visual, sem iniciar outro processo.
    *   **Correção adicional:** As duas cenas do tabuleiro apontavam para um caminho incorreto da fonte Comfortaa; os caminhos agora correspondem ao arquivo existente em `fonts/comfortaa/`.
*   [ ] **Compra de Cartas por Clique:** Configurar o contêiner do `Deck` para enviar um card para a mão sempre que for clicado.
*   [ ] **Mecânica de Recursos:** Restringir o jogador a baixar apenas 1 recurso da mão por turno (virado para baixo).
*   [ ] **Sistema de Energia e Anexos (*Attachments*):**
    *   [ ] Programar a mecânica de arrastar cards de recurso para "baixo" de um Personagem em jogo.
    *   [ ] Criar um contador numérico em cima do herói mostrando a quantidade de energias carregadas.
*   [ ] **Lógica de Dano, Nocaute e Vitória:**
    *   [ ] Criar função para tirar energias carregadas quando o personagem sofrer dano e mandá-las para o descarte.
    *   [ ] Validar Nocaute: Quando as energias zerarem, mover o herói para o Limbo e colocar cards do topo do deck do oponente na zona de Prêmios dele.
    *   [ ] Checar Vitória: Se a soma da energia inicial dos cards na zona de Prêmios chegar a 15, disparar a tela de vitória.

### 🧱 Fase 2: Infraestrutura Básica & Interface Visual
*   [ ] **Importar Projeto:** Clonar o seu fork do framework e abri-lo no Godot Engine.
*   [ ] **Configurar Resolução (`CFConst.gd`):** Ajustar as proporções visuais dos cards para o padrão clássico do Battle Scenes.
*   [ ] **Criar Conexão HTTP (CDN do Amigo):** Programar o nó `HTTPRequest` para gerar a URL dinâmica baseada nas pastas do repositório `inimig0r/bsdb-imagens`.
*   [ ] **Montar o Tabuleiro 2D:** Posicionar na tela as zonas essenciais (Mão, Deck, Recursos, Cenário, Zona de Combate e Prêmios).

### 🌐 Fase 3: Multiplayer Simples (Espelhamento via WebSockets)
*   [ ] **Criar Script de Rede (`Rede.gd`):** Adicionar o nó `WebSocketMultiplayerPeer` com interface de botões para "Criar Sala" (Host) e "Entrar na Sala" (Client).
*   [ ] **Sincronizar Ações com `@rpc`:**
    *   [ ] Sincronizar Arrastar: Mover uma carta na mesa deve replicar a posição na tela do oponente.
    *   [ ] Sincronizar Rotação: Replicar o ângulo de rotação da capacitação em tempo real na outra aba.
    *   [ ] Sincronizar Ações Ocultas: Avisar o oponente que um card misterioso se moveu (ex: "Comprou carta", "Baixou recurso"), mantendo a identidade oculta.

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
| **Fase 3: Multiplayer (WebSockets)**| ⏳ Planejado | 0% |
| **Fase 4: Deploy (Netlify)** | ⏳ Planejado | 0% |
