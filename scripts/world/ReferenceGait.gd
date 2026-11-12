extends RefCounted
## Shared motion for the painted actors. This remains a procedural cutout
## gait, not a claim of hand-drawn walk cycles. The foot pivots are attached
## near the top of their existing masks, so the shins do not simply slide away
## from the hems. Their nodes, collider and contact shadow never move.

const STRIDE_PER_CYCLE := 42.0
const BASE_RIG_SCALE := 0.28


static func advance(phase: float, speed: float, delta: float, rig_scale: float) -> float:
	# One cycle is two steps. Advance by actual distance, so an escort, walking
	# player, runner and armour-slowed David do not all shuffle at one rate.
	var stride := STRIDE_PER_CYCLE * maxf(rig_scale, 0.001) / BASE_RIG_SCALE
	return fposmod(phase + maxf(speed, 0.0) * maxf(delta, 0.0) * TAU / stride, TAU)


static func apply(body: Sprite2D, near_boot: Sprite2D, far_boot: Sprite2D,
		direction: Vector2i, pose: String, phase: float, amount: float,
		cut_y: float, duplicate_profile: bool, restrained: bool) -> void:
	var wave := sin(phase) * amount
	var side := -1.0 if direction.x < 0 else 1.0
	var profile := pose == "profile"
	var ease := 0.72 if restrained else 1.0
	# Twice-per-cycle body rise and modest weight transfer, all eased in and
	# out. The side pose leans very slightly into travel rather than remaining a
	# rigid cardboard figure. These are source-pixel amounts, scaled by the rig.
	var rise := (0.5 - 0.5 * cos(phase * 2.0)) * amount
	body.position = Vector2(wave * 0.8 * ease, -rise * 2.0 * ease)
	body.rotation = (side * amount * 0.022 + side * wave * 0.012) if profile else wave * 0.017
	body.rotation *= ease

	# Pivot around the mask's top edge, not around the toe or the world origin.
	# The light lift is small enough to leave long hems and David's staff intact.
	var cut_height := 98.0 - cut_y
	var near_x := 0.0 if profile else -7.0
	var far_x := 0.0 if profile else 7.0
	if direction.x < 0:
		near_x = -near_x
		far_x = -far_x
	var swing := (0.30 if profile else 0.14) * ease * side
	_foot(near_boot, body, Vector2(near_x, -cut_height), wave * swing,
		-maxf(0.0, wave) * 1.0 * ease)
	_foot(far_boot, body, Vector2(far_x, -cut_height), -wave * swing,
		-maxf(0.0, -wave) * 1.0 * ease)
	# Most side paintings have only one visible foot. While moving, add a
	# subdued copy behind it as the far foot. It disappears completely at idle;
	# the skirt and the two genuinely separated profiles don't use this copy.
	far_boot.modulate = Color(0.68, 0.66, 0.62, amount * 0.78) \
		if profile and duplicate_profile else Color.WHITE


static func _foot(boot: Sprite2D, body: Sprite2D, pivot: Vector2,
		angle: float, lift: float) -> void:
	boot.rotation = body.rotation + angle
	# Follow the body's lateral lean but keep the planted sole close to the
	# ground rather than making both feet float with the body's vertical bob.
	var anchor := Vector2(body.position.x, 0.0) + pivot.rotated(body.rotation)
	boot.position = anchor - pivot.rotated(boot.rotation) + Vector2(0.0, lift)
