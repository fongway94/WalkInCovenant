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
var atlas_cols: int = 16

var _view := Rect2i()
var _anim := 0
var _acc := 0.0
## Opt-in environmental layering for the selected art direction (docs/ART-RESET.md
## §6). The classic build never sets this. It is drawn INSIDE the terrain's own
## canvas, after the tiles and before the y-sorted props: a far olive ridge, a
## warm middle-ground wash and a shaded near edge. These are shapes with a
## single upper-right light source, not a global brightness/saturation filter,
## and the ground sprites themselves are unchanged so navigation is unaffected.
var depth_mode := "none"     # none | storybook | cinematic


func set_depth_mode(m: String) -> void:
	depth_mode = m
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
## The measured world band is screen rows 24-112 (the dialogue panel covers
## 116-176), so the wall, light gradient, cast bands and path all land in it.
func _draw_cinematic_depth() -> void:
	var left := float(_view.position.x) * TILE
	var top := float(_view.position.y) * TILE
	var right := left + float(_view.size.x) * TILE
	var bottom := top + float(_view.size.y) * TILE
	var w := right - left
	# 1. Golden sun from the upper LEFT: ten vertical strips, alpha falling off
	#    to the right. No hard seam (v3's rectangular wash was rejected).
	for i in range(10):
		var t := float(i) / 9.0
		var a := 0.26 * (1.0 - t) * (1.0 - t)
		var sx := left + w * float(i) / 10.0
		draw_rect(Rect2(sx, top, w / 10.0 + 1.0, bottom - top),
				Color(1.0, 0.84, 0.46, a))
	# 2. Cool shade under the trees on the right third.
	var cool := PackedVector2Array()
	cool.append(Vector2(left + w * 0.66, top))
	cool.append(Vector2(right, top))
	cool.append(Vector2(right, bottom))
	cool.append(Vector2(left + w * 0.58, bottom))
	draw_colored_polygon(cool, Color(0.13, 0.19, 0.14, 0.22))
	# 3. Dry-stone wall along the far edge — a real landmark, not a gradient.
	#    Irregular block sizes; lit top face, dark mortar, no repeated stamp.
	var wx := left
	var wi := 0
	while wx < right:
		var bw := 11.0 + fmod(float(wi) * 7.3, 9.0)
		var bh := 6.0 + fmod(float(wi) * 3.1, 3.0)
		var wy := top + 46.0 + sin(float(wi) * 0.7) * 2.0
		draw_rect(Rect2(wx, wy, bw, bh), Color(0.20, 0.20, 0.17, 0.72))
		draw_rect(Rect2(wx + 1.0, wy + 1.0, bw - 2.0, 2.0),
				Color(0.72, 0.67, 0.53, 0.60))
		wx += bw + 1.0
		wi += 1
	# 4. Winding sunlit path, tapering into the distance. Control points are
	#    deliberately irregular; the shape is a polygon, not a straight band.
	var path := PackedVector2Array()
	var spine := [0.18, 0.22, 0.28, 0.33, 0.36, 0.34, 0.30, 0.26]
	var halfw := [0.11, 0.09, 0.075, 0.06, 0.05, 0.042, 0.033, 0.025]
	for i in range(8):
		var py := top + 112.0 - float(i) * 12.0
		var px := left + w * float(spine[i])
		path.append(Vector2(px - w * float(halfw[i]), py))
	for i in range(7, -1, -1):
		var py := top + 112.0 - float(i) * 12.0
		var px := left + w * float(spine[i])
		path.append(Vector2(px + w * float(halfw[i]), py))
	draw_colored_polygon(path, Color(0.98, 0.76, 0.38, 0.30))
	# 5. Long diagonal cast-shadow bands from the off-screen trees (upper-left
	#    sun → lower-right shadows). Tapered, irregular, no black.
	for i in range(4):
		var oy := top + 62.0 + float(i) * 14.0
		var ox := left + w * (0.12 + float(i) * 0.10)
		var band := PackedVector2Array()
		band.append(Vector2(ox, oy))
		band.append(Vector2(ox + 26.0, oy - 3.0))
		band.append(Vector2(ox + 78.0, oy + 17.0))
		band.append(Vector2(ox + 52.0, oy + 20.0))
		draw_colored_polygon(band, Color(0.10, 0.14, 0.10, 0.20))
	# 6. Foreground leaf silhouettes framing the two lower corners. Drawn
	#    behind the sprites, so they frame the picture without hiding a path.
	var near := PackedVector2Array()
	near.append(Vector2(left, bottom))
	near.append(Vector2(left, top + 96.0))
	near.append(Vector2(left + 22.0, top + 100.0))
	near.append(Vector2(left + 36.0, top + 94.0))
	near.append(Vector2(left + 52.0, top + 104.0))
	near.append(Vector2(left + 62.0, bottom))
	draw_colored_polygon(near, Color(0.09, 0.13, 0.09, 0.36))
	var near_r := PackedVector2Array()
	near_r.append(Vector2(right, bottom))
	near_r.append(Vector2(right, top + 92.0))
	near_r.append(Vector2(right - 26.0, top + 98.0))
	near_r.append(Vector2(right - 42.0, top + 92.0))
	near_r.append(Vector2(right - 58.0, top + 106.0))
	near_r.append(Vector2(right - 70.0, bottom))
	draw_colored_polygon(near_r, Color(0.09, 0.13, 0.09, 0.32))
