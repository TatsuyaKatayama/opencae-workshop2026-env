# 検証記録

## 現在の状態

初期実装中です。講習向けの確認済みリリースではありません。

| 項目 | 状態 |
| --- | --- |
| 開発ホスト | WSL2、Ubuntu 24.04、ARM64、メモリ約32GB、Docker Engine 29.1.1 |
| 実行入口 | 引数・終了コード保持、別ディレクトリからの呼び出し、Desktop / remote 拒否の単体テストを実施 |
| apt 版 ParaView | 5.11.2+dfsg-6build5 + libosmesa6 を ARM64 一時コンテナへ導入。DISPLAY 不在で sphere を Render / SaveScreenshot すると vtkXOpenGLRenderWindow → XSync で SIGSEGV。採用せず |
| OpenFOAM | 公式 apt の openfoam2606-default 2606.0~rc2-1 を導入し、実行時の v2606 表示を確認。正式版ソースとの同一性は未確認 |
| ARM64 OSMesa ParaView | ローカル WSL2 / ARM64 で 5.13.3 のビルド・CPU 描画・動画生成・永続化まで成功。Ubuntu セットアップ CI でも検証成功 |
| amd64 OSMesa ParaView | 同版の公式バイナリで成功。Linux amd64 のネイティブ Actions で計算・描画・動画・永続化まで通過（下記） |
| 直列・MPI・Python 後処理 | ネットワークなしの一時コンテナで通過。400セル、最終時刻0.02、速度差 L2=1.03e-9、圧力差 L2=9.73e-10。指定7パッケージの import、foamlib 読み込み、CSV・日本語グラフ保存、Optuna の小規模計算を確認 |
| 任意 UID の起動 | UID/GID 1001 で OpenFOAM v2606、Python パッケージ、MPI 実行パス /usr/bin/mpirun を確認 |
| 描画・動画・永続化の一括検証 | Linux amd64 の Actions とローカル WSL2 / ARM64 で成功 |
| Windows 新規構築 | ARM64 / x64 とも未検証 |
| Crew / Kiro CLI / OpenCode | この WSL に CLI 2.34.0 / Crew 0.9.0 を導入し管理画面を起動。利用者が認証し、Crew 経由の計算・描画・動画生成まで成功を報告。OpenCode は既存導入あり、Crew 接続は未検証 |
| Apple Silicon Mac | 導入・認証・launchd制御を実装。ホスト導入CI成功、Colima通し実機受け入れは未実施 |

## GitHub Actions

- `Source checks`：push / pull request で構文、実行入口のテスト、Compose 定義を検査。
- `Native image smoke tests`：main と codex/cfd-tools-bootstrap への関連変更の push、または手動実行で起動。
- `ubuntu-24.04` は amd64、`ubuntu-24.04-arm` は ARM64 のネイティブランナー。Windows / WSL の検証を代替するものではない。
- GitHub の Actions タブから実行を開き、`validation-ubuntu-24.04` / `validation-ubuntu-24.04-arm` artifact を取得する。
- artifact の `work/build-*` にビルドログと実際の版、`work/smoke-*` に直列・MPI のログ、PNG、MP4、結果 JSON を保存する。失敗時も取得できる。
- 成功判定は `result.json` の passed と各 job の完了を両方確認する。workflow の作成だけで実行済みとは扱わない。

## 正式リリース前

OpenFOAM の RC2 表記を解消するか、採用版を明示した仕様判断が必要です。両 CPU のネイティブビルド、Windows 新規構築、各バックエンド接続、再実行での状態保持を確認した Git タグを受講者へ配布します。16GB 環境でのビルド時間・空き容量・ピークメモリも測定します。

ローカルの計算のみの検証には、配布用 Dockerfile と同じ apt / Python 構成から ParaView のコピーを省いた一時イメージを使用しました。配布イメージ全体の成功とは区別します。

## amd64 Actions の初回失敗と修正

実行 `40176820088` ではイメージビルド、直列・MPI 計算、Python 後処理まで成功しました。公式 OSMesa 配布物の `pvpython-real` が `libglapi.so.0` 不足で起動せず、終了コード127になりました。ランタイムに `libglapi-mesa` を明示追加し、コマンド失敗時に保存ログ末尾を Actions のコンソールへ表示するよう修正しました。修正版の描画・動画生成は Actions で再検証します。

