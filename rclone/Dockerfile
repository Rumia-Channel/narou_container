# rclone/Dockerfile

FROM rclone/rclone:latest

# jq とディレクトリ作成
RUN apk add --no-cache jq coreutils findutils && \
    mkdir -p /config

# スクリプトを /config に配置
COPY backup.sh /config/backup.sh

# 実行権限を付与
RUN chmod +x /config/backup.sh

# ENTRYPOINT を /config/backup.sh に
ENTRYPOINT ["/bin/sh", "/config/backup.sh"]
