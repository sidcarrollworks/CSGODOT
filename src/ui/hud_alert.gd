class_name HudAlert
extends HudElement

## One of CS2's bars of text over the health and ammo (CSGOHudAlerts,
## hudalerts.xml and .css, and the hint text, hudhinttext.css): 300 px wide,
## dark, with a 2 px upright line at each end, white 18 px text in the
## middle, opening out from its centre over a quarter of a second. The
## alert carries the part of the match it is (warmup, the round's
## announcement, who won); the hint, below it, says why something was
## refused, with red ends as CS2's high-priority hints have. Under the
## alert a smaller line can say what to press.

const WIDTH := 300.0
const HEIGHT := 37.0
const TEXT_SIZE := 18
const NOTE_SIZE := 15
## hudalerts.css: transform over .25s, the dark behind it rgba(0,0,0,0.5).
const OPEN_SECONDS := 0.25
const BACKGROUND := Color(0, 0, 0, 0.5)

## How far the bar's top is above the bottom of the screen. The alert is
## measured from CS2 at 4K (In_game_ui.webp: 750 of 1080); the hint sits
## 50 px lower, as its y (170 px) is to the alert's (120 px).
var up_from_bottom: float = 330.0
## The colour of the ends: the team's, or red for a refusal.
var ends: Color = HudStyle.T_COLOUR

var text: String = ""
## A smaller line under the bar, such as the key that starts the match.
var note: String = ""
var _open: float = 0.0


func _ready() -> void:
	place(Vector2(0.5, 1.0), Rect2(-WIDTH * 0.5, -up_from_bottom, WIDTH, HEIGHT + NOTE_SIZE + 10.0))


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


func _advance(delta: float) -> bool:
	_open = minf(_open + delta / OPEN_SECONDS, 1.0)
	return _open < 1.0


func _draw() -> void:
	if text.is_empty():
		return
	var eased := 1.0 - pow(1.0 - _open, 2.0)
	# 300 px, or wider for a longer line, keeping 24 px either side of it.
	var text_width := HudStyle.font(false).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
	var half := maxf(WIDTH, text_width + 48.0) * 0.5 * eased
	var bar := Rect2(WIDTH * 0.5 - half, 0.0, half * 2.0, HEIGHT)
	draw_rect(bar, BACKGROUND)
	draw_rect(Rect2(bar.position, Vector2(2, HEIGHT)), ends)
	draw_rect(Rect2(Vector2(bar.end.x - 2.0, 0.0), Vector2(2, HEIGHT)), ends)
	if _open < 1.0:
		return
	var baseline := HEIGHT * 0.5 + HudStyle.cap_height(TEXT_SIZE, false) * 0.5
	HudStyle.draw_text(self, Vector2(WIDTH * 0.5, baseline), text, TEXT_SIZE, Color.WHITE,
		HORIZONTAL_ALIGNMENT_CENTER, false)
	if not note.is_empty():
		HudStyle.draw_text(self, Vector2(WIDTH * 0.5, HEIGHT + 6.0 + HudStyle.cap_height(NOTE_SIZE, false)),
			note, NOTE_SIZE, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, false)
