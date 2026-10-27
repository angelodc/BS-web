---
name: bs-multiplayer-smoke
description: Roteiro de teste manual de multiplayer LAN do BS-web com dois clientes. Use ao validar criação e busca de sala, preparação com decks, espelhamento do tabuleiro, cursor remoto, privacidade de mão/deck, fases, reconexão, Prêmios, Cenário ou retomada por checkpoint, especialmente após mudar Multiplayer.gd, MultiplayerSync.gd, Rede.gd, LocalRelay.gd, MatchHUD.gd, CheckpointStore.gd ou CheckpointList.gd.
---

# Teste manual de multiplayer (dois clientes)

## Relação com a skill bs-godot-test

Esta skill não repete comandos de GUT, restart, logs ou regras de processo. Antes de começar, carregue `bs-godot-test` e use o **modo 2**. Lá estão:

- comando do teste focado;
- restart do F5 com `restart-godot-game.ps1`;
- regras para não fechar o editor e não matar processos;
- caminho dos logs.

Aqui fica apenas o que é específico de dois clientes. O comportamento esperado está em [MULTIPLAYER.md](file:///C:/Users/doug/Projetos/BS-web/MULTIPLAYER.md); consulte a seção "Como testar" em vez de duplicá-la.

## Pré-condições

1. Rodar o GUT focado, incluindo `tests/integration/test_multiplayer_lobby.gd`.
2. Corrigir qualquer falha automatizada antes do teste manual.
3. Só então reiniciar o F5 e abrir a segunda instância.

## Preparar os dois clientes

- Primeiro cliente: execução normal do F5, em fullscreen.
- Segundo cliente: use a abertura do modo 2 descrita na `bs-godot-test` (`run-second-instance.cmd`, em janela).
- Mesma máquina: relay `127.0.0.1:9080`. O relay embutido sobe sozinho; não inicie `tools/ws_relay.py` sem necessidade.
- Usernames **diferentes**. O relay compara sem diferenciar maiúsculas de minúsculas e recusa nomes iguais.
- Os dois clientes compartilham `user://`: configurações, decks e checkpoints são os mesmos arquivos. Evite trocar username durante o teste; ao reiniciar um cliente, confira o username antes de entrar.

## Ordem do teste

### 1. Menu e pareamento

- P1 usa **Criar Sala**; P2 usa **Procurar Partida**.
- Confirmar que os dois entram na mesma partida e que o status/indicador mostra os usernames corretos.
- Testar **Cancelar** durante a busca.
- Testar username igual: o erro deve aparecer no diálogo com **OK** e no status; o diálogo precisa fechar normalmente.
- Testar um terceiro cliente, se possível: a sala deve recusar.

### 2. Preparação e início

- O último deck usado deve vir selecionado; **Decks salvos** deve listar o deck importado.
- `INICIAR` só habilita quando os dois escolheram decks com exatamente 60 cartas.
- Qualquer um dos dois consegue iniciar.
- Os dois clientes devem ver os mesmos dados, o mesmo vencedor e a mesma rodada inicial.
- Cada jogador vê 10 cartas apenas na própria mão.

### 3. Tabuleiro espelhado e privacidade

- O campo superior deve ser do oponente, com cartas giradas em 180° e contidas na área superior.
- O campo do oponente não deve aceitar interação local.
- Mover cartas entre zonas públicas e conferir a posição espelhada nos dois clientes.
- Mão e deck do oponente nunca podem revelar nome, face ou imagem; apenas contadores/posições.
- Cursor remoto: espelhado, 10 Hz, com username, some após cerca de 3 segundos sem movimento.
- Comparar as duas telas: o mesmo estado deve aparecer nos dois lados, mesmo com janelas de tamanhos diferentes.

### 4. Regras visíveis no tabuleiro

- Cenário: só um ativo entre os dois campos; ao jogar um novo, o Cenário do oponente vai para Recursos/Descarte do dono.
- Cena: capacidade dinâmica, duas linhas, posicionamento central e suporte na linha de trás quando houver personagem na frente.
- Personagem em Cena: botão **Prêmios** visível no multiplayer e funcional; a carta vai para os Prêmios do adversário.
- Suporte: botão **Nocaute** funcional; cartas anexadas vão para o descarte junto.
- Anexos e Recursos: cartas sob uma principal acompanham o destino correto.

### 5. Fases

- Sequência por jogador: `REG → PREP → ADJ → ANT → ATK`.
- O indicador mostra rodada, etapa, jogador ativo, quem começa e os resultados dos dados.
- Cores: `PREP` branco, `ANT` vermelho, `ATK` verde.
- A rodada só incrementa depois que os dois completam a sequência, e recomeça por quem venceu o d6.

### 6. Queda e reconexão

- Fechar a janela de P2 durante a partida: P1 deve congelar e mostrar espera sem limite.
- Reabrir P2 e voltar à mesma sala pelo fluxo do menu; confirmar se o estado é retomado e se P1 volta a interagir.
- Testar encerrar manualmente durante a espera.

### 7. Checkpoints e retomada

- Avançar fases para gerar checkpoints e fechar os dois clientes.
- **Iniciar jogo salvo** no cliente que vai hospedar; o outro entra com o username original.
- Verificar que os dois retomam a mesma partida, sequência e fase.
- Testar uma cópia local corrompida: o outro cliente deve fornecer a cópia íntegra.
- Testar sem checkpoint comum íntegro: a retomada deve ser bloqueada com explicação, sem trocar participante.

## Como reportar

Para cada falha, informe:

- Cliente: P1/anfitrião ou P2/convidado.
- Passo e resultado esperado.
- Resultado observado nos dois lados, quando possível.
- Se o estado divergiu entre os clientes (dados, fase, rodada, posição, Cenário, Prêmios).
- Linha de log ou mensagem do HUD, se houver.

Não considere aprovado só porque não houve crash. O critério é: os dois clientes mostram o mesmo estado público e cada um mantém a própria mão/deck privada.

## Encerramento

- Sair da sessão pelo fluxo do jogo antes de fechar as janelas.
- Para fechar as instâncias e reiniciar o F5, siga o encerramento do modo 2 da `bs-godot-test`.

## Armadilhas conhecidas

- `F5` não abre uma segunda instância; use `run-second-instance.cmd`.
- Usernames iguais são recusados; diferencie maiúsculas/minúsculas.
- O relay embutido só atende endereços locais. Para outra máquina, use o IP do anfitrião, libere a porta 9080 e, se necessário, o relay externo.
- `--no-window` pode travar a suíte GUT neste ambiente; rode o teste do multiplayer com janela.
- O relay de desenvolvimento não tem TLS nem autenticação: não o exponha à internet.
