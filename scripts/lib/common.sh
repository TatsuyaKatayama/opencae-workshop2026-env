#!/usr/bin/env bash
# 呼び出し元は set -euo pipefail を有効にする。
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
set -a
source "$REPO_ROOT/versions.env"
set +a
if [[ "$(uname -s)" == Darwin ]]; then
    export PATH="$PATH:$HOME/.local/share/opencae/macos/bin:/opt/homebrew/bin:/opt/homebrew/sbin"
fi
export HOST_UID="$(id -u)" HOST_GID="$(id -g)"
case "$(uname -m)" in
    aarch64|arm64) export CFD_PLATFORM=linux/arm64 ;;
    x86_64|amd64) export CFD_PLATFORM=linux/amd64 ;;
    *) echo '対応 CPU は ARM64 / amd64 です。' >&2; return 1 ;;
esac
fail() { echo "ERROR: $*" >&2; exit 1; }
compose() {
    docker compose --project-directory "$REPO_ROOT" \
        --env-file "$REPO_ROOT/versions.env" \
        -f "$REPO_ROOT/compose/compose.yaml" "$@"
}
require_engine() {
    command -v docker >/dev/null || fail 'Docker CLI がありません。各 OS のセットアップを実行してください。'
    local binary endpoint info server_arch expected_endpoint
    binary="$(command -v docker)"
    [[ "$binary" != /mnt/* && "$binary" != *docker.exe ]] || fail 'WSL 内の Linux 版 Docker CLI を使用してください。'
    expected_endpoint=unix:///var/run/docker.sock
    if [[ "$(uname -s)" == Darwin ]]; then
        [[ "$(uname -m)" == arm64 ]] || fail 'Apple Silicon のネイティブ端末を使用してください。'
        [[ -z "${DOCKER_HOST:-}" ]] || fail 'DOCKER_HOST を解除してください。講習用 Colima だけを使用します。'
        [[ -z "${COLIMA_HOME:-}" && -z "${LIMA_HOME:-}" && -z "${DOCKER_CONFIG:-}" ]] || fail 'Colima / Docker の設定領域を変更する環境変数を解除してください。'
        [[ -z "${DOCKER_CONTEXT:-}" || "$DOCKER_CONTEXT" == colima-opencae-workshop2026 ]] || fail '別の DOCKER_CONTEXT が指定されています。'
        export DOCKER_CONTEXT=colima-opencae-workshop2026
        expected_endpoint="unix://$HOME/.colima/opencae-workshop2026/docker.sock"
    fi
    endpoint="${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}"
    [[ "$endpoint" == "$expected_endpoint" ]] || fail "接続先が標準構成ではありません: ${endpoint}。各 OS の導入手順を確認してください。"
    info="$(docker info --format '{{.OperatingSystem}}|{{.OSType}}|{{.Architecture}}')" || fail 'WSL 内の Docker Engine へ接続できません。サービスとグループ反映を確認してください。'
    [[ "$(printf '%s' "$info" | tr '[:upper:]' '[:lower:]')" != *desktop* && "$info" == *'|linux|'* ]] || fail 'Docker Desktop は対象外です。WSL / Colima 内の Linux Docker Engine を使用してください。'
    server_arch="${info##*|}"
    case "$CFD_PLATFORM:$server_arch" in
        linux/arm64:aarch64|linux/arm64:arm64|linux/amd64:x86_64|linux/amd64:amd64) ;;
        *) fail "ホストと Engine の CPU が一致しません: $CFD_PLATFORM / $server_arch" ;;
    esac
    docker compose version >/dev/null || fail 'Docker Compose プラグインが必要です。'
    docker buildx version >/dev/null || fail 'Docker Buildx プラグインが必要です。'
}
