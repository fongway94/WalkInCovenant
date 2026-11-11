extends Node2D
class_name Player
## Player — grid-intent movement in continuous space, with the things that
## make it feel like a console game on a phone (docs/FEEL.md §2):
##
##   1. INSTANT FACING  a direction change rotates the sprite on the frame it
##      is pressed and the walk re-aims without stopping. Playtest 3 killed
##      the old 70 ms turn-in-place pause: on a phone every sweep of the thumb
##      around the floating stick re-triggered it, and "a bit of delay" is
##      exactly what a pause per direction change feels like.
##   2. TWO-FRAME RAMP  velocity reaches the target in ~2 frames (accel 1800)
##      and leaves it in ~1 (decel 2400): snappy, never teleported.
##   3. ANALOG FLOOR    touch magnitude scales walk speed but never below 72%
##      of it, and a full tilt (>= 0.9) runs — so a light touch still goes.
##   4. GRID MAGNETISM  gentle pull to tile centres on the crossing axis
##   5. CORNER NUDGE    slip past a corner instead of catching on it
##
## Deliberately NOT a CharacterBody2D: collision is a small feet box tested
## against the region grid, exactly as Covenant's tryMove() did. Fewer moving
## parts, no physics-engine surprises, and doorways behave predictably.

const TILE := 16.0
## The authored overworld uses 16-unit tiles. The approved field has its own
## 0.35 scale; keep painted people smaller on the compact tile maps so they do
## not tower over tents or overlap adjacent NPCs.
const WORLD_RIG_SCALE := 0.23
const FIELD_RIG_SCALE := 0.35

@export var walk_speed := 60.0        # px/s  → 3.75 tiles/s
@export var run_speed := 96.0         # px/s  → 6.00 tiles/s
@export var accel := 1800.0           # px/s^2 — full walk speed in ~2 frames
@export var decel := 2400.0           # px/s^2 — stop in ~1
@export var magnet := 24.0            # px/s pull toward tile centre
@export var run_push := 0.9           # touch magnitude that counts as running

enum Mode { IDLE, MOVING }

var model: RegionModel = null
var char_id := "pilgrim"
## Which sheet directory is active. The opt-in art direction has crafted sheets
## for the two actors in the shepherd scene; every other actor keeps its classic
## sheet. Dimensions/frame counts are identical, so animation is untouched.
var art_dir := "res://art/characters"
## When a shared ContactShadowLayer draws the ground shade, suppress the small
## rectangle in _draw() so figures are not double-shadowed.
var external_shadow := false
## A self-contained field can replace the grid collision without changing the
## region model or the player's feet box. Cleared when that scene ends.
var collision_override: Callable = Callable()
var world_speed_scale := 1.0
## A separate stage does not inherit the invisible valley's terrain or bounds.
var surface_speed_override := -1.0
var footstep_override := ""
var clamp_to_model := true
var field_visual := false
var mode: Mode = Mode.IDLE
var facing := Vector2i(0, 1)          # down
var velocity := Vector2.ZERO

# touch controls push an analog vector here; keyboard/gamepad is read directly
var external_intent := Vector2.ZERO

# animation
var sprite: Sprite2D = null
## Shared painted rig is used only while this actor is David.
var david_visual = null
var human_visual = null
## A sibling drawn above whichever body is visible. The overlay follows the
## body's scale, pose and stagger but never moves the collision or shadow.
var armour_visual = null
var walk_tex: Texture2D = null
var idle_tex: Texture2D = null
var _frame := 0.0
var _anim_t := 0.0
var _foot_t := 0.0
var _foot_side := 0

## Saul's armour (1 Samuel 17:38-39). The game does not tell the player that
## David cannot walk in it — it hands them the thumb and lets them find out.
## Speed drops to a shade under half, the walk gains a stagger, and the sprite
## wears bronze that is not his.
var armour := false
var _armour_t := 0.0

# journey-mirror "step" way: recorded per distance travelled, not per choice
var _step_acc := 0.0

signal interact_requested
signal arrived_at(pos: Vector2)


func setup(m: RegionModel, char_id: String) -> void:
	model = m
	self.char_id = char_id
	# Keep the REQUESTED theme even when this particular actor has no themed
	# sheet. Otherwise becoming David permanently downgraded a later pilgrim.
	var sheet_dir := _sheet_dir(char_id)
	walk_tex = load("%s/%s_walk.png" % [sheet_dir, char_id])
	idle_tex = load("%s/%s_idle.png" % [sheet_dir, char_id])
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.centered = true
		sprite.offset = Vector2(0, -8)       # 16px cell → feet land on the node
		add_child(sprite)
	sprite.texture = idle_tex
	sprite.hframes = 2
	sprite.vframes = 4
	sprite.frame = 0
	_sync_visual()


