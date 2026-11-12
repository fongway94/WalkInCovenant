extends Node2D
class_name FlockSheep
## FlockSheep — one stray on David's slope. A living animal, not a quest dot.
##
## The milestone asked for an actual herding loop without turning it into a
## minigame. This is the whole of it:
##
##   * each sheep grazes in a small circle around its tile, two animation frames
##     (head up / head down), a <=1 px bob, and its own tempo (docs/ART_DIRECTION.md §3);
##   * come at it from the FOLD side (you are between it and home) and it shies
##     away from you, once, for 0.7 s. You see the mistake, you are not punished
##     for it: after the startle it can still be caught;
##   * come at it from BEHIND (the fold is beyond the sheep) and it walks toward
##     the hurdle while you hold that side. `trust` fills in about 1.4 s, then
##     the sheep goes home on its own and counts as *guided*;
##   * walking right up to it always works. Nothing here can strand a player,
##     block a save, or turn three sheep into a chase.
##
## The pickup flag, the HUD counter and the toast still belong to Region and
## Main. This node only owns the animal's body and its mood; `Region.collect_pickup`
## is the one door that turns "in the fold" into story progress.

signal reacted(id: String, mood: int)
signal arrived(id: String, guided: bool)

enum Mood { GRAZE, ALERT, HERDED, GOING_HOME }

const TILE := 16
const TRUST_RATE := 0.72
const HOME_SPEED := 19.0
const STARTLE_SECS := 0.7
const HOME_RADIUS := 16.0

var sheep_id := ""
var anchor := Vector2.ZERO
var fold := Vector2.ZERO
var temper := "calm"
var player: Node2D = null
var region: Node = null
var mood: int = Mood.GRAZE
var trust := 0.0
var guided := false
var driven_px := 0.0

var _leash := 10.0
var _notice := 38.0
var _speed := 9.0
var _graze_bias := 0.5
var _phase := 0.0
var _t := 0.0
var _startle := 0.0
var _bleat_cd := 0.0
var _hinted := false
var _leaving := false
var _sprite: Sprite2D = null
var _up_tex: Texture2D = null
var _graze_tex: Texture2D = null
var _alert_tex: Texture2D = null
var _field_frames: Array[Texture2D] = []
var _field_walkable: Callable = Callable()
var _field_route: Callable = Callable()
var _home_path := PackedVector2Array()
var _home_path_index := 0
var _home_path_asked := false


func setup(id: String, at: Array, fold_at: Array, temper_name: String,
		pl: Node2D, reg: Node) -> void:
	sheep_id = id
	temper = temper_name
	player = pl
	region = reg
	anchor = Vector2(float(at[0]) * TILE + 8.0, float(at[1]) * TILE + 12.0)
	fold = Vector2(float(fold_at[0]) * TILE + 8.0,
		float(fold_at[1]) * TILE + 12.0)
	global_position = anchor
	# Three animals, three dispositions. The difference is readable in the
	# frame: one hardly looks up, one startles at a distance, one drifts close.
	match temper:
		"skittish":
			_leash = 14.0; _notice = 47.0; _speed = 13.0; _graze_bias = 0.22
		"curious":
			_leash = 8.0; _notice = 31.0; _speed = 7.0; _graze_bias = 0.78
		_:
			_leash = 10.0; _notice = 38.0; _speed = 9.0; _graze_bias = 0.5
	# Deterministic per-sheep phase, so a row of animals never pulses as one
	# object and a captured frame is reproducible across CI runs.
	_phase = float(id.length()) * 0.7 + float(at[0]) * 0.21 + float(at[1]) * 0.13
	_up_tex = load("res://art/props/sheep.png")
	_graze_tex = load("res://art/props/sheep_graze.png")
	_alert_tex = load("res://art/props/sheep_alert.png")
	_sprite = Sprite2D.new()
	_sprite.texture = _up_tex
	_sprite.scale = Vector2(0.85, 0.85)
	add_child(_sprite)


## Crafted wool poses are opt-in with the rest of the selected art direction;
## the animal's behaviour, collision and save flags are untouched.
func apply_art_theme(theme: String) -> void:
	var d := "res://art/props"
	var alt := "res://art/props_%s" % theme
	if (theme == "storybook" or theme == "cinematic") \
			and ResourceLoader.exists("%s/sheep.png" % alt) \
			and ResourceLoader.exists("%s/sheep_graze.png" % alt) \
			and ResourceLoader.exists("%s/sheep_alert.png" % alt):
		d = alt
	var painted := "res://art/props_painted"
	if theme == "cinematic" and ResourceLoader.exists(painted + "/sheep.png") \
			and ResourceLoader.exists(painted + "/sheep_graze.png") \
			and ResourceLoader.exists(painted + "/sheep_alert.png"):
		d = painted
	_up_tex = load("%s/sheep.png" % d)
	_graze_tex = load("%s/sheep_graze.png" % d)
	_alert_tex = load("%s/sheep_alert.png" % d)
	if _sprite != null and _sprite.texture != null:
		var cur := _sprite.texture.resource_path
		if cur.ends_with("sheep_graze.png"):
			_sprite.texture = _graze_tex
		elif cur.ends_with("sheep_alert.png"):
			_sprite.texture = _alert_tex
		else:
			_sprite.texture = _up_tex
		if d == painted:
			_sprite.scale = Vector2.ONE * (0.425 / ArtDirection.PAINTED_PROP_DETAIL_FACTOR)
			_sprite.offset = Vector2(0, -float(_up_tex.get_height()) * 0.5)
		else:
			_sprite.scale = Vector2.ONE * 0.85
			_sprite.offset = Vector2.ZERO


