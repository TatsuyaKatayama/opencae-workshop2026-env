# 検証記録

## 現在の状態

初期実装中です。講習向けの確認済みリリースではありません。

| 項目 | 状態 |
| --- | --- |
| 開発ホスト | WSL2、Ubuntu 24.04、ARM64、メモリ約32GB、Docker Engine 29.1.1 |
| 実行入口 | 引数・終了コード保持、別ディレクトリからの呼び出し、Desktop / remote 拒否の単体テストを実施 |
| apt 版 ParaView | 5.11.2+dfsg-6build5 + libosmesa6 を ARM64 一時コンテナへ導入。DISPLAY 不在で sphere を Render / SaveScreenshot すると vtkXOpenGLRenderWindow → XSync で SIGSEGV。採用せず |
| OpenFOAM | 公式 apt の openfoam2606-default 2606.0~rc2-1 を導入し、実行時の v2606 表示を確認。正式版ソースとの同一性は未確認 |
| ARM64 OSMesa ParaView | 5.13.3 の構成・コンパイル開始を確認。長時間の本検証は GitHub Actions へ移し、ローカルは中断（再開用キャッシュあり） |
| amd64 OSMesa ParaView | 同版の公式バイナリを取得し SHA256 を固定。GitHub Actions のネイティブランナーで描画を検証予定 |
| 直列・MPI・Python 後処理 | ネットワークなしの一時コンテナで通過。400セル、最終時刻0.02、速度差 L2=1.03e-9、圧力差 L2=9.73e-10。指定7パッケージの import、foamlib 読み込み、CSV・日本語グラフ保存、Optuna の小規模計算を確認 |
| 任意 UID の起動 | UID/GID 1001 で OpenFOAM v2606、Python パッケージ、MPI 実行パス /usr/bin/mpirun を確認 |
| 描画・動画・永続化の一括検証 | smoke-test.sh を実装。GitHub Actions で確認予定 |
| Windows 新規構築 | ARM64 / x64 とも未検証 |
| Crew / Kiro CLI / OpenCode | 未導入・未接続検証 |
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
