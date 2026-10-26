#!/usr/bin/env bash
# 呼び出し元で set -euo pipefail を有効化する。
SETUP_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

platform() {
    local ID VERSION_ID
    source /etc/os-release
    [[ "$ID:$VERSION_ID" == ubuntu:24.04 ]] || die 'Ubuntu 24.04 が必要です。'
    case "$(uname -m)" in
        aarch64|arm64) ARCH=arm64; ARCH_KEY=ARM64; LINUX_CPU=aarch64 ;;
        x86_64|amd64) ARCH=amd64; ARCH_KEY=AMD64; LINUX_CPU=x86_64 ;;
        *) die '対応 CPU は ARM64 / amd64 です。' ;;
    esac
    (( EUID != 0 )) || die 'sudo 権限を持つ通常ユーザーで実行してください。'
    [[ "$SETUP_ROOT" != /mnt/* ]] || die 'プロジェクトを Linux ファイルシステムへ配置してください。'
}

select_artifact() {
    local prefix="$1" url_var sha_var
    case "$prefix" in KIRO_CLI|OPENCODE|CODEX) ;; *) die '未対応の配布物です。' ;; esac
    url_var="${prefix}_${ARCH_KEY}_URL"; sha_var="${prefix}_${ARCH_KEY}_SHA256"
    ARTIFACT_URL="${!url_var}"; ARTIFACT_SHA256="${!sha_var}"
    [[ "$ARTIFACT_URL" == https://* && "$ARTIFACT_SHA256" =~ ^[0-9a-f]{64}$ ]] || die '配布設定が不正です。'
}

archive_binary() {
    case "$1" in
        codex) printf 'codex-%s-unknown-linux-musl\n' "$LINUX_CPU" ;;
        opencode) printf 'opencode\n' ;;
        *) die '未対応のバイナリです。' ;;
    esac
}

init_state() {
    STATE="$HOME/.local/state/opencae-workshop2026"
    umask 077
    mkdir -p "$STATE"
    chmod 700 "$STATE"
}

# 設定は JSON として読み、シェルコードとして評価しない。
load_config() {
    init_state
    [[ -f "$STATE/crew.json" ]] || die '先に setup.sh を実行してください。'
    local values
    values="$(python3 "$SETUP_ROOT/setup/ubuntu2404/state.py" read "$STATE/crew.json")" || die 'Crew 設定が不正です。'
    mapfile -t fields <<< "$values"
    PROJECT="${fields[0]}"; PORT="${fields[1]}"; UNIT="${fields[2]}"
    [[ "$PROJECT" == "$SETUP_ROOT" ]] || die '設定とプロジェクトの配置先が異なります。'
    load_proxy
}

load_proxy() {
    [[ -f "$STATE/proxy.json" ]] || return 0
    local values
    values="$(python3 "$SETUP_ROOT/setup/ubuntu2404/state.py" proxy-read "$STATE/proxy.json")" || die 'Proxy 設定を確認してください。'
    mapfile -t proxy_fields <<< "$values"
    export HTTP_PROXY="${proxy_fields[0]}" HTTPS_PROXY="${proxy_fields[1]}" NO_PROXY="${proxy_fields[2]}"
    export http_proxy="$HTTP_PROXY" https_proxy="$HTTPS_PROXY" no_proxy="$NO_PROXY"
}

user_bus() {
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    systemctl --user show-environment >/dev/null 2>&1 || die 'ユーザー systemd に接続できません。WSL を再起動して再実行してください。'
}

authenticated() { timeout 30 kiro-cli whoami >/dev/null 2>&1; }

download() {
    local url="$1" digest="$2" dest="$3"
    [[ "$url" == https://* && "$digest" =~ ^[0-9a-f]{64}$ ]] || die '配布設定が不正です。'
    if [[ -f "$dest" ]] && printf '%s  %s\n' "$digest" "$dest" | sha256sum --check --status; then return; fi
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 30 --max-time 1200 "$url" -o "$dest.part"
    printf '%s  %s\n' "$digest" "$dest.part" | sha256sum --check --status || die '取得ファイルの SHA256 が一致しません。'
    mv -- "$dest.part" "$dest"
}

has_version() {
    local output
    command -v "$1" >/dev/null || return 1
    output="$(timeout 30 "$1" --version 2>/dev/null)" || return 1
    # 1.2.3 を 11.2.30 に誤一致させない。
    python3 -c 'import re,sys; sys.exit(not re.search(r"(?<![0-9.])"+re.escape(sys.argv[1])+r"(?![0-9.])",sys.argv[2]))' "$2" "$output"
}
