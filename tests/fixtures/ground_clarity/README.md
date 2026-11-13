# Published ground samples

These two 300×300 RGB crops come from the ground textures published at game
revision `d8526c3`:

- `elah-published.png`: `world_elah_refined_bottom.png`, box `(700, 950, 1000, 1250)`.
- `bethlehem-published.png`: `world_bethlehem_refined_top.png`, box `(100, 400, 400, 700)`.

`tests/proto/check_quality_assets.py` uses them to catch regressions in local
edge strength and palette. They are ground pixels only, not gameplay images,
and the numerical check does not establish artistic quality or absence of
motion shimmer. The fixtures are excluded from release exports.
