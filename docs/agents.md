# WSL の Kiro CLI / Crew

## 導入・確認した構成

2026-10-25、このリポジトリを開発している WSL2 Ubuntu 24.04 / ARM64 に導入しました。取得情報は `setup/config/agents.env` に記録しています。ホスト側のアプリケーションであり、計算コンテナには含めません。

| 項目 | 確認した版・配置 |
| --- | --- |
| Kiro CLI | 2.34.0 stable、`~/.local/bin/kiro-cli`。ACP コマンドあり |
| Crew | 0.9.0 stable、`~/.kiro/crew-venv` の専用環境、入口は `~/.local/bin/kirocrew` |
| Crew の Python | 3.12.13。ホストの venv / ensurepip が不足していたため、公式インストーラーが `~/.kiro/crew-python` に用意 |
| 管理画面 | `http://localhost:5476`。127.0.0.1 / ::1 のみで待ち受け、HTTP 200 を確認 |
| 認証 | Kiro CLI のブラウザーログインを別工程として行う |

CLI は公式インストーラーが SHA256 を確認し、Crew は公式インストーラーが配布マニフェストの署名と wheel の SHA256 を検証しています。Crew のフロントエンドは wheel に同梱され、Node.js によるソースビルドは行いません。

## amd64 の対応確認

- CLI 2.34.0 の `x86_64-unknown-linux-gnu` 配布物と SHA256 が同じ公式マニフェストに存在します。
- Crew 0.9.0 は `py3-none-any` の共通 wheel で、Python >=3.12 が必要です。
- Linux amd64 / Python 3.12 を対象に、Crew の基本依存関係50パッケージがビルド済み wheel のみで解決できることを確認しました。
- amd64 ホストへの CLI / Crew の実インストール・起動・認証は未検証です。計算コンテナの amd64 CI 成功とは別の確認です。

## Kiro CLI のログイン

通常の WSL ターミナルで実行します。

```bash
kiro-cli login --use-device-flow
kiro-cli whoami
```

CLI が表示する URL を Windows のブラウザーで開き、画面に従ってコード入力とログインを行います。組織の IAM Identity Center を利用する場合は `kiro-cli login --help` の `--license pro`、`--identity-provider`、`--region` を確認してください。

この認証は GitHub リポジトリへの push に使う `GITHUB_ACCESS_TOKEN` とは別です。Crew の Kiro バックエンドは、同じ WSL の CLI ログイン状態を利用します。ログイン後は Crew で新しい会話を開始します。

## Crew の管理画面

この WSL では、起動を維持するためユーザー用 systemd の一時サービス `kirocrew-workshop.service` で実行しています。WSL 再起動時の自動起動は設定していません。トンネルと外部メッセージ連携は有効にしていません。

```bash
systemctl --user is-active kirocrew-workshop.service
kirocrew token
```

`kirocrew token` が出力するアクセス URL を Windows のブラウザーで開きます。この URL は管理画面へのアクセス権を含むので、Git や共有ログへ保存しません。Kiro CLI のモデル認証とは別の、Crew 管理画面の認証です。

現在のサービスを止める場合：

```bash
systemctl --user stop kirocrew-workshop.service
```

その後、通常のターミナルから起動する場合：

```bash
kirocrew gateway --no-open --no-tunnel --port 5476
```

現在の起動ログは `~/.kiro/crew/logs/gateway-bootstrap.log` に本人専用の権限で保存しています。認証 URL を含む可能性があるため、Actions の artifact 対象である `work/` には置きません。

## 計算コンテナの利用

Kiro CLI をこのリポジトリで起動し、計算ツールは既存の入口を使います。

```bash
scripts/run-tool.sh blockMesh -help
scripts/run-tool.sh pvpython --version
```

Crew の会話からは、このリポジトリの絶対パスで `scripts/run-tool.sh` を指定できます。教材と成果物はリポジトリの `work/` に保存します。利用者による認証後、Crew の会話からバージョン確認と `scripts/smoke-test.sh` の実行に成功し、生成動画の再生も確認されました。Windows 新規環境での自動セットアップは未実装です。

## 参照した公式手順

- [Kiro CLI の導入](https://kiro.dev/docs/getting-started/installation/)
- [Crew の導入](https://kiro.dev/docs/crew/installation/)
