#!/usr/bin/env bash
set -euo pipefail
[[ $# == 3 && $EUID != 0 ]] || exit 1
source_dir="$1"; destination="$2"; identity="$3"
[[ "$destination" == "$HOME/opencae-workshop2026-env" && "$identity" == "$(cat /etc/opencae-environment-id)" ]] || exit 1
if [[ -e "$destination" ]]; then
    [[ -f "$destination/.opencae-staged-id" && "$(cat "$destination/.opencae-staged-id")" == "$identity" ]] && exit 0
    echo 'Project destination already exists' >&2; exit 1
fi
staging="$(mktemp -d "$HOME/.opencae-stage-XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
tar -C "$source_dir" --exclude=.git --exclude=work --exclude=.aws --exclude=.codex --exclude=.agents \
    --exclude=.venv --exclude=.env --exclude='.env.*' --exclude=__pycache__ -cf - . |
    tar -C "$staging" --no-same-owner -xf -
[[ -f "$staging/setup/ubuntu2404/setup.sh" && -f "$staging/PROJECT_SPEC.md" ]] || exit 1
chmod +x "$staging"/scripts/*.sh "$staging"/examples/smoke/run.sh "$staging"/setup/ubuntu2404/*.sh
printf '%s\n' "$identity" > "$staging/.opencae-staged-id"
mv -- "$staging" "$destination"
