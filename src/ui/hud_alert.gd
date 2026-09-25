class_name HudAlert
extends HudElement

## One of CS2's bars of text over the health and ammo: the alert (CSGOHudAlerts;
## CS2's panorama/layout/hud/hudalerts.xml and styles/hud/hudalerts.css),
## which says what part of the match it is (warmup, the round's announcement,
## who won), or the hint text (CSGOHudHintText, hudhinttext.xml and .css),
## which says why something was refused. Each is a bar 300 px wide
## (alert-width) with 3 px round corners: the world behind darkened by half
## (and blurred, in CS2) with its faint dot pattern, a 2 px upright line at
## each end, and white Stratum2 Medium TF at 18 px in the middle, padded 8 px
## above and below. It opens out from its centre over a quarter of a second
## after a quarter of a second's wait, as the css's transitions do.
##
## The kinds differ as CS2's do: the alert's ends and text add their light in
## the team's colour; a high-priority hint (a refusal) sits 50 px lower, its
## ends red, a red alert icon before its text, and its dark twice as deep; a
## low-priority one lower still. GameHud also uses one for the line across
## the middle while you are dead, which CS2 has no bar for.

enum Kind { ALERT, HINT, NOTE }

const WIDTH := 300.0
const TEXT_SIZE := 18
const PADDING := 8.0
const SIDE := 2.0
const CORNER := 3.0
## The css: the transform opens over .25 s after a .25 s wait, ease-in.
const WAIT_SECONDS := 0.25
const OPEN_SECONDS := 0.25
## .alert-bar-bg and .hud-hint_bg: rgba(0,0,0,0.5); a visible high-priority
## hint's own background adds hud-blur-bg-color (#000000a0) under it.
const DARK := Color(0, 0, 0, 0.5)
const DARK_HINT := Color(0, 0, 0, 0.5 + 0.5 * 0.627)
## The dot pattern: bluedots_large_png at 360 px, 4 % (background-img-opacity).
const DOTS_SIZE := 360.0
const DOTS_OPACITY := 0.04
## Where each kind's bar starts, from the bottom of the screen: the alert's
## top is 750.7 down on CS2's screenshot (its float panel's 120 px in); the
## hints are 170 + 2 and 236 + 2 px into the same panel (hudhinttext.css).
const TOP := {Kind.ALERT: 750.7, Kind.HINT: 750.7 + 52.0, Kind.NOTE: 750.7 + 118.0}
## The ends of the alert add the team's colour faintly: CS2's screenshot has
## them a dim khaki over the darkened pavement, not the numbers' gold.
const ALERT_END_STRENGTH := 0.3

var kind: Kind = Kind.ALERT
## Where the bar's top is, down from the top of the base size; set before
## it enters the tree to move it (GameHud's line while dead).
var top: float = -1.0
## The colour of the alert's ends: the team's.
var ends: Color = HudStyle.T_COLOUR

var text: String = ""
## A smaller line under the bar, such as the key that starts the match.
var note: String = ""
var _open: float = -1.0
var _added: Control


func _ready() -> void:
	if top < 0.0:
		top = TOP[kind]
	var height := PADDING * 2.0 + _line_height() + 24.0
	place(Vector2(0.5, 0.0), Rect2(-WIDTH * 0.5 - 60.0, top, WIDTH + 120.0, height))
	# What adds its light (the alert's ends and text) draws on its own
	# surface over the bar.
	_added = Control.new()
	_added.name = "Added"
	_added.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_added.material = HudStyle.additive()
	_added.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_added.draw.connect(_draw_added)
	add_child(_added, false, Node.INTERNAL_MODE_FRONT)


## Shows a line (none hides the bar), a note under it, and the ends' colour
## (none keeps the one set).
func say(line: String, under: String = "", end_colour: Color = Color(0, 0, 0, 0)) -> void:
	if end_colour.a == 0.0:
		end_colour = ends
	var opening := text.is_empty() and not line.is_empty()
	text = line
	note = under
	ends = end_colour
	if show_state([line, under, end_colour]) and opening:
		_open = 0.0
		animate()


func is_showing() -> bool:
	return not text.is_empty()


