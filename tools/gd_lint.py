#!/usr/bin/env python3
"""gd_lint.py — catch the GDScript mistakes that only a real engine would catch.

This project is authored in a sandbox that cannot run Godot (release binaries
live on a host outside its network). Every syntax bug therefore costs a full CI
round-trip — minutes per iteration — to discover. This script closes most of
that loop locally, in milliseconds, by flagging constructs that are *valid
looking* but invalid or version-fragile GDScript.

Each rule exists because it actually broke a build here:

  INFER-TYPE   `var x := Dictionary = {}`      — cannot combine := with a type
  INT-LOOP     `for i in list.size():`         — GDScript cannot iterate an int
  IS-NOT       `if x is not Dictionary:`       — prefer `not (x is Dictionary)`
  MISSING-RES  preload/load of a res:// path that does not exist
  DUP-CLASS    two files declaring the same class_name
  DUP-FUNC     the same func defined twice in one file
  SIGNAL-HANDLER  connect("sig", _on_sig) with no _on_sig in the file
  MIXED-INDENT tabs and spaces in the same file's indentation

Usage:  python3 tools/gd_lint.py            # exits non-zero on any finding
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

INT_LOOP_EXPR = re.compile(
    r"^\s*for\s+\w+\s+in\s+(?!range\(|\[)(.*?):\s*$")
INT_LOOP_TAIL = re.compile(r"(\.size\(\)|\.length\(\)|\.count\(\)|\b\d+\s*)$")
INT_NAMES = re.compile(
    r"^(width|height|rows|cols|count|num_|n_|TILE|PIPS|HEARTS|BAR_H|"
    r"DEADZONE|FULL|total|len)$")

findings = []


def add(path, line, rule, msg):
    findings.append((path, line, rule, msg))


def scan(path):
    rel = os.path.relpath(path, ROOT)
    src = open(path, encoding="utf-8").read()
    lines = src.split("\n")

    classes = re.findall(r"^class_name\s+(\w+)", src, re.M)
    funcs = re.findall(r"^func\s+(\w+)", src, re.M)
    seen = set()
    for i, f in enumerate(funcs, 1):
        if f in seen:
            add(rel, i, "DUP-FUNC", "func %s defined twice" % f)
        seen.add(f)

    for i, line in enumerate(lines, 1):
        if re.search(r"(var|const)\s+\w+\s*:=\s*[A-Z]\w*\s*=", line):
            add(rel, i, "INFER-TYPE",
                "cannot combine := with an explicit type: %s" % line.strip())

        m = INT_LOOP_EXPR.match(line)
        if m:
            expr = m.group(1).strip()
            if INT_LOOP_TAIL.search(expr) or INT_NAMES.match(expr):
                add(rel, i, "INT-LOOP",
                    "GDScript cannot iterate an int; use range(%s): %s"
                    % (expr, line.strip()))

        # Strip string literals and comments first: "it is not your hand" in a
        # verse and "# this is not a check" are prose, not operators.
        code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
        code = re.sub(r"'(?:[^'\\]|\\.)*'", "''", code)
        code = code.split("#", 1)[0]

        if re.search(r"\bis\s+not\b", code):
            add(rel, i, "IS-NOT",
                "prefer not (x is T) — `is not` support varies by version")

        # Constructor traps that parse fine and fail at runtime. All three were
        # found by CI in this project, not by reading.
        if re.search(r"(?<!Packed)(?<!\w)String\(", code) and "StringName(" not in code:
            add(rel, i, "STR-CTOR",
                "String(x) is not a valid constructor for a Variant; use str(x)")

        m = re.search(r"Packed(?:String|Byte|Int32|Float32|Int64|Float64|Vector2|"
                      r"Vector3|Color)Array\(([^)]+)\)", code)
        if m and "Packed" not in m.group(1):
            add(rel, i, "PACKED-CTOR",
                "packed arrays have no (Array) constructor; build with append(): %s"
                % line.strip())

        m = re.search(r"Vector2i?\(([^)]*\[\d\][^)]*)\)", code)
        if m and "int(" not in m.group(1) and "float(" not in m.group(1):
            add(rel, i, "JSON-INT",
                "JSON numbers arrive as floats; wrap in int()/float(): %s"
                % line.strip())

        if re.match(r"^\t* +\t|^\t+ +", line):
            add(rel, i, "MIXED-INDENT", "tabs and spaces mixed in indentation")

        for res in re.findall(r'(?:preload|load)\("(res://[^"]+)"\)', line):
            local = os.path.join(ROOT, res[len("res://"):])
            if not os.path.exists(local):
                add(rel, i, "MISSING-RES", "%s does not exist" % res)

        for sig, handler in re.findall(
                r'connect\("([^"]+)"\s*,\s*(?:Callable\(\s*self\s*,\s*)?"?(_?\w+)"?\s*\)',
                line):
            if handler.startswith("_on_") and handler not in seen and \
                    ("func %s" % handler) not in src:
                add(rel, i, "SIGNAL-HANDLER",
                    'connect("%s", %s) but %s is not defined in this file'
                    % (sig, handler, handler))

    return classes


def main():
    all_classes = {}
    gd_files = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in
                   (".git", ".godot", "build", "node_modules", "__pycache__")]
        for f in files:
            if f.endswith(".gd"):
                gd_files.append(os.path.join(base, f))

    for path in sorted(gd_files):
        for cls in scan(path):
            all_classes.setdefault(cls, []).append(os.path.relpath(path, ROOT))

    for cls, paths in all_classes.items():
        if len(paths) > 1:
            add(paths[0], 0, "DUP-CLASS",
                "class_name %s declared in %s" % (cls, ", ".join(paths)))

    if findings:
        print("gd_lint: %d finding(s) across %d files" % (len(findings), len(gd_files)))
        for path, line, rule, msg in sorted(findings):
            print("  %-14s %s:%d  %s" % (rule, path, line, msg))
        return 1
    print("gd_lint: clean (%d files, %d class_names)" % (len(gd_files), len(all_classes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
