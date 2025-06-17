# ベースイメージを Ruby＋Debian Bookworm Slim に
FROM ruby:slim-bookworm

# 必要最低限のパッケージ（git やビルドに必要なツールなど）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash curl expect git build-essential ca-certificates jq unzip && \
    curl -fsSL https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb -o /tmp/jdk-21.deb && \
    dpkg -i /tmp/jdk-21.deb && \
    apt-get -f install -y --no-install-recommends && \
    rm -f /tmp/jdk-21.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# specific_install と Bundler をインストール
RUN gem install specific_install bundler --no-document

# EPUB 出力用ディレクトリを作成
WORKDIR /share/epub

# 実データ格納用ディレクトリを作成かつ作業ディレクトリに設定
WORKDIR /share/data

# エントリポイントスクリプトをコピーし、実行権限を付与
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# コンテナ起動時に entrypoint.sh を実行
ENTRYPOINT ["/entrypoint.sh"]