## How far open the bar is, 0 to 1.
func openness() -> float:
	if _open < 0.0:
		return 1.0
	var t := clampf((_open - WAIT_SECONDS) / OPEN_SECONDS, 0.0, 1.0)
	return t * t


func _advance(delta: float) -> bool:
	_open += delta
	if _open >= WAIT_SECONDS + OPEN_SECONDS:
		_open = -1.0
		return false
	return true


func redraw() -> void:
	super()
	if _added != null:
		_added.queue_redraw()


func _line_height() -> float:
	var font := HudStyle.face(&"medium_tf")
	return font.get_ascent(TEXT_SIZE) + font.get_descent(TEXT_SIZE)


## The bar as far open as it is, in this element's coordinates.
func _bar() -> Rect2:
	var half := WIDTH * 0.5 * openness()
	return Rect2(size.x * 0.5 - half, 0.0, half * 2.0, PADDING * 2.0 + _line_height())


## Where the bar's blur is: nowhere while it is hidden.
func _blur_rect() -> Rect2:
	return Rect2() if text.is_empty() or openness() <= 0.0 else _bar()


## The world behind the bar, blurred (world-blur: hudWorldBlur), under the
## dark.
func _draw_blur(on: CanvasItem) -> void:
	if text.is_empty() or openness() <= 0.0:
		return
	var shape := StyleBoxFlat.new()
	shape.bg_color = Color.WHITE
	shape.set_corner_radius_all(int(CORNER))
	shape.anti_aliasing = true
	on.draw_style_box(shape, _bar())


## The bar itself, with the ordinary blend: the dark, the dots and, for a
## hint, its ends.
func _draw() -> void:
	if text.is_empty() or openness() <= 0.0:
		return
	var bar := _bar()
	var dark := StyleBoxFlat.new()
	dark.bg_color = DARK_HINT if kind == Kind.HINT else DARK
	dark.set_corner_radius_all(int(CORNER))
	dark.anti_aliasing = true
	draw_style_box(dark, bar)
	var dots := HudStyle.icon("backgrounds/bluedots_large_png")
	if dots != null:
		draw_texture_rect_region(dots, bar, Rect2(bar.position * (dots.get_size().x / DOTS_SIZE),
			bar.size * (dots.get_size().x / DOTS_SIZE)), Color(1, 1, 1, DOTS_OPACITY))
	if kind != Kind.ALERT:
		var end := Color.RED if kind == Kind.HINT else ends
		_draw_ends(self, bar, end)


## What adds its light: the alert's ends, and every kind's text.
func _draw_added() -> void:
	if text.is_empty() or openness() <= 0.0:
		return
	var bar := _bar()
	if kind == Kind.ALERT:
		_draw_ends(_added, bar, Color(ends, ALERT_END_STRENGTH))
	if openness() < 1.0:
		return
	var font := HudStyle.face(&"medium_tf")
	var baseline := bar.position.y + PADDING + font.get_ascent(TEXT_SIZE)
	var centre := size.x * 0.5
	if kind == Kind.HINT:
		# The alert icon, 32 px and 10 px either side of it, before the text.
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
		var icon := HudStyle.icon("icons/ui/alert")
		var box := Rect2(centre - (width + 52.0) * 0.5 + 10.0, bar.get_center().y - 16.0, 32.0, 32.0)
		if icon != null:
			HudStyle.draw_fitted(_added, icon, box, Color.RED)
			centre += 26.0
	HudStyle.draw_text(_added, Vector2(centre, baseline), text, TEXT_SIZE, Color.WHITE,
		HORIZONTAL_ALIGNMENT_CENTER, &"medium_tf")
	if not note.is_empty():
		HudStyle.draw_text(_added, Vector2(size.x * 0.5, bar.end.y + 6.0 + font.get_ascent(15)), note, 15,
			Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, &"medium_tf")


## The 2 px upright lines at the bar's two ends.
func _draw_ends(on: CanvasItem, bar: Rect2, colour: Color) -> void:
	on.draw_rect(Rect2(bar.position, Vector2(SIDE, bar.size.y)), colour)
	on.draw_rect(Rect2(Vector2(bar.end.x - SIDE, bar.position.y), Vector2(SIDE, bar.size.y)), colour)
