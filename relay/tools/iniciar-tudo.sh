#!/data/data/com.termux/files/usr/bin/bash
# Sobe o relay do BS-web, o túnel público e o registro do endereço no site.
# Idempotente: rodar de novo não derruba o que já está no ar.
#
# Cópia do script que vive em ~/projetos/bs-relay/iniciar-tudo.sh no S20 FE.
H=/data/data/com.termux/files/home
LOG=$H/projetos/bs-relay
tmux has-session -t bs-relay 2>/dev/null || tmux new -d -s bs-relay \
  "cd $LOG && PORT=9080 TRUST_PROXY=1 LOG_LEVEL=info node src/server.js 2>&1 | tee -a $LOG/relay.log"
sleep 2
tmux has-session -t cf-relay 2>/dev/null || tmux new -d -s cf-relay \
  "proot-distro login debian -- cloudflared tunnel --protocol http2 --url http://127.0.0.1:9080 2>&1 | tee $LOG/cf-relay.log"
sleep 8
if curl -sS -m 3 -o /dev/null http://127.0.0.1:8888/ 2>/dev/null; then
  tmux has-session -t cf-site 2>/dev/null || tmux new -d -s cf-site \
    "proot-distro login debian -- cloudflared tunnel --protocol http2 --url http://127.0.0.1:8888 2>&1 | tee $H/projetos/tuneis/cf-site.log"
  sleep 8
  echo "site:  $(grep -oE 'https://[a-z0-9-]+.trycloudflare.com' $H/projetos/tuneis/cf-site.log | tail -1)"
fi
# O hostname do túnel muda a cada reinício do cloudflared. O registro publica o
# endereço novo num Blob do Netlify e o lobby passa a entregá-lo sem redeploy; o
# watcher repete a conferência a cada minuto, então um túnel que caiu e voltou
# com outro nome se recupera sozinho.
tmux has-session -t bs-register 2>/dev/null || tmux new -d -s bs-register \
  "cd $LOG && node register-relay.mjs --watch 2>&1 | tee -a $LOG/registrar.log"
node $LOG/register-relay.mjs
echo "relay: https://$(grep -oE '[a-z0-9-]+.trycloudflare.com' $LOG/cf-relay.log | tail -1)"
curl -sS -m 8 http://127.0.0.1:9080/healthz; echo
