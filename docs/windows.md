# Windows / WSL のセットアップ

Windows 11 ARM64／x64 が対象です。事前に専用の WSL2 Ubuntu 24.04 を作成し、当日はデスクトップのショートカットから認証・Crew の起動・停止を行います。Docker Desktop は使用しません。

## 事前準備

1. WSL2 を利用可能にします。未導入なら管理者 PowerShell で `wsl --install --no-distribution` を実行し、Windows を再起動します。必要に応じて `wsl --update` で更新します。
2. 本プロジェクトを Git clone または ZIP ダウンロード・解凍で取得します。ZIP は Windows で「すべて展開」を行ってください。
3. **通常ユーザーの64ビット PowerShell** を開き、取得先で次を実行します。日常操作と同じ Windows ユーザーで実行し、別の管理者アカウントでは実行しません。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup\windows\Setup.ps1 -UserName workshop
```

Linux ユーザー名を省略すると入力を求めます。保存先も `-InstallLocation` を省略すると入力を求め、Enter だけなら表示された既定値を使用します。再開時は記録済みの保存先を候補にします。新しい Linux ユーザーの sudo 用パスワードは端末で2回入力します（文字は表示されません）。認証情報はセットアップに保存しません。

環境名・保存先・Crew ポートを変える場合：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup\windows\Setup.ps1 `
  -DistroName opencae-2026 `
  -UserName workshop `
  -InstallLocation D:\WSL\opencae-2026 `
  -Port 5476
```

Ubuntu の公式 rootfs を取得し、プロジェクトで固定した SHA256 と照合して `wsl --import --version 2` で新規作成します。環境名は既定で `opencae-workshop2026`、保存先は `%LOCALAPPDATA%\OpenCAE\WSL\<環境名>`。既存環境は流用・削除しません。WSL 本体の初期導入や Windows の再起動が必要な場合は準備を案内して停止します。

指定ユーザー・sudo・systemd を初期化し、プロジェクトを `/home/<ユーザー>/opencae-workshop2026-env` にコピーします。Git 管理情報、認証領域、既存の `work/` はコピーしません。Linux のセットアップが Docker Engine／Compose／Buildx、Kiro CLI・Crew・OpenCode・Codex CLI を導入し、CFD イメージのローカルビルドと計算・描画・動画の確認を行います。ARM64 の ParaView ビルドは時間がかかるので、講習前に完了してください。進捗は端末へ表示します。

## 完了後と当日の操作

デスクトップに環境名を付けた3つのショートカットが作成されます。

1. **Start Backend**：`1: Kiro CLI / 2: Codex / 3: OpenCode` を選択します。Kiro CLI・Codex は認証済みなら再ログインせず、未認証ならデバイス認証を開始します。Codex は ChatGPT の個人設定または組織設定でデバイスコード認証の許可が必要です。OpenCode は提供先を選んで API キーまたは OAuth で認証します。既に設定済みの提供先やローカルモデルを使う場合はログイン確認に `n` を入力できます。
2. **Start Kiro Crew**：起動完了後に既定ブラウザーで Crew を開きます。起動済みならその画面を開きます。端末を閉じても Crew は動きます。
3. **Stop Kiro Crew**：終了時に実行します。この環境の Crew のみ停止し、Docker や計算コンテナは停止しません。ブラウザーのタブは自分で閉じます。

Crew の管理画面はバックエンドの認証前にも起動できます。バックエンドを変更した場合は Stop → Start で反映します。OpenCode の保存済み認証だけではモデル利用可否を断定できないため、Crew で提供先・モデルを選択し、会話を確認してください。KAS は使用しません。

認証 URL を自動で開けない場合は、端末に表示された URL を手動でブラウザーに貼り付けます。URL とコードを共有ログへ保存しないでください。Crew の URL もアクセス権を含みます。エラー時は端末が残るので内容を確認します。

起動用 PS1 と環境設定は `%LOCALAPPDATA%\OpenCAE\environments\<環境名>` に保存します。元の ZIP 解凍先を移動・削除してもショートカットを使用できます。WSL の登録名・Linux ユーザー・プロジェクト配置先は記録済みなので、当日に再入力する必要はありません。

## ショートカットだけ更新する場合

