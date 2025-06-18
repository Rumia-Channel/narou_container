#!/bin/sh
set -euo pipefail
trap 'echo "[ERROR] 行:$LINENO で失敗"; exit 1' ERR

# --------------------------------------------------
# 環境変数チェック
# --------------------------------------------------
: "${WEBDAV_URL:?WEBDAV_URL が未設定です}"
: "${WEBDAV_VENDOR:?WEBDAV_VENDOR が未設定です}"
: "${WEBDAV_USER:?WEBDAV_USER が未設定です}"
: "${WEBDAV_PASS:?WEBDAV_PASS が未設定です}"
: "${WEBDAV_PATH:?WEBDAV_PATH が未設定です}"
WEBDAV_REMOTE_NAME=${WEBDAV_REMOTE_NAME:-mywebdav}

# --------------------------------------------------
# EPUB 用環境変数（未設定でもエラーにならないように定義）
# --------------------------------------------------
EPUB_LOCAL=/share/epub
EPUB_REMOTE="${WEBDAV_REMOTE_NAME}:${WEBDAV_PATH}/epub"

# --------------------------------------------------
# rclone.conf 作成
# --------------------------------------------------
setup_rclone_conf() {
  ENC_PASS="$(rclone obscure "${WEBDAV_PASS}")"
  mkdir -p /config
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
# rclone に与える共通オプション
# --------------------------------------------------
RC_ENC="--local-encoding Raw --webdav-encoding Percent"

# --------------------------------------------------
# パス定義
# --------------------------------------------------
LOCAL="/share/data"
REMOTE="${WEBDAV_REMOTE_NAME}:${WEBDAV_PATH}"
BACKUP_ROOT_LOCAL="/share/_archive/data"
BACKUP_ROOT_REMOTE="${WEBDAV_REMOTE_NAME}:archive${WEBDAV_PATH}"
READY_FILE="${LOCAL}/.ready"
BISYNC_FLAG_FILE="${LOCAL}/.bisync_initialized"
BISYNC_WORKDIR="/config/bisync_work"

# --------------------------------------------------
# マーカーリセット
# --------------------------------------------------
prepare_initial() {
  mkdir -p "${LOCAL}"
  if [ ! "$(ls -A "${LOCAL}")" ]; then
    for f in ".ready" ".bisync_initialized"; do
      [ -f "${LOCAL}/${f}" ] && {
        echo "[cleanup] stale ${f} を削除"
        rm -f "${LOCAL}/${f}"
      }
    done
  fi
}

# --------------------------------------------------
# サイズ比較＆復元
# --------------------------------------------------
check_and_restore_if_needed() {
  sub=$1
  remote_size=$(rclone size "${REMOTE}/${sub}" --config /config/rclone.conf --json ${RC_ENC} | jq '.bytes')
  local_size=$(rclone size "${LOCAL}/${sub}"  --config /config/rclone.conf --json ${RC_ENC} | jq '.bytes')
  if [ "${remote_size}" -gt "${local_size}" ]; then
    echo "[restore] ${sub} ${local_size}→${remote_size}B"
    rclone copy "${REMOTE}/${sub}" "${LOCAL}/${sub}" \
      --config /config/rclone.conf --progress \
      --exclude ".ready" --exclude ".bisync_initialized" ${RC_ENC}
  fi
}

# --------------------------------------------------
# 初回同期
# --------------------------------------------------
initial_sync() {
  if [ -f "${READY_FILE}" ]; then
    echo "[rclone] 初回セットアップ済み"
    return
  fi

  echo "[rclone] 初回フルコピー ('.ready' '.bisync_initialized' を除外)"
  rclone sync "${REMOTE}" "${LOCAL}" \
    --config /config/rclone.conf --progress \
    --exclude ".ready" --exclude ".bisync_initialized" ${RC_ENC}

  for path in "${LOCAL}"/*; do
    [ -d "${path}" ] && check_and_restore_if_needed "${path##*/}"
  done

  touch "${READY_FILE}"
  echo "[rclone] 初回完了 (.ready 作成)"
}

