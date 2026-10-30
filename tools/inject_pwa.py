#!/usr/bin/env python3
"""inject_pwa.py — finish a Godot web export into an installable offline PWA.

Godot generates index.html; it knows nothing about service workers or
manifests. This script is the seam:

  1. copies web/sw.js + web/manifest.webmanifest + web/icons into the build dir
  2. stamps the cache-busting version (git sha) into sw.js
  3. injects <link rel=manifest> + the SW registration <script> into index.html
  4. verifies the injection actually landed, so CI fails loudly instead of
     shipping a build that silently cannot go offline

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


def main():
    if not os.path.isfile(os.path.join(BUILD, "index.html")):
        print("inject_pwa: no index.html in %s — did the export run?" % BUILD)
        return 1

    version = sha()

    # 1. copy the PWA shell
    os.makedirs(os.path.join(BUILD, "icons"), exist_ok=True)
    for f in ("sw.js", "manifest.webmanifest"):
        shutil.copy(os.path.join(WEB, f), os.path.join(BUILD, f))
    icons = os.path.join(WEB, "icons")
    if os.path.isdir(icons):
        for f in os.listdir(icons):
            shutil.copy(os.path.join(icons, f), os.path.join(BUILD, "icons", f))

    # 2. stamp the cache version so a deploy can never serve a stale .pck
    sw = os.path.join(BUILD, "sw.js")
    src = open(sw, encoding="utf-8").read()
    src = re.sub(r'const CACHE = "[^"]+"', 'const CACHE = "walkincovenant-%s"' % version, src)
    open(sw, "w", encoding="utf-8").write(src)

    # 3. inject manifest + registration into the generated index.html
    html_path = os.path.join(BUILD, "index.html")
    html = open(html_path, encoding="utf-8").read()
    inject = (
        '<link rel="manifest" href="./manifest.webmanifest">\n'
        '<meta name="theme-color" content="#14202a">\n'
        '<script>\n'
        "if ('serviceWorker' in navigator) {\n"
        "  window.addEventListener('load', function () {\n"
        "    navigator.serviceWorker.register('./sw.js').catch(function (e) {\n"
        "      console.warn('SW registration failed (offline play unavailable):', e);\n"
        "    });\n"
        "  });\n"
        "}\n"
        "</script>\n"
    )
    if "manifest.webmanifest" not in html:
        if "</head>" in html:
            html = html.replace("</head>", inject + "</head>", 1)
        else:
            html = inject + html
        open(html_path, "w", encoding="utf-8").write(html)

    # 4. verify
    html = open(html_path, encoding="utf-8").read()
    ok = ("manifest.webmanifest" in html
          and "serviceWorker" in html
          and os.path.isfile(sw)
          and ("walkincovenant-%s" % version) in open(sw, encoding="utf-8").read())
    print("inject_pwa: version=%s %s" % (version, "OK" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