## The painted rig is opt-in for the cinematic theme or the approved field;
## the classic sheet remains available when the theme changes back.
func _sync_visual() -> void:
	var use_painted := char_id == "david" and (field_visual or art_dir.ends_with("_cinematic"))
	if use_painted and david_visual == null:
		david_visual = load("res://scripts/world/DavidVisual.gd").new()
		add_child(david_visual)
		david_visual.build()
	if david_visual != null:
		david_visual.scale = Vector2.ONE * (FIELD_RIG_SCALE if field_visual else WORLD_RIG_SCALE)
		david_visual.visible = use_painted
		if use_painted:
			david_visual.set_pose(facing, false, 0.0, 0.0)
	var use_pilgrim := char_id == "pilgrim" and art_dir.ends_with("_cinematic")
	if use_pilgrim and human_visual == null:
		human_visual = load("res://scripts/world/HumanVisual.gd").new()
		human_visual.scale = Vector2.ONE * WORLD_RIG_SCALE
		add_child(human_visual)
		human_visual.build("pilgrim")
	if human_visual != null:
		human_visual.visible = use_pilgrim
		if use_pilgrim:
			human_visual.set_pose(facing, false, 0.0, 0.0)
	if sprite != null:
		sprite.visible = not use_painted and not use_pilgrim
	if armour_visual != null:
		# A new body rig may have been added after the overlay during a theme or
		# character change. The armour must always be painted on top of it.
		move_child(armour_visual, -1)
		_update_armour_visual()


func set_field_visual(enabled: bool) -> void:
	field_visual = enabled
	_sync_visual()


## Screen-space overlays can avoid the visible, foot-anchored character in
## either the painted or classic theme without guessing from the hidden sprite.
func visual_height() -> float:
	if david_visual != null and david_visual.visible:
		return 98.0 * david_visual.scale.y
	if human_visual != null and human_visual.visible:
		return 98.0 * human_visual.scale.y
	return 16.0


func set_armour(on: bool) -> void:
	armour = on
	_armour_t = 0.0
	if on and armour_visual == null:
		armour_visual = load("res://scripts/world/ArmourVisual.gd").new()
		add_child(armour_visual)
	# Both the classic sprite and painted rig must return to their feet when the
	# armour comes off (BUG-005), including when the theme changed mid-stagger.
	_set_stagger(0.0)
	_update_armour_visual()


func _set_stagger(offset_x: float) -> void:
	if sprite != null:
		sprite.offset = Vector2(offset_x, -8.0)
	if david_visual != null:
		david_visual.position.x = offset_x
	if human_visual != null:
		human_visual.position.x = offset_x
	_update_armour_visual()


func _update_armour_visual() -> void:
	if armour_visual == null:
		return
	armour_visual.visible = armour
	if not armour:
		return
	var rig = null
	if david_visual != null and david_visual.visible:
		rig = david_visual
	elif human_visual != null and human_visual.visible:
		rig = human_visual
	armour_visual.configure(rig != null, facing)
	if rig != null:
		armour_visual.scale = rig.scale
		# The body bobs independently of the boots in the cutout gait. Follow
		# the body while leaving its foot anchor and ground shadow untouched.
		armour_visual.position = rig.position + rig.body.position * rig.scale
	else:
		armour_visual.scale = Vector2.ONE
		armour_visual.position = Vector2(sprite.offset.x, 0.0) if sprite != null else Vector2.ZERO


## The armour is weight, not a wall: the player must still be able to cross the
## camp and walk to the brook, just not the way they walked before.
func speed_scale() -> float:
	return 0.42 if armour else 1.0


func _ready() -> void:
	if sprite == null and walk_tex != null:
		setup(model, "pilgrim")


# ── intent ───────────────────────────────────────────────────────────────
func _read_intent() -> Vector2:
	var v := external_intent
	var k := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		k.x -= 1
	if Input.is_action_pressed("move_right"):
		k.x += 1
	if Input.is_action_pressed("move_up"):
		k.y -= 1
	if Input.is_action_pressed("move_down"):
		k.y += 1
	var total := v + k
	if total.length_squared() < 0.04:
		return Vector2.ZERO
	# snap intent to the dominant axis — this game is 4-directional by design
	if absf(total.x) > absf(total.y):
		return Vector2(signf(total.x), 0)
	return Vector2(0, signf(total.y))


