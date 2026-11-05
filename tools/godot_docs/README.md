# Pinned Godot class reference (offline cache)

`tools/api_check.py` and `tools/xref_check.py` verify every call into the engine
against Godot's own `doc/classes/*.xml`. Those live in `godotengine/godot` at the
`4.7-stable` tag (`REF` comes from `project.godot`'s `config/features`).

CI used to fetch ~54 XML files from `api.github.com` on every push. When that
host rate-limits or hiccups, `fetch_doc()` returns `None` for every engine class
and `xref_check` reports **76 false positives** ("Node2D exists nowhere in the
project", "Player has no global_position") — run `42015418307`. A red build that
blames our own code for a dead network is worse than no diagnostic.

So the parsed class list for exactly the classes this project touches is
committed here. `fetch_doc()` prefers these files when `VERSION` matches `REF`,
and still falls back to the network for any class not in the set (or after a
Godot upgrade changes `REF`). Regenerate with:

    rm -rf /tmp/godot-docs && python3 tools/api_check.py   # rebuild /tmp cache
    cp /tmp/godot-docs/*.json tools/godot_docs/

This is the same data as before, just pinned — no check was relaxed.
