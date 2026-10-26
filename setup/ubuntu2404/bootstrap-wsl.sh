#!/usr/bin/env bash
# Setup.ps1 が専用の新規 WSL 環境で root として呼び出す。
set -euo pipefail
[[ $EUID == 0 && $# == 2 ]] || { echo 'root / user / environment-id required' >&2; exit 1; }
user="$1"; identity="$2"
[[ "$user" =~ ^[a-z][a-z0-9_-]{0,30}$ && "$user" != root && "$identity" =~ ^[a-f0-9-]{36}$ ]] || exit 1
source /etc/os-release
[[ "$ID:$VERSION_ID" == ubuntu:24.04 ]] || exit 1
marker=/etc/opencae-environment-id
if [[ -f "$marker" && "$(cat "$marker")" != "$identity" ]]; then
    echo 'Environment identity mismatch' >&2; exit 1
fi
printf '%s\n' "$identity" > "$marker"
chmod 644 "$marker"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y sudo python3
if ! id "$user" >/dev/null 2>&1; then useradd --create-home --shell /bin/bash "$user"; fi
usermod -aG sudo "$user"
if [[ "$(passwd -S "$user" | awk '{print $2}')" != P ]]; then
    echo "Set the Linux sudo password for $user (input is hidden)."
    passwd "$user"
fi
python3 - "$user" <<'PY'
import configparser, pathlib, sys
p=pathlib.Path('/etc/wsl.conf')
c=configparser.ConfigParser()
c.read(p)
for section in ('boot','user'):
    if not c.has_section(section): c.add_section(section)
c['boot']['systemd']='true'
c['user']['default']=sys.argv[1]
with p.open('w') as f: c.write(f)
PY