再実行 `40177659597` では libglapi の不足は解消しましたが、pvpython がセグメンテーションフォルトで停止しました。公式配布物は `lib/mesa` に libglapi と OSMesa を同梱しており、上流でも探索パスの問題が報告されています（https://discourse.paraview.org/t/trouble-running-paraview-5-13-3-on-hpc-cluster-missing-libgl-so-1-and-libglapi-so-0/16749/2）。システムの libglapi 追加を取り消し、amd64 launcher に `--mesa --backend llvmpipe` を渡して同梱ライブラリを選択する構成へ変更しました。ARM64 のソースビルドにはこの引数を渡しません。

## amd64 の検証成功

修正コミット `a978ae6` の [Actions 実行 40178307578](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/40178307578/job/121123697823) で amd64 ジョブが成功しました。artifact `validation-ubuntu-24.04` の結果 JSON も確認しました。

- OpenFOAM の直列・MPI 計算、追加 Python パッケージ、foamlib、日本語グラフが成功。
- DISPLAY / X サーバーなしで `vtkOSOpenGLRenderWindow` を使用。
- 実レンダラーは Mesa 21.2.1 / llvmpipe（LLVM 7.0.0）。GPU は使用せず。
- 640×480 の PNG 10枚と、H.264 / 2秒 / 10フレームの MP4 を生成。
- 別の一時コンテナから成果物の保持を確認し、ホストの所有権検査も通過。

これは Linux amd64 ランナーの結果です。ARM64 はその後ローカルビルドを再開し、下記の全体検証を完了しました。Windows 新規構築と Crew 接続は引き続き未完了です。

## ARM64 の初回 Actions 失敗

最初の ARM64 ジョブ（実行 `40176820088`）は、約90分で ParaView のコンパイルとイメージ作成を完了しました。直列・MPI 計算と Python 後処理も成功しています。描画の起動時に `libpython3.12.so.1.0` が見つからず、終了コード127で停止しました。タイムアウトではありません。

実行ステージへ `libpython3.12t64` を追加し、イメージ作成時の `pvpython --version` 起動検査も追加しました。ParaView のコンパイル済みキャッシュは再利用し、ARM64 の描画・動画生成を再検証します。

## ローカル WSL2 / ARM64 の検証成功

修正コミット `f95f206` の構成で `scripts/smoke-test.sh` が成功しました。ローカルイメージは `opencae-workshop2026-env/cfd-tools:of2606-r1` です。イメージをレジストリへ公開していません。

- 実行基盤：WSL2 Ubuntu 24.04、Docker Engine / CLI、linux/arm64、ホストメモリ約32GB。
- ParaView 5.13.3 のソースビルドを再開。前回の約1,000工程をキャッシュから利用し、残りを6並列で処理。再開からの所要時間は1,379秒（約23分）。
- 実行レイヤーへの libpython 追加後の再ビルドは46秒。ParaView は再コンパイルせずキャッシュを利用。
- OpenFOAM v2606 の400セル・最終時刻0.02のケースで直列 / MPI 2プロセスが整合。差の L2 ノルムは速度1.03e-9、圧力9.73e-10。
- foamlib、追加 Python パッケージ、日本語グラフ、PNG 10枚、H.264 / 2秒の MP4 が成功。
- 描画は vtkOSOpenGLRenderWindow、Mesa 25.1.7 / llvmpipe（LLVM 20.1.2、128 bits）。X サーバーと GPU を使用しない。
- 別の一時コンテナからデータ保持を確認し、ホストユーザーの所有権検査も成功。

ローカルの構築記録は `work/build-20261025T101155Z-AfmOga/`、検証結果は `work/smoke-20261025T101332Z-2JXxdA/` に保存しました。これらは Git 管理対象外です。16GB ホストでの検証、Windows 新規構築は引き続き別工程です。

## WSL のエージェント導入

この WSL / ARM64 に Kiro CLI 2.34.0 と Crew 0.9.0 を公式配布から導入しました。CLI の ACP コマンド、Crew の標準エージェント設定、localhost:5476 の HTTP 200 を確認しています。amd64 の CLI 配布と Crew の wheel 依存解決も確認しましたが、amd64 ホストでの実起動は未検証です。認証・管理画面・起動方法は `docs/agents.md` に記載しています。

通常の初期設定後、Crew doctor の標準 MCP プローブは通過しました。音声認識の追加依存とホスト側 ffmpeg は今回の導入対象に含めていません。Kiro CLI の認証未完了時に出た ACP 起動失敗は、ログに明示された `You are not logged in` が直接の原因です。

