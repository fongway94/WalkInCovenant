#!/usr/bin/env python3
"""inject_pwa.py — make sure a Godot web export is actually installable/offline.

Godot 4.7 has NATIVE PWA export. With `progressive_web_app/enabled=true` it
writes `<name>.service.worker.js` and `<name>.manifest.json` next to index.html
and wires the registration into the loader itself. That is the mechanism this
project uses — the engine knows every file the loader fetches, which is exactly
the list an offline cache has to get right.

So this script no longer assumes it must inject anything. It VERIFIES:

  1. native mode  — the engine's service worker + manifest exist and index.html
                    registers them. Nothing is written; a second service worker
                    on the same scope would replace the engine's and break it.
  2. fallback     — if the native artifacts are absent (preset disabled, older
                    engine), copy web/sw.js + web/manifest.webmanifest in,
                    stamp the cache version from the git sha, and inject the
                    manifest link and registration into index.html.

Either way it exits non-zero if the result cannot work offline, so CI fails
instead of publishing a build that silently loses the one property that
replaces Covenant's single-file offline html.

Usage:  python3 tools/inject_pwa.py build/web
"""
import os
import re
import shutil
import subprocess
import sys

BUILD = sys.argv[1] if len(sys.argv) > 1 else "build/web"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
WEB = os.path.join(ROOT, "web")


def sha():
    try:
        return subprocess.check_output(
            ["git", "-C", ROOT, "rev-parse", "--short", "HEAD"],
            stderr=subprocess.DEVNULL).decode().strip() or "dev"
    except Exception:
        return "dev"


def fail(msg):
    print("inject_pwa: FAIL — %s" % msg)
    return 1


def verify_native(html, files):
    """The engine's own PWA artifacts. Returns (ok, description)."""
    sw = [f for f in files if f.endswith(".service.worker.js")]
    mf = [f for f in files if f.endswith(".manifest.json")]
    if not sw or not mf:
        return False, "native service worker/manifest not found"
    sw_name, mf_name = sw[0], mf[0]
    problems = []
    if sw_name not in html:
        problems.append("index.html does not reference %s" % sw_name)
    if mf_name not in html:
        problems.append("index.html does not reference %s" % mf_name)
    if "serviceWorker" not in html:
        problems.append("index.html registers no service worker")
    if problems:
        return False, "; ".join(problems)
    return True, "native PWA verified (%s + %s)" % (sw_name, mf_name)


def inject_fallback(html_path, html, files):
    """Only used when the engine did not emit PWA artifacts."""
    version = sha()
    os.makedirs(os.path.join(BUILD, "icons"), exist_ok=True)
    for f in ("sw.js", "manifest.webmanifest"):
        src = os.path.join(WEB, f)
        if os.path.isfile(src):
            shutil.copy(src, os.path.join(BUILD, f))
    icons = os.path.join(WEB, "icons")
    if os.path.isdir(icons):
        for f in os.listdir(icons):
            shutil.copy(os.path.join(icons, f), os.path.join(BUILD, "icons", f))

    sw = os.path.join(BUILD, "sw.js")
    if os.path.isfile(sw):
        src = open(sw, encoding="utf-8").read()
        src = re.sub(r'const CACHE = "[^"]+"',
                     'const CACHE = "walkincovenant-%s"' % version, src)
        open(sw, "w", encoding="utf-8").write(src)

    block = (
        '<link rel="manifest" href="./manifest.webmanifest">\n'
        '<meta name="theme-color" content="#14202a">\n'
        '<script>\n'
        "if ('serviceWorker' in navigator) {\n"
        "  window.addEventListener('load', function () {\n"
        "    navigator.serviceWorker.register('./sw.js').catch(function (e) {\n"
        "      console.warn('SW registration failed:', e);\n"
        "    });\n"
        "  });\n"
        "}\n"
        "</script>\n"
    )
    if "manifest.webmanifest" not in html:
        html = html.replace("</head>", block + "</head>", 1) if "</head>" in html \
            else block + html
        open(html_path, "w", encoding="utf-8").write(html)

    ok = ("manifest.webmanifest" in html and "serviceWorker" in html
          and os.path.isfile(sw)
          and ("walkincovenant-%s" % version) in open(sw, encoding="utf-8").read())
    return ok, "fallback PWA injected (cache stamped %s)" % version


def main():
    html_path = os.path.join(BUILD, "index.html")
    if not os.path.isfile(html_path):
        return fail("no index.html in %s — did the export run?" % BUILD)

    html = open(html_path, encoding="utf-8").read()
    files = os.listdir(BUILD)

    ok, msg = verify_native(html, files)
    if ok:
        print("inject_pwa: OK — %s" % msg)
        return 0

    print("inject_pwa: native PWA incomplete (%s) — using fallback" % msg)
    ok, msg = inject_fallback(html_path, html, files)
    if not ok:
        return fail(msg)
    print("inject_pwa: OK — %s" % msg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
