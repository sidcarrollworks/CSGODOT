class_name MoneyPanel
extends HudElement

## Your money in the bottom left, as CS2 draws it (CSGOMoneyPanel; CS2's
## panorama/layout/hud/hudmoney.xml, styles/hud/hudmoney.css and
## scripts/hud/hudmoney.js with scripts/digitpanel.js): "$" and the amount in
## the team's colour, added to the world behind (the panel's `additive`
## class), in Stratum2 Mono Bold at 38 px. It is an odometer: six cells, the
## string right-aligned in them ("$800" leaves the first two blank), each
## cell a strip of " $0123456789" that rolls to its new symbol over 0.6 s on
## the script's cubic-bezier(0.9, 0.01, 0.1, 1), so a digit going from 3 to
## 6 rolls past 4 and 5 and the "$" rolls along when the amount gains a
## digit. While you may buy, the buy zone's cart sits after it in light green
## (CS2 shows the key's glyph there only for a controller).
##
## It only draws what GameHud gives it each frame, and redraws only when
## that changes or while the digits roll (HudElement).

## The odometer's symbols, in order (csgo_english.txt
## "buymenu_money_digitpanel_digits"), and its cells: as many as "$16000"
## has (hudmoney.js sizes it so).
const SYMBOLS := " $0123456789"
const CELLS := 6
const TEXT_SIZE := 38
## Where the cells are: their band is the 36 px the css gives the digit
## panel (.digitpanel-container), 16 px up from the bottom of the money's
## 80 (.money-text is 22 up and 48 tall, the band centred in it); each cell
## is a band's height of strip per symbol. On CS2's screenshot the cells'
## middles are 19.2 px apart from 25.5 px in, a little wider than the css's
## 18 px labels.
const PANEL_HEIGHT := 80.0
const BAND := Rect2(16.0, 16.0, CELLS * 19.2, 36.0)
const FIRST_CENTRE := 25.5
const PITCH := 19.2
## The cart: 30 px, 6 px after the cells, on the band's bottom
## (.money-text-buy-icon).
const CART := Rect2(BAND.end.x + 6.0, BAND.end.y - 30.0, 30.0, 30.0)
## How long a roll takes (hudmoney.js passes 0.6 to MakeDigitPanel).
const ROLL_SECONDS := 0.6

var team: String = "T"
var amount: int = 0
## Whether the cart shows.
var may_buy: bool = false

## Each cell's symbol index now (fractional mid-roll), where its roll
## started and where it is going.
var _at := PackedFloat32Array()
var _from := PackedFloat32Array()
var _to := PackedFloat32Array()
var _roll := -1.0
var _started := false
var _band: Control


func _init() -> void:
	super()
	additive = true
	for i in CELLS:
		_at.append(0.0)
		_from.append(0.0)
		_to.append(0.0)


func _ready() -> void:
	place(Vector2(0.0, 1.0), Rect2(0, -PANEL_HEIGHT, CART.end.x + 12.0, PANEL_HEIGHT))
	# The cells are clipped to their band, as the digit panel's overflow is,
	# so a rolling digit slides in and out of it; the band draws with the
	# panel's additive blend.
	_band = Control.new()
	_band.name = "Band"
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.use_parent_material = true
	_band.clip_contents = true
	_band.position = BAND.position
	_band.size = BAND.size
	_band.draw.connect(_draw_cells)
	add_child(_band, false, Node.INTERNAL_MODE_FRONT)


## Takes this frame's money; a new amount rolls there, but the first one
## shows at once (hudmoney.js's instant update).
func show_values(side: String, money: int, buying: bool) -> void:
	if not _started or money != amount:
		var target := symbols_for(money)
		for i in CELLS:
			_from[i] = _at[i] if _started else target[i]
			_to[i] = target[i]
			if not _started:
				_at[i] = target[i]
		if _started:
			_roll = 0.0
			animate()
	_started = true
	team = side
	amount = money
	may_buy = buying
	show_state([side, money, buying])


