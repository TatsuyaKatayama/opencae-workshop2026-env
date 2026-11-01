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

専用 Ubuntu の新規作成、Docker・Kiro CLI・Crew・OpenCode・Codex CLI の導入、CFD イメージのローカルビルドと検証、インストール先への起動スクリプト配置まで行います。既存 WSL は流用しません。詳細と Proxy プレビュー、途中再開は [Windows 手順](docs/windows.md) を参照してください。

メモリ16GBを暫定基準とし、ビルドは標準2並列です。ARM64 の ParaView もビルド済みの OSMesa パッケージを使用します。初回の取得・イメージ構築は事前に完了してください。ビルド済みイメージは公開・配布しません。

## 当日の操作

WSL のインストール先（例 `C:\wsl_img\opencae-workshop2026`）に置かれた次のファイルをダブルクリックします。

1. **1_StartBackend.cmd**：Kiro CLI・Codex・OpenCode を選び、端末の案内に従って認証します。Codex はデバイスコード認証、OpenCode は提供先ごとの認証です。
2. **2_StartCrew.cmd**：Crew を起動し、ブラウザーで開きます。
3. **3_StopCrew.cmd**：終了時に Crew を停止します。Docker や計算コンテナは停止しません。

Crew の管理画面はバックエンド未認証でも起動できます。バックエンド変更時は Stop → Start で反映します。OpenCode は提供先とモデルも画面で選びます。KAS は導入・選択しません。

PS1 は保存先の `scripts` フォルダーにまとめます。環境を完全に削除する場合だけ **9_Allclean.cmd** を使用してください。対象とデータ消失の警告が表示され、`DELETE` と入力するまで削除しません。

認証 URL を自動で開けない場合は端末の URL をブラウザーで開きます。認証コードや Crew のアクセス URL は共有しないでください。

専用 WSL を削除する場合は、[Windows 手順の環境削除](docs/windows.md#環境の削除)を参照してください。

既存環境を起動スクリプト方式へ更新する場合は、取得元のリポジトリで次を実行します。WSL・CFD の再構築は行いません。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup\windows\UpdateLaunchers.ps1 `
  -DistroName opencae-workshop2026 -InstallLocation C:\wsl_img\opencae-workshop2026
```

設定はインストール先の `environment.json` に保存します。旧 AppData の記録は移行元として読み取り、デスクトップの古いショートカットは手動で削除してください。

## Apple Silicon Mac

macOS 15 以降とネイティブ Homebrew を用意し、プロジェクト内で実行します。Docker Desktop は使わず、専用 Colima で Linux ARM64 コンテナを動かします。

```bash
bash setup/macos/setup.sh
```

当日は `setup/macos/1_StartBackend.command` → `2_StartCrew.command`、終了時は `3_StopCrew.command` を使用します。CLI と Crew は Mac 上で動作します。導入要件・再開・CI と実機確認の範囲は [macOS 手順](docs/macos.md) を参照してください。

## Ubuntu から直接利用する場合

Ubuntu 24.04、systemd、sudo 権限を持つ通常ユーザーで、Linux ファイルシステム内にプロジェクトを配置します。

```bash
cd ~/opencae-workshop2026-env
bash setup/ubuntu2404/setup.sh
bash setup/ubuntu2404/start-backend.sh --backend kiro
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

Ubuntu ARM64／amd64 の新規導入・CFD ビルド・計算・CPU 描画・動画生成は CI 成功済みです。Windows x64／ARM64 の PowerShell 5.1／7 で制御テストも成功しています。Windows 版は利用者による実機確認を完了し、v1.0.0 としてリリースしました。Apple Silicon macOS 用スクリプトも実装しています。Colima を含む実機受け入れは未実施です。検証済み範囲は [検証記録](docs/validation.md) を参照してください。

OpenFOAM v2606 は公式 apt、ParaView 5.13.3 は OSMesa 対応版を使用します。amd64 は公式バイナリ、ARM64 は conda-forge の同版 OSMesa バイナリと依存ロックを使用します。OpenFOAM の採用 apt 版は **2606.0~rc2-1** であり、正式版ソースと同一とは扱いません。一般の Python 後処理は ParaView と別の venv です。

## Windows で文字化けする場合

この README は **UTF-8 BOM 付き**です。VS Code などでは文字コードを UTF-8 として開いてください。PowerShell で読む場合は明示します。

```powershell
Get-Content -Encoding UTF8 .\README.md
```

Bash が読み込む `*.env` は UTF-8（BOM なし）・LF 改行を維持します。`.gitattributes` で LF を指定しており、エディターで CRLF に変更しないでください。設定 JSON の読み取りも PowerShell 側で UTF-8 を明示しています。

## 関連資料

- [v1.0.0 リリースノート](docs/releases/v1.0.0.md)
- [仕様書](PROJECT_SPEC.md)
- [ビルド・キャッシュ・依存関係の更新](docs/image-build.md)
- [セットアップのテスト計画](docs/setup-test-plan.md)
- [エージェントの操作](docs/agents.md)
- [第三者ソフトと取得元](THIRD_PARTY_NOTICES.md)

独自のコード・設定・文書は Apache-2.0 です。第三者ソフトは各ライセンスに従います。
