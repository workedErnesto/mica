#!/usr/bin/env python3
"""Package the 512px PNG staging images produced by macos/scripts/app-icons.swift.

Requires Pillow and macOS iconutil. The 24 source PNGs remain outside the repository.
"""
import pathlib
import subprocess
import sys
import tempfile

from PIL import Image

root = pathlib.Path(__file__).resolve().parent.parent
staging = pathlib.Path(sys.argv[1])
windows = root / "shared/icons/app"
images = sorted(staging.glob("*.png"))
if len(images) != 24 or not (staging / "base-original.png").is_file():
    raise SystemExit("Expected all 24 staged PNG icons")

for path in images:
    image = Image.open(path).convert("RGBA")
    if image.size != (512, 512):
        raise SystemExit(f"Unexpected size: {path}")
    image.resize((256, 256), Image.Resampling.LANCZOS).save(windows / path.name, optimize=True)
    image.save(windows / (path.stem + ".ico"), format="ICO", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

original = Image.open(staging / "base-original.png").convert("RGBA")
original.save(root / "shared/icons/mica-512.png", optimize=True)
original.save(root / "shared/icons/mica.ico", format="ICO", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
with tempfile.TemporaryDirectory() as tmp:
    iconset = pathlib.Path(tmp) / "mica.iconset"
    iconset.mkdir()
    for logical in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = logical * scale
            target = iconset / f"icon_{logical}x{logical}{'@2x' if scale == 2 else ''}.png"
            original.resize((pixels, pixels), Image.Resampling.LANCZOS).save(target, optimize=True)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(root / "macos/Resources/App/mica.icns")], check=True)
