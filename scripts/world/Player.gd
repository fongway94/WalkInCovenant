extends Node2D
class_name Player
## Player — grid-intent movement in continuous space, with the four things
## that make it feel like a console game (docs/FEEL.md §2):
##
##   1. TURN-IN-PLACE   a direction change rotates first, then steps
##   2. INPUT BUFFERING a press during the turn is remembered, not dropped
##   3. GRID MAGNETISM  gentle pull to tile centres on the crossing axis
##   4. CORNER NUDGE    slip past a corner instead of catching on it
##
## Deliberately NOT a CharacterBody2D: collision is a small feet box tested
## against the region grid, exactly as Covenant's tryMove() did. Fewer moving
## parts, no physics-engine surprises, and doorways behave predictably.

const TILE := 16.0

@export var walk_speed := 60.0        # px/s  → 3.75 tiles/s
@export var run_speed := 96.0         # px/s  → 6.00 tiles/s
@export var turn_time := 0.07         # s — the single most important number here
@export var accel := 900.0
@export var decel := 1200.0
@export var magnet := 22.0            # px/s pull toward tile centre
@export var buffer_window := 0.18     # s

enum Mode { IDLE, TURNING, MOVING }

var model: RegionModel = null
var mode: Mode = Mode.IDLE
var facing := Vector2i(0, 1)          # down
var velocity := Vector2.ZERO

# touch controls push an analog vector here; keyboard/gamepad is read directly
var external_intent := Vector2.ZERO

# animation
var sprite: Sprite2D = null
var walk_tex: Texture2D = null
var idle_tex: Texture2D = null
var _frame := 0.0
var _anim_t := 0.0
var _foot_t := 0.0
var _foot_side := 0

# input buffer
var _buffer := Vector2i.ZERO
var _buffer_age := 999.0
var _turn_t := 0.0

# journey-mirror "step" way: recorded per distance travelled, not per choice
var _step_acc := 0.0

signal interact_requested
signal arrived_at(pos: Vector2)


func setup(m: RegionModel, char_id: String) -> void:
	model = m
	walk_tex = load("res://art/characters/%s_walk.png" % char_id)
	idle_tex = load("res://art/characters/%s_idle.png" % char_id)
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.centered = true
		sprite.offset = Vector2(0, -12)      # 24px cell → feet land on the node
		add_child(sprite)
	sprite.texture = idle_tex
	sprite.hframes = 2
	sprite.vframes = 4
	sprite.frame = 0


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
	_buffer_age += delta
	var intent := _read_intent()

	if intent != Vector2.ZERO:
		var want := _dir_from(intent)
		if want != facing:
			_buffer = want
			_buffer_age = 0.0
			if mode != Mode.TURNING:
				mode = Mode.TURNING
				_turn_t = 0.0
				velocity = Vector2.ZERO
		elif mode == Mode.TURNING:
			# already turning toward it; keep going
			pass

	if mode == Mode.TURNING:
		_turn_t += delta
		if _turn_t >= turn_time:
			# consume the buffer: the press made *during* the turn is honoured
			var d := _consume_buffer()
			if d != Vector2i.ZERO:
				facing = d
			mode = Mode.MOVING
		_update_anim(0.0, delta)
		return

	if intent == Vector2.ZERO:
		mode = Mode.IDLE
		_decelerate(delta)
		_apply_magnetism(delta)
		_update_anim(0.0, delta)
		return

	mode = Mode.MOVING
	var running := Input.is_action_pressed("run")
	var base := run_speed if running else walk_speed
	var surface := model.speed_at(global_position.x, global_position.y)
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
		var s := model.sfx_at(global_position.x, global_position.y)
		if s != "":
			AudioDirector.play_sfx(s, -6.0 + (2.0 if _foot_side == 0 else 0.0))

	_update_anim(velocity.length(), delta)


func _consume_buffer() -> Vector2i:
	if _buffer_age <= buffer_window and _buffer != Vector2i.ZERO:
		var d := _buffer
		_buffer = Vector2i.ZERO
		_buffer_age = 999.0
		return d
	return Vector2i.ZERO


func _decelerate(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, decel * delta)
	if velocity.length() > 0.5:
		_move_with_collision(delta)


## Axis-separated sweep against the region grid, with a corner nudge so
## one-tile doorways never eat the player.
func _move_with_collision(delta: float) -> void:
	var dx := velocity.x * delta
	var dy := velocity.y * delta
	if dx != 0:
		var nx := global_position.x + dx
		if _box_free(nx, global_position.y):
			global_position.x = nx
		elif _box_free(nx, global_position.y - 3):
			global_position.x = nx; global_position.y -= 3     # corner nudge
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
	# clamp inside the region
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
			if model.solid_at(px + ox, py + oy):
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
		global_position.y += clampf(d, -magnet * delta, magnet * delta)
	else:
		var d := cx - global_position.x
		global_position.x += clampf(d, -magnet * delta, magnet * delta)


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
	var moving := speed > 4.0 and mode != Mode.TURNING
	var row := _dir_row()
	if moving:
		sprite.texture = walk_tex
		sprite.hframes = 4
		_anim_t += delta * (speed / walk_speed) * 7.0
		_frame = float(int(_anim_t) % 4)
	else:
		sprite.texture = idle_tex
		sprite.hframes = 2
		_anim_t += delta * 2.0
		_frame = float(int(_anim_t) % 2)
	sprite.vframes = 4
	sprite.frame = int(row * sprite.hframes + _frame)


func _draw() -> void:
	# contact shadow — grounds the figure. Drawn, not baked, so it is always
	# under the feet regardless of frame.
	draw_rect(Rect2(-5, -2, 10, 3), Color(0.05, 0.08, 0.10, 0.35))


func face_toward(target: Vector2) -> void:
	var d := target - global_position
	# Hoisted out of the argument list on purpose. A ternary split across a line
	# continuation inside nested parentheses is a GDScript parser edge case:
	# "Expected closing ) after grouping expression". That single line made
	# Player.gd unparseable, which cascaded into every script that mentions
	# Player and reported itself as "Could not parse global class Player".
	var sx: float = signf(d.x) if absf(d.x) > absf(d.y) else 0.0
	var sy: float = signf(d.y) if absf(d.y) >= absf(d.x) else 0.0
	facing = _dir_from(Vector2(sx, sy))
	mode = Mode.IDLE
