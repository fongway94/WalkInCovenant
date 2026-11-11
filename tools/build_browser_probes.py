#!/usr/bin/env python3
"""Create a disposable Web export with browser-test scenes, never a release.

First import the project and export/inject the ordinary Web build to build/web.
This copies its shell to a separate directory, replaces only that copy's PCK
with the `Web Test Only` pack, and creates test launchers with no service
worker. The normal Web artifact and its saved-game entry point are untouched.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from check_pack_contents import validate


ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "build/web")
    parser.add_argument("--output", type=Path, default=ROOT / "build/web-probes")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    args = parser.parse_args()
    source, out = args.source.resolve(), args.output.resolve()
    release = (ROOT / "build/web").resolve()
    if out == release or release in out.parents:
        parser.error("probe output must not be the release directory or inside it")
    if source == out or source in out.parents or out in source.parents:
        parser.error("source and output must be separate directories")
    try:
        validate(source / "index.pck", "release")
        for name in ("index.html", "index.js", "index.wasm"):
            if not (source / name).is_file():
                raise ValueError(f"missing Web shell file: {source / name}")
        out.mkdir(parents=True, exist_ok=True)
        for item in source.glob("index.*"):
            if item.is_file() and item.name != "index.pck":
                shutil.copy2(item, out / item.name)
        # A previous output may already exist. Export into a unique empty
        # directory so an exit-0 Godot failure cannot accidentally validate a
        # stale PCK and report a successful rebuild.
        with tempfile.TemporaryDirectory(prefix=".pck-build-", dir=out) as temp:
            fresh_pack = Path(temp) / "index.pck"
            command = [args.godot, "--headless", "--path", str(ROOT), "--export-pack",
                       "Web Test Only", str(fresh_pack)]
            result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, check=False)
            if result.returncode or any(s in result.stdout for s in
                                        ("SCRIPT ERROR", "Parse Error", "Failed to load script")):
                print(result.stdout, file=sys.stderr)
                raise ValueError(f"test pack export failed (exit {result.returncode})")
            validate(fresh_pack, "probes")
            os.replace(fresh_pack, out / "index.pck")
        subprocess.run([sys.executable, str(ROOT / "tools/prepare_browser_probes.py"), str(out)],
                       cwd=ROOT, check=True)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"browser probe build: FAIL: {exc}", file=sys.stderr)
        return 1
    print(f"browser probe build: test-only copy ready in {out}; do not publish it")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
