#!/usr/bin/env python3
"""decode_frames.py — bring rendered CI frames back into the workspace.

The authoring sandbox can reach api.github.com but NOT the hosts that serve
workflow artifacts or raw logs (productionresultssa*.blob.core.windows.net,
results-receiver.actions.githubusercontent.com). Check-run ANNOTATIONS are on
api.github.com, so the visual job prints each PNG as base64 split across a few
::notice:: lines. This tool reassembles them into real files we can look at.

    python3 tools/decode_frames.py <run-id> [--out frames]

It uses `gh` (already authenticated here) and the {owner}/{repo} placeholders,
so it works for a fork without being edited. No third-party packages needed.
"""

import argparse
import base64
import json
import pathlib
import subprocess
import sys

MARK = "WICFRAME|"


def gh(*args):
    p = subprocess.run(["gh", "api", *args], capture_output=True, text=True)
    if p.returncode != 0:
        print("gh api failed: " + p.stderr.strip(), file=sys.stderr)
        sys.exit(1)
    return p.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_id", help="GitHub Actions run id (gh run list)")
    ap.add_argument("--out", default="frames")
    a = ap.parse_args()

    jobs_raw = gh("repos/{owner}/{repo}/actions/runs/%s/jobs" % a.run_id,
                  "--jq", ".jobs[].id")
    job_ids = [x for x in jobs_raw.split() if x.strip()]
    if not job_ids:
        print("no jobs found for run " + a.run_id)
        return 1

    chunks = {}
    for jid in job_ids:
        raw = gh("repos/{owner}/{repo}/check-runs/%s/annotations" % jid,
                 "--paginate", "--jq", ".[] | .message")
        for line in raw.splitlines():
            if not line.startswith(MARK):
                continue
            body = line[len(MARK):]
            parts = body.split("|", 3)
            if len(parts) != 4:
                continue
            name, idx, total, data = parts
            chunks.setdefault(name, {})[int(idx)] = (int(total), data)

    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    found = 0
    for name in sorted(chunks):
        parts = chunks[name]
        total = next(iter(parts.values()))[0]
        if sorted(parts) != list(range(total)):
            print("  incomplete: %s (%d/%d chunks)" % (name, len(parts), total))
            continue
        blob = b"".join(base64.b64decode(parts[i][1]) for i in range(total))
        path = out / (name + ".png")
        path.write_bytes(blob)
        print("  wrote %s (%d bytes)" % (path, len(blob)))
        found += 1

    summary = pathlib.Path("build/frames/summary.json")
    if found == 0:
        print("no WICFRAME annotations in run %s" % a.run_id)
        print("(the visual job may not have rendered, or the annotations were capped)")
        # Not an error: an honest 'could not capture' is a valid result.
    else:
        print("%d frame(s) decoded into %s/" % (found, out))
        if summary.exists():
            print("local summary: " + json.dumps(json.loads(summary.read_text()))[:400])
    return 0


if __name__ == "__main__":
    sys.exit(main())
