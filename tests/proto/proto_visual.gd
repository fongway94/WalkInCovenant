extends Node
## Real Godot framebuffer captures, not composited mock-ups. The walk/camera,
## rock, foreground, tree/fence depth and sheep tests exercise the playable scene.
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
	var alignment_a: int = await _empty_depth_difference()
	print("PROTO empty depth mismatch camera A=%d" % alignment_a)
	_check(alignment_a <= 8, "depth overlays align to backdrop at camera A")
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
	# The preceding run contains the interaction capture; this run uses the
	# sixth full-frame slot to show the new fence from the opposite side.
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
	var behind_stats: Dictionary = await _layer_pixel_difference(tree)
	var behind_changed: int = int(behind_stats["actor"])
	# In front of the tree but behind the fence: its top rail should hide the
	# boots instead of appearing painted behind the character.
	field.set_david(Vector2(920, 224))
	field.camera.reset_smoothing()
	await _frames(8)
	await _save("proto_02_tree_front")
	var alignment_b: int = await _empty_depth_difference()
	print("PROTO empty depth mismatch camera B=%d" % alignment_b)
	_check(alignment_b <= 8, "depth overlays align to backdrop at camera B")
	var front_stats: Dictionary = await _layer_pixel_difference(tree)
	var front_changed: int = int(front_stats["actor"])
	print("PROTO tree actor delta behind=%d front=%d; raw=%d/%d background=%d/%d" % [
		behind_changed, front_changed, int(behind_stats["raw"]), int(front_stats["raw"]),
		int(behind_stats["background"]), int(front_stats["background"])])
	_check(behind_changed > 10 and front_changed < maxi(5, int(float(behind_changed) * 0.15)),
		"rendered tree covers behind, not in front")
	_check(int(behind_stats["background"]) <= 6 and int(front_stats["background"]) <= 6,
		"tree overlay does not shift its background")
	var fence: Node2D = field.get_node("FenceDepth") as Node2D
	var fence_behind_stats: Dictionary = await _layer_pixel_difference(fence)
	var fence_behind: int = int(fence_behind_stats["actor"])
	field.set_david(Vector2(920, 280))
	field.camera.reset_smoothing()
	await _frames(8)
	await _save("proto_04_fence_front")
	var fence_front_stats: Dictionary = await _layer_pixel_difference(fence)
	var fence_front: int = int(fence_front_stats["actor"])
	print("PROTO fence actor delta behind=%d front=%d; raw=%d/%d background=%d/%d" % [
		fence_behind, fence_front, int(fence_behind_stats["raw"]), int(fence_front_stats["raw"]),
		int(fence_behind_stats["background"]), int(fence_front_stats["background"])])
	_check(fence_behind > 4 and fence_front < maxi(4, int(float(fence_behind) * 0.25)),
		"rendered fence covers behind, not in front")
	_check(int(fence_behind_stats["background"]) <= 6 and int(fence_front_stats["background"]) <= 6,
		"fence overlay does not shift its background")
	if failures == 0:
		print("PROTO PASS")
	else:
		print("PROTO FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _layer_pixel_difference(layer: Node2D) -> Dictionary:
	# Four real framebuffers distinguish actor occlusion from discrepancies in
	# the overlay's *background pixels*. Count on/off changes only where the
	# actor is visible with the overlay off, and separately gate background
	# mismatches. Subtracting two deltas would falsely count an actor in front
	# just because it covers a mismatched background pixel.
	layer.visible = true
	await RenderingServer.frame_post_draw
	var with_actor_on := get_viewport().get_texture().get_image()
	layer.visible = false
	await RenderingServer.frame_post_draw
	var with_actor_off := get_viewport().get_texture().get_image()
	_set_actor_art_visible(false)
	layer.visible = true
	await RenderingServer.frame_post_draw
	var empty_on := get_viewport().get_texture().get_image()
	layer.visible = false
	await RenderingServer.frame_post_draw
	var empty_off := get_viewport().get_texture().get_image()
	_set_actor_art_visible(true)
	layer.visible = true
	var changed := 0
	var raw := 0
	var background := 0
	var map := Image.create(640, 360, false, Image.FORMAT_RGB8)
	map.fill(Color.BLACK)
	for y in range(30, 370, 4):
		for x in range(580, 850, 4):
			var a := with_actor_on.get_pixel(x, y)
			var b := with_actor_off.get_pixel(x, y)
			var c := empty_on.get_pixel(x, y)
			var d := empty_off.get_pixel(x, y)
			var raw_delta := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			var bg_delta := absf(c.r - d.r) + absf(c.g - d.g) + absf(c.b - d.b)
			var actor_visible := absf(b.r - d.r) + absf(b.g - d.g) + absf(b.b - d.b)
			if raw_delta > 0.15:
				raw += 1
			if bg_delta > 0.15:
				background += 1
			var actor_changed := raw_delta > 0.15 and actor_visible > 0.15
			if actor_changed:
				changed += 1
			# Red = on/off difference on the actor; green = empty background.
			if actor_changed or bg_delta > 0.15:
				var colour := Color(1.0 if actor_changed else 0.0, 1.0 if bg_delta > 0.15 else 0.0, 0.0)
				map.set_pixel(int(x / 2), int(y / 2), colour)
				map.set_pixel(int(x / 2) + 1, int(y / 2), colour)
	# A sparse diagnostic derived from real framebuffers, not a gameplay frame.
	if layer.name == "UpperTreeDepth" and field.david.position.y > 200.0:
		var path := ProjectSettings.globalize_path(OUT).path_join("proto_07_tree_delta.png")
		var err := map.save_png(path)
		print("PROTO saved tree delta diagnostic err=%d" % err)
	return {"actor": changed, "raw": raw, "background": background}


func _set_actor_art_visible(on: bool) -> void:
	field.david_sprite.visible = on
	field.david_boot_left.visible = on
	field.david_boot_right.visible = on
	(field.david.get_node("GroundShadow") as Node2D).visible = on


func _empty_depth_difference() -> int:
	# Compare both depth copies against the backdrop with all moving characters
	# hidden. Sample the entire framebuffer at two distinct camera positions;
	# static HUD/foreground remain identical in both captures.
	var tree: Node2D = field.get_node("UpperTreeDepth") as Node2D
	var fence: Node2D = field.get_node("FenceDepth") as Node2D
	_set_actor_art_visible(false)
	for s in field.sheep:
		(s["node"] as Node2D).visible = false
	tree.visible = true
	fence.visible = true
	await RenderingServer.frame_post_draw
	var enabled := get_viewport().get_texture().get_image()
	tree.visible = false
	fence.visible = false
	await RenderingServer.frame_post_draw
	var disabled := get_viewport().get_texture().get_image()
	tree.visible = true
	fence.visible = true
	_set_actor_art_visible(true)
	for s in field.sheep:
		(s["node"] as Node2D).visible = true
	var mismatches := 0
	var size := enabled.get_size()
	for y in range(0, size.y, 8):
		for x in range(0, size.x, 8):
			var a := enabled.get_pixel(x, y)
			var b := disabled.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.15:
				mismatches += 1
	return mismatches


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