# --------------------------------------------------
# バックアップ世代整理
# --------------------------------------------------
prune_backups() {
  target_root="$1"
  mode="$2"

  echo "[prune][${mode}] ${target_root} : 7日より前の世代を削除"

  if [ "${mode}" = "remote" ]; then
    NOW=$(date +%s)
    CUTOFF=$(( NOW - 7*24*3600 ))
    THRESHOLD=$(
      date -u -d "@${CUTOFF}" +%Y-%m-%d 2>/dev/null \
      || date -u -r "${CUTOFF}" +%Y-%m-%d
    )
    for sub in $(rclone lsd "${target_root}" --config /config/rclone.conf ${RC_ENC} 2>/dev/null | awk '{print $5}'); do
      [ "${sub}" \< "${THRESHOLD}" ] || continue
      echo "[prune][remote] purge ${sub}"
      rclone purge "${target_root}/${sub}" --config /config/rclone.conf --verbose ${RC_ENC} || true
    done
  else
    find "${target_root}" -mindepth 1 -maxdepth 1 -type d -mtime +7 -print -exec rm -rf {} \; || true
  fi
}

# --------------------------------------------------
# EPUB 一方向アップロード（変数が空なら何もしない）
# --------------------------------------------------
epub_upload() {
  if [ -z "${EPUB_LOCAL}" ] || [ -z "${EPUB_REMOTE}" ]; then
    return
  fi
  echo "[epub] Uploading ${EPUB_LOCAL} → ${EPUB_REMOTE}"
  rclone copy "${EPUB_LOCAL}" "${EPUB_REMOTE}" \
    --config /config/rclone.conf --progress --update ${RC_ENC}
}

# --------------------------------------------------
# 定期 bisync
# --------------------------------------------------
periodic_sync() {
  today=$(date +%F)
  echo "[rclone] bisync start (backup ${today})"

  mkdir -p "${BISYNC_WORKDIR}"
  BISYNC_OPTS="--workdir ${BISYNC_WORKDIR} --size-only --compare size"

  if [ ! -f "${BISYNC_FLAG_FILE}" ]; then
    BISYNC_OPT="--resync"
    echo "  --resync (初回 or 復旧)"
  else
    BISYNC_OPT=""
  fi

  if ! rclone bisync "${LOCAL}" "${REMOTE}" \
      --config /config/rclone.conf ${BISYNC_OPTS} \
      --backup-dir1 "${BACKUP_ROOT_LOCAL}/${today}" \
      --backup-dir2 "${BACKUP_ROOT_REMOTE}/${today}" \
      --checksum ${BISYNC_OPT} --verbose \
      --exclude ".ready" --exclude ".bisync_initialized" ${RC_ENC}; then
    echo "[rclone] bisync に失敗、フラグをリセット"
    rm -f "${BISYNC_FLAG_FILE}"
  else
    touch "${BISYNC_FLAG_FILE}"
  fi

  prune_backups "${BACKUP_ROOT_REMOTE}" "remote"
  prune_backups "${BACKUP_ROOT_LOCAL}"  "local"
}

# --------------------------------------------------
# メインループ
# --------------------------------------------------
main() {
  setup_rclone_conf
  prepare_initial
  # 必要なディレクトリをまとめて作成
  mkdir -p "${LOCAL}" "${BACKUP_ROOT_LOCAL}" "${BISYNC_WORKDIR}"
  initial_sync

  find /share/data -type f -name toc.yaml -exec sed -i 's/[\x00-\x08\x0B\x0C\x0E-\x1F]//g' {} \;

  # CRLF→LF 化（改行コードを Unix 形式に統一）
  if command -v dos2unix >/dev/null 2>&1; then
    echo "[cleanup] dos2unix で改行コードを変換中..."
    find /share/data -type f -exec dos2unix {} +
  fi

  while :; do
    # ループ開始時にステールロックを確実に削除
    rm -f "${BISYNC_WORKDIR}"/*.lck 2>/dev/null || true

    periodic_sync
    epub_upload
    echo "[cleanup] dos2unix で改行コードを変換中..."
    find /share/data -type f -exec dos2unix {} +
    echo "[rclone] 60 分スリープ"
    sleep 3600
  done
}

# スクリプト実行
main "$@"