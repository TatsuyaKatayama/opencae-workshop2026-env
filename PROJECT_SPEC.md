# OpenCAE Workshop 2026 Environment — 講習環境構築仕様書

バージョン：0.12 ／ 更新日：2026-10-26 ／ 状態：計算コンテナ・ローカルCrew接続検証済み／Ubuntu 24.04 Bashコア実装・CI検証中／Windows側未実装

## プロジェクト名・リポジトリ名

| 項目 | 名称・方針 |
| --- | --- |
| プロジェクト名 | **OpenCAE Workshop 2026 Environment** |
| GitHub リポジトリ名 | **opencae-workshop2026-env** |
| GitHub URL | github.com/TatsuyaKatayama/opencae-workshop2026-env |
| 基本の配布方法 | GitHub で Dockerfile・ビルド用ファイル・Compose・セットアップ処理を配布 |
| イメージの用意方法 | 受講者が配布された Dockerfile からローカルビルド |
| 独自成果物のライセンス | Apache-2.0 を採用する方針 |

OpenCAE 学会の2026年の講習会に向けた環境構築プロジェクト。リポジトリ名は opencae-workshop2026-env に決定し、GitHub の所有者は TatsuyaKatayama。

## 1. 全体構成

Windows ARM64 を最初の構築・検証環境とし、Windows x64 にも対応する。構築する環境を次の3層に分ける。

| 層 | 用意する環境 | 導入物 |
| --- | --- | --- |
| Docker 層 | 計算・可視化・動画生成用の Linux コンテナ | **OpenFOAM v2606**、ParaView＋Mesa、ffmpeg、Python、MPI |
| WSL Ubuntu 層 | エージェントとコンテナを動かす Linux ホスト | Ubuntu 24.04 LTS、Docker Engine／CLI、Compose、Kiro Crew、Kiro CLI、OpenCode、Codex CLI、Python、Git |
| Windows 層 | WSL の起動と操作画面 | Windows 11、WSL2、Windows Terminal、PowerShell、Web ブラウザー |

Crew と CLI は同じ WSL Ubuntu 内で動かし、Windows のブラウザーから Crew を操作する。Kiro CLI、OpenCode、Codex CLI を導入する。講習当日は Kiro CLI を Crew のバックエンドとして使用する。OpenCode／Codex CLI は単独で利用できるように導入し、Crew との接続は今回の必須要件に含めない。

## 2. Docker 層

### イメージに入れるもの

初版は必要な計算ツールを1つの **cfd-tools** イメージにまとめる。

| 導入物 | バージョン方針 | 用途 |
| --- | --- | --- |
| Ubuntu | 24.04 LTS | コンテナのベース OS |
| OpenFOAM | **v2606（openfoam.com 系）を公式 apt で導入。初期候補のパッケージ版は 2606.0~rc2-1。正式版と同一内容とは扱わず、リリース前に確認** | メッシュ生成・流体計算・後処理 |
| MPI ランタイム | OpenFOAM のビルドと整合する版 | コンテナ内の並列計算 |
| ParaView | **5.13.3**。OSMesa 対応。amd64 は公式バイナリ、ARM64 は同版をソースビルド | pvpython／pvbatch による自動可視化 |
| Mesa・OSMesa | ParaView と整合する版 | CPU によるヘッドレス描画 |
| ffmpeg・ffprobe | Ubuntu 24.04 の提供版を基本とする | 動画生成・動画情報の確認 |
| Python | Ubuntu 24.04 の Python 3.12 を使用。後処理用は /opt/post-venv、ParaView 用は別環境 | 補助スクリプトの実行 |
| Python パッケージ | foamlib、numpy、scipy、matplotlib、japanize-matplotlib、optuna、pandas。uv とハッシュ付きロックで固定 | ケース操作・数値処理・日本語グラフ・最適化 |
| シェル・基本コマンド・共有ライブラリ | 上記ツールに必要なもの | 起動・ファイル処理 |

OpenFOAM 以外の厳密な版は構築時に選び、動作確認後に固定する。ParaView のコンパイラーやビルド専用依存関係はビルド用ステージへ配置する。OpenFOAM の -default パッケージが依存する開発ツールは公式パッケージ構成として導入する。

