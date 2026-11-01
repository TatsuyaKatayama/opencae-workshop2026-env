# CI構成

入口は [ci.yml](../.github/workflows/ci.yml) です。各OSのworkflowは共通入口から呼び出し、個別の手動実行も残します。利用者向けのセットアップ手順と導入バージョンは変更していません。

## 起動条件

| イベント | 検証 |
| --- | --- |
| develop／main向けPR | ソース検査＋変更ファイルに関係するOS・バックエンド・実VM境界 |
| mainへのpush | 関連変更がある場合に、両CPUのCFD統合 |
| CIの手動実行 | 全OSの検証＋両CPUのUbuntu新規導入・CFD統合 |
| 個別workflowの手動実行 | 指定した検証のみ |

feature／developへのpush、タグのpushでは自動起動しません。PR更新時は同じPRの古いCIをキャンセルします。developへのPRとmainへのPRは、それぞれのマージ先に統合した状態を検証します。

[changes.py](../scripts/ci/changes.py) が変更ファイルから対象を選びます。資料だけの変更ではOSの実導入を行いません。Windows専用変更はMacやLinuxの導入を起動せず、Mac専用変更はWindowsやCFDを起動しません。入口・選択ロジックの変更と全体の手動実行では全対象を選びます。

`required` が各検証の失敗・キャンセルを集約します。PRの必須チェックを設定する場合はこのジョブを使用します。対象外のジョブのskipは許可しますが、失敗をskipへ置き換えません。

## 確認範囲

| ジョブ | 実行環境と内容 |
| --- | --- |
| source | Ubuntuで構文、Python単体テスト、Compose定義。Mac専用の実launchdテストはMacで実施 |
| windows | Windows x64／ARM64、PowerShell 5.1／7。制御・再開・削除保護と実CMDの引数・終了コード |
| windows-wsl | Windows x64の実WSL2 Ubuntu 24.04。両PowerShellから製品の引数転送、日本語パス、stdout／stderr、終了コード、プロジェクト配置・LF正規化・秘密ファイル除外・再配置 |
| backends | Ubuntu ARM64／amd64で固定CLI実導入・再導入、未認証状態、ACP初期応答 |
| macos | Apple Silicon macOS 15。標準Bash、固定CLI実導入・再導入、ACP、実launchdとダミーHTTPサービス |
| macos-vm | Apple Silicon macOS 15。実Colima Linux VMから製品のDocker接続チェック、UbuntuコンテナのCompose実行、日本語引数、双方向共有、UID、永続化、終了コード |
| setup | 使い捨てUbuntuのARM64／amd64で既存Dockerを除去し、製品のDocker導入からCLI・CFDビルド・スモークまで実行 |
| image | Ubuntu両CPUのCFDビルド・計算・MPI・OSMesa描画・Python後処理・動画・永続化 |

mainではUbuntu導入関連の変更があれば `setup`、CFD関連だけなら `image` を選びます。`setup` 自体がCFDビルドとスモークを含むため、同じCPUで `image` を重複実行しません。PRでは長いCFDビルドを行いません。

`paraview-arm64.yml` は依存ロック再調査用の手動workflowです。通常の製品ビルドは既存ロックを使用し、ソルバーを毎回実行しません。

## 実VMの限界

Macのホスト型ランナーではQEMU／TCGのソフトウェアエミュレーションと9p共有を使用します。製品の標準構成はVZ／virtiofsのままです。CIはMac→Linux VM内Docker→Ubuntuコンテナ→Macの実際の経路を検証しますが、VZ／virtiofsやMac上のCFD全体の合格とは扱いません。計算イメージの内容はLinux両CPUで検証します。

Windowsは実WSL2カーネルを確認してから本番ヘルパーを呼び出します。WSL1やモックを実WSL2の合格扱いにしません。追加CIはx64の引数・配置境界に限定し、製品のrootfsインポートやsystemd＋Docker＋Crew全体、ARM64上の実WSL2を検証したとは扱いません。

個人認証、ブラウザー、Finder／CMDの対話操作、OS再起動後の復帰などは実機確認が必要です。Homebrewの初回対話導入は制御テストであり、Mac CIの実バイナリ導入には既存Homebrewを使用します。

## 結果の取得

Actionsの各実行でジョブとステップの成否を確認します。CFDのartifactは `validation-ubuntu-24.04`／`validation-ubuntu-24.04-arm`、新規導入は `ubuntu2404-setup-amd64`／`ubuntu2404-setup-arm64` です。`work/` 内のログ・PNG・MP4・結果JSONを保存します。ビルド済みイメージや個人の認証情報・Crewログは公開しません。
