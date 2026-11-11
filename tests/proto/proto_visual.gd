extends Node
## Real Godot framebuffer captures, not composited mock-ups. The field and the
## low-resolution comparison use the same frozen world and camera position.
## The walk/camera frame, rock, foreground and sheep tests exercise the scene.

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
	field.set_david(Vector2(700, 360))
	field.set_process(false)
	field.camera.reset_smoothing()
	await _frames(20)
	var cam_a: Vector2 = field.camera.get_screen_center_position()
	var bg_a: Vector2 = (field.get_node("Backdrop") as Node2D).global_position
	await _save("proto_01_field_640")
	# Same framing and frozen actors: only the logical size, camera zoom and
	# proportional HUD size change. Both captures are real 1280x720 frames.
	field.set_prototype_resolution(320)
	field.camera.reset_smoothing()
	await _frames(8)
	await _save("proto_02_field_320")
	field.set_prototype_resolution(640)
	field.camera.reset_smoothing()
	field.set_process(true)
	await _frames(8)
	var sheep_start: Vector2 = (field.sheep[0]["node"] as Node2D).position
	field.sheep[0]["idle"] = 0.0
	field.sheep[0]["target"] = sheep_start + Vector2(24, 0)
	var x0: float = field.david.position.x
	Input.action_press("ui_right")
	await _frames(90)
	Input.action_release("ui_right")
	await _frames(30)
	var dx: float = field.david.position.x - x0
	var sheep_dx: float = (field.sheep[0]["node"] as Node2D).position.distance_to(sheep_start)
	var cam_b: Vector2 = field.camera.get_screen_center_position()
	var bg_b: Vector2 = (field.get_node("Backdrop") as Node2D).global_position
	print("PROTO walk dx=%.1f sheep_moved=%.1f" % [dx, sheep_dx])
	print("PROTO camera A=(%.2f,%.2f) B=(%.2f,%.2f) bg_A=(%.1f,%.1f) bg_B=(%.1f,%.1f) zoom=%.3f" % [
		cam_a.x, cam_a.y, cam_b.x, cam_b.y, bg_a.x, bg_a.y, bg_b.x, bg_b.y, field.camera.zoom.x])
	_check(dx > 20.0, "keyboard movement")
	_check(sheep_dx > 1.0, "independent sheep movement")
	_check(absf(cam_b.x - cam_a.x) > 10.0, "camera followed horizontally")
	_check(cam_b.distance_to(field.david.position) < 35.0, "camera settled near player")
	_check(bg_a == bg_b, "backdrop world origin unchanged")
	await _save("proto_05_camera")
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
	field.set_david(p + Vector2(-30, 4))
	field.camera.reset_smoothing()
	await _frames(6)
	var ok: bool = field.interact()
	var count_after: int = field.counted
	var again: bool = field.interact()
	await _frames(14)
	print("PROTO interact=%s counted=%d repeat=%s" % [str(ok), field.counted, str(again)])
	_check(ok and count_after == 1 and again and field.counted == 1, "sheep interaction counts once")
	await _save("proto_04_sheep")
	if failures == 0:
		print("PROTO PASS")
	else:
		print("PROTO FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


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
