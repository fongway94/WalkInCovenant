extends Node
## Renders the isolated shepherd-field prototype in the real engine and writes
## PNG frames to build/proto. Walks David with real input actions, checks rock
## collision, parks him behind the bottom-left foreground and interacts with a
## sheep. Every capture is a real framebuffer read.

const SCENE := "res://scenes/proto/ShepherdFieldProto.tscn"
const OUT := "res://build/proto"

var field: Node2D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	field = (load(SCENE) as PackedScene).instantiate()
	add_child(field)
	await _frames(20)
	field.set_david(Vector2(700, 470))
	await _frames(10)
	await _save("proto_01_field")
	var x0: float = field.david.position.x
	Input.action_press("ui_right")
	await _frames(90)
	Input.action_release("ui_right")
	await _frames(10)
	print("PROTO walk dx=%.1f" % (field.david.position.x - x0))
	await _save("proto_02_walk")
	field.set_david(Vector2(590, 250))
	await _frames(4)
	Input.action_press("ui_right")
	await _frames(60)
	Input.action_release("ui_right")
	await _frames(4)
	var stop_x: float = field.david.position.x
	print("PROTO rock stop_x=%.1f blocked=%s" % [stop_x, str(stop_x < 618.0)])
	field.set_david(Vector2(236, 606))
	await _frames(10)
	await _save("proto_03_occlusion")
	var p: Vector2 = field.nearest_sheep_pos()
	field.set_david(p + Vector2(-30, 4))
	await _frames(12)
	var ok: bool = field.interact()
	await _frames(14)
	print("PROTO interact=%s counted=%d" % [str(ok), field.counted])
	await _save("proto_04_sheep")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT).path_join(name + ".png")
	var err := img.save_png(path)
	print("PROTO saved %s err=%d" % [name, err])