### 実行・保存方法

- Compose でコンテナを管理し、WSL の CLI からコンテナ内のツールを呼び出す。
- OpenFOAM の環境設定はコンテナの実行ラッパーで読み込む。
- 可視化は Mesa による画面なしの描画、動画はソフトウェアエンコードで生成する。
- WSL の **~/opencae-workshop2026-env/work** をコンテナの **/work** にマウントし、入力・結果・画像・動画を保存する。
- Kiro Crew、Kiro CLI、OpenCode、Codex CLI とその認証情報は、このイメージに含めない。

### CPU 対応と配布

- **linux/arm64 と linux/amd64** に対応する Dockerfile とビルド用ファイルを配布する。
- 両 CPU で OpenFOAM v2606 と同じ版の計算ツールをそろえる。
- 対応バイナリがないものはソースからビルドする。ARM64 の ParaView＋Mesa は先行して確認する。
- 受講者は自分の CPU に対応するイメージをローカルビルドする。別 CPU のエミュレーションは標準手順に含めない。
- 講師側では両 CPU のビルドと動作を確認する。ARM マシンからの amd64 検証には Buildx とエミュレーションも利用可能とし、必要に応じて amd64 実機のビルド環境へ分離する。
- ビルドは講習前の準備に含める。受講者向けにビルド・再実行・キャッシュ利用の手順を用意する。

### GitHub での配布

| 配布対象 | 配布先・扱い |
| --- | --- |
| Dockerfile・ビルド用スクリプト・パッチ | GitHub リポジトリ。標準の配布物 |
| Compose 定義・セットアップ処理・手順書 | 同じ GitHub リポジトリ |
| ビルド済み Docker イメージ | 公開・配布しない。GitHub Actions からも push しない |

- 受講者は確認済みの Git タグを取得し、Compose の build 設定からローカルイメージを作成する。
- ローカルイメージ名は **opencae-workshop2026-env/cfd-tools:of2606-r1** とする。
- 取得するベースイメージ、パッケージ、ソースの版を固定し、ソースアーカイブ等のチェックサムを記録する。
- レジストリへの公開やイメージアーカイブの配布は行わない。

GitHub リポジトリは作成済み。実装・Actions の検証状況は docs/validation.md に記録する。

## 3. WSL Ubuntu 層

### 導入するもの

| 導入物 | バージョン方針・設定 | 用途 |
| --- | --- | --- |
| Ubuntu | **24.04 LTS、WSL2、systemd 有効** | Linux 実行環境 |
| Docker Engine・Docker CLI | Ubuntu 24.04 対応の安定版 | コンテナの実行・管理 |
| Docker Compose プラグイン | Docker Engine と整合する版 | 計算環境の起動・停止 |
| Docker Buildx プラグイン | Docker Engine と整合する版。受講者にも導入 | Compose からのイメージビルド |
| Python・venv | Python 3.12 系 | Crew とセットアップ処理の実行 |
| Kiro Crew | Kiro CLI 接続を確認した版 | 管理画面・エージェント接続 |
| Kiro CLI | Crew と互換性を確認した Linux 版 | 講習当日のエージェント |
| OpenCode | Ubuntu 24.04 と各 CPU で確認した Linux 版 | 単独利用するエージェント |
| Codex CLI | Ubuntu 24.04 と各 CPU で確認した Linux 版 | 単独利用するエージェント |
| Git・curl・CA 証明書・展開ツール | Ubuntu 24.04 の提供版 | 構築ファイル・バイナリの取得 |

CPU に合わせて ARM64／x64 のバイナリを導入する。ホストの Docker・各 CLI は公式バイナリ／apt パッケージを優先し、対応物がなければ自動ソースビルドせず停止する。Crew はビルド済み配布物と wheel を専用 Python 環境へ導入する。フロントエンドのソースビルド用 Node.js は必須導入物にしない。

Docker Engine、Linux 版 Docker CLI、Compose、Buildx は WSL 内に配置する。Docker Desktop は導入・標準検証対象に含めない。CLI の接続先は WSL 内の unix:///var/run/docker.sock とし、既存 Desktop の連携や別デーモンを検出した場合は停止して手動切り替えの手順を案内する。既存設定は自動変更しない。