利用者が別の WSL ターミナルで Kiro CLI の認証を完了し、Crew の会話からホスト・Docker・コンテナのバージョン確認を実行しました。続いて `scripts/smoke-test.sh` の成功と動画の再生を報告しました。これはローカル ARM64 での手動接続検証であり、Windows 新規セットアップの検証とは区別します。

## Ubuntu 24.04 セットアップの ARM64／amd64 対応

2026-10-26、共通 Bash によるバイナリ導入、認証、Crew 起動・停止を実装しました。ローカルの制御テスト22件（既存4件を含む）、Bash 構文、Compose 設定検査が通過しました。CPU 別 URL・ハッシュ・Codex の展開名、amd64 の計画表示と Crew 再利用もモックで確認しています。実際のソフト導入や CFD ビルドはこの開発用 WSL では実行していません。

2026-10-27、ARM64 [40206466748](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/40206466748) と amd64 [40206879065](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/40206879065) がともに成功したことを確認しました。Docker 新規導入、各 CLI・Crew 導入、CFD ビルド・計算・描画・動画生成、未認証状態と Crew 停止の確認まで通過しています。Kiro CLI 2.34.0、Crew 0.9.0、OpenCode 1.19.4、Codex CLI 0.164.0 と Docker 関連パッケージの採用版は共通です。認証・ブラウザー・WSL 新規作成・Proxy 経由通信は今回の CI の合格対象に含めません。

## Windows セットアップ・当日操作の実装

2026-10-27、`codex/windows-launchers` で Setup.ps1、KiroLogin.ps1、StartCrew.ps1、StopCrew.ps1 と手順書を実装しました。Ubuntu の新規インポート、ユーザー初期化、配置、工程再開、設定・ショートカット、対話認証のブラウザー連携を提供します。

[Windows CI 40356116711](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/40356116711) で windows-2025（x64）と windows-11-arm の各 PowerShell 5.1／7 がすべて成功しました。CPU のネイティブ判定、構文、設定、対象登録照合、新規作成・再開の制御、認証状態分岐、起動終了コマンド、アクセス URL の検証を確認しました。WSL コマンド・ブラウザー・ダウンロードはモックであり、実際の環境作成や認証の成功を示すものではありません。Linux のソース検査と24件のテストも通過しています。

Windows 実機での初回 WSL 構築、sudo パスワード入力、実際のショートカット作成・クリック、認証と既定ブラウザー、Windows 再起動後の復帰、Proxy 通信は未検証です。受講者向け正式リリース前の受け入れ項目として残します。操作手順は [Windows 手順](windows.md) を参照してください。


## バックエンド選択と環境削除（2026-11-01）

Start Backend で Kiro CLI／Codex／OpenCode を選び、同じ WSL ユーザーで認証と Crew 設定を行う実装を追加しました。Crew 0.11.1、OpenCode 1.19.5、Codex CLI 0.166.0、Crew が想定する `@agentclientprotocol/codex-acp` 2.5.0、専用 Node.js 24.11.1 を固定しました。KAS は取得せず、初期選択を Kiro CLI に明示します。バックエンド未認証でも管理画面の起動を許可します。

Windows 環境削除は登録・保存先・識別記録の照合、明示確認、WhatIf、失敗後の再開を実装しました。開発用 WSL ではソフトを導入・更新せず、CFD のビルドや実際の WSL 削除も実行していません。Python 33件、Linux 上の PowerShell 81項目とソース検査が通過しました。[Windows CI 41262362383](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41262362383) で x64／ARM64 の PowerShell 5.1／7 が成功し、[Backend binary checks 41262362316](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41262362316) で両 CPU の新規バイナリ導入・再実行・Codex／OpenCode の ACP 初期応答が成功しました。認証と Crew 経由の会話、実機 WSL 削除は未検証です。

main の [Ubuntu 統合 CI 41261172219](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41261172219) は agents 工程の SHA256 不一致で停止しました。Kiro CLI 2.34.0 の両 CPU 用 ZIP の実ハッシュ、OpenCode 1.19.4／Codex 0.164.0 の GitHub リリース digest は記録と一致しました。一方、可変 URL `https://download.crew.kiro.dev/cli.sh` の内容が変わり、記録の `99e69080…` に対して取得物は `9111584c…` でした。今回からインストーラー自体も採用リリースの完全なコミット URL と SHA256 で固定し、ハッシュ不一致には対象ファイル名を表示します。ハッシュ検証は維持します。

