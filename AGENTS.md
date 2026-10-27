# Instrucoes do projeto

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

O script pode ser chamado pelo PowerShell com a excecao temporaria de politica:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\restart-godot-game.ps1
```

Essa excecao vale somente para essa chamada e nao altera a politica permanente
do Windows. A implementacao fica em [restart-godot-game.ps1](./restart-godot-game.ps1).
