#!/bin/bash
set -euo pipefail

: "${TS_ADMIN_KEY:?TS_ADMIN_KEY が未設定です}"
: "${TAILNET_NAME:?TAILNET_NAME が未設定です}"
: "${TS_HOSTNAME:?TS_HOSTNAME が未設定です}"
: "${TS_AUTHKEY:?TS_AUTHKEY が未設定です}"

NODE="${TS_HOSTNAME%%.*}"
FQDN="${TS_HOSTNAME}"
CERT_DIR="/var/lib/tailscale/certs"
CRT="/var/lib/tailscale/tls.crt"
KEY="/var/lib/tailscale/tls.key"

log(){ echo "[$(date +%H:%M:%S)] $*"; }

# 既存デバイス削除
log "purge duplicates of ${FQDN}"
curl -s -u "${TS_ADMIN_KEY}:" \
  "https://api.tailscale.com/api/v2/tailnet/${TAILNET_NAME}/devices" |
  jq -r '.devices[] | select(.name=="'"${FQDN}"'") | .id' |
  while read -r id; do
    [ -n "$id" ] && curl -sf -u "${TS_ADMIN_KEY}:" -X DELETE \
      "https://api.tailscale.com/api/v2/device/${id}" && log "  deleted ${id}"
  done

# tailscaled 起動
log "start tailscaled"
tailscaled --state=/var/lib/tailscale/tailscaled.state &
for i in {1..20}; do tailscale status &>/dev/null && break; sleep 1; done

# tailscale up
log "tailscale up (${NODE})"
tailscale up --reset --authkey="${TS_AUTHKEY}" --hostname="${NODE}" || log "[warn] up failed"

# 証明書バックグラウンド取得
(
  log "tailscale cert background fetch"
  mkdir -p "$CERT_DIR"
  if tailscale cert \
        --cert-file "${CRT}" \
        --key-file  "${KEY}" \
        "${FQDN}"; then
    log "cert fetched and written to /var/lib/tailscale"
  else
    log "[warn] cert fetch failed"
  fi
) &

wait
