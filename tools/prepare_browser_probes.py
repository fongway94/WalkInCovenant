#!/usr/bin/env python3
"""Create temporary, same-origin test launchers beside a Web export.

The shipped index and PCK are not changed. Each launcher preloads a Godot
`override.cfg` selecting a test-only scene, and disables the service worker so
it cannot disturb the ordinary game's cache. Run on the test-only copy made by
`tools/build_browser_probes.py`, never in a published directory.
"""
from pathlib import Path
import sys

from check_pack_contents import validate


ROOT = Path(__file__).resolve().parent.parent

PROBES = {
    "setpiece": "setpiece",
    "shepherd": "shepherd",
    "world": "world",
    "shepherd-resume": "shepherd_resume",
    "journey-slots": "journey_slots",
}


def main() -> None:
    web = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "build/web-probes"
    release = (ROOT / "build/web").resolve()
    if web == release or release in web.parents:
        raise SystemExit("refusing to add test launchers in the release output build/web")
    try:
        validate(web / "index.pck", "probes")
    except (OSError, ValueError) as exc:
        raise SystemExit(f"not a test-only browser pack: {exc}") from exc
    source = (web / "index.html").read_text(encoding="utf-8")
    needle = "const engine = new Engine(GODOT_CONFIG);"
    if source.count(needle) != 1:
        raise SystemExit("unexpected Godot HTML shell; refusing to patch launchers")
    for label, scene in PROBES.items():
        override = f"{label}-override.cfg"
        replacement = f"""// Local test launcher; the shipped index.html is unchanged.
GODOT_CONFIG.serviceWorker = '';
const engine = new Engine(GODOT_CONFIG);
const startOriginalGame = engine.startGame.bind(engine);
engine.startGame = (...args) => engine.preloadFile('{override}', 'override.cfg')
    .then(() => startOriginalGame(...args));"""
        (web / f"{label}-probe.html").write_text(
            source.replace(needle, replacement), encoding="utf-8")
        (web / override).write_text(
            f'[application]\nrun/main_scene="res://tests/browser/{scene}_probe.tscn"\n',
            encoding="utf-8")
    print(f"prepared {len(PROBES)} temporary test launchers in {web}")


if __name__ == "__main__":
    main()
