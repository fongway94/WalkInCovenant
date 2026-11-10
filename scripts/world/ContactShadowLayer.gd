extends Node2D
## ContactShadowLayer — one light direction for the whole scene.
##
## Drawn BETWEEN the terrain and the y-sorted sprites, so every tree, rock,
## person and animal sits on the same ground instead of floating on it. The
## classic build keeps this layer disabled (Player._draw() still draws its own
## small rectangle). It is enabled only by Region.apply_art_theme("storybook"),
## the one scene the art-direction reset integrated.
##
## Shapes are deliberately soft irregular ovals, not black circles: a warm
## brown translucent ground shade that follows the same upper-right light as
## the crafted prop ramps. Nothing here affects collision or input.

const RING := 12

var enabled := false
## [{node: Node2D, w: float, h: float}] — nodes are read live, so walking
## figures keep their shadow under their feet without any per-frame bookkeeping.
var targets: Array = []


func set_enabled(v: bool) -> void:
	enabled = v
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
		var pts := PackedVector2Array()
		for i in range(RING):
			var a := TAU * float(i) / float(RING)
			pts.append(Vector2(p.x + cos(a) * rx + 1.0,
					p.y - 1.0 + sin(a) * ry))
		draw_colored_polygon(pts, Color(0.20, 0.13, 0.08, 0.34))
