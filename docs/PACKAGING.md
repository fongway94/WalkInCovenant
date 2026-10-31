# PACKAGING — how a player actually gets the game

> **The question:** *"Can we package it into a single runnable HTML for users to play?"*
>
> **The answer:** not as one double-clickable file — and it is important to understand
> *why*, because the reason is not laziness, it is the browser.

---

## 1. Why the old trick no longer works

Covenant shipped `Covenant-offline.html`: a **10.7 MB single file** you could send over
WeChat or WhatsApp and open by double-clicking, no server, no network. That worked
because Covenant was **pure JavaScript** — the whole game was text the browser could
execute straight from a `file://` page.

The remake runs on Godot, which exports **WebAssembly**:

```
build/web/
  index.html                 ← a loader page, not the game
  index.js                   ← the engine's JS glue
  index.wasm                 ← the engine, compiled
  index.pck                  ← EVERY game asset and scene, packed
  index.audio.worklet.js
  index.audio.position.worklet.js
  index.png
```

Two hard browser facts kill the single-file idea:

1. **`file://` is refused.** Module loading and the `.pck` fetch both fail when the
   page is opened from disk. The export *must* be served over HTTP. "You still cannot
   double click index.html" is Godot's own documentation, not an opinion.
2. **WASM cannot be inlined away.** Base64-embedding the `.wasm` and `.pck` into one
   HTML is not supported by Godot, requires hand-patching the loader, hits browser
   script-size limits, and would produce a ~60 MB HTML file that still might not boot.
   It is a hack fighting the platform, not a shipping path.

So: **the single-file offline HTML is gone, and no amount of work brings it back while
the game is on a real engine.** Anyone who tells you otherwise is selling something.

---

## 2. What replaces it — and why it is better for your audience

Your audience never needed "one file." They needed **one QR code that opens the game
and then works with no signal.** That is exactly what a hosted PWA gives:

| Property | Covenant-offline.html | Hosted PWA (this project) |
|---|---|---|
| One link / one QR to share | ❌ (a 10 MB file to send) | ✅ a URL |
| Plays with zero install | ✅ | ✅ |
| Works offline | ✅ always | ✅ after first load (service worker) |
| Add to home screen, fullscreen | ❌ | ✅ |
| Updates reach players | ❌ re-send the file | ✅ next visit |
| Save data survives | ✅ (file-local) | ✅ (IndexedDB; clearing site data wipes it) |
| Engine quality ceiling | hand-rolled canvas | Godot 4.7 |

**Godot 4.7 does this natively.** With `progressive_web_app/enabled=true` the exporter
writes `<name>.service.worker.js` and `<name>.manifest.json` beside `index.html` and
wires the registration into the loader itself — and it knows every file the loader
fetches, which is precisely the list an offline cache must get right. That is the
mechanism this project ships: the engine's own service worker, our icons and colours,
`display=Fullscreen`, `orientation=Landscape`.

`tools/inject_pwa.py` therefore **verifies rather than injects**: it checks the native
service worker and manifest exist and are referenced by `index.html`, and only falls
back to hand-injecting `web/sw.js` (with a git-sha-stamped cache name) if they are
missing. It exits non-zero either way if the result cannot work offline, so CI never
publishes a build that lost the one property replacing `Covenant-offline.html`.
Injecting a second service worker unconditionally would have *replaced* the engine's on
the same scope — the obvious wrong move, and the reason this script changed role.

`ensure_cross_origin_isolation_headers` stays **off**: it makes the loader demand
COOP/COEP headers, which GitHub Pages cannot send. Single-threaded builds do not need
them.

**It is built and published automatically.** `.github/workflows/build-web.yml` runs
Godot headless in CI (the authoring sandbox cannot run Godot; GitHub Actions can),
runs the content lint first, exports single-threaded Web, injects the PWA shell,
enforces an 80 MB budget, and publishes to GitHub Pages. Push → URL. That URL is your
QR code. This is the same distribution Covenant's README always recommended as primary.

### GitHub Pages gotcha, already handled

