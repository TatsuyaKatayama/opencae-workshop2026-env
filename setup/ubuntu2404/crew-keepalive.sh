#!/usr/bin/env bash
# Windows の wsl.exe 呼び出しを、対象 Crew の稼働中だけ維持する。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
[[ $# == 0 ]] || die '使用法: crew-keepalive.sh'
platform
load_config
user_bus
exec 8>"$STATE/crew-lifetime.lock"
# 停止・再起動と重なった古い監視プロセスからの引き継ぎを少し待つ。
flock -w 3 8 || exit 0
# 起動・停止用の crew.lock は保持しない。HTTP の一時的な不調では終了しない。
while systemctl --user is-active --quiet "$UNIT.service"; do
    sleep 1
done
