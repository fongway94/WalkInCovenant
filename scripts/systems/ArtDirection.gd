extends RefCounted
class_name ArtDirection
## One shared initial theme for the chapter on Web, desktop and Android.
## The user-selected painterly direction is the working production default;
## it does not change saves, collision or story state. Classic remains an
## explicit reversible theme for comparisons and regression coverage.

const DEFAULT_THEME := "cinematic"
## Painted prop PNGs are rebuilt from their sources at this multiple of their
## former canvas density. Divide visual scales by it; gameplay stays in world
## units and classic/storybook assets are unaffected.
const PAINTED_PROP_DETAIL_FACTOR := 3.0


static func current() -> String:
	return DEFAULT_THEME
