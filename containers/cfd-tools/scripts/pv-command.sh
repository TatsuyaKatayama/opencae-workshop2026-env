#!/bin/sh
set -eu
tool=${0##*/}
case "$tool" in
    pvpython|pvbatch) ;;
    *) echo 'pvpython または pvbatch の名前で起動してください。' >&2; exit 2 ;;
esac
# 公式バイナリの launcher は --mesa で同梱 lib/mesa を優先する。
# ARM64 のソースビルドには launcher / -real がない。
if [ -x "/opt/paraview/bin/$tool-real" ]; then
    exec "/opt/paraview/bin/$tool" --mesa --backend llvmpipe "$@"
fi
exec "/opt/paraview/bin/$tool" "$@"
