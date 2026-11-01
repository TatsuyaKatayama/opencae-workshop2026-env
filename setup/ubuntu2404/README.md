# Ubuntu 24.04 セットアップ

Windows 用 PowerShell と Ubuntu 単体で共通利用する Bash コアです。Ubuntu 24.04、systemd、sudo 権限を持つ通常ユーザー、Linux ファイルシステム上のプロジェクトを前提にします。ユーザー作成と WSL 初期化は`Setup.ps1` が担当します。

## 実行

```bash
bash setup/ubuntu2404/setup.sh --plan
bash setup/ubuntu2404/setup.sh
bash setup/ubuntu2404/start-backend.sh --backend kiro
bash setup/ubuntu2404/crew-start.sh
bash setup/ubuntu2404/crew-stop.sh
```

`setup.sh` は Docker Engine／CLI・Compose・Buildx、Kiro CLI、Crew、OpenCode、Codex CLI を導入し、既存の `scripts/build-image.sh` と `scripts/smoke-test.sh` を実行します。後処理 Python と ParaView は CFD イメージ内にあります。個人認証と Crew の起動は自動では行いません。Ubuntu の userns 制限がある場合は、Crew の専用 AppArmor プロファイルを公式コマンドで導入します。Codex 用の `@agentclientprotocol/codex-acp` 2.5.0 と Node.js 24.11.1 も、ユーザー専用領域へ導入します。Node は公式バイナリ、npm 依存は lockfile と integrity で固定し、インストールスクリプトを実行しません。pipx がある場合も Crew の導入先を `~/.local/share/opencae/pipx` に固定します。既存の Node を置き換えず、専用ランチャーだけが固定 Node を使用します。

ホスト用ツールは公式 apt パッケージ／事前ビルド済みバイナリ／wheel を使用し、ソースビルドへ自動フォールバックしません。Kiro CLI 2.34.0、Crew 0.11.1、OpenCode 1.19.5、Codex CLI 0.166.0 を固定しました。OpenCode amd64 は AVX2 前提を避ける baseline 版、Codex は公式 musl 版です。版・URL・SHA256 は `setup/config/agents.env`、Docker は `setup/config/docker.env` にあります。Crew のインストーラー自体もリリースのコミット URL と SHA256 で固定します。ハッシュ検証した公式インストーラーで指定版の署名付きマニフェストを検証し、依存も wheel のみ導入します。

既存 CFD Dockerfile の ARM64 ParaView は、OSMesa 対応配布物の制約によりソースビルドです。このホスト用セットアップで新たなソースビルド経路は追加しません。

## 再実行と既存環境

`~/.local/state/opencae-workshop2026/` に本人専用の構成、ダウンロードキャッシュ、工程完了日時、失敗工程を保存します。再実行時は各工程を再評価し、同版 CLI と検証済みダウンロードを再利用します。apt は固定版へ収束させ、Docker ビルドはキャッシュを使用します。CFD 確認は再実行します。

別版の CLI、競合 Docker パッケージ、別の Docker 接続先は自動削除せず停止します。専用の新規 Ubuntu を利用してください。認証・成果物を削除するリセット機能は設けていません。失敗時は端末のエラー、`failed-step`、CFD 工程では `work/build-*`／`work/smoke-*` を確認します。セットアップ全出力の自動ファイル保存は行いません。

Crew の既定ポートは 5476。初回セットアップ時に `--port 5477` 等で変更可能です。登録済み構成と違う配置先・ポートでの再実行は停止します。複数 WSL から同時利用する場合は Windows localhost のポートが競合しないよう別ポートを選びます。

## 認証と Crew

`start-backend.sh --backend kiro|codex|opencode` で認証と Crew のバックエンド設定を行います。Kiro CLI は `login --use-device-flow`、Codex は `login --device-auth`、OpenCode は `auth login` を使用します。Codex は ChatGPT 側でデバイスコード認証の許可が必要です。OpenCode の既存設定・ローカルモデルを使う場合は `--skip-auth` を追加できます。

`--status` は Kiro CLI／Codex で認証済みなら 0、未認証なら 3。OpenCode は提供先・モデルの利用可否を自動判定せず 4 を返します。状態確認はバックエンド設定を変更しません。`--open-browser` は既知の認証先 URL を Windows の既定ブラウザーで開きます。未対応の提供先では表示 URL を手動で開いてください。URL・コードはログに保存しません。

