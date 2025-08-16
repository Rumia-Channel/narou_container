#!/bin/bash
set -euo pipefail

: "${TS_ADMIN_KEY:?TS_ADMIN_KEY が未設定です}"
: "${TAILNET_NAME:?TAILNET_NAME が未設定です}"
: "${TS_HOSTNAME:?TS_HOSTNAME が未設定です}"
: "${TS_AUTHKEY:?TS_AUTHKEY が未設定です}"

# ホスト名と完全修飾ドメイン名
NODE="${TS_HOSTNAME%%.*}"
FQDN="${TS_HOSTNAME}"

log(){ echo "[$(date +%H:%M:%S)] $*"; }

# ─── 既存デバイスの重複登録を削除 ───────────────────────
log "purge duplicates of ${FQDN}"

# Tailscale Admin API は tailnet 名を URL エンコードした方が安全
TAILNET_ENC="$(printf '%s' "${TAILNET_NAME}" | jq -sRr @uri)"

# JSON をいったん変数に取り、null や失敗でも落ちないようにする
devices_json="$(curl -sf -u "${TS_ADMIN_KEY}:" \
  "https://api.tailscale.com/api/v2/tailnet/${TAILNET_ENC}/devices" \
  2>/dev/null || true)"
: "${devices_json:=null}"

# 同名の端末を抽出し、全件削除
# lastSeen が無ければ created を、どちらも無ければ 0 をキーにソート
dupe_ids="$(printf '%s' "${devices_json}" \
  | jq -r --arg name "${FQDN}" '
      (.devices? // [])
      | map(select(.name == $name))
      | .[]?                         # ← 全件
      | .id
    ' 2>/dev/null || true)"

if [ -z "${dupe_ids}" ]; then
  log "no duplicates for ${FQDN}"
else
  while read -r id; do
    [ -z "${id}" ] && continue
    if curl -sf -u "${TS_ADMIN_KEY}:" -X DELETE \
         "https://api.tailscale.com/api/v2/device/${id}" >/dev/null; then
      log "  deleted ${id}"
    else
      log "[warn] failed to delete ${id}"
    fi
  done <<< "${dupe_ids}"
fi

# ─── tailscaled をバックグラウンドで起動 ─────────────────────
log "start tailscaled"
tailscaled --state=/var/lib/tailscale/tailscaled.state &
TS_PID=$!

# tailscaled が起動完了するまで待機
for i in {1..20}; do
  if tailscale status &>/dev/null; then
    break
  fi
  sleep 1
done

# ─── tailnet にログイン＆接続 ─────────────────────────────
log "tailscale up (${NODE})"
tailscale up --reset --authkey="${TS_AUTHKEY}" --hostname="${NODE}" \
  || log "[warn] tailscale up failed"

# ─── HTTP（80）と HTTPS（443）を同時に公開 ──────────────────
log "tailscale serve --bg --http=80 http://127.0.0.1:80"
tailscale serve --bg --http=80 http://127.0.0.1:80 \
  || log "[warn] serve HTTP failed"

log "tailscale serve --bg --https=443 http://127.0.0.1:80"
tailscale serve --bg --https=443 http://127.0.0.1:80 \
  || log "[warn] serve HTTPS failed"


# ─── tailscaled プロセスを維持 ────────────────────────────
wait $TS_PID