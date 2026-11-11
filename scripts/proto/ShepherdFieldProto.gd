extends Node2D
## Isolated art prototype: a playable shepherd field on the edited reference
## backdrop. No production scene loads this file. Coordinates are BACKDROP
## pixels: the 1440x666 picture sits at the origin at scale 1, so obstacles and
## sheep homes are measured on the painting itself.

const BG_PATH := "res://art/proto/shepherd_field_empty.png"
const FG_PATH := "res://art/proto/shepherd_field_fg_cutout.png"
const UPPER_TREE_PATH := "res://art/proto/shepherd_field_upper_tree.png"
const UPPER_FENCE_PATH := "res://art/proto/shepherd_field_upper_fence.png"
const TREE_GROUND_Y := 202.0
const FENCE_GROUND_Y := 268.0
const TREE_DEPTH_Z := 1
const FENCE_DEPTH_Z := 3
# Clip transparent horizontal margins, but preserve the full backdrop height
# and the same world origin. Bounds contain the masks and fall on 20px units.
const TREE_DEPTH_REGION := Rect2(880, 0, 380, 666)
const FENCE_DEPTH_REGION := Rect2(840, 0, 140, 666)
const DAVID_BODY_PATH := "res://art/proto/sprites/david_reference_body.png"
const DAVID_LEFT_BOOT_PATH := "res://art/proto/sprites/david_reference_boot_left.png"
const DAVID_RIGHT_BOOT_PATH := "res://art/proto/sprites/david_reference_boot_right.png"
# Each variant contains the still reference pose and two subtle baked strides.
# The frames share one canvas/anchor, so switching adds no extra sprite draws.
const SHEEP_PATHS := [
	[
		"res://art/proto/sprites/sheep_reference_a.png",
		"res://art/proto/sprites/sheep_reference_a_stride_a.png",
		"res://art/proto/sprites/sheep_reference_a_stride_b.png",
	],
	[
		"res://art/proto/sprites/sheep_reference_b.png",
		"res://art/proto/sprites/sheep_reference_b_stride_a.png",
		"res://art/proto/sprites/sheep_reference_b_stride_b.png",
	],
]
const WORLD := Rect2(0, 0, 1440, 666)
# The actor art is hand-matted from the approved reference and enlarged with
# nearest-neighbour sampling to suit the edited 1440px backdrop. In the
# reference, sheep are about half the shepherd's height, not white stickers.
const DAVID_SCALE := 1.0
const SHEEP_SCALE := 0.66
# 640 logical pixels across, showing roughly 1,164 world pixels. The window
# is still free to resize; the painting, collisions and actors stay in world
# space. 320 is supported for the CI resolution comparison only.
const PROTO_WIDTH := 640
const CAMERA_ZOOM := 0.55
const DAVID_SPEED := 70.0
const SHEEP_WALK := 14.0
const SHEEP_FLEE := 40.0
# Keep a taller visual clearance behind David: otherwise a northward sheep
# overlaps his head even though their feet are 60-70 world pixels apart.
const SHEEP_FLEE_X := 70.0
const SHEEP_FLEE_Y := 105.0
const INTERACT_RANGE := 76.0
const FIELD := Rect2(330, 150, 760, 400)
const SHEEP_HOMES := [
	Vector2(700, 300), Vector2(790, 400), Vector2(620, 470),
	Vector2(880, 440), Vector2(960, 330), Vector2(560, 380),
]
## Solid obstacles as [x, y, w, h] in backdrop pixels: walls, trunks, fence, rocks.
const OBSTACLES := [
	[0, 0, 300, 58],
	[430, 0, 1010, 60],
	[1408, 0, 32, 666],
	[0, 530, 200, 136],
	[1008, 150, 74, 52],
	[1082, 170, 26, 32],
	[1154, 165, 25, 28],
	[1080, 350, 130, 150],
	[856, 226, 120, 42],
	[618, 230, 34, 22],
	[524, 290, 34, 22],
	[566, 422, 34, 22],
	[594, 538, 34, 22],
	[672, 540, 34, 22],
	[1196, 560, 34, 22],
]

