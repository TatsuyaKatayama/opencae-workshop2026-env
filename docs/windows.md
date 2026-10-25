# Windows / WSL の準備

対象は Windows 11 ARM64 / x64 と WSL2 Ubuntu 24.04 LTS です。Windows 側からは Terminal とブラウザーを使います。Docker 操作は Ubuntu 内の Linux 版 CLI で行います。

Windows / WSL の自動導入スクリプトは後続工程です。現段階では [Docker 公式の Ubuntu 用手順](https://docs.docker.com/engine/install/ubuntu/) に従い、**WSL Ubuntu 内に Docker Engine、CLI、containerd、Compose、Buildx** を導入してください。Ubuntu は systemd を有効にし、Docker サービスを起動します。Docker Desktop は導入しません。

通常ユーザーを Docker グループへ追加した場合は、WSL のシェルを開き直してグループ反映を確認します。ビルド・スモーク用の入口は通常ユーザーで実行してください。

```bash
command -v docker
docker context show
docker context inspect --format '{{.Endpoints.docker.Host}}'
docker info --format '{{.OperatingSystem}} / {{.OSType}} / {{.Architecture}}'
docker compose version
docker buildx version
```

接続先は `unix:///var/run/docker.sock`、サーバーは WSL 内の Linux Engine、CPU は WSL と一致することを確認します。`docker` が `/mnt/c` 以下の Windows バイナリでないことも確認します。

既存 Docker Desktop の WSL 連携や `DOCKER_HOST` / `DOCKER_CONTEXT` により別のデーモンへ接続している場合、入口は停止します。Docker Desktop 側で対象 Ubuntu の WSL 連携を無効化し、Ubuntu 内の Engine / CLI とサービスを整備してください。その後、WSL のシェルを開き直して上記を再確認します。接続設定・既存イメージ・既存コンテナを自動で削除・変更する処理は用意しません。

リポジトリは `~/opencae-workshop2026-env` を標準とし、Windows の `/mnt/c` 以下には置きません。計算結果はリポジトリ内の `work/` に保存します。

Crew・Kiro CLI・OpenCode の導入、モデル認証、Windows ブラウザーからの localhost 接続は、計算コンテナの完成後に整備します。
