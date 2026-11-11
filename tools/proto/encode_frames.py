"""Publish real Godot captures as 640x360 WebP annotation chunks.

GitHub has a per-job annotation budget as well as a per-step limit. Choose the
highest common WebP quality that fits all frames in 48 chunks, leaving room for
the single joined PROTOLOG annotation and an infrastructure warning. The
quality and chunk count are included in that log rather than another notice.
"""
import base64
import glob
import io
import os
import sys

from PIL import Image

CH = 4000  # Leave room for the PROTOFRAME header below GitHub's 4096 limit.
NP = 8     # The workflow publishes one bucket per step.
MAX_CHUNKS = 48

src_dir = sys.argv[1]
parts_dir = os.path.join(src_dir, "parts")
os.makedirs(parts_dir, exist_ok=True)
paths = sorted(glob.glob(os.path.join(src_dir, "*.png")))
if not paths:
    raise SystemExit("no prototype PNG frames to publish")

images = []
for path in paths:
    with Image.open(path) as source:
        image = source.convert("RGB")
        if image.size != (640, 360):
            image = image.resize((640, 360), Image.Resampling.LANCZOS)
        images.append((os.path.basename(path)[:-4], image))

for quality in range(78, 32, -3):
    encoded = []
    total_chunks = 0
    for name, image in images:
        buf = io.BytesIO()
        image.save(buf, "WEBP", quality=quality, method=6)
        data = buf.getvalue()
        raw = base64.b64encode(data).decode("ascii")
        chunks = [raw[i:i + CH] for i in range(0, len(raw), CH)]
        encoded.append((name, data, chunks))
        total_chunks += len(chunks)
    if total_chunks <= MAX_CHUNKS:
        break
else:
    raise SystemExit("prototype frames exceed the %d-chunk annotation budget" % MAX_CHUNKS)

buckets = [[] for _ in range(NP)]
line_index = 0
for name, data, chunks in encoded:
    with open(os.path.join(src_dir, name + ".webp"), "wb") as output:
        output.write(data)
    for i, chunk in enumerate(chunks):
        buckets[line_index % NP].append(
            "::notice::PROTOFRAME|%s|%d|%d|%s" % (name, i, len(chunks), chunk))
        line_index += 1
    print("encoded %s bytes=%d chunks=%d" % (name, len(data), len(chunks)), file=sys.stderr)
for i, bucket in enumerate(buckets):
    with open(os.path.join(parts_dir, "part_%d.txt" % i), "w", encoding="utf-8") as output:
        output.write("\n".join(bucket) + ("\n" if bucket else ""))
summary = "PROTO encoding quality=%d frames=%d chunks=%d" % (quality, len(encoded), total_chunks)
with open(os.path.join(src_dir, "encoding.txt"), "w", encoding="utf-8") as output:
    output.write(summary)
print(summary, file=sys.stderr)