## The production field uses the same independent reference-derived sheep as
## the approved prototype, at the field's uniform world scale.
func apply_shepherd_field(at: Vector2, home: Vector2, variant: int,
		walkable: Callable, route: Callable) -> void:
	anchor = at
	fold = home
	global_position = at
	_field_walkable = walkable
	_field_route = route
	_home_path = PackedVector2Array()
	_home_path_index = 0
	_home_path_asked = false
	var suffix := "a" if variant % 2 == 0 else "b"
	var base := "res://art/proto/sprites/sheep_reference_" + suffix
	_field_frames = [load(base + ".png"), load(base + "_stride_a.png"), load(base + "_stride_b.png")]
	_up_tex = _field_frames[0]
	_graze_tex = _field_frames[0]
	_alert_tex = _field_frames[0]
	_sprite.texture = _up_tex
	_sprite.scale = Vector2.ONE * (0.66 * 0.35)
	_sprite.offset = Vector2(0, -float(_up_tex.get_height()) * 0.5)


func mood_name() -> String:
	match mood:
		Mood.ALERT: return "alert"
		Mood.HERDED: return "herded"
		Mood.GOING_HOME: return "home"
		_: return "graze"


func is_guided() -> bool:
	return guided


func _process(delta: float) -> void:
	if _leaving or _sprite == null:
		return
	# A conversation owns the world: animals freeze under a box, exactly like
	# the player and the NPCs. Nothing in here may fire while the story speaks.
	if region != null and region.has_method("is_paused") and bool(region.call("is_paused")):
		return
	_t += delta
	_startle = maxf(0.0, _startle - delta)
	_bleat_cd = maxf(0.0, _bleat_cd - delta)
	_animate()
	if player == null:
		return

	var to_player := global_position - player.global_position
	var dist := to_player.length()
	var to_fold := fold - global_position
	var fold_dir := to_fold.normalized() if to_fold.length() > 1.0 else Vector2.ZERO
	# Standing on the far side of the sheep from the hurdle IS the herding
	# position: the animal is between you and home.
	var behind := to_player.dot(fold_dir) > 0.0

	if mood == Mood.GOING_HOME:
		_step_toward_fold(delta)
		return
	if dist < _notice and not behind:
		if mood != Mood.ALERT:
			mood = Mood.ALERT
			_startle = STARTLE_SECS
			if not _hinted:
				_hinted = true
				reacted.emit(sheep_id, Mood.ALERT)
			_bleat()
	elif dist < _notice and behind:
		if mood != Mood.HERDED:
			mood = Mood.HERDED
			if not _hinted:
				_hinted = true
				reacted.emit(sheep_id, Mood.HERDED)
			_bleat()
		trust = minf(1.0, trust + TRUST_RATE * delta)
		if trust >= 1.0:
			mood = Mood.GOING_HOME
			guided = true
			reacted.emit(sheep_id, Mood.GOING_HOME)
	elif dist >= _notice * 1.25 and mood != Mood.GRAZE:
		mood = Mood.GRAZE

	if mood == Mood.HERDED:
		global_position += fold_dir * _speed * delta
		driven_px += _speed * delta
	elif mood == Mood.ALERT and _startle > 0.0 and dist > 0.1:
		global_position += to_player.normalized() * _speed * 0.8 * delta
	else:
		var idle_target := anchor + Vector2(
			sin(_t * 0.70 + _phase) * _leash * 0.55,
			cos(_t * 0.51 + _phase) * _leash * 0.34)
		global_position = global_position.move_toward(idle_target, _speed * 0.55 * delta)
	_clamp_to_leash()


