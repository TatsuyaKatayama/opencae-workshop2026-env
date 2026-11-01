#!/bin/bash
set -uo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
action="${1:-}"
case "$action" in
    setup) bash "$MAC_ROOT/setup/macos/setup.sh"; status=$? ;;
    backend)
        printf 'Backend: 1=Kiro CLI / 2=Codex / 3=OpenCode [1]: '
        IFS= read -r choice
        case "$choice" in
            ''|1) backend=kiro ;; 2) backend=codex ;; 3) backend=opencode ;;
            *) echo '1 / 2 / 3 を入力してください。'; exit 1 ;;
        esac
        bash "$MAC_ROOT/setup/macos/start-backend.sh" --backend "$backend" --open-browser; status=$? ;;
    start) bash "$MAC_ROOT/setup/macos/crew-start.sh" --open-browser; status=$? ;;
    stop) bash "$MAC_ROOT/setup/macos/crew-stop.sh"; status=$? ;;
    *) exit 2 ;;
esac
printf '\n終了コード: %s。Enter で閉じます。' "$status"
IFS= read -r _ || true
exit "$status"
