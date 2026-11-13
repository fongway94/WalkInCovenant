# Previous public ground samples

These 300×300 RGB crops come from the ground textures of game revision
`f2afae9`, published before the material-detail pass:

- `elah-f2afae9.png`: `world_elah_refined_bottom.png`, box `(700, 950, 1000, 1250)`.
- `bethlehem-f2afae9.png`: `world_bethlehem_refined_top.png`, box `(100, 400, 400, 700)`.

The asset check compares the rebuilt previous ground to these files and checks
edge strength and palette changes in the new ground. This is a regression
indicator, **not** an automated judgment of artistic quality or motion shimmer.
These fixtures are excluded from game exports and from Godot imports.
