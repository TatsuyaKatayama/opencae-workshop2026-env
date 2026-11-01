#!/bin/bash
# macOS 標準 Bash 3.2 でも動作する。呼び出し元で set -euo pipefail。
MAC_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
MAC_STATE="$HOME/.local/state/opencae-workshop2026-macos"
MAC_TOOLS="$HOME/.local/share/opencae/macos"
export PATH="$MAC_TOOLS/bin:/opt/homebrew/opt/python@3.12/libexec/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
export KIROCREW_HOME="$MAC_TOOLS/crew"
# subprocess と launchd へも同じ接続先を引き継ぐ。他の context は変更しない。
MAC_CONTEXT=colima-opencae-workshop2026
mac_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
mac_platform() {
    [[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || mac_die 'Apple Silicon のネイティブ端末で実行してください。Intel / Rosetta は対象外です。'
    [[ "$(sw_vers -productVersion | cut -d . -f 1)" -ge 15 ]] || mac_die 'macOS 15 以降が必要です。'
    (( EUID != 0 )) || mac_die '通常ユーザーで実行してください。sudo で起動しないでください。'
    case "$MAC_ROOT" in *$'\n'*|*$'\r'*|*:*) mac_die '配置先に改行やコロンは使用できません。' ;; esac
    [[ -z "${COLIMA_HOME:-}" && -z "${LIMA_HOME:-}" && -z "${DOCKER_CONFIG:-}" ]] || mac_die 'COLIMA_HOME / LIMA_HOME / DOCKER_CONFIG を解除してください。'
    [[ -z "${DOCKER_HOST:-}" ]] || mac_die 'DOCKER_HOST を解除してください。'
    [[ -z "${DOCKER_CONTEXT:-}" || "$DOCKER_CONTEXT" == "$MAC_CONTEXT" ]] || mac_die '別の DOCKER_CONTEXT が指定されています。解除してください。'
}
mac_python() {
    [[ -x /opt/homebrew/opt/python@3.12/bin/python3.12 ]] || mac_die '先に setup/macos/setup.sh を実行してください。Python 3.12 が必要です。'
    /opt/homebrew/opt/python@3.12/bin/python3.12 "$@"
}
mac_control() { mac_python "$MAC_ROOT/setup/macos/control.py" "$@"; }
