extends Node2D
## Saul's armour is a removable overlay, not part of David's body art. It is
## drawn after the actor, at the same scale and stagger offset as the visible
## rig. The painted shapes are in the 70x98 source-image coordinates; they
## deliberately leave the face, hands and feet visible. Classic retains its
## own small pixel-space treatment.

var painted := false
var facing := Vector2i(0, 1)


func configure(use_painted: bool, direction: Vector2i) -> void:
	if painted == use_painted and facing == direction:
		return
	painted = use_painted
	facing = direction
	queue_redraw()


func _draw() -> void:
	if painted:
		_draw_painted()
	else:
		_draw_classic()


func _draw_classic() -> void:
	var dark := Color(0.32, 0.22, 0.10)
	var bronze := Color(0.68, 0.48, 0.19)
	var light := Color(0.91, 0.71, 0.35)
	# Keep the middle of the head uncovered: it is a helmet, not a face mask.
	draw_rect(Rect2(-4, -16, 8, 2), dark)
	draw_rect(Rect2(-3, -16, 6, 1), light)
	draw_rect(Rect2(-5, -10, 10, 2), dark)
	draw_rect(Rect2(-4, -9, 8, 4), bronze)
	draw_rect(Rect2(-3, -9, 6, 1), light)
	draw_rect(Rect2(-4, -6, 8, 1), dark)


func _draw_painted() -> void:
	# The artwork's centre is (35, 49), with its feet 49 units below that.
	# Mirror the profile together with the body when facing left.
	var flipped := facing.x < 0
	var origin := Vector2(35, -98) if flipped else Vector2(-35, -98)
	var direction_scale := Vector2(-1, 1) if flipped else Vector2.ONE
	draw_set_transform(origin, 0.0, direction_scale)
	var dark := Color(0.25, 0.17, 0.09)
	var bronze := Color(0.50, 0.34, 0.15)
	var mid := Color(0.64, 0.45, 0.21)
	var light := Color(0.88, 0.67, 0.34)
	var shade := Color(0.35, 0.24, 0.11)

	# A low cap shows the weight of the oversized helmet without obscuring the
	# face on front and profile poses. Back-facing David gets the same cap.
	_poly([Vector2(17, 11), Vector2(19, 6), Vector2(24, 2), Vector2(35, 1),
		Vector2(41, 5), Vector2(43, 11), Vector2(41, 14), Vector2(37, 12),
		Vector2(28, 11), Vector2(22, 14)], dark)
	_poly([Vector2(19, 10), Vector2(21, 6), Vector2(25, 3), Vector2(35, 3),
		Vector2(39, 6), Vector2(41, 11), Vector2(36, 9), Vector2(27, 9),
		Vector2(22, 12)], bronze)
	draw_line(Vector2(22, 7), Vector2(26, 4), light, 1.5)
	draw_line(Vector2(26, 4), Vector2(34, 4), mid, 1.5)

	if facing.x != 0:
		# The profile is narrower so the forward arm and staff stay legible.
		_poly([Vector2(22, 32), Vector2(27, 30), Vector2(36, 31), Vector2(41, 35),
			Vector2(41, 44), Vector2(40, 59), Vector2(37, 64), Vector2(24, 63),
			Vector2(21, 58), Vector2(21, 40)], dark)
		_poly([Vector2(24, 34), Vector2(28, 32), Vector2(36, 33), Vector2(39, 36),
			Vector2(38, 59), Vector2(35, 61), Vector2(25, 60), Vector2(23, 56)], bronze)
		draw_line(Vector2(25, 36), Vector2(35, 35), light, 1.3)
		for y in [41, 47, 53]:
			draw_line(Vector2(24, y), Vector2(37, y + 1), shade, 1.4)
			draw_line(Vector2(26, y - 1), Vector2(33, y), mid, 1.0)
	else:
		# Broad shoulder pieces and a segmented coat read as armour from both
		# front and back, while the shepherd's lower body remains visible.
		_poly([Vector2(16, 34), Vector2(21, 30), Vector2(26, 30), Vector2(30, 33),
			Vector2(37, 32), Vector2(42, 30), Vector2(47, 35), Vector2(46, 41),
			Vector2(42, 42), Vector2(43, 58), Vector2(40, 62), Vector2(23, 62),
			Vector2(20, 58), Vector2(20, 42), Vector2(16, 40)], dark)
		_poly([Vector2(20, 35), Vector2(24, 32), Vector2(29, 35), Vector2(37, 34),
			Vector2(41, 32), Vector2(44, 36), Vector2(40, 41), Vector2(41, 57),
			Vector2(38, 60), Vector2(24, 60), Vector2(22, 57), Vector2(22, 41)], bronze)
		_poly([Vector2(17, 35), Vector2(21, 32), Vector2(25, 33), Vector2(24, 37),
			Vector2(20, 40), Vector2(17, 39)], mid)
		_poly([Vector2(39, 34), Vector2(43, 32), Vector2(46, 35), Vector2(45, 39),
			Vector2(41, 40)], mid)
		draw_line(Vector2(20, 35), Vector2(24, 33), light, 1.3)
		draw_line(Vector2(25, 37), Vector2(38, 37), light, 1.2)
		for y in [42, 48, 54]:
			draw_line(Vector2(23, y), Vector2(40, y), shade, 1.4)
			draw_line(Vector2(25, y - 1), Vector2(36, y - 1), mid, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _poly(points: Array[Vector2], color: Color) -> void:
	var vertices := PackedVector2Array()
	for point in points:
		vertices.append(point)
	draw_colored_polygon(vertices, color)