Threaded Godot web builds need COOP/COEP headers, which GitHub Pages **cannot** set.
`export_presets.cfg` sets `variant/thread_support=false`, so the build is
single-threaded and runs on ordinary static hosting with no special headers — and on
iOS Safari, where threaded builds have always been broken. Do not turn threads on
unless you move to a host that sends those headers.

---

## 3. The full distribution matrix

| Channel | Artifact | Status | For |
|---|---|---|---|
| **Web PWA (primary)** | GitHub Pages URL + QR | ✅ wired in CI | everyone; youth groups, cell groups, Sunday school |
| **itch.io** | same `build/web` folder | ⏳ trivial (butler push) | game-audience discovery; enable "played in browser" |
| **Android APK** | one `.apk`, sideloadable | ⏳ preset exists, needs keystore + SDK | the true "send one file over WhatsApp" workflow; offline with no first-load |
| **Desktop** | `.exe` / `.x86_64` / `.app` | ⏳ one CLI flag each | reviewers, pastors on laptops, demo days |
| **iOS** | App Store / TestFlight | ⏳ needs a Mac or macOS CI runner for signing | later |
| **Nintendo Switch** | — | ❌ out of scope | Godot has no first-party console export; needs Nintendo approval + a paid porting partner (~US$10–50k). See `PLAN.md` §4. |

**The APK is the honest heir to `Covenant-offline.html`.** It is genuinely one file,
you send it over WhatsApp, it installs, it plays offline with no first-load and no
server. `export_presets.cfg` already has an unsigned Android preset; what remains is a
keystore and the SDK on a machine you control. When you want the "one file for the
auntie who cannot open a link" case, build the APK — do not try to resurrect the HTML.

---

## 3b. The one switch only you can flip — now flipped

Everything in the pipeline is automated **except** the Pages site itself, which
requires repository admin. Neither the workflow's `GITHUB_TOKEN` nor an automated
agent token is granted it, for either creating the site or changing how it builds:

```
POST /repos/:owner/:repo/pages   → 403 Resource not accessible by integration
PUT  /repos/:owner/:repo/pages   → 403 Resource not accessible by integration
   (with build_type=workflow)
```

Done by hand on 2026-10-30. The site is:

> **https://fongway94.github.io/WalkInCovenant/** — one URL, one QR code.

### The trap in that settings page

**Source: `Deploy from a branch` is the default, and it is the wrong one.** It
creates the site with `build_type: "legacy"`, which makes Pages Jekyll-build the
*repository root* of whichever branch is selected. Two consequences, both
confusing:

1. The URL goes live immediately and serves repository text instead of the game,
   so it looks like it worked.
2. `actions/deploy-pages` cannot publish to a legacy site at all, so the `deploy`
   job would keep succeeding while publishing nothing.

The Source dropdown must read **`GitHub Actions`**, which sets `build_type:
"workflow"`. Verify from the API rather than the page:

```bash
gh api repos/fongway94/WalkInCovenant/pages --jq '.build_type'   # → workflow
gh api repos/fongway94/WalkInCovenant/pages/deployments --jq '.[0].status'
```

Until that reads `workflow`, the `deploy` job stays green, publishes nothing, and
prints the instruction as an annotation.

**Playing it without Pages at all:** the CI run uploads a `web` artifact containing
the complete build. Download it, unzip, and serve it — never double-click `index.html` (§1):

```bash
unzip web.zip -d web && cd web && python3 -m http.server 8080
# → http://localhost:8080   open that on your phone over the same Wi-Fi to test touch
```

Or export locally with Godot on your own machine (§4). itch.io is another host that needs
no Pages switch at all.

## 4. Local play while developing

```bash
# export once
godot --headless --export-release "Web" build/web/index.html
python3 tools/inject_pwa.py build/web

# serve (NEVER open index.html from disk)
python3 -m http.server 8080 --directory build/web
# → http://localhost:8080   (open it on your phone over the same Wi-Fi to test touch)
```

Cache warning: the browser caches `index.pck` aggressively. When a fix "did not
apply," it is the cache, not the build. Hard-reload, or test in a private window.

---

## 5. What CI enforces on every push

This is the pipeline as it actually runs on `build-web.yml`, in order. Every one
of these gates exists because it caught something real; the notes say what.

