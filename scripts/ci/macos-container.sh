#!/usr/bin/env bash
# CI-only boundary test. Full CFD is independently tested on native Linux CPUs.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
[[ "$(uname -s):$(uname -m)" == Darwin:arm64 ]]
require_engine
directory="$(mktemp -d "$REPO_ROOT/work-ci-macos-XXXXXX")"
trap 'rm -rf -- "$directory"' EXIT
export CI_MOUNT="$directory" CI_UBUNTU="$UBUNTU_IMAGE"
printf 'host 日本語\n' > "$directory/input.txt"
cat > "$directory/compose.yaml" <<'YAML'
services:
  boundary:
    image: ${CI_UBUNTU}
    platform: linux/arm64
    user: ${HOST_UID}:${HOST_GID}
    network_mode: none
    volumes:
      - ${CI_MOUNT}:/work
    working_dir: /work
    entrypoint: [bash, -eu, -c]
YAML
boundary() { docker compose -p opencae-ci-boundary -f "$directory/compose.yaml" "$@"; }
boundary pull
boundary run --rm boundary '
  source /etc/os-release
  test "$ID:$VERSION_ID" = ubuntu:24.04
  test "$(uname -m)" = aarch64
  test "$(cat input.txt)" = "host 日本語"
  test "$1" = "space 日本語"
  printf "container 日本語\n" > output.txt
' _ 'space 日本語'
[[ "$(cat "$directory/output.txt")" == 'container 日本語' ]]
[[ "$(stat -f %u "$directory/output.txt")" == "$HOST_UID" ]]
# A second container must see persisted data, and Compose must retain exit status.
status=0
boundary run --rm boundary 'test "$(cat output.txt)" = "container 日本語"; exit 42' || status=$?
[[ "$status" == 42 ]]
[[ -z "$(boundary ps -aq)" ]]
echo 'PASS: Mac Docker context, Ubuntu ARM64, Compose, Unicode arguments, bidirectional persistence, UID and exit status.'
