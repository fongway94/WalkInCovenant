extends Node
## GameState — the save. Everything the player earns lives here.
##
## Schema is deliberately compatible in spirit with Covenant v0.9.38's
## localStorage save so SaveMigrator can honour old players' journeys.
##
## The four virtues and the four "ways of walking" are separate on purpose.
## Virtues are raised by choices; ways are *observed behaviour* (step / notice /
## stay / wait) that feed the Journey Mirror. And hint usage is tracked apart
## from both — see EventBus.gd — so the Mirror stays honest.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

const VIRTUES := ["courage", "wisdom", "compassion", "faith"]
const WAYS := ["step", "notice", "stay", "wait"]
const VIRTUE_MAX := 12

var data: Dictionary = {}


func _ready() -> void:
	new_game()
	load_game()


func new_game() -> void:
	data = {
		"version": SAVE_VERSION,
		"name": "pilgrim",
		"calling": "shepherd",
		"level": 1,
		"xp": 0,
		"stats": {"courage": 1, "wisdom": 1, "compassion": 1, "faith": 1},
		"ways": {"step": 0, "notice": 0, "stay": 0, "wait": 0},
		"hints_used": 0,
		"guidance": 0,
		"relics": [],
		"fruits": [],
		"seals": [],
		"completed": [],
		"flags": {},
		"words": [],            # verses handed over by people on the road
		"quests": {},           # quest_id -> {objectives:[], done:bool}
		"region": "elah",
		"campaign": "elah",     # which entry in data/campaigns.json this save plays
		"pos": [0, 0],
		"day": 1,
		"time_of_day": "morning",
		"settings": {"clean_mode": true, "sound": true, "music": true, "reduce_motion": false},
	}


# ── marks ────────────────────────────────────────────────────────────────
const SEALS_PATH := "res://data/achievements.json"
static var _seal_titles: Dictionary = {}


## A mark, granted once, announced once. The titles are content (data), the rule
## is here (platform), so campaign 02 can hand out its own without a script.
func grant_seal(id: String) -> bool:
	if id == "" or data["seals"].has(id):
		return false
	data["seals"].append(id)
	if _seal_titles.is_empty():
		_load_seal_titles()
	var t: Dictionary = _seal_titles.get(id, {})
	if not t.is_empty():
		EventBus.toast_requested.emit(I18n.t({
			"en": "Mark · %s", "zh": "记号 · %s"}) % I18n.t(t))
	return true


func seal_title(id: String) -> Dictionary:
	if _seal_titles.is_empty():
		_load_seal_titles()
	return _seal_titles.get(id, {})


func _load_seal_titles() -> void:
	_seal_titles = {}
	if not FileAccess.file_exists(SEALS_PATH):
		return
	var f := FileAccess.open(SEALS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for s in (parsed as Dictionary).get("seals", []):
		_seal_titles[str(s.get("id", ""))] = s.get("title", {})


# ── virtues & ways ───────────────────────────────────────────────────────
func add_virtue(v: String, amount: int) -> void:
	if v not in VIRTUES:
		return
	var old: int = data["stats"].get(v, 0)
	var nv := clampi(old + amount, 0, VIRTUE_MAX)
	data["stats"][v] = nv
	EventBus.virtue_changed.emit(v, nv)


func record_way(w: String) -> void:
	if w not in WAYS:
		return
	data["ways"][w] = int(data["ways"][w]) + 1
	EventBus.way_recorded.emit(w)


func record_hint() -> void:
	# Deliberately NOT a way. The Mirror must reflect unaided choices.
	data["hints_used"] = int(data["hints_used"]) + 1
	EventBus.hint_used.emit()


# ── progression ──────────────────────────────────────────────────────────
func xp_needed(level: int) -> int:
	return 40 + (level - 1) * 30


func add_xp(amount: int) -> void:
	data["xp"] = int(data["xp"]) + amount
	EventBus.xp_gained.emit(amount)
	while data["xp"] >= xp_needed(data["level"]):
		data["xp"] -= xp_needed(data["level"])
		data["level"] += 1
		EventBus.level_changed.emit(data["level"])


func grant_relic(id: String) -> void:
	if id not in data["relics"]:
		data["relics"].append(id)
		EventBus.relic_granted.emit(id)


func gather_fruit(id: String) -> void:
	if id not in data["fruits"]:
		data["fruits"].append(id)
		EventBus.fruit_gathered.emit(id)


func earn_seal(id: String) -> void:
	if id not in data["seals"]:
		data["seals"].append(id)
		EventBus.seal_earned.emit(id)


func add_guidance(n: int) -> void:
	data["guidance"] = maxi(0, int(data["guidance"]) + n)
	EventBus.guidance_changed.emit(data["guidance"])


func receive_word(id: String, ref: String) -> void:
	if id not in data["words"]:
		data["words"].append(id)
		EventBus.verse_received.emit(id, ref)


func complete_chapter(id: String) -> void:
	if id not in data["completed"]:
		data["completed"].append(id)
		EventBus.chapter_completed.emit(id)


func set_flag(key: String, value: Variant = true) -> void:
	data["flags"][key] = value
	EventBus.settings_changed.emit("flag:" + key, value)


func flag(key: String, default: Variant = false) -> Variant:
	return data["flags"].get(key, default)


# ── quests ───────────────────────────────────────────────────────────────
func quest_start(id: String, objectives: Array) -> void:
	if data["quests"].has(id):
		return
	data["quests"][id] = {"objectives": objectives.duplicate(), "met": [], "done": false}
	EventBus.quest_started.emit(id)


func quest_meet(id: String, objective: String) -> void:
	var q: Dictionary = data["quests"].get(id, {})
	if q.is_empty() or objective in q.get("met", []):
		return
	q["met"].append(objective)
	EventBus.quest_objective_met.emit(id, objective)
	if q["met"].size() >= q["objectives"].size():
		q["done"] = true
		EventBus.quest_completed.emit(id)


# ── persistence ──────────────────────────────────────────────────────────
func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("GameState: could not open %s for writing" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	EventBus.game_saved.emit()


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return false
	# merge over defaults so a save from an older version still has every key
	for k in data:
		if parsed.has(k):
			data[k] = parsed[k]
	EventBus.game_loaded.emit()
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func erase() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	new_game()