| # | Gate | Tool | What it caught |
|---|---|---|---|
| 1 | GDScript lint | `tools/gd_lint.py` | `:=` combined with a type; iterating an int; `var x := floor(...)` (Variant); `for x in (a, b)` (GDScript has no tuples); a ternary argument wrapped across lines; missing `res://` paths; duplicate `class_name`/`func`; signal handlers that do not exist; mixed indentation |
| 2 | Export configuration | `tools/check_export.py` | `for_mobile=true` without `import_etc2_astc` — Godot refuses the export and prints **no reason**; an option key that does not exist (`progressive_download/enabled`), which is silently ignored; threads on a host that cannot send COOP/COEP; missing PWA icons |
| 3 | Cross-script members | `tools/xref_check.py` | members called on our own classes and on the four autoloads; `class_name` cycles (`Region → Npc → Region`), which Godot reports against an unrelated file |
| 4 | Engine API | `tools/api_check.py` | `AStarGrid2D.diagonal_enabled` (the property is `diagonal_mode`); `push_front` on a `PackedVector2Array`; `get_viewport_rect()` on a `CanvasLayer`; every `Class.CONSTANT` and `.new()`, verified against the class reference XML at the exact version tag |
| 5 | Font coverage | `tools/check_font.py` | decodes the real cmap table out of `fonts/game.ttf` — stdlib only — and fails if any character `data/` or `scripts/` can put on screen has no glyph. A `✧` in the HUD shipped as tofu because the subsetter silently drops what the source face lacks and the charset file recorded the *request*, not the *result* |
| 6 | Import | `godot --headless --import` | builds the global class cache; without it every `class_name` is unresolvable from other scripts |
| 7 | Per-file parse | `tools/ci_parsecheck.sh` | names the file **and line** of a parse error, filtering the two noise classes inherent to checking one file at a time (unregistered autoloads, and the cascades they cause) |
| 8 | Boot | `tools/ci_bootcheck.sh` | runs the real project headless for ten frames with autoloads present and the main scene instantiated. It greps for **runtime** errors too (`Invalid get index`, `Attempt to call function`, `null instance`, `Parent node is busy setting up children`) — parse-only grepping let a boot that built an empty world pass as healthy |
| 9 | Content | `tests/run_all.gd` | legend covers the grid; spawn/NPCs/items on walkable ground; a path exists from spawn to every NPC and item; every line and verse bilingual; no shout without a matching verse |
| 10 | **Playthrough** | `tests/smoke.tscn` | boots the game and *plays* it: briefing, four conversations, crossing the line empty-handed, five stones, BECOME, five rounds of the word battle, RETURN, revisit — then asserts the save state left behind. It caught four bugs gates 1–9 all passed; see below |
| 11 | Export | `godot --export-release "Web"` | single-threaded, `gl_compatibility` |
| 12 | No broken scripts shipped | grep gate | Godot writes the `.pck` and exits **0** even when a script inside it does not parse, so the log is grepped and the job fails |
| 13 | PWA verify | `tools/inject_pwa.py` | confirms the engine emitted and wired `index.service.worker.js` + `index.manifest.json`; injects the fallback only if they are missing |
| 14 | Size budget | `du -sk` | fails over 80 MB; pixel art should land near 10–20 MB |

### What a successful run produces

```
index.html                            8 KB   loader page
index.js                            276 KB   engine glue
index.wasm                                   the engine (the bulk of the build)
index.pck                                    every asset, scene and script
index.audio.worklet.js                  8 KB
index.audio.position.worklet.js         4 KB
index.service.worker.js                      native PWA: offline cache
index.manifest.json                          native PWA: install metadata
index.icon.png                          8 KB
index.apple-touch-icon.png             16 KB
index.144x144.png / 180x180 / 512x512        PWA icons
```

Verified on the run that first went green: `inject_pwa: OK — native PWA verified
(index.service.worker.js + index.manifest.json)`.

### Six things worth knowing about this pipeline

**A green build did not once mean a working game.** Godot exits 0 while packing a
`.pck` that contains scripts which fail to parse. Gate 12 exists because of that.

