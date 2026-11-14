extends Node2D
## GoldenRimLayer — Direction B's low sun, drawn ABOVE the y-sorted sprites.
##
## TerrainLayer._draw_cinematic_depth() lights the GROUND and ContactShadowLayer
## casts the shadows, but both are behind the sprites. Without this layer the
## figures stay flat dark cut-outs against a golden field — the exact complaint
## the four-way comparison made about palette-only art. This layer adds a thin
## warm rim on the upper-left edge of every live prop, animal, NPC and player.
## It reads the same target array as the shadow layer each frame, so walking
## figures keep their rim light ANIMATED without duplicating any bookkeeping.
##
## It is opt-in: Region.apply_art_theme("cinematic") enables it; classic and
## storybook never see it. UI is a CanvasLayer above all world nodes, so the
## dialogue panel and HUD are never tinted.

var enabled := false
## [{node: Node2D, w: float, h: float}] — shared by reference with
## ContactShadowLayer; never copied into a static snapshot.
var targets: Array = []


func set_enabled(v: bool) -> void:
	enabled = v
	queue_redraw()


func set_targets(t: Array) -> void:
	targets = t
	queue_redraw()


func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	for t in targets:
		var d: Dictionary = t
		var item = d["node"]
		if not is_instance_valid(item):
			continue
		var n: Node2D = item
		if not n.is_visible_in_tree():
			continue
		var w: float = float(d["w"])
		var h: float = float(d["h"])
		if w < 7.0:
			continue
		var p: Vector2 = n.global_position - global_position
		var rx: float = w * 0.5
		var ry: float = minf(h * 0.5, 10.0)
		# Upper-left quadrant of a small ellipse around the sprite centre:
		# angle PI (left) to 3*PI/2 (top), in screen space. Not a full outline —
		# one light direction only, matching the terrain and the cast shadows.
		var arc := PackedVector2Array()
		for i in range(9):
			var a: float = PI + (TAU * 0.25) * float(i) / 8.0
			arc.append(Vector2(p.x + cos(a) * rx,
					p.y - 1.0 + sin(a) * ry))
		draw_polyline(arc, Color(1.0, 0.86, 0.52, 0.58), 1.4)
		# A shorter, brighter crest where the light actually hits.
		var crest := PackedVector2Array()
		crest.append(Vector2(p.x - rx * 0.75, p.y - 1.0 - ry * 0.35))
		crest.append(Vector2(p.x - rx * 0.20, p.y - 1.0 - ry * 0.85))
		draw_polyline(crest, Color(1.0, 0.94, 0.70, 0.72), 1.5)
