class_name WinPanel
extends HudElement

## CS2's win panel (CSGOHudWinPanel; its panorama/layout/hud/hudwinpanel.xml,
## styles/hud/hudwinpanel.css and scripts/hud/hudwinpanel.js, read from
## GameTracking-CS2 on 2026-09-26): from a round's end until the next round
## starts, 190 px down in the middle, a bar 400 wide and 80 tall saying ROUND
## WON or ROUND LOST between two double arrows, the round's fun fact under
## it, and under that the MVP's band, 640 wide and 90 tall, with their
## portrait, why they are MVP and their name.
##
## Its colours are CS2's: the bar is the winner's (winPanelBgColorT
## rgba(66, 46, 8, .85) or winPanelBgColorCT rgba(9, 40, 61, .85)) with 4 px
## ends and the title in t-color or ct-color, or, for the side that lost,
## negativeColor #DB4437 on rgba(32, 2, 2, .877). The MVP's band is always
## the winner's, their reason black on the team's colour, their name in it.
##
## How it opens, as the css's transitions do: the bar opens out from its
## middle and fades in over .25 s, ease-in; the title starts half as large
## again and shrinks to its size over 5 s, ease-in; the arrows slide 25 px in
## over .25 s after .5 s, from ten times as bright; the fun fact fades in
## over .25 s; the MVP's band opens out over .25 s under a white flash that
## fades from .25 to .5 s.
##
## Left out: the glitch video over the bar (a .webm), the 3D render of the
## MVP's agent on the band (a map CS2 renders, ui/match_mvp: the band shows
## its colour instead, faded at both ends as its mask fades it), music kits,
## and the surrender line. The MVP's portrait is the team counter's: CS2's
## bot portrait, or a head and shoulders for a player.

## hudwinpanel.css: winPanelPosY, winPanelWidth, the bar's height, its ends,
## the gap under it (.WinPanelTopSection margin-bottom).
const TOP := 190.0
const WIDTH := 400.0
const BAR_HEIGHT := 80.0
const END := 4.0
const CORNER := 3.0
const GAP := 16.0
## The title (.WinPanel__Result__Title): Stratum2 Medium Condensed 64 px,
## 8 px apart, in a label 340 by 60 that shrinks what does not fit, 14 px of
## margin under it, a soft dark shadow.
const TITLE_SIZE := 64
const TITLE_SPACING := 8
const TITLE_WIDTH := 340.0
const TITLE_HEIGHT := 60.0
const TITLE_MARGIN := 14.0
## Rajdhani, standing in without the extraction, is not condensed, so it
## is fitted to the width CS2's title has on its screenshot (about 232 px
## at 1080p) rather than filling the label.
const TITLE_FALLBACK_WIDTH := 232.0
const TITLE_START_SCALE := 1.5
const TITLE_SHRINK_SECONDS := 5.0
const TEXT_SHADOW := Color8(0x35, 0x35, 0x35, 0xbb)
## The double arrows: 16 px tall, 12 px in from each end, centred with the
## title; 25 px out and ten times as bright before they slide in.
const ARROW_HEIGHT := 16.0
const ARROW_INSET := 12.0
const ARROW_SLIDE := 25.0
const ARROW_BRIGHTNESS := 10.0
const ARROW_DELAY := 0.5
## The fun fact: Stratum2 12 px, white, in a 16 px row 3 px off the bar's
## bottom.
const FACT_SIZE := 12
const FACT_ROW := 16.0
const FACT_MARGIN := 3.0
## The MVP's band (.MVP_section, non-premier) and what is on it: a 72 px
## portrait with 8 px after it; the reason 18 px in a 21 px box padded 6 px;
## the name 28 px in a 250 by 38 box, half as bright again.
const BAND_WIDTH := 640.0
const BAND_HEIGHT := 90.0
const AVATAR := 72.0
const AVATAR_GAP := 8.0
const REASON_SIZE := 18
const REASON_HEIGHT := 21.0
const REASON_PADDING := 6.0
const NAME_SIZE := 28
const NAME_WIDTH := 250.0
const NAME_HEIGHT := 38.0
const NAME_BRIGHTNESS := 1.5
const NAME_SHADOW := Color8(0x14, 0x14, 0x14, 0xdc)
## How far in from each end the band's mask (mvp_banner_fade-both-right-left)
## has faded it in: read off CS2's screenshot, where the band is solid from
## about a fifth of the way in. A guess until the mask is read.
const BAND_FADE := 0.18
## The avatar's grey (.MVP__Avatar: #6d6d6d to #464646, top to bottom).
const AVATAR_TOP := Color8(0x6d, 0x6d, 0x6d)
const AVATAR_BOTTOM := Color8(0x46, 0x46, 0x46)

