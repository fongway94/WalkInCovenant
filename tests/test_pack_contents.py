#!/usr/bin/env python3
"""Unit tests for the release/test PCK boundary, without requiring Godot."""
from __future__ import annotations

import contextlib
import io
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check_pack_contents import PROBES, paths_in_pack, validate  # noqa: E402

GAME = ["project.binary", "scenes/main/Main.tscn.remap"]
TEST_SCENES = [f"tests/browser/{name}_probe.tscn.remap" for name in PROBES]


def pack(names: list[str], *, magic: bytes = b"GDPC", version: int = 4,
         major: int = 4, minor: int = 7, flags: int = 2) -> bytes:
    """A minimal PCK v4 index; these checks inspect the index, not file data."""
    header = struct.pack("<4s5I2Q", magic, version, major, minor, 2, flags, 0, 40)
    index = bytearray(struct.pack("<I", len(names)))
    for name in names:
        raw = name.encode("utf-8")
        raw += b"\x00" * (-len(raw) % 4)
        index.extend(struct.pack("<I", len(raw)))
        index.extend(raw)
        index.extend(bytes(8 + 8 + 16 + 4))
    return header + index


class PackBoundaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.file = Path(self.temp.name) / "index.pck"

    def write(self, data: bytes) -> Path:
        self.file.write_bytes(data)
        return self.file

    def check(self, names: list[str], mode: str) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            validate(self.write(pack(names)), mode)

    def test_release_has_game_but_no_test_resources(self) -> None:
        self.check(GAME + ["scripts/world/Player.gdc"], "release")
        with self.assertRaisesRegex(ValueError, "test resources"):
            self.check(GAME + ["tests/browser/shepherd_probe.tscn.remap"], "release")
        with self.assertRaisesRegex(ValueError, "missing game resources"):
            self.check(["project.binary"], "release")

    def test_probe_pack_requires_every_browser_scene_and_game(self) -> None:
        self.check(GAME + TEST_SCENES, "probes")
        with self.assertRaisesRegex(ValueError, "lacks probes"):
            self.check(GAME + TEST_SCENES[:-1], "probes")
        with self.assertRaisesRegex(ValueError, "missing game resources"):
            self.check(TEST_SCENES, "probes")

    def test_both_pack_modes_reject_generated_build_outputs(self) -> None:
        for mode, names in (("release", GAME), ("probes", GAME + TEST_SCENES)):
            with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, "generated build output"):
                self.check(names + ["build/web-probes/override.cfg"], mode)

    def test_rejects_unsupported_or_encrypted_indexes(self) -> None:
        for data in (pack(GAME, magic=b"nope"), pack(GAME, version=3),
                     pack(GAME, minor=6), pack(GAME, flags=3)):
            with self.subTest(header=data[:24]), self.assertRaises(ValueError):
                paths_in_pack(self.write(data))

    def test_rejects_truncated_duplicate_or_noncanonical_paths(self) -> None:
        bad = [pack(GAME)[:12], pack(GAME)[:-1], pack(GAME + [GAME[0]])]
        for name in ("res://tests/probe", "/tests/probe", "tests/../probe",
                     "tests//probe", "tests\\probe", "tests/evil\x00name"):
            bad.append(pack(GAME + [name]))
        for data in bad:
            with self.subTest(data=data[-60:]), self.assertRaises(ValueError):
                paths_in_pack(self.write(data))

    def make_release_shell(self) -> Path:
        source = Path(self.temp.name) / "release"
        source.mkdir()
        (source / "index.pck").write_bytes(pack(GAME))
        (source / "index.html").write_text("const engine = new Engine(GODOT_CONFIG);", encoding="utf-8")
        (source / "index.js").write_text("// shell", encoding="utf-8")
        (source / "index.wasm").write_bytes(b"shell")
        return source

    def test_probe_builder_never_accepts_a_stale_pack_after_an_empty_export(self) -> None:
        source = self.make_release_shell()
        out = Path(self.temp.name) / "probes"
        out.mkdir()
        stale = pack(GAME + TEST_SCENES)
        (out / "index.pck").write_bytes(stale)
        fake_godot = Path(self.temp.name) / "godot"
        fake_godot.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fake_godot.chmod(0o755)
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/build_browser_probes.py"),
             "--source", str(source), "--output", str(out), "--godot", str(fake_godot)],
            cwd=self.temp.name, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("browser probe build: FAIL", result.stderr)
        self.assertEqual((out / "index.pck").read_bytes(), stale)
        self.assertFalse((out / "shepherd-probe.html").exists())

    def test_probe_builder_installs_only_the_new_validated_pack(self) -> None:
        source = self.make_release_shell()
        out = Path(self.temp.name) / "probes"
        out.mkdir()
        (out / "index.pck").write_bytes(pack(GAME + TEST_SCENES))
        fresh = pack(GAME + TEST_SCENES + ["scripts/world/Player.gdc"])
        payload = Path(self.temp.name) / "fresh.pck"
        payload.write_bytes(fresh)
        fake_godot = Path(self.temp.name) / "godot"
        fake_godot.write_text(f"#!/bin/sh\nfor last do :; done\ncp '{payload}' \"$last\"\n", encoding="utf-8")
        fake_godot.chmod(0o755)
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/build_browser_probes.py"),
             "--source", str(source), "--output", str(out), "--godot", str(fake_godot)],
            cwd=self.temp.name, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((out / "index.pck").read_bytes(), fresh)
        self.assertEqual((source / "index.pck").read_bytes(), pack(GAME))
        self.assertTrue((out / "shepherd-probe.html").is_file())

    def test_probe_tools_reject_release_directory_before_writing(self) -> None:
        release = ROOT / "build/web"
        child = release / Path(self.temp.name).name
        self.assertFalse(child.exists(), "test expects a fresh output path")
        for command in (
            [sys.executable, str(ROOT / "tools/build_browser_probes.py"),
             "--source", self.temp.name, "--output", str(child)],
            [sys.executable, str(ROOT / "tools/prepare_browser_probes.py"), str(child)],
        ):
            result = subprocess.run(command, cwd=self.temp.name, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertFalse(child.exists(), "guard must run before creating output")


if __name__ == "__main__":
    unittest.main()
