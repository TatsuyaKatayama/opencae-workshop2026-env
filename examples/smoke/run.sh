#!/usr/bin/env bash
set -euo pipefail
output="${1:?出力先を指定してください}"
[[ "$output" == /work/smoke-* && -d "$output" ]] || { echo '作成済みの /work/smoke-* を指定してください。' >&2; exit 1; }
cd "$output"
mkdir logs
cp -a /opt/workshop-smoke/case serial
cp -a /opt/workshop-smoke/case parallel
printf '%s\n' "$WM_PROJECT_VERSION" > logs/openfoam-version.txt
[[ "$WM_PROJECT_VERSION" == v2606 ]]
for case in serial parallel; do
    blockMesh -case "$case" > "logs/$case-blockMesh.log" 2>&1
    checkMesh -case "$case" > "logs/$case-checkMesh.log" 2>&1
done
icoFoam -case serial > logs/serial-icoFoam.log 2>&1
decomposePar -case parallel > logs/decomposePar.log 2>&1
mpirun --oversubscribe -np 2 icoFoam -case parallel -parallel > logs/parallel-icoFoam.log 2>&1
reconstructPar -case parallel > logs/reconstructPar.log 2>&1
python /opt/workshop-smoke/postprocess.py "$PWD"
touch serial/cavity.foam
# 描画の成功条件に、実ホストの WSLg や X を利用しないことを含める。
unset DISPLAY WAYLAND_DISPLAY
pvpython --force-offscreen-rendering /opt/workshop-smoke/render.py "$PWD" > logs/paraview.log 2>&1
ffmpeg -nostdin -y -framerate 5 -i frames/frame-%03d.png -c:v libx264 \
    -threads 1 -pix_fmt yuv420p cavity.mp4 > logs/ffmpeg.log 2>&1
ffprobe -v error -count_frames -show_streams -show_format -of json cavity.mp4 > logs/ffprobe.json
python /opt/workshop-smoke/validate.py "$PWD"
cp -a /opt/workshop-manifest manifest
printf '保存データ検証用\n' > persistence.txt
echo '計算・MPI・Python 後処理・描画・動画生成が完了しました。'
