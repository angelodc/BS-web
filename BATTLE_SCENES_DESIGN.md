# 📓 Caderno de Design - Battle Scenes Web
> Espaço para anotações de lógica, mecânicas e mapeamento técnico.

---

## 🧠 Lógica de Regras Traduzidas para Código

### 1. Sistema de Capacitação (Rotação)
No Battle Scenes físico, as cartas inclinam para indicar uso. Na Godot, usaremos a propriedade `rotation_degrees`:
*   **Pronto (Estágio 0):** `0` graus.
*   **Incapacitado V1 (Estágio 1):** `45` graus (usou uma ação padrão ou tomou efeito).
*   **Incapacitado V2 (Estágio 2):** `90` graus (usou ação que exige incapacitação máxima).

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

### Ideias de Melhorias Futuras (Backlog)
*   [ ] Adicionar um efeito sonoro de papel/carta sendo arrastada.
*   [ ] Criar um botão "Girar Mesa" para o jogador poder ver o campo sob a perspectiva do oponente.
*   [ ] Colocar um efeito visual de brilho (Glow) ao redor das cartas que têm ações disponíveis no turno atual.
