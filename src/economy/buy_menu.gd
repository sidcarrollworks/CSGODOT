class_name BuyMenu
extends HudElement

## CS2's buy menu: five columns (pistols, mid-tier, rifles, equipment,
## grenades) of the player's loadout, each item a card with its key, name,
## icon and price, the way CS2 draws them (buymenu.xml and buymenu.css,
## GameTracking-CS2 2026-09-23): a dark panel (rgba 0,0,0,0.75), 90 px
## cards with a faint grey fill and 5 px corners, the key in the top left
## at 40 %, the name top right, the icon in the middle and the price bottom
## right in the team's colour; an item that cannot be bought greyed, one you
## cannot afford with its price greyed, one you own outlined in white, the
## card under the mouse brighter. Above the columns your money and the buy
## time left, as CS2's info panel has them. CS2 also stands your agent to
## the left of it; this does not.
##
## It only reads the economy and asks it for purchases (Economy.buy and
## undo), which the next tick carries out, so it is drawing, not game state,
## and would work the same on a client.
##
## It is one HudElement: the whole menu is drawn in one `_draw()` and hit-
## tested by hand, with no Button or container nodes, and redraws only when
## something on it changes (the money, an item's state, the card under the
## mouse, the time left).
##
## B opens and closes it, as in CS2, and so does Escape. With it open the
## mouse is free and the view holds still; moving still works. Click an item
## to buy it, right-click one bought this round to undo it. The keys work
## as CS2's do: a number picks a column, a second number an item in it
## (B 3 2 is the AK-47 or the M4A1-S), and no other key press gets past it
## while it is open. It closes itself when buying is over
## for you: buy time ends, you leave the buy zone, or you die.

## buymenu.css: the body 950 px wide, a column padded 15 px each side, a card
## 90 px tall with 10 px under it, the column's title 28 px, a card's text
## 14 px and the key 18 px. The whole screen behind goes 95 % black
## (.buymenu), and each column is as wide as its kind (.ccpistols 18 %,
## .ccmidtier 22 %, .ccrifles 24 %, .ccequip and .ccgrenades 18 %), so the
## rifles' long icons get the widest.
const BODY_WIDTH := 950.0
const BACKDROP := Color(0, 0, 0, 0.95)
const COLUMN_SHARES := {"Pistols": 0.18, "Mid-Tier": 0.22, "Rifles": 0.24, "Equipment": 0.18, "Grenades": 0.18}
const COLUMN_PADDING := 15.0
const CARD_HEIGHT := 90.0
const CARD_GAP := 10.0
const HEADER_HEIGHT := 64.0
const TITLE_HEIGHT := 46.0
const FOOTER_HEIGHT := 40.0
const BACKGROUND := Color(0, 0, 0, 0.75)
const CARD_FILL := Color(0.45, 0.45, 0.45, 0.2)
const CARD_FILL_HOVER := Color(0.62, 0.62, 0.62, 0.36)
const CARD_CANT := Color(0.169, 0.169, 0.169, 0.897)
const GREY_TEXT := Color(0.5, 0.5, 0.5)
const GREY_ICON := Color(0.25, 0.25, 0.25)

## The economy it shows and the player it is for.
var economy: Economy
var userid: int = -1

var _picked_column: int = -1
var _hovered: String = ""
var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
## Each item's card this frame: item class to its rectangle, in this
## element's coordinates.
var _cards := {}
## What each card shows this frame: item class to [refusal, price, owned].
var _items := {}

## B was pressed where the menu may not open: why (Economy's refusal), for
## the HUD to say.
signal refused(reason: StringName)


func _ready() -> void:
	visible = false
	place(Vector2.ZERO, Rect2())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func is_open() -> bool:
	return visible


func open() -> void:
	if economy == null or visible:
		return
	var why := economy.shop_refusal(userid)
	if why != Economy.OK:
		refused.emit(why)
		return
	_picked_column = -1
	_hovered = ""
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_mouse_before = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	Input.set_mouse_mode(_mouse_before)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"buy_menu"):
		close() if visible else open()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	# While it is open the menu owns the keyboard: every key press stops here,
	# so nothing behind it (grenades, the range's keys) acts on it. Movement
	# is polled, so it keeps working.
	var key := event as InputEventKey
	if key != null and key.pressed:
		var number := key.physical_keycode - KEY_1
		if not key.echo and number >= 0 and number < Loadout.COLUMNS.size():
			_press_number(number)
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var over := item_under(motion.position)
		if over != _hovered:
			_hovered = over
			_refresh()
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	var item := item_under(click.position)
	if item.is_empty():
		return
	if click.button_index == MOUSE_BUTTON_LEFT:
		economy.buy(userid, item)
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		economy.undo(userid, item)
	accept_event()