**Godot blames the wrong file.** A single pair of parentheses in `Player.gd`
(`for ox in (-3.0, 3.0)` — GDScript has no tuples) made `Player` unparseable, so
five scripts that merely mention `Player` reported *"Could not parse global class
Player"*, and `Main.gd`, which never mentions it, reported *"Could not resolve
external class member"*. Reading the analyzer source explains why: that message
means resolving the member pushed errors into *another* script. The blamed file
is a victim. That is why gate 7 prints `file:line` — without it, every failure
pointed somewhere that was not the cause.

**Everything above can be green and the game still unplayable.** Gate 10 was
added last, and on its first four runs it found four bugs that gates 1–9 had all
passed:

1. `Region._build()` never populated its trigger list, so the challenge line at
   row 11 could not fire. Walk the whole valley, pick up all five stones, cross
   the line — nothing happens. The fight was unreachable.
2. `Main._ready()` connected `region_ready` *after* `add_child(region)`, and
   `Region._ready()` emits it from inside that call. `_on_region_ready()` never
   ran, so the stick was never bound to the player and the HUD never bound to the
   region: a valley that renders and ignores every thumb on the screen.
3. The dialogue box was built *after* the NPCs who talk through it, so each one
   was handed `null` and `talk()` returned at its guard. Pressing A next to
   anybody did nothing — the interaction the whole game is built on.
4. `DialogueBox._pick()` incremented the line index after its callback had
   already opened the next beat, instantly finishing single-line follow-ups and
   firing their `on_done` early. The word battle's feedback line was never
   readable and the round double-advanced.

None of those is a parse error, a content error or an API error. All four are
*wiring* errors — correct code assembled in the wrong order — and the only thing
that finds them is playing the game. Note also that gate 10 boots a **scene**
(`res://tests/smoke.tscn`), not `--script`: `Main::start()` instantiates a
`--script` main loop at `main.cpp:4438` and only registers autoloads as global
constants at `:4498`, so on that path the test and every script it pulls in fail
to compile with *"Identifier not found: GameState"*.

**A green deploy did not mean the player received it.** The engine's service
worker template sets `CACHE_VERSION` to the *Godot version*, so two exports from
the same engine produce byte-identical workers — and a browser decides whether
to update a worker by comparing its bytes. Identical bytes mean a returning
phone keeps the old worker, and the old worker serves its old `index.pck`
cache-first: a playtest reported "still tofu" about a build that had shipped a
font three commits earlier, because the font was on the server and the player's
cache was not. `tools/inject_pwa.py` now stamps `CACHE_VERSION` with the run sha
(`WIC_BUILD_STAMP`), and the exported page posts the worker's own `update`
message — skipWaiting, claim, re-navigate every client — so a waiting worker is
adopted on the next open instead of the one after. When a playtest contradicts a
green pipeline, suspect the cache before the code.

**Diagnostics are written for a reader who cannot see the logs.** GitHub keeps
about ten annotations per run and Godot prints ANSI progress lines *after* the
error, so a naive tail fills the quota with noise and the reason disappears. Each
gate therefore emits one joined annotation containing everything that matters,
because `api.github.com` is reachable from environments where the raw-log host is
not.

**The font promised characters it did not carry.** `build_font.py` asks the
subsetter for every character in `data/` and `scripts/`, and the subsetter drops
— without a word — any glyph the *source* face lacks. Noto Sans SC has no `✧`
(U+2727), so the HUD's verse counter rendered as tofu in the very build that
"fixed" tofu; the charset file listed `✧` as covered because it recorded the
request, not the result, and the first version of gate 5 trusted the file.
`build_font.py` now verifies its own output against the built cmap, gate 5 reads
that cmap directly, and the verified symbol vocabulary lives in `EXTRA`. One
engine-side wrinkle from the same hunt: in a cold headless boot `has_char()` can
answer from the glyphs *shaped so far* — one run knew `谷` (it appears in the
briefing) yet denied `石` (not yet drawn anywhere) — so the smoke test asserts
the char table only when `get_supported_chars()` returns the whole table, and
prints a diagnostic either way.
