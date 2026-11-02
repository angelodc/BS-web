# 🦸‍♂️ Battle Scenes Web — Planejamento

> Planos que ainda dependem de decisão ou de mais de uma sessão. O que está
> pronto e pendente de execução fica em [TODO.md](./TODO.md); o histórico do
> que já foi entregue fica em [CONCLUIDOS.md](./CONCLUIDOS.md).

---

## 1. Rota B — app desktop Windows

**Objetivo:** um `.exe` nativo para quem quer sair do navegador: janela própria,
1080p nativo, sem aba nem canvas do browser. Não muda as regras nem o
multiplayer — o cliente continua falando com o mesmo relay.

**Passos propostos**

1. Criar o preset **Windows Desktop (x86_64)** em `export_presets.cfg`, saída
   `build/BSWeb-<versao>.zip` (fora de `online/`, para não ir ao Netlify).
2. Ajustar `config/name`, ícone e versão em `project.godot`; desligar o console
   no build de release (`application/run/disable_stdout` conforme o caso).
3. Definir o relay padrão do desktop: hoje o campo nasce em `127.0.0.1:9080`
   (relay local). No app publicado o natural é abrir já apontando para
   `wss://129-159-222-25.sslip.io`, mantendo o campo editável para LAN.
4. Publicar o `.zip` em **GitHub Releases** (recomendado: não consome a banda do
   Netlify e dá histórico por versão). Link “Baixar app desktop” no lobby web,
   visível só no navegador (`OS.has_feature("web")`), e um aviso curto no menu
   do desktop quando houver versão nova (consulta simples a um JSON estático).
5. Reaproveitar o seletor de resolução/nitidez (seção 3) também no desktop.

**Decisões em aberto**

- **Assinatura do `.exe`:** sem assinatura o SmartScreen mostra “aplicativo não
  reconhecido”. Assinar custa certificado; para v1, aceitar o aviso e documentar.
- **Onde hospedar:** GitHub Releases (grátis) × Netlify (`/download/`); recomendo
  Releases para não gastar banda do site.
- **Dois builds:** web e desktop saem do mesmo commit; a versão precisa aparecer
  no menu para não confundir relatos de bug.
- **Atualização:** manual (baixar de novo) na v1; atualizador automático fica
  fora até existir motivo.

**Custo esperado:** um dia de implementação + uma rodada de validação em Windows
(instalação, fullscreen, áudio, relay e partida solo).

---

## 2. Tabuleiro WYSIWYG — a cena como fonte da verdade (rota B)

**Contexto:** `CGFBoard.tscn` não mostra o tabuleiro real. O playmat é escolha
de runtime (`playmat_id` em `user://CGFSettings.json`, hoje
`battle_scenes_fit`) e **não pode** ser gravado na cena: o export web exclui
`assets/playmats/*`, então uma referência fixa quebraria o pacote. Já o campo e
o cenário eram recomputados em `_apply_battle_scenes_layout()` a partir de
valores autorais, então o editor exibia coordenadas antigas (grid 374×345 em
(453, 360), 6 slots) enquanto o jogo usava outras (961×286,2 em
(159,5; 366,2), 7 colunas × 2 fileiras).

**Decisão (2026-11-02):** rota B — a cena passa a conter a geometria real e o
runtime respeita o autorado.

**Passos**

1. Assar a geometria em `CGFBoard.tscn`: grid em (159.5, 366.2) com
   961×286.2; `CGFPlacementGridDemo.tscn` com 7 colunas e 14 slots (o runtime
   para de criar slots dinamicamente); cenário em (1152.5, 368.2) com
   99×138.6; legenda do cenário em (1124, 508.8) com 156×20; deck salvo já
   deitado a 270°.
2. `CGFBoard.gd` passa a *respeitar* o autorado:
   `_apply_battle_scenes_layout()` vira sincronização do espelho
   (`OpponentScene` segue o rect do grid) + `hand.re_place()`; some o
   recálculo dependente de viewport e o posicionamento da legenda.
3. O grid segue auto-arranjado: `configure_width` usa a largura autorada do
   próprio grid, então alargar/estreitar na mão atualiza as colunas no F5/F6.
4. Testes: ajustar `test_placement_grid`, `test_mirror_geometry`,
   `test_board_use`; garantir que o layout autorado sobrevive ao `_ready`.
5. Validar: GUT focado + integração, F6 (passa a mostrar a geometria real) e
   F5.

**Trade-offs:** mexer no grid/cenário à mão passa a valer no jogo; quem ajustar
precisa saber que a banda do oponente é derivada do grid (não se edita
direto). O playmat continua fora da cena — o editor mostra a geometria real
sobre o fundo padrão do projeto, não sobre a arte.

**Custo esperado:** meio dia com testes.

---

## 3. Base de resolução — HD+ na web, HD e Full HD no desktop

**Decisão (2026-11-02):** a base de *renderização do tabuleiro* sobe para
**HD+ 1600×900** na web. No desktop, o jogador escolhe entre **HD 1280×720** e
**Full HD 1920×1080**. As coordenadas de design continuam 1280×720 — muda só a
densidade do raster do `SubViewport`.

**Plano**