## The item whose card is at `point`, or none.
func item_under(point: Vector2) -> String:
	for item: String in _cards:
		if (_cards[item] as Rect2).has_point(point):
			return item
	return ""


func _press_number(number: int) -> void:
	if _picked_column < 0:
		_picked_column = number
		_refresh()
		return
	var item := Loadout.item_at(_side(), _picked_column, number)
	_picked_column = -1
	_refresh()
	if not item.is_empty():
		economy.buy(userid, item)


func _process(_delta: float) -> void:
	if not visible:
		return
	if not _may_shop():
		close()
		return
	_refresh()


## Reads what the menu shows and redraws if any of it changed.
func _refresh() -> void:
	var side := _side()
	_layout(side)
	_items.clear()
	var seconds := economy.buy_seconds_left(SimClock.now_usec())
	var signature: Array = [side, economy.money(userid), _hovered, _picked_column,
		-1 if is_inf(seconds) else ceili(seconds), size]
	for item: String in _cards:
		var why := economy.refusal(userid, item)
		var owned := why == Economy.ALREADY_HAVE or economy.can_undo(userid, item)
		_items[item] = [why, economy.price_for(userid, item), owned]
		signature.append_array(_items[item])
	show_state(signature)


## Where every card goes, for the side's loadout, centred on the screen.
func _layout(side: String) -> void:
	_cards.clear()
	var body := _body()
	for column in Loadout.COLUMNS.size():
		var span := _column(column, body)
		for place in Loadout.PLACES:
			var item := Loadout.item_at(side, column, place)
			if item.is_empty() or not ItemRegistry.has(item):
				continue
			_cards[item] = Rect2(
				span.position.x + COLUMN_PADDING,
				body.position.y + HEADER_HEIGHT + TITLE_HEIGHT + place * (CARD_HEIGHT + CARD_GAP),
				span.size.x - 2.0 * COLUMN_PADDING, CARD_HEIGHT)


## A column's share of the body, left to right.
func _column(column: int, body: Rect2) -> Rect2:
	var x := body.position.x
	for before in column:
		x += body.size.x * float(COLUMN_SHARES.get(Loadout.COLUMNS[before]["name"], 0.2))
	var width := body.size.x * float(COLUMN_SHARES.get(Loadout.COLUMNS[column]["name"], 0.2))
	return Rect2(x, body.position.y, width, body.size.y)


func _body() -> Rect2:
	var height := HEADER_HEIGHT + TITLE_HEIGHT + Loadout.PLACES * (CARD_HEIGHT + CARD_GAP) + FOOTER_HEIGHT
	return Rect2((size - Vector2(BODY_WIDTH, height)) * 0.5, Vector2(BODY_WIDTH, height))


func _draw() -> void:
	if not visible or economy == null:
		return
	var side := _side()
	var colour := HudStyle.team_colour(side)
	var body := _body()
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	draw_rect(body.grow(12.0), BACKGROUND)

	# CS2's info panel: the money, and the buy time left.
	var seconds := economy.buy_seconds_left(SimClock.now_usec())
	var top := body.position.y + 36.0
	HudStyle.draw_text(self, Vector2(body.position.x + COLUMN_PADDING, top), GameHud.money_text(economy.money(userid)),
		30, colour)
	var left := "No time limit" if is_inf(seconds) else "Time left  %s" % GameHud.clock_text(seconds)
	HudStyle.draw_text(self, Vector2(body.end.x - COLUMN_PADDING, top), left, 18, Color(1, 1, 1, 0.8),
		HORIZONTAL_ALIGNMENT_RIGHT, &"medium")
	draw_line(Vector2(body.position.x, body.position.y + HEADER_HEIGHT - 12.0),
		Vector2(body.end.x, body.position.y + HEADER_HEIGHT - 12.0), Color(1, 1, 1, 0.08), 1.0)

	# Each column's key and title; the other columns dimmed once one is
	# picked by its key, as CS2 does (brightness 0.3).
	for column in Loadout.COLUMNS.size():
		var span := _column(column, body)
		var dim := 1.0 if _picked_column < 0 or _picked_column == column else 0.3
		var title_y := body.position.y + HEADER_HEIGHT + 22.0
		HudStyle.draw_text(self, Vector2(span.position.x + COLUMN_PADDING, title_y), str(column + 1), 18, Color(1, 1, 1, 0.5 * dim))
		HudStyle.draw_text(self, Vector2(span.get_center().x, title_y), String(Loadout.COLUMNS[column]["name"]),
			24, Color(1, 1, 1, dim), HORIZONTAL_ALIGNMENT_CENTER, &"medium")

	for item: String in _cards:
		_draw_card(item, _cards[item], colour, body)

	# The footer: why the card under the mouse cannot be bought, or the keys.
	var said := ""
	if not _hovered.is_empty() and _items.has(_hovered) and _items[_hovered][0] != Economy.OK:
		said = Economy.MESSAGES.get(_items[_hovered][0], "")
	if said.is_empty():
		said = "Click: buy    Right-click: undo    1-5 then 1-5: buy by keys    B / Esc: close"
	HudStyle.draw_text(self, Vector2(body.get_center().x, body.end.y - 12.0), said, 16, Color(1, 1, 1, 0.7),
		HORIZONTAL_ALIGNMENT_CENTER, &"medium")


