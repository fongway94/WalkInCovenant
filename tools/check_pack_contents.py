#!/usr/bin/env python3
"""Check a Godot 4.7 PCK's logical directory without extracting it.

Release exports must not ship save-seeding browser probes or test fixtures.
The separate test-only pack must contain those scenes. Neither pack may contain
logical paths from generated build output. This reads the PCK v4 index, not a
byte search through compressed assets; fail closed if the format changes or
the directory is malformed.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import struct
import sys


PROBES = ("setpiece", "shepherd", "shepherd_resume", "world", "journey_slots")


def paths_in_pack(path: Path) -> set[str]:
    size = path.stat().st_size
    with path.open("rb") as f:
        header = f.read(40)
        if len(header) != 40:
            raise ValueError("truncated PCK header")
        magic, version, major, minor, patch, flags, _base, directory = struct.unpack(
            "<4s5I2Q", header
        )
        if magic != b"GDPC" or version != 4:
            raise ValueError(f"unsupported PCK header: {magic!r}, format {version}")
        if (major, minor) != (4, 7) or flags & 1:
            raise ValueError(f"unexpected engine version or encrypted index: {major}.{minor}.{patch}, flags={flags}")
        if directory < 40 or directory >= size:
            raise ValueError("invalid PCK directory offset")
        f.seek(directory)

        def read_exact(n: int) -> bytes:
            b = f.read(n)
            if len(b) != n:
                raise ValueError("truncated PCK directory")
            return b

        count = struct.unpack("<I", read_exact(4))[0]
        if count > 100_000:
            raise ValueError("implausible PCK entry count")
        names: set[str] = set()
        for _ in range(count):
            length = struct.unpack("<I", read_exact(4))[0]
            if not 0 < length <= 16_384:
                raise ValueError("invalid PCK path length")
            name = read_exact(length).rstrip(b"\x00").decode("utf-8")
            read_exact(8 + 8 + 16 + 4)  # offset, size, MD5, file flags
            # Godot stores paths relative to res://. Refuse non-canonical
            # names rather than allowing a malformed path to bypass tests/.
            if (not name or name.startswith("/") or "\\" in name or "\x00" in name
                    or any(part in ("", ".", "..") for part in name.split("/"))
                    or ":" in name):
                raise ValueError(f"invalid PCK path: {name!r}")
            if name in names:
                raise ValueError(f"duplicate PCK path: {name}")
            names.add(name)
        return names


def validate(path: Path, mode: str) -> None:
    names = paths_in_pack(path)
    needed = {"project.binary", "scenes/main/Main.tscn.remap"}
    missing = needed - names
    if missing:
        raise ValueError("missing game resources: " + ", ".join(sorted(missing)))
    generated = sorted(n for n in names if n.startswith("build/"))
    if generated:
        raise ValueError("generated build output in pack: " + ", ".join(generated[:8]))
    if mode == "release":
        leaked = sorted(n for n in names if n.startswith("tests/"))
        if leaked:
            raise ValueError("test resources in release pack: " + ", ".join(leaked[:8]))
    elif mode == "probes":
        required = {f"tests/browser/{name}_probe.tscn.remap" for name in PROBES}
        missing = required - names
        if missing:
            raise ValueError("test-only pack lacks probes: " + ", ".join(sorted(missing)))
    else:
        raise ValueError(f"unknown pack mode: {mode}")
    print(f"pack check: {mode} OK ({len(names)} indexed resources, {path})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("release", "probes"))
    parser.add_argument("pack", type=Path)
    args = parser.parse_args()
    try:
        validate(args.pack, args.mode)
    except (OSError, UnicodeError, ValueError, struct.error) as exc:
        print(f"pack check: FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