### 配置するもの

| 保存先 | 内容 |
| --- | --- |
| ~/opencae-workshop2026-env/setup | セットアップ処理・構成管理ファイル |
| ~/opencae-workshop2026-env/compose | Compose 定義・イメージ指定 |
| ~/opencae-workshop2026-env/work | 教材の作業コピー・計算データ・成果物 |
| 各製品のユーザー設定領域 | Crew の状態、Kiro／OpenCode／Codex の設定と認証 |

作業データは WSL の Linux ファイルシステムに置く。Crew の画面は Windows のブラウザーからローカル接続する。モデル認証はソフト導入後の独立したステップとする。

## 4. Windows 層

| 導入・準備するもの | 用途 |
| --- | --- |
| Windows 11 ARM64／x64 | ホスト OS |
| WSL2 と必要な仮想化機能 | Ubuntu を実行 |
| Windows Terminal | Ubuntu のシェルを操作 |
| PowerShell | Windows 側の初期セットアップ |
| Web ブラウザー | Crew の画面・モデル提供先の認証画面を操作 |

既に利用可能なものはそのまま使う。Crew、各 CLI、OpenFOAM、ParaView、ffmpeg の Windows 版は導入しない。

## 5. 構築ステップ

### 5.1 講師・開発者側：先に配布環境を作る

最小のビルド環境を用意した後、Docker イメージの作成・検証を先行する。Crew や各エージェントの導入前に、計算ツール単体で動作を確認する。

| ステップ | 処理 | 成果物 |
| --- | --- | --- |
| 1. ビルド基盤を準備 | 講師の WSL Ubuntu に Docker Engine・Buildx を用意。必要に応じて amd64 ビルド先も用意 | ビルド可能な環境 |
| 2. Docker イメージを作成・検証 | OpenFOAM v2606、ParaView＋Mesa、ffmpeg を組み込み、ARM64／amd64 で計算・画像・動画生成を確認 | Dockerfile、検証済みイメージ |
| 3. 導入手順を整備 | Windows／Ubuntu の準備、Dockerfile からのローカルビルド、Crew・CLI 導入を段階別に自動化 | セットアップ処理、Compose 定義 |
| 4. 新規環境で確認 | 受講者用ファイルだけからビルドし、Kiro CLI／OpenCode から計算コンテナを利用 | 配布可能な構築手順 |
| 5. GitHub で配布 | Dockerfile・関連ファイル・手順書をリリースとして公開 | 固定した Git タグ |

### 5.1.1 初期実装の検証先と方針

- 最初の実装単位は ARM64 計算コンテナまでとし、このリポジトリを配置した WSL2／ARM64 内の Docker Engine で検証する。
- apt 等の確認済み公式バイナリを優先する。ParaView の Ubuntu 24.04 apt 版は X 不在での描画に失敗したため、OSMesa 対応版を使い、amd64 は公式バイナリ、ARM64 はソースビルドを採用する。
- OpenFOAM は公式 apt を利用し、パッケージ版と実行時の版を両方記録する。
- 一般の python／python3 は /opt/post-venv を標準とし、pvpython／pvbatch の環境と分離する。
- Crew・Kiro CLI は計算コンテナ完成後、この WSL に導入して接続を確認済み。OpenCode／Codex CLI は新規セットアップでの導入・単独起動を確認する。認証は独立した対話工程とする。
- 受講 PC のメモリ16GBを暫定基準とし、標準ビルド並列数は2。時間・必要容量・ピークメモリは実測から要件を確定する。

### 5.2 受講者側：事前準備と当日の操作

事前に Git clone または ZIP のダウンロード・解凍で配布ファイルを取得し、`setup/windows/Setup.ps1` を実行する。ZIP からも構築できるよう、Git の管理情報や Git コマンドによる配布元の再取得を必須にしない。

