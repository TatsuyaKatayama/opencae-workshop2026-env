# OpenCAE Workshop 2026 Environment

OpenCAE 講習会向けの、AI エージェントから計算・可視化・動画生成を行う環境です。Windows 11 ARM64／x64 を対象とし、専用の WSL2 Ubuntu 24.04 と Docker Engine を使用します。Docker Desktop は導入しません。

## Windows：事前準備

1. WSL2 を利用可能にします。未導入なら管理者 PowerShell で `wsl --install --no-distribution` を実行し、Windows を再起動します。
2. 本プロジェクトを Git clone または ZIP ダウンロード・解凍で取得します。
3. 取得先で通常ユーザーの64ビット PowerShell を開き、次を実行します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup\windows\Setup.ps1 -UserName workshop
```

**保存先は実行時に質問します。** Enter だけなら表示された既定値を使用し、再開時は記録済みの保存先を候補にします。Linux ユーザーの sudo 用パスワードも端末で設定します。

環境名・保存先を指定する例：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup\windows\Setup.ps1 `
  -DistroName ubuntu_of_kiro `
  -UserName workshop `
  -InstallLocation C:\wsl_img\ubuntu_of_kiro
```

専用 Ubuntu の新規作成、Docker・Kiro CLI・Crew・OpenCode・Codex CLI の導入、CFD イメージのローカルビルドと検証、デスクトップショートカット作成まで行います。既存 WSL は流用しません。詳細と Proxy プレビュー、途中再開は [Windows 手順](docs/windows.md) を参照してください。

メモリ16GBを暫定基準とし、ビルドは標準2並列です。特に ARM64 の ParaView コンパイルは時間がかかるため、事前に完了してください。ビルド済みイメージは公開・配布しません。

## 当日の操作

デスクトップに環境名付きで作成されたショートカットを使用します。

1. **Kiro CLI Login**：未認証なら端末の案内に従い、既定ブラウザーで認証します。
2. **Start Kiro Crew**：Crew を起動し、ブラウザーで開きます。
3. **Stop Kiro Crew**：終了時に Crew を停止します。Docker や計算コンテナは停止しません。

認証 URL を自動で開けない場合は端末の URL をブラウザーで開きます。認証コードや Crew のアクセス URL は共有しないでください。

## Ubuntu から直接利用する場合

Ubuntu 24.04、systemd、sudo 権限を持つ通常ユーザーで、Linux ファイルシステム内にプロジェクトを配置します。

```bash
cd ~/opencae-workshop2026-env
bash setup/ubuntu2404/setup.sh
bash setup/ubuntu2404/kiro-login.sh
bash setup/ubuntu2404/crew-start.sh
bash setup/ubuntu2404/crew-stop.sh
```

[Bash セットアップの詳細](setup/ubuntu2404/README.md) を参照してください。導入済みの計算環境を個別に操作する場合：

```bash
scripts/run-tool.sh blockMesh -help
scripts/run-tool.sh pvpython --version
scripts/check-environment.sh
scripts/smoke-test.sh
```

成果物・ログは `work/` に保存されます。スモークケースは毎回コピーし、過去の結果を上書きしません。ビルドだけを再実行する場合は `BUILD_JOBS=2 scripts/build-image.sh` を使用します。

## 検証と構成

Ubuntu ARM64／amd64 の新規導入・CFD ビルド・計算・CPU 描画・動画生成は CI 成功済みです。Windows x64／ARM64 の PowerShell 5.1／7 で制御テストも成功しています。Windows 実機での通し確認と macOS 対応は残っています。検証済み範囲は [検証記録](docs/validation.md) を参照してください。

OpenFOAM v2606 は公式 apt、ParaView 5.13.3 は OSMesa 対応版を使用します。amd64 は公式バイナリ、ARM64 はソースビルドです。OpenFOAM の採用 apt 版は **2606.0~rc2-1** であり、正式版ソースと同一とは扱いません。一般の Python 後処理は ParaView と別の venv です。

## Windows で文字化けする場合

この README は **UTF-8 BOM 付き**です。VS Code などでは文字コードを UTF-8 として開いてください。PowerShell で読む場合は明示します。

```powershell
Get-Content -Encoding UTF8 .\README.md
```

Bash が読み込む `*.env` は UTF-8（BOM なし）・LF 改行を維持します。`.gitattributes` で LF を指定しており、エディターで CRLF に変更しないでください。設定 JSON の読み取りも PowerShell 側で UTF-8 を明示しています。

## 関連資料

- [仕様書](PROJECT_SPEC.md)
- [ビルド・キャッシュ・依存関係の更新](docs/image-build.md)
- [セットアップのテスト計画](docs/setup-test-plan.md)
- [エージェントの操作](docs/agents.md)
- [第三者ソフトと取得元](THIRD_PARTY_NOTICES.md)

独自のコード・設定・文書は Apache-2.0 です。第三者ソフトは各ライセンスに従います。