const OPEN_SECONDS := 0.25
const FLASH_SECONDS := 0.25

const BAR_T := Color8(66, 46, 8, 217)
const BAR_CT := Color8(9, 40, 61, 217)
const BAR_LOST := Color(32 / 255.0, 2 / 255.0, 2 / 255.0, 0.877)
const NEGATIVE := Color8(0xDB, 0x44, 0x37)
## The dot pattern over the bar: 360 px at 4 %.
const DOTS_SIZE := 360.0
const DOTS_OPACITY := 0.04

## What it shows; an empty title hides it.
var title: String = ""
var winner: String = "T"
var lost: bool = false
var fact: String = ""
var mvp_name: String = ""
var mvp_reason: String = ""
var mvp_side: String = "T"
var mvp_bot: bool = false
## Seconds since it opened.
var _t: float = 0.0

static var _title_font: FontVariation


func _ready() -> void:
	place(Vector2(0.5, 0.0), Rect2(-BAND_WIDTH * 0.5, TOP, BAND_WIDTH, BAR_HEIGHT + GAP + BAND_HEIGHT))


## Shows a round's end: the title (none hides it), the side that won and
## whether it was yours that lost, the fun fact, and the MVP (no name for
## none) with why and their side.
func show_round(p_title: String, p_winner: String = "T", p_lost: bool = false, p_fact: String = "",
		p_mvp_name: String = "", p_mvp_reason: String = "", p_mvp_side: String = "T", p_mvp_bot: bool = false) -> void:
	var opening := title.is_empty() and not p_title.is_empty()
	title = p_title
	winner = p_winner
	lost = p_lost
	fact = p_fact
	mvp_name = p_mvp_name
	mvp_reason = p_mvp_reason
	mvp_side = p_mvp_side
	mvp_bot = p_mvp_bot
	if show_state([p_title, p_winner, p_lost, p_fact, p_mvp_name, p_mvp_reason, p_mvp_side, p_mvp_bot]) and opening:
		_t = 0.0
		animate()


func is_showing() -> bool:
	return not title.is_empty()


func _advance(delta: float) -> bool:
	_t += delta
	return is_showing() and _t < TITLE_SHRINK_SECONDS


