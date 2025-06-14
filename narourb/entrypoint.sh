#!/usr/bin/env bash
set -euxo pipefail

# narou のインストール
gem specific_install -b docker https://github.com/Rumia-Channel/narou.git

echo "[Narou rb] /share/data に .ready ファイルを待機中…"
while ! ls /share/data/.ready &>/dev/null; do
  sleep 1
done
echo "[Narou rb] .ready ファイルを検出しました。Narou rb を起動します。"

# AozoraEpub3 を /share/data/AozoraEpub3 にダウンロード＆解凍
DIR=/share/data/AozoraEpub3
u=$(curl -s https://api.github.com/repos/kyukyunyorituryo/AozoraEpub3/releases/latest \
    | jq -r '.assets[] | select(.name | endswith(".zip")) | .browser_download_url')
mkdir -p "$DIR"
curl -L "$u" -o "$DIR/$(basename "$u")"
unzip -q -o -d "$DIR" "$DIR/$(basename "$u")"
rm "$DIR/$(basename "$u")"

# 作業ディレクトリを /share/data に移動
cd /share/data

# /files/webnovel があれば /share/data/webnovel に丸ごとコピー
if [ -d /files/webnovel ]; then
  mkdir -p /share/data/webnovel
  cp -rf /files/webnovel/. /share/data/webnovel
fi

# 初回のみ
if [ ! -d .narousetting ]; then
  # -p に AozoraEpub3 フォルダ、-l に行の高さ（em）を指定
  narou init -p /share/data/AozoraEpub3 -l 1.8
fi

# ── ここで「already-server-boot」を true にしておく ──
ruby -e "require 'narou'; \
inv = Inventory.load('server_setting', :global); \
inv['already-server-boot'] = true; \
inv.save"

# EPUB 作成を無効化（設定として永続化）
narou setting convert.no-epub=true

narou setting server-bind=0.0.0.0

narou web -p 3641 --no-browser