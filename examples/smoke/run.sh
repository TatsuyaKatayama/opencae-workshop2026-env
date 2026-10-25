#!/usr/bin/env bash
set -euo pipefail
output="${1:?出力先を指定してください}"
[[ "$output" == /work/smoke-* && -d "$output" ]] || { echo '作成済みの /work/smoke-* を指定してください。' >&2; exit 1; }
cd "$output"
mkdir logs
# リダイレクト先のエラーも Actions の画面に残し、元の終了コードを保つ。
run_logged() {
    local log="$1" status
    shift
    if "$@" > "$log" 2>&1; then
        return 0
    else
        status=$?
        printf '失敗したコマンド: %s (終了コード %s)\nログ: %s\n' "$1" "$status" "$log" >&2
        tail -n 80 "$log" >&2
        return "$status"
    fi
}
cp -a /opt/workshop-smoke/case serial
cp -a /opt/workshop-smoke/case parallel
printf '%s\n' "$WM_PROJECT_VERSION" > logs/openfoam-version.txt
[[ "$WM_PROJECT_VERSION" == v2606 ]]
for case in serial parallel; do
    run_logged "logs/$case-blockMesh.log" blockMesh -case "$case"
    run_logged "logs/$case-checkMesh.log" checkMesh -case "$case"
done
run_logged logs/serial-icoFoam.log icoFoam -case serial
run_logged logs/decomposePar.log decomposePar -case parallel
run_logged logs/parallel-icoFoam.log mpirun --oversubscribe -np 2 icoFoam -case parallel -parallel
run_logged logs/reconstructPar.log reconstructPar -case parallel
python /opt/workshop-smoke/postprocess.py "$PWD"
touch serial/cavity.foam
# 描画の成功条件に、実ホストの WSLg や X を利用しないことを含める。
unset DISPLAY WAYLAND_DISPLAY
run_logged logs/paraview.log pvpython --force-offscreen-rendering /opt/workshop-smoke/render.py "$PWD"
run_logged logs/ffmpeg.log ffmpeg -nostdin -y -framerate 5 -i frames/frame-%03d.png -c:v libx264 \
    -threads 1 -pix_fmt yuv420p cavity.mp4
ffprobe -v error -count_frames -show_streams -show_format -of json cavity.mp4 > logs/ffprobe.json
python /opt/workshop-smoke/validate.py "$PWD"
cp -a /opt/workshop-manifest manifest
printf '保存データ検証用\n' > persistence.txt
echo '計算・MPI・Python 後処理・描画・動画生成が完了しました。'
