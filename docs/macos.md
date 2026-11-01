# macOS の導入手順

Apple Silicon、macOS 15 以降を対象にした実装です。Intel Mac・Rosetta 端末は対象外です。ホストバイナリの実導入と制御CIは成功しています。Colimaを含む実機での受け入れ前であり、検証状況は [validation.md](validation.md) に記録します。

## 構成

- Mac 上：Kiro CLI・Kiro Crew・OpenCode・Codex CLI、専用 Node／Codex ACP、Python 3.12、Docker CLI／Compose／Buildx。
- Colima 上：専用の Linux ARM64 VM と Docker Engine。VZ（Apple Virtualization.framework）と virtiofs を使用します。Docker Desktop は不要です。
- 計算コンテナ：Windows／Ubuntu と同じ Dockerfile・Compose・`work/`。ARM64 の ParaView 5.13.3 は conda-forge の OSMesa バイナリと依存ロックを使用し、ParaView／Mesa のソースビルドはしません。

Colima profile は `opencae-workshop2026`、Docker context は `colima-opencae-workshop2026` です。スクリプトと Crew にだけこの context を渡し、端末全体の既定 context は切り替えません。同名の既存 profile は本スクリプトの記録がなければ引き継ぎません。

Colima はコンテナ用の VM です。CLI の認証と Crew の Web サーバーは Mac 上で動作するため、WSL の稼働維持処理は使いません。

## 事前準備

