extends Node2D
## Foot-anchored reference-direction rig for the witness and supporting people.
## The witness and supporting cast have generated front/right/back sprites.
## Left mirrors right. Feet are animated cutouts, not authored walk frames.
## Samuel's seated art stays in one layer; a missing view falls back to front.

const GAIT := preload("res://scripts/world/ReferenceGait.gd")
const ROOT := "res://art/characters_reference/"
## Must match SEATED_HEIGHT in the reproducible character builder.
const SEATED_HEIGHT := 76.0

var visible_height := 98.0
var seated := false
var actor_id := ""
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
	actor_id = actor
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
	add_child(boot_right)  # the subdued far foot, behind the near foot
	add_child(boot_left)
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
		var duplicate := name == "profile" and actor_id not in ["elder", "woman", "samuel"]
		boot_right.texture = pose[1] if duplicate else pose[2]
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
	moving = walking and speed > 0.1 and not seated
	gait_amount = move_toward(gait_amount, 1.0 if moving else 0.0, maxf(0.0, delta) * 8.0)
	if moving:
		phase = GAIT.advance(phase, speed, delta, scale.x)
	var cut_y := 90.0 if actor_id == "woman" or (pose == "back" and actor_id in ["pilgrim", "king"]) else 84.0
	var duplicate := pose == "profile" and actor_id not in ["elder", "woman", "samuel"]
	var restrained := actor_id == "woman" or (pose == "back" and actor_id in ["pilgrim", "king"])
	GAIT.apply(body, boot_left, boot_right, direction, pose, phase, gait_amount,
		cut_y, duplicate, restrained)
