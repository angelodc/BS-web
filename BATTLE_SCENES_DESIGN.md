# 📓 Caderno de Design - Battle Scenes Web
> Espaço para anotações de lógica, mecânicas e mapeamento técnico.

---

## 🧠 Lógica de Regras Traduzidas para Código

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
*   A "vida" de um personagem na mesa é igual à contagem de cartas na sua lista `cartas_carregadas`.
*   **Cálculo de Dano:** Quando um herói recebe 2 de dano, o código deve rodar um loop removendo as 2 últimas cartas anexadas a ele e mandando-as para o Limbo.

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
