#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
[[ $# == 0 || ( $# == 1 && ( "$1" == --status || "$1" == --open-browser ) ) ]] || die '使用法: kiro-login.sh [--status|--open-browser]'
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
if [[ "${1:-}" == --open-browser ]]; then
    python3 "$SETUP_ROOT/setup/ubuntu2404/login_browser.py"
else
    kiro-cli login --use-device-flow
fi
authenticated || die '認証を確認できませんでした。同じコマンドで再試行してください。'
note 'Kiro CLI の認証が完了しました。'