| 時期 | 操作・処理 |
| --- | --- |
| 事前 | Setup.ps1 で専用の WSL2 Ubuntu 24.04 を新規作成し、Linux ユーザー、systemd、Docker Engine／CLI・Compose・Buildx、Kiro CLI・Crew・OpenCode・Codex CLI を導入・設定 |
| 事前 | 配布ファイルを WSL の Linux ファイルシステムへ配置し、既存 Dockerfile からネイティブ CPU 用の CFD イメージをローカルビルドして確認 |
| 事前 | Windows 側の設定・起動スクリプトを保存し、デスクトップに3つのショートカットを作成 |
| 当日 | **Kiro CLI Login** を起動し、Windows のブラウザーで個人認証 |
| 当日 | **Start Kiro Crew** を起動し、Windows のブラウザーから利用 |
| 終了時 | **Stop Kiro Crew** を起動 |

ソフト導入と個人認証を分離する。OpenCode／Codex CLI の提供先認証は必要な利用者が別途行う。Bash と PowerShell を主体とし、Ansible は導入しない。

### 5.3 セットアップ処理の責務

- 処理の本体は **setup/ubuntu2404/setup.sh**。Ubuntu 24.04 のみを対象とし、Ubuntu 単体でも直接実行できる構成にする。
- **setup/windows/Setup.ps1** は Windows／WSL の前提確認、新規環境作成、ユーザー初期化、配布ファイルの配置、Bash の呼び出し、Windows 用設定保存、ショートカット作成を担当する。
- Windows は ARM64／x64 に対応し、同じ CPU の Ubuntu・CLI・コンテナを利用する。
- WSL 本体や仮想化機能が不足する場合は必要な準備と再起動を案内し、準備後に再実行する。自動化の対象は専用ディストリビューションの新規作成以降とする。
- Ubuntu のシステム導入処理だけ root／sudo を使用し、CLI・Crew・認証・作業ファイルは指定ユーザーで管理する。ユーザーを作成して sudo 権限を付与し、パスワードは保存しない。
- 版・取得元・チェックサムを共有設定で管理し、再実行によって意図せず最新版へ更新しない。
- 長時間のローカルビルドはキャッシュを利用する。ステップの成否とログの場所を記録し、途中失敗から再開できる。

### 5.4 Setup.ps1 の入力と新規環境

| 入力 | 仕様 |
| --- | --- |
| DistroName | WSL の登録名。独自名を指定可能。既定値 opencae-workshop2026 |
| UserName | 新規 Linux ユーザー名。省略時は対話入力 |
| InstallLocation | 任意の Windows 側保存先。例 D:\WSL\opencae-workshop2026。省略時は %LOCALAPPDATA%\OpenCAE\WSL\<環境名> |
| EnableProxyPreview | Proxy のプレビュー機能を明示的に有効化。既定では無効 |

環境名とインストール先は独立した値とする。Ubuntu 24.04 の公式配布物を用い、指定名・指定先で WSL2 環境を新規作成する。取得方法・配布物の検証と必要な WSL 版は実装時に確定して記録する。

既存ディストリビューションの転用はしない。同名環境、既存データのある保存先は無条件に上書き・削除しない。ただし本セットアップの作成記録に一致する未完了環境は、記録と実環境を照合して再開可能とする。既存の WSL 環境や既定ディストリビューションを変更しない。

### 5.5 Windows 設定・ショートカット

セットアップで Windows の **%LOCALAPPDATA%\OpenCAE** 配下に、環境ごとの設定と Windows 用スクリプトを配置する。元の clone／ZIP 解凍ディレクトリを移動しても起動できるようにする。

設定には WSL 登録名、Linux ユーザー名、WSL 内のプロジェクト絶対パス、Crew のポート、作成・セットアップ状態を記録する。登録名の受け渡しにグローバルな環境変数は使用しない。各 PS1 は `-ConfigPath` で設定ファイルを受け取り、`wsl.exe -d <登録名> -u <ユーザー名>` で同じユーザーの Bash を呼び出す。

| ショートカット | Windows 側 | Ubuntu 側 |
| --- | --- | --- |
| Kiro CLI Login | KiroLogin.ps1 | kiro-login.sh |
| Start Kiro Crew | StartCrew.ps1 | crew-start.sh |
| Stop Kiro Crew | StopCrew.ps1 | crew-stop.sh |

