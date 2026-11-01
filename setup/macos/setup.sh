#!/bin/bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
port=5476; cpu=2; memory=8; disk=100; plan=0; agents_only=0
while (( $# )); do
    case "$1" in
        --port|--cpu|--memory|--disk)
            (( $# >= 2 )) || mac_die "$1 の値が必要です。"
            key="${1#--}"; printf -v "$key" '%s' "$2"; shift 2 ;;
        --plan) plan=1; shift ;;
        --agents-only) agents_only=1; shift ;;
        --help|-h)
            echo 'setup.sh [--port 5476] [--cpu 2] [--memory 8] [--disk 100] [--plan] [--agents-only]'
            echo 'Apple Silicon / macOS 15+ / Homebrew が必要です。memory・disk は GiB。--plan は変更・通信なし。'
            exit 0 ;;
        *) mac_die "未対応の引数: $1" ;;
    esac
done
for value in "$port" "$cpu" "$memory" "$disk"; do
    [[ "$value" =~ ^[1-9][0-9]*$ && ${#value} -le 5 ]] || mac_die '数値オプションには正の整数を指定してください。'
done
(( port >= 1024 && port <= 65535 && cpu >= 2 && cpu <= 64 && memory >= 8 && memory <= 512 && disk >= 80 && disk <= 4096 )) || mac_die 'port=1024..65535 / cpu=2..64 / memory=8..512 / disk=80..4096 を指定してください。'
mac_platform
if (( plan )); then
    printf 'CPU=arm64\nport=%s\nColima: cpu=%s memory=%sGiB disk=%sGiB\n' "$port" "$cpu" "$memory" "$disk"
    if (( agents_only )); then echo '工程: prerequisites agents crew-config（Docker・CFD なし）'
    else echo '工程: prerequisites agents crew-config colima cfd-build cfd-check'; fi
    exit 0
fi
[[ -x /opt/homebrew/bin/brew ]] || mac_die 'Homebrew が必要です。https://brew.sh/ja/ の公式手順で導入してから再実行してください。'
# --force-bottle で Homebrew のソースビルドへの自動フォールバックを禁止。
export HOMEBREW_NO_AUTO_UPDATE=1
/opt/homebrew/bin/brew install --force-bottle python@3.12 pipx git
if (( ! agents_only )); then
    /opt/homebrew/bin/brew install --force-bottle colima docker docker-compose docker-buildx
fi
args=(setup --port "$port" --cpu "$cpu" --memory "$memory" --disk "$disk")
(( ! agents_only )) || args+=(--agents-only)
mac_control "${args[@]}"