CI では既存の共有 pipx 領域 `/opt/pipx` を継承すると AppArmor の権限検査に失敗したため、Crew 用の pipx ホームと公開バイナリ先を指定ユーザーの領域に固定しました。最小 Ubuntu でも Node の展開と専用 AppArmor プロファイルを利用できるよう `xz-utils` と `apparmor` を前提パッケージへ明示しました。


## WSL 稼働維持と停止直後のポート確認（2026-11-01）

利用者の実機検証で、Codex 認証後のチャット送信時に Crew がオフラインとなり、systemd サービスだけでは WSL の稼働を維持できないことが報告されました。Windows 側に用意された暫定修正を取り込み、稼働維持を専用 Bash へ分離しました。通常の wsl.exe を Crew のサービスが稼働する間だけ非表示で維持し、HTTP 応答ではなくサービス状態を監視します。起動・停止用と別のロックで重複を防ぎ、サービス停止で終了します。

起動前のポート確認に SO_REUSEADDR を適用し、HTTP サーバーと同様に TCP TIME_WAIT を許容します。実際の localhost ソケットを使う回帰テストで、LISTEN 中は拒否し、停止後の TIME_WAIT では通過することを確認しました。開発用 WSL ではインストールや CFD ビルドを行っていません。Python 38件、Linux 上の PowerShell 99項目が通過しました。WSL の実際のアイドル終了抑止とチャット継続は実機で再確認します。


## 起動ファイルの整理と Allclean（2026-11-01）

インストール先の PS1 と runtime を scripts 配下へ移し、直下の CMD を 1_StartBackend／2_StartCrew／3_StopCrew／9_Allclean に整理しました。更新時は旧レイアウトの既知ファイルだけを削除し、無関係な Windows ファイルは保持します。Allclean は登録 ID・保存先・Linux 識別記録を照合後、日本語で登録解除コマンドとデータ消失を表示し、DELETE 入力時だけ削除へ進みます。キャンセル・WhatIf は削除しません。実際の WSL 削除は開発機では行わず、モックで確認します。Windows CI ではテスト用 PS1 で CMD の実行・引数・終了コード、および Allclean の CMD 自体が消えるケースを確認します。


## Windows 版 v1.0.0（2026-11-01）

利用者から Windows 版の実機確認完了の報告を受け、v1.0.0 としてリリースします。[Windows CI 41287149106](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41287149106) で x64／ARM64 の PowerShell 5.1／7 が成功し、Allclean が自身の CMD を削除する場合の終了もダミー処理で確認しました。[ソース検査 41287149173](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41287149173)、[バックエンド導入 41287149125](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41287149125) も成功しています。過去の未確認事項は各時点の記録です。Proxy はプレビュー、macOS は未対応であり、実際の WSL 全削除は開発機で行っていません。


## macOS 実装と ARM64 OSMesa バイナリ（2026-11-01）

`feature/macos-support` で、macOS 15以降のApple Silicon向けにHomebrew bottle、固定ネイティブCLI、専用Colima profile、launchdと.command入口を追加しました。Homebrew自体の初回導入は公式手順で事前に行います。macOS標準Bash 3.2を対象とし、Python 3.12で設定照合・ロック・工程再開・認証・サービス制御を行います。個人認証・ブラウザー・Colima・CFD通し・スリープ復帰等は実機受け入れに残します。

ARM64 ParaViewは同じ5.13.3のconda-forge `py312hcc5151f_8_osmesa` 配布物があることを確認しました。[調査CI 41311322286](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41311322286) でDISPLAYなし、`vtkOSOpenGLRenderWindow`、Mesa 25.0.5／llvmpipeによる画像生成が成功しました。全依存の取得URL・SHA256を明示ロックに固定し、CFDイメージのARM64ステージをソースビルドからバイナリ導入へ変更しました。イメージタグはof2606-r2です。

[Native image CI 41311793737](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41311793737) はUbuntu ARM64／amd64の両方で成功しました。CFDイメージのネイティブビルドと、OpenFOAM直列・MPI、ParaViewのOpenFOAMReaderとCPU画像、後処理、動画、永続化を再確認しています。この成功はLinux上のコンテナ検証であり、MacのColima経由の共有フォルダーやlaunchdの実機成功を示すものではありません。

