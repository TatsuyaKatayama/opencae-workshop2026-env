#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
(( HOST_UID != 0 )) || fail 'MPI と成果物の所有権を確認するため、通常ユーザーで実行してください。'
require_engine
mkdir -p "$REPO_ROOT/work"
result="$(mktemp -d "$REPO_ROOT/work/smoke-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
container_result="/work/${result##*/}"
cp "$REPO_ROOT/versions.env" "$result/versions.env"
git -C "$REPO_ROOT" rev-parse --verify HEAD > "$result/git-revision.txt" 2>/dev/null || echo uncommitted > "$result/git-revision.txt"
git -C "$REPO_ROOT" status --porcelain > "$result/git-status.txt"
docker image inspect "$CFD_IMAGE" > "$result/image-inspect.json"
echo "検証結果の保存先: $result"
"$REPO_ROOT/scripts/run-tool.sh" bash /opt/workshop-smoke/run.sh "$container_result" 2>&1 | tee "$result/smoke.log"
# 別の一時コンテナから確認し、再作成後の永続化とホスト所有権を検証する。
"$REPO_ROOT/scripts/run-tool.sh" test -s "$container_result/persistence.txt"
[[ -O "$result/cavity.mp4" && -w "$result/cavity.mp4" ]] || fail '成果物の所有権がホストユーザーと一致しません。'
cat "$result/result.json"
echo
