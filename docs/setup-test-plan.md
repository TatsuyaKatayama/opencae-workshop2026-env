# セットアップスクリプトのテスト計画

更新日：2026-11-01。Ubuntu 24.04 の Bash スクリプト、制御テスト、ARM64／amd64 統合 CI を実装済み。Windows 用スクリプトとモックによる制御テストも実装済み。この文書の全項目が通過したという意味ではなく、実施結果は docs/validation.md と CI に記録する。

## 検証の分担

| 区分 | 実行環境 | 確認範囲 |
| --- | --- | --- |
| 自動・制御 | GitHub Actions Windows／Ubuntu | 入力、設定、外部コマンドへの引数、終了コード、失敗・再開判定。WSL 等をモック化したテストは実起動検証として数えない |
| 自動・Linux 統合 | Ubuntu 24.04 ARM64／amd64 | Bash の導入処理、各ツールの版、権限、Docker・CFD 検証。systemd が必要なものは利用可能な VM で実施 |
| WSL2 統合 | Windows ARM64／x64 の実機、または WSL2 対応セルフホスト型ランナー | 専用 Ubuntu の新規作成、配置、ユーザー、systemd、Docker、起動・停止、再開 |
| 手動 | Windows ARM64／x64 | 個人認証、既定ブラウザー、CMD 起動操作、再起動後の復帰、Crew 会話・動画再生 |

Canonical は WSL の導入・rootfs 取得・Bash 実行用 Actions を提供している。ただし Actions の存在は GitHub ホスト型ランナー上の WSL2 動作保証を意味しない。GitHub はネストした仮想化を正式サポートしていないため、標準 Windows ランナーだけで WSL2＋systemd＋Docker の全工程を保証しない。WSL1 の成功は代替の合格条件にしない。

WSL2 CI はまずカーネル起動を含む能力確認を行い、対応環境を確定してから有効化する。非対応による未実施は成功と区別する。セルフホスト型の破壊的な新規作成検証は専用の検証機で手動起動し、本テストが作成した環境のみ後片付けする。個人認証情報を持つ通常の開発環境で、外部 PR のコードを実行しない。

## スクリプト別の項目

| ID | 対象 | テストと期待結果 | 方法 |
| --- | --- | --- | --- |
| S01 | Setup.ps1 | 必須入力、既定値、環境名・ユーザー名・保存先の検証。不正値では環境を変更しない | 自動 |
| S02 | Setup.ps1 | 空白・日本語を含む配布元と保存先、引数の引用を保持し、値をコマンドとして実行しない | 自動＋WSL2 |
| S03 | Setup.ps1 | WSL 未導入、WSL2 不可、再起動待ちを判定し、次の操作を案内 | 自動＋手動 |
| S04 | Setup.ps1 | 同名環境・既存データを拒否し、既存 WSL の内容・既定環境を変更しない | 自動＋WSL2 |
| S05 | Setup.ps1 | 任意名・既定／指定保存先で Ubuntu 24.04／WSL2 を作成し、指定ユーザー・sudo・systemd を確認 | WSL2 |
| S06 | Setup.ps1 | clone／ZIP から Linux ファイルシステムへ配置。元の配布ディレクトリを移動しても起動可能 | WSL2＋手動 |
| S07 | Setup.ps1 | 作成記録が一致する未完了環境のみ再開。記録不整合や他環境を再利用しない | 自動＋WSL2 |
| S08 | Setup.ps1 | インストール先への設定保存と4 CMD 配置。ConfigPath、対象環境・ユーザー・プロジェクトパスが一致 | 自動＋手動 |
| L01 | setup.sh | Ubuntu 24.04、ARM64／amd64 を判定し、対象外 OS／CPU を拒否 | 自動＋Linux |
| L02 | setup.sh | Docker Engine／CLI・Compose・Buildx、Kiro CLI・Crew・OpenCode・Codex CLI の指定版を導入 | Linux＋WSL2 |
| L03 | setup.sh | システム操作の権限と、CLI・Crew・作業ファイルの指定ユーザー所有を確認 | Linux＋WSL2 |
| L04 | setup.sh | 新規セッションの指定ユーザーから対象 Engine を利用できる。Desktop・別デーモンを誤利用しない | Linux＋WSL2 |
| L05 | setup.sh | 再実行で版・設定・認証・成果物を保持し、完了工程とビルドキャッシュを利用 | 自動＋Linux＋WSL2 |
| L06 | setup.sh | 通信失敗、ハッシュ不一致、容量不足、導入・ビルド失敗を成功扱いせず工程とログを報告 | 自動＋統合 |
| L07 | setup.sh | 自 CPU 用 CFD イメージをビルドし、既存 smoke-test.sh で計算・描画・動画・保持を確認 | Linux＋WSL2 |
| A01 | Start Backend の PS1／Bash | Kiro／Codex は認証済みなら再認証しない。OpenCode は提供先別認証とモデル確認、認証省略の選択を確認 | 自動＋手動 |
| A02 | Start Backend の PS1／Bash | URL・コードを案内し、Windows 既定ブラウザーを開く。自動取得不可時の案内を確認 | 自動＋手動 |
| A03 | Start Backend の PS1／Bash | キャンセル・期限切れ・通信失敗を区別して案内し、再試行可能。失敗端末を読める | 自動＋手動 |
| A04 | Start Backend の PS1／Bash | Crew と同じ Linux ユーザーに認証が保存され、別ユーザーへ混入しない | 手動 |
| C01 | Start の PS1／Bash | 設定欠落、対象環境不在、Docker 停止を検出して復旧操作を案内。モデル未認証でも管理画面は起動可能 | 自動＋WSL2 |
| C02 | Start の PS1／Bash | 起動完了後にアクセス URL を開く。起動端末を閉じても稼働継続 | WSL2＋手動 |
| C03 | Start の PS1／Bash | 起動済みなら二重起動せず画面を開く。同時起動要求でも重複しない | 自動＋WSL2 |
| C04 | Start の PS1／Bash | 他プロセスのポート競合、起動失敗、タイムアウトを検出。無関係な画面を開かない | 自動＋WSL2 |
| C05 | Start の PS1／Bash | localhost のみで待ち受け、トンネルなし。正しい環境の URL を開く | WSL2＋手動 |
| T01 | Stop の PS1／Bash | 起動中は正常終了と停止確認、未起動は正常終了 | 自動＋WSL2 |
| T02 | Stop の PS1／Bash | 停止失敗・タイムアウトを報告。別 Crew、Docker、計算コンテナを停止しない | 自動＋WSL2 |

