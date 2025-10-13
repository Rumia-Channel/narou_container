#!/usr/bin/env bash
set -euxo pipefail

# 追加推奨: ここで UTF-8 を強制しておく
export LANG=ja_JP.UTF-8 LC_ALL=ja_JP.UTF-8 LANGUAGE=ja_JP:ja TZ=Asia/Tokyo
export RUBYOPT='-EUTF-8:UTF-8'

java -version || {
  echo "Java がインストールされていません。Java をインストールしてください。"
  exit 1
}

ruby -e 'p [Encoding.default_external, Encoding.default_internal]'
# 期待: ["UTF-8", "UTF-8"] もしくは ["UTF-8", nil]

# narou のインストール
# 追加: specific_install が未導入なら入れてから使う
if ! gem list -i specific_install >/dev/null 2>&1; then
  gem install specific_install --no-document
fi
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
unzip -q -o -d "$DIR" "$DIR/$(basename "$u")" || unzip -O cp932 -q -o -d "$DIR" "$DIR/$(basename "$u")"
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
ruby -e "require 'narou'; inv = Inventory.load('server_setting', :global); inv['already-server-boot'] = true; inv.save"

# ── 取り外し可能デバイス検出を無効化（nil 例外回避） ──
ruby -e "require 'narou'; class Narou::AppServer; def start_device_ejectable_event; end; end"

# EPUB 作成を無効化（設定として永続化）
narou setting convert.no-epub=${NO_CONVERT_EPUB:-true}

narou setting server-bind=0.0.0.0

narou setting convert.copy-to=/share/epub

narou setting convert.copy-zip-to=/share/zip

narou setting over18=true

narou setting convert.make-zip=${MAKE_ZIP:-true}

narou setting auto-add-tags=${AUTO_ADD_TAG:-true}

narou setting update.auto-schedule.enable=${AUTO_UPDATE:-true}
narou setting update.auto-schedule=${AUTO_UPDATE_TIME:-0300,1500}

narou setting user-agent="Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"

narou setting download.choices-of-digest-options=${AUTO_DIGEST_OPTIONS:-8,4,1}

# AozoraEpub3の画像回転防止iniの生成（必ずRotateImage=0にする）
if [ ! -f "$DIR/AozoraEpub3.ini" ]; then
  echo "RotateImage=0" > "$DIR/AozoraEpub3.ini"
elif grep -q '^RotateImage=' "$DIR/AozoraEpub3.ini"; then
  # 既存のRotateImage行を必ず0に書き換える（全ての一致を置換）
  sed -i 's/^RotateImage=.*/RotateImage=0/g' "$DIR/AozoraEpub3.ini"
else
  echo "RotateImage=0" >> "$DIR/AozoraEpub3.ini"
fi

# NAROU_DEBUG=1 narou web -p 3641 --no-browser
RUBYOPT='-EUTF-8:UTF-8' narou web -p 3641 --no-browser