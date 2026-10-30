#!/usr/bin/env python3
"""api_check.py — verify every Godot engine API this project touches, offline.

WHY: this project is authored in a sandbox that cannot run Godot. A wrong
property name is not a parse error — `astar.diagonal_enabled = false` compiles
fine and then aborts the function at runtime, which left the A* grid dirty and
silently froze every NPC. Finding that cost several CI round-trips of ~70s each.

So instead of guessing, check the engine's own source of truth: the class
reference XML that ships in the Godot repository at the exact version tag in
project.godot. Every `Class.CONSTANT`, every `.new()`, and every member access
on a variable whose type we can see is verified against it, walking the
inheritance chain so inherited members count.

Cached under /tmp/godot-docs, so repeat runs are instant. Needs network only on
a cold cache; CI re-verifies on every push.

Usage:  python3 tools/api_check.py            # exits non-zero on any finding
"""
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CACHE = "/tmp/godot-docs"
REF = None          # git tag, resolved from project.godot below
REPO = "godotengine/godot"

VAR_TYPE = re.compile(
    r"^\s*(?:@onready\s+|@export\s+)*var\s+(\w+)\s*:\s*([A-Z]\w*)")
VAR_INFER = re.compile(r"^\s*var\s+(\w+)\s*:=\s*([A-Z]\w*)\.new\(")
PARAM_TYPE = re.compile(r"func\s+\w+\s*\(([^)]*)\)")
NEW_CALL = re.compile(r"\b([A-Z]\w*)\.new\(")
CLASS_CONST = re.compile(r"\b([A-Z]\w*)\.([A-Z][A-Z0-9_]{2,})\b")
MEMBER = re.compile(r"\b(\w+)\.(\w+)")

# Our own classes and GDScript builtins are not engine classes; skip them.
SKIP_TYPES = set()
GD_BUILTINS = {
    "Array", "Dictionary", "String", "StringName", "NodePath", "Variant",
    "int", "float", "bool", "Vector2", "Vector2i", "Vector3", "Rect2",
    "Rect2i", "Color", "PackedByteArray", "PackedStringArray",
    "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array",
    "PackedFloat64Array", "PackedVector2Array", "PackedVector3Array",
    "PackedColorArray", "Callable", "Signal", "RID", "Transform2D",
}

docs = {}
findings = []
own_classes = set()


def godot_version():
    txt = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    m = re.search(r'config/features=PackedStringArray\("([^"]+)"', txt)
    if m:
        return m.group(1)
    m = re.search(r'config_version=(\d+)', txt)
    return "4.7"


def gh(path):
    """Fetch a file from the Godot repo at our exact version tag.

    Uses the gh CLI when present (authoring sandbox), otherwise curl with
    GITHUB_TOKEN (CI containers, which do not ship gh). Returns None when the
    network is unavailable so the caller can degrade to a warning rather than
    fail a build over a missing lookup.
    """
    import base64
    rel = "repos/%s/contents/%s?ref=%s-stable" % (REPO, path, REF)
    try:
        if subprocess.run(["which", "gh"], capture_output=True).returncode == 0:
            out = subprocess.run(["gh", "api", rel, "--jq", ".content"],
                                 capture_output=True, text=True, timeout=60)
            if out.returncode == 0 and out.stdout.strip():
                return base64.b64decode(out.stdout.strip()).decode("utf-8", "replace")
        token = os.environ.get("GITHUB_TOKEN", "")
        hdr = ["-H", "Accept: application/vnd.github.raw+json"]
        if token:
            hdr += ["-H", "Authorization: Bearer %s" % token]
        url = "https://api.github.com/" + rel
        out = subprocess.run(["curl", "-sfL", "--max-time", "60"] + hdr + [url],
                             capture_output=True, text=True, timeout=90)
        if out.returncode == 0 and out.stdout:
            return out.stdout
    except Exception:
        pass
    return None


def fetch_doc(cls):
    """Class reference for `cls`, or None if the engine has no such class."""
    if cls in docs:
        return docs[cls]
    path = os.path.join(CACHE, cls + ".json")
    if os.path.isfile(path):
        docs[cls] = json.load(open(path, encoding="utf-8"))
        return docs[cls]

    xml = gh("doc/classes/%s.xml" % cls)
    if xml is None:
        docs[cls] = None
        return None
    root = ET.fromstring(xml)
    members = set()
    for tag in ("method", "member", "constant", "signal"):
        for el in root.iter(tag):
            if el.get("name"):
                members.add(el.get("name"))
    doc = {"inherits": root.get("inherits"), "members": sorted(members)}
    docs[cls] = doc
    os.makedirs(CACHE, exist_ok=True)
    json.dump(doc, open(path, "w", encoding="utf-8"))
    return doc


def all_members(cls, depth=0):
    """Members of `cls` plus everything it inherits."""
    if depth > 8:
        return set()
    doc = fetch_doc(cls)
    if not doc:
        return set()
    out = set(doc["members"])
    if doc.get("inherits"):
        out |= all_members(doc["inherits"], depth + 1)
    return out


def add(path, line, rule, msg):
    findings.append((path, line, rule, msg))


