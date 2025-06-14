#!/usr/bin/env bash
set -euxo pipefail

echo "[init] Rye のインストールチェック…"
if ! command -v rye >/dev/null 2>&1; then
  echo "[init] rye が見つからないのでインストールします"
  curl -sSf https://rye.astral.sh/get | RYE_NO_AUTO_INSTALL=1 RYE_INSTALL_OPTION="--yes" bash
  echo "[init] rye インストール完了"
fi

# インストール直後に環境を読み込む
. "$HOME/.rye/env"

echo "[debug] PATH=$PATH"
echo "[debug] which rye: $(command -v rye || echo 'not found')"

## ── 0. 前提チェック ──────────────────────────────
: "${GIT_REPO:?環境変数 GIT_REPO が未設定です}"
: "${GIT_BRANCH:=main}"           # 未指定なら main
: "${COOKIE_PATH:=/app/code/cookie}"

## ── 1. Git クローン／更新 ────────────────────────
if [ ! -d /app/code/.git ]; then
  echo "[app] リポジトリをクローンします (${GIT_BRANCH})"
  git clone --depth=1 --branch "$GIT_BRANCH" "$GIT_REPO" /app/code
else
  echo "[app] 既存リポジトリを更新します (${GIT_BRANCH})"
  git -C /app/code fetch origin "$GIT_BRANCH" --depth=1
  git -C /app/code reset --hard "origin/${GIT_BRANCH}"
fi

## ── 2. 設定ファイルを配置 ───────────────────────
echo "[app] 設定ファイルを配置します"
install -Dm644 /app/files/setting.ini /app/code/setting/setting.ini

# Cookie
if [ -d /app/files/cookie ]; then
  mkdir -p "$COOKIE_PATH"
  cp -rf /app/files/cookie/. "$COOKIE_PATH/"
fi

# Crawler
if [ -d /app/files/crawler ]; then
  install -d /app/code/crawler
  cp -rf /app/files/crawler/. /app/code/crawler/
fi

## ── 3. （任意）Rye 環境同期 ─────────────────────
# rye sync || true   # 必要なら有効化

## ── 4. アプリを実行 ────────────────────────────
# /share/data に *.ready ファイルが現れるまで待機
echo "[app] /share/data に .ready ファイルを待機中…"
while ! ls /share/data/.ready &>/dev/null; do
  sleep 1
done
echo "[app] .ready ファイルを検出しました。アプリを起動します。"

cd /app/code
chmod +x ./main.sh
exec ./main.sh
