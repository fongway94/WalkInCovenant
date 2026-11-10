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
var storybook_depth := false


func set_storybook_depth(on: bool) -> void:
	storybook_depth = on
	queue_redraw()


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
	if storybook_depth:
		_draw_depth()


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