var david: CharacterBody2D
var david_sprite: Sprite2D
var david_boot_left: Sprite2D
var david_boot_right: Sprite2D
var camera: Camera2D
var hud_panel: PanelContainer
var sheep: Array = []
var counted := 0
var label: Label
var _t := 0.0
var _browser_probe := false
var _browser_full_depth := false
var _browser_probe_start_x := 0.0


func _ready() -> void:
	# These flags are supplied only by the temporary CI Web launcher.
	var launch_args := OS.get_cmdline_user_args()
	_browser_probe = OS.has_feature("web") and launch_args.has("--prototype-browser-probe")
	_browser_full_depth = _browser_probe and launch_args.has("--prototype-full-depth")
	seed(42)
	y_sort_enabled = true
	var bg := Sprite2D.new()
	bg.name = "Backdrop"
	bg.texture = load(BG_PATH) as Texture2D
	bg.centered = false
	bg.z_index = -100
	add_child(bg)
	_build_obstacles()
	_build_depth_layer("UpperTreeDepth", UPPER_TREE_PATH, TREE_DEPTH_Z, TREE_DEPTH_REGION)
	_build_depth_layer("FenceDepth", UPPER_FENCE_PATH, FENCE_DEPTH_Z, FENCE_DEPTH_REGION)
	_build_david()
	for i in range(SHEEP_HOMES.size()):
		_add_sheep(SHEEP_HOMES[i], i)
	var fg := Sprite2D.new()
	fg.texture = load(FG_PATH) as Texture2D
	fg.centered = false
	# The image is a cropped, alpha-matted foreground beginning at world y=250.
	fg.position = Vector2(0, 250)
	fg.z_index = 100
	add_child(fg)
	_build_hud()
	# Normal gameplay always starts at 640 logical pixels, with no test marker.
	var width := PROTO_WIDTH
	if _browser_probe and launch_args.has("--prototype-width=320"):
		width = 320
	set_prototype_resolution(width)
	if _browser_probe:
		_browser_probe_start_x = david.position.x
		var full_flag := "true" if _browser_full_depth else "false"
		JavaScriptBridge.eval("window.__prototypeReady = %d; window.__prototypeFullDepth = %s; window.__prototypeMoved = false;" % [width, full_flag], true)


