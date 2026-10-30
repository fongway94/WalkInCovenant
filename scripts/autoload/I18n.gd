extends Node
## I18n — language state. Chinese is the DEFAULT, English the toggle.
##
## This is Covenant's existing choice and it does not change: the author writes
## in Chinese and the first audiences are Chinese-speaking churches.
##
## Chapter content does NOT go through TranslationServer. It lives as inline
## {"en":…, "zh":…} pairs inside data/**/*.json so a line of dialogue always sits
## next to its translation — that is what makes pastoral review possible.
## TranslationServer (CSV) is reserved for UI chrome only.

signal language_changed(lang: String)

const LANGS := ["zh", "en"]
var lang: String = "zh"


func _ready() -> void:
	var saved := get_meta("lang", "")
	if saved in LANGS:
		lang = saved
	TranslationServer.set_locale(lang)


func t(d: Variant) -> String:
	"""Resolve an inline bilingual value. Accepts {"en":…,"zh":…}, a plain
	String, or null. Never crashes on malformed content — a broken line should
	show something, not take down a chapter."""
	if d == null:
		return ""
	if d is String:
		return d
	if d is Dictionary:
		if d.has(lang):
			return str(d[lang])
		for l in LANGS:
			if d.has(l):
				return str(d[l])
		return str(d.values()[0]) if not d.is_empty() else ""
	return str(d)


func is_zh() -> bool:
	return lang == "zh"


func set_lang(l: String) -> void:
	if l not in LANGS or l == lang:
		return
	lang = l
	set_meta("lang", l)
	TranslationServer.set_locale(l)
	language_changed.emit(l)


func toggle() -> void:
	set_lang("en" if lang == "zh" else "zh")
