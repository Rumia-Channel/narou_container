#!/bin/sh
# WebDAV <-> ローカルの定期 bisync と単方向アップロードを行う運用スクリプト
# Alpine/BusyBox(ash) でも安全に動くように調整（trap/pipefail/print0 等）

# --------------------------------------------------
# シェル動作: ash でも落ちないように pipefail はベストエフォート
# --------------------------------------------------
set -eu
(set -o pipefail) 2>/dev/null || true

# bash の ERR トラップは ash で非対応のため、EXIT でまとめて通知
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "[ERROR] スクリプトが異常終了 (rc=$rc)"; fi' EXIT

# --------------------------------------------------
# 必須環境変数
# --------------------------------------------------
: "${WEBDAV_URL:?WEBDAV_URL が未設定です}"
: "${WEBDAV_VENDOR:?WEBDAV_VENDOR が未設定です}"
: "${WEBDAV_USER:?WEBDAV_USER が未設定です}"
: "${WEBDAV_PASS:?WEBDAV_PASS が未設定です}"
: "${WEBDAV_PATH:?WEBDAV_PATH が未設定です}"
WEBDAV_REMOTE_NAME="${WEBDAV_REMOTE_NAME:-mywebdav}"

# 末尾スラッシュ事故防止（URL もパスも）
WEBDAV_URL="${WEBDAV_URL%/}"
WEBDAV_PATH="${WEBDAV_PATH%/}"

# --------------------------------------------------
# EPUB/ZIP 送信用の既定値（未設定でも動作継続）
# --------------------------------------------------
EPUB_LOCAL="${EPUB_LOCAL:-/share/epub}"
ZIP_LOCAL="${ZIP_LOCAL:-/share/zip}"
EPUB_REMOTE="${EPUB_REMOTE:-${WEBDAV_REMOTE_NAME}:${WEBDAV_PATH}/epub}"
ZIP_REMOTE="${ZIP_REMOTE:-${WEBDAV_REMOTE_NAME}:${WEBDAV_PATH}/zip}"

# --------------------------------------------------
# 共通パス/設定
# --------------------------------------------------
LOCAL="/share/data"
REMOTE="${WEBDAV_REMOTE_NAME}:${WEBDAV_PATH}"
BACKUP_ROOT_LOCAL="/share/_archive/data"
# リモート側バックアップも WEBDAV_PATH 配下に統一
BACKUP_ROOT_REMOTE="${WEBDAV_REMOTE_NAME}:${WEBDAV_PATH}/_archive/data"
READY_FILE="${LOCAL}/.ready"
BISYNC_FLAG_FILE="${LOCAL}/.bisync_initialized"
BISYNC_WORKDIR="/config/bisync_work"

# rclone のエンコーディング（スペース/特殊文字対策）
RC_ENC_LOCAL="--local-encoding=Raw"
RC_ENC_WEBDAV="--webdav-encoding=Percent"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# --------------------------------------------------
# 依存コマンド確認（jq は任意、rclone は必須）
# --------------------------------------------------
command -v rclone >/dev/null 2>&1 || { echo "[FATAL] rclone が必要です"; exit 1; }
command -v jq >/dev/null 2>&1 || echo "[warn] jq 不在: rclone size の JSON 解析は 0 扱いになります"

# --------------------------------------------------
# rclone.conf 作成（権限制限）
# --------------------------------------------------
setup_rclone_conf() {
  ENC_PASS="$(rclone obscure "${WEBDAV_PASS}")"
  mkdir -p /config
  umask 077
  cat > /config/rclone.conf <<EOF
[${WEBDAV_REMOTE_NAME}]
type   = webdav
url    = ${WEBDAV_URL}
vendor = ${WEBDAV_VENDOR}
user   = ${WEBDAV_USER}
pass   = ${ENC_PASS}
EOF
}

# --------------------------------------------------
# 初期マーカー整備
# --------------------------------------------------
prepare_initial() {
  mkdir -p "${LOCAL}"
  # 空ディレクトリなら古いマーカーをクリーン
  if [ -z "$(ls -A "${LOCAL}" 2>/dev/null || true)" ]; then
    for f in ".ready" ".bisync_initialized"; do
      if [ -f "${LOCAL}/${f}" ]; then
        echo "[cleanup] stale ${f} を削除"
        rm -f "${LOCAL}/${f}"
      fi
    done
  fi
}

