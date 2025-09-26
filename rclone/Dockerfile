# rclone/Dockerfile
FROM rclone/rclone:latest

# 必要最小限のパッケージだけ追加
# - jq        : rclone size --json の解析
# - findutils : GNU find（-print0/ -d '' を使うため）
# - dos2unix  : 改行コード正規化（任意利用）
RUN set -eux; \
    apk add --no-cache bash jq findutils dos2unix && \
    mkdir -p /config /share/epub /share/zip /share/_archive/data /config/bisync_work

# スクリプト配置（実行権限付与）
COPY backup.sh /config/backup.sh
RUN chmod 0755 /config/backup.sh

# BusyBox/ash で実行（bash は必用）
ENTRYPOINT ["/bin/bash", "/config/backup.sh"]