func _dir_from(v: Vector2) -> Vector2i:
	if v.x > 0:
		return Vector2i(1, 0)
	if v.x < 0:
		return Vector2i(-1, 0)
	if v.y < 0:
		return Vector2i(0, -1)
	return Vector2i(0, 1)


# ── movement ─────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if model == null:
		return
	var intent := _read_intent()

	# Instant facing. The turn-in-place pause this replaces cost every
	# direction change 70 ms of dead time; on a floating stick that pause
	# fired on every thumb sweep and read as input lag (playtest 3).
	if intent != Vector2.ZERO:
		facing = _dir_from(intent)

	if intent == Vector2.ZERO:
		mode = Mode.IDLE
		_decelerate(delta)
		_apply_magnetism(delta)
		if armour:
			_set_stagger(0.0)
		_update_anim(0.0, delta)
		return

	mode = Mode.MOVING
	var push: float = external_intent.length()
	var running := Input.is_action_pressed("run") or push >= run_push
	var base := (run_speed if running else walk_speed) * speed_scale() * world_speed_scale
	if external_intent != Vector2.ZERO and not running:
		# Analog tilt walks slower the gentler it is, but never crawls: the
		# floor keeps the first millimetres of stick travel at walking pace.
		base *= clampf(0.72 + 0.28 * push * 1.2, 0.72, 1.0)
	var surface := _surface_speed()
	var target := intent * base * surface
	velocity = velocity.move_toward(target, accel * delta)

	_move_with_collision(delta)
	_apply_magnetism(delta)

	_step_acc += velocity.length() * delta
	if _step_acc >= TILE * 12:
		_step_acc = 0.0
		GameState.record_way("step")

	# footsteps keyed to terrain, alternating left/right
	_foot_t += delta
	var step_int := 0.32 if not running else 0.22
	if _foot_t >= step_int and velocity.length() > 4:
		_foot_t = 0.0
		_foot_side = 1 - _foot_side
		var s := _surface_sound()
		if s != "":
			AudioDirector.play_sfx(s, -6.0 + (2.0 if _foot_side == 0 else 0.0))

	_update_anim(velocity.length(), delta)
	if armour:
		_armour_t += delta
		# A stumble, not a wobble: the plate pulls the displayed figure sideways
		# without moving the player's collision or shared ground shadow.
		_set_stagger(sin(_armour_t * 11.0) * 1.6)


func _surface_speed() -> float:
	if surface_speed_override >= 0.0:
		return surface_speed_override
	return model.speed_at(global_position.x, global_position.y)


func _surface_sound() -> String:
	if footstep_override != "":
		return footstep_override
	return model.sfx_at(global_position.x, global_position.y)

func _decelerate(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, decel * delta)
	if velocity.length() > 0.5:
		_move_with_collision(delta)


## Axis-separated sweep against the region grid, with a corner nudge so
## one-tile doorways never eat the player.
func _move_with_collision(delta: float) -> void:
	# Sample short steps in the field, including at low frame rates, so a single
	# long frame cannot jump through the much thinner painted obstacle traces.
	var steps := 1
	if collision_override.is_valid():
		steps = maxi(1, ceili(maxf(absf(velocity.x), absf(velocity.y)) * delta / 2.0))
	for i in range(steps):
		var dx := velocity.x * delta / float(steps)
		var dy := velocity.y * delta / float(steps)
		if dx != 0:
			var nx := global_position.x + dx
			if _box_free(nx, global_position.y):
				global_position.x = nx
			elif _box_free(nx, global_position.y - 3):
				global_position.x = nx; global_position.y -= 3
			elif _box_free(nx, global_position.y + 3):
				global_position.x = nx; global_position.y += 3
			else:
				velocity.x = 0
		if dy != 0:
			var ny := global_position.y + dy
			if _box_free(global_position.x, ny):
				global_position.y = ny
			elif _box_free(global_position.x - 3, ny):
				global_position.y = ny; global_position.x -= 3
			elif _box_free(global_position.x + 3, ny):
				global_position.y = ny; global_position.x += 3
			else:
				velocity.y = 0
	if clamp_to_model:
		global_position.x = clampf(global_position.x, 4, model.width * TILE - 4)
		global_position.y = clampf(global_position.y, 4, model.height * TILE - 2)

## Feet box: 8 wide, 4 tall, centred on the node. Small on purpose.
func _box_free(px: float, py: float) -> bool:
	# Array literals, NOT parenthesised comma lists. GDScript has no tuples:
	# `for ox in (-3.0, 3.0)` parses the "(" as a grouping expression, reads
	# -3.0, then meets "," and fails with 'Expected closing ")" after grouping
	# expression'. That one line made Player.gd unparseable, and because five
	# other scripts mention Player, the engine blamed THEM instead.
	for ox in [-3.0, 3.0]:
		for oy in [-3.0, 0.0]:
			var sample := Vector2(px + ox, py + oy)
			if collision_override.is_valid():
				if not bool(collision_override.call(sample)):
					return false
			elif model.solid_at(sample.x, sample.y):
				return false
	return true


