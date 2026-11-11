extends Node
## Real Godot framebuffer captures, not composited mock-ups. The walk/camera,
## rock, foreground, tree-depth and sheep tests exercise the playable scene.
## The previous run documented the frozen 320-vs-640 resolution comparison.

const SCENE := "res://scenes/proto/ShepherdFieldProto.tscn"
const OUT := "res://build/proto"

# This is an instance of the prototype script, not a plain engine Node2D. Keep
# it dynamically typed so the offline API checker does not mistake its custom
# methods and fields for missing Godot Node2D API members.
var field
var failures := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	field = (load(SCENE) as PackedScene).instantiate()
	add_child(field)
	# Use the actual scene spawn, also making the baseline/new captures
	# comparable. At y=360 the original sheep home overlaps David's head.
	field.set_david(Vector2(700, 470))
	field.set_process(false)
	field.camera.reset_smoothing()
	await _frames(20)
	var cam_a: Vector2 = field.camera.get_screen_center_position()
	var bg_a: Vector2 = (field.get_node("Backdrop") as Node2D).global_position
	await _save("proto_01_field_640")
	field.set_process(true)
	await _frames(8)
	var sheep_start: Vector2 = (field.sheep[0]["node"] as Node2D).position
	field.sheep[0]["idle"] = 0.0
	field.sheep[0]["target"] = sheep_start + Vector2(24, 0)
	var x0: float = field.david.position.x
	Input.action_press("ui_right")
	var max_stride := 0.0
	for i in range(90):
		await get_tree().process_frame
		max_stride = maxf(max_stride, absf(field.david_boot_left.position.x))
	# Select a walking pose, not just an idle frame after releasing the key.
	for i in range(20):
		if absf(field.david_boot_left.position.x) > 1.4:
			break
		await get_tree().process_frame
	var dx: float = field.david.position.x - x0
	var sheep_dx: float = (field.sheep[0]["node"] as Node2D).position.distance_to(sheep_start)
	var cam_b: Vector2 = field.camera.get_screen_center_position()
	var bg_b: Vector2 = (field.get_node("Backdrop") as Node2D).global_position
	print("PROTO walk dx=%.1f sheep_moved=%.1f max_stride=%.2f" % [dx, sheep_dx, max_stride])
	print("PROTO camera A=(%.2f,%.2f) B=(%.2f,%.2f) bg_A=(%.1f,%.1f) bg_B=(%.1f,%.1f) zoom=%.3f" % [
		cam_a.x, cam_a.y, cam_b.x, cam_b.y, bg_a.x, bg_a.y, bg_b.x, bg_b.y, field.camera.zoom.x])
	_check(dx > 20.0, "keyboard movement")
	_check(max_stride > 1.0, "layered boot gait")
	_check(sheep_dx > 1.0, "independent sheep movement")
	_check(absf(cam_b.x - cam_a.x) > 10.0, "camera followed horizontally")
	# Vertical tracking is intentionally limited because this wide view nearly
	# fits the 666px-tall world. Check the clamped target, not player distance.
	var half_world_height: float = 180.0 / field.camera.zoom.y
	var expected_y: float = clampf(field.david.position.y, half_world_height, 666.0 - half_world_height)
	_check(absf(cam_b.x - field.david.position.x) < 20.0 and absf(cam_b.y - expected_y) < 2.0,
		"camera follows within world limits")
	_check(bg_a == bg_b, "backdrop world origin unchanged")
	await _save("proto_05_camera")
	Input.action_release("ui_right")
	await _frames(8)
	# Walk into a painted rock. The collision body must stop before its left
	# edge; a teleport alone would not test the physics shape.
	field.set_david(Vector2(590, 250))
	await _frames(4)
	Input.action_press("ui_right")
	await _frames(60)
	Input.action_release("ui_right")
	await _frames(4)
	var stop_x: float = field.david.position.x
	print("PROTO rock stop_x=%.1f blocked=%s" % [stop_x, str(stop_x < 618.0)])
	_check(stop_x >= 600.0 and stop_x < 618.0, "rock collision")
	# At the old (236,606) location the polygon hid nearly the whole figure.
	field.set_david(Vector2(310, 610))
	field.camera.reset_smoothing()
	await _frames(8)
	await _save("proto_03_occlusion")
	var p: Vector2 = field.nearest_sheep_pos()
	field.set_david(p + Vector2(-62, 4))
	field.camera.reset_smoothing()
	# Interact immediately, as a player can, before the sheep flees away.
	var ok: bool = field.interact()
	var count_after: int = field.counted
	var again: bool = field.interact()
	await _frames(14)
	print("PROTO interact=%s counted=%d repeat=%s" % [str(ok), field.counted, str(again)])
	_check(ok and count_after == 1 and again and field.counted == 1, "sheep interaction counts once")
	await _save("proto_04_sheep")
	field.set_david(Vector2(330, 110))
	_check(not field.interact() and field.counted == 1, "interaction requires nearby sheep")
	# The right-hand upper tree is separately y-sorted at its ground line.
	# Test a real trunk collider, then capture and compare both sides of the
	# depth line using the real renderer, not just the scene hierarchy.
	field.set_david(Vector2(1130, 180))
	await _frames(4)
	Input.action_press("ui_right")
	await _frames(60)
	Input.action_release("ui_right")
	await _frames(4)
	var trunk_x: float = field.david.position.x
	print("PROTO tree trunk stop_x=%.1f" % trunk_x)
	_check(trunk_x >= 1140.0 and trunk_x < 1154.0, "tree trunk collision")
	field.set_process(false)
	var tree: Node2D = field.get_node("UpperTreeDepth") as Node2D
	field.set_david(Vector2(920, 165))
	field.camera.reset_smoothing()
	await _frames(8)
	await _save("proto_06_tree_behind")
	var behind_changed: int = await _tree_pixel_difference(tree)
	field.set_david(Vector2(920, 210))
	field.camera.reset_smoothing()
	await _frames(8)
	await _save("proto_02_tree_front")
	var front_changed: int = await _tree_pixel_difference(tree)
	print("PROTO tree pixel change behind=%d front=%d" % [behind_changed, front_changed])
	_check(behind_changed > 10 and front_changed < maxi(8, int(float(behind_changed) * 0.25)),
		"rendered tree covers behind, not in front")
	if failures == 0:
		print("PROTO PASS")
	else:
		print("PROTO FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _tree_pixel_difference(tree: Node2D) -> int:
	# At these two fixed test positions the camera is clamped to the right and
	# top of the world. The region contains David and the canopy. The sheep are
	# frozen. Toggling the depth copy should change rendered actor pixels only
	# behind the tree, not while the same actor is in front of its ground line.
	tree.visible = true
	await RenderingServer.frame_post_draw
	var with_tree := get_viewport().get_texture().get_image()
	tree.visible = false
	await RenderingServer.frame_post_draw
	var without_tree := get_viewport().get_texture().get_image()
	tree.visible = true
	var changed := 0
	for y in range(30, 300, 4):
		for x in range(580, 850, 4):
			var a := with_tree.get_pixel(x, y)
			var b := without_tree.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.15:
				changed += 1
	return changed


func _check(ok: bool, name: String) -> void:
	print("PROTO check %s: %s" % [name, "PASS" if ok else "FAIL"])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT).path_join(name + ".png")
	var err := img.save_png(path)
	print("PROTO saved %s size=%s err=%d" % [name, str(img.get_size()), err])
	_check(err == OK, "save " + name)
