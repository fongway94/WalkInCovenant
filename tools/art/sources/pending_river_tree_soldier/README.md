# Pending river, tree and soldier art experiments

These are **unapproved, unintegrated candidates**, saved from ignored `build/`
scratch so a later session can continue even if the sandbox is reset. They are
not game assets and are excluded from Godot imports and release exports. The
live game is still the previously approved `0fb4c82` build. All copied PNGs
passed basic image verification; that is not an artistic or gameplay approval.

## What is here

- `river-tree-characters/river-detail-retry.png` and `river-ripples-retry.png`:
  generated river candidates. The context painting also contains banks and
  stones, so do **not** paste it wholesale over the ground. The scratch trials
  sample only an explicit water mask, with an additional stone-colour guard.
  The result needs careful visual and pixel-level review; the guard is not
  proven to protect every rock or edge.
- `olive-tall-v2.png`, `olive-variant-retry.png`, `fig-tall.png`, and
  `fig-natural-retry.png`: generated tree candidates on magenta key
  backgrounds. The user specifically wants trees **taller than people**, not
  just wider. Their transparency, foot anchors, shadows, depth sorting,
  occlusion and collision must be reviewed before use.
- `champion-retry.png` and `champion-style-retry.png` are candidate ridge
  champion images; `sprites/` contains temporary keyed/resized samples used
  only in a staged Godot comparison. The figure on the Elah ridge at `[16, 7]`
  is Goliath, drawn separately via `Region.gd` and
  `art/scenes_painted/goliath.png`; it may be the figure the user means, but
  verify in actual play. The regular `soldier` NPC currently falls back to a
  tinted Corin rig (`Npc.gd`); the `soldier-{front,profile,back}.png` files are
  unintegrated generated alternatives and must be checked for consistency.
- `choice_probe.gd.txt` / `choice_probe.tscn`, `river_guard_probe.gd.txt` /
  `river_guard_probe.tscn`, and the Python trial scripts are disposable
  prototypes, not production code or complete tests. The `.gd.txt` suffix
  prevents project-wide GDScript checks from treating scratch as game code.
  `evidence/` holds selected **actual staged Godot framebuffers** from those
  trials, including before/after river, tree and champion comparisons. The
  captures completed without fixture assertions, but no candidate has been
  selected or approved and the engine printed its existing shutdown resource
  warnings. Some generation attempts were reported as failed; these particular
  files are present, but regenerate anything actually missing or visually
  unusable.

## Restoring the scratch layout

From the repository root, in a disposable workspace:

```sh
mkdir -p build/river-tree-characters/{sprites,river-candidates,river-frames,choice-frames} \
         build/river-tree-warrior-probe/frames
touch build/.gdignore
cp -R tools/art/sources/pending_river_tree_soldier/river-tree-characters/. build/river-tree-characters/
cp -R tools/art/sources/pending_river_tree_soldier/river-tree-warrior-probe/. build/river-tree-warrior-probe/
for probe in choice_probe river_guard_probe; do
  mv "build/river-tree-characters/$probe.gd.txt" "build/river-tree-characters/$probe.gd"
done
# The river scripts require Pillow and NumPy and write only under build/.
python3 build/river-tree-characters/river_context_trial.py
python3 build/river-tree-characters/river_safe_trial.py
# Then run the restored *.tscn fixtures with Godot 4.7.2 and a graphical
# renderer at 1000x450; use isolated XDG_DATA_HOME, as in AGENT_CONTINUATION.
```

The mask and world-coordinate assumptions are tied to the current published
Elah reference and map. If either changes, rebuild/revalidate them rather than
reusing them blindly. Preserve actual gameplay, save files, shore/crossing
geometry and the existing approved art. Capture and evaluate real before/after
frames, then run asset/gameplay/browser checks. Do not publish a new version
without separate user approval.
