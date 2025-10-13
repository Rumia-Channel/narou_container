# ベースイメージを Ruby＋Debian Bookworm Slim に
FROM ruby:slim-bookworm

# 非対話とパスの基本設定
ENV DEBIAN_FRONTEND=noninteractive

# 必要最低限のパッケージ（git やビルドに必要なツールなど）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      bash curl expect git build-essential ca-certificates jq unzip wget locales; \
    # ルート証明書を更新
    update-ca-certificates; \
    # Oracle JDK を取得・インストール
    curl -fsSL https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb -o /tmp/jdk-21.deb; \
    dpkg -i /tmp/jdk-21.deb || apt-get -f install -y --no-install-recommends; \
    rm -f /tmp/jdk-21.deb; \
    # ロケールファイルを有効化
    sed -i 's/# *ja_JP.UTF-8/ja_JP.UTF-8/' /etc/locale.gen; \
    sed -i 's/# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen; \
    locale-gen; \
    update-locale LANG=ja_JP.UTF-8 LC_ALL=ja_JP.UTF-8; \
    # キャッシュ削除で軽量化
    apt-get purge -y --auto-remove; \
    rm -rf /var/lib/apt/lists/*

# 既定ロケールを環境変数でも固定
ENV LANG=ja_JP.UTF-8 \
    LC_ALL=ja_JP.UTF-8 \
    LANGUAGE=ja_JP:ja \
    JAVA_HOME=/usr/lib/jvm/jdk-21 \
    PATH="/usr/lib/jvm/jdk-21/bin:${PATH}"

# Ruby の既定エンコードも揃えたい場合はコメントを外す
# ENV RUBYOPT="-EUTF-8:UTF-8"

# EPUB 出力用ディレクトリを作成
WORKDIR /share/epub

# 実データ格納用ディレクトリを作成かつ作業ディレクトリに設定
WORKDIR /share/data

# エントリポイントスクリプトをコピーし、実行権限を付与
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
COPY dl_cover.sh /dl_cover.sh
RUN chmod +x /dl_cover.sh

# コンテナ起動時に entrypoint.sh を実行
ENTRYPOINT ["/entrypoint.sh"]