func _apply_magnetism(delta: float) -> void:
	if velocity == Vector2.ZERO:
		return
	# floorf, not floor. The unsuffixed floor()/ceil()/round()/abs()/min()/max()
	# take and return Variant in Godot 4 — that is why the f/i variants exist —
	# so `:=` on them infers Variant, which is ERROR-level (INFERENCE_ON_VARIANT)
	# and stops the script compiling at all.
	var cx := (floorf(global_position.x / TILE) * TILE) + TILE * 0.5
	var cy := (floorf(global_position.y / TILE) * TILE) + TILE * 0.5
	if absf(velocity.x) > absf(velocity.y):
		var d := cy - global_position.y
		var target_y := global_position.y + clampf(d, -magnet * delta, magnet * delta)
		if _box_free(global_position.x, target_y):
			global_position.y = target_y
	else:
		var d := cx - global_position.x
		var target_x := global_position.x + clampf(d, -magnet * delta, magnet * delta)
		if _box_free(target_x, global_position.y):
			global_position.x = target_x


# ── animation ────────────────────────────────────────────────────────────
func _dir_row() -> int:
	match facing:
		Vector2i(0, 1): return 0
		Vector2i(-1, 0): return 1
		Vector2i(1, 0): return 2
		_: return 3


func _update_anim(speed: float, delta: float) -> void:
	if sprite == null:
		return
	var moving := speed > 4.0 and mode == Mode.MOVING
	if david_visual != null and david_visual.visible:
		david_visual.set_pose(facing, moving, speed, delta)
	if human_visual != null and human_visual.visible:
		human_visual.set_pose(facing, moving, speed, delta)
	var row := _dir_row()
	if moving:
		sprite.texture = walk_tex
		sprite.hframes = 4
		_anim_t += delta * (speed / walk_speed) * 8.0
		_frame = float(int(_anim_t) % 4)
	else:
		sprite.texture = idle_tex
		sprite.hframes = 2
		_anim_t += delta * 2.0
		_frame = float(int(_anim_t) % 2)
	sprite.vframes = 4
	sprite.frame = int(row * sprite.hframes + _frame)
	_update_armour_visual()


func _draw() -> void:
	# contact shadow — grounds the figure. Drawn, not baked, so it is always
	# under the feet regardless of frame. In the storybook scene the shared
	# ContactShadowLayer owns all ground shade instead (one light direction).
	if not external_shadow:
		draw_rect(Rect2(-5, -2, 10, 3), Color(0.05, 0.08, 0.10, 0.35))


## Swap to the crafted sheets only when BOTH exist for this actor. Remember
## the selected theme even if this actor temporarily requires a classic sheet.
func apply_art_theme(theme: String) -> void:
	art_dir = "res://art/characters"
	if theme == "storybook" or theme == "cinematic":
		art_dir = "res://art/characters_%s" % theme
	var d := _sheet_dir(char_id)
	external_shadow = theme == "storybook" or theme == "cinematic"
	walk_tex = load("%s/%s_walk.png" % [d, char_id])
	idle_tex = load("%s/%s_idle.png" % [d, char_id])
	if sprite != null:
		sprite.texture = idle_tex
		sprite.hframes = 2
		sprite.vframes = 4
		sprite.frame = 0
	_sync_visual()
	queue_redraw()


func _sheet_dir(actor: String) -> String:
	if ResourceLoader.exists("%s/%s_walk.png" % [art_dir, actor]) \
			and ResourceLoader.exists("%s/%s_idle.png" % [art_dir, actor]):
		return art_dir
	return "res://art/characters"


func face_toward(target: Vector2) -> void:
	var d := target - global_position
	# Hoisted out of the argument list on purpose. A ternary split across a line
	# continuation inside nested parentheses is a GDScript parser edge case:
	# "Expected closing ) after grouping expression". That single line made
	# Player.gd unparseable, which cascaded into every script that mentions
	# Player and reported itself as "Could not parse global class Player".
	var sx: float = signf(d.x) if absf(d.x) > absf(d.y) else 0.0
	var sy: float = signf(d.y) if absf(d.y) >= absf(d.x) else 0.0
	if sx != 0.0 or sy != 0.0:
		facing = _dir_from(Vector2(sx, sy))
	mode = Mode.IDLE
	_update_anim(0.0, 0.0)
