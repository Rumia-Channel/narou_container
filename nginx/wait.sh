#!/bin/bash
set -euo pipefail

CERT="/etc/nginx/ssl/tls.crt"
KEY="/etc/nginx/ssl/tls.key"
TIMEOUT=120        # 秒。長さはお好みで

echo "[nginx] 証明書が揃うまで待機します..."

elapsed=0
while [[ (! -s "$CERT" || ! -s "$KEY") && $elapsed -lt $TIMEOUT ]]; do
  sleep 1
  elapsed=$((elapsed + 1))
done

if [[ ! -s "$CERT" || ! -s "$KEY" ]]; then
  echo "[nginx] ${TIMEOUT}s 以内に証明書が揃いませんでした。"
  echo "[nginx] 一時的な自己署名証明書を生成して起動します。"
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -subj "/CN=localhost" \
    -keyout "$KEY" -out "$CERT"
else
  echo "[nginx] 証明書が揃いました。nginx を起動します。"
fi

exec nginx -g 'daemon off;'
