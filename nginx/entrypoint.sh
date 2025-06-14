#!/bin/bash
set -euo pipefail

# --------------------------------------------------
# tailscale + nginx entrypoint
#   * tailscale cert をバックグラウンドで取得
#   * nginx は先に自己署名で Listen、正式証明書が落ちたら自動 reload
# --------------------------------------------------

: "${TS_ADMIN_KEY:?TS_ADMIN_KEY が未設定です}"
: "${TAILNET_NAME:?TAILNET_NAME が未設定です}"
: "${TS_HOSTNAME:?TS_HOSTNAME が未設定です}"
: "${TS_AUTHKEY:?TS_AUTHKEY が未設定です}"

NODE="${TS_HOSTNAME%%.*}"
FQDN="${TS_HOSTNAME}"
CERT_DIR="/var/lib/tailscale/certs"
NGINX_SSL_DIR="/etc/nginx/ssl"
CRT="${NGINX_SSL_DIR}/tls.crt"
KEY="${NGINX_SSL_DIR}/tls.key"

log(){ echo "[$(date +%H:%M:%S)] $*"; }

# ===== 既存デバイス削除 =====
log "purge duplicates of ${FQDN}"
curl -s -u "${TS_ADMIN_KEY}:" \
  "https://api.tailscale.com/api/v2/tailnet/${TAILNET_NAME}/devices" |
  jq -r '.devices[] | select(.name=="'"${FQDN}"'") | .id' |
  while read -r id; do
    [ -n "$id" ] && curl -sf -u "${TS_ADMIN_KEY}:" -X DELETE \
      "https://api.tailscale.com/api/v2/device/${id}" && log "  deleted ${id}"
  done

# ===== tailscaled 起動 =====
log "start tailscaled"
tailscaled --state=/var/lib/tailscale/tailscaled.state &
for i in {1..20}; do tailscale status &>/dev/null && break; sleep 1; done

# ===== tailscale up =====
log "tailscale up (${NODE})"
tailscale up --reset --authkey="${TS_AUTHKEY}" --hostname="${NODE}" || log "[warn] up failed"

# ===== 先に自己署名を用意して nginx 起動 =====
mkdir -p "$NGINX_SSL_DIR"
if [[ ! -s "$CRT" || ! -s "$KEY" ]]; then
  log "generate temp self‑signed cert"
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -subj "/CN=${FQDN}" -keyout "$KEY" -out "$CRT" 2>/dev/null
fi

log "start nginx (self‑signed)"
nginx -g 'daemon off;' &
NGINX_PID=$!

# ===== 正式証明書をバックグラウンド取得し、完了後 reload =====
(
  log "tailscale cert background fetch"
  mkdir -p "$CERT_DIR"
  if tailscale cert \
        --cert-file "${CERT_DIR}/${FQDN}.crt" \
        --key-file  "${CERT_DIR}/${FQDN}.key" \
        "${FQDN}"; then
    log "cert fetched; installing and reloading nginx"
    install -Dm640 "${CERT_DIR}/${FQDN}.crt" "$CRT"
    install -Dm640 "${CERT_DIR}/${FQDN}.key" "$KEY"
    nginx -s reload || kill -HUP "$NGINX_PID"
  else
    log "[warn] cert fetch failed"
  fi
) &

wait "$NGINX_PID"