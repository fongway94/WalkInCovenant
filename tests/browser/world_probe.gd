extends Node
## Test-only camera staging for inspecting the real painted overworld. It does
## not prove progression: it starts a fresh game and places the player near a
## named landmark. Keyboard/touch movement still uses the production handlers.

var main = null
var ready_for_probe := false
var place := "camp"
var poll := 0.0


func _ready() -> void:
	if OS.has_feature("web"):
		var param = JavaScriptBridge.eval("new URLSearchParams(location.search).get('place')", true)
		if param != null:
			place = str(param)
	GameState.new_game()
	GameState.data["settings"]["reduce_motion"] = true
	if place == "bethlehem" or place == "well":
		GameState.data["region"] = "bethlehem"
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	# Most locations are visual-only, but the first-sight probe deliberately
	# leaves Main and Region's real trigger path enabled for an actual camera pan.
	if place != "sight":
		main.set_process(false)
		main.region.triggers.clear()
		main.region.model.curios.clear()
	await get_tree().process_frame
	var tile: Vector2i = main.region.model.spawn
	match place:
		"brook": tile = Vector2i(16, 27)
		"crossing": tile = Vector2i(16, 24)
		"ridge": tile = Vector2i(16, 9)
		"sight": tile = Vector2i(16, 17)
		"bethlehem": tile = Vector2i(16, 8)
		"well": tile = Vector2i(10, 19)
	main._place_at([tile.x, tile.y])
	main.region.player.velocity = Vector2.ZERO
	if place == "armour":
		# Visual fixture only: the real chapter turns this on after Saul's scene.
		main.region.player.setup(main.region.model, "david")
		if OS.has_feature("web") and bool(JavaScriptBridge.eval(
				"new URLSearchParams(location.search).get('theme') === 'classic'", true)):
			main.apply_art_theme("classic")
		main.region.player.set_armour(true)
	main.region.set_paused(false)
	ready_for_probe = true
	_publish()


func _process(delta: float) -> void:
	if not ready_for_probe:
		return
	poll += delta
	if poll >= 0.10:
		poll = 0.0
		_publish()


func _publish() -> void:
	if not OS.has_feature("web") or main == null or main.region == null:
		return
	var r: Region = main.region
	var p: Player = r.player
	var rig = p.david_visual if p.david_visual != null and p.david_visual.visible else p.human_visual
	# Read-only telemetry for naturally occurring ambient chatter. The fixture
	# does not trigger an emote or replace its normal cooldown and placement.
	var bubbles: Array = []
	for person in r.npcs:
		if person._bubble == null or not person._bubble.visible:
			continue
		var canvas := person.get_global_transform_with_canvas()
		var top_left: Vector2 = canvas * person._bubble.position
		var extent := Vector2(canvas.x.length() * person._bubble.size.x,
			canvas.y.length() * person._bubble.size.y)
		var label: Label = person._bubble_lbl
		var body: Rect2 = person._speaker_canvas_rect(canvas)
		var player_body: Rect2 = person._player_canvas_rect()
		var text_width := label.get_theme_font("font").get_string_size(label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		bubbles.append({"id": person.npc_id(), "text": label.text,
			"page": person._bubble_page, "pages": person._bubble_pages.size(),
			"rect": [top_left.x, top_left.y, extent.x, extent.y],
			"speaker_rect": [body.position.x, body.position.y, body.size.x, body.size.y],
			"player_rect": [player_body.position.x, player_body.position.y, player_body.size.x, player_body.size.y],
			"text_width": text_width, "label_width": label.size.x,
			"panel_width": person._bubble.size.x})
	var language_rect: Rect2 = main.hud.lang_btn.get_global_rect()
	var status := {"ready": ready_for_probe, "place": place, "region": r.region_id,
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"language": I18n.lang,
		"language_button": [language_rect.position.x, language_rect.position.y,
			language_rect.size.x, language_rect.size.y],
		"bubbles": bubbles,
		"player": [p.global_position.x, p.global_position.y],
		"facing": [p.facing.x, p.facing.y], "moving": p.mode == Player.Mode.MOVING,
		"pose": str(rig._pose_name) if rig != null else "",
		"flip": bool(rig.body.flip_h) if rig != null else false,
		"armour": p.armour, "armour_visible": p.armour_visual != null and p.armour_visual.visible,
		"armour_painted": p.armour_visual.painted if p.armour_visual != null else false,
		"stagger": p.sprite.offset.x,
		"painted_ground": r.terrain.painted_ground != null,
		"dialogue": r.dialogue.is_open(), "paused": r.is_paused(),
		"first_sight": bool(GameState.flag("elah_saw_him")),
		"camera": [r.cam.global_position.x, r.cam.global_position.y],
		"cinematic_camera": r.cam._cine}
	JavaScriptBridge.eval("window.__worldProbe=" + JSON.stringify(status) + ";", true)
