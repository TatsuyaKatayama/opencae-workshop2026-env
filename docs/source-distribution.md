# ソースと取得元

通常の配布物はこのリポジトリの Dockerfile、設定、スクリプトです。第三者ソフトは受講者のビルド時に取得します。バイナリイメージの GHCR 配布は実装していません。

| 対象 | 固定情報・対応するソース |
| --- | --- |
| Ubuntu | `versions.env` のベース digest と `APT_SNAPSHOT`。https://snapshot.ubuntu.com/ の同日時点のソースパッケージ |
| OpenFOAM apt | `OPENFOAM_DEB_VERSION`。`openfoam2606-source` 同版が `-default` の依存としてイメージに入る。公式 https://dl.openfoam.com/repos/deb/dists/noble/main/ |
| OpenFOAM 正式版ソース | `OPENFOAM_URL` と `OPENFOAM_SHA256` に記録。apt の RC2 パッケージと同一内容とは扱わず、現行ビルドには使用しない |
| ParaView | ARM64 は `PARAVIEW_URL` と `PARAVIEW_SHA256`、amd64 は `PARAVIEW_AMD64_URL` と `PARAVIEW_AMD64_SHA256`。同じ 5.13.3 のソースと公式 OSMesa 配布物を使用。ARM64 はソースを変更せず CMake オプションで構築 |
| uv | `UV_VERSION`、CPU 別 SHA256。https://github.com/astral-sh/uv/releases/tag/0.9.10 と対応タグのソース |
| Python | `containers/cfd-tools/requirements.lock` に版・配布物 SHA256。PyPI の対応版ソース |

OpenFOAM はリポジトリ限定の署名鍵を `signed-by` で指定します。鍵の取得物 SHA256 を固定し、配布側の鍵更新はレビューして反映します。パッケージ版が取得できなくなった場合はビルドを失敗させ、別版へ自動更新しません。

uv のバイナリ配布物のライセンスをイメージへ同梱します。ParaView はインストールされるライセンスに加え、上流ソースのライセンス表示を保存します。Ubuntu と Python パッケージの表示も削除しません。

将来 GHCR 等でバイナリイメージを配布する場合は、タグ・digest と実際に含むパッケージ一覧を確定し、必要な対応ソース、パッチ、ビルド設定、取得方法、提供期間を整備してから公開します。Dockerfile の公開だけをもって、その対応が完了したとは扱いません。
