# 📓 Caderno de Design - Battle Scenes Web
> Espaço para anotações de lógica, mecânicas e mapeamento técnico.

---

## 🧠 Lógica de Regras Traduzidas para Código

### 0. Campo de jogo (campo visual para 2 jogadores)
*   Organizar o campo geral em duas fileiras:
    *   Superior: `[Deck] [Cena] [Cenário] [Prêmios]`.
    *   Inferior: `[Recursos / Descarte] [Mão]`.
*   Dividir o tabuleiro em duas metades verticais: o espaço superior representa visualmente o campo espelhado do oponente, e o campo interativo do jogador atual fica na metade inferior.
*   Nesta etapa, as zonas do oponente (Mão, Recursos/Descarte, Deck, Cena, Cenário e Prêmios) são apenas visuais e não aceitam cartas nem interação.
*   Recursos/Descarte ficam visíveis para todos. A pilha não se expande por clique; durante a entrada de um Personagem/Suporte que exige anexos, ela abre automaticamente como uma segunda mão para seleção. A mão normal continua sendo a zona separada de cartas na mão.
*   A Cena contém Personagens/Suportes e um único espaço de Cenário ativo. Ao colocar um Cenário novo, o Cenário ativo anterior vai para Recursos/Descarte.
*   A zona de Prêmios é neutra nesta versão. O marcador sobre ela soma o campo `ENERGIA` das cartas que ainda pertencem à pilha; `ENERGIA_EXTRA` não entra no cálculo.
*   Recursos e descarte permanecem juntos; não criar um Limbo separado neste momento.
*   A disposição em duas metades, a reserva visual do oponente e a seleção automática de anexos estão implementadas. A interface e as interações ainda precisam de validação visual no Godot.

### 1. Sistema de Capacitação (Rotação)
No Battle Scenes físico, as cartas inclinam para indicar uso. No jogo, a capacitação será acionada pelo menu de ações exibido ao passar o mouse sobre um personagem em campo (não por um clique direto na carta):
*   **Posição central:** `0°`; os botões **Capacitar** e **Incapacitar** ficam disponíveis.
*   **Inclinada à esquerda:** `-90°`; fica disponível apenas **Capacitar**.
*   **Inclinada à direita:** `+90°`; fica disponível apenas **Incapacitar**.
*   O menu aparece ao passar o mouse sobre personagens em campo. **Incapacitar** move a carta 90° à esquerda e **Capacitar** move 90° à direita; não há rotação além de `-90°` ou `+90°`.
*   Personagens mantêm os botões **Capacitar**, **Incapacitar**, **Flip** e **Escudo**. Escudo abre opções para adicionar `1`, `2` ou `3` e retirar `1`, `2` ou `3`, limitadas à quantidade existente. A contagem é armazenada como token `escudo` na carta. Os demais tipos mantêm **T** e **Flip**; **V** e a rotação **@** foram removidos.
*   A rotação inclinada é tratada pelo código customizado do jogo, pois o framework-base limita sua rotação geral a múltiplos de 90°.
*   As cartas da coleção de demonstração estão marcadas como personagens via `_tipo`, para que os controles apareçam durante a validação local. Os dados de cada carta real também precisarão preencher esse campo.
*   **Validação pendente:** O log do Godot 3.4 registrou falhas de inferência de tipo no script customizado do menu; `is_on_board` e o estágio agora têm tipos explícitos. Também foram corrigidos caminhos da fonte Comfortaa e implementados controles visuais de incapacitação/escudo. A suíte focada não foi concluída após travamentos do VS Code. Não considerar a mecânica validada até executar uma verificação segura.

### 2. O Fluxo da Pilha de Energia (Mecânica de Anexos)
*   Antes de colocar um Personagem ou Suporte da Mão em Cena, verificar se Recursos/Descarte contém cartas suficientes para o valor de `ENERGIA` da carta. Uma carta de `ENERGIA` 3 exige três cartas anexadas para entrar em Cena; sem recursos suficientes, a entrada não pode ser concluída. A validação foi implementada.
*   Ao colocar um Personagem ou Suporte em Cena, abrir automaticamente a segunda mão de Recursos para o jogador escolher por clique as cartas que serão anexadas sob a carta principal. O popup fecha quando a quantidade exigida for escolhida; cancelar devolve a carta principal à Mão.
*   As cartas anexadas ficam empilhadas para baixo, sob a carta principal, mostrando apenas 5% da borda inferior de cada anexo. O deslocamento visual de cada pilha usa o offset definido na própria carta anexada; a carta principal permanece totalmente visível por cima e mantém os controles normais de jogo.
*   Não há botão dedicado para remover vida no Personagem: os Recursos anexados podem ser retirados manualmente. A pilha Recursos/Descarte tem um botão **Trocar**; ao acioná-lo, o jogador escolhe uma carta disponível da pilha e depois o anexo de um Personagem em Cena que será substituído. O anexo substituído volta para Recursos/Descarte como carta disponível. Os botões genéricos de visualizar, ordenar e embaralhar ficam ocultos nessa pilha, que não abre por clique; a seleção automática de anexos durante a entrada em Cena permanece disponível.
*   Anexos não devem girar 90° junto com a carta principal quando esta for capacitada/incapacitada; a rotação de cartas anexadas é bloqueada.
*   A quantidade de cartas anexadas representa a energia carregada/vida atual do Personagem.
*   **Cálculo de Dano:** quando um herói recebe dano, remover a quantidade correspondente de cartas anexadas e enviá-las a Recursos/Descarte. A regra detalhada de ordem de remoção e nocaute permanece para implementação posterior.
*   A regra de entrada e a disposição visual ainda precisam de validação no Godot.

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

### Ideias de Melhorias Futuras (Backlog)
*   [ ] Adicionar um efeito sonoro de papel/carta sendo arrastada.
*   [ ] Criar um botão "Girar Mesa" para o jogador poder ver o campo sob a perspectiva do oponente.
*   [ ] Colocar um efeito visual de brilho (Glow) ao redor das cartas que têm ações disponíveis no turno atual.
