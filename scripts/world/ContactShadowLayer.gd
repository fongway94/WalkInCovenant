extends Node2D
## ContactShadowLayer — one light direction for the whole scene.
##
## Drawn BETWEEN the terrain and the y-sorted sprites, so every tree, rock,
## person and animal sits on the same ground instead of floating on it. The
## classic build keeps this layer disabled (Player._draw() still draws its own
## small rectangle). Region.apply_art_theme() enables it for the opt-in C and B
## scenes; only "cinematic" adds the long tapered cast shadow.
##
## Shapes are deliberately soft irregular ovals, not black circles: a warm
## brown translucent ground shade that follows the light direction of the
## crafted prop ramps. Direction B's matching rim light is a separate layer
## ABOVE the sprites (GoldenRimLayer.gd). Nothing here affects collision or
## input.

const RING := 12

var enabled := false
## "storybook" draws only a soft contact oval. "cinematic" (Direction B) also
## draws a long tapered cast shadow toward the lower right, matching the low
## upper-left sun of the B concept. Both follow live node positions, so walking
## figures animate their shadows without any extra bookkeeping.
var mode := "storybook"
## [{node: Node2D, w: float, h: float}] — nodes are read live, so walking
## figures keep their shadow under their feet without any per-frame bookkeeping.
var targets: Array = []


func set_enabled(v: bool) -> void:
	enabled = v
	queue_redraw()


func set_mode(m: String) -> void:
	mode = m
	queue_redraw()


func add_target(node: Node2D, w: float, h: float) -> void:
	targets.append({"node": node, "w": w, "h": h})
	queue_redraw()


func _process(_delta: float) -> void:
	# Walking NPCs and the player move every frame; a static shadow list would
	# leave dark ovals behind. One queue_redraw() is cheaper than a signal per
	# character and is only active in the opt-in scene.
	if enabled:
		queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	for t in targets:
		var d: Dictionary = t
		var n: Node2D = d["node"]
		if n == null or not is_instance_valid(n):
			continue
		var p: Vector2 = n.global_position - global_position
		var rx := float(d["w"]) * 0.5
		var ry := float(d["h"])
		if mode == "cinematic":
			# One light direction for the whole picture: upper-left sun,
			# shadows run to the lower right. Length scales with the object so
			# a tree casts farther than a sheep, and the shape is a tapered
			# quad rather than a black oval.
			var length := 8.0 + float(d["w"]) * 0.78
			var cast := PackedVector2Array()
			cast.append(Vector2(p.x - rx * 0.8, p.y - 1.0))
			cast.append(Vector2(p.x + rx * 0.8, p.y - 1.0))
			cast.append(Vector2(p.x + rx * 0.45 + length, p.y + ry + 3.5))
			cast.append(Vector2(p.x - rx * 0.45 + length, p.y + ry + 3.5))
			draw_colored_polygon(cast, Color(0.08, 0.11, 0.07, 0.38))
			# A second, shorter band gives the cast a soft core and a readable
			# ground contact instead of one flat triangle.
			var core := PackedVector2Array()
			core.append(Vector2(p.x - rx * 0.45, p.y))
			core.append(Vector2(p.x + rx * 0.45, p.y))
			core.append(Vector2(p.x + rx * 0.25 + length * 0.62, p.y + ry))
			core.append(Vector2(p.x - rx * 0.25 + length * 0.62, p.y + ry))
			draw_colored_polygon(core, Color(0.07, 0.10, 0.06, 0.20))
		var pts := PackedVector2Array()
		for i in range(RING):
			var a := TAU * float(i) / float(RING)
			pts.append(Vector2(p.x + cos(a) * rx + 1.0,
					p.y - 1.0 + sin(a) * ry))
		if mode == "cinematic":
			draw_colored_polygon(pts, Color(0.10, 0.09, 0.06, 0.50))
		else:
			draw_colored_polygon(pts, Color(0.20, 0.13, 0.08, 0.34))
