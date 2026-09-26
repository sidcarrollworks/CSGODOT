class_name HudStyle
extends RefCounted

## What CS2's HUD looks like, in one place: its colours, its fonts and its
## icons, for every part of the HUD and the buy menu to draw with.
##
## The numbers are CS2's own, from the Panorama layouts and styles it ships
## (game/csgo/pak01_dir.vpk: panorama/styles/csgostyles.vcss_c and
## panorama/styles/hud/*.vcss_c, decompiled by Source 2 Viewer on
## 2026-09-25): the team colours, the dark behind a panel, the fonts by
## family, and each element's sizes in its own script. Everything is laid out
## on the 1920x1080 base size, which is also Panorama's; the canvas_items
## stretch scales it to the window.
##
## How CS2 blends. Most of the HUD carries Panorama's `additive` class: the
## numbers, bars, lines and icons add their light to the world behind them
## instead of covering it, and Panorama does it in linear light. Measured on
## CS2's own screenshot (reference/cs2 _screenshots/In_game_ui.webp), the
## health's gold adds the same linear amount over the dark sleeve and the
## bright pavement, t-color itself, which is why the numbers look lit and
## the pavement's seams show through them. `additive()` gives an element
## that blend, and the project renders 2D in linear light (project.godot,
## rendering/viewport/hdr_2d) so that it and every translucent panel blend
## the way Panorama's do.
##
## CS2's font (Stratum2) and icons are Valve's, so they come only from the
## extraction (scripts/extract_assets.sh hud) into assets/hud/. Without them
## the HUD draws with Rajdhani (SIL Open Font License, src/ui/fonts/), the
## closest free face, and draws its own simple icons, so it looks right in
## shape everywhere and exactly right where CS2 is installed.

## csgostyles.css t-color and ct-color: the HUD's wash in your team's colour
## (cl_hud_color 0, the default).
const T_COLOUR := Color8(234, 190, 84)
const CT_COLOUR := Color8(150, 200, 250)
## csgostyles.css color-T and color-CT: the team counter's paler pair, for
## the scores and the players alive on each side.
const COUNTER_T := Color8(234, 209, 138)
const COUNTER_CT := Color8(181, 212, 238)
## The dark behind a blurred HUD panel (hud-blur-bg-color #000000a0), which
## the HUD's cl_hud_background_alpha class halves (csgostyles.css
## .csgo-hud--cl_hud_background_alpha, opacity .5); measured on CS2's
## screenshot, the ring's disc keeps 0.7 to 0.8 of the world's light behind
## it, which is this. CS2 also blurs the world behind; this draws the tint.
const PANEL_TINT := Color(0, 0, 0, 0.314)
## A hit taking health (hudhealthammocenter.css 'on-damage', #DD0000).
const DAMAGE_RED := Color8(221, 0, 0)
## The buy zone's cart (hudmoney.css, wash-color lightgreen).
const BUY_GREEN := Color8(144, 238, 144)
## Teammates' colours, in the order CS2 hands them out (cl_teammate_color_1
## to 5, convars.txt; the border of your card on CS2's screenshot is the
## fourth exactly): blue, green, yellow, orange, purple.
const TEAMMATE_COLOURS: Array[Color] = [
	Color8(136, 206, 245), Color8(0, 158, 128), Color8(241, 228, 65),
	Color8(230, 128, 42), Color8(189, 44, 150),
]

## Stratum2's faces by the family names CS2's styles ask for (csgostyles.css
## .stratum-bold-tf and the rest), each with the file the extraction unpacks
## and the bundled face that stands in for it.
const FACES := {
	# The HUD's numbers: bold with tabular figures, every digit as wide.
	&"bold_tf": ["stratum2_tf_bold.otf", "Rajdhani-Bold.ttf"],
	&"medium_tf": ["stratum2_tf_medium.otf", "Rajdhani-SemiBold.ttf"],
	&"bold": ["stratum2-bold.otf", "Rajdhani-Bold.ttf"],
	&"medium": ["stratum2-medium.otf", "Rajdhani-SemiBold.ttf"],
	&"regular": ["stratum2-regular.otf", "Rajdhani-SemiBold.ttf"],
	# The money's rolling digits (.digitpanel-font) and the team counter's
	# equipment money (.stratum-bold-mono).
	&"mono_bold": ["stratum2mono-bold.otf", "Rajdhani-Bold.ttf"],
	&"bold_condensed": ["stratum2condensed-bold.otf", "Rajdhani-Bold.ttf"],
	&"condensed": ["stratum2condensed-regular.otf", "Rajdhani-SemiBold.ttf"],
	&"light_condensed": ["stratum2condensed-light.otf", "Rajdhani-SemiBold.ttf"],
	# The buy menu's column titles (medium, condensed) and its item notes'
	# last line (italic).
	&"medium_condensed": ["stratum2condensed-medium.otf", "Rajdhani-SemiBold.ttf"],
	&"italic": ["stratum2-regularitalic.otf", "Rajdhani-SemiBold.ttf"],
}

