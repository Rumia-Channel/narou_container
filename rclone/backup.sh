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
# rclone.conf
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
# パス定義
# --------------------------------------------------
LOCAL="/share/data"
REMOTE="${WEBDAV_REMOTE_NAME}:${WEBDAV_PATH}"
BACKUP_ROOT_LOCAL="/share/_archive/data"
BACKUP_ROOT_REMOTE="${WEBDAV_REMOTE_NAME}:archive${WEBDAV_PATH}"
READY_FILE="${LOCAL}/.ready"

# bisync の作業フォルダ（named volume 経由で永続化）
BISYNC_WORKDIR="/config/bisync_work"
mkdir -p "${BISYNC_WORKDIR}"

# --------------------------------------------------
# サイズ比較＆復元
# --------------------------------------------------
check_and_restore_if_needed() {
  sub=$1
  remote_size=$(rclone size "${REMOTE}/${sub}" --json --config /config/rclone.conf | jq '.bytes')
  local_size=$( rclone size  "${LOCAL}/${sub}" --json --config /config/rclone.conf | jq '.bytes')
  if [ "${remote_size}" -gt "${local_size}" ]; then
    echo "[restore] ${sub} ${local_size}→${remote_size}B"
    rclone copy "${REMOTE}/${sub}" "${LOCAL}/${sub}" \
      --config /config/rclone.conf --progress
  fi
}

# --------------------------------------------------
# 初回同期
# --------------------------------------------------
initial_sync() {
  [ -f "${READY_FILE}" ] && { echo "[rclone] 初回セットアップ済み"; return; }

  echo "[rclone] 初回フルコピー"
  rclone sync "${REMOTE}" "${LOCAL}" \
    --config /config/rclone.conf --progress

  for path in "${LOCAL}"/*; do
    [ -d "${path}" ] && check_and_restore_if_needed "${path##*/}"
  done

  touch "${READY_FILE}"
  echo "[rclone] 初回完了 (.ready 作成)"
}

# =====================================
# バックアップ世代整理 (BusyBox 対応)
#   ・find の -printf を使わずシンプルな for ループ
#   ・削除基準は "7 days ago" を busybox date -d で計算
prune_backups() {
  target_root="$1"   # ex: ${BACKUP_ROOT_REMOTE}
  mode="$2"          # "remote" or "local"

  echo "[prune][${mode}] ${target_root} : 7日より前の世代をディレクトリ単位で削除"

  if [ "${mode}" = "remote" ]; then
    # ── 日付閾値を計算 ──
    NOW=$(date +%s)
    CUTOFF=$(( NOW - 7*24*3600 ))
    # BusyBox でも動くように -d "@…" or -r fallback
    THRESHOLD=$(date -u -d "@${CUTOFF}" +%Y-%m-%d 2>/dev/null \
                || date -u -r "${CUTOFF}" +%Y-%m-%d)

    # ── サブディレクトリを列挙して、名前で比較 ──
    for sub in $(rclone lsd "${target_root}" \
                   --config /config/rclone.conf 2>/dev/null \
                 | awk '{print $5}'); do
      [ "${sub}" \< "${THRESHOLD}" ] || continue
      echo "[prune][remote] purge ${sub}"
      rclone purge "${target_root}/${sub}" \
        --config /config/rclone.conf --verbose || true
    done
  else
    # ローカル側
    find "${target_root}" -mindepth 1 -maxdepth 1 \
      -type d -mtime +7 \
      -print -exec rm -rf {} \; || true
  fi
}

# --------------------------------------------------
# 定期 bisync
# --------------------------------------------------
periodic_sync() {
  today=$(date +%F)
  echo "[rclone] bisync start (backup ${today})"

  bisync_opts="--workdir ${BISYNC_WORKDIR} --size-only --compare size"

  # ① 初回フラグが無ければ --resync
  if [ ! -f "${LOCAL}/.bisync_initialized" ]; then
    BISYNC_OPT="--resync"
    echo "  --resync (初回 or 前回エラー復旧)"
  else
    BISYNC_OPT=""
  fi

  if rclone bisync "${LOCAL}" "${REMOTE}" \
    --config /config/rclone.conf \
    --backup-dir1 "${BACKUP_ROOT_LOCAL}/${TODAY}" \
    --backup-dir2 "${BACKUP_ROOT_REMOTE}/${TODAY}" \
    --checksum ${BISYNC_OPT} --verbose; then
    touch "${LOCAL}/.bisync_initialized"
  else
    echo "[rclone] bisync に失敗したため .bisync_initialized をリセット"
    rm -f "${LOCAL}/.bisync_initialized"
  fi

  prune_backups "${BACKUP_ROOT_REMOTE}" "remote"
  prune_backups "${BACKUP_ROOT_LOCAL}" "local"
}

# --------------------------------------------------
# メイン
# --------------------------------------------------
main() {
  mkdir -p "${LOCAL}" "${BACKUP_ROOT_LOCAL}"
  initial_sync
  while :; do
    periodic_sync
    echo "[rclone] 60 分スリープ"
    sleep 3600
  done
}

main "$@"