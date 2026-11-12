extends Node
## Staged browser inspection for the real setpieces. It does not exercise
## progression; input still runs through each actual setpiece's input handlers.

var scene = null
var kind := "duel"
var timer := 0.0
var done := false


func _ready() -> void:
	GameState.new_game()
	if OS.has_feature("web"):
		var param = JavaScriptBridge.eval("new URLSearchParams(location.search).get('scene')", true)
		if param != null:
			kind = str(param)
		var language = JavaScriptBridge.eval("new URLSearchParams(location.search).get('lang')", true)
		if language != null:
			I18n.set_lang(str(language))
	match kind:
		"practice":
			scene = SlingPractice.new()
			add_child(scene)
			scene.apply_art_theme("cinematic")
			scene.finished.connect(func(): done = true)
			scene.start(3)
		"brook":
			scene = StoneChoice.new()
			add_child(scene)
			scene.apply_art_theme("cinematic")
			scene.finished.connect(func(_count): done = true)
			scene.start(5, 9)
		_:
			kind = "duel"
			scene = GoliathFight.new()
			add_child(scene)
			scene.apply_art_theme("cinematic")
			scene.objective_text = I18n.t({"zh": "站住，迎战歌利亚。", "en": "Stand and face Goliath."})
			scene.finished.connect(func(): done = true)
			scene.start()
	_publish()


func _process(delta: float) -> void:
	if scene == null:
		return
	timer += delta
	if timer > 0.025:
		timer = 0.0
		_publish()


func _publish() -> void:
	if not OS.has_feature("web") or scene == null:
		return
	var status := {"ready": true, "kind": kind, "done": done,
		"tap_count": TapGate.count()}
	match kind:
		"practice":
			status["phase"] = int(scene.phase)
			status["marker"] = float(scene._marker)
			status["direction"] = float(scene._dir)
			status["band"] = float(scene._band)
			status["hits"] = int(scene.hits)
			status["misses"] = int(scene.misses)
			status["message"] = str(scene._msg)
		"brook":
			status["chosen"] = int(scene.chosen_count())
			status["full"] = bool(scene.is_full())
			status["language"] = I18n.lang
			status["message"] = str(scene._msg) if scene._msg_t > 0.0 else ""
			var view: Vector2 = scene._layer.size
			var panel: Rect2 = scene._message_backdrop(view, str(scene._msg), ThemeDB.fallback_font)
			var hint: Rect2 = scene._hint_backdrop(view, scene._hint_text(), ThemeDB.fallback_font)
			status["viewport"] = [view.x, view.y]
			status["message_rect"] = [panel.position.x, panel.position.y, panel.size.x, panel.size.y]
			status["hint_rect"] = [hint.position.x, hint.position.y, hint.size.x, hint.size.y]
		_:
			status["phase"] = int(scene.phase)
			status["marker"] = float(scene._marker)
			status["band"] = float(scene._band)
			status["hits"] = int(scene.hits)
			status["strike"] = float(scene._strike)
			status["nerve"] = int(scene.nerve)
			status["stones"] = int(scene.stones)
	JavaScriptBridge.eval("window.__setpieceProbe=" + JSON.stringify(status) + ";", true)