# --------------------------------------------------
# JSON の .bytes を数値で返す（jq 無ければ 0）
# --------------------------------------------------
json_bytes_or_zero() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.bytes // 0' 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# --------------------------------------------------
# サイズ比較してローカル不足分のみ復元（エラー耐性あり）
# --------------------------------------------------
check_and_restore_if_needed() {
  sub="$1"

  remote_size="$(
    rclone size "${REMOTE}/${sub}" --config /config/rclone.conf --json \
      --exclude ".ready" --exclude ".bisync_initialized" \
      ${RC_ENC_LOCAL} ${RC_ENC_WEBDAV} 2>/dev/null \
    | json_bytes_or_zero
  )"

  local_size="$(
    rclone size "${LOCAL}/${sub}" --config /config/rclone.conf --json \
      --exclude ".ready" --exclude ".bisync_initialized" \
      ${RC_ENC_LOCAL} ${RC_ENC_WEBDAV} 2>/dev/null \
    | json_bytes_or_zero
  )"

  : "${remote_size:=0}"
  : "${local_size:=0}"

  # POSIX では -gt は整数前提
  if [ "${remote_size}" -gt "${local_size}" ]; then
    echo "[restore] ${sub} ${local_size}→${remote_size}B"
    rclone copy "${REMOTE}/${sub}" "${LOCAL}/${sub}" \
      --config /config/rclone.conf --progress --update \
      --exclude ".ready" --exclude ".bisync_initialized" \
      ${RC_ENC_LOCAL} ${RC_ENC_WEBDAV}
  fi
}

# --------------------------------------------------
# 初回同期（フル）
# --------------------------------------------------
initial_sync() {
  if [ -f "${READY_FILE}" ]; then
    echo "[rclone] 初回セットアップ済み"
    return
  fi

  echo "[rclone] 初回フルコピー ('.ready' '.bisync_initialized' 除外)"
  rclone sync "${REMOTE}" "${LOCAL}" \
    --config /config/rclone.conf --progress \
    --exclude ".ready" --exclude ".bisync_initialized" \
    ${RC_ENC_LOCAL} ${RC_ENC_WEBDAV}

  # 直下のディレクトリを列挙してサイズ補正（NUL 区切りで安全に）
  find "${LOCAL}" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null \
  | while IFS= read -r -d '' path; do
      name="$(basename "$path")"
      check_and_restore_if_needed "$name"
    done

  : > "${READY_FILE}"
  echo "[rclone] 初回完了 (.ready 作成)"
}

# --------------------------------------------------
# バックアップ世代整理
#   - remote: ファイル年齢で削除 → 空ディレクトリを掃除
#   - local : mtime で削除 → 空ディレクトリ掃除
# --------------------------------------------------
prune_backups_remote() {
  # 7日より前のファイルを削除し、空ディレクトリを削除（ルートは残す）
  echo "[prune][remote] ${BACKUP_ROOT_REMOTE} : 7日より前のファイル/空ディレクトリを削除"
  rclone delete "${BACKUP_ROOT_REMOTE}" --config /config/rclone.conf --min-age 7d \
    ${RC_ENC_LOCAL} ${RC_ENC_WEBDAV} 2>/dev/null || true
  rclone rmdirs "${BACKUP_ROOT_REMOTE}" --config /config/rclone.conf --leave-root \
    ${RC_ENC_LOCAL} ${RC_ENC_WEBDAV} 2>/dev/null || true
}

prune_backups_local() {
  echo "[prune][local ] ${BACKUP_ROOT_LOCAL} : 7日より前のファイルを削除"
  # ファイル削除
  find "${BACKUP_ROOT_LOCAL}" -type f -mtime +7 -print -exec rm -f {} \; 2>/dev/null || true
  # 空ディレクトリ削除
  find "${BACKUP_ROOT_LOCAL}" -type d -empty -mindepth 1 -print -exec rmdir {} \; 2>/dev/null || true
}

