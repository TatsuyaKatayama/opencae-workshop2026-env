"""pvpython 専用。システムの後処理用 venv には依存しない。"""
import json
import sys
from pathlib import Path
from paraview.simple import (
    OpenFOAMReader, GetActiveViewOrCreate, Show, ColorBy, Render, SaveScreenshot,
)

root = Path(sys.argv[1])
frames = root / "frames"
frames.mkdir()
reader = OpenFOAMReader(FileName=str(root / "serial/cavity.foam"))
reader.MeshRegions = ["internalMesh"]
reader.CellArrays = ["U", "p"]
reader.UpdatePipelineInformation()
times = [float(t) for t in reader.TimestepValues if t > 0]
assert len(times) >= 2, times
view = GetActiveViewOrCreate("RenderView")
view.ViewSize = [640, 480]
view.OrientationAxesVisibility = 0
view.CameraParallelProjection = 1
view.CameraPosition = [0.05, 0.05, 1]
view.CameraFocalPoint = [0.05, 0.05, 0.005]
view.CameraViewUp = [0, 1, 0]
view.CameraParallelScale = 0.065
view.Background = [1, 1, 1]
display = Show(reader, view)
ColorBy(display, ("CELLS", "U", "Magnitude"))
for i, time in enumerate(times):
    reader.UpdatePipeline(time)
    view.ViewTime = time
    display.RescaleTransferFunctionToDataRange(False, True)
    Render(view)
    SaveScreenshot(str(frames / f"frame-{i:03d}.png"), view)
window = view.GetClientSideObject().GetRenderWindow()
backend = window.GetClassName()
assert "OSOpenGL" in backend, backend
(root / "logs/render.json").write_text(json.dumps({
    "backend": backend, "frames": len(times), "times": times,
    "capabilities": window.ReportCapabilities(),
}, indent=2))
