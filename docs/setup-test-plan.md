# セットアップスクリプトのテスト計画

更新日：2026-10-25。対象スクリプト・テスト・CI ジョブは未実装。この文書は実装前の受け入れ条件であり、既存計算コンテナの検証成功とは区別する。

## 検証の分担

| 区分 | 実行環境 | 確認範囲 |
| --- | --- | --- |
| 自動・制御 | GitHub Actions Windows／Ubuntu | 入力、設定、外部コマンドへの引数、終了コード、失敗・再開判定。WSL 等をモック化したテストは実起動検証として数えない |
| 自動・Linux 統合 | Ubuntu 24.04 ARM64／amd64 | Bash の導入処理、各ツールの版、権限、Docker・CFD 検証。systemd が必要なものは利用可能な VM で実施 |
| WSL2 統合 | Windows ARM64／x64 の実機、または WSL2 対応セルフホスト型ランナー | 専用 Ubuntu の新規作成、配置、ユーザー、systemd、Docker、起動・停止、再開 |
| 手動 | Windows ARM64／x64 | 個人認証、既定ブラウザー、ショートカット操作、再起動後の復帰、Crew 会話・動画再生 |

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
| S08 | Setup.ps1 | 設定保存と3ショートカット作成。ConfigPath、対象環境・ユーザー・プロジェクトパスが一致 | 自動＋手動 |
| L01 | setup.sh | Ubuntu 24.04、ARM64／amd64 を判定し、対象外 OS／CPU を拒否 | 自動＋Linux |
| L02 | setup.sh | Docker Engine／CLI・Compose・Buildx、Kiro CLI・Crew・OpenCode・Codex CLI の指定版を導入 | Linux＋WSL2 |
| L03 | setup.sh | システム操作の権限と、CLI・Crew・作業ファイルの指定ユーザー所有を確認 | Linux＋WSL2 |
| L04 | setup.sh | 新規セッションの指定ユーザーから対象 Engine を利用できる。Desktop・別デーモンを誤利用しない | Linux＋WSL2 |
| L05 | setup.sh | 再実行で版・設定・認証・成果物を保持し、完了工程とビルドキャッシュを利用 | 自動＋Linux＋WSL2 |
| L06 | setup.sh | 通信失敗、ハッシュ不一致、容量不足、導入・ビルド失敗を成功扱いせず工程とログを報告 | 自動＋統合 |
| L07 | setup.sh | 自 CPU 用 CFD イメージをビルドし、既存 smoke-test.sh で計算・描画・動画・保持を確認 | Linux＋WSL2 |
| A01 | Login の PS1／Bash | 認証済みなら再認証せず終了。未認証ならデバイス認証と完了確認 | 自動＋手動 |
| A02 | Login の PS1／Bash | URL・コードを案内し、Windows 既定ブラウザーを開く。自動取得不可時の案内を確認 | 自動＋手動 |
| A03 | Login の PS1／Bash | キャンセル・期限切れ・通信失敗を区別して案内し、再試行可能。失敗端末を読める | 自動＋手動 |
| A04 | Login の PS1／Bash | Crew と同じ Linux ユーザーに認証が保存され、別ユーザーへ混入しない | 手動 |
| C01 | Start の PS1／Bash | 設定欠落、対象環境不在、Docker 停止、未認証を検出し、復旧操作を案内 | 自動＋WSL2 |
| C02 | Start の PS1／Bash | 起動完了後にアクセス URL を開く。起動端末を閉じても稼働継続 | WSL2＋手動 |
| C03 | Start の PS1／Bash | 起動済みなら二重起動せず画面を開く。同時起動要求でも重複しない | 自動＋WSL2 |
| C04 | Start の PS1／Bash | 他プロセスのポート競合、起動失敗、タイムアウトを検出。無関係な画面を開かない | 自動＋WSL2 |
| C05 | Start の PS1／Bash | localhost のみで待ち受け、トンネルなし。正しい環境の URL を開く | WSL2＋手動 |
| T01 | Stop の PS1／Bash | 起動中は正常終了と停止確認、未起動は正常終了 | 自動＋WSL2 |
| T02 | Stop の PS1／Bash | 停止失敗・タイムアウトを報告。別 Crew、Docker、計算コンテナを停止しない | 自動＋WSL2 |

## 横断項目

- 複数環境の設定・ショートカット・ログを分離する。同時起動する Crew は異なる Windows localhost ポートを使用する。ポート割当方法は実装時に確定する。
- Bash の終了コードを PowerShell が保持し、成功と失敗を正しく表示する。
- パスワード・トークン・認証コード・アクセス URL・Proxy の秘密情報が共有ログ、Git、CI artifact、ショートカットに残らない。認証中の端末表示と保護されたローカルログは別に確認する。
- Ubuntu 単体で Bash を直接実行し、Windows コマンドなしでセットアップ・認証・起動・停止できる。
- Proxy プレビューは無効時に設定を変更しない。有効時は導入通信、Docker 取得、ビルド、CLI／Crew 通信を別々に検証する。localhost が Proxy を経由しないこと、認証付き Proxy の秘密情報が漏れないことを確認する。独自 CA の対応は別項目とする。

## 最終受け入れ

Windows ARM64／x64 それぞれで、配布取得 → Setup → Windows 再起動 → Kiro CLI Login → Start Kiro Crew → Crew から smoke-test.sh → 動画再生 → Stop Kiro Crew → 再度 Start を行い、認証・成果物の保持を確認する。clone／ZIP、既定／任意環境名、既定／任意保存先を検証ケースへ割り当て、どの組み合わせを確認したか記録する。

記録にはテスト ID、対象 CPU、Windows／WSL／Ubuntu・ソフトの版、Git コミット、方法、成功／失敗／未実施、ログの場所を含める。実行していない項目を推測で成功にしない。Proxy プレビューは正式な通常経路の合格判定と分ける。

## 根拠資料

- [Canonical：Ubuntu WSL 用 GitHub Actions](https://ubuntu.com/wsl/docs/latest/reference/actions/)
- [GitHub：ホスト型ランナーとネストした仮想化の制限](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners)
- [GitHub：ランナーの OS・CPU・リソース](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