## CSS's ease-in: cubic-bezier(.42, 0, 1, 1), close enough as a square.
static func _ease_in(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c


## How far open the bar is, 0 to 1, and so the band (both open over the
## same quarter second).
func openness() -> float:
	return _ease_in(_t / OPEN_SECONDS)


## The bar as far open as it is, in this element's coordinates.
func _bar() -> Rect2:
	var half := WIDTH * 0.5 * openness()
	return Rect2(size.x * 0.5 - half, 0.0, half * 2.0, BAR_HEIGHT)


func _band() -> Rect2:
	var half := BAND_WIDTH * 0.5 * openness()
	return Rect2(size.x * 0.5 - half, BAR_HEIGHT + GAP, half * 2.0, BAND_HEIGHT)


func _blur_rect() -> Rect2:
	return Rect2() if title.is_empty() or openness() <= 0.0 else _bar()


## The world behind the bar blurred (world-blur: hudWorldBlur).
func _draw_blur(on: CanvasItem) -> void:
	if title.is_empty() or openness() <= 0.0:
		return
	on.draw_style_box(_rounded(Color.WHITE), _bar())


func _rounded(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(int(CORNER))
	box.anti_aliasing = true
	return box


## The colour of the bar's ends, arrows and title.
func accent() -> Color:
	return NEGATIVE if lost else HudStyle.team_colour(winner)


func _draw() -> void:
	if title.is_empty() or openness() <= 0.0:
		return
	var fade := openness()
	var bar := _bar()
	var background: Color = BAR_LOST if lost else (BAR_CT if winner == "CT" else BAR_T)
	draw_style_box(_rounded(Color(background, background.a * fade)), bar)
	var dots := HudStyle.icon("backgrounds/bluedots_large_png")
	if dots != null:
		var scale := dots.get_size().x / DOTS_SIZE
		draw_texture_rect_region(dots, bar, Rect2(bar.position * scale, bar.size * scale), Color(1, 1, 1, DOTS_OPACITY * fade))
	var colour := Color(accent(), fade)
	draw_rect(Rect2(bar.position, Vector2(minf(END, bar.size.x), BAR_HEIGHT)), colour)
	draw_rect(Rect2(Vector2(bar.end.x - minf(END, bar.size.x), 0.0), Vector2(minf(END, bar.size.x), BAR_HEIGHT)), colour)
	_draw_title(fade)
	_draw_arrows(fade)
	if not fact.is_empty():
		var baseline := HudStyle.baseline_centred(BAR_HEIGHT - FACT_MARGIN - FACT_ROW * 0.5, FACT_SIZE, &"regular")
		HudStyle.draw_text(self, Vector2(size.x * 0.5, baseline), fact, FACT_SIZE, Color(1, 1, 1, fade),
			HORIZONTAL_ALIGNMENT_CENTER, &"regular", Color(0, 0, 0, 0.5 * fade), 4)
	if not mvp_name.is_empty():
		_draw_band()


## The title, CS2's letter spacing, shrunk to fit its label, then scaled
## from half as large again down to its size.
func _draw_title(fade: float) -> void:
	var font := title_font()
	var size_now := float(TITLE_SIZE)
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
	var room := TITLE_WIDTH if HudStyle.has_cs2_font() else TITLE_FALLBACK_WIDTH
	if width > room:
		size_now *= room / width
	size_now *= title_scale()
	var drawn := int(roundf(size_now))
	width = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, drawn).x
	var centre_y := ((BAR_HEIGHT - TITLE_MARGIN) - TITLE_HEIGHT) * 0.5 + TITLE_HEIGHT * 0.5
	var baseline := centre_y - (font.get_ascent(drawn) + font.get_descent(drawn)) * 0.5 + font.get_ascent(drawn)
	# The letter spacing trails the last letter too; centre the letters.
	var at := Vector2(size.x * 0.5 - (width - TITLE_SPACING) * 0.5, baseline)
	draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, drawn, 6, Color(TEXT_SHADOW, TEXT_SHADOW.a * fade * 0.5))
	draw_string(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, drawn, Color(accent(), fade))


## How large the title is against its size: 1.5 at the start, 1 after 5 s.
func title_scale() -> float:
	return lerpf(TITLE_START_SCALE, 1.0, _ease_in(_t / TITLE_SHRINK_SECONDS))


## The two double arrows, pointing in at the title.
func _draw_arrows(fade: float) -> void:
	var slide := _ease_in((_t - ARROW_DELAY) / OPEN_SECONDS)
	var brightness := lerpf(ARROW_BRIGHTNESS, 1.0, slide)
	var base := accent()
	var colour := Color(base.r * brightness, base.g * brightness, base.b * brightness, fade)
	var centre_y := ((BAR_HEIGHT - TITLE_MARGIN) - ARROW_HEIGHT) * 0.5 + ARROW_HEIGHT * 0.5
	var offset := ARROW_SLIDE * (1.0 - slide)
	var bar := _bar()
	var arrows := HudStyle.icon("hud/double_arrows")
	var arrow_width := ARROW_HEIGHT
	if arrows != null and arrows.get_size().y > 0.0:
		arrow_width = ARROW_HEIGHT * arrows.get_size().x / arrows.get_size().y
	for right in [false, true]:
		var left_x: float = bar.end.x - ARROW_INSET - arrow_width if right else bar.position.x + ARROW_INSET
		var box := Rect2(left_x + offset, centre_y - ARROW_HEIGHT * 0.5, arrow_width, ARROW_HEIGHT)
		if arrows != null:
			# The image points left (the right one's); the left one is flipped.
			if right:
				draw_texture_rect(arrows, box, false, colour)
			else:
				draw_texture_rect(arrows, Rect2(box.position + Vector2(box.size.x, 0.0), Vector2(-box.size.x, box.size.y)),
					false, colour)
		else:
			_draw_chevrons(box, not right, colour)


