#!/usr/bin/env bash
set -euxo pipefail

# /files/webnovel があれば /share/data/webnovel に丸ごとコピー
if [ -d /files/webnovel ]; then
  mkdir -p /share/data/webnovel
  cp -rf /files/webnovel/. /share/data/webnovel
fi

# narou のインストール
gem specific_install -b docker https://github.com/Rumia-Channel/narou.git

echo "[Narou rb] /share/data に .ready ファイルを待機中…"
while ! ls /share/data/.ready &>/dev/null; do
  sleep 1
done
echo "[Narou rb] .ready ファイルを検出しました。Narou rb を起動します。"

# 作業ディレクトリを /share/data に移動
cd /share/data

# 初回のみ narou init を自動実行（AozoraEpub3 設定をスキップ）
if [ ! -d .narousetting ]; then
  echo | narou init
fi

# ── ここで「already-server-boot」を true にしておく ──
ruby -e "require 'narou'; \
inv = Inventory.load('server_setting', :global); \
inv['already-server-boot'] = true; \
inv.save"

# EPUB 作成を無効化（設定として永続化）
narou setting convert.no-epub=true

narou web -p 3641 --no-browser