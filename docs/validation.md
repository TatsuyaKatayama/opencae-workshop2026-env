# 検証記録

## 現在の状態

初期実装中です。講習向けの確認済みリリースではありません。

| 項目 | 状態 |
| --- | --- |
| 開発ホスト | WSL2、Ubuntu 24.04、ARM64、メモリ約32GB、Docker Engine 29.1.1 |
| 実行入口 | 引数・終了コード保持、別ディレクトリからの呼び出し、Desktop / remote 拒否の単体テストを実施 |
| apt 版 ParaView | 5.11.2+dfsg-6build5 + libosmesa6 を ARM64 一時コンテナへ導入。DISPLAY 不在で sphere を Render / SaveScreenshot すると vtkXOpenGLRenderWindow → XSync で SIGSEGV。採用せず |
| OpenFOAM | 公式 apt の openfoam2606-default 2606.0~rc2-1 を導入し、実行時の v2606 表示を確認。正式版ソースとの同一性は未確認 |
| ARM64 OSMesa ParaView | ローカル WSL2 / ARM64 で 5.13.3 のビルド・CPU 描画・動画生成・永続化まで成功。修正版 CI は再検証中 |
| amd64 OSMesa ParaView | 同版の公式バイナリで成功。Linux amd64 のネイティブ Actions で計算・描画・動画・永続化まで通過（下記） |
| 直列・MPI・Python 後処理 | ネットワークなしの一時コンテナで通過。400セル、最終時刻0.02、速度差 L2=1.03e-9、圧力差 L2=9.73e-10。指定7パッケージの import、foamlib 読み込み、CSV・日本語グラフ保存、Optuna の小規模計算を確認 |
| 任意 UID の起動 | UID/GID 1001 で OpenFOAM v2606、Python パッケージ、MPI 実行パス /usr/bin/mpirun を確認 |
| 描画・動画・永続化の一括検証 | Linux amd64 の Actions とローカル WSL2 / ARM64 で成功 |
| Windows 新規構築 | ARM64 / x64 とも未検証 |
| Crew / Kiro CLI / OpenCode | この WSL に CLI 2.34.0 / Crew 0.9.0 を導入し管理画面を起動。利用者が認証し、Crew 経由の計算・描画・動画生成まで成功を報告。OpenCode は既存導入あり、Crew 接続は未検証 |
| Apple Silicon Mac | 後続工程 |

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

ARM64 の初回セットアップ CI は [40206466748](https://github.com/TatsuyaKatayama/opencae-workshop2026-env/actions/runs/40206466748) で実行中です。amd64 のネイティブ新規導入 CI を追加し、両 CPU の全工程の合否は CI 完了後に記録します。Kiro CLI 2.34.0、Crew 0.9.0、OpenCode 1.19.4、Codex CLI 0.164.0 と Docker 関連パッケージの採用版は共通です。認証・ブラウザー・WSL 新規作成・Proxy 経由通信は今回の CI の合格対象に含めません。
