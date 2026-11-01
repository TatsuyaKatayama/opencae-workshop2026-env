"""pvpython 専用。DISPLAY と GPU を使わず OSMesa 描画を確認する。"""
import json
import sys
from pathlib import Path
from paraview.simple import Sphere, GetActiveViewOrCreate, Show, Render, SaveScreenshot

output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
view = GetActiveViewOrCreate('RenderView')
view.ViewSize = [320, 240]
Show(Sphere(), view)
Render(view)
window = view.GetClientSideObject().GetRenderWindow()
assert window.GetClassName() == 'vtkOSOpenGLRenderWindow', window.GetClassName()
SaveScreenshot(str(output / 'sphere.png'), view)
assert (output / 'sphere.png').stat().st_size > 1000
(output / 'render.json').write_text(json.dumps({
    'backend': window.GetClassName(), 'capabilities': window.ReportCapabilities(),
}, indent=2))
print('CPU headless OSMesa rendering passed')
