FROM tailscale/tailscale:stable

RUN apk add --no-cache bash curl jq openssl

# entrypoint.sh をルートにコピー
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