配布物はスクリプト・Dockerfile・設定・ロック・資料のみです。conda-forgeはビルド時に各環境から取得し、Anaconda Distribution・Miniconda・defaultsは使いません。取得物のライセンス表示を保持し、ビルド済みイメージを公開する処理はありません。

[macOS CI 41312974824](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41312974824) ではApple Siliconのmacos-15で標準Bashの構文・制御、Kiro app bundleの署名検証・固定版起動、Crew・OpenCode・Codex・Node／ACPの実導入、未認証状態、ACP初期応答、再導入とバックエンド保持が成功しました。Colimaを起動せず `--agents-only` で実施し、認証やLLM呼び出しは行っていません。

[macOS CI 41313214361](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41313214361) は上記に加え、実際のlaunchdへのbootstrap、ダミーHTTPサービスの準備完了、重複起動時の再利用、bootout、停止後の状態確認も成功しました。これはサービス制御の実検証であり、Crew本体の会話・Colimaの実起動は含めません。Linux側では共通検査も通過し、開発用WSLにホストCLIや計算環境を導入していません。

最終のローカル共通検査は66テスト（macOS実launchd専用の1件のみLinuxではスキップ）が通過しました。標準Bashでの日本語隣接変数は明示的に区切り、呼び出し元のPATHを保持して制御テストが実Dockerへ誤接続しないことも確認しています。

## 最終コミットのCIとissue #1の確認（2026-11-01）

実装コミット `4d6a455` で以下のCIがすべて成功しました。

- [macOSホスト導入・制御](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41313735909)：標準Bash、固定バイナリ導入、実launchd＋ダミーHTTPサービス、未認証状態・ACP、再導入。
- [Native image smoke tests](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41313735843)：Ubuntu ARM64／amd64のビルド・OpenFOAM直列／MPI・CPU描画・動画生成・永続化。
- [Windows制御](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41313735985)：x64／ARM64、PowerShell 5.1／7。
- [Linuxバックエンド導入](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41313735828)：ARM64／amd64の実導入・未認証状態・ACP・再導入。
- [共通ソース検査](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41313735917)。

[issue #1](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/issues/1) は別途確認しました。`colima ssh` は通常利用には不要な診断操作であり、今回の構成はCrewとCLIをMac上、計算処理をDocker CLI／Compose経由で実行します。NginxのHTTPポート転送検証は本プロジェクトの必須経路ではなく、既存のCFD Composeとスモークケースを検証の中心としています。issue本文のチェックリストは変更・クローズしていません。Colimaを含むMac実機の通し確認、個人認証、Finder操作は未実施であり、CI成功で代替しません。

## Homebrewの初回自動導入（2026-11-01）

Homebrew手動導入の前提を変更し、セットアップ内で既存の `/opt/homebrew` を確認・再利用し、未導入なら公式インストーラーを起動する処理を追加しました。公式スクリプトはHomebrew/installのコミット `8c82c081753d4263da0cfe615ef8d9433425f22b` とSHA256を固定しています。対話入力を維持し、ハッシュ不一致・取得失敗・導入失敗・導入後の配置先不一致は後続工程へ進めません。`--plan` は導入・通信を行いません。

専用hello-world／SSH／Nginxテストは追加せず、通常セットアップで自動実行するOpenFOAMの共通スモークで今回のCFD利用経路を確認する方針にしました。実際のMacでのHomebrew初回導入（sudo入力・Command Line Toolsを含む）と、Colima経由の通し確認は引き続き未実施です。issue本文の変更やクローズ、develop／mainへのマージ・タグ・リリースは行っていません。

ローカルの共通検査は74テスト（LinuxではmacOS実launchd専用の1件をスキップ）が通過しました。Homebrew制御の8件は既存環境・初回導入・非対話拒否・SHA256不一致・取得失敗・導入失敗・再実行・一時ファイル清掃をテスト用スクリプトで確認しています。

実装コミット `317a39e` の [macOS CI 41315334930](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41315334930)、[ソース検査 41315334941](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41315334941)、[Linux両CPUの導入 41315334903](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41315334903)、[Windows両CPUの制御 41315334990](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/41315334990) がすべて成功しました。初回Homebrew導入の制御はダミーインストーラー、実セットアップはランナーの既存Homebrewで確認しており、macOSを初期化してCLToolsから実導入した検証ではありません。公式インストーラーはCLTools未導入時にAppleのsoftwareupdateを使用し、必要に応じてxcode-selectのGUIへフォールバックします。