func _step_toward_fold(delta: float) -> void:
	var to_fold := fold - global_position
	if to_fold.length() <= HOME_RADIUS or to_fold.length() < 1.0:
		arrived.emit(sheep_id, true)
		return
	if not _field_route.is_valid():
		global_position += to_fold.normalized() * HOME_SPEED * delta
		_sprite.flip_h = to_fold.x < 0.0
		return
	if not _home_path_asked:
		_home_path = _field_route.call(global_position, fold)
		_home_path_index = 0
		_home_path_asked = true
	var travel := HOME_SPEED * delta
	while travel > 0.0 and _home_path_index < _home_path.size():
		var target: Vector2 = _home_path[_home_path_index]
		var distance := global_position.distance_to(target)
		if distance < 0.01:
			_home_path_index += 1
			continue
		var next := global_position.move_toward(target, travel)
		# The field owns the route and collision. If it changes or disappears,
		# stop rather than tunnelling through a prop. A deliberate count still
		# works if a route cannot be found.
		if not _field_segment_clear(global_position, next):
			_home_path = PackedVector2Array()
			return
		_sprite.flip_h = next.x < global_position.x
		global_position = next
		travel -= minf(distance, travel)
		if distance <= 0.01 or global_position.distance_to(target) < 0.01:
			_home_path_index += 1


func _field_segment_clear(a: Vector2, b: Vector2) -> bool:
	if not _field_walkable.is_valid():
		return false
	var steps := maxi(1, ceili(a.distance_to(b)))
	for i in range(steps + 1):
		if not bool(_field_walkable.call(a.lerp(b, float(i) / float(steps)))):
			return false
	return true

func _clamp_to_leash() -> void:
	# Never leave the authored tile, never walk into a rock, never wander off
	# the map. The world reacts, but the objective stays where the player saw it.
	var off := global_position - anchor
	var lim := _leash * 1.8
	if off.length() > lim:
		global_position = anchor + off.normalized() * lim
	if _field_walkable.is_valid():
		if not bool(_field_walkable.call(global_position)):
			global_position = anchor
		return
	if region != null and region.get("model") != null:
		var m = region.get("model")
		var tx := int(floor(global_position.x / TILE))
		var ty := int(floor((global_position.y - 4.0) / TILE))
		if m.has_method("solid_at_tile") and m.solid_at_tile(tx, ty):
			global_position = anchor


func _bleat() -> void:
	if _bleat_cd > 0.0:
		return
	_bleat_cd = 3.2
	AudioDirector.play_sfx("sheep", -14.0)


func _animate() -> void:
	# Two frames + a one-pixel bob. Head down while grazing, head up when the
	# animal has noticed anything, head up and moving when being driven home.
	var eating := (_t + _phase) < 0.0 or fmod(_t + _phase, 2.4) < 1.15
	if not _field_frames.is_empty():
		var stride := sin(_t * 9.0 + _phase)
		var frame := 0
		if mood == Mood.HERDED or mood == Mood.GOING_HOME or (mood == Mood.ALERT and _startle > 0.0):
			frame = 1 if stride > 0.25 else (2 if stride < -0.25 else 0)
		_sprite.texture = _field_frames[frame]
	elif mood == Mood.GRAZE and eating and _graze_bias > 0.3:
		_sprite.texture = _graze_tex
	elif mood == Mood.GRAZE:
		_sprite.texture = _up_tex
	else:
		_sprite.texture = _alert_tex
	_sprite.position.y = sin(_t * 5.2 + _phase) * 0.6
	if mood == Mood.HERDED or mood == Mood.GOING_HOME:
		var to_fold := fold - global_position
		_sprite.flip_h = to_fold.x < 0.0
	elif mood == Mood.ALERT and player != null:
		_sprite.flip_h = player.global_position.x > global_position.x


## Region asks this each frame instead of collecting by distance alone: a sheep
## that has just shied away is not caught in the same instant. It settles after
## STARTLE_SECS, so approaching from the "wrong" side is feedback, not a wall.
func wants_catch(d: float, rng: float) -> bool:
	if _leaving or d >= rng:
		return false
	return _startle <= 0.0


## Walk into the fold instead of blinking out of the world. The pickup flag and
## the HUD counter have already been updated by Region; this is only the picture.
func go_home() -> void:
	if _leaving:
		return
	_leaving = true
	_sprite.texture = _alert_tex
	var tw := create_tween()
	# A visible answering hop precedes the return, even when already close to
	# the fold. The feet/shadow remain at the node, not baked into the art.
	tw.tween_property(_sprite, "position:y", -4.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sprite, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _field_route.is_valid():
		# The visible return uses the same routed footpath as a guided animal.
		# Limit the exit animation to 48 world units; the counter was saved at
		# the deliberate action, so no long walk blocks the chapter.
		var points: PackedVector2Array = _field_route.call(global_position, fold)
		var remaining := 48.0
		var prior := global_position
		for point in points:
			if remaining <= 0.01:
				break
			var distance := prior.distance_to(point)
			if distance < 0.01:
				continue
			var length := minf(distance, remaining)
			var target := prior.move_toward(point, length)
			if not _field_segment_clear(prior, target):
				break
			tw.tween_property(self, "global_position", target, length / 100.0)
			prior = target
			remaining -= length
	else:
		var target := fold if (fold - global_position).length() < 64.0 \
			else global_position + (fold - global_position).normalized() * 48.0
		tw.tween_property(self, "global_position", target, 0.38)
	tw.tween_property(_sprite, "modulate:a", 0.0, 0.16)
	tw.tween_callback(queue_free)
