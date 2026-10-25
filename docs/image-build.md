# 計算イメージのビルド

## 実行

WSL 内の Linux Docker CLI から実行します。ローカルの `/var/run/docker.sock` を使い、Desktop・別 CPU のデーモン・リモートデーモンへの接続は入口で停止します。

```bash
scripts/build-image.sh
BUILD_JOBS=2 scripts/build-image.sh
scripts/build-image.sh --no-cache
scripts/check-environment.sh
scripts/smoke-test.sh
```

ローカル名は `opencae-workshop2026-env/cfd-tools:of2606-r1` です。変更がなければ Docker のレイヤーキャッシュを使用します。途中の失敗後も同じコマンドで再実行できます。`--no-cache` はビルドをやり直す必要があるときに使用します。

初回はネットワーク接続が必要です。ビルド完了後は、スモーク処理に外部のモデル認証や GHCR を必要としません。再ビルドには配布元への接続が必要になる場合があります。

## 固定するもの

- Ubuntu 24.04：両 CPU を含む OCI index digest。
- Ubuntu パッケージ：`APT_SNAPSHOT` 日時の署名付きリポジトリ。TLS 初期化用 CA パッケージのみ通常の Ubuntu リポジトリから `20240203` を取得し、証明書をコピーします。
- OpenFOAM：公式署名鍵の SHA256 と apt パッケージ版。apt が署名付き一覧にあるパッケージのハッシュを確認します。初期候補は `2606.0~rc2-1` です。
- ParaView：5.13.3。amd64 は公式 OSMesa / MPI / Python 3.10 バイナリの URL と SHA256、ARM64 はソース URL と SHA256 を固定します。ARM64 は CATALYST_RENDERING edition で Qt・X・EGL を無効、OSMesa と Python 3.12 を有効にしてビルドします。
- uv：0.9.10 の CPU 別アーカイブと SHA256。
- 後処理 Python：`requirements.in` と、推移依存を含むハッシュ付き `requirements.lock`。

amd64 の `pvpython` / `pvbatch` は起動ラッパーで `--mesa --backend llvmpipe` を指定し、公式配布物の `lib/mesa` を使用します。ARM64 のソースビルドにはこの launcher 用引数を渡しません。

OpenFOAM の `-default` パッケージは開発ヘッダーやコンパイラー等も依存関係として含みます。ParaView のビルド用ステージとは別に、OpenFOAM の公式パッケージ構成として導入します。

## 結果の確認

`work/build-*` にはビルドログ、経過秒数、並列数、CPU、Git 状態、固定値、イメージ ID・サイズ、実際の apt パッケージ一覧を保存します。失敗時も終了コードとログを残します。コンテナ内の `/opt/workshop-manifest` には Python の版一覧と ffmpeg のビルド設定も保存します。

ビルド時間・必要な空き容量・ピークメモリは実測に基づいて受講要件を確定します。ビルドスクリプトが測る経過時間にはダウンロードも含みます。Docker CLI 自身のメモリ使用量をビルダーのピークメモリとして報告しません。

## 依存関係の更新

`requirements.in` を変更した場合は uv 0.9.10 で次を実行し、差分をレビューします。

```bash
uv pip compile containers/cfd-tools/requirements.in \
  --python-version 3.12 --universal --generate-hashes \
  --output-file containers/cfd-tools/requirements.lock
```

`versions.env`、ロックファイル、イメージタグを対応付けて更新し、両 CPU のビルド・スモーク検証をやり直します。ベース、APT スナップショット、取得物を変更した場合も同様です。
