#!/usr/bin/env bash
set -e
export HOME="${HOME:-/tmp/opencae-home}"
mkdir -p "$HOME"
# CI 等の任意 UID に名前を与え、MPI がユーザー情報を取得できるようにする。
if ! getent passwd "$(id -u)" >/dev/null; then
    cp /etc/passwd "$HOME/passwd"
    cp /etc/group "$HOME/group"
    printf 'workshop:x:%s:%s:Workshop:%s:/bin/bash\n' "$(id -u)" "$(id -g)" "$HOME" >> "$HOME/passwd"
    if ! getent group "$(id -g)" >/dev/null; then
        printf 'workshop:x:%s:\n' "$(id -g)" >> "$HOME/group"
    fi
    export NSS_WRAPPER_PASSWD="$HOME/passwd" NSS_WRAPPER_GROUP="$HOME/group"
    export LD_PRELOAD="$(find /usr/lib -name libnss_wrapper.so -print -quit)${LD_PRELOAD:+:$LD_PRELOAD}"
fi
# OpenFOAM のスクリプトは未定義変数を参照するため nounset は使わない。
# 引数なしの関数内で読む。直接 source すると実行コマンドの $@ を
# OpenFOAM が設定引数として解釈してしまう。
load_openfoam_environment() {
    source /usr/lib/openfoam/openfoam2606/etc/bashrc
}
set +e
load_openfoam_environment
status=$?
set -e
if (( status != 0 )) || [[ "${WM_PROJECT_VERSION:-}" != v2606 ]]; then
    echo 'OpenFOAM v2606 の環境設定に失敗しました。' >&2
    exit 1
fi
export PATH="/opt/post-venv/bin:$PATH"
exec "$@"