複数環境ではショートカット名に環境名を付け、各ショートカットを対応する設定へ関連付ける。ショートカットや通常の構成ファイルにパスワード・認証トークンを埋め込まない。

### 5.6 認証・起動・停止

- **Login**：認証状態を確認し、認証済みなら結果を表示して終了。未認証なら対話ログインを開始する。デバイス認証の URL とコードを案内し、Windows の既定ブラウザーを開く。URL の自動取得ができない場合は手動で開ける案内を残す。最後に認証状態を確認し、失敗時は端末を残す。
- **Start**：設定、対象環境、Docker、認証状態を確認する。未認証なら Kiro CLI Login を案内する。Crew の起動完了を待ち、アクセス用 URL を Windows の既定ブラウザーで開く。起動済みなら同じ Crew の画面を開く。トンネルは有効にせず localhost のみで待ち受ける。
- **Stop**：本プロジェクトで管理する Crew を正常終了し、停止を確認する。未起動なら正常終了。Docker デーモンや計算コンテナ、別用途の Crew は停止しない。ブラウザーのタブは利用者が閉じる。
- Crew は環境内の専用サービス名で管理し、Windows の起動端末を閉じても稼働を維持する。OS／WSL 起動時の自動起動は標準で有効にしない。
- 認証は指定ユーザーの製品設定領域に保存する。アクセス URL を含み得るログは本人用権限で保管し、Git や CI artifact の対象にしない。失敗時は次の操作とログの場所を示す。

### 5.7 Proxy プレビュー

Proxy 対応はプレビュー実装とし、通常経路と区別して対応範囲・制限・検証状況を表示する。HTTP_PROXY／HTTPS_PROXY／NO_PROXY を扱い、localhost・127.0.0.1・::1 を除外する。インストール時通信、Docker デーモン、Docker ビルド、当日の CLI／Crew の各通信を適用対象として設計し、実際の対応範囲を記録する。

認証付き Proxy の秘密情報をショートカット、共有設定、通常ログへ保存しない。独自 CA の導入は Proxy URL と別の設定として扱い、必要時の手順・対応範囲を明示する。Proxy 経由の未検証項目を通常環境での検証成功に含めない。

## 6. macOS への展開

Apple Silicon Mac では Windows／WSL の準備を macOS 用セットアップに置き換える。macOS 上に Crew、Kiro CLI、OpenCode、Codex CLI、Python、Git、Docker CLI／Compose／Buildx とコンテナ実行基盤を導入する。macOS は Windows 両 CPU の完成後に対応し、コンテナ実行基盤は Docker Desktop を前提とせず、その段階で選定する。

Docker 層の Dockerfile、Compose 定義、作業フォルダー構成は共通化し、Mac でも linux/arm64 イメージをローカルビルドする。ホスト側の CLI は macOS 用を導入する。Windows 固有処理を Dockerfile や共通の起動処理へ含めない。

## 7. 環境構築の完了条件

- Windows ARM64 と Windows x64 で各層のソフトが起動する。
- 配布ファイルから自分の CPU 用イメージをビルドでき、講師の作成済みイメージや GHCR に依存しない。
- OpenFOAM v2606 の最小ケースが実行できる。
- ParaView＋OSMesa で GPU・DISPLAY・X サーバーを使用せず画像を生成し、ffmpeg で動画にできる。
- MPI 2プロセスの結果が直列計算と許容誤差内で一致する。
- 追加 Python パッケージを読み込め、foamlib でケースを読み、日本語ラベル付きグラフを保存できる。
- Crew から Kiro CLI を使い、計算コンテナ内のコマンドを実行できる。OpenCode／Codex CLI は導入・単独起動を確認する。
- Windows の新規環境作成、任意名・任意保存先、ZIP／clone 両経路、途中再開、3つのショートカットによる認証・起動・停止を確認する。
- Ubuntu 24.04 単体で Bash のセットアップ処理を利用できる。Proxy プレビューの検証状況を別途記録する。
- コンテナを作り直しても作業フォルダーのデータが残る。
- macOS 対応版では Apple Silicon Mac でも同じ確認を完了する。