func _build_obstacles() -> void:
	for r in OBSTACLES:
		var body := StaticBody2D.new()
		body.position = Vector2(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(float(r[2]), float(r[3]))
		shape.shape = rect
		body.add_child(shape)
		add_child(body)


func _build_depth_layer(layer_name: String, path: String, depth_z: int, region: Rect2) -> void:
	# The texture has the backdrop's world size. Clipping only transparent x
	# margins reduces overdraw; the sprite remains at world origin and draws at
	# the region's world coordinates. Full height retains the backdrop's y quad.
	# The frame harness checks that snapped sampling still matches the backdrop.
	# Actors select z bands using their feet; y-sort orders actors in each band.
	var image := Sprite2D.new()
	image.name = layer_name
	image.texture = load(path) as Texture2D
	image.centered = false
	# The temporary browser benchmark can select the previous full-quad path
	# for a same-runner A/B; ordinary prototype play always uses the region.
	if not _browser_full_depth:
		image.region_enabled = true
		image.region_rect = region
		image.offset = region.position
	image.z_index = depth_z
	add_child(image)


func _update_actor_depth(actor: Node2D) -> void:
	if actor.position.y >= FENCE_GROUND_Y:
		actor.z_index = FENCE_DEPTH_Z + 1
	elif actor.position.y >= TREE_GROUND_Y:
		actor.z_index = TREE_DEPTH_Z + 1
	else:
		actor.z_index = TREE_DEPTH_Z - 1


func _build_david() -> void:
	david = CharacterBody2D.new()
	david.position = Vector2(700, 470)
	_update_actor_depth(david)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	shape.position = Vector2(0, -6)
	david.add_child(shape)
	david.add_child(_shadow(16.0))
	# Boot layers are cut from the same reference pixels as the body. They
	# reconstruct the still pose at rest and stride gently while moving.
	david_boot_left = _david_part(DAVID_LEFT_BOOT_PATH)
	david_boot_right = _david_part(DAVID_RIGHT_BOOT_PATH)
	david.add_child(david_boot_left)
	david.add_child(david_boot_right)
	david_sprite = _david_part(DAVID_BODY_PATH)
	david.add_child(david_sprite)
	camera = Camera2D.new()
	var cam := camera
	cam.zoom = Vector2.ONE * CAMERA_ZOOM
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = 1440
	cam.limit_bottom = 666
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	david.add_child(cam)
	add_child(david)
	cam.make_current()


func _david_part(path: String) -> Sprite2D:
	var part := Sprite2D.new()
	var tex := load(path) as Texture2D
	part.texture = tex
	part.scale = Vector2.ONE * DAVID_SCALE
	# A centered sprite's origin is already at its centre. Its bottom centre
	# belongs at the physics body's feet/contact shadow.
	part.offset = Vector2(0, -tex.get_height() * 0.5)
	return part


func _add_sheep(home: Vector2, variant: int) -> void:
	var node := Node2D.new()
	node.position = home
	_update_actor_depth(node)
	node.add_child(_shadow(16.0))
	var spr := Sprite2D.new()
	var frames: Array[Texture2D] = []
	for path in SHEEP_PATHS[variant % SHEEP_PATHS.size()]:
		frames.append(load(path) as Texture2D)
	var tex: Texture2D = frames[0]
	spr.texture = tex
	spr.scale = Vector2.ONE * SHEEP_SCALE
	spr.offset = Vector2(0, -tex.get_height() * 0.5)
	node.add_child(spr)
	add_child(node)
	sheep.append({"node": node, "sprite": spr, "frames": frames, "home": home, "target": home,
		"idle": 1.0, "hop": 0.0, "counted": false, "phase": randf() * TAU})


func _shadow(radius: float) -> Node2D:
	var n := Node2D.new()
	n.name = "GroundShadow"
	# Keep this at the same z as the actor and add it BEFORE the sprite: a
	# negative z places it behind the opaque backdrop, not just behind feet.
	n.draw.connect(_draw_shadow.bind(n, radius))
	n.queue_redraw()
	return n


func _draw_shadow(n: Node2D, radius: float) -> void:
	# The reference's sunlight comes from the upper left; its long shadows
	# travel down and right. A soft cool cast and a darker, smaller contact
	# ellipse share the actor's real ground position.
	n.draw_set_transform(Vector2(radius * 0.75, radius * 0.20), 0.14, Vector2(1.8, 0.32))
	n.draw_circle(Vector2.ZERO, radius, Color(0.07, 0.09, 0.11, 0.13))
	n.draw_set_transform(Vector2(radius * 0.55, radius * 0.15), 0.14, Vector2(1.35, 0.24))
	n.draw_circle(Vector2.ZERO, radius, Color(0.07, 0.08, 0.10, 0.17))
	n.draw_set_transform(Vector2(0, 0), 0.0, Vector2(0.85, 0.24))
	n.draw_circle(Vector2.ZERO, radius, Color(0.05, 0.055, 0.06, 0.48))


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_panel = PanelContainer.new()
	hud_panel.anchor_left = 1.0
	hud_panel.anchor_right = 1.0
	hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.09, 0.74)
	style.border_color = Color(0.73, 0.61, 0.39, 0.32)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	hud_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(hud_panel)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color(0.96, 0.89, 0.72))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.06, 0.95))
	hud_panel.add_child(label)
	_refresh_hud()


func _refresh_hud() -> void:
	label.text = "Flock %d/%d  |  Space" % [counted, sheep.size()]


## Local to this isolated scene; does not edit project.godot or production UI.
## CI switches between these sizes without changing camera framing to compare
## actual render detail and text. Canvas-items stretch still uses the window.
func set_prototype_resolution(width: int) -> void:
	var factor := float(width) / 640.0
	get_tree().root.content_scale_size = Vector2i(width, int(float(width) * 9.0 / 16.0))
	camera.zoom = Vector2.ONE * CAMERA_ZOOM * factor
	hud_panel.offset_left = -164.0 * factor
	hud_panel.offset_right = -10.0 * factor
	hud_panel.offset_top = 9.0 * factor
	hud_panel.offset_bottom = 33.0 * factor
	label.add_theme_font_size_override("font_size", maxi(6, roundi(12.0 * factor)))
	label.add_theme_constant_override("outline_size", maxi(1, roundi(2.0 * factor)))


