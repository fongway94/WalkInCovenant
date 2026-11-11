"""Reassemble PROTOFRAME annotations from a run's proto-frames job.

usage: decode_proto.py <run-id> [outdir]
"""
import base64
import collections
import json
import os
import subprocess
import sys

REPO = "fongway94/WalkInCovenant"


def gh(*args):
    return subprocess.run(["gh", *args], capture_output=True, text=True, check=True).stdout


run_id = sys.argv[1]
outdir = sys.argv[2] if len(sys.argv) > 2 else "build/proto_frames"
os.makedirs(outdir, exist_ok=True)
jobs = json.loads(gh("api", "repos/%s/actions/runs/%s/jobs?per_page=100" % (REPO, run_id)))["jobs"]
job = next(j for j in jobs if j["name"] == "proto-frames")
check_url = job["check_run_url"]
anns = json.loads(gh("api", check_url.replace("https://api.github.com/", "") + "/annotations?per_page=100"))
parts = collections.defaultdict(dict)
counts = {}
for a in anns:
    msg = a.get("message", "")
    if not msg.startswith("PROTOFRAME|"):
        continue
    _, name, idx, cnt, chunk = msg.split("|", 4)
    parts[name][int(idx)] = chunk
    counts[name] = int(cnt)
if not parts:
    raise SystemExit("no PROTOFRAME annotations found")
incomplete = False
for name, chunks in sorted(parts.items()):
    missing = [i for i in range(counts[name]) if i not in chunks]
    if missing:
        print("%s: missing chunks %s" % (name, missing))
        incomplete = True
        continue
    data = base64.b64decode("".join(chunks[i] for i in range(counts[name])))
    path = os.path.join(outdir, name + ".webp")
    open(path, "wb").write(data)
    print("wrote %s (%d bytes)" % (path, len(data)))

if incomplete:
    raise SystemExit("incomplete prototype frame annotations")
