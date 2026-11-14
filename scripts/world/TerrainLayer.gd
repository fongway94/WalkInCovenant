extends Node2D
class_name TerrainLayer
## TerrainLayer — blits the terrain atlas, tile by tile, only where visible.
##
## Why not a TileMap: Godot's TileSet/Terrain API churns between versions and we
## cannot run the engine here to verify it. A direct blit from a known atlas is
## the smallest possible surface area, is deterministic, and matches exactly the
## data artgen emits (data/tiles.json). Autotiling is deliberately absent: the
## tiles ship with hand-authored variants and organic edges are a Phase-0
## editor task, not a blocker.
##
## Water and shallows animate: their four atlas variants ARE the four frames.

const TILE := 16
const WATER_KEYS := ["water", "shallow"]
const ANIM_FPS := 6.0

var model: RegionModel = null
var tex: Texture2D = null
## Optional map-aligned painted ground. Physics still comes from the model.
## Refined maps use two joined textures so each side fits a 2048px GPU limit.
var painted_ground: Texture2D = null
var painted_ground_bottom: Texture2D = null
var atlas_cols: int = 16

var _view := Rect2i()
var _anim := 0
var _acc := 0.0
## Opt-in environmental layering for the art reset (docs/ART-RESET.md §6,
## §12.7). The classic build never sets this. It is drawn INSIDE the terrain's
## own canvas, after the tiles and before the y-sorted props. "storybook" is the
## assistant's Direction C (far ridge, warm middle band, shaded near edge);
## "cinematic" is the user-selected Direction B (camera-relative golden-hour
## wash, dry-stone wall, winding sunlit path, long cast bands). Both are shapes
## with one light source, not a global filter; navigation is unaffected.
var depth_mode := "none"     # none | storybook | cinematic


func set_depth_mode(m: String) -> void:
	depth_mode = m
	queue_redraw()


func set_painted_ground(texture: Texture2D) -> void:
	painted_ground = texture
	painted_ground_bottom = null
	queue_redraw()


func set_painted_ground_pieces(top: Texture2D, bottom: Texture2D) -> void:
	painted_ground = top
	painted_ground_bottom = bottom if top != null else null
	queue_redraw()


func set_storybook_depth(on: bool) -> void:
	set_depth_mode("storybook" if on else "none")


func setup(m: RegionModel, texture: Texture2D, cols: int) -> void:
	model = m
	tex = texture
	atlas_cols = cols
	_queue()


func _queue() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	if model == null:
		return
	_acc += delta
	var f := int(_acc * ANIM_FPS) % 4
	var changed := false
	if f != _anim:
		_anim = f
		changed = true
	var r := _visible_range()
	if r != _view:
		_view = r
		changed = true
	if changed:
		queue_redraw()


func _visible_range() -> Rect2i:
	var cam := get_viewport().get_camera_2d()
	var vs := get_viewport_rect().size
	if cam == null:
		return Rect2i(0, 0, model.width, model.height)
	var half := vs * 0.5 / maxf(0.0001, cam.zoom.x)
	var c := cam.global_position
	var x0 := int(floor((c.x - half.x) / TILE)) - 1
	var y0 := int(floor((c.y - half.y) / TILE)) - 1
	var x1 := int(ceil((c.x + half.x) / TILE)) + 1
	var y1 := int(ceil((c.y + half.y) / TILE)) + 1
	return Rect2i(
		clampi(x0, 0, model.width), clampi(y0, 0, model.height),
		clampi(x1 - x0, 0, model.width), clampi(y1 - y0, 0, model.height))


func _draw() -> void:
	if model == null or tex == null:
		return
	if painted_ground != null:
		var extent := Vector2(model.width * TILE, model.height * TILE)
		if painted_ground_bottom == null:
			draw_texture_rect(painted_ground, Rect2(Vector2.ZERO, extent), false)
		else:
			# Both pieces were cut from one image; their common edge maps to the
			# exact middle of the region, not two independently tiled surfaces.
			var half := Vector2(extent.x, extent.y * 0.5)
			draw_texture_rect(painted_ground, Rect2(Vector2.ZERO, half), false)
			draw_texture_rect(painted_ground_bottom, Rect2(Vector2(0, half.y), half), false)
		return
	for y in range(_view.position.y, _view.position.y + _view.size.y):
		for x in range(_view.position.x, _view.position.x + _view.size.x):
			var key := model.tile_key_at(x, y)
			var count := model.variant_count(key)
			var variant: int
			if key in WATER_KEYS:
				variant = _anim % count
			else:
				variant = RegionModel.cell_variant(x, y) % count
			var idx := model.atlas_index_for(key, variant)
			var col := idx % atlas_cols
			var row := idx / atlas_cols
			var src := Rect2(col * TILE, row * TILE, TILE, TILE)
			var dst := Rect2(x * TILE, y * TILE, TILE, TILE)
			draw_texture_rect_region(tex, dst, src)
	if depth_mode == "storybook":
		_draw_depth()
	elif depth_mode == "cinematic":
		_draw_cinematic_depth()