## The symbol index each cell shows for `money`: "$" and the digits, right-
## aligned in the cells with blanks before them.
static func symbols_for(money: int) -> PackedFloat32Array:
	var text := GameHud.money_text(money)
	var out := PackedFloat32Array()
	for i in CELLS:
		var from_right := CELLS - i
		var symbol := text[text.length() - from_right] if from_right <= text.length() else " "
		out.append(float(SYMBOLS.find(symbol)))
	return out


## The amount the cells read now, rounded to whole symbols (for checks).
func shown() -> String:
	var text := ""
	for i in CELLS:
		text += SYMBOLS[clampi(roundi(_at[i]), 0, SYMBOLS.length() - 1)]
	return text.strip_edges()


func _advance(delta: float) -> bool:
	_roll = minf(_roll + delta / ROLL_SECONDS, 1.0)
	var eased := cubic_bezier(_roll, 0.9, 0.01, 0.1, 1.0)
	for i in CELLS:
		_at[i] = lerpf(_from[i], _to[i], eased)
	if _roll >= 1.0:
		_roll = -1.0
		return false
	return true


func redraw() -> void:
	super()
	if _band != null:
		_band.queue_redraw()


func _draw() -> void:
	if not may_buy:
		return
	var texture := HudStyle.icon("icons/ui/buyzone")
	if texture != null:
		HudStyle.draw_fitted(self, texture, CART, HudStyle.BUY_GREEN)
	else:
		_draw_cart(CART, HudStyle.BUY_GREEN)


## The cells, each its strip of symbols moved up to the one it shows.
func _draw_cells() -> void:
	var colour := HudStyle.team_colour(team)
	var font := HudStyle.face(&"mono_bold")
	var baseline := font.get_ascent(TEXT_SIZE)
	for i in CELLS:
		var centre := FIRST_CENTRE - BAND.position.x + i * PITCH
		var at := _at[i]
		# Only the symbols that can show in the band this frame: the one it is
		# on and the next.
		for index: int in [floori(at), floori(at) + 1]:
			if index < 0 or index >= SYMBOLS.length():
				continue
			var y := (index - at) * BAND.size.y
			if absf(y) >= BAND.size.y:
				continue
			var symbol := SYMBOLS[index]
			if symbol == " ":
				continue
			HudStyle.draw_text(_band, Vector2(centre, y + baseline), symbol, TEXT_SIZE, colour,
				HORIZONTAL_ALIGNMENT_CENTER, &"mono_bold")


## CSS's cubic-bezier timing: the curve's y where its x is `t`.
static func cubic_bezier(t: float, x1: float, y1: float, x2: float, y2: float) -> float:
	if t <= 0.0 or t >= 1.0:
		return clampf(t, 0.0, 1.0)
	# Solve x(s) = t for s by bisection; x is monotonic for x1, x2 in [0, 1].
	var low := 0.0
	var high := 1.0
	var s := t
	for i in 24:
		s = (low + high) * 0.5
		var x := _bezier(s, x1, x2)
		if x < t:
			low = s
		else:
			high = s
	return _bezier(s, y1, y2)


static func _bezier(s: float, p1: float, p2: float) -> float:
	var u := 1.0 - s
	return 3.0 * u * u * s * p1 + 3.0 * u * s * s * p2 + s * s * s


## A shopping cart, where CS2's is not extracted.
func _draw_cart(box: Rect2, colour: Color) -> void:
	var s := box.size.x / 30.0
	var o := box.position
	var basket := PackedVector2Array([
		o + Vector2(7, 8) * s, o + Vector2(27, 8) * s, o + Vector2(24, 19) * s, o + Vector2(10, 19) * s,
	])
	draw_polyline(PackedVector2Array([o + Vector2(2, 4) * s, o + Vector2(6, 4) * s, o + Vector2(10, 19) * s,
		o + Vector2(10, 22) * s, o + Vector2(25, 22) * s]), colour, 2.0 * s, true)
	draw_colored_polygon(basket, colour)
	draw_circle(o + Vector2(12, 26) * s, 2.2 * s, colour)
	draw_circle(o + Vector2(23, 26) * s, 2.2 * s, colour)
