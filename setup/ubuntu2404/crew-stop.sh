#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
[[ $# == 0 ]] || die '使用法: crew-stop.sh'
platform
load_config
user_bus
exec 9>"$STATE/crew.lock"
flock -w 30 9 || die 'Crew の起動・停止が実行中です。'
if ! systemctl --user is-active --quiet "$UNIT.service"; then
    note 'Crew は停止しています。'
    exit 0
fi
timeout 45 systemctl --user stop "$UNIT.service" || die 'Crew の停止に失敗しました。サービス状態を確認してください。'
systemctl --user is-active --quiet "$UNIT.service" && die 'Crew の停止を確認できませんでした。'
note 'Crew を停止しました。'