const IMAGES := "res://assets/hud/panorama/images"
const FONTS := "res://assets/hud/fonts"
const FALLBACK_FONTS := "res://src/ui/fonts"
const FALLBACK_BOLD := "res://src/ui/fonts/Rajdhani-Bold.ttf"

static var _faces := {}
static var _icons := {}
static var _additive: CanvasItemMaterial
static var _world_blur := {}


static func team_colour(side: String) -> Color:
	return CT_COLOUR if side == "CT" else T_COLOUR


static func counter_colour(side: String) -> Color:
	return COUNTER_CT if side == "CT" else COUNTER_T



## One of the HUD's faces (FACES): CS2's Stratum2 where it was extracted,
## else the bundled stand-in.
static func face(name: StringName = &"bold_tf") -> Font:
	if not _faces.has(name):
		var files: Array = FACES[name]
		var path := FONTS.path_join(files[0])
		var found: Font = load(path) as Font if ResourceLoader.exists(path) else null
		if found == null:
			found = load(FALLBACK_FONTS.path_join(files[1])) as Font
		_faces[name] = found
	return _faces[name]


## Whether CS2's own font is in use.
static func has_cs2_font() -> bool:
	return ResourceLoader.exists(FONTS.path_join(FACES[&"bold_tf"][0]))


## One of CS2's HUD images by its path under panorama/images, without the
## extension ("hud/armor", "icons/ui/buyzone"); null where it was not
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


## The material that makes a CanvasItem add its light to what is behind it,
## as Panorama's `additive` class does. One, shared.
static func additive() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


## The material that shows the world behind a shape blurred, as Panorama's
## world-blur does (hud_blur.gdshader), `level` steps down Godot's screen mip
## chain at the base size: 4 for the HUD's panels, more for the buy menu's
## whole screen. One per level, shared.
static func world_blur(level: float = 4.0) -> ShaderMaterial:
	if not _world_blur.has(level):
		var blur := ShaderMaterial.new()
		blur.shader = load("res://src/ui/hud_blur.gdshader")
		blur.set_shader_parameter(&"level", level)
		_world_blur[level] = blur
	return _world_blur[level]


## Draws `texture` fitted into `box`, keeping its shape, tinted (Panorama's
## wash-color on a white icon).
static func draw_fitted(on: CanvasItem, texture: Texture2D, box: Rect2, tint: Color) -> void:
	var size := texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var scale := minf(box.size.x / size.x, box.size.y / size.y)
	var drawn := size * scale
	on.draw_texture_rect(texture, Rect2(box.get_center() - drawn * 0.5, drawn), false, tint)


## Draws text with its left end, centre or right end at `at.x` and its
## baseline at `at.y`, in one of the faces, and returns its width. A shadow
## colour with alpha draws Panorama's text-shadow under it: offset one pixel
## down and right, softened by an outline of `shadow_spread`.
static func draw_text(on: CanvasItem, at: Vector2, text: String, size: int, colour: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, font_face: StringName = &"bold_tf",
		shadow: Color = Color(0, 0, 0, 0), shadow_spread: int = 2) -> float:
	var font := face(font_face)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= width
	if shadow.a > 0.0:
		var offset := Vector2(x + 1.0, at.y + 1.0)
		on.draw_string_outline(font, offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shadow_spread, shadow)
		on.draw_string(font, offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shadow)
	on.draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)
	return width


## Where a Panorama label puts its text's baseline: the label is as tall as
## the face's ascent and descent at that size, set `centre_y` in the middle
## of it (vertical-align: center), and its text sits on the ascent. `nudge`
## is the label's own y offset in its style (.HudHealthAmmoCenter Label's
## y: 2px, and so on).
static func baseline_centred(centre_y: float, size: int, font_face: StringName = &"bold_tf", nudge: float = 0.0) -> float:
	var font := face(font_face)
	var ascent := font.get_ascent(size)
	var descent := font.get_descent(size)
	return centre_y - (ascent + descent) * 0.5 + ascent + nudge


## The same for a label whose top is at `top_y` (vertical-align: top).
static func baseline_from_top(top_y: float, size: int, font_face: StringName = &"bold_tf") -> float:
	return top_y + face(font_face).get_ascent(size)