| B01 | Start Backend | Kiro／Codex／OpenCode を選択。Codex で Kiro 認証を要求しない。不正なバックエンドや失敗時に設定を更新しない | 自動＋手動 |
| B02 | CLI 導入 | 両 CPU で同じ固定版のバイナリ・wheel を取得しハッシュ検証。Codex ACP と Node の lockfile 導入・再実行、ACP 初期応答を確認 | Linux CI |
| R01 | RemoveEnvironment.ps1 | 登録 ID・保存先・識別記録の不一致、無関係な設定パスでは削除しない | 自動＋WSL2 |
| R02 | RemoveEnvironment.ps1 | -WhatIf／確認拒否では削除・設定変更なし。unregister 失敗時はメタデータを保持 | 自動＋手動 |
| R03 | RemoveEnvironment.ps1 | 対象のみ unregister。対応する起動ファイルと既知メタデータを削除し、他環境・Windows 配布元・未知ファイルを保持。途中再開も確認 | 自動＋WSL2 |

| U01 | UpdateLaunchers.ps1 | AppData／MSIX の旧記録から保存先へ移行。同じ登録 ID・保存先・識別記録の確認後に配置し、別環境や曖昧な記録を拒否 | 自動＋WSL2 |
| U02 | CMD 起動ファイル | 空白・日本語を含む保存先、別の現在位置から4 CMD を実行し、同じフォルダーの設定を渡して終了コードを保持 | Windows CI＋手動 |
| S09 | Setup.ps1 | インポート前の記録は保存先の外へ置き、インポート成功後に保存先へ移す。途中再開で登録済みディスクを再インポートしない | 自動＋WSL2 |

| C06 | Crew 稼働維持 | Windows が選択した WSL・ユーザーで非表示の維持プロセスを起動。重複せず、HTTP の一時不調に左右されず、サービス停止で終了 | 自動＋WSL2 |
| C07 | Crew 再起動 | 実 TCP の TIME_WAIT でも起動前確認を通過し、実際の LISTEN ソケットは拒否。Stop → Start を連続実行 | 自動＋WSL2 |

| R04 | 9_Allclean.cmd | 日本語で対象・登録解除コマンド・データ消失を警告し、DELETE 入力時だけ実行。空入力・その他・WhatIf で削除しない。自分の CMD が消えても終了できる | 自動＋Windows CI＋手動 |
| U03 | 配置変更 | PS1 と runtime は scripts 配下、CMD は番号付き4本。旧管理ファイルだけを整理し、無関係なファイルを保持する | 自動 |

## 横断項目

- 複数環境の設定・起動ファイル・ログを分離する。同時起動する Crew は異なる Windows localhost ポートを使用する。ポート割当方法は実装時に確定する。
- Bash の終了コードを PowerShell が保持し、成功と失敗を正しく表示する。
- パスワード・トークン・認証コード・アクセス URL・Proxy の秘密情報が共有ログ、Git、CI artifact、起動ファイルに残らない。認証中の端末表示と保護されたローカルログは別に確認する。
- Ubuntu 単体で Bash を直接実行し、Windows コマンドなしでセットアップ・認証・起動・停止できる。
- Proxy プレビューは無効時に設定を変更しない。有効時は導入通信、Docker 取得、ビルド、CLI／Crew 通信を別々に検証する。localhost が Proxy を経由しないこと、認証付き Proxy の秘密情報が漏れないことを確認する。独自 CA の対応は別項目とする。

