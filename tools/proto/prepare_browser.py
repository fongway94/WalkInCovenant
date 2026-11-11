#!/usr/bin/env python3
"""Prepare a *temporary* prototype launcher beside a downloaded Web export.

The ordinary index.html and PCK are not edited. Godot's supported override.cfg
is preloaded only by proto.html, selecting the isolated field scene; two
explicit user arguments select the logical resolution and expose a test-ready
marker. The local launcher disables service-worker installation so the probe
does not affect another browser test's cache. Run after downloading the Web
artifact to build/web, never against a deployed directory.
"""
from pathlib import Path
import sys

web = Path(sys.argv[1] if len(sys.argv) > 1 else "build/web")
source = (web / "index.html").read_text(encoding="utf-8")
needle = "const engine = new Engine(GODOT_CONFIG);"
if source.count(needle) != 1:
    raise SystemExit("unexpected Godot HTML shell; refusing to patch the launcher")
replacement = """// Local CI prototype launcher; index.html remains unchanged.
const protoWidth = new URLSearchParams(location.search).get('width') === '320' ? 320 : 640;
GODOT_CONFIG.args = ['--', '--prototype-browser-probe', '--prototype-width=' + protoWidth];
GODOT_CONFIG.serviceWorker = '';
const engine = new Engine(GODOT_CONFIG);
const startOriginalGame = engine.startGame.bind(engine);
engine.startGame = (...args) => engine.preloadFile('prototype-override.cfg', 'override.cfg')
    .then(() => startOriginalGame(...args));"""
(web / "proto.html").write_text(source.replace(needle, replacement), encoding="utf-8")
(web / "prototype-override.cfg").write_text(
    '[application]\nrun/main_scene="res://scenes/proto/ShepherdFieldProto.tscn"\n',
    encoding="utf-8",
)
print("prepared temporary prototype launcher in", web)
