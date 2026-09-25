class_name MoneyPanel
extends HudElement

## Your money in the bottom left, as CS2 draws it (CSGOMoneyPanel,
## hudmoney.xml and .css): "$" and the amount in the team's colour, rolling
## to a new amount rather than jumping (the game rolls each digit), and
## while you may buy, the buy zone's cart beside it in light green with the
## key that opens the menu.
##
## It only draws what GameHud gives it each frame, and redraws only when
## that changes or while the amount rolls (HudElement).

## The amount's size and place, measured from CS2 at 4K
## (reference/cs2 _screenshots/In_game_ui.webp) and halved to the base size:
## 18 px in from the left, its baseline 30 px up from the bottom.
const TEXT_SIZE := 36
const LEFT := 18.0
const BASELINE_UP := 30.0
## The cart, 30 px with 6 px either side (hudmoney.css .money-text-buy-icon).
const CART_SIZE := 30.0
## How long a change in the amount takes to roll, in seconds. By eye.
const ROLL_SECONDS := 0.4

var team: String = "T"
var amount: int = 0
## Whether the cart shows.
var may_buy: bool = false
## The key the menu opens on, beside the cart.
var buy_key: String = "B"

var _shown: float = 0.0
var _rolling_from: float = 0.0
var _roll_left: float = 0.0
var _started: bool = false


func _ready() -> void:
	place(Vector2(0.0, 1.0), Rect2(0, -80, 360, 80))


func show_values(side: String, money: int, buying: bool) -> void:
	if not _started:
		_started = true
		_shown = money
		amount = money
	if money != amount:
		_rolling_from = _shown
		_roll_left = ROLL_SECONDS
		animate()
	team = side
	amount = money
	may_buy = buying
	show_state([side, money, buying])


## The amount on screen now, mid-roll or not.
func shown() -> int:
	return roundi(_shown)


func _advance(delta: float) -> bool:
	_roll_left = maxf(_roll_left - delta, 0.0)
	var t := 1.0 - _roll_left / ROLL_SECONDS
	_shown = lerpf(_rolling_from, amount, 1.0 - pow(1.0 - t, 3.0))
	return _roll_left > 0.0


func _draw() -> void:
	var baseline := size.y - BASELINE_UP
	var width := HudStyle.draw_text(self, Vector2(LEFT, baseline), GameHud.money_text(shown()), TEXT_SIZE,
		HudStyle.team_colour(team))
	if not may_buy:
		return
	var cart := Rect2(Vector2(LEFT + width + 8.0, baseline - CART_SIZE + 2.0), Vector2.ONE * CART_SIZE)
	var texture := HudStyle.icon("icons/ui/buyzone")
	if texture != null:
		HudStyle.draw_fitted(self, texture, cart, HudStyle.BUY_GREEN)
	else:
		_draw_cart(cart, HudStyle.BUY_GREEN)
	# The key, in a small box, as CS2 shows the bound key's glyph there.
	var key_box := Rect2(Vector2(cart.end.x + 6.0, baseline - 20.0), Vector2(20, 20))
	draw_rect(key_box, Color(HudStyle.BUY_GREEN, 0.9), false, 1.5)
	HudStyle.draw_text(self, Vector2(key_box.get_center().x, key_box.end.y - 4.0), buy_key, 15,
		HudStyle.BUY_GREEN, HORIZONTAL_ALIGNMENT_CENTER)


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
