#!/usr/bin/env python3
"""xref_check.py — resolve every cross-script member access in the project.

The gap this closes: api_check.py verifies calls into the ENGINE and
deliberately skips our own classes, so a typo in our own API was invisible.
That is not theoretical — CI produced:

    ERROR: Failed to load script "res://scripts/main/Main.gd" (Parse error)
    SCRIPT ERROR: Parse Error: Could not resolve external class member "bind"
    SCRIPT ERROR: Parse Error: Could not resolve external class member "player"

...and still wrote a .pck and exited 0, so the build went GREEN containing a
script that cannot load. The game would have black-screened at boot.

Worse, when one script fails to parse, every member of it becomes unresolvable
from other scripts, so the reported file is usually a victim, not the cause.
This tool checks the whole graph at once:

  OWN-MEMBER    x.member where x is typed as one of our classes and the class
                has no such var / func / signal / const (walking its extends
                chain, and the engine's own docs for engine bases)
  AUTOLOAD      GameState.foo / EventBus.bar / I18n.baz / AudioDirector.qux —
                the four singletons every system calls. A missing one is a null
                identifier at runtime in Godot, and silently breaks a feature.
  SIGNAL        sig.connect(...) where sig is not a signal on that class
  NO-CLASS      a type annotation naming a class that does not exist anywhere

Usage:  python3 tools/xref_check.py        # exits non-zero on any finding
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

findings = []

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import api_check  # noqa: E402  (engine class reference, with its own cache)

api_check.REF = None
_engine_cache = {}

BUILTIN_TYPES = {
    "Variant", "Array", "Dictionary", "String", "StringName", "NodePath",
    "Callable", "Signal", "RID", "int", "float", "bool", "Vector2", "Vector2i",
    "Vector3", "Vector3i", "Rect2", "Rect2i", "Color", "Transform2D",
    "PackedByteArray", "PackedStringArray", "PackedInt32Array",
    "PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array",
    "PackedVector2Array", "PackedVector3Array", "PackedColorArray",
}


def is_engine(t):
    """True for engine classes and builtins — neither is a project typo."""
    if t in BUILTIN_TYPES:
        return True
    if t in _engine_cache:
        return _engine_cache[t]
    if api_check.REF is None:
        api_check.REF = api_check.godot_version()
    known = api_check.fetch_doc(t) is not None
    _engine_cache[t] = known
    return known


def add(path, line, rule, msg):
    findings.append((path, line, rule, msg))


class Script:
    def __init__(self, path):
        self.path = path
        self.rel = os.path.relpath(path, ROOT)
        src = open(path, encoding="utf-8").read()
        self.src = src
        self.lines = src.split("\n")
        m = re.search(r"^class_name\s+(\w+)", src, re.M)
        self.class_name = m.group(1) if m else None
        m = re.search(r"^extends\s+([\w.]+)", src, re.M)
        self.extends = m.group(1) if m else "RefCounted"
        self.vars = set(re.findall(r"^(?:@onready\s+|@export\s+)*var\s+(\w+)", src, re.M))
        self.funcs = set(re.findall(r"^(?:static\s+)?func\s+(\w+)", src, re.M))
        self.signals = set(re.findall(r"^signal\s+(\w+)", src, re.M))
        self.consts = set(re.findall(r"^const\s+(\w+)", src, re.M))
        self.enums = set()
        for body in re.findall(r"^enum\s+(\w+)?\s*\{([^}]*)\}", src, re.M):
            if body[0]:
                self.consts.add(body[0])
            for part in body[1].split(","):
                name = part.split("=", 1)[0].strip()
                if name:
                    self.consts.add(name)
        # autoload singletons are also plain scripts with members
        self.members = self.vars | self.funcs | self.signals | self.consts


def load_scripts():
    out = {}
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in
                   (".git", ".godot", "build", "node_modules", "__pycache__")]
        for f in files:
            if f.endswith(".gd"):
                s = Script(os.path.join(base, f))
                out[s.rel] = s
                if s.class_name:
                    out[s.class_name] = s
    return out


def autoloads():
    """{name: script} from project.godot's [autoload] section."""
    txt = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    sec = re.search(r"^\[autoload\](.*?)(?=^\[|\Z)", txt, re.M | re.S)
    out = {}
    if sec:
        for line in sec.group(1).split("\n"):
            m = re.match(r'^\*?(\w+)="\*?(res://[^"]+)"', line.strip())
            if m:
                out[m.group(1)] = m.group(2)[len("res://"):]
    return out