導入した版、使用した Git タグ、ビルド設定、ローカルイメージ ID を構築結果として保存する。ビルド済みイメージは公開・配布しない。実施済みの範囲と未検証項目は docs/validation.md に記録する。Windows 両 CPU の新規構築と Crew 連携の確認を正式リリース条件とする。

### 7.1 セットアップのテスト方針

スクリプト別の受け入れ条件は [セットアップテスト計画](docs/setup-test-plan.md) に定める。PowerShell の入力・設定・コマンド制御と Bash の処理を自動テストし、Ubuntu 24.04 ARM64／amd64 で導入・計算処理を検証する。長い CFD ビルドは統合検証として分離する。

WSL 用 Actions は利用可能だが、GitHub ホスト型ランナーのネストした仮想化は正式サポートされていない。標準 Windows CI の成功を WSL2 の検証成功とみなさない。WSL2＋systemd＋Docker の新規作成・再開・起動停止は、能力確認済みの Windows 実機または専用セルフホスト型ランナーで確認する。WSL1 は代替の合格条件にしない。

個人認証、既定ブラウザー、ショートカット操作、Windows 再起動後の復帰、Crew の会話と動画再生は ARM64／x64 の手動受け入れに含める。テスト ID・対象 CPU・実行環境・結果を記録し、モックの成功や未実施を実機成功として扱わない。Proxy プレビューは別途記録する。Ubuntu 24.04 の Bash コアとモックによる制御テストを実装した。Docker の新規導入と CFD ビルド・確認を伴う統合テストは使い捨て ARM64／amd64 のネイティブ CI で実行し、開発用 WSL では実行しない。同版配布を利用し、CPU に対応する URL・ハッシュ・展開名を選択する。CI は対象 CPU を選択可能とし、統合実行の成否は CPU ごとに別記録とする。Windows 側スクリプトは未実装。

## 8. Git リポジトリの構成

Dockerfile・ビルド用ファイルと各 OS の構築処理を1つのリポジトリで管理する。以下は全体の予定構成。初期実装は計算コンテナ・Compose・操作スクリプト・スモーク検証・資料とし、setup 配下の自動導入処理は後続工程とする。

```text
opencae-workshop2026-env/
├─ README.md                     # 最初に読む導入案内
├─ PROJECT_SPEC.md               # 本仕様書
├─ LICENSE                       # 独自成果物に適用する Apache-2.0 本文
├─ THIRD_PARTY_NOTICES.md         # 第三者ソフトの表示・ライセンス案内
├─ versions.env                  # ソフトの版・ベースイメージ・取得元・チェックサム
├─ .gitignore                    # 作業データ・認証情報などの除外
├─ .github/
│  └─ workflows/                 # ビルド・動作確認。イメージ公開なし
├─ containers/
│  └─ cfd-tools/
│     ├─ Dockerfile              # ARM64／amd64 の計算イメージ
│     └─ scripts/                # コンテナ内の環境設定・実行処理
├─ compose/
│  └─ compose.yaml               # 受講者用。Dockerfile から build して起動
├─ setup/
│  ├─ windows/                   # Setup.ps1 / KiroLogin.ps1 / StartCrew.ps1 / StopCrew.ps1
│  ├─ ubuntu2404/                # setup.sh / kiro-login.sh / crew-start.sh / crew-stop.sh
│  ├─ macos/                     # macOS 用の導入処理
│  └─ config/                    # Crew・CLI などの設定テンプレート
├─ scripts/
│  ├─ build-image.sh             # 講師・受講者共通のローカルビルド入口
│  └─ check-environment.sh       # 導入済みソフト・CPU・接続の確認
├─ examples/
│  └─ smoke/                     # 計算・描画・動画生成の最小確認ケース
├─ docs/
│  ├─ windows.md                 # Windows／WSL の導入手順
│  ├─ macos.md                   # Mac の導入手順
│  ├─ image-build.md             # ローカルビルド・再ビルド手順
│  ├─ backend-switch.md          # Kiro CLI → OpenCode の切り替え手順
│  └─ source-distribution.md      # 使用ソースの取得元・ライセンス情報
└─ work/                         # 実行時に作成。Git 管理対象外
```

