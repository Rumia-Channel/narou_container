# nginx/Dockerfile
FROM nginx:stable

# 必要パッケージ & Tailscale リポジトリ追加 → tailscale インストール
RUN apt-get update && \
    apt-get install -y curl apt-transport-https gnupg lsb-release jq && \
    \
    # Tailscale の GPG 鍵を追加
    curl -fsSL https://pkgs.tailscale.com/stable/debian/$(lsb_release -cs).noarmor.gpg \
      | gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg && \
    \
    # ソースリストに Tailscale レポジトリを追加
    echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian \
      $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/tailscale.list && \
    \
    # パッケージリスト更新＆tailscaleインストール
    apt-get update && \
    apt-get install -y tailscale iptables openssl && \
    \
    # キャッシュ削除
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