## Two chevrons in a box, pointing right or left, where CS2's image is not
## extracted.
func _draw_chevrons(box: Rect2, pointing_right: bool, colour: Color) -> void:
	var w := box.size.x * 0.5
	for i in 2:
		var x0 := box.position.x + i * w * 0.9
		var tip := x0 + w if pointing_right else x0
		var back := x0 if pointing_right else x0 + w
		draw_polyline(PackedVector2Array([
			Vector2(back, box.position.y), Vector2(tip, box.get_center().y), Vector2(back, box.end.y),
		]), colour, 2.5, true)


## The MVP's band: the winner's colour faded in from both ends, the
## portrait, the reason on its tab and the name.
func _draw_band() -> void:
	var band := _band()
	if band.size.x <= 0.0:
		return
	var background: Color = BAR_CT if winner == "CT" else BAR_T
	var inner := band.size.x * BAND_FADE
	var xs := [band.position.x, band.position.x + inner, band.end.x - inner, band.end.x]
	var alphas := [0.0, background.a, background.a, 0.0]
	for i in 3:
		var a := Color(background, alphas[i])
		var b := Color(background, alphas[i + 1])
		draw_polygon(PackedVector2Array([Vector2(xs[i], band.position.y), Vector2(xs[i + 1], band.position.y),
			Vector2(xs[i + 1], band.end.y), Vector2(xs[i], band.end.y)]), PackedColorArray([a, b, b, a]))

	var team := HudStyle.team_colour(winner)
	var reason_font := HudStyle.face(&"medium_condensed")
	var reason_width := reason_font.get_string_size(mvp_reason, HORIZONTAL_ALIGNMENT_LEFT, -1, REASON_SIZE).x \
		+ REASON_PADDING * 2.0
	var details := maxf(NAME_WIDTH, reason_width)
	var left := size.x * 0.5 - (AVATAR + AVATAR_GAP + details) * 0.5
	var middle_y := band.get_center().y
	var avatar := Rect2(left, middle_y - AVATAR * 0.5, AVATAR, AVATAR)
	_draw_avatar(avatar)
	var top := middle_y - (REASON_HEIGHT + NAME_HEIGHT) * 0.5
	var details_left := avatar.end.x + AVATAR_GAP
	draw_rect(Rect2(details_left, top, reason_width, REASON_HEIGHT), team)
	HudStyle.draw_text(self, Vector2(details_left + REASON_PADDING,
		HudStyle.baseline_centred(top + REASON_HEIGHT * 0.5, REASON_SIZE, &"medium_condensed")),
		mvp_reason, REASON_SIZE, Color.BLACK, HORIZONTAL_ALIGNMENT_LEFT, &"medium_condensed")
	var bright := Color(minf(team.r * NAME_BRIGHTNESS, 1.0), minf(team.g * NAME_BRIGHTNESS, 1.0),
		minf(team.b * NAME_BRIGHTNESS, 1.0))
	HudStyle.draw_text(self, Vector2(details_left,
		HudStyle.baseline_centred(top + REASON_HEIGHT + NAME_HEIGHT * 0.5, NAME_SIZE, &"condensed")),
		fit_name(mvp_name), NAME_SIZE, bright, HORIZONTAL_ALIGNMENT_LEFT, &"condensed", NAME_SHADOW, 3)
	# The white flash over the band as it opens.
	var flash := 1.0 - clampf((_t - FLASH_SECONDS) / FLASH_SECONDS, 0.0, 1.0)
	if flash > 0.0:
		draw_rect(band, Color(1, 1, 1, flash))


## The name, cut short with an ellipsis where it would run past its box.
static func fit_name(text: String) -> String:
	var font := HudStyle.face(&"condensed")
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x <= NAME_WIDTH:
		return text
	var cut := text
	while cut.length() > 1 and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x > NAME_WIDTH:
		cut = cut.left(cut.length() - 1)
	return cut + "…"


