#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
[[ $# == 0 || ( $# == 1 && "$1" == --status ) ]] || die '使用法: kiro-login.sh [--status]'
platform
load_config
command -v kiro-cli >/dev/null || die 'Kiro CLI が見つかりません。setup.sh を実行してください。'
if authenticated; then
    note 'Kiro CLI は認証済みです。'
    exit 0
fi
[[ "${1:-}" != --status ]] || exit 3
[[ -t 0 && -t 1 ]] || die '対話端末で実行してください。'
note '表示される URL をブラウザーで開き、コードを入力してください。認証出力を共有ログへ保存しないでください。'
# PS 側でのブラウザー連携は後続。ここでは URL とコードを端末へ直接表示する。
kiro-cli login --use-device-flow
authenticated || die '認証を確認できませんでした。同じコマンドで再試行してください。'
note 'Kiro CLI の認証が完了しました。'
