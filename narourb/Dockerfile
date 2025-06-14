# ベースイメージを Ruby＋Debian Bookworm Slim に
FROM ruby:slim-bookworm

# 必要最低限のパッケージ（git やビルドに必要なツールなど）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash curl expect git build-essential ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# specific_install と Bundler をインストール
RUN gem install specific_install bundler --no-document

# 作業ディレクトリを /share/data に設定
WORKDIR /share/data

# エントリポイントスクリプトをコピーし、実行権限を付与
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# コンテナ起動時に entrypoint.sh を実行
ENTRYPOINT ["/entrypoint.sh"]
