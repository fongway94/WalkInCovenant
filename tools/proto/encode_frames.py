"""Encode prototype PNG captures as small JPEG annotation chunks for CI.

Each frame is 640x360 JPEG, base64-encoded and split into annotation-sized
chunks: `PROTOFRAME|name|index|count|chunk`. The decoder reassembles them.
"""
import base64
import glob
import os
import sys

from PIL import Image

CH = 4000  # GitHub truncates an annotation at 4096 characters.

src_dir = sys.argv[1]
for f in sorted(glob.glob(os.path.join(src_dir, "*.png"))):
    name = os.path.basename(f)[:-4]
    out = os.path.join(src_dir, name + ".jpg")
    Image.open(f).convert("RGB").resize((640, 360), Image.LANCZOS).save(
        out, quality=72, optimize=True)
    raw = base64.b64encode(open(out, "rb").read()).decode()
    parts = [raw[i:i + CH] for i in range(0, len(raw), CH)]
    for i, part in enumerate(parts):
        print("::notice::PROTOFRAME|%s|%d|%d|%s" % (name, i, len(parts), part))
    print("encoded %s bytes=%d chunks=%d" % (name, len(raw), len(parts)), file=sys.stderr)
