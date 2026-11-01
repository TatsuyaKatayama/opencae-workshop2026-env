#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
backend=''; status=0; open_browser=0; skip_auth=0
while (( $# )); do
    case "$1" in
        --backend) (( $# >= 2 )) || die '--backend の値が必要です。'; backend="$2"; shift 2 ;;
        --status) status=1; shift ;;
        --open-browser) open_browser=1; shift ;;
        --skip-auth) skip_auth=1; shift ;;
        *) die '使用法: start-backend.sh --backend kiro|codex|opencode [--status|--open-browser]' ;;
    esac
done
case "$backend" in kiro|codex|opencode) ;; *) die '--backend kiro|codex|opencode を指定してください。' ;; esac
[[ "$skip_auth" == 0 || "$backend" == opencode ]] || die '--skip-auth は OpenCode 専用です。'
platform
load_config
command -v kirocrew >/dev/null || die '先に setup.sh を実行してください。'
tool="$backend"; [[ "$backend" != kiro ]] || tool=kiro-cli
command -v "$tool" >/dev/null || die "$tool が見つかりません。setup.sh を確認してください。"
if [[ "$backend" == codex ]]; then
    command -v codex-acp >/dev/null || die 'Codex ACP アダプターが見つかりません。setup.sh を確認してください。'
fi
check_auth() {
    case "$backend" in
        kiro) authenticated ;;
        codex) timeout 30 codex login status >/dev/null 2>&1 ;;
        opencode) return 4 ;; # 保存済み認証の一覧だけではモデルの利用可否を断定できない。
    esac
}
if (( status )); then
    if [[ "$backend" == opencode ]]; then
        note 'OpenCode の認証・モデル利用可否は自動判定できません。Crew で提供先とモデルを確認してください。'
        exit 4
    fi
    check_auth && exit 0
    exit 3
fi
exec 9>"$STATE/crew.lock"
flock -w 30 9 || die 'Crew の起動・停止またはバックエンド設定が実行中です。'
if (( ! skip_auth )) && ! check_auth; then
    [[ -t 0 && -t 1 ]] || die '認証には対話端末が必要です。'
    case "$backend" in
        kiro)
            if (( open_browser )); then python3 "$SETUP_ROOT/setup/ubuntu2404/login_browser.py" kiro
            else kiro-cli login --use-device-flow; fi ;;
        codex)
            note 'ChatGPT の個人設定または組織設定でデバイスコード認証を許可してください。'
            if (( open_browser )); then python3 "$SETUP_ROOT/setup/ubuntu2404/login_browser.py" codex
            else codex login --device-auth; fi ;;
        opencode)
            note '提供先を選んで API キーまたは OAuth で認証してください。ローカルモデル等は --skip-auth で選択のみ行えます。'
            if (( open_browser )); then python3 "$SETUP_ROOT/setup/ubuntu2404/login_browser.py" opencode
            else opencode auth login; fi ;;
    esac
    if [[ "$backend" != opencode ]]; then check_auth || die '認証を確認できませんでした。再実行してください。'; fi
fi
# 環境全体の選択。進行中のターンを中断しないため、再起動は利用者に案内する。
kirocrew config set agent.acp_backend "$backend"
kirocrew config set agent.kas_bundle false
printf '%s\n' "$backend" > "$STATE/backend"
note "バックエンドを $backend に設定しました。Start Kiro Crew を実行してください。"
note 'Crew が起動中なら Stop Kiro Crew → Start Kiro Crew で設定を反映してください。'
[[ "$backend" != opencode ]] || note 'OpenCode の提供先・モデルを Crew の画面で選び、会話できることを確認してください。'
