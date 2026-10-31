extends RefCounted
class_name CampaignModel
## CampaignModel — the platform registry.
##
## Everything that makes one Bible story playable already lives in data:
## `data/regions/<id>.json` holds the map, the cast, the verses, the shouts, the
## ending and (for a story that has one) the errand. What was NOT in data was
## which story the game is playing. That one string was hardcoded in Main.gd.
##
## This is the seam that makes campaign #2 content instead of code: point a
## campaign at a region file, and the shared machinery — witness mode, escort,
## BECOME, word battle, HUD, save — runs it. A story that needs a mechanic
## nothing else has (Moses parting water) adds its own scene like GoliathFight,
## and the shared layer never learns its name.

const PATH := "res://data/campaigns.json"


static func load_all() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var list: Array = (parsed as Dictionary).get("campaigns", [])
	list.sort_custom(func(a, b): return int(a.get("order", 99)) < int(b.get("order", 99)))
	return list


static func by_id(id: String) -> Dictionary:
	for c in load_all():
		if str(c.get("id", "")) == id:
			return c
	return {}


## The campaign this save is playing. Falls back to the first registered one so
## a save written before the registry existed still boots.
static func current() -> Dictionary:
	var id := ""
	if GameState != null and GameState.data.has("campaign"):
		id = str(GameState.data["campaign"])
	var c := by_id(id) if id != "" else {}
	if c.is_empty():
		var all := load_all()
		c = all[0] if not all.is_empty() else {}
	return c


## The region file the current campaign runs in. This is the only thing Main
## has to ask the platform.
static func current_region() -> String:
	var c := current()
	return str(c.get("region", "elah"))


static func current_hero() -> String:
	var c := current()
	return str(c.get("hero", "david"))


## Mixed case, for the HUD nameplate.
static func current_hero_name() -> Dictionary:
	var c := current()
	var nm: Dictionary = c.get("hero_name", {})
	if nm.is_empty():
		return {"en": "David", "zh": "大卫"}
	return nm


## Upper case, for the BECOME plate that fills the screen.
static func current_hero_plate() -> Dictionary:
	var c := current()
	var nm: Dictionary = c.get("hero_name", {})
	if nm.is_empty():
		return {"en": "DAVID", "zh": "大卫"}
	return {"en": str(nm.get("en", "DAVID")).to_upper(), "zh": str(nm.get("zh", "大卫"))}