## Three large-scale value planes. Coordinates are derived from the VISIBLE tile
## range, so the ridge stays at the far edge of the composition as the camera
## follows the player rather than sliding away with world space. The measured
## failure of the palette-only prototype was world_value_spread 20.1 -> 10.6:
## a uniform tan field. Deliberate far/middle/near contrast is the fix, and it
## is verified against a real engine frame, not asserted here.
func _draw_depth() -> void:
	var left := float(_view.position.x) * TILE
	var top := float(_view.position.y) * TILE
	var right := left + float(_view.size.x) * TILE
	var bottom := top + float(_view.size.y) * TILE
	var w := right - left
	# The shipped dialogue panel covers screen rows 116-176, so the VISIBLE
	# world is only rows 24-112. All three planes must fall inside that band:
	# two earlier attempts were measured from REAL CI frames, not assumed:
	#   v1 ridge 0-26 / shade 146-180 left one uniform wash  -> spread 8.0
	#   v2 three planes inside the band but too weak          -> spread 12.3
	#   v3 stronger planes (spread 17.1) but a visible hard horizontal stripe
	# v4 keeps v3's values with a graded warm band and irregular hill/near
	# edges, so the depth reads as terrain rather than as overlaid strips.
	# Classic measured 20.1 — inflated by its own dark HUD scrim bleeding into
	# rows 24-40, NOT by environment depth; see docs/ART-RESET.md §9.
	# Far ridge: cool shade down to an irregular hill line at ~row 60.
	var far := PackedVector2Array()
	far.append(Vector2(left, top))
	for i in range(13):
		var fx := left + w * float(i) / 12.0
		var fy := top + 58.0 + sin(float(i) * 0.83 + 1.1) * 11.0 \
				+ cos(float(i) * 0.39) * 7.0
		far.append(Vector2(fx, fy))
	far.append(Vector2(right, top))
	draw_colored_polygon(far, Color(0.15, 0.19, 0.16, 0.50))
	# A thin sunlit crest along the hill line gives the far plane an edge and a
	# readable volume instead of a flat dark wash.
	var crest := PackedVector2Array()
	for i in range(13):
		var cx := left + w * float(i) / 12.0
		var cy := top + 58.0 + sin(float(i) * 0.83 + 1.1) * 11.0 \
				+ cos(float(i) * 0.39) * 7.0
		crest.append(Vector2(cx, cy))
	for i in range(12, -1, -1):
		var cx := left + w * float(i) / 12.0
		var cy := top + 60.0 + sin(float(i) * 0.83 + 1.1) * 11.0 \
				+ cos(float(i) * 0.39) * 7.0
		crest.append(Vector2(cx, cy))
	draw_colored_polygon(crest, Color(0.86, 0.78, 0.56, 0.22))
	# Middle ground: a GRADED warm band, not a hard-edged rectangle. v3 used a
	# rect and the real frame showed a straight horizontal stripe — exactly the
	# mechanical shape the art direction rejects. Twelve thin strips with a
	# sine alpha envelope give the same value hierarchy without a seam.
	for i in range(12):
		var by := top + 42.0 + float(i) * 6.0
		var t := float(i) / 11.0
		var a := 0.34 * sin(PI * t)
		draw_rect(Rect2(left, by, w, 6.0), Color(0.99, 0.90, 0.70, a))
	# A single long cast shadow across the warm band, from the upper-right sun.
	var cast := PackedVector2Array()
	cast.append(Vector2(left + w * 0.18, top + 88.0))
	cast.append(Vector2(left + w * 0.52, top + 88.0))
	cast.append(Vector2(left + w * 0.34, top + 102.0))
	cast.append(Vector2(left - w * 0.02, top + 102.0))
	draw_colored_polygon(cast, Color(0.21, 0.15, 0.10, 0.26))
	# Near edge: the foreground returns to shade just above the dialogue panel.
	var near := PackedVector2Array()
	near.append(Vector2(left, bottom))
	for i in range(13):
		var nx := left + w * float(i) / 12.0
		var ny := top + 100.0 + sin(float(i) * 0.71 + 0.4) * 10.0 \
				+ cos(float(i) * 0.31) * 6.0
		near.append(Vector2(nx, ny))
	near.append(Vector2(right, bottom))
	draw_colored_polygon(near, Color(0.18, 0.13, 0.09, 0.44))


