# 構築戦略

## 決定事項

- Windows の標準構成は WSL2 Ubuntu 24.04 内の Docker Engine・Linux 版 Docker CLI・Compose・Buildx。Docker Desktop は導入・標準検証対象に含めない。
- 最初の開発・検証先は、このリポジトリを配置した WSL2 / ARM64 環境。
- OpenFOAM は公式 apt を優先。ParaView は apt 版の無画面描画を検証した結果、OSMesa 版を採用。amd64 は公式バイナリ、ARM64 は同版のソースビルドを使う。
- 両 CPU でツールの版をそろえる。受講者はネイティブ CPU でローカルビルドし、エミュレーションは標準手順に含めない。
- ホストの導入自動化は Bash / PowerShell。メモリ16GBを暫定基準とし、ビルド並列数を指定可能にする。

## 段階と完了条件

| 段階 | 作業 | 完了条件 |
| --- | --- | --- |
| 1 | リポジトリ基礎、取得物固定、ARM64 のヘッドレス描画検証 | 描画方式と両 CPU の取得方法が確定 |
| 2 | 計算イメージ、Compose、実行入口、Python、スモークケース | ARM64 で直列・MPI・後処理・画像・動画・データ保持を確認 |
| 3 | amd64 ネイティブ検証と CI | 同一の版・ケースが両 CPU で動作 |
| 4 | Windows / WSL の段階別セットアップ、Crew / CLI 導入 | 新規 Windows ARM64 / x64 で配布ファイルだけから構築・接続 |
| 5 | リリースの固定 | Windows 両 CPU の実機検証、版・ライセンス・資料を確定 |
| 6 | Apple Silicon Mac | Docker Desktop を前提としない実行基盤を選び、共通ケースを検証 |

初期実装対象は段階1〜2。段階3向けに両 CPU 共通の Dockerfile とネイティブ CI を用意する。実施済みの検証は `validation.md` に記録する。

Crew・Kiro CLI・OpenCode は計算コンテナ完成後、この WSL に導入して接続検証する。各製品の認証は独立した対話工程とし、イメージや Git に含めない。Windows のブラウザーから Crew の localhost へ接続する。OpenCode のバックエンド選択が Preview である点を含め、互換性を確認した版を固定してから自動化する。

## 操作とデータ

- `build-image.sh`：ネイティブ CPU 用ビルドと構築記録の保存。
- `run-tool.sh <command> [args...]`：通常ユーザーの UID/GID で一時コンテナを実行。終了コード・引数を保持。
- `check-environment.sh`：CPU、接続先、導入状態、イメージの診断。設定は変更しない。
- `smoke-test.sh`：原本を実行別の `work/smoke-*` にコピーし、一連の処理と永続化を検証。

一般 Python は `/opt/post-venv`、ParaView の Python は `/opt/paraview` に分ける。`python` / `python3` は後処理用 venv、`pvpython` / `pvbatch` は可視化用とする。
