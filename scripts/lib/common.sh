#!/usr/bin/env bash
# 呼び出し元は set -euo pipefail を有効にする。
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
set -a
source "$REPO_ROOT/versions.env"
set +a
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
    command -v docker >/dev/null || fail 'WSL Ubuntu 内に Docker Engine / CLI を導入してください。'
    local binary endpoint info server_arch
    binary="$(command -v docker)"
    [[ "$binary" != /mnt/* && "$binary" != *docker.exe ]] || fail 'WSL 内の Linux 版 Docker CLI を使用してください。'
    endpoint="${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}"
    [[ "$endpoint" == unix:///var/run/docker.sock ]] || fail "接続先が標準構成ではありません: $endpoint。docs/windows.md を確認してください。"
    info="$(docker info --format '{{.OperatingSystem}}|{{.OSType}}|{{.Architecture}}')" || fail 'WSL 内の Docker Engine へ接続できません。サービスとグループ反映を確認してください。'
    [[ "${info,,}" != *desktop* && "$info" == *'|linux|'* ]] || fail 'WSL 内の Linux Docker Engine を使用してください。'
    server_arch="${info##*|}"
    case "$CFD_PLATFORM:$server_arch" in
        linux/arm64:aarch64|linux/arm64:arm64|linux/amd64:x86_64|linux/amd64:amd64) ;;
        *) fail "ホストと Engine の CPU が一致しません: $CFD_PLATFORM / $server_arch" ;;
    esac
    docker compose version >/dev/null || fail 'Docker Compose プラグインが必要です。'
    docker buildx version >/dev/null || fail 'Docker Buildx プラグインが必要です。'
}