## Direction B environmental lighting — the golden-hour concept the user
## preferred (docs/ART-RESET.md §12.7). NOT a colour filter: every element is a
## shape with one consistent upper-left sun, and every one is drawn INSIDE the
## terrain canvas so it sits behind the y-sorted sprites and the UI. Ground
## collision, tile indices and navigation are completely unaffected.
##
## v2 (2026-11-10) is anchored to the CAMERA rather than the tile range. The
## first B real frame measured world luma 58.0 against the concept's 84.6: the
## path and most of the light had landed under the HUD or behind the dialogue
## panel. Here the visible world band is rows 34-118 of a 180-row screen, so the
## wash, wall, winding path, cast bands and foreground leaves all live there.
## The camera origin is read live, so the composition follows the player without
## sliding away in world space.
func _cinematic_hash(x: int, y: int) -> int:
	# Stable integer hash for world-anchored micro-detail. No random() call:
	# random details would crawl every time the terrain canvas redraws.
	var n: float = absf(float(x * 73 + y * 151 + x * y * 17))
	return int(fmod(n, 997.0))


func _draw_cinematic_depth() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var vs := get_viewport_rect().size
	var z := maxf(0.0001, cam.zoom.x)
	var half := vs * 0.5 / z
	var origin := cam.global_position + cam.offset - half
	var left := origin.x
	var top := origin.y
	var w := vs.x / z
	var h := vs.y / z
	var right := left + w
	var bottom := top + h

	# 1. Golden sun from the upper LEFT: a graded, camera-relative wash. 16
	#    overlapping strips with a sine envelope and a horizontal falloff, so
	#    there is no hard seam and the right side stays cool.
	var rows := 16
	var cols := 8
	for j in range(rows):
		var ty := float(j) / float(rows - 1)
		var by := top + 34.0 + ty * 84.0
		var env := sin(PI * ty)
		for i in range(cols):
			var tx := float(i) / float(cols - 1)
			var fall := 1.0 - tx
			var a := 0.38 * env * fall * fall
			var sx := left + w * float(i) / float(cols)
			draw_rect(Rect2(sx, by, w / float(cols) + 1.0,
					84.0 / float(rows) + 1.0),
					Color(1.0, 0.82, 0.42, a))
	draw_rect(Rect2(left, top + 34.0, w, 84.0),
			Color(1.0, 0.84, 0.50, 0.10))
	# Four soft diagonal sun shafts. They share ONE upper-left light direction
	# with the cast shadows, rather than acting as a global brightness filter.
	# B v4 lowers their alpha: at 0.10+ the live screenshot read as hard
	# translucent wedges rather than volumetric light.
	for i in range(4):
		var ox := left + w * (0.02 + float(i) * 0.23)
		var oy := top + 30.0 + float(i) * 7.0
		var shaft := PackedVector2Array()
		shaft.append(Vector2(ox, oy))
		shaft.append(Vector2(ox + 20.0, oy - 5.0))
		shaft.append(Vector2(ox + 158.0, oy + 67.0))
		shaft.append(Vector2(ox + 124.0, oy + 76.0))
		draw_colored_polygon(shaft,
				Color(1.0, 0.86, 0.52, 0.045 + float(i) * 0.008))

	# 2. Cool shade under the trees on the right third; irregular, not a rect.
	var cool := PackedVector2Array()
	cool.append(Vector2(left + w * 0.62, top + 30.0))
	cool.append(Vector2(right, top + 26.0))
	cool.append(Vector2(right, bottom))
	cool.append(Vector2(left + w * 0.54, bottom))
	draw_colored_polygon(cool, Color(0.10, 0.17, 0.14, 0.13))

	# 3. Dry-stone wall along the far edge — two irregular courses, lit top
	#    faces and dark mortar; no repeated stamp. It stays inside the world
	#    band under the HUD, like the concept's enclosing pasture wall.
	for row in range(2):
		var wx := left + (7.0 if row == 1 else 0.0)
		var wi := 0
		while wx < right:
			var bw := 9.0 + fmod(float(wi) * 7.3 + float(row) * 4.1, 10.0)
			var bh := 4.0 + fmod(float(wi) * 3.1, 3.0)
			var wy := top + 37.0 + float(row) * 6.0 + sin(float(wi) * 0.7) * 2.0
			draw_rect(Rect2(wx, wy, bw, bh), Color(0.20, 0.20, 0.16, 0.66))
			draw_rect(Rect2(wx + 1.0, wy + 1.0, bw - 2.0, 2.0),
					Color(0.84, 0.75, 0.53, 0.58))
			wx += bw + 1.0
			wi += 1

	# 4. Winding sunlit path: wide in the foreground, tapering to the horizon.
	#    v3 keeps the shape but cuts the flat orange wash and adds ruts, lit
	#    stones and shadowed gravel, so the road is pixel detail rather than a
	#    translucent polygon laid over the meadow.
	var spine := [0.52, 0.48, 0.43, 0.39, 0.36, 0.34, 0.33, 0.32, 0.31, 0.30]
	var halfw := [0.14, 0.12, 0.10, 0.085, 0.07, 0.058, 0.048, 0.038, 0.030, 0.024]
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var edge := PackedVector2Array()
	var rut_l := PackedVector2Array()
	var rut_r := PackedVector2Array()
	for i in range(10):
		var t := float(i) / 9.0
		var py := top + 116.0 - t * 74.0
		var px := left + w * float(spine[i])
		var hw := w * float(halfw[i])
		outer.append(Vector2(px - hw, py))
		inner.append(Vector2(px - hw * 0.55, py))
		edge.append(Vector2(px - hw, py))
		rut_l.append(Vector2(px - hw * 0.42, py))
		rut_r.append(Vector2(px + hw * 0.42, py))
	for i in range(9, -1, -1):
		var t := float(i) / 9.0
		var py := top + 116.0 - t * 74.0
		var px := left + w * float(spine[i])
		var hw := w * float(halfw[i])
		outer.append(Vector2(px + hw, py))
		inner.append(Vector2(px + hw * 0.55, py))
	draw_colored_polygon(outer, Color(1.0, 0.76, 0.34, 0.24))
	draw_colored_polygon(inner, Color(1.0, 0.90, 0.60, 0.16))
	draw_polyline(edge, Color(1.0, 0.95, 0.70, 0.62), 1.0)
	draw_polyline(rut_l, Color(0.32, 0.19, 0.09, 0.42), 1.0)
	draw_polyline(rut_r, Color(0.32, 0.19, 0.09, 0.36), 1.0)
	# Lit stones with a lower-right shadow, anchored to the winding spine.
	for i in range(10):
		var t := float(i) / 9.0
		var py := top + 116.0 - t * 74.0
		var px := left + w * float(spine[i]) + sin(float(i) * 2.3) * w * 0.03
		draw_rect(Rect2(px, py, 2.0, 1.0), Color(1.0, 0.92, 0.66, 0.58))
		draw_rect(Rect2(px + 2.0, py + 1.0, 2.0, 1.0),
				Color(0.30, 0.20, 0.10, 0.34))
		var px2 := px + 7.0 + fmod(float(i) * 5.0, 11.0)
		draw_rect(Rect2(px2, py + 2.0, 2.0, 1.0),
				Color(0.95, 0.79, 0.45, 0.44))
		draw_rect(Rect2(px2 + 2.0, py + 3.0, 1.0, 1.0),
				Color(0.25, 0.18, 0.10, 0.36))

	# 5. Long diagonal cast-shadow bands from off-screen trees. B v4 uses five
	#    low-alpha bands: seven at 0.28 produced hard triangular wedges in the
	#    live frame. The shadows still share the upper-left sun direction.
	for i in range(5):
		var oy := top + 48.0 + float(i) * 11.0
		var ox := left + w * (0.05 + float(i) * 0.115)
		var reach := 98.0 + fmod(float(i) * 13.0, 38.0)
		var band := PackedVector2Array()
		band.append(Vector2(ox, oy))
		band.append(Vector2(ox + 16.0 + float(i % 3) * 4.0, oy - 4.0))
		band.append(Vector2(ox + reach, oy + 23.0))
		band.append(Vector2(ox + reach - 30.0, oy + 29.0))
		draw_colored_polygon(band, Color(0.08, 0.12, 0.08, 0.15))

	# 6. World-anchored foreground grass and flower tufts. The hash uses TILE
	#    coordinates, so these details stay attached to the world as the camera
	#    follows the player. They are drawn behind the y-sorted sprites.
	var gx0 := int(floor(left / TILE)) - 1
	var gx1 := int(ceil(right / TILE)) + 1
	var gy := int(floor(top / TILE)) + 6
	for gx in range(gx0, gx1):
		var hv := _cinematic_hash(gx, gy)
		# B v4: a blade in every visible tile became another cream confetti
		# layer on top of the atlas marks. Only one tile in five gets one.
		if hv % 5 != 0:
			continue
		var wx := float(gx * TILE) + float(hv % 13)
		var blade_row := int(floor(float(hv) / 7.0)) % 30
		var wy := top + 86.0 + float(blade_row)
		# The path occupies the centre-left; keep tall foreground blades in the
		# meadow on the right and along the left frame, as in the concept.
		if wx > left + w * 0.38 and wx < left + w * 0.57:
			continue
		var blade := PackedVector2Array()
		blade.append(Vector2(wx - 2.0, wy + 2.0))
		blade.append(Vector2(wx, wy - 1.0))
		blade.append(Vector2(wx + 2.0, wy + 2.0))
		draw_polyline(blade, Color(0.12, 0.19, 0.10, 0.62), 1.0)
		if hv % 7 == 0:
			draw_line(Vector2(wx - 1.0, wy), Vector2(wx, wy - 3.0),
					Color(0.96, 0.79, 0.39, 0.55), 1.0)
		if hv % 11 == 0:
			draw_rect(Rect2(wx + 3.0, wy - 1.0, 2.0, 2.0),
					Color(0.98, 0.88, 0.56, 0.68))
			draw_rect(Rect2(wx + 5.0, wy + 1.0, 1.0, 1.0),
					Color(0.16, 0.20, 0.11, 0.52))

	# 7. Foreground leaf silhouettes frame the two lower corners just above the
	#    dialogue panel. Drawn behind the sprites, so they never hide a path.
	var near_bottom := top + 130.0
	var near := PackedVector2Array()
	near.append(Vector2(left, near_bottom))
	near.append(Vector2(left, top + 92.0))
	near.append(Vector2(left + 22.0, top + 100.0))
	near.append(Vector2(left + 36.0, top + 92.0))
	near.append(Vector2(left + 52.0, top + 104.0))
	near.append(Vector2(left + 62.0, near_bottom))
	draw_colored_polygon(near, Color(0.07, 0.11, 0.07, 0.42))
	var near_r := PackedVector2Array()
	near_r.append(Vector2(right, near_bottom))
	near_r.append(Vector2(right, top + 88.0))
	near_r.append(Vector2(right - 26.0, top + 98.0))
	near_r.append(Vector2(right - 42.0, top + 90.0))
	near_r.append(Vector2(right - 58.0, top + 106.0))
	near_r.append(Vector2(right - 70.0, near_bottom))
	draw_colored_polygon(near_r, Color(0.07, 0.11, 0.07, 0.38))
	# A few individual leaves with a single warm sunlit tip, not a black bar.
	for i in range(5):
		var lx := left + 5.0 + float(i) * 11.0
		var ly := top + 96.0 + sin(float(i) * 1.7) * 7.0
		var leaf := PackedVector2Array()
		leaf.append(Vector2(lx, ly))
		leaf.append(Vector2(lx + 7.0, ly - 4.0))
		leaf.append(Vector2(lx + 11.0, ly + 2.0))
		leaf.append(Vector2(lx + 4.0, ly + 5.0))
		draw_colored_polygon(leaf, Color(0.07, 0.11, 0.07, 0.54))
		draw_line(Vector2(lx + 7.0, ly - 4.0), Vector2(lx + 11.0, ly + 2.0),
				Color(0.82, 0.68, 0.34, 0.34), 1.0)
