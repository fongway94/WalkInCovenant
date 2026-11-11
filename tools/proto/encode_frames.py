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
NP = 8     # GitHub accepts only about ten annotations per step, so chunks are
           # spread over NP steps; the workflow prints part_0..part_{NP-1}.

src_dir = sys.argv[1]
parts_dir = os.path.join(src_dir, "parts")
os.makedirs(parts_dir, exist_ok=True)
buckets = [[] for _ in range(NP)]
lines_out = []
for f in sorted(glob.glob(os.path.join(src_dir, "*.png"))):
    name = os.path.basename(f)[:-4]
    out = os.path.join(src_dir, name + ".jpg")
    Image.open(f).convert("RGB").resize((640, 360), Image.LANCZOS).save(
        out, quality=72, optimize=True)
    raw = base64.b64encode(open(out, "rb").read()).decode()
    parts = [raw[i:i + CH] for i in range(0, len(raw), CH)]
    for i, part in enumerate(parts):
        lines_out.append("::notice::PROTOFRAME|%s|%d|%d|%s" % (name, i, len(parts), part))
    print("encoded %s bytes=%d chunks=%d" % (name, len(raw), len(parts)), file=sys.stderr)
for i, line in enumerate(lines_out):
    buckets[i % NP].append(line)
for k, b in enumerate(buckets):
    with open(os.path.join(parts_dir, "part_%d.txt" % k), "w") as fh:
        fh.write("\n".join(b) + ("\n" if b else ""))
print("prepared %d chunk(s) in %d part(s)" % (len(lines_out), NP), file=sys.stderr)
