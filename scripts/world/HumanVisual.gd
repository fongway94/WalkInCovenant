extends Node2D
## Foot-anchored reference-direction rig for the witness and supporting people.
## The witness and supporting cast have generated front/right/back sprites.
## Left mirrors right. Feet are animated cutouts, not authored walk frames.
## Samuel's seated art stays in one layer; a missing view falls back to front.

const ROOT := "res://art/characters_reference/"
## Must match SEATED_HEIGHT in the reproducible character builder.
const SEATED_HEIGHT := 76.0

var visible_height := 98.0
var seated := false
var body: Sprite2D
var boot_left: Sprite2D
var boot_right: Sprite2D
var direction := Vector2i(0, 1)
var moving := false
var phase := 0.0
var gait_amount := 0.0
var _poses := {}
var _pose_name := ""


func build(actor: String) -> void:
	if body != null:
		return
	seated = actor == "samuel"
	visible_height = SEATED_HEIGHT if seated else 98.0
	for pose in ["front", "profile", "back"]:
		var prefix: String = ROOT + actor + "_" + str(pose)
		if ResourceLoader.exists(prefix + "_body.png"):
			_poses[pose] = [load(prefix + "_body.png"), load(prefix + "_boot_left.png"),
				load(prefix + "_boot_right.png")]
	boot_left = _part()
	boot_right = _part()
	body = _part()
	add_child(boot_left)
	add_child(boot_right)
	add_child(body)
	_select_pose("front", false)


func _part() -> Sprite2D:
	var piece := Sprite2D.new()
	piece.centered = true
	piece.offset = Vector2(0, -49)
	piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return piece


func _select_pose(name: String, flipped: bool) -> void:
	if not _poses.has(name):
		name = "front"
		flipped = false
	if name != _pose_name:
		var pose: Array = _poses[name]
		body.texture = pose[0]
		boot_left.texture = pose[1]
		boot_right.texture = pose[2]
		_pose_name = name
	body.flip_h = flipped
	boot_left.flip_h = flipped
	boot_right.flip_h = flipped


func set_pose(facing: Vector2i, walking: bool, speed: float, delta: float) -> void:
	if body == null:
		return
	if facing != Vector2i.ZERO:
		direction = facing
	var pose := "front"
	if direction.y < 0:
		pose = "back"
	elif direction.x != 0:
		pose = "profile"
	_select_pose(pose, direction.x < 0)
	# Even if a caller requests movement, the seated prophet's stool and body
	# must never bob as if walking. This does not change NPC movement logic.
	moving = walking and not seated
	gait_amount = move_toward(gait_amount, 1.0 if moving else 0.0, maxf(0.0, delta) * 8.0)
	if moving:
		phase += delta * clampf(speed / 60.0, 0.5, 1.7) * 9.0
	var wave := sin(phase) * gait_amount
	var side := -1.0 if direction.x < 0 else 1.0
	body.position = Vector2(0, -absf(wave) * 0.6)
	boot_left.position = Vector2(side * wave * 1.5, -maxf(0.0, wave) * 0.8)
	boot_right.position = Vector2(-side * wave * 1.5, -maxf(0.0, -wave) * 0.8)
