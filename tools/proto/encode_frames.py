"""Publish real Godot captures as 640x360 WebP annotation chunks.

The wider field contains much more detail: packing all five frames into one
job's ~50-annotation limit forced quality down to 48. Use two jobs instead,
each with at most 46 frame chunks and eight publish steps, retaining room for
the single joined PROTOLOG and runner warnings. Captures remain ordinary WebP;
the decoder simply collects chunks from both check runs.
"""
import base64
import glob
import io
import os
import sys

from PIL import Image

CH = 4000  # Leave room for the PROTOFRAME header below GitHub's 4096 limit.
NP = 8
MAX_PER_JOB = 46
JOBS = 2

src_dir = sys.argv[1]
part_dirs = [os.path.join(src_dir, "parts"), os.path.join(src_dir, "overflow")]
for directory in part_dirs:
    os.makedirs(directory, exist_ok=True)
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
    if total_chunks <= MAX_PER_JOB * JOBS:
        break
else:
    raise SystemExit("prototype frames exceed the two-job annotation budget")

buckets = [[[] for _ in range(NP)] for _ in range(JOBS)]
line_index = 0
for name, data, chunks in encoded:
    with open(os.path.join(src_dir, name + ".webp"), "wb") as output:
        output.write(data)
    for i, chunk in enumerate(chunks):
        group = line_index // MAX_PER_JOB
        bucket = (line_index % MAX_PER_JOB) % NP
        buckets[group][bucket].append(
            "::notice::PROTOFRAME|%s|%d|%d|%s" % (name, i, len(chunks), chunk))
        line_index += 1
    print("encoded %s bytes=%d chunks=%d" % (name, len(data), len(chunks)), file=sys.stderr)
for group, directory in enumerate(part_dirs):
    for i, bucket in enumerate(buckets[group]):
        with open(os.path.join(directory, "part_%d.txt" % i), "w", encoding="utf-8") as output:
            output.write("\n".join(bucket) + ("\n" if bucket else ""))
summary = "PROTO encoding quality=%d frames=%d chunks=%d primary=%d overflow=%d" % (
    quality, len(encoded), total_chunks, min(total_chunks, MAX_PER_JOB),
    max(0, total_chunks - MAX_PER_JOB))
with open(os.path.join(src_dir, "encoding.txt"), "w", encoding="utf-8") as output:
    output.write(summary)
print(summary, file=sys.stderr)
