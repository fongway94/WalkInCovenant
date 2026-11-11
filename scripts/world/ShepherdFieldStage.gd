extends Node2D
## The approved shepherd field, installed behind the production Region during
## the shepherd act. Coordinates are the original painting's pixels; the
## uniform transform preserves its aspect ratio, reference masks and depth.
## The chapter's actors, quests, flags, HUD and dialogue remain Region/Main's.

const PAINT_SCALE := 0.35
const ORIGIN := Vector2(0, 400)
const SIZE := Vector2(1440, 666)
const START := Vector2(700, 470)
const FOLD := Vector2(910, 300)
const HIRED_BOY := Vector2(815, 285)
const HURDLE_MEMORY := Vector2(260, 510)
const STRAYS := {
	"sheep_north": Vector2(700, 310),
	"sheep_east": Vector2(980, 380),
	"sheep_west": Vector2(560, 400),
}
## Same traced obstacle footprints as the approved prototype. They are an
## approximation and must continue to be checked against actual rendered paths.
const OBSTACLES := [
	[0, 0, 300, 58], [430, 0, 1010, 60], [1408, 0, 32, 666],
	[0, 530, 200, 136], [1008, 150, 74, 52], [1082, 170, 26, 32],
	[1154, 165, 25, 28], [1080, 350, 130, 150], [856, 226, 120, 42],
	[618, 230, 34, 22], [524, 290, 34, 22], [566, 422, 34, 22],
	[594, 538, 34, 22], [672, 540, 34, 22], [1196, 560, 34, 22],
]


func build() -> void:
	position = ORIGIN
	scale = Vector2.ONE * PAINT_SCALE
	_add_layer("Backdrop", "res://art/proto/shepherd_field_empty.png", -100)
	_add_clipped_layer("Tree", "res://art/proto/shepherd_field_upper_tree.png", 1,
		Rect2(880, 0, 380, 666))
	_add_clipped_layer("Fence", "res://art/proto/shepherd_field_upper_fence.png", 3,
		Rect2(840, 0, 140, 666))
	var foreground := _add_layer("Foreground", "res://art/proto/shepherd_field_fg_cutout.png", 100)
	foreground.position = Vector2(0, 250)


func _add_layer(label: String, path: String, depth: int) -> Sprite2D:
	var layer := Sprite2D.new()
	layer.name = label
	layer.texture = load(path) as Texture2D
	layer.centered = false
	layer.z_index = depth
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(layer)
	return layer


func _add_clipped_layer(label: String, path: String, depth: int, rect: Rect2) -> void:
	var layer := _add_layer(label, path, depth)
	layer.region_enabled = true
	layer.region_rect = rect
	layer.offset = rect.position


func world(art_position: Vector2) -> Vector2:
	return ORIGIN + art_position * PAINT_SCALE


func world_bounds() -> Rect2:
	return Rect2(ORIGIN, SIZE * PAINT_SCALE)


## Keep the painting covering the viewport at tall or very wide aspect ratios.
## The normal 16:9 framing remains 0.9; a small margin prevents pixel snapping
## from exposing the clear colour along an edge. This changes framing only,
## never the world coordinates, depth masks or collision geometry.
func camera_zoom_for(view_size: Vector2) -> float:
	var size := world_bounds().size
	return maxf(0.9, maxf((view_size.x + 2.0) / size.x, (view_size.y + 2.0) / size.y))


func stray_position(id: String) -> Vector2:
	return world(STRAYS.get(id, START + Vector2(80, -80)))


func depth_at(world_position: Vector2) -> int:
	var art_y := (world_position.y - ORIGIN.y) / PAINT_SCALE
	if art_y >= 268.0:
		return 4
	if art_y >= 202.0:
		return 2
	return 0


## World-space foot sample, used by both the player and the sheep. This does
## not stretch or consult the unrelated Elah tile grid while the field is up.
func walkable(world_position: Vector2) -> bool:
	var p := (world_position - ORIGIN) / PAINT_SCALE
	if not Rect2(6, 60, 1428, 596).has_point(p):
		return false
	for obstacle in OBSTACLES:
		var r := Rect2(float(obstacle[0]), float(obstacle[1]),
			float(obstacle[2]), float(obstacle[3]))
		if r.has_point(p):
			return false
	return true


## A small grid is built once for animals on this stage. Unlike the Elah grid,
## it comes from the same traced painted obstacles as the player's feet. A
## 2-unit inset keeps a sheep's contact point from brushing through a fence.
const NAV_CELL := 4.0
const NAV_RADIUS := 2.0
var _nav: AStarGrid2D = null


func _nav_clear(p: Vector2) -> bool:
	for offset in [Vector2.ZERO, Vector2(NAV_RADIUS, 0), Vector2(-NAV_RADIUS, 0),
			Vector2(0, NAV_RADIUS), Vector2(0, -NAV_RADIUS)]:
		if not walkable(p + offset):
			return false
	return true


func segment_clear(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b)))
	for i in range(steps + 1):
		if not _nav_clear(a.lerp(b, float(i) / float(steps))):
			return false
	return true


func _prepare_nav() -> void:
	if _nav != null:
		return
	_nav = AStarGrid2D.new()
	var bounds := world_bounds()
	_nav.region = Rect2i(0, 0, ceili(bounds.size.x / NAV_CELL), ceili(bounds.size.y / NAV_CELL))
	_nav.cell_size = Vector2.ONE * NAV_CELL
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_nav.update()
	for y in range(_nav.region.size.y):
		for x in range(_nav.region.size.x):
			var id := Vector2i(x, y)
			if not _nav_clear(_nav_point(id)):
				_nav.set_point_solid(id)


func _nav_point(id: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(id) + Vector2(0.5, 0.5)) * NAV_CELL


## Find an open grid centre that the endpoint can actually reach in a straight
## line. A nearest cell across a thin fence is not a valid entrance to the path.
func _nav_nearest(p: Vector2) -> Vector2i:
	var local := (p - ORIGIN) / NAV_CELL
	var base := Vector2i(floori(local.x), floori(local.y))
	var best := Vector2i(-1, -1)
	var best_d := INF
	for radius in range(7):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var id := base + Vector2i(x, y)
				if not _nav.is_in_boundsv(id) or _nav.is_point_solid(id):
					continue
				var point := _nav_point(id)
				var d := point.distance_squared_to(p)
				if d < best_d and segment_clear(p, point):
					best = id
					best_d = d
		if best.x >= 0:
			return best
	return best


func sheep_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var route := PackedVector2Array()
	if not _nav_clear(from) or not _nav_clear(to):
		return route
	if segment_clear(from, to):
		route.append(to)
		return route
	_prepare_nav()
	var first := _nav_nearest(from)
	var last := _nav_nearest(to)
	if first.x < 0 or last.x < 0:
		return route
	var ids := _nav.get_id_path(first, last)
	if ids.is_empty():
		return route
	var prior := from
	for id in ids:
		var next := _nav_point(id)
		if not segment_clear(prior, next):
			return PackedVector2Array()
		route.append(next)
		prior = next
	if not segment_clear(prior, to):
		return PackedVector2Array()
	route.append(to)
	return route