- Windows／WSL ではリポジトリを WSL 内の **~/opencae-workshop2026-env** に配置する。Mac でも同じホーム相対の配置を基本とする。
- examples は配布する原本として管理し、実行時は work へコピーする。計算結果・画像・動画・ログは work に保存する。
- 認証情報、個人用の環境変数ファイル、取得したバイナリ、イメージ書き出しファイルを Git に追加しない。versions.env は秘密情報を含まない共有設定とする。
- Bash / PowerShell の導入処理は setup 配下へ配置し、OS ごとの入口と構築ステップを維持する。

### ブランチ・リリース

| 項目 | 方針 |
| --- | --- |
| 既定ブランチ | 公開時は main とする |
| 作業ブランチ | codex/<作業内容> などの短期間のブランチを使い、確認後に main へ反映 |
| 環境のリリース | Git タグ v0.1.0、v0.2.0 などでセットアップ処理と資料を固定 |
| ローカルイメージのタグ | of2606-r1、of2606-r2 などでビルド設定のリリースを識別 |
| リリース間の対応 | 各 Git タグの versions.env に、各ソフトの版・取得元・ベースイメージ・チェックサムを記録。ローカル構築結果にはイメージ ID を記録 |

講習では確認済みの Git タグまたは対応 ZIP を指定し、その Dockerfile からビルドする。Ubuntu 24.04 の Bash コアは実装済み。Windows 側の自動化は後続工程。

## 9. ライセンス方針

本プロジェクトで独自に作成する Dockerfile、Compose 定義、セットアップスクリプト、設定、文書には **Apache License 2.0（Apache-2.0）** を適用する。第三者から取得・改変したファイルは、その出自とライセンスを保持する。

| 対象 | 適用する条件 |
| --- | --- |
| 独自の構築コード・設定・文書 | Apache-2.0 |
| OpenFOAM v2606 とその改変物 | OpenFOAM の GPL 条件。取得したソースのライセンス表記に従う |
| ParaView、Mesa、ffmpeg、MPI、ベース OS の各パッケージ | 実際に含めた各コンポーネントの条件 |
| ローカルビルドする Docker イメージ | 内包する各コンポーネントの条件に従う。イメージ全体を一律 Apache-2.0 と表記しない |

- 原則として独自スクリプトから別プロセスのコマンドとしてツールを呼び出す。OpenFOAM のコード流用やリンクする追加ソルバーを作成する場合は、その部分の適用条件を別途確認する。
- 公開時に LICENSE と適用範囲の説明を用意する。著作権・ライセンス表示を保持し、引き継ぐ必要のある NOTICE がある場合は同梱する。
- 基本配布物は Dockerfile とビルド用ファイルとし、第三者ソフトは受講者のビルド時に指定した配布元から取得する。第三者のソース・パッチ等をリポジトリへ同梱する場合は、その配布条件に従う。
- ビルド済みイメージは公開・配布しない。将来この方針を変更する場合は、GPL／LGPL 等の対応ソース提供を含む再配布条件を改めて確認する。
- 使用ソースの取得元を docs/source-distribution.md に記録する。
- ffmpeg はビルド設定・外部ライブラリにより適用ライセンスが変わるため、構築した版のライセンスとビルド設定を記録する。
- 上流のチュートリアルや設定を取り込む場合も、独自作成物と区別して出典・ライセンスを記録する。
- Kiro CLI 等は公式配布元から利用者環境へ導入する構成を維持する。本プロジェクトの Apache-2.0 は第三者製品の再配布権を付与しない。

## 参考資料

- [OpenFOAM v2606](https://www.openfoam.com/news/main-news/openfoam-v2606)
- [Kiro Crew の導入](https://kiro.dev/docs/crew/installation/)
- [Kiro Crew の対応バックエンド](https://kiro.dev/docs/crew/features/agent-backends/)
- [Docker Engine の Ubuntu への導入](https://docs.docker.com/engine/install/ubuntu/)
- [Docker のマルチプラットフォームビルド](https://docs.docker.com/build/building/multi-platform/)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- [GPL：独立プログラムの同梱とソース提供](https://www.gnu.org/licenses/gpl-faq.en.html)
- [ffmpeg のライセンス](https://ffmpeg.org/legal.html)
