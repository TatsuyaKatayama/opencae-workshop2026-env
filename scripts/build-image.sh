#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
[[ "${BUILD_JOBS:-2}" =~ ^[1-9][0-9]*$ ]] || fail 'BUILD_JOBS は正の整数で指定してください。'
require_engine
mkdir -p "$REPO_ROOT/work"
result="$(mktemp -d "$REPO_ROOT/work/build-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
cp "$REPO_ROOT/versions.env" "$result/versions.env"
cp "$REPO_ROOT/containers/cfd-tools/requirements.lock" "$result/requirements.lock"
git -C "$REPO_ROOT" rev-parse --verify HEAD > "$result/git-revision.txt" 2>/dev/null || echo uncommitted > "$result/git-revision.txt"
git -C "$REPO_ROOT" status --porcelain > "$result/git-status.txt" 2>/dev/null || echo unavailable-zip > "$result/git-status.txt"
docker version > "$result/docker-version.txt"
start=$SECONDS
status=0
compose --progress plain build "$@" cfd-tools 2>&1 | tee "$result/build.log" || status=$?
printf 'exit_code=%s\nelapsed_seconds=%s\nbuild_jobs=%s\nplatform=%s\n' "$status" "$((SECONDS-start))" "${BUILD_JOBS:-2}" "$CFD_PLATFORM" > "$result/build-result.env"
if (( status == 0 )); then
    docker image inspect "$CFD_IMAGE" > "$result/image-inspect.json"
    compose run --rm --no-deps -T --pull never cfd-tools cat /opt/workshop-manifest/packages.tsv > "$result/packages.tsv"
fi
echo "構築記録: $result"
exit "$status"