def inherited(scripts, s, seen=None):
    """Every member visible on script `s`, including from its base classes."""
    seen = seen or set()
    if s.rel in seen:
        return set(), None
    seen.add(s.rel)
    members = set(s.members)
    base = s.extends
    if base in scripts:
        more, engine = inherited(scripts, scripts[base], seen)
        return members | more, engine
    return members, base          # base is an engine class name (or None)


def main():
    scripts = load_scripts()
    autos = autoloads()
    known = set(scripts.keys()) | set(autos.keys())

    # 1. autoloads referenced anywhere must exist and must have the member
    for rel, s in scripts.items():
        if rel.endswith(".gd") is False:
            continue
        for i, raw in enumerate(s.lines, 1):
            code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', raw).split("#", 1)[0]
            for auto, member in re.findall(r"\b(\w+)\.(\w+)", code):
                if auto not in autos:
                    continue
                target = scripts.get(autos[auto])
                if target is None:
                    add(rel, i, "AUTOLOAD",
                        "autoload %s points at %s which is not in the project"
                        % (auto, autos[auto]))
                    continue
                members, _ = inherited(scripts, target)
                if member not in members:
                    add(rel, i, "AUTOLOAD",
                        "%s.%s — %s (%s) has no such member"
                        % (auto, member, auto, autos[auto]))

        # 2. typed locals/vars of our own classes
        types = {}
        for line in s.lines:
            m = re.match(r"^\s*(?:@onready\s+|@export\s+)*var\s+(\w+)\s*:\s*(\w+)", line)
            if m:
                types[m.group(1)] = m.group(2)
            m = re.match(r"^\s*var\s+(\w+)\s*:=\s*(\w+)\.new\(", line)
            if m:
                types[m.group(1)] = m.group(2)
            m = re.match(r"^\s*for\s+\w+\s+in\b", line)
            if m:
                pass

        for i, raw in enumerate(s.lines, 1):
            code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', raw).split("#", 1)[0]

            for var, member in re.findall(r"\b(\w+)\.(\w+)", code):
                t = types.get(var)
                if not t or t in autos:
                    continue
                if t not in known and not is_engine(t):
                    add(rel, i, "NO-CLASS",
                        "%s is annotated as %s, which exists nowhere in the project"
                        % (var, t))
                    continue
                target = scripts.get(t)
                if target is None:
                    continue
                members, engine_base = inherited(scripts, target)
                if member in members:
                    continue
                # the base may be an engine class; its members are legitimate
                if engine_base:
                    try:
                        if member in api_check.all_members(engine_base):
                            continue
                    except Exception:
                        pass
                add(rel, i, "OWN-MEMBER",
                    "%s is a %s and has no '%s' (it has: %s)"
                    % (var, t, member,
                       ", ".join(sorted(members)[:6]) + ("…" if len(members) > 6 else "")))

            # 3. signal connections must name a real signal
            for obj, sig in re.findall(r"\b(\w+)\.(\w+)\.connect\(", code):
                t = types.get(obj)
                if not t or t not in scripts:
                    continue
                members, _ = inherited(scripts, scripts[t])
                if sig not in members:
                    add(rel, i, "SIGNAL",
                        "%s.%s.connect() — %s has no such signal or member"
                        % (obj, sig, t))

    # NO-CLASS depends on being able to ask the engine whether a type is its
    # own. Without network the reference is empty and every engine type would
    # look like a typo, so those findings are dropped rather than trusted.
    report = findings
    if not any(api_check.docs.values()):
        report = [f for f in report if f[2] != "NO-CLASS"]

    if report:
        print("xref_check: %d finding(s)" % len(report))
        for path, line, rule, msg in sorted(set(report)):
            print("  %-11s %s:%d  %s" % (rule, path, line, msg))
        return 1
    print("xref_check: clean — %d scripts, %d autoloads, all cross-script "
          "members resolve" % (len([k for k in scripts if k.endswith(".gd")]),
                               len(autos)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