func _draw_card(item: String, card: Rect2, colour: Color, body: Rect2) -> void:
	var why: StringName = _items[item][0]
	var price: int = _items[item][1]
	var owned: bool = _items[item][2]
	var column := 0
	while column + 1 < Loadout.COLUMNS.size() and card.position.x >= _column(column + 1, body).position.x:
		column += 1
	var place := roundi((card.position.y - body.position.y - HEADER_HEIGHT - TITLE_HEIGHT) / (CARD_HEIGHT + CARD_GAP))
	var dim := 1.0 if _picked_column < 0 or _picked_column == column else 0.3
	# Owning it is not "cannot buy": it shows as owned, outlined.
	var cant := why != Economy.OK and why != Economy.NO_MONEY and not owned
	var fill := CARD_CANT if cant else (CARD_FILL_HOVER if item == _hovered else CARD_FILL)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill, fill.a * dim)
	style.set_corner_radius_all(5)
	if owned:
		style.border_color = Color(1, 1, 1, dim)
		style.set_border_width_all(1)
	draw_style_box(style, card)
	var text := GREY_TEXT if cant else colour
	text.a *= dim
	HudStyle.draw_text(self, card.position + Vector2(8, 20), str(place + 1), 18, Color(1, 1, 1, 0.4 * dim))
	var name := ItemRegistry.item(item).name
	var icon := HudStyle.item_icon(item)
	var icon_box := Rect2(card.position + Vector2(10, card.size.y * 0.3), Vector2(card.size.x - 20.0, card.size.y * 0.45))
	if icon != null:
		HudStyle.draw_text(self, Vector2(card.end.x - 8.0, card.position.y + 18.0), name,
			_fitting(name, 14, card.size.x - 34.0), text, HORIZONTAL_ALIGNMENT_RIGHT, &"medium")
		HudStyle.draw_fitted(self, icon, icon_box, GREY_ICON if cant else Color(colour, dim))
	else:
		# Without CS2's icons, the name in the icon's place.
		var fitted := _fitting(name, 20, icon_box.size.x)
		HudStyle.draw_text(self, Vector2(icon_box.get_center().x, HudStyle.baseline_centred(icon_box.get_center().y, fitted, &"medium")),
			name, fitted, text, HORIZONTAL_ALIGNMENT_CENTER, &"medium")
	var price_colour := GREY_TEXT if cant or why == Economy.NO_MONEY else colour
	price_colour.a *= dim
	var price_text := "Owned" if owned and why == Economy.ALREADY_HAVE else "$%d" % price
	HudStyle.draw_text(self, card.end - Vector2(8, 8), price_text, 16, price_colour, HORIZONTAL_ALIGNMENT_RIGHT)


## The largest size up to `wanted` at which `text` fits in `width`.
static func _fitting(text: String, wanted: int, width: float) -> int:
	var size := wanted
	while size > 10 and HudStyle.face(&"medium").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 1
	return size


## Whether this player can shop at all now; the menu closes when not.
func _may_shop() -> bool:
	return economy.shop_refusal(userid) == Economy.OK


func _side() -> String:
	return economy.game.roster.team_of(userid) if economy.game != null else ""
