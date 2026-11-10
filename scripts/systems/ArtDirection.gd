extends RefCounted
class_name ArtDirection
## ArtDirection — one decision for the whole working-branch preview.
##
## The user chose Direction B ("cinematic") but also asked to keep the current
## animation. Classic remains the shipped default in source, desktop, headless
## suites and the Xvfb visual harness. Only the Web export served from the
## WORKING BRANCH Pages preview starts in B; the visual harness can still call
## Main.apply_art_theme() explicitly for its own comparison frames.
##
## This is a runtime theme, not a default-asset replacement. Setting the
## constant back to "classic" restores every screen. No autoload, save data,
## gameplay or animation state lives here.

const WEB_PREVIEW_THEME := "cinematic"


static func current() -> String:
	# Godot's Web exports expose the "web" feature; Xvfb/headless do not.
	# Main.gd already used the same check to bring B to the live preview after
	# the user's "why still same" screenshot. Sharing it here keeps the duel,
	# the drill and the brook from falling back to classic while the overworld
	# is golden hour.
	if OS.has_feature("web"):
		return WEB_PREVIEW_THEME
	return "classic"
