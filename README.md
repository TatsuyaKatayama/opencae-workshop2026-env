# OpenCAE Workshop 2026 Environment

OpenCAE 講習会向けの計算・可視化・動画生成環境です。仕様は [PROJECT_SPEC.md](PROJECT_SPEC.md)、段階別の構築方針は [docs/implementation.md](docs/implementation.md) にまとめています。

Windows では **WSL2 Ubuntu 24.04 内の Docker Engine / CLI・Compose・Buildx** を使用します。Docker Desktop は導入しません。

## 現在の実装範囲

初期実装は ARM64 の計算コンテナと、そのビルド・診断・スモーク検証です。OpenFOAM v2606 は公式 apt、ParaView は CPU ヘッドレス描画用の OSMesa 版を利用し、amd64 は公式バイナリ、ARM64 はソースビルドを使います。一般の Python 後処理には専用 venv を用意します。

`openfoam2606` の取得時の apt 版は **2606.0~rc2-1** です。正式版ソースの v2606 と同一内容であるとは扱いません。講習用の正式リリース判定は [検証記録](docs/validation.md) を参照してください。

Linux amd64 のネイティブ CI と、ローカル WSL2 / ARM64 の両方で、計算・CPU 描画・動画生成・データ保持まで通過しました。ARM64 の修正版 CI は再検証中です。Windows の新規導入と認証・起動・終了スクリプトを実装しました。Windows 実機での受け入れと macOS 対応は後続です。Crew → Kiro CLI → 計算コンテナの実行と動画生成は利用者による操作で確認済みです。この WSL の Kiro CLI / Crew は導入済みで、認証と操作は [エージェントの手順](docs/agents.md) を参照してください。

## はじめる

前提は WSL2 Ubuntu 24.04、通常ユーザーから利用できる WSL 内の Docker Engine、Compose・Buildx、Git です。作業場所は WSL の Linux ファイルシステム内に置きます。既存 Engine の確認方法は [Windows の手順](docs/windows.md) を参照してください。

```bash
cd ~/opencae-workshop2026-env
scripts/build-image.sh
scripts/check-environment.sh
scripts/smoke-test.sh
```

メモリ16GBを暫定基準とし、ビルドは標準2並列です。初回は ParaView のコンパイルに時間がかかります。

```bash
BUILD_JOBS=2 scripts/build-image.sh
scripts/run-tool.sh blockMesh -help
scripts/run-tool.sh python -c 'import foamlib, numpy, scipy, matplotlib, japanize_matplotlib, optuna, pandas'
scripts/run-tool.sh pvpython --version
```

結果・ログ・構築記録は `work/` に保存されます。コンテナを再作成しても残ります。スモークケースは実行ごとにコピーし、過去の結果を上書きしません。任意のディレクトリからスクリプトを呼び出すこともできます。

- [ビルド、キャッシュ、依存関係の更新](docs/image-build.md)
- [検証済み範囲と残りの確認](docs/validation.md)
- [第三者ソフトと取得元](THIRD_PARTY_NOTICES.md)

独自のコード・設定・文書は Apache-2.0 です。コンテナに含まれる第三者ソフトはそれぞれのライセンスに従います。

## Ubuntu 24.04 セットアップの実装

Bash の導入・認証・Crew 起動／停止は [setup/ubuntu2404](setup/ubuntu2404/README.md) にあります。新規導入と CFD ビルドの統合テストは ARM64／amd64 のネイティブ CI で実施します。Windows の WSL 新規作成・ショートカット・認証・起動終了は [Windows 手順](docs/windows.md) を参照してください。

Windows の事前準備の入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup\windows\Setup.ps1 -UserName workshop
```

当日は **Kiro CLI Login → Start Kiro Crew**、終了時は **Stop Kiro Crew** を使用します。
