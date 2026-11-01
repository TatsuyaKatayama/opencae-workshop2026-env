#!/bin/bash
# lib.sh 読み込み後に使用。macOS 標準 Bash 3.2 対応。
mac_homebrew_available() { [[ -x /opt/homebrew/bin/brew ]]; }
mac_homebrew() { /opt/homebrew/bin/brew "$@"; }
mac_homebrew_terminal() { [[ -t 0 && -t 1 ]]; }

mac_verify_homebrew() {
    [[ "$(mac_homebrew --prefix)" == /opt/homebrew ]] || mac_die 'Apple Silicon 用 Homebrew の配置先が /opt/homebrew ではありません。'
    mac_homebrew --version
}

# 一時ファイルと EXIT trap をこの工程内に閉じる。
mac_bootstrap_homebrew() (
    set -euo pipefail
    if mac_homebrew_available; then
        mac_verify_homebrew
        exit 0
    fi
    mac_homebrew_terminal || mac_die 'Homebrew の初回導入には対話端末が必要です。Terminal または 0_Setup.command から再実行してください。'
    printf '%s\n' 'Homebrew がないため、公式インストーラーを起動します。' \
        '管理者パスワードや Command Line Tools の導入確認が表示された場合は、画面の案内に従ってください。' >&2
    source "$MAC_ROOT/setup/config/homebrew.env"
    [[ "$HOMEBREW_INSTALLER_URL" =~ ^https://raw\.githubusercontent\.com/Homebrew/install/[0-9a-f]{40}/install\.sh$ \
        && "$HOMEBREW_INSTALLER_SHA256" =~ ^[0-9a-f]{64}$ ]] || mac_die 'Homebrew の配布設定が不正です。'
    bootstrap_dir="$(mktemp -d "${TMPDIR:-/tmp}/opencae-homebrew.XXXXXX")"
    trap 'rm -rf -- "$bootstrap_dir"' EXIT
    curl --fail --silent --show-error --location --retry 3 --proto '=https' --proto-redir '=https' \
        --connect-timeout 30 --max-time 300 "$HOMEBREW_INSTALLER_URL" -o "$bootstrap_dir/install.sh"
    actual_sha="$(shasum -a 256 "$bootstrap_dir/install.sh" | cut -d ' ' -f 1)"
    [[ "$actual_sha" == "$HOMEBREW_INSTALLER_SHA256" ]] || mac_die 'Homebrew インストーラーの SHA256 が一致しません。実行しません。'
    # インストーラー自身の対話・sudo を利用する。親の CI/NONINTERACTIVE は引き継がない。
    status=0
    env -u CI -u NONINTERACTIVE INTERACTIVE=1 /bin/bash "$bootstrap_dir/install.sh" || status=$?
    if (( status != 0 )); then
        printf 'ERROR: Homebrew の導入に失敗しました (exit=%s)。原因を修正し、同じセットアップを再実行してください。\n' "$status" >&2
        exit "$status"
    fi
    mac_homebrew_available || mac_die 'Homebrew を確認できません。導入先と公式インストーラーの出力を確認してください。'
    mac_verify_homebrew
)
