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
# rclone.conf 作成
# --------------------------------------------------
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

# --------------------------------------------------
# rclone に与える共通エンコードオプション
# --------------------------------------------------
RC_ENC="--local-encoding Raw --webdav-encoding Percent"

# --------------------------------------------------
# パス定義（定数はすべて大文字）
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
  # ローカルが空なら stale マーカーを削除
  if [ ! "$(ls -A "${LOCAL}")" ]; then
    for f in ".ready" ".bisync_initialized"; do
      if [ -f "${LOCAL}/${f}" ]; then
        echo "[cleanup] stale ${f} を削除"
        rm -f "${LOCAL}/${f}"
      fi
    done
  fi
}

# --------------------------------------------------
# サイズ比較＆復元
# --------------------------------------------------
check_and_restore_if_needed() {
  sub=$1
  remote_size=$(rclone size "${REMOTE}/${sub}" \
                  --config /config/rclone.conf --json ${RC_ENC} \
                | jq '.bytes')
  local_size=$(rclone size "${LOCAL}/${sub}" \
                  --config /config/rclone.conf --json ${RC_ENC} \
                | jq '.bytes')
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
    for sub in $(rclone lsd "${target_root}" \
                   --config /config/rclone.conf ${RC_ENC} 2>/dev/null \
                 | awk '{print $5}'); do
      [ "${sub}" \< "${THRESHOLD}" ] || continue
      echo "[prune][remote] purge ${sub}"
      rclone purge "${target_root}/${sub}" \
        --config /config/rclone.conf --verbose ${RC_ENC} || true
    done
  else
    find "${target_root}" -mindepth 1 -maxdepth 1 \
      -type d -mtime +7 \
      -print -exec rm -rf {} \; || true
  fi
}

# --------------------------------------------------
# EPUB 一方向アップロード
# --------------------------------------------------
epub_upload() {
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

  if rclone bisync "${LOCAL}" "${REMOTE}" \
      --config /config/rclone.conf ${BISYNC_OPTS} \
      --backup-dir1 "${BACKUP_ROOT_LOCAL}/${today}" \
      --backup-dir2 "${BACKUP_ROOT_REMOTE}/${today}" \
      --checksum ${BISYNC_OPT} --verbose \
      --exclude ".ready" --exclude ".bisync_initialized" ${RC_ENC}; then
    touch "${BISYNC_FLAG_FILE}"
  else
    echo "[rclone] bisync に失敗、フラグをリセット"
    rm -f "${BISYNC_FLAG_FILE}"
  fi

  prune_backups "${BACKUP_ROOT_REMOTE}" "remote"
  prune_backups "${BACKUP_ROOT_LOCAL}"  "local"
}

# --------------------------------------------------
# メイン
# --------------------------------------------------
main() {
  prepare_initial
  mkdir -p "${LOCAL}" "${BACKUP_ROOT_LOCAL}"
  initial_sync
  while :; do
    periodic_sync
    epub_upload
    echo "[rclone] 60 分スリープ"
    sleep 3600
  done
}

main "$@"