1. `ViewportCardFocus._ready`: `SubViewport.size = <escolha>`,
   `size_2d_override = Vector2i(1280, 720)`,
   `size_2d_override_stretch = true`; o mesmo fator no SubViewport de foco
   (300×450 → 375×563 na web, 450×675 em FHD) para a prévia de carta nítida.
2. Resolução efetiva: web sempre 1600×900 (`OS.has_feature("web")`); desktop lê
   `board_render_res` do `CGFSettings.json`, com seletor no menu visível só
   fora do web.
3. `DisplayMode.gd` aplica o tamanho da janela (HD/FHD) no boot e na troca; na
   web nada muda — a política de canvas adaptativa do export continua mandando.
4. Validar input (arrasto/hover) com o override ativo no F5 e no export web: o
   mouse passa pelo `StretchTransform` do SubViewport.

**Observações**

- Menu e HUD já são nítidos em qualquer janela (`canvas_items` re-renderiza o
  vetor por frame); o ganho é no tabuleiro e na prévia, hoje raster fixo
  720p/300×450 esticado.
- A arte não ganha detalhe além da textura de origem; o ganho é texto, moldura
  e ícones.
- O workflow de captura do tabuleiro (prints por PID) precisa ser revisto,
  porque o viewport interno muda de tamanho.
- Alternativa descartada: re-autorar todas as cenas em 1600×900 (×1,25 em cada
  offset/fonte). Custo alto, ganho pequeno — o stretch do canvas já escala o
  design com nitidez.

**Em aberto:** padrão no desktop (HD é o recomendado para telas menores) e se
HD+ vira terceira opção do desktop depois.

---

## 4. Botão de sugestões / reportar bug

**Objetivo:** um ícone discreto no jogo (começar no menu; depois avaliar o HUD da
partida) que abre um diálogo para escrever uma sugestão ou relatar um bug, com
opção de anexar um print da tela e o log da partida.

**Fluxo de UI**

- Ícone no canto (mesmo lugar previsto para o botão de instalação PWA) →
  diálogo com:
  - tipo: **Bug** / **Sugestão**;
  - campo de texto livre;
  - contato opcional (e-mail/Discord);
  - checkbox **Incluir captura da tela** (ligado por padrão);
  - checkbox **Incluir log da partida** (ligado por padrão);
  - aviso de privacidade com o que será enviado (nome, sala, endereço do relay,
    trecho do log) e como desligar;
  - **Enviar** + estado (enviando/erro/sucesso).
- Um relato por sessão para não spammar; se a rede falhar, guardar em
  `user://reports/` e reenviar depois.

**Captura e log**

- Print: `await RenderingServer.frame_post_draw` e
  `get_viewport().get_texture().get_image()` (funciona no web sem depender de
  `preserveDrawingBuffer`), redimensionado para no máximo ~1600 px de largura e
  enviado como PNG.
- Log: buffer do autoload `GameEvents` (ações da partida) + arquivo do Godot em
  `user://logs/`, limitado às últimas ~200 linhas; remover endereço do relay e
  IPs quando o jogador desmarcar “incluir dados da partida”.

**Backend recomendado: Supabase**

Já faz parte da stack do projeto e o free tier cobre de sobra relatos de bug;
não consome cota do Netlify.

- Tabela `reports`: `id`, `created_at`, `kind` (`bug`/`suggestion`), `message`,
  `contact`, `app_version`, `platform`, `room_code`, `log_excerpt`,
  `screenshot_path`, `user_agent`.
- Bucket `reports` (privado) para os PNGs, limite de ~2 MB e `image/png`.
- Cliente envia com a chave publishable e RLS **somente insert** em `reports` e
  **somente upload** no bucket. Leitura fica no dashboard do Supabase (service
  role); nada de listar relatos pelo cliente.
- Rate limit: um envio a cada 30 s no cliente; se aparecer abuso, uma Edge
  Function com throttle por IP.

**Alternativas consideradas**

- **Google Forms:** grátis e simples, mas não anexa print/log de forma
  programática — o jogador teria que copiar e colar. Serve como fallback
  “abrir formulário” enquanto o Supabase não estiver pronto.
- **Netlify Blobs/Functions:** evitar, é justamente a cota que queremos poupar.
- **Cloudflare D1/R2:** barato, mas adiciona uma stack nova sem necessidade.

**Decisões em aberto:** o ícone fica no menu, no HUD da partida ou nos dois; o
contato é obrigatório?; prazo de retenção/limpeza dos relatos.

---

## 5. Outros planos que precisam de decisão

- **Single Player Demo:** definir antes de voltar o botão ao menu — deck fixo,
  se há oponente (ausente/scriptado/hotseat), quais mecânicas mostra, como sai
  e o que acontece no build web.
- **Área de texto na partida:** recado entre jogadores (chat, precisa de
  mensagem nova no relay e proteção contra abuso) × caderno particular (só no
  cliente). Decidir onde mora e o que fica visível no solo.
- **PWA com cache offline do jogo:** a PWA atual instala e abre o lobby offline,
  mas `/game/` fica sempre na rede para não prender builds antigos. Se offline
  virar requisito, avaliar a PWA embutida do Godot 4 (manifest/service worker
  gerados no export) em vez da implementação manual do site.
- **Relay v3 em Cloudflare Workers + Durable Objects (opcional):** sem prazo;
  a VM Oracle com IP reservado atende até haver motivo concreto para migrar.
