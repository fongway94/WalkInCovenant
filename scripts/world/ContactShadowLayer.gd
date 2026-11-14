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


func add_target(node: Node2D, w: float, h: float, offset: Vector2 = Vector2.ZERO) -> void:
	targets.append({"node": node, "w": w, "h": h, "offset": offset})
	queue_redraw()


## Field-only actors can disappear while their return tween is still running.
## Remove both their shadow and any already-freed entries when the field closes.
func remove_target(node: Node2D) -> void:
	for i in range(targets.size() - 1, -1, -1):
		var item = targets[i].get("node")
		if not is_instance_valid(item) or item == node:
			targets.remove_at(i)
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
		var item = d["node"]
		if not is_instance_valid(item):
			continue
		var n: Node2D = item
		if not n.is_visible_in_tree():
			continue
		var p: Vector2 = n.global_position - global_position + Vector2(d.get("offset", Vector2.ZERO))
		var rx := float(d["w"]) * 0.5
		var ry := float(d["h"])
		if mode == "painted_field":
			_draw_field_shadow(n, p, rx)
			continue
		if mode == "painted_world":
			_draw_world_shadow(n, p, rx)
			continue
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


## The overworld's independent props cast a longer, soft shadow in the same
## direction as the approved field. Flat objects keep only their contact shadow.
## This separate mode deliberately leaves the approved field rendering intact.
func _draw_world_shadow(node: Node2D, p: Vector2, radius: float) -> void:
	var low := false
	if node is Sprite2D:
		var sprite := node as Sprite2D
		var path := sprite.texture.resource_path if sprite.texture != null else ""
		if path.ends_with("/house.png") or path.ends_with("/house_reference_alt.png"):
			# The painted houses end at an off-centre isometric corner. A
			# person-sized oval at the tile centre read as a floating building.
			# Broaden and shift the contact under the actual bottom corner;
			# this draws only below the sprite and changes no map geometry.
			var corner := p + Vector2(radius * 0.55, 0.0)
			var footprint := PackedVector2Array([
				corner + Vector2(-radius * 2.25, -radius * 0.60),
				corner + Vector2(radius * 0.70, -radius * 1.05),
				corner + Vector2(radius * 2.70, -radius * 0.28),
				corner + Vector2(radius * 1.80, radius * 0.28),
				corner + Vector2(0.0, radius * 0.35),
				corner + Vector2(-radius * 1.10, radius * 0.12)])
			draw_colored_polygon(footprint, Color(0.07, 0.08, 0.06, 0.24))
			return
		if path.ends_with("/tent.png") or path.ends_with("/tent_camp_a.png") \
				or path.ends_with("/tent_camp_b.png") or path.ends_with("/tent_royal_open.png"):
			# Tent silhouettes meet the ground along a slanted edge, not at a
			# person's single central foot. Keep the contact wide and quiet.
			var shift := -0.35
			if path.ends_with("/tent_camp_a.png"):
				shift = -0.75
			elif path.ends_with("/tent_camp_b.png"):
				shift = 0.15
			var corner := p + Vector2(radius * shift, 0.0)
			var footprint := PackedVector2Array([
				corner + Vector2(-radius * 2.20, -radius * 0.42),
				corner + Vector2(-radius * 0.65, -radius * 0.90),
				corner + Vector2(radius * 1.35, -radius * 0.70),
				corner + Vector2(radius * 2.45, -radius * 0.18),
				corner + Vector2(radius * 1.40, radius * 0.20),
				corner + Vector2(-radius * 0.70, radius * 0.22)])
			draw_colored_polygon(footprint, Color(0.07, 0.08, 0.06, 0.20))
			return
		for key in ["fire", "altar_stones", "rock", "boulder", "wool_tuft", "wheat_sheaf"]:
			if path.ends_with("/" + key + ".png"):
				low = true
				break
	if not low:
		draw_set_transform(p + Vector2(radius * 1.1, radius * 0.32), 0.16, Vector2(2.35, 0.28))
		draw_circle(Vector2.ZERO, radius, Color(0.07, 0.09, 0.07, 0.12))
		draw_set_transform(p + Vector2(radius * 0.65, radius * 0.18), 0.16, Vector2(1.75, 0.22))
		draw_circle(Vector2.ZERO, radius, Color(0.07, 0.08, 0.06, 0.16))
	draw_set_transform(p, 0.0, Vector2(0.85, 0.22))
	draw_circle(Vector2.ZERO, radius, Color(0.05, 0.055, 0.045, 0.38))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Soft, grounded casts from the approved field prototype. Lighting direction
## remains upper-left to lower-right, regardless of the actor's facing.
func _draw_field_shadow(node: Node2D, p: Vector2, radius: float) -> void:
	if node is FlockSheep:
		draw_set_transform(p + Vector2(radius * 0.65, radius * 0.12), 0.14, Vector2(2.0, 0.26))
		draw_circle(Vector2.ZERO, radius, Color(0.07, 0.09, 0.11, 0.10))
		draw_set_transform(p + Vector2(radius * 0.25, 0), 0.10, Vector2(1.7, 0.20))
		draw_circle(Vector2.ZERO, radius, Color(0.07, 0.08, 0.10, 0.10))
		draw_set_transform(p + Vector2(0, -radius * 0.18), 0.0, Vector2(1.7, 0.17))
		draw_circle(Vector2.ZERO, radius, Color(0.05, 0.055, 0.06, 0.24))
	else:
		draw_set_transform(p + Vector2(radius * 0.75, radius * 0.20), 0.14, Vector2(1.8, 0.32))
		draw_circle(Vector2.ZERO, radius, Color(0.07, 0.09, 0.11, 0.13))
		draw_set_transform(p + Vector2(radius * 0.55, radius * 0.15), 0.14, Vector2(1.35, 0.24))
		draw_circle(Vector2.ZERO, radius, Color(0.07, 0.08, 0.10, 0.17))
		draw_set_transform(p, 0.0, Vector2(0.85, 0.24))
		draw_circle(Vector2.ZERO, radius, Color(0.05, 0.055, 0.06, 0.48))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
