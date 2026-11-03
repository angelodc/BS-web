# 🦸‍♂️ Battle Scenes Web — TODO (só o que falta)

> **Planejado e já entregue:** [CONCLUIDOS.md](./CONCLUIDOS.md)
> **Planos que ainda precisam de decisão:** [PLANEJAMENTO.md](./PLANEJAMENTO.md)
> Regras: [BATTLE_SCENES_DESIGN.md](./BATTLE_SCENES_DESIGN.md) · Layout: [BOARD_LAYOUT.md](./BOARD_LAYOUT.md) · Online: [ONLINE_HOSTING.md](./ONLINE_HOSTING.md) e [MULTIPLAYER.md](./MULTIPLAYER.md)

Atualizado em 2026-11-02. Produção: build web de 2026-10-30 (Godot 3.4.4) em
`https://battle-scenes.netlify.app`; relay na VM Oracle em
`https://129-159-222-25.sslip.io`.

---

## ⚙️ Engine e build

- [ ] **Export web no Godot 4.7.2:** o preset `Web` já aponta para
  `online/site/game/index.html` e injeta manifest/PWA pelo `head_include`.
  Gerar o build, validar no navegador e publicar. O build no ar ainda é o de
  2026-10-30, feito no 3.4.4.
- [ ] **Confirmar o CI:** os workflows já baixam o Godot 4.7.2 e o GUT 9.7.1
  está instalado; rodar a suíte no GitHub Actions e corrigir qualquer teste
  legado que não tenha sido adaptado.
- [ ] **Enxugar o pacote (−1,4 MB):** remover `src/core/CardViewer/DeckBuilder/`,
  `src/core/CardViewer/CardLibrary/`, `src/custom/CGFDeckbuilder/` e os 4
  screenshots do README na raiz (`deckbuilder-*.png`, `card-library-*.png`).
  Sair junto o botão **DeckBuilder** e o `DeckBuilderPopup` do `CGFBoard.tscn`.
  **Não remover** `CVGridCardObject`, `CVPreviewPopup` e `CVInfoPanel`: o
  “Procurar” do deck depende deles. É o gatilho que paga a próxima publicação.

## 🃏 Regras (Fase 1)

- [ ] **Contador de energia sobre o Personagem:** contador numérico sobre a carta
  com a quantidade de energias carregadas.
- [ ] **Ações cruzadas de regra entre assentos:** ataque entre assentos com dano
  real (hoje só registra no log) e retirada de anexo de baixo do Personagem do
  oponente (envia para Recursos/Descarte do dono). Transporte previsto:
  mensagem `mp_card_action_request` no `MultiplayerSync` e aplicação local no
  `_remote_meta` do espelho no solo. Valem em qualquer fase, sem limite por
  turno.
- [ ] **Motor validar o JSON da carta:** aplicar `PODERES`/Tags, `AFILIACAO`,
  `ESCUDO` e `ENERGIA_EXTRA` durante a partida. A importação já guarda esses
  campos nas propriedades da carta; falta a validação de regra.

## 🌐 Multiplayer