## 最終受け入れ

Windows ARM64／x64 それぞれで、配布取得 → Setup → Windows 再起動 → Start Backend → Start Kiro Crew → Crew から smoke-test.sh → 動画再生 → Stop Kiro Crew → 再度 Start を行い、認証・成果物の保持を確認する。Kiro CLI／Codex／OpenCode の各バックエンドで実施し、OpenCode の提供先・モデルも記録する。削除検証は成果物を退避した専用環境で行う。clone／ZIP、既定／任意環境名、既定／任意保存先を検証ケースへ割り当て、どの組み合わせを確認したか記録する。

記録にはテスト ID、対象 CPU、Windows／WSL／Ubuntu・ソフトの版、Git コミット、方法、成功／失敗／未実施、ログの場所を含める。実行していない項目を推測で成功にしない。Proxy プレビューは正式な通常経路の合格判定と分ける。

## 根拠資料

- [Canonical：Ubuntu WSL 用 GitHub Actions](https://ubuntu.com/wsl/docs/latest/reference/actions/)
- [GitHub：ホスト型ランナーとネストした仮想化の制限](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners)
- [GitHub：ランナーの OS・CPU・リソース](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

## macOS（Apple Silicon）

| ID | 対象 | 確認内容 | 自動化 |
| --- | --- | --- | --- |
| MAC-00 | Homebrew | 既存環境の配置先・版確認、未導入なら公式インストーラー実行、対話入力維持、URL・SHA256検証、取得・導入失敗で停止、一時ファイル清掃、再実行 | Bash制御CI／管理者入力・CLTの初回実導入は実機 |
| MAC-01 | setup.sh | Apple Silicon・macOS 15+・通常ユーザー、数値・未知引数、--planで変更や通信なし | 標準 Bash 構文・制御CI／実機 |
| MAC-02 | 導入 | 公式 macOS バイナリの版・SHA256、Kiro署名、Crew wheelのみ、既存CLIの非上書き | macOSバイナリCI |
| MAC-03 | 再実行 | 同設定で再開、異なる設定は拒否、成功状態と選択バックエンドを保持 | 制御CI・再導入CI |
| MAC-04 | Colima | 同名の管理外profile拒否、VZ・aarch64・virtiofs・書き込みマウント、既定context非変更 | 制御CI／VMは実機 |
| MAC-05 | Docker入口 | 専用socket・context・CPU照合、Desktop／リモート／設定領域上書きを拒否 | 制御CI |
| MAC-06 | 認証 | 状態確認で変更なし、未認証は対話限定、Codex既認証ならKiro不要、OpenCode選択 | 制御CI・未認証CI／認証は実機 |
| MAC-07 | ブラウザー | 許可した認証URL、localhost・正しいportのCrew URL、シェル評価なし | 制御CI／既定ブラウザーは実機 |
| MAC-08 | launchd | 専用label・argv・PATH・context・ログ権限、ログイン自動起動なし、重複起動回避、起動timeout | 制御CI・実launchd＋ダミーHTTPのCI／Crew本体は実機 |
| MAC-09 | Stop | 対象jobだけbootout、停止済みは正常終了、Colima・計算コンテナ・別Crewを停止しない | 制御CI・実launchd＋ダミーHTTPのCI／Crew本体の正常終了は実機 |
| MAC-10 | CFD | 共通ケースの直列・MPI・CPU描画・動画・再作成後の保持・MacのUID/GID書き込み | Linux両CPU CI／Colima経由は実機 |
| MAC-11 | 利用操作 | Finderの.command起動、空白・日本語パス、Terminal終了後の継続、Stop直後再起動、再ログイン | 実機 |

macOS標準CIはVZのネストした仮想化を要求しない。`--agents-only` でホストCLI・Crew・ACPを実導入し、ColimaとCFDは構築しない。Mac実機の成功をモックCIで代替しない。Intel Mac・Proxy自動設定は今回の対象外。

ARM64 ParaViewの取得方式を変更したため、コンテナのCIでは `vtkOSOpenGLRenderWindow` と llvmpipe、OpenFOAMReader、一般後処理venvとの分離、ffmpeg、MPIも再確認する。ロックはconda-forge URLと全依存SHA256を固定し、開発用WSLでは導入・ビルドしない。

Homebrew初回導入の制御テストは実際のインストーラー・sudoを実行せず、テスト用スクリプトに置き換える。macOS CIでは標準Bashでも同じ分岐を確認し、ランナーの既存Homebrewを使う実セットアップも継続する。開発ホストへのHomebrew導入やCLI導入は行わない。

Macの通常導入では既存のOpenFOAMスモークを自動実行する。hello-world／SSHログイン／Nginxの専用テストは必須にしない。コンテナからのHTTP公開を使わない今回の構成では、ポート転送の成功をCFDの完了条件に含めない。
