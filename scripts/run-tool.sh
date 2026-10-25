#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
[[ $# -gt 0 ]] || fail '使用法: scripts/run-tool.sh <command> [args...]'
require_engine
mkdir -p "$REPO_ROOT/work"
# build / pull は別工程。未作成時は明確なエラーにする。
exec docker compose --project-directory "$REPO_ROOT" \
    --env-file "$REPO_ROOT/versions.env" -f "$REPO_ROOT/compose/compose.yaml" \
    run --rm --no-deps --no-TTY --pull never cfd-tools "$@"
