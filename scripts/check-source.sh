#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
while IFS= read -r file; do bash -n "$file"; done < <(find "$root/scripts" "$root/containers" "$root/examples" "$root/setup" -name '*.sh' -type f)
python3 -m compileall -q "$root/examples" "$root/tests" "$root/setup/ubuntu2404"
python3 -m unittest discover -s "$root/tests" -v
source "$root/scripts/lib/common.sh"
compose config --format json | python3 -c '
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
service = json.load(sys.stdin)["services"]["cfd-tools"]
assert pathlib.Path(service["build"]["context"]) == root
assert pathlib.Path(service["volumes"][0]["source"]) == root / "work"
assert service["platform"] in ("linux/arm64", "linux/amd64")
' "$root"