## The MVP's portrait on the avatar's grey: CS2's bot portrait washed in the
## side's colour, as the team counter draws it, or a head and shoulders.
func _draw_avatar(box: Rect2) -> void:
	draw_polygon(PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end,
		Vector2(box.position.x, box.end.y)]), PackedColorArray([AVATAR_TOP, AVATAR_TOP, AVATAR_BOTTOM, AVATAR_BOTTOM]))
	if mvp_bot:
		var bot := HudStyle.icon("hud/teamcounter/teamcounter_botavatar")
		if bot != null:
			HudStyle.draw_fitted(self, bot, box.grow(-6.0), TeamCounter.BOT_WASH.get(mvp_side, Color.WHITE))
			return
	else:
		draw_rect(box, Color(TeamCounter.DEFAULT_PORTRAIT.get(mvp_side, Color.GRAY), 0.8))
	var c := box.get_center()
	var s := box.size.x / 50.0
	var colour := Color(1, 1, 1, 0.45)
	draw_circle(c + Vector2(0, -6) * s, 9.0 * s, colour)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-17, 22) * s, c + Vector2(-14, 9) * s, c + Vector2(-6, 5) * s,
		c + Vector2(6, 5) * s, c + Vector2(14, 9) * s, c + Vector2(17, 22) * s,
	]), colour)


## The title's face: Stratum2 Medium Condensed with CS2's 8 px between
## letters.
static func title_font() -> FontVariation:
	if _title_font == null:
		_title_font = FontVariation.new()
		_title_font.base_font = HudStyle.face(&"medium_condensed")
		_title_font.spacing_glyph = TITLE_SPACING
	return _title_font


## The title for a round's end as you see it: ROUND WON or ROUND LOST for
## a side's player (WinPanel_RoundWon, WinPanel_RoundLost), who won for
## someone on neither (SFUI_WinPanel_T_Win, _CT_Win), and a draw
## (SFUI_WinPanel_Round_Draw).
static func title_for(winner: String, your_side: String) -> String:
	if winner != "T" and winner != "CT":
		return "Round Draw"
	if your_side != "T" and your_side != "CT":
		return "Terrorists Win" if winner == "T" else "Counter-Terrorists Win"
	return "ROUND WON" if your_side == winner else "ROUND LOST"


## What the MVP's tab says for CS2's reason (hudwinpanel.js _SetMVP, with
## csgo_english.txt's Panorama_winpanel_mvp_* strings).
static func mvp_reason_text(reason: int) -> String:
	match reason:
		2:
			return "MVP for planting the bomb"
		3:
			return "MVP for defusing the bomb"
		4:
			return "MVP for extracting a hostage"
		9:
			return "MVP for an Ace Round"
		10:
			return "MVP for dealing a significant amount of fire damage"
		11:
			return "MVP for dealing a significant amount of explosive damage"
		13:
			return "MVP for planting and defending the bomb"
		14:
			return "MVP for a clutch defuse"
		15:
			return "MVP for most kills (3k)"
		16:
			return "MVP for most kills (4k)"
	return "MVP"


## A fun fact in English (csgo_english.txt's funfact_* strings, one and
## many), with the player's name and its number; empty for a token it does
## not know.
static func fun_fact_text(token: String, player: String, data1: int) -> String:
	var one := data1 == 1
	match token.trim_prefix("#"):
		"funfact_t_win_no_casualties":
			return "Terrorists won without taking any casualties."
		"funfact_ct_win_no_casualties":
			return "Counter-Terrorists won without taking any casualties."
		"funfact_kills_headshots":
			return "%s killed %d %s with headshots that round." % [player, data1, "enemy" if one else "enemies"]
		"funfact_killed_enemies":
			return "%s killed %d %s." % [player, data1, "opponent" if one else "opponents"]
		"funfact_damage_no_kills":
			return "%s had no kills, but did %d damage." % [player, data1]
		"funfact_first_blood":
			return "%s drew first blood %d %s into the round." % [player, data1, "second" if one else "seconds"]
		"funfact_bomb_planted_before_kill":
			return "No players were killed prior to the bomb being planted."
		"funfact_short_round":
			return "That round took only %d %s!" % [data1, "second" if one else "seconds"]
	return ""


## Why the round ended, short, for a round with no fun fact
## (csgo_english.txt's winpanel_end_* strings); by round_end's reason.
static func reason_text(reason: String) -> String:
	return {
		"TargetBombed": "Bomb detonated",
		"BombDefused": "Bomb defused",
		"TargetSaved": "Bombing failed",
		"TerroristsWin": "CTs eliminated",
		"CTsWin": "Terrorists eliminated",
	}.get(reason, "")