- [ ] **Autoridade completa do anfitrião:** o anfitrião já é autoritativo para
  início, d6, semente, fases e estado público, e valida as ações
  estruturalmente. Falta aprovar cada jogada antes de aplicar e tratar as
  próprias ações pelo mesmo fluxo. Ver
  [MULTIPLAYER.md](./MULTIPLAYER.md#limitações-conhecidas-da-v1).
- [ ] **Validar partida real com dois clientes:** redes diferentes, estados
  divergentes, desconexões, reconexão automática e privacidade (mão/deck/recados).
  Não considerar competitivo antes disso.
- [ ] **Botão “Back to Main” no multiplayer:** o botão existe e funciona no solo,
  mas `_setup_multiplayer()` o esconde. Mostrar, escolher posição (o canto
  esquerdo tem o log do HUD) e decidir se sai direto ou confirma antes de
  abandonar a partida do outro jogador. `_on_BackToMain_pressed()` já encerra a
  sessão.

## 📱 Web e distribuição

- [ ] **Validar e publicar a PWA:** implementada em 2026-11-02 (manifest,
  service worker, ponte `pwa.js`, ícones e botão **Instalar app** no menu web).
  Falta validar no Chrome/Edge/Android e no iPhone (instalação manual), publicar
  `online/site` e confirmar que uma publicação nova não fica presa no cache.
  Guia em [online/README.md](./online/README.md).
- [ ] **Conferir arte/contraste no build web:** título e botões sobre a camada
  escura de 62%, recorte em janelas estreitas e o playmat padrão **BS Web** para
  quem nunca escolheu um. O build publicado já tem a arte; falta olhar no
  navegador.
- [ ] **Publicar em lote:** acumular mudanças de cliente e subir uma vez quando
  houver algo que pague a rebaixa do `index.pck` (ex.: a limpeza de 1,4 MB).
  Detalhes na tabela abaixo.
- [ ] **Testar deploy só de Functions:** `netlify deploy --functions` sem
  reenviar `site/` ainda não foi validado aqui; até então, considerar que
  qualquer upload manda o diretório inteiro.

## 🧭 Layout (pós-bake, arrasto no Inspector)

O layout grande já foi para a cena (Fase 5 em
[CONCLUIDOS.md](./CONCLUIDOS.md)); falta o ajuste fino:

- [x] **Cena como fonte da verdade (rota B):** a geometria real do campo/cenário
  foi assada no `CGFBoard.tscn` (2026-11-02) e o runtime passou a respeitar o
  autorado (espelho derivado do grid). O ajuste fino abaixo já vale no F5/F6.
- [x] **Base HD+ na web / HD e Full HD no desktop:** render do SubViewport a
  1600×900 no web; seletor HD/FHD no menu desktop (`size_2d_override` mantém as
  coordenadas 1280×720). Entregue em 2026-11-02, descrito em
  [CONCLUIDOS.md](./CONCLUIDOS.md).
- [ ] Cenário ativo no mesmo tamanho das cartas em jogo.
- [ ] Rótulo de quantidade/energia dos Prêmios em outra posição.
- [ ] Rótulos do lado do oponente que se espalham sobre o campo.
- O deck **não** entra nesta lista: continua deitado a 270° e mantém a área
  atual.

---

## 📦 Controle de publicação

O site é publicado por deploy manual (`netlify deploy --prod` da pasta
`online/`) e o jogo é um **build**: o `index.pck` é baixado de novo por todo
navegador depois de uma publicação, porque `.pck`/`.wasm` vão com
`must-revalidate`. O custo real de um upload é a rebaixa de todo mundo que
joga no navegador.

O que é do **relay** ou das **Functions** não espera upload do jogo: o relay
roda sob systemd na VM da Oracle e uma mudança só de Function pode ser
publicada sem reexportar o HTML5.

| Mudança pendente | Onde mora | Sobe no Netlify? | Estado |
| :--- | :--- | :---: | :--- |
| PWA: manifest, service worker, ponte e botão no menu | site + cliente | sim (site agora; botão no próximo export) | implementada, falta validar |
| Export web no Godot 4.7.2 | cliente | sim (export + `site/`) | não iniciado |
| Tirar DeckBuilder/CardLibrary/screenshots do pacote (−1,4 MB) | cliente | sim, **e é o gatilho que paga um upload** | não iniciado |
| Contador de energia sobre o Personagem | cliente | sim | não iniciado |
| Ações cruzadas entre assentos | cliente | sim | não iniciado |
| Autoridade do anfitrião por ação | cliente | sim | não iniciado |
| Botão “Back to Main” no multiplayer | cliente | sim | não iniciado |
| Conferir arte/contraste no build web | validação | não (o build já está publicado) | falta olhar no navegador |
| Deploy só de Functions (`--functions`) | Netlify | — | não validado |
