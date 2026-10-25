import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image

root = Path(sys.argv[1])
render = json.loads((root / "logs/render.json").read_text())
images = sorted((root / "frames").glob("frame-*.png"))
assert len(images) == render["frames"] >= 2
for path in images:
    with Image.open(path) as image:
        assert image.size == (640, 480), (path, image.size)
        pixels = np.asarray(image.convert("RGB"))
        assert np.any(pixels != pixels[0, 0]), path
with Image.open(root / "velocity-ja.png") as image:
    image.verify()
probe = json.loads((root / "logs/ffprobe.json").read_text())
stream, = [s for s in probe["streams"] if s["codec_type"] == "video"]
assert stream["codec_name"] == "h264"
assert int(stream["nb_read_frames"]) == len(images)
assert abs(float(probe["format"]["duration"]) - len(images) / 5) < 0.1
(root / "result.json").write_text(json.dumps({
    "status": "passed", "frames": len(images), "backend": render["backend"],
    "duration": probe["format"]["duration"],
}, indent=2))
