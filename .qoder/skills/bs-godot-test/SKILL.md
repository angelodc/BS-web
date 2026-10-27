---
name: bs-godot-test
description: Executa e interpreta testes GUT do projeto BS-web (Godot 3.4) e reinicia o jogo do F5 com restart-godot-game.ps1 sem fechar o editor. Aceita modo 1 (uma instância) ou modo 2 (duas instâncias para teste manual de multiplayer). Use ao validar mudanças em GDScript, rodar tests/integration ou tests/unit, diagnosticar falhas de teste, checar erros de parse/runtime no Godot, ou recarregar o jogo após alterar código.
argument-hint: "[1|2]"
---

# Testes e reinício do jogo (BS-web)

## Visão geral

Fluxo padrão para validar código neste projeto: rodar primeiro o teste focado, interpretar o resumo do GUT, e só então reiniciar o jogo do F5 para teste manual. O editor Godot nunca deve ser fechado.

## Escolha do modo

- `/bs-godot-test` ou `/bs-godot-test 1`: **modo 1 instância** (padrão). Valida código com GUT e reinicia o F5 para teste manual normal.
- `/bs-godot-test 2`: **modo 2 instâncias**. Faz o mesmo, mas depois do restart abre a segunda instância para testar sala, espelhamento, checkpoint e sincronização.

Importante: o GUT roda sempre em um processo único; ele não se conecta às duas instâncias abertas. A segunda instância é apenas para o teste manual final. Testes automatizados de multiplayer ficam em `tests/integration/test_multiplayer_lobby.gd` e rodam como qualquer outro teste.

| Objetivo | Modo | Etapa manual final |
|---|---|---|
| Validar GDScript, cartas, tabuleiro, regras | 1 | Reiniciar o F5 |
| Validar sala, espelhamento, checkpoint, dois jogadores | 2 | Reiniciar o F5 e abrir a segunda instância |

## Caminhos fixos

- Projeto: `C:\Users\doug\Projetos\BS-web`
- Godot 3.4.4: `C:\Users\doug\Downloads\Godot_v3.4.4-stable_win64.exe\Godot_v3.4.4-stable_win64.exe`
- Testes de integração: `tests/integration`
- Testes unitários: `tests/unit`
- Logs do jogo: `%LOCALAPPDATA%\Godot\BS-web\logs`

## 1. Rodar um teste focado

Escolha o diretório conforme o teste. O `-gselect` recebe o nome do arquivo com extensão.

```bash
"C:/Users/doug/Downloads/Godot_v3.4.4-stable_win64.exe/Godot_v3.4.4-stable_win64.exe" \
  --path "C:/Users/doug/Projetos/BS-web" \
  -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration \
  -gselect=test_placement_grid.gd \
  -gexit -glog=1
```

Para um único caso dentro do script, acrescente:

```bash
-gunit_test_name=test_scene_grid_is_three_by_two
```

Para testes unitários, troque o diretório:

```bash
-gdir=res://tests/unit -gselect=test_BoardPlacementGrid_class.gd
```

## 2. Rodar a suíte completa

Só depois que os testes focados passarem. Rode um diretório por vez para evitar timeout e excesso de saída.

```bash
# integração
... -gdir=res://tests/integration -gexit -glog=1

# unitários
... -gdir=res://tests/unit -gexit -glog=1
```

A suíte inteira é demorada e cria muitos órfãos; não a use como primeiro diagnóstico.

## 3. Interpretar o resultado

O código de saída do Godot não é confiável: ele pode retornar 0 mesmo com erros de script. Decida pelo resumo do GUT:

- Sucesso: `All tests passed` e `Failing tests 0`.
- Falha: `Tests failed`, lista de `[Failed]` ou `Failing tests` maior que zero.

Ao falhar, extraia apenas o necessário:

1. Nome do teste e mensagem da asserção.
2. Primeiro `SCRIPT ERROR` ou `ERROR` que aponta para arquivo e linha do projeto.
3. Se o erro veio antes do teste (parse, cena, autoload), corrija isso primeiro.

Ruído comum que **não** define falha sozinho:

- `new orphans`, `ObjectDB instances leaked`, `Resources still in use at exit`.
- Avisos de instanciação de cartas de teste (`canonical_name`, `_determine_idle_state`).
- `WARNING: ObjectDB instances leaked at exit`.

Trate esses avisos como pista, não como veredito. O veredito é o resumo do GUT.

Não use `--check-only` como validação principal: o projeto tem dependências cíclicas entre `class_name` e o modo de checagem reporta falsos erros. GUT e a execução do jogo carregam os scripts de verdade.

## 4. Reiniciar o jogo do F5 (usado nos dois modos)

Faça isso somente quando o código novo estiver pronto e os testes adequados tiverem rodado. O usuário deu autorização permanente para fechar as instâncias de teste quando houver código novo; ainda assim, não reinicie se ele avisar que está no meio de um teste.

Regras:

- Não feche nem reinicie o editor Godot.
- O script exige exatamente um editor e uma execução do F5 correspondente ao projeto.
- Se houver uma segunda instância aberta (`run-second-instance.cmd`), feche-a pela janela antes; nunca encerre processos à força.
- Se o script não encontrar exatamente uma execução ou se ela não fechar normalmente, pare e informe o problema.
- O script verifica erros e avisos nos primeiros 45 segundos e salva stdout/stderr em `%LOCALAPPDATA%\Godot\BS-web\logs`.

Invocação correta no Git Bash (não use `-File`, que quebra no `ShouldProcess`):

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\Users\doug\Projetos\BS-web\restart-godot-game.ps1' -Confirm:\$false"
```

O `\$false` é necessário para o Bash não expandir a variável.

Depois de reiniciar, informe:

- Se o arranque ficou limpo ou quais erros/avisos apareceram.
- O caminho dos logs mais recentes em `%LOCALAPPDATA%\Godot\BS-web\logs`.

## 5. Modo 1: uma instância

Sequência:

1. Rodar o GUT focado (e a suíte, se necessário).
2. Reiniciar o F5 com o comando da seção 4.
3. Testar manualmente no jogo reiniciado.
4. Encerrar aqui. Não abrir segunda instância.

Use quando a mudança não envolve sala, dois jogadores, espelhamento ou checkpoint.

## 6. Modo 2: duas instâncias

Sequência:

1. Rodar o GUT focado. Para multiplayer, inclua `test_multiplayer_lobby.gd` entre os testes.
2. Se a segunda instância estiver aberta, feche-a pela janela. O script de restart não aceita duas execuções do jogo.
3. Reiniciar o F5 com o comando da seção 4.
4. Abrir a segunda instância:

```bash
./run-second-instance.cmd
```

5. Na primeira instância, criar a sala e escolher o deck.
6. Na segunda, usar Procurar Partida e entrar na sala.
7. Validar o comportamento e reportar o que foi observado.
8. Ao terminar o teste, fechar a segunda instância pela janela antes do próximo restart.

Esse modo não substitui os testes GUT; a segunda instância serve apenas para o teste manual de multiplayer.