1. [Homebrew の公式手順](https://brew.sh/ja/)でネイティブ ARM64 版を導入します。必要な Command Line Tools や管理者操作もこの段階で完了してください。セットアップは `/opt/homebrew/bin/brew` を使用します。
2. プロジェクトを clone または ZIP で取得し、ローカルディスクのホーム配下へ配置します。例：`~/opencae-workshop2026-env`。iCloud 管理フォルダーや外付けディスクは初回検証対象にしません。構築後は配置先を変更しないでください。
3. 通常ユーザーの Terminal で実行します。セットアップ全体を `sudo` で起動しません。

```bash
cd ~/opencae-workshop2026-env
bash setup/macos/setup.sh --plan
bash setup/macos/setup.sh
```

Finder からは `setup/macos/0_Setup.command` をダブルクリックできます。ZIP 解凍で実行権限が失われている場合は Terminal で `chmod +x setup/macos/*.command` を実行します。macOS がダウンロードしたスクリプトの実行を制限する場合は、内容を確認したうえで上記の Terminal コマンドを使用してください。Gatekeeper や署名検証を一括で無効にする処理は行いません。

メモリ16GB以上を暫定基準とし、VM の既定値は CPU 2・メモリ8GiB・ディスク上限100GiBです。ディスクはスパース形式であり、初めから100GiBを使用する指定ではありません。イメージ・キャッシュ用の空き容量は別途確保してください。実測値は実機受け入れで確認します。

```bash
bash setup/macos/setup.sh --port 5476 --cpu 4 --memory 8 --disk 100
```

同じ配置先・port・VM オプション・ツール版で再実行すると途中から再開できます。失敗した工程を記録し、既存データを削除しません。CFD の構築・検証は通常モードで毎回実行しますが、Docker のキャッシュを使用します。

セットアップは Homebrew の bottle と公式の固定版バイナリを優先し、ソースビルドへ自動フォールバックしません。Homebrew の基盤パッケージは導入時の bottle を使い、実際の版を `installed-versions.json` へ記録します。各 CLI と Node の版は [agents.env](../setup/config/agents.env)、macOS 配布物の URL・SHA256 は [macos.env](../setup/config/macos.env) に固定しています。

## 当日の操作

`setup/macos` の次のファイルを順にダブルクリックします。別フォルダーへの移動はせず、元の場所で使用してください。

| ファイル | 動作 |
| --- | --- |
| `1_StartBackend.command` | Kiro CLI／Codex／OpenCode を選び、必要なら認証する |
| `2_StartCrew.command` | Colima を必要時に起動し、Crew の準備完了後に既定ブラウザーで開く |
| `3_StopCrew.command` | 本プロジェクトの Crew だけを停止する |

認証スクリプトは Kiro CLI／Codex の認証状態を確認し、認証済みならログインを繰り返しません。Codex はデバイスコード認証、OpenCode は提供先ごとの OAuth／API キーです。既知の認証 URL は `/usr/bin/open` に引数として渡し、既定ブラウザーで開きます。自動で開けない提供先は表示された URL を手動で開いてください。

Crew 管理画面の起動にバックエンドの事前認証は必須ではありません。会話には選択したバックエンドの認証が必要です。変更後は Stop → Start で反映します。OpenCode の提供先とモデルは Crew 画面で選択します。KAS は導入しません。

Terminal からも実行できます。

```bash
bash setup/macos/start-backend.sh --backend codex --open-browser
bash setup/macos/start-backend.sh --backend opencode --skip-auth  # ローカルモデル等
bash setup/macos/crew-start.sh --open-browser
bash setup/macos/crew-start.sh --status
bash setup/macos/crew-stop.sh
```

`--status` はログイン・バックエンド変更・VM 起動を行いません。起動／認証済みは0、未認証／未起動は3、OpenCode の自動判定不可は4です。

Crew はユーザーの launchd job として起動します。plist は `~/Library/LaunchAgents` には置かず、明示的な Start でのみ登録するため、ログイン時の自動起動は有効にしません。Terminal を閉じても起動を継続し、Stop で登録を解除します。Mac のスリープ中は動作しません。

Stop は Colima と計算コンテナを停止しません。計算も含めて終了するときは、必要な処理が完了したことを確認してから次を実行します。

```bash
colima --profile opencae-workshop2026 stop
```

## 配置と再開

| 場所 | 内容 |
| --- | --- |
| `~/.local/state/opencae-workshop2026-macos/` | 環境記録、工程記録、ダウンロード、plist、本人用ログ |
| `~/.local/share/opencae/macos/` | 固定 CLI、Kiro の app bundle、専用 Node・ACP・pipx、Crew 設定 |
| `~/.colima/opencae-workshop2026/` | 専用 VM の設定・Docker socket |
| リポジトリの `work/` | 計算・描画・動画とビルドログ |

CLI と Crew は専用領域へ配置し、既存の同名 CLI と通常の Crew ホームを上書きしません。Kiro CLI／Codex／OpenCode 自体のログイン情報は各製品の標準保存先・Keychain等を使用します。アンインストール時にそれらをまとめて削除しないでください。

構築が失敗したときは原因を修正し、同じオプションでセットアップを再実行します。環境の初期化や profile の削除は自動では行いません。`failed-step` は工程名だけを記録します。`logs/crew.log` はアクセス URL 等を含む可能性がある本人用ログで、共有・Git 登録・CI artifact への添付を避けてください。

## 計算コンテナの確認

```bash
scripts/check-environment.sh
scripts/run-tool.sh blockMesh -help
scripts/run-tool.sh pvpython --version
scripts/smoke-test.sh
```

入口は native `linux/arm64`、専用 Colima socket、Linux Engine を照合し、Docker Desktop・別 CPU・リモート daemon を拒否します。`DOCKER_HOST`／別の `DOCKER_CONTEXT`／`DOCKER_CONFIG`／`COLIMA_HOME`／`LIMA_HOME` が指定されている端末では解除して実行してください。

`work/` は virtiofs 経由で共有し、コンテナへ Mac の UID/GID を渡します。計算・描画・MPI・再作成後の永続化・Mac 側での書き込み権限を共通のスモークケースで確認します。Dockerfile に Mac 専用ソフトやブラウザーは入れません。GPU・Metal・X サーバー・DISPLAY は使わず、コンテナ内の llvmpipe で描画します。

ARM64 ParaView は `/opt/paraview` の専用 Python 3.12、一般後処理は `/opt/post-venv` です。conda-forge の URL と推移依存の SHA256 は [paraview-arm64.lock](../containers/cfd-tools/paraview-arm64.lock) に固定しています。Anaconda Distribution／Miniconda／defaults チャネルを使わず、ビルド済みイメージは公開・配布しません。

## CI と実機受け入れ

標準 macOS CI はネストした VZ を前提にしません。標準 Bash 3.2 の構文・制御テスト、ダミーHTTPサービスを使った実launchdの起動・再利用・停止と、macOS バイナリの実導入・版確認・再導入・未認証状態・ACP 初期応答を確認します。`--agents-only` はこのためのモードで、Colima／CFD を構築しません。

Apple Silicon 実機では、Homebrew の初回導入、Colima 新規作成と再起動、CFD ビルド・共通スモーク、Finder のダブルクリック、3種の認証、既定ブラウザー、Crew 経由の会話、Terminal を閉じた後の継続、Stop直後の再起動を確認してください。Mac の Proxy 自動設定は今回の実装対象外です。Windows の Proxy プレビューと同じ検証済み範囲とは扱いません。

参考：[Colima 導入](https://colima.run/docs/installation/)・[Lima の virtiofs](https://lima-vm.io/docs/config/mount/)・[GitHub macOS ランナーの制約](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#limitations-for-arm64-macos-runners)。
