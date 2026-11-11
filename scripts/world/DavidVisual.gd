extends Node2D
## A shared foot-anchored painterly David rig for the player and David NPC.
## Side/back are generated, keyed sources; the front is the approved reference.
## Left mirrors the side art, including its lighting. This is a subtle layered
## cutout gait, not a claim of fully hand-animated directional sprite sheets.

const ROOT := "res://art/characters_painted/"
const REFERENCE := "res://art/proto/sprites/david_reference_"

var body: Sprite2D
var boot_left: Sprite2D
var boot_right: Sprite2D
var direction := Vector2i(0, 1)
var moving := false
var phase := 0.0
var gait_amount := 0.0
var _poses := {}
var _pose_name := ""


func build() -> void:
	if body != null:
		return
	_poses = {
		"front": [load(REFERENCE + "body.png"), load(REFERENCE + "boot_left.png"),
			load(REFERENCE + "boot_right.png")],
		"profile": [load(ROOT + "david_profile_body.png"), load(ROOT + "david_profile_boot_left.png"),
			load(ROOT + "david_profile_boot_right.png")],
		"back": [load(ROOT + "david_back_body.png"), load(ROOT + "david_back_boot_left.png"),
			load(ROOT + "david_back_boot_right.png")],
	}
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
	if name != _pose_name:
		var pose: Array = _poses[name]
		body.texture = pose[0]
		boot_left.texture = pose[1]
		boot_right.texture = pose[2]
		_pose_name = name
	body.flip_h = flipped
	boot_left.flip_h = flipped
	boot_right.flip_h = flipped


## Called from the owning actor's animation update. At idle the last nonzero
## facing remains; no position, collision shape or ground-shadow node moves.
func set_pose(facing: Vector2i, walking: bool, speed: float, delta: float) -> void:
	if body == null:
		build()
	if facing != Vector2i.ZERO:
		direction = facing
	var pose := "front"
	if direction.y < 0:
		pose = "back"
	elif direction.x != 0:
		pose = "profile"
	_select_pose(pose, direction.x < 0)
	moving = walking
	gait_amount = move_toward(gait_amount, 1.0 if walking else 0.0, maxf(0.0, delta) * 8.0)
	if walking:
		phase += delta * clampf(speed / 60.0, 0.5, 1.7) * 9.0
	var wave := sin(phase) * gait_amount
	var side := -1.0 if direction.x < 0 else 1.0
	body.position = Vector2(0, -absf(wave) * 0.6)
	boot_left.position = Vector2(side * wave * 2.0, -maxf(0.0, wave) * 1.2)
	boot_right.position = Vector2(-side * wave * 2.0, -maxf(0.0, -wave) * 1.2)
