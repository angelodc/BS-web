# Instrucoes do projeto

## Engine

O projeto roda em **Godot 4.7.2 / GDScript 4.x** (`project.godot` com
`config/features=PackedStringArray("4.7")`). Use apenas API e sintaxe dessa
versao. Diferencas que ja causaram erro na migracao:

- `_ready`/`_enter_tree` nao sao chamados automaticamente nos scripts base:
  chame `super._ready()` no inicio do `_ready` derivado, uma unica vez.
- Nunca sobrescreva metodos nativos como `add_child`, `remove_child` ou
  `move_child`: o Godot 4 nao chama a versao em GDScript. Reaja pelos sinais de
  arvore (`child_entered_tree`, `child_exiting_tree`, `child_order_changed`).
- Nomes de irmaos duplicados sao renomeados automaticamente (`@Control@12`);
  nao dependa de um nome repetido para localizar um no.
- `PopupPanel`/`PopupMenu` sao `Window`: tamanho e posicao sao `Vector2i`.
- Em `Label`/`RichTextLabel` use `autowrap_mode`, nao a propriedade `autowrap`.
- Use `await`, `Callable`, `instantiate()`, `get_node_or_null()` e os metodos
  `add_theme_*`/`get_theme_*` do Godot 4. Nao existe `has_node_or_null`.

## Testes locais no Godot

Depois de implementar uma alteracao e executar as verificacoes automatizadas
adequadas, reinicie a execucao do jogo iniciada pelo F5 para que o usuario
possa testar a versao atualizada. **Nao feche nem reinicie o editor Godot.**

Use `.\restart-godot-game.ps1` na raiz do projeto. O script identifica o jogo
pelo caminho do projeto, pelo editor e pelos argumentos de depuracao do F5;
solicita o fechamento normal, aguarda o processo terminar e inicia o jogo
novamente conectado ao editor. A saida padrao e a saida de erro do jogo sao
salvas em `%LOCALAPPDATA%\Godot\BS-web\logs`, e o script verifica erros e
avisos durante os primeiros 45 segundos do arranque. Informe os resultados e
os caminhos dos logs. Se nao encontrar exatamente uma execucao correspondente ou
se ela nao fechar normalmente, pare e informe o problema: nao encerre processos
a forca nem feche terminais ou processos sem relacao.

Antes de reiniciar, confirme que o usuario terminou o teste em andamento e
autorizou a reinicializacao. Se o usuario estiver testando ou nao houver
autorizacao clara, mantenha o jogo aberto e pergunte antes.

O script pode ser chamado pelo PowerShell com a excecao temporaria de politica.
No Git Bash, `-File` nao repassa o caminho corretamente, entao use `-Command`
com o caminho absoluto e `-Confirm:$false`. Rode a partir da raiz do projeto:
`$(pwd -W)` resolve o caminho absoluto sem fixar a maquina no documento.

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '$(pwd -W)/restart-godot-game.ps1' -Confirm:\$false"
```

Em PowerShell nativo, a forma equivalente e:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\restart-godot-game.ps1' -Confirm:$false"
```

Essa excecao vale somente para essa chamada e nao altera a politica permanente
do Windows. A implementacao fica em [restart-godot-game.ps1](./restart-godot-game.ps1).
