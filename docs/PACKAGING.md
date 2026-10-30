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

The service worker (`web/sw.js`) caches the whole export — including the `.pck`, which
holds every asset — on first load, cache-first afterwards. `tools/inject_pwa.py` wires
it into Godot's generated `index.html` and stamps the cache name with the git sha so a
deploy can never serve a stale `.pck` against new code.

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

1. `tests/run_all.gd` — the content lint: legend covers the grid; spawn/NPCs/items on
   walkable ground; **a navigation path exists from spawn to every NPC and item**;
   every line bilingual; **no shout without a matching verse** (no unwinnable rounds).
   This is the descendant of Covenant's twelve `check:*` scripts.
2. The export itself, single-threaded, `gl_compatibility`.
3. PWA injection verified — CI fails if the manifest/SW block did not land.
4. **80 MB size budget.** Pixel art should keep this around 10–20 MB; the budget exists
   because solo developers do not notice gradual bloat.

If any of these fail, nothing is published. A broken map never reaches a player.
