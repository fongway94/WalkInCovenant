extends RefCounted
class_name ArtDirection
## One shared initial theme for the chapter on Web, desktop and Android.
## The user-selected painterly direction is the working production default;
## it does not change saves, collision or story state. Classic remains an
## explicit reversible theme for comparisons and regression coverage.

const DEFAULT_THEME := "cinematic"


static func current() -> String:
	return DEFAULT_THEME
