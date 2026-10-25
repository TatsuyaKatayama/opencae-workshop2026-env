#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
[[ $# == 0 || ( $# == 1 && "$1" == --status ) ]] || die '使用法: crew-start.sh [--status]'
platform
load_config
user_bus
exec 9>"$STATE/crew.lock"
flock -w 30 9 || die 'Crew の起動・停止が実行中です。'
if [[ "${1:-}" == --status ]]; then
    systemctl --user is-active --quiet "$UNIT.service" || exit 3
    curl --noproxy '*' --fail --silent --max-time 5 -o /dev/null "http://127.0.0.1:$PORT/" || exit 3
    note 'Crew は起動中です。'
    exit 0
fi
authenticated || die '先に Kiro CLI Login（kiro-login.sh）を実行してください。'
source "$SETUP_ROOT/scripts/lib/common.sh"
require_engine
if ! systemctl --user is-active --quiet "$UNIT.service"; then
    python3 - "$PORT" <<'PY'
import socket, sys
with socket.socket() as s:
    try:
        s.bind(('127.0.0.1', int(sys.argv[1])))
    except OSError:
        sys.exit('ERROR: Crew のポートは別プロセスが使用中です。')
PY
    command -v kirocrew >/dev/null || die 'Crew が見つかりません。'
    mkdir -p "$STATE/logs"
    touch "$STATE/logs/crew.log"
    chmod 600 "$STATE/logs/crew.log"
    systemctl --user reset-failed "$UNIT.service" >/dev/null 2>&1 || true
    env_args=()
    for name in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
        [[ -v "$name" ]] && env_args+=("--setenv=$name=${!name}")
    done
    systemd-run --user --unit="$UNIT" --collect --property=UMask=0077 \
        "--property=WorkingDirectory=$PROJECT" \
        "--property=StandardOutput=append:$STATE/logs/crew.log" \
        "--property=StandardError=append:$STATE/logs/crew.log" \
        "--setenv=PATH=$PATH" "${env_args[@]}" \
        "$(command -v kirocrew)" gateway --no-open --no-tunnel --port "$PORT" >&2
fi
ready=0
for (( attempt=0; attempt<60; attempt++ )); do
    systemctl --user is-active --quiet "$UNIT.service" || die "Crew が終了しました。本人用ログ: $STATE/logs/crew.log"
    if curl --noproxy '*' --fail --silent --max-time 2 -o /dev/null "http://127.0.0.1:$PORT/"; then ready=1; break; fi
    sleep 1
done
(( ready )) || die "Crew の起動待ちがタイムアウトしました。Stop 後に再試行してください。本人用ログ: $STATE/logs/crew.log"
note 'Crew は起動中です。次のアクセス URL をブラウザーで開いてください（共有禁止）。'
# アクセス URL は stdout のみに出す。ログへの tee はしない。
kirocrew token | python3 -c '
import re,sys
from urllib.parse import urlsplit
port=int(sys.argv[1])
for url in re.findall(r"https?://[^\s\x1b]+",sys.stdin.read()):
    u=urlsplit(url)
    if u.hostname in ("localhost","127.0.0.1","::1") and u.port==port:
        print(url); break
else:
    sys.exit("ERROR: Crew のアクセス URL を取得できません。kirocrew token を確認してください。")
' "$PORT"