def split_funcs(lines):
    """Yield (first_index, last_index_exclusive, func_signature_or_None).

    A segment is either the class body (no signature) or one function. GDScript
    is indentation-scoped, so a column-0 `func` starts a body that ends at the
    next column-0 declaration. Tracking this matters: a parameter named `d` in
    one function must not be assumed to have the same type as a `d` in another,
    which is exactly the false positive this file used to produce.
    """
    segs = []
    cur_start = 0
    cur_sig = None
    for i, line in enumerate(lines):
        if re.match(r"^(func|static func)\s", line):
            if i > cur_start:
                segs.append((cur_start, i, cur_sig))
            cur_start, cur_sig = i, line
        elif re.match(r"^(var|const|signal|enum|class|@|static var)\s*", line) \
                and cur_sig is not None and not line.startswith("\t"):
            segs.append((cur_start, i, cur_sig))
            cur_start, cur_sig = i, None
    segs.append((cur_start, len(lines), cur_sig))
    return segs


def types_in(lines, a, b, sig, global_types, preloads):
    """Visible types for one segment: class members, params, local vars."""
    t = dict(global_types)
    if sig:
        params = sig[sig.index("(") + 1:sig.rindex(")")] if "(" in sig else ""
        for part in params.split(","):
            if ":" in part:
                name, _, ptype = part.partition(":")
                ptype = ptype.strip().split("=", 1)[0].strip()
                if re.fullmatch(r"[A-Z]\w*", ptype):
                    t[name.strip()] = ptype
    for line in lines[a:b]:
        m = VAR_TYPE.match(line)
        if m:
            t[m.group(1)] = m.group(2)
        m = VAR_INFER.match(line)
        if m:
            t[m.group(1)] = m.group(2)
        # a loop variable's type depends on the container; treat as unknown
        m = re.match(r"\s*for\s+(\w+)\s+in\b", line)
        if m:
            t.pop(m.group(1), None)
    for name in preloads:
        t.pop(name, None)
    return t


def scan(path):
    rel = os.path.relpath(path, ROOT)
    src = open(path, encoding="utf-8").read()
    lines = src.split("\n")

    preloads = set(re.findall(r"^const\s+(\w+)\s*=\s*preload\(", src, re.M))
    global_types = {}
    for line in lines:
        if line.startswith("var ") or line.startswith("@onready var ") \
                or line.startswith("@export var "):
            m = VAR_TYPE.match(line)
            if m:
                global_types[m.group(1)] = m.group(2)

    for i, raw in enumerate(lines, 1):
        code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', raw)
        code = code.split("#", 1)[0]
        for cls in NEW_CALL.findall(code):
            if cls in own_classes or cls in SKIP_TYPES or cls in preloads:
                continue
            if fetch_doc(cls) is None:
                add(rel, i, "NO-CLASS", "%s.new() — no such engine class" % cls)
        for cls, const in CLASS_CONST.findall(code):
            if cls in own_classes or cls in SKIP_TYPES or cls in GD_BUILTINS \
                    or cls in preloads:
                continue
            if fetch_doc(cls) is None:
                continue
            if const not in all_members(cls):
                add(rel, i, "NO-CONSTANT",
                    "%s.%s does not exist in Godot %s" % (cls, const, REF))

    for a, b, sig in split_funcs(lines):
        t = types_in(lines, a, b, sig, global_types, preloads)
        for i in range(a, b):
            code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', lines[i])
            code = code.split("#", 1)[0]
            for var, member in MEMBER.findall(code):
                ty = t.get(var)
                # Variant-typed locals hold JSON results; skip them
                if not ty or ty == "Variant" or ty in own_classes \
                        or ty in SKIP_TYPES:
                    continue
                doc = fetch_doc(ty)
                if doc is None:
                    continue
                if member not in all_members(ty):
                    add(rel, i + 1, "NO-MEMBER",
                        "%s is a %s and has no '%s' in Godot %s"
                        % (var, ty, member, REF))


def main():
    global REF, SKIP_TYPES, own_classes
    REF = godot_version()
    SKIP_TYPES = set()
    own_classes = set()
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", ".godot", "build")]
        for f in files:
            if f.endswith(".gd"):
                own_classes |= set(re.findall(
                    r"^class_name\s+(\w+)",
                    open(os.path.join(base, f), encoding="utf-8").read(), re.M))
    print("api_check: verifying against Godot %s class reference" % REF)

    gd = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in
                   (".git", ".godot", "build", "node_modules", "__pycache__")]
        for f in files:
            if f.endswith(".gd"):
                gd.append(os.path.join(base, f))

    for path in sorted(gd):
        scan(path)

    if not any(docs.values()):
        print("api_check: could not reach the Godot class reference "
              "(no network / no token) — skipped, not failed")
        return 0

    if findings:
        seen = set()
        print("api_check: %d finding(s)" % len(findings))
        for path, line, rule, msg in sorted(findings):
            key = (rule, msg)
            if key in seen:
                continue
            seen.add(key)
            print("  %-11s %s:%d  %s" % (rule, path, line, msg))
        return 1
    print("api_check: clean (%d files, %d engine classes verified)"
          % (len(gd), len([c for c in docs.values() if c])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