# --------------------------------------------------
# EPUB/ZIP 一方向アップロード（設定が空ならスキップ）
# --------------------------------------------------
epub_upload() {
  [ -n "${EPUB_LOCAL}" ] && [ -n "${EPUB_REMOTE}" ] || return 0
  if [ -d "${EPUB_LOCAL}" ]; then
    echo "[epub] Uploading ${EPUB_LOCAL} → ${EPUB_REMOTE}"
    rclone copy "${EPUB_LOCAL}" "${EPUB_REMOTE}" \
      --config /config/rclone.conf --progress --update \
      --exclude ".ready" --exclude ".bisync_initialized" \
      ${RC_ENC_LOCAL} ${RC_ENC_WEBDAV}
  fi
}

zip_upload() {
  [ -n "${ZIP_LOCAL}" ] && [ -n "${ZIP_REMOTE}" ] || return 0
  if [ -d "${ZIP_LOCAL}" ]; then
    echo "[zip ] Uploading ${ZIP_LOCAL} → ${ZIP_REMOTE}"
    rclone copy "${ZIP_LOCAL}" "${ZIP_REMOTE}" \
      --config /config/rclone.conf --progress --update \
      --exclude ".ready" --exclude ".bisync_initialized" \
      ${RC_ENC_LOCAL} ${RC_ENC_WEBDAV}
  fi
}

# --------------------------------------------------
# 定期 bisync
#   BusyBox でも安全なオプション選定：
#   - 比較基準は size のみ（--checksum は併用しない）
#   - 初回/復旧は --resync
# --------------------------------------------------
periodic_sync() {
  today="$(date +%F)"
  echo "[rclone] bisync start (backup ${today})"

  mkdir -p "${BISYNC_WORKDIR}"
  # --compare size と --size-only は趣旨が重複するため --size-only に統一
  BISYNC_OPTS="--workdir ${BISYNC_WORKDIR} --size-only"

  BISYNC_OPT=""
  if [ ! -f "${BISYNC_FLAG_FILE}" ]; then
    BISYNC_OPT="--resync"
    echo "  --resync (初回 or 復旧)"
  fi

  if rclone bisync "${LOCAL}" "${REMOTE}" \
        --config /config/rclone.conf ${BISYNC_OPTS} ${BISYNC_OPT} --verbose \
        --backup-dir1 "${BACKUP_ROOT_LOCAL}/${today}" \
        --backup-dir2 "${BACKUP_ROOT_REMOTE}/${today}" \
        --exclude ".ready" --exclude ".bisync_initialized" \
        ${RC_ENC_LOCAL} ${RC_ENC_WEBDAV}
  then
    : > "${BISYNC_FLAG_FILE}"
  else
    echo "[rclone] bisync に失敗、フラグをリセット"
    rm -f "${BISYNC_FLAG_FILE}"
  fi

  prune_backups_remote
  prune_backups_local
}

# --------------------------------------------------
# 改行コード変換（dos2unix が入っていれば）
#   BusyBox には通常入っていないので存在チェックしてから実行
#   NUL 区切りで安全に処理
# --------------------------------------------------
normalize_line_endings() {
  if command -v dos2unix >/dev/null 2>&1; then
    echo "[cleanup] dos2unix で改行コードを変換中..."
    find "${LOCAL}" -type f -print0 2>/dev/null \
    | while IFS= read -r -d '' f; do
        dos2unix "$f" >/dev/null 2>&1 || true
      done
  fi
}

# --------------------------------------------------
# メインループ
# --------------------------------------------------
main() {
  setup_rclone_conf
  mkdir -p "${LOCAL}" "${BACKUP_ROOT_LOCAL}" "${BISYNC_WORKDIR}"
  prepare_initial
  initial_sync
  normalize_line_endings

  while :; do
    # bisync のステールロック掃除
    rm -f "${BISYNC_WORKDIR}"/*.lck 2>/dev/null || true

    periodic_sync
    epub_upload
    zip_upload
    normalize_line_endings

    echo "[rclone] 60 分スリープ"
    sleep 3600
  done
}

main "$@"