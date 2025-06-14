# Debian＋Rye＋Playwright 依存ライブラリ
FROM debian:bookworm-slim

# 1) 必要パッケージ
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash curl git ca-certificates \
        libnss3 libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libxkbcommon0 \
        libxcomposite1 libxdamage1 libxrandr2 libasound2 libgtk-3-0 libxshmfence1 \
        libgbm1 libpango-1.0-0 libpangocairo-1.0-0 libx11-xcb1 libxfixes3 \
        libx11-6 libxext6 libxtst6 libwayland-client0 libwayland-cursor0 \
        libwayland-egl1 libxrender1 libglu1-mesa fonts-liberation \
        libgdk-pixbuf2.0-0 libu2f-udev xvfb xauth && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 2) エントリポイント & 付随ファイル
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]