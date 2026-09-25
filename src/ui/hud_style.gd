class_name HudStyle
extends RefCounted

## What CS2's HUD looks like, in one place: its colours, its font and its
## icons, for every part of the HUD and the buy menu to draw with.
##
## The numbers are CS2's own, from the Panorama styles it ships (GameTracking-
## CS2, game/csgo/pak01_dir/panorama/styles/, 2026-09-23): csgostyles.css for
## the team colours and the blurred panels' tint, hud/hudhealthammocenter.css
## for the health and ammo cluster, hud/hudteamcounter.css for the top, and
## hud/hudmoney.css and hud/hudalerts.css for the money and the alert bar.
## Everything is laid out on the 1920x1080 base size; the stretch scales it.
##
## The HUD is washed in your team's colour (CS2's default cl_hud_color 0):
## gold for the terrorists, light blue for the counter-terrorists.
##
## CS2's font (Stratum2) and icons are Valve's, so they come only from the
## extraction (scripts/extract_assets.sh hud) into assets/hud/. Without them
## the HUD draws with Rajdhani (SIL Open Font License, src/ui/fonts/), the
## closest free face, and draws its own simple icons, so it looks right in
## shape everywhere and exactly right where CS2 is installed.

## csgostyles.css: t-color #eabe54, ct-color rgb(150, 200, 250).
const T_COLOUR := Color(0.9176, 0.7451, 0.3294)
const CT_COLOUR := Color(0.5882, 0.7843, 0.9804)
## The dark behind a blurred panel (hud-blur-bg-color #000000a0). CS2 blurs
## the world behind it too; this draws the tint alone.
const PANEL_TINT := Color(0, 0, 0, 0.627)
## A hit taking health (hudhealthammocenter.css 'on-damage', #DD0000).
const DAMAGE_RED := Color(0.8667, 0, 0)
## The buy zone's cart (hudmoney.css, wash-color lightgreen).
const BUY_GREEN := Color(0.5647, 0.9333, 0.5647)
## Teammates' colours, in the order CS2 hands them out
## (cl_teammate_color_1 to 5, convars.txt): blue, green, yellow, orange,
## purple.
const TEAMMATE_COLOURS: Array[Color] = [
	Color8(136, 206, 245), Color8(0, 158, 128), Color8(241, 228, 65),
	Color8(230, 128, 42), Color8(189, 44, 150),
]
const SHADOW := Color(0, 0, 0, 0.82)

const IMAGES := "res://assets/hud/panorama/images"
const FONTS := "res://assets/hud/fonts"
const FALLBACK_BOLD := "res://src/ui/fonts/Rajdhani-Bold.ttf"
const FALLBACK_MEDIUM := "res://src/ui/fonts/Rajdhani-SemiBold.ttf"

static var _fonts := {}
static var _icons := {}


static func team_colour(side: String) -> Color:
	return CT_COLOUR if side == "CT" else T_COLOUR


## The HUD's font: CS2's Stratum2 where it was extracted, bold or medium,
## else Rajdhani.
static func font(bold: bool = true) -> Font:
	var key := "bold" if bold else "medium"
	if not _fonts.has(key):
		var found := _extracted_font(bold)
		if found == null:
			found = load(FALLBACK_BOLD if bold else FALLBACK_MEDIUM) as Font
		_fonts[key] = found
	return _fonts[key]


## Whether CS2's own font is in use.
static func has_cs2_font() -> bool:
	return _extracted_font(true) != null


static func _extracted_font(bold: bool) -> Font:
	var dir := DirAccess.open(FONTS)
	if dir == null:
		return null
	var best := ""
	for file in dir.get_files():
		var lower := file.to_lower()
		if not (lower.ends_with(".ttf") or lower.ends_with(".otf")) or not lower.contains("stratum2"):
			continue
		if lower.contains("italic") or lower.contains("mono") or lower.contains("thin") or lower.contains("light"):
			continue
		var wanted := lower.contains("bold") if bold else (lower.contains("medium") or lower.contains("regular"))
		if wanted and (best.is_empty() or file.length() < best.length()):
			best = file
	return load(FONTS.path_join(best)) as Font if not best.is_empty() else null


## One of CS2's HUD images by its path under panorama/images, without the
## extension ("hud/health_cross", "icons/ui/buyzone"); null where it was not
## extracted, and the caller draws its own.
static func icon(path: String) -> Texture2D:
	if not _icons.has(path):
		var texture: Texture2D = null
		for extension in [".svg", ".png"]:
			var full := IMAGES.path_join(path + extension)
			if ResourceLoader.exists(full):
				texture = load(full) as Texture2D
				break
		_icons[path] = texture
	return _icons[path]


## An item's icon from CS2's equipment set ("weapon_ak47" is
## icons/equipment/ak47), or null.
static func item_icon(item_class: String) -> Texture2D:
	return icon("icons/equipment/" + item_class.trim_prefix("weapon_").trim_prefix("item_"))


## Draws `texture` fitted into `box`, keeping its shape, tinted.
static func draw_fitted(on: CanvasItem, texture: Texture2D, box: Rect2, tint: Color) -> void:
	var size := texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var scale := minf(box.size.x / size.x, box.size.y / size.y)
	var drawn := size * scale
	on.draw_texture_rect(texture, Rect2(box.get_center() - drawn * 0.5, drawn), false, tint)


## Draws text with its left end, centre or right end at `at` (the baseline's
## height), with CS2's soft dark shadow under it.
static func draw_text(on: CanvasItem, at: Vector2, text: String, size: int, colour: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, bold: bool = true) -> float:
	var face := font(bold)
	var width := face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= width
	# Dark text (a number on a white bar) goes without the shadow.
	if colour.get_luminance() > 0.3:
		var shadow := Color(SHADOW, SHADOW.a * colour.a)
		on.draw_string_outline(face, Vector2(x + 1, at.y + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			maxi(2, roundi(size * 0.1)), shadow)
	on.draw_string(face, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)
	return width


## How tall a font's capitals stand, to centre a number on a line.
static func cap_height(size: int, bold: bool = true) -> float:
	return font(bold).get_ascent(size) * 0.72