バックエンド選択はこの WSL ユーザーの Crew 全体に適用されます。起動中に変更した場合は `crew-stop.sh` → `crew-start.sh` で反映します。OpenCode の提供先・モデルは Crew の画面でも選択し、会話を確認してください。KAS はインストーラーの `--no-kas` で取得せず、初期選択を `kiro` に固定します。Mates 等の追加機能は設定対象外です。旧 `kiro-login.sh` は認証だけの互換入口として残します。

Crew はプロジェクト絶対パスから生成した専用名のユーザー systemd 一時サービスとして起動します。端末終了後も動きますが、WSL／OS 起動時の自動起動はしません。`crew-start.sh` は Docker を確認し、認証前でも管理画面を起動できます。起動済みなら再利用します。`--status` は正常起動なら 0、未起動なら 3。通常実行の stdout はアクセス URL のみで、状態・案内は stderr です。URL を共有ログへ保存しないでください。

Crew ログは本人専用の `~/.local/state/opencae-workshop2026/logs/crew.log` です。認証 URL を含む可能性があり、CI artifact や `work/` へコピーしません。Stop は構成に対応する Crew のみを停止し、Docker や計算コンテナには触れません。

## Proxy プレビュー

認証なし HTTP(S) Proxy のみ対応するプレビューです。本人所有・権限 600 の JSON を指定します。

```json
{
  "httpProxy": "http://proxy.example:8080",
  "httpsProxy": "http://proxy.example:8080",
  "noProxy": "internal.example"
}
```

```bash
chmod 600 /path/to/proxy.json
bash setup/ubuntu2404/setup.sh --enable-proxy-preview --proxy-config /path/to/proxy.json
```

HTTP_PROXY／HTTPS_PROXY／NO_PROXY と小文字の変数、apt の実行環境、Docker の専用 systemd drop-in、Docker クライアントの build 用 proxies 設定、Crew の起動環境へ適用します。localhost・127.0.0.1・::1 は常に除外します。保存した設定は後続の認証・起動で再利用します。無効の通常実行では新たな Proxy 設定を作成しません。既存 Proxy を明示的に解除する機能、認証付き Proxy、独自 CA は未対応です。ネットワーク経由の動作確認は未実施で、通常構築の合格とは区別します。

`setup.sh --agents-only` は使い捨て CI 用に CLI・Crew の導入だけを実行し、Docker・CFD は導入・ビルドしません。通常の `setup.sh` は全工程です。

## テスト

```bash
python3 -m unittest discover -s tests -v
```

ローカルでは外部コマンドをモック化し、設定検証、失敗伝播、対象サービスの分離、URL の出力制御を確認します。実際のソフト導入や CFD ビルドは実行しません。

`Ubuntu 24.04 setup integration` は使い捨てネイティブ Ubuntu ランナーから既存 Docker パッケージを除去し、セットアップ全工程を実行する CI です。手動起動の `architecture` は `amd64`／`arm64`／`both` を選べます。main への対象ファイル push は amd64 を実行し、先行中の ARM64 実行とは別グループで管理します。WSL 検証ではありません。認証とブラウザー操作も含みません。両 CPU の URL・SHA256・展開ファイル名は制御テストで確認し、実インストールと CFD の成否は CI の結果で判断します。

`Backend binary checks` は両 CPU の使い捨て Ubuntu で固定配布物の導入・再実行と Codex／OpenCode の ACP 初期応答を確認します。認証・LLM 呼び出し・Crew 会話の実証は含みません。

導入情報の出典： [Docker apt](https://download.docker.com/linux/ubuntu/dists/noble/stable/)、[Kiro CLI manifest](https://prod.download.cli.kiro.dev/stable/latest/manifest.json)、[Crew](https://kiro.dev/docs/crew/installation/)、[OpenCode v1.19.5](https://github.com/anomalyco/opencode/releases/tag/v1.19.5)、[Codex 0.166.0](https://github.com/openai/codex/releases/tag/rust-v0.166.0)、[Codex CLI 公式資料](https://learn.chatgpt.com/docs/codex/cli)。
