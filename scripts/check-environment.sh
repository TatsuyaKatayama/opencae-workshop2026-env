#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
printf 'CPU: %s\nDocker CLI: %s\n' "$CFD_PLATFORM" "$(command -v docker || true)"
require_engine
docker version
for command in kirocrew kiro-cli opencode; do
    if command -v "$command" >/dev/null; then
        printf '%s: %s\n' "$command" "$(command -v "$command")"
    else
        printf '%s: 未導入（計算コンテナ単体の検証には不要）\n' "$command"
    fi
done
if ! docker image inspect "$CFD_IMAGE" >/dev/null 2>&1; then
    fail "イメージ未作成: scripts/build-image.sh を実行してください。"
fi
docker image inspect --format 'Image: {{.Id}} / {{.Os}}/{{.Architecture}}' "$CFD_IMAGE"
echo '認証・Crew 接続は別途対話確認が必要です。検証状況は docs/validation.md を参照してください。'
