#!/usr/bin/env python3
"""decode_browser_frames.py — bring CI browser screenshots and logs back here.

The ``browser`` CI job opens the exported game in Chromium and writes PNGs plus
a structured ``log.json``. This sandbox cannot reach the hosts that serve
Actions artifacts (productionresultssa*.blob.core.windows.net) or the Pages
site, but check-run annotations live on api.github.com. The job therefore
prints each PNG and the log as base64 ``::notice::`` lines; this tool puts them
back together.

    python3 tools/decode_browser_frames.py <run-id> [--out browser-frames]

Only stdlib and an authenticated ``gh`` are required. A separate marker from
WICFRAME keeps the two transports independent.
"""

import argparse
import base64
import json
import pathlib
import subprocess
import sys

PNG = "WICBROWSER|"
LOG = "WICBROWSERLOG|"
TEXT = "WICBROWSERTEXT|"


def gh(*args):
    p = subprocess.run(["gh", "api", *args], capture_output=True, text=True)
    if p.returncode != 0:
        print("gh api failed: " + p.stderr.strip(), file=sys.stderr)
        sys.exit(1)
    return p.stdout


def collect(run_id):
    raw = gh("repos/{owner}/{repo}/actions/runs/%s/jobs" % run_id,
             "--jq", ".jobs[].id")
    job_ids = [x for x in raw.split() if x.strip()]
    images, logs, texts = {}, {}, []
    for jid in job_ids:
        out = gh("repos/{owner}/{repo}/check-runs/%s/annotations" % jid,
                 "--paginate", "--jq", ".[] | .message")
        for line in out.splitlines():
            if line.startswith(PNG):
                name, idx, total, data = line[len(PNG):].split("|", 3)
                images.setdefault(name, {})[int(idx)] = (int(total), data)
            elif line.startswith(LOG):
                idx, total, data = line[len(LOG):].split("|", 2)
                logs[int(idx)] = (int(total), data)
            elif line.startswith(TEXT):
                texts.append(line[len(TEXT):])
    return images, logs, texts


def join(parts):
    total = next(iter(parts.values()))[0]
    if sorted(parts) != list(range(total)):
        return None, total, len(parts)
    return b"".join(base64.b64decode(parts[i][1]) for i in range(total)), total, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_id", help="GitHub Actions run id")
    ap.add_argument("--out", default="browser-frames")
    a = ap.parse_args()
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    images, logs, texts = collect(a.run_id)

    found = 0
    for name in sorted(images):
        blob, total, got = join(images[name])
        if blob is None:
            print("  incomplete: %s (%d/%d chunks)" % (name, got, total))
            continue
        (out / (name + ".png")).write_bytes(blob)
        print("  wrote %s.png (%d bytes)" % (name, len(blob)))
        found += 1

    if logs:
        blob, total, got = join(logs)
        if blob is None:
            print("  incomplete log (%d/%d chunks)" % (got, total))
        else:
            (out / "log.json").write_bytes(blob)
            print("  wrote log.json (%d bytes)" % len(blob))
            try:
                d = json.loads(blob)
                s = d.get("summary", {})
                print("  chromium: %s  checks=%s failed=%s consoleErrors=%s pageErrors=%s" %
                      (d.get("chromium"), s.get("checks"), s.get("failedChecks"),
                       s.get("consoleErrors"), s.get("pageErrors")))
                for c in d.get("checks", []):
                    if not c.get("ok"):
                        print("    FAILED %s — %s" % (c.get("name"), c.get("detail")))
                for t in d.get("notes", []):
                    print("    NOTE %s" % t)
            except Exception as e:
                print("  (could not summarise log: %s)" % e)
    for t in texts:
        print("  " + t)

    if found == 0:
        print("no WICBROWSER annotations in run %s" % a.run_id)
    else:
        print("%d browser screenshot(s) decoded into %s/" % (found, out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
