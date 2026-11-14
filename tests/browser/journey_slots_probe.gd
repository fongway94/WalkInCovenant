extends Node
## TEST-ONLY. A query seeds one completed save; after that every button, save,
## reload and conversation goes through the actual game. Never ship this scene.

var main = null
var boot := 0
var poll := 0.0


func _ready() -> void:
	if OS.has_feature("web"):
		var seed := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('seed') || ''", true))
		if seed == "complete":
			GameState.erase()
			GameState.data["settings"]["reduce_motion"] = true
			GameState.data["level"] = 3
			GameState.data["words"] = ["original_keepsake"]
			GameState.data["progress"] = {"act": "done", "stones": 5, "pos": [16, 44]}
			GameState.set_flag("elah_ended", true)
			GameState.set_flag("goliath_down", true)
			GameState.set_flag("original_keepsake", true)
			GameState.save_game()
		elif seed == "corrupt":
			GameState.erase()
			var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
			file.store_string("original-needs-recovery")
			file.close()
			GameState._load_selected_on_startup()
		if seed != "":
			# Scene and page reloads must not re-seed or delete either slot.
			JavaScriptBridge.eval("history.replaceState(null, '', location.pathname)", true)
		boot = int(JavaScriptBridge.eval("window.__journeyBoot=(window.__journeyBoot||0)+1", true))
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	_publish()


func _process(delta: float) -> void:
	poll += delta
	if poll >= 0.08:
		poll = 0.0
		_publish()


func _rect(c: Control) -> Array:
	if c == null:
		return []
	var bounds := c.get_global_rect()
	return [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]


func _publish() -> void:
	if not OS.has_feature("web") or main == null or main.region == null:
		return
	var r: Region = main.region
	if r.player == null or r.dialogue == null or main.journal == null:
		return
	var body: Array = []
	for child in main.journal._body.get_children():
		if child is Label:
			body.append((child as Label).text)
	var status := {
		"ready": true, "boot": boot, "slot": GameState.active_slot,
		"has_replay": GameState.has_replay(), "act": main.act_id(),
		"save_protected": GameState.save_protected(),
		"corrupt_original_intact": FileAccess.file_exists(GameState.SAVE_PATH) \
			and FileAccess.get_file_as_string(GameState.SAVE_PATH) == "original-needs-recovery",
		"runner_running": main.runner.running,
		"region": r.region_id, "player": [r.player.global_position.x, r.player.global_position.y],
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"objective": main.hud.objective_lbl.text,
		"language": I18n.lang, "journal_open": main.journal.is_open(),
		"confirming": main.journal._confirming, "journey_error": main.journal._journey_error,
		"journal_button": _rect(main.hud.journal_btn),
		"language_button": _rect(main.hud.lang_btn),
		"sound_button": _rect(main.hud.sound_btn), "sound_text": main.hud.sound_btn.text,
		"sound_enabled": bool(GameState.data["settings"].get("sound", true)),
		"music_enabled": bool(GameState.data["settings"].get("music", true)),
		"focus_muted": AudioDirector._muted_by_focus,
		"sfx_bus_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),
		"music_bus_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),
		"journey_button": _rect(main.journal._journey_btn),
		"close_button": _rect(main.journal._close_btn),
		"journey_text": main.journal._journey_btn.text,
		"journey_disabled": main.journal._journey_btn.disabled, "book_body": body,
		"dialogue": r.dialogue.is_open(), "target_kind": str(r.context_target().get("kind", "")),
		"talked_corin": bool(GameState.flag("talked:elah:corin")),
		"original_keepsake": bool(GameState.flag("original_keepsake")),
		"ended": bool(GameState.flag("elah_ended")),
		"level": int(GameState.data.get("level", 0)), "words": GameState.data.get("words", []),
		"progress": GameState.data.get("progress", {}),
	}
	JavaScriptBridge.eval("window.__journeySlotsProbe=" + JSON.stringify(status) + ";", true)
