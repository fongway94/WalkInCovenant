#!/usr/bin/env python3
"""check_export.py — catch export configuration errors before the exporter does.

Godot's export validator can refuse a preset WITHOUT SAYING WHY. Concretely, in
4.7.2 `EditorExportPlatformWeb::has_valid_project_configuration` sets
`valid = false` when a preset asks for mobile VRAM compression but the project
has not enabled ETC2/ASTC import — and it never writes anything into `r_error`.
CI therefore printed:

    ERROR: Cannot export project with preset "Web" due to configuration errors:

...with nothing after the colon. Cost: several CI round-trips to find a
one-line project setting.

This script encodes the rules the engine checks but does not explain, plus the
ones it does not check at all:

  VRAM-MOBILE     for_mobile=true needs rendering/.../import_etc2_astc=true
  VRAM-DESKTOP    for_desktop=true needs rendering/.../import_s3tc_bptc=true
  THREADS-PAGES   thread_support=true cannot work on GitHub Pages (no COOP/COEP)
  UNKNOWN-OPTION  an option key the engine does not have (silently ignored, so a
                  typo means the setting you meant never applied)
  MISSING-FILE    PWA icons / custom HTML shell paths that do not exist
  BAD-PATH        export_path outside the repo, or wrong extension for platform
  CSHARP-WEB      C# cannot export to Web at all
  MISSING-SCENE   main scene or an autoload path that does not exist
  DUP-PRESET      two presets with the same name
  SCREEN          the display chain: stretch mode/aspect/scale_mode, landscape
                  lock, canvas resize policy and PWA orientation all have to
                  agree with each other, or the picture letterboxes on a phone

The Web option list below is transcribed from
platform/web/export/export_plugin.cpp at tag 4.7.2-stable — not from memory.

Usage:  python3 tools/check_export.py        # exits non-zero on any finding
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Verbatim from platform/web/export/export_plugin.cpp @ 4.7.2-stable,
# EditorExportPlatformWeb::get_export_options().
WEB_OPTIONS = {
    "custom_template/debug", "custom_template/release",
    "variant/extensions_support", "variant/thread_support",
    "vram_texture_compression/for_desktop", "vram_texture_compression/for_mobile",
    "html/export_icon", "html/custom_html_shell", "html/head_include",
    "html/canvas_resize_policy", "html/focus_canvas_on_start",
    "html/experimental_virtual_keyboard",
    "progressive_web_app/enabled",
    "progressive_web_app/ensure_cross_origin_isolation_headers",
    "progressive_web_app/offline_page", "progressive_web_app/display",
    "progressive_web_app/orientation", "progressive_web_app/icon_144x144",
    "progressive_web_app/icon_180x180", "progressive_web_app/icon_512x512",
    "progressive_web_app/background_color",
}

PRESET_KEYS = {
    "name", "platform", "runnable", "advanced_options", "dedicated_server",
    "custom_features", "export_filter", "include_filter", "exclude_filter",
    "export_path", "encryption_include_filters", "encryption_exclude_filters",
    "encrypt_pck", "encrypt_directory",
}

findings = []


def add(rule, msg):
    findings.append((rule, msg))


def parse_presets(path):
    """Minimal .cfg reader: returns [{header: {k: v}, 'options': {k: v}}]."""
    presets = []
    cur = None
    section = None
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        m = re.match(r"^\[(preset\.\d+)(\.options)?\]$", line)
        if m:
            if m.group(2):
                section = "options"
            else:
                cur = {"preset": {}, "options": {}}
                presets.append(cur)
                section = "preset"
            continue
        if cur is None or "=" not in line:
            continue
        k, _, v = line.partition("=")
        cur[section][k.strip()] = v.strip()
    return presets


def unquote(v):
    return v[1:-1] if len(v) > 1 and v.startswith('"') and v.endswith('"') else v


def project_settings(path):
    txt = open(path, encoding="utf-8").read()
    out = {}
    section = ""
    for raw in txt.split("\n"):
        line = raw.strip()
        if line.startswith(";") or not line:
            continue
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            section = m.group(1)
            continue
        if "=" in line and not line.startswith("["):
            k, _, v = line.partition("=")
            out[(section + "/" + k.strip()).lstrip("/")] = v.strip()
    return out, txt


def res_exists(res):
    if not res.startswith("res://"):
        return os.path.exists(os.path.join(ROOT, res))
    return os.path.exists(os.path.join(ROOT, res[len("res://"):]))


def check_screen(settings: dict, preset: str) -> list:
    """The display chain, as one rule.

    These settings are only correct in combination. Stretch mode `viewport`
    would make the UI scale with the picture; aspect `keep` letterboxes tall
    phones; scale_mode `integer` drops a whole step on a small resize (playtest
    8's bug C); a canvas that does not resize leaves black around the picture;
    a PWA that asks for portrait fights the landscape lock. Each is legal on
    its own, which is why they drift apart.
    """
    out = []
    want = {
        "display/window/stretch/mode": "canvas_items",
        "display/window/stretch/aspect": "expand",
        "display/window/stretch/scale_mode": "fractional",
        "display/window/handheld/orientation": "sensor_landscape",
        "display/window/size/viewport_width": "320",
        "display/window/size/viewport_height": "180",
        "rendering/textures/canvas_textures/default_texture_filter": "0",
    }
    for key, val in want.items():
        got = settings.get(key)
        if got is not None:
            got = got.strip('"')
        if got != val:
            out.append("SCREEN %s is %r, expected %r" % (key, got, val))
    m = re.search(r"^html/canvas_resize_policy\s*=\s*(\d+)", preset, re.M)
    if not m or m.group(1) != "2":
        out.append("SCREEN html/canvas_resize_policy is %s, expected 2 (adaptive)"
                   % (m.group(1) if m else "missing"))
    m = re.search(r"^progressive_web_app/orientation\s*=\s*(\d+)", preset, re.M)
    if not m or m.group(1) != "1":
        out.append("SCREEN PWA orientation is %s, expected 1 (landscape)"
                   % (m.group(1) if m else "missing"))
    return out


def _preset_text(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def main():
    cfg = os.path.join(ROOT, "export_presets.cfg")
    if not os.path.isfile(cfg):
        add("NO-PRESETS", "export_presets.cfg is missing")
        print_findings()
        return 1

    settings, proj_txt = project_settings(os.path.join(ROOT, "project.godot"))
    presets = parse_presets(cfg)
    names = {}

    has_cs = any(f.endswith(".cs") for _, _, fs in os.walk(ROOT)
                 if ".git" not in _ for f in fs)

    for p in presets:
        head, opts = p["preset"], p["options"]
        name = unquote(head.get("name", "?"))
        platform = unquote(head.get("platform", "?"))
        if name in names:
            add("DUP-PRESET", "preset name '%s' used twice" % name)
        names[name] = True

        for k in head:
            if k not in PRESET_KEYS:
                add("UNKNOWN-PRESET-KEY", "'%s' in preset %s is not a preset key"
                    % (k, name))

        # export path
        ep = unquote(head.get("export_path", ""))
        if not ep:
            add("BAD-PATH", "preset %s has no export_path" % name)
        else:
            if ep.startswith("/") or ".." in ep:
                add("BAD-PATH", "preset %s exports outside the repo: %s" % (name, ep))
            want = {"Web": ".html", "Android": ".apk"}.get(platform)
            if want and not ep.endswith(want):
                add("BAD-PATH", "preset %s (%s) should end in %s, got %s"
                    % (name, platform, want, ep))

        if platform != "Web":
            continue

        for f in check_screen(settings, _preset_text(cfg)):
            kind, _, msg = f.partition(" ")
            add(kind, msg)

        # ── Web-specific ────────────────────────────────────────────────
        if has_cs:
            add("CSHARP-WEB", "C# scripts exist but Web export cannot use them")

        for k in opts:
            if k not in WEB_OPTIONS:
                add("UNKNOWN-OPTION",
                    "'%s' in preset %s is not a Godot 4.7 web export option — "
                    "it is silently ignored, so whatever it was meant to do "
                    "does not happen" % (k, name))

        if opts.get("vram_texture_compression/for_mobile") == "true" and \
                settings.get("rendering/textures/vram_compression/import_etc2_astc") != "true":
            add("VRAM-MOBILE",
                "preset %s asks for mobile VRAM compression but the project does "
                "not set rendering/textures/vram_compression/import_etc2_astc=true. "
                "Godot refuses the export and reports NO reason." % name)

        if opts.get("vram_texture_compression/for_desktop") == "true" and \
                settings.get("rendering/textures/vram_compression/import_s3tc_bptc") != "true":
            add("VRAM-DESKTOP",
                "preset %s asks for desktop VRAM compression but the project does "
                "not set rendering/textures/vram_compression/import_s3tc_bptc=true"
                % name)

        if opts.get("variant/thread_support") == "true":
            add("THREADS-PAGES",
                "preset %s enables threads, which needs COOP/COEP headers that "
                "GitHub Pages cannot send and iOS Safari does not support. "
                "Single-threaded is the setting that makes this project hostable."
                % name)

        shell = unquote(opts.get("html/custom_html_shell", ""))
        if shell and not res_exists(shell):
            add("MISSING-FILE", "custom HTML shell does not exist: %s" % shell)

        if opts.get("progressive_web_app/enabled") == "true":
            for key in ("icon_144x144", "icon_180x180", "icon_512x512"):
                icon = unquote(opts.get("progressive_web_app/" + key, ""))
                if icon and not res_exists(icon):
                    add("MISSING-FILE",
                        "PWA %s does not exist: %s" % (key, icon))
            if not any(unquote(opts.get("progressive_web_app/" + k, ""))
                       for k in ("icon_144x144", "icon_180x180", "icon_512x512")):
                add("MISSING-FILE", "PWA enabled but no icons configured")

    # ── project-level references ────────────────────────────────────────
    m = re.search(r'run/main_scene="([^"]+)"', proj_txt)
    if m and not res_exists(m.group(1)):
        add("MISSING-SCENE", "main scene does not exist: %s" % m.group(1))
    for path in re.findall(r'^\w+="\*?(res://[^"]+\.gd)"', proj_txt, re.M):
        if not res_exists(path):
            add("MISSING-SCENE", "autoload script does not exist: %s" % path)

    print_findings()
    return 1 if findings else 0


def print_findings():
    if findings:
        print("check_export: %d finding(s)" % len(findings))
        for rule, msg in findings:
            print("  %-18s %s" % (rule, msg))
    else:
        print("check_export: clean — presets agree with project settings and "
              "with the Godot 4.7 web option list")


if __name__ == "__main__":
    sys.exit(main())
