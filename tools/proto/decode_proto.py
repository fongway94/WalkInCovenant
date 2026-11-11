"""Reassemble PROTOFRAME annotations from the prototype render/publisher jobs.

usage: decode_proto.py <run-id> [outdir] [--browser]

With --browser, only the separate real-Web prototype screenshots are read;
the default remains the Xvfb prototype and its overflow publisher.
"""
import argparse
import base64
import collections
import json
import os
import subprocess

REPO = "fongway94/WalkInCovenant"


def gh(*args):
    return subprocess.run(["gh", *args], capture_output=True, text=True, check=True).stdout


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("run_id")
parser.add_argument("outdir", nargs="?", default="build/proto_frames")
parser.add_argument("--browser", action="store_true", help="decode the separate prototype Web browser job")
args = parser.parse_args()
run_id, outdir = args.run_id, args.outdir
os.makedirs(outdir, exist_ok=True)
jobs = json.loads(gh("api", "repos/%s/actions/runs/%s/jobs?per_page=100" % (REPO, run_id)))["jobs"]
names = ("proto-browser",) if args.browser else ("proto-frames", "proto-frame-overflow")
required = names[0]
publishers = [j for j in jobs if j["name"] in names]
if not any(j["name"] == required for j in publishers):
    raise SystemExit("%s job not found" % required)
parts = collections.defaultdict(dict)
counts = {}
for job in publishers:
    if job["status"] != "completed":
        raise SystemExit("%s is not complete yet" % job["name"])
    check_url = job["check_run_url"]
    anns = json.loads(gh("api", check_url.replace("https://api.github.com/", "") + "/annotations?per_page=100"))
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