func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	david.velocity = dir * DAVID_SPEED
	david.move_and_slide()
	david.position = david.position.clamp(WORLD.position, WORLD.end)
	_update_actor_depth(david)
	if _browser_probe and absf(david.position.x - _browser_probe_start_x) > 20.0:
		JavaScriptBridge.eval("window.__prototypeMoved = true;", true)
		_browser_probe = false
	if dir.length() > 0.1:
		var stride := sin(_t * 9.0)
		david_sprite.position.y = -absf(stride) * 0.6
		david_boot_left.position = Vector2(stride * 2.0, -maxf(0.0, stride) * 1.2)
		david_boot_right.position = Vector2(-stride * 2.0, -maxf(0.0, -stride) * 1.2)
	else:
		david_sprite.position = Vector2.ZERO
		david_boot_left.position = Vector2.ZERO
		david_boot_right.position = Vector2.ZERO


func _process(delta: float) -> void:
	_t += delta
	for s in sheep:
		_update_sheep(s, delta)


func _update_sheep(s: Dictionary, delta: float) -> void:
	var node: Node2D = s["node"]
	var spr: Sprite2D = s["sprite"]
	var vel := Vector2.ZERO
	var away: Vector2 = node.position - david.position
	var clearance := Vector2(away.x / SHEEP_FLEE_X, away.y / SHEEP_FLEE_Y)
	if clearance.length() < 1.0:
		vel = (away.normalized() if away.length() > 0.5 else Vector2.RIGHT) * SHEEP_FLEE
		s["idle"] = 0.0
	elif float(s["idle"]) > 0.0:
		s["idle"] = float(s["idle"]) - delta
	else:
		var to_target: Vector2 = s["target"] - node.position
		if to_target.length() < 2.0:
			s["target"] = _random_home(s["home"])
			s["idle"] = randf_range(1.2, 3.0)
		else:
			vel = to_target.normalized() * SHEEP_WALK
	var next_pos: Vector2 = node.position + vel * delta
	var moved := false
	if FIELD.has_point(next_pos) and not _blocked(next_pos):
		node.position = next_pos
		moved = vel.length_squared() > 0.01
	_update_actor_depth(node)
	if vel.x != 0.0:
		spr.flip_h = vel.x < 0.0
	var hop := float(s["hop"])
	var bob := 0.0
	var frame_index := 0
	if hop > 0.0:
		s["hop"] = hop - delta
		var k := clampf(1.0 - hop / 0.6, 0.0, 1.0)
		bob = -sin(k * PI) * 10.0
	elif moved:
		var stride := sin(_t * 9.0 + float(s["phase"]))
		bob = -absf(stride) * 1.2
		if stride > 0.25:
			frame_index = 1
		elif stride < -0.25:
			frame_index = 2
	else:
		bob = sin(_t * 1.8 + float(s["phase"])) * 0.4
	# The original pose is retained during idle, blocking and a hop. The two
	# walking textures move only the reference's feet, with a shared anchor.
	var frames: Array = s["frames"]
	if spr.texture != frames[frame_index]:
		spr.texture = frames[frame_index]
	spr.position = Vector2(0, bob)


func _random_home(home: Vector2) -> Vector2:
	return home + Vector2(randf_range(-30.0, 30.0), randf_range(-18.0, 18.0))


func _blocked(p: Vector2) -> bool:
	for r in OBSTACLES:
		if Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).grow(4.0).has_point(p):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		interact()
		get_viewport().set_input_as_handled()


## Space beside a sheep: it hops, and the first time it counts toward the flock.
func interact() -> bool:
	var best: Dictionary = {}
	var best_d := INTERACT_RANGE
	for s in sheep:
		var d: float = (s["node"] as Node2D).position.distance_to(david.position)
		if d < best_d:
			best_d = d
			best = s
	if best.is_empty():
		return false
	best["hop"] = 0.6
	if not best["counted"]:
		best["counted"] = true
		counted += 1
	_refresh_hud()
	return true


func set_david(p: Vector2) -> void:
	david.position = p
	david.velocity = Vector2.ZERO
	_update_actor_depth(david)


func nearest_sheep_pos() -> Vector2:
	return (sheep[0]["node"] as Node2D).position