リポジトリを更新した後、次を実行すると、保存済みの起動スクリプトとショートカットだけを更新できます。Docker／CFD の再構築や WSL の作成は行いません。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup\windows\RefreshShortcuts.ps1
```

既定以外の登録名では `-DistroName <登録名>`、設定を直接指定する場合は `-ConfigPath <environment.json>` を追加します。作成済みの各リンクは起動先・引数・作業フォルダーを保存後に照合します。PowerShell は `-NoExit` で起動するため、結果を確認したら端末を閉じてください。OneDrive でデスクトップを同期する場合、別 PC のショートカットが同期されることがあるため、利用する PC で更新してください。

## 失敗した場合の再開

同じ取得元で、**初回と同じ環境名・ユーザー名・保存先・ポート**を指定して Setup.ps1 を再実行します。 Git clone の場合は配布対象ブランチを更新してください。現在のセットアップは新規環境用です。WSL 内と取得元の固定ツール版が異なる場合は更新せず停止するため、別の環境名・保存先で構築してください。初回配置・再実行時に、WSL 内の `versions.env`・`setup/config/agents.env`・`setup/config/docker.env` を UTF-8 BOM なし・LF に揃えます。Windows 側の元ファイルは変更せず、固定版の比較でも改行・BOM だけの違いは無視します。再実行時は Windows 側の `scripts/smoke-test.sh` を既存 WSL 内へ反映し、内容の一致を確認してから検証へ進みます。手動コピーは不要です。作業データ・認証情報・イメージは削除しません。本スクリプトの設定、WSL 登録 ID・保存先、Linux 側の識別記録を照合して再開します。作成済みの別環境やデータのある保存先は上書きしません。インポート途中で登録が残らず保存先にデータだけがある場合は、安全のため自動再開せず内容確認を案内します。

Ubuntu 内の工程記録は `~/.local/state/opencae-workshop2026/`、CFD のログ・結果はプロジェクト内の `work/` です。Crew の本人用ログは `~/.local/state/opencae-workshop2026/logs/crew.log` にあります。ログにはアクセス URL が含まれる可能性があるので共有しないでください。

Windows／WSL の再起動後は **Start Kiro Crew** を再実行します。自動起動は設定しません。Windows から localhost へ接続できない場合は、WSL の localhost 転送や組織のファイアウォール設定を確認します。これらのグローバル設定はスクリプトで書き換えません。

## 環境の削除

専用 WSL の Linux ファイル・個人認証・Docker イメージ・計算結果をすべて削除します。必要な成果物は事前に退避してください。設定ファイルは環境名ごとに作成されています。

```powershell
$config = "$env:LOCALAPPDATA\OpenCAE\environments\ubuntu_of_kiro\environment.json"
# 対象の確認のみ
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup\windows\RemoveEnvironment.ps1 -ConfigPath $config -WhatIf
# 確認に同意した後に削除
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup\windows\RemoveEnvironment.ps1 -ConfigPath $config
```

`ubuntu_of_kiro` は作成した環境名へ置き換えます。WSL 登録 ID・保存先・Linux 側の識別記録を照合し、一致しない場合は停止します。削除成功後に、その環境の設定と所有が確認できたショートカットを削除します。Windows の clone／ZIP、他の WSL、共有ダウンロードキャッシュは保持します。保存先を再帰削除せず、未知のメタデータファイルも保持します。WSL 削除後の処理失敗時は、残った設定で同じコマンドを再実行できます。インポート途中など識別記録が未作成の環境は手動確認が必要です。

## Proxy プレビュー

認証なし HTTP(S) Proxy のみ対象です。次の JSON を用意し、セットアップに渡します。独自 CA と認証付き Proxy は未対応です。

```json
{
  "httpProxy": "http://proxy.example:8080",
  "httpsProxy": "http://proxy.example:8080",
  "noProxy": "internal.example"
}
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup\windows\Setup.ps1 `
  -UserName workshop -EnableProxyPreview -ProxyConfig C:\path\proxy.json
```

Windows の rootfs 取得、Ubuntu 初期化、Linux セットアップ、Docker の取得・ビルド、当日の CLI／Crew に適用します。localhost は除外します。通信経路ごとの実地検証は未実施です。再開時も必要に応じて同じ Proxy オプションを指定してください。

## 検証範囲

Ubuntu 24.04 の ARM64／amd64 では、実際の導入・CFD ビルド・計算・描画・動画生成まで CI が成功しています。Windows のテストは構文・設定・WSL 呼び出し制御・再開・ブラウザーへの URL 受け渡しをモックで確認します。Windows 実機での新規 WSL 作成、sudo パスワード入力、個人認証、ブラウザー表示は別途受け入れ確認が必要です。
