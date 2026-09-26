class_name BuyMenu
extends HudElement

## CS2's buy menu, as its own files lay it out (panorama/layout/buymenu.xml
## and styles/buymenu.css, decompiled from the game) and as Sid's screenshots
## of it show it (2026-09-25): the game behind lightly blurred and dimmed,
## your money and the buy time left in a bar across the top, five columns of
## cards under it (Equipment, Pistols, Mid-Tier, Rifles and Grenades, keyed 1
## to 5 in that order, each as wide as its kind), the dropped weapons' panel
## below, the keys along the bottom, and on the right your agent in CS2's own
## pose for what is in your hand, or what the mouse is over, holding it
## (BuyMenuAgent), with that item's name and CS2's word on it. The team counter and your money stay over it; the
## health and ammo, the crosshair and the alerts go.
##
## A card is CS2's: a soft grey from the middle out, 5 px corners, the key at
## 40 % in the top left, the name top right, the icon in the middle at 45 % of
## the height and the price bottom right, in the team's colour; under the
## mouse twice as bright (brightness 2.2). One you cannot buy is dark with
## its icon and words grey; one you own is outlined in white, with a pip in
## the colour of each of your team who carries it; one you cannot afford
## has its price grey.
##
## It only reads the economy and asks it for purchases (Economy.buy and
## undo), which the next tick carries out, so it is drawing, not game state,
## and would work the same on a client. It is one HudElement: the menu is
## drawn in `_draw()` and hit-tested by hand, and redraws only when
## something on it changes.
##
## B opens and closes it, as in CS2, and so does Escape. With it open the
## mouse is free and the view holds still; moving still works. Click an item
## to buy it, right-click one bought this round to refund it, Delete refunds
## them all (CS2's sellbackall). The keys work as CS2's do: a number picks a
## column, a second number an item in it (B 4 2 is the AK-47 or the M4A1-S),
## and no other key press gets past it while it is open. It closes itself
## when buying is over for you: buy time ends, you leave the buy zone, or
## you die.

## The columns in CS2's order, as the loadout's (Loadout.COLUMNS keeps CS2's
## slot order, which purchases are numbered by), and each one's share of the
## body (.ccequip, .ccpistols, .ccmidtier, .ccrifles, .ccgrenades).
const COLUMN_ORDER := [3, 0, 1, 2, 4]
const COLUMN_SHARES := [0.18, 0.18, 0.22, 0.24, 0.18]

## Where it all goes (buymenu.css; the screenshot agrees to the pixel): the
## left part (a 16 px margin and the 950 px body) and the right (the item's
## panel, 350 px with 32 before it) side by side, centred and moved 50 px
## left, the left part 180 px down.
const BODY_WIDTH := 950.0
const LEFT_MARGIN := 16.0
const RIGHT_WIDTH := 382.0
const SHIFT := 50.0
const TOP := 180.0
## The money and time's bar (.buymenu-info: 22 px text padded 6 above and
## below) with 4 under it; the columns' titles (28 px) with 15 under them; a
## card 90 tall with 10 under it; a column padded 15 either side.
const INFO_HEIGHT := 38.0
const INFO_GAP := 4.0
const TITLE_HEIGHT := 34.0
const TITLE_GAP := 15.0
const CARD_HEIGHT := 90.0
const CARD_GAP := 10.0
const COLUMN_PADDING := 15.0
## The dropped weapons' panel: 10 below the body, 216 tall.
const GROUND_GAP := 10.0
const GROUND_HEIGHT := 216.0
## The item's panel: 350 by 110, 670 px down in the right part, which is
## padded 38 at the top (.buymenu-item-info, .buymenu-right).
const ITEM_PANEL := Vector2(350.0, 110.0)
const ITEM_PANEL_TOP := 38.0 + 670.0
## A failed purchase's bar (.buymenu__purchase-failure): 30 tall, 120 up from
## the bottom of the right part.
const FAILURE_HEIGHT := 30.0
const FAILURE_SECONDS := 2.0
## The keys along the bottom (.buymenu-navbar: 24 px bold condensed capitals,
## a faint line over them).
const NAV_SIZE := 24
const NAV_BASELINE := 1061.0
const NAV_LINE := 1024.0
## Where the picture of your agent starts, right of the screen's middle: CS2
## draws its whole screen through its camera (BuyMenuAgent), and the agent
## and anything in its hands stay right of this.
const AGENT_FROM := 60.0

## The colours: the screen behind, the panels (buymenuBackgroundColor), a
## card's fill from its middle to its edge, a card that cannot be bought, its
## icon and words, the item panel, a failure's bar, the name of a stock item
## (.common). The screen behind is .buymenu's rgba(0, 0, 0, 0.95) with the
## game drawn back over it by the agent's panel (game-background), which
## leaves it as Sid's screenshot measures it: nothing darker than about 30
## and nothing brighter than about 68 (of 255), the floor's black tiles and a
## sign's white letters alike; in linear light, the world under this grey.
const BACKDROP := Color(31.0 / 255.0, 31.0 / 255.0, 31.0 / 255.0, 0.955)
const PANEL := Color(0, 0, 0, 0.75)
const CARD_CENTRE := Color(141.0 / 255.0, 141.0 / 255.0, 141.0 / 255.0, 0.2)
const CARD_EDGE := Color(85.0 / 255.0, 85.0 / 255.0, 85.0 / 255.0, 0.2)
const CARD_CANT := Color(43.0 / 255.0, 43.0 / 255.0, 43.0 / 255.0, 0.897)
const CANT_ICON := Color8(64, 64, 64)
const GREY := Color8(128, 128, 128)
const HOVER := 2.2
const ITEM_PANEL_FILL := Color(0, 0, 0, 208.0 / 255.0)
const FAILURE_FILL := Color(163.0 / 255.0, 148.0 / 255.0, 14.0 / 255.0, 0.87)
const STOCK_NAME := Color8(153, 153, 153)
const TIME_TITLE := Color(1, 1, 1, 0.356)
const DOTS_OPACITY := 0.01
const DOTS_SIZE := 360.0
## How strongly the game behind is blurred: lightly, since the letters of a
## sign behind still read in Sid's screenshot (the HUD's panels read 4).
const BACKDROP_BLUR := 1.5
## CS2's word on each item, extracted with the HUD (csgo_english.txt's
## csgo_item_usage_desc_*): Valve's text, so read from assets/ where it is.
const USAGE_FILE := "res://assets/hud/resource/item_usage.txt"

## The economy it shows and the player it is for.
var economy: Economy
var userid: int = -1
## The match, where there is one, for the colours of the pips.
var match_state: MatchState

## Your agent on the right; null where its model is not extracted.
var agent: BuyMenuAgent

var _picked_column: int = -1
var _hovered: String = ""
var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
## Each item's card this frame: item class to its rectangle.
var _cards := {}
## What each card shows this frame: item class to [refusal, price, owned].
var _items := {}
var _failure := ""
var _failure_left := 0.0
static var _usage := {}

## B was pressed where the menu may not open: why (Economy's refusal), for
## the HUD to say.
signal refused(reason: StringName)


func _ready() -> void:
	visible = false
	place(Vector2.ZERO, Rect2())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _blur != null:
		_blur.material = HudStyle.world_blur(BACKDROP_BLUR)


## Stands your side's agent beside the menu, built now rather than when the
## menu first opens, so opening it reads nothing.
func build_agent(side: String) -> void:
	if agent != null:
		agent.queue_free()
		agent = null
	var built := BuyMenuAgent.new()
	built.name = "Agent"
	add_child(built)
	if not built.build(side):
		built.queue_free()
		return
	agent = built
	_size_agent()
	if not get_viewport().size_changed.is_connected(_size_agent):
		get_viewport().size_changed.connect(_size_agent)


## Sizes the agent's picture to the screen's pixels, and frames it.
func _size_agent() -> void:
	if agent == null:
		return
	var rect := _agent_rect()
	var scale := get_viewport().get_stretch_transform().get_scale()
	agent.size = Vector2i(maxi(roundi(rect.size.x * scale.x), 16), maxi(roundi(rect.size.y * scale.y), 16))
	agent.frame(rect, size)


## The part of the screen the agent's picture covers.
func _agent_rect() -> Rect2:
	var from := size.x * 0.5 + AGENT_FROM
	return Rect2(from, 0.0, size.x - from, size.y)


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
	_failure_left = 0.0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_mouse_before = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if agent != null:
		agent.draw_while(true)
		agent.show_item(_in_hand())
	_refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	Input.set_mouse_mode(_mouse_before)
	if agent != null:
		agent.draw_while(false)
	redraw()


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
		if not key.echo and number >= 0 and number < COLUMN_ORDER.size():
			_press_number(number)
		elif not key.echo and key.physical_keycode == KEY_DELETE:
			refund_all()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var over := item_under(motion.position)
		if over != _hovered:
			_hovered = over
			if agent != null:
				agent.show_item(over if not over.is_empty() else _in_hand())
			_refresh()
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	var item := item_under(click.position)
	if item.is_empty():
		return
	if click.button_index == MOUSE_BUTTON_LEFT:
		_try_buy(item)
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		economy.undo(userid, item)
	accept_event()


## The item whose card is at `point`, or none.
func item_under(point: Vector2) -> String:
	for item: String in _cards:
		if (_cards[item] as Rect2).has_point(point):
			return item
	return ""


## Refunds everything bought this round that can be (CS2's sellbackall).
func refund_all() -> void:
	for item in Loadout.items(_side()):
		if economy.can_undo(userid, item):
			economy.undo(userid, item)


func _press_number(number: int) -> void:
	if _picked_column < 0:
		_picked_column = number
		_refresh()
		return
	var item := Loadout.item_at(_side(), COLUMN_ORDER[_picked_column], number)
	_picked_column = -1
	_refresh()
	if not item.is_empty():
		_try_buy(item)


## Asks for it; one that will not go through says why in the failure's bar,
## as CS2's does.
func _try_buy(item: String) -> void:
	var why := economy.refusal(userid, item)
	if why != Economy.OK and why != Economy.ALREADY_HAVE:
		_failure = Economy.MESSAGES.get(why, "")
		_failure_left = FAILURE_SECONDS
	economy.buy(userid, item)


func _process(delta: float) -> void:
	if not visible:
		return
	if not _may_shop():
		close()
		return
	if _failure_left > 0.0:
		_failure_left = maxf(_failure_left - delta, 0.0)
	_refresh()


## Reads what the menu shows and redraws if any of it changed.
func _refresh() -> void:
	var side := _side()
	_layout(side)
	_items.clear()
	var seconds := buy_seconds_shown()
	var signature: Array = [side, economy.money(userid), _hovered, _picked_column,
		-1 if is_inf(seconds) else ceili(seconds), size, _failure_left > 0.0]
	for item: String in _cards:
		var why := economy.refusal(userid, item)
		var owned := why == Economy.ALREADY_HAVE or economy.can_undo(userid, item)
		_items[item] = [why, economy.price_for(userid, item), owned, _carriers(item)]
		signature.append_array(_items[item])
	show_state(signature)


## Where every card goes, for the side's loadout.
func _layout(side: String) -> void:
	_cards.clear()
	var body := _body()
	for column in COLUMN_ORDER.size():
		var span := _column(column, body)
		for place in Loadout.PLACES:
			var item := Loadout.item_at(side, COLUMN_ORDER[column], place)
			if item.is_empty() or not ItemRegistry.has(item):
				continue
			_cards[item] = Rect2(span.position.x + COLUMN_PADDING,
				body.position.y + TITLE_HEIGHT + TITLE_GAP + place * (CARD_HEIGHT + CARD_GAP),
				span.size.x - 2.0 * COLUMN_PADDING, CARD_HEIGHT)


## The body: the titles and the cards.
func _body() -> Rect2:
	var left := (size.x - (LEFT_MARGIN + BODY_WIDTH + RIGHT_WIDTH)) * 0.5 - SHIFT + LEFT_MARGIN
	var top := TOP + INFO_HEIGHT + INFO_GAP
	return Rect2(left, top, BODY_WIDTH, TITLE_HEIGHT + TITLE_GAP + Loadout.PLACES * (CARD_HEIGHT + CARD_GAP))


## A column's share of the body, left to right in CS2's order.
func _column(column: int, body: Rect2) -> Rect2:
	var x := body.position.x
	for before in column:
		x += body.size.x * float(COLUMN_SHARES[before])
	return Rect2(x, body.position.y, body.size.x * float(COLUMN_SHARES[column]), body.size.y)


## The buy time the bar counts down, in seconds (CS2's countdown always shows
## a time): the economy's once its clock runs; before that, what is left of
## it all the same, the rest of freeze time and the buy time after it, or in
## warmup, which buying lasts, the warmup's clock; INF where nothing ends it.
func buy_seconds_shown() -> float:
	var now := SimClock.now_usec()
	var seconds := economy.buy_seconds_left(now)
	if not is_inf(seconds) or match_state == null:
		return seconds
	match match_state.phase:
		MatchState.Phase.WARMUP:
			return match_state.seconds_left(now)
		MatchState.Phase.FREEZE:
			return match_state.seconds_left(now) + economy.rules.buy_seconds
	return seconds


## The world behind, blurred, the whole screen while it is open.
func _blur_rect() -> Rect2:
	return Rect2(Vector2.ZERO, size) if visible else Rect2()


func _draw_blur(on: CanvasItem) -> void:
	if visible:
		on.draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)


func _draw() -> void:
	if not visible or economy == null:
		return
	var side := _side()
	var colour := HudStyle.team_colour(side)
	var body := _body()
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	if agent != null:
		draw_texture_rect(agent.get_texture(), _agent_rect(), false)

	# The bar across the top: your money on the left, the buy time left in the
	# middle, and the least you will have next round on the right.
	var info := Rect2(body.position.x, TOP, BODY_WIDTH, INFO_HEIGHT)
	_draw_panel(info)
	var middle_y := info.get_center().y
	HudStyle.draw_text(self, Vector2(info.position.x + 10.0, HudStyle.baseline_centred(middle_y, 22)),
		GameHud.money_text(economy.money(userid)), 22, colour)
	var seconds := buy_seconds_shown()
	var title := "Buy Time Remaining"
	var clock := "--:--" if is_inf(seconds) else _two_digit_clock(seconds)
	var title_width := HudStyle.face(&"regular").get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var clock_width := HudStyle.face().get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var start := info.get_center().x - (title_width + 10.0 + clock_width) * 0.5
	HudStyle.draw_text(self, Vector2(start, HudStyle.baseline_centred(middle_y, 22, &"regular")), title, 22, TIME_TITLE,
		HORIZONTAL_ALIGNMENT_LEFT, &"regular")
	HudStyle.draw_text(self, Vector2(start + title_width + 10.0, HudStyle.baseline_centred(middle_y, 22)), clock, 22,
		Color.WHITE)
	HudStyle.draw_text(self, Vector2(info.end.x - 10.0, HudStyle.baseline_centred(middle_y, 14, &"regular")),
		"Next Round Minimum: %s" % _thousands(next_round_minimum()), 14, GREY, HORIZONTAL_ALIGNMENT_RIGHT, &"regular")

	# The body, each column's key and title over its cards; the other columns
	# dimmed once one is picked by its key (brightness 0.3).
	_draw_panel(body)
	for column in COLUMN_ORDER.size():
		var span := _column(column, body)
		var dim := 1.0 if _picked_column < 0 or _picked_column == column else 0.3
		var title_middle := body.position.y + TITLE_HEIGHT * 0.5
		if _picked_column < 0:
			HudStyle.draw_text(self, Vector2(span.position.x + COLUMN_PADDING, HudStyle.baseline_centred(title_middle, 18, &"mono_bold")),
				str(column + 1), 18, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_LEFT, &"mono_bold")
		HudStyle.draw_text(self, Vector2(span.get_center().x, HudStyle.baseline_centred(title_middle, 28, &"medium_condensed")),
			String(Loadout.COLUMNS[COLUMN_ORDER[column]]["name"]), 28, Color(dim, dim, dim), HORIZONTAL_ALIGNMENT_CENTER,
			&"medium_condensed")
	for item: String in _cards:
		_draw_card(item, _cards[item], colour, body)

	# The dropped weapons' panel, its faint title over nothing yet.
	var ground := Rect2(body.position.x, body.end.y + GROUND_GAP, BODY_WIDTH, GROUND_HEIGHT)
	_draw_panel(ground)
	var title_font := HudStyle.face(&"medium_condensed")
	var ground_title := "Dropped Weapons"
	var spaced := title_font.get_string_size(ground_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 90).x + 10.0 * (ground_title.length() - 1)
	var x := ground.get_center().x - spaced * 0.5
	for letter in ground_title:
		HudStyle.draw_text(self, Vector2(x, HudStyle.baseline_centred(ground.get_center().y, 90, &"medium_condensed")), letter, 90,
			Color(1, 1, 1, 4.0 / 255.0), HORIZONTAL_ALIGNMENT_LEFT, &"medium_condensed")
		x += title_font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 90).x + 10.0

	# The right part: the item under the mouse, and a failed purchase's bar.
	var right_left := body.end.x + 32.0
	if not _hovered.is_empty():
		_draw_item_panel(Rect2(Vector2(right_left, ITEM_PANEL_TOP), ITEM_PANEL), _hovered)
	if _failure_left > 0.0 and not _failure.is_empty():
		var bar := Rect2(right_left, size.y - 120.0 - FAILURE_HEIGHT - 60.0, ITEM_PANEL.x, FAILURE_HEIGHT)
		draw_rect(bar, FAILURE_FILL)
		HudStyle.draw_text(self, Vector2(bar.get_center().x, HudStyle.baseline_centred(bar.get_center().y, 22, &"condensed")),
			_failure, 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, &"condensed")

	# The keys along the bottom.
	var keys := PackedStringArray(["[Right click] Refund", "[Del] Refund all", "[Escape] Back"])
	var widths: Array[float] = []
	var total := 0.0
	var nav_font := HudStyle.face(&"bold_condensed")
	for label in keys:
		var width := nav_font.get_string_size(label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, NAV_SIZE).x
		widths.append(width)
		total += width
	total += 32.0 * (keys.size() - 1)
	draw_line(Vector2(size.x * 0.5 - total * 0.5 - 24.0, NAV_LINE), Vector2(size.x * 0.5 + total * 0.5 + 24.0, NAV_LINE),
		Color(1, 1, 1, 0.05), 1.0)
	x = size.x * 0.5 - total * 0.5
	for i in keys.size():
		HudStyle.draw_text(self, Vector2(x, NAV_BASELINE), keys[i].to_upper(), NAV_SIZE, colour, HORIZONTAL_ALIGNMENT_LEFT,
			&"bold_condensed")
		x += widths[i] + 32.0


## A dark panel with CS2's faint dots.
func _draw_panel(box: Rect2) -> void:
	draw_rect(box, PANEL)
	var dots := HudStyle.icon("backgrounds/bluedots_large_png")
	if dots != null:
		var scale := dots.get_size().x / DOTS_SIZE
		draw_texture_rect_region(dots, box, Rect2(Vector2.ZERO, box.size * scale), Color(1, 1, 1, DOTS_OPACITY))


func _draw_card(item: String, card: Rect2, colour: Color, body: Rect2) -> void:
	var why: StringName = _items[item][0]
	var price: int = _items[item][1]
	var owned: bool = _items[item][2]
	var carriers: Array = _items[item][3]
	var column := 0
	while column + 1 < COLUMN_ORDER.size() and card.position.x >= _column(column + 1, body).position.x:
		column += 1
	var dim := 1.0 if _picked_column < 0 or _picked_column == column else 0.3
	var cant := why != Economy.OK and why != Economy.NO_MONEY
	var bright := HOVER if item == _hovered else 1.0
	var lit := func(tint: Color) -> Color:
		return Color(minf(tint.r * bright * dim, 1.0), minf(tint.g * bright * dim, 1.0), minf(tint.b * bright * dim, 1.0), tint.a)

	# The fill: CS2's grey from the middle out, or the dark of one you cannot
	# buy; round at the corners.
	if cant:
		_draw_rounded(card, lit.call(CARD_CANT), lit.call(CARD_CANT))
	else:
		_draw_rounded(card, lit.call(CARD_CENTRE), lit.call(CARD_EDGE))
	if owned:
		var border := StyleBoxFlat.new()
		border.draw_center = false
		border.set_corner_radius_all(5)
		border.set_border_width_all(1)
		border.border_color = lit.call(Color.WHITE)
		border.anti_aliasing = true
		draw_style_box(border, card)

	var inner := card.grow_individual(-10.0, -4.0, -10.0, -4.0)
	var words: Color = lit.call(GREY if cant else colour)
	HudStyle.draw_text(self, Vector2(inner.position.x, inner.position.y + HudStyle.face(&"mono_bold").get_ascent(18)),
		str(_place_of(item) + 1), 18, lit.call(Color(1, 1, 1, 0.4)), HORIZONTAL_ALIGNMENT_LEFT, &"mono_bold")
	_draw_name(ItemRegistry.item(item).name, inner, card.size.x * 0.7, words)
	var icon := HudStyle.item_icon(item)
	var icon_box := Rect2(card.position.x, card.get_center().y - CARD_HEIGHT * 0.45 * 0.5, card.size.x, CARD_HEIGHT * 0.45)
	if icon != null:
		HudStyle.draw_fitted(self, icon, icon_box, lit.call(CANT_ICON if cant else colour))
	var price_colour: Color = lit.call(GREY if cant or why == Economy.NO_MONEY else colour)
	var price_at := Vector2(inner.end.x, inner.end.y - HudStyle.face(&"mono_bold").get_descent(14))
	HudStyle.draw_text(self, price_at, "$%d" % price, 14, price_colour, HORIZONTAL_ALIGNMENT_RIGHT, &"mono_bold",
		Color(0, 0, 0, 0.53), 0)
	# The pips: one in the colour of each of your team who carries it.
	var pip_x := card.get_center().x - (carriers.size() * 9.0 - 4.0) * 0.5
	for pip: Color in carriers:
		draw_circle(Vector2(pip_x + 2.5, card.end.y - 7.5), 2.5, lit.call(pip), true, -1.0, true)
		pip_x += 9.0


## An item's name at the top right, in 14 px, running to a second line where
## it is wider than width: .buywheel-item__name's 70 %, which is of the whole
## card, padding and all (Sid's screenshot fits "Decoy Grenade", 92 px, on a
## line of a card 141 px wide, whose padded inside is 121).
func _draw_name(name: String, inner: Rect2, width: float, colour: Color) -> void:
	var font := HudStyle.face(&"medium")
	var lines := PackedStringArray([name])
	if font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x > width and name.contains(" "):
		var cut := name.rfind(" ")
		while cut > 0 and font.get_string_size(name.substr(0, cut), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x > width:
			cut = name.rfind(" ", cut - 1)
		if cut > 0:
			lines = PackedStringArray([name.substr(0, cut), name.substr(cut + 1)])
	var y := inner.position.y + font.get_ascent(14) + 2.0
	for line in lines:
		HudStyle.draw_text(self, Vector2(inner.end.x, y), line, 14, colour, HORIZONTAL_ALIGNMENT_RIGHT, &"medium")
		y += font.get_height(14)


## The panel of the item under the mouse: its name in a stock item's grey,
## and CS2's word on it, line by line, the difficulty's stars in their own
## colour.
func _draw_item_panel(box: Rect2, item: String) -> void:
	draw_rect(box, ITEM_PANEL_FILL)
	var inner := box.grow(-10.0)
	var y := inner.position.y + HudStyle.face(&"bold").get_ascent(16)
	HudStyle.draw_text(self, Vector2(inner.position.x, y), ItemRegistry.item(item).name, 16, STOCK_NAME,
		HORIZONTAL_ALIGNMENT_LEFT, &"bold")
	y += HudStyle.face(&"bold").get_descent(16) + 10.0
	for line: Array in usage_lines(item):
		var font_name: StringName = &"italic" if line[2] else &"regular"
		y += HudStyle.face(font_name).get_ascent(14)
		var x := HudStyle.draw_text(self, Vector2(inner.position.x, y), line[0], 14, Color(1, 1, 1, 0.9),
			HORIZONTAL_ALIGNMENT_LEFT, font_name)
		if not String(line[1]).is_empty():
			HudStyle.draw_text(self, Vector2(inner.position.x + x, y), line[3], 14, Color.html(line[1]),
				HORIZONTAL_ALIGNMENT_LEFT, font_name)
		y += HudStyle.face(font_name).get_descent(14) + 2.0


## CS2's word on an item, as [text, star colour or "", italic, stars] per
## line; none where the strings were not extracted.
static func usage_lines(item: String) -> Array:
	if _usage.is_empty():
		_usage = _read_usage()
	var text: String = _usage.get("csgo_item_usage_desc_" + item.trim_prefix("weapon_").trim_prefix("item_"), "")
	var out := []
	for part in text.split("<br>", false):
		var italic := part.contains("<i>")
		part = part.replace("<i>", "").replace("</i>", "")
		var colour := ""
		var stars := ""
		var at := part.find("<font color=\"")
		if at >= 0:
			var colour_end := part.find("\"", at + 13)
			colour = part.substr(at + 13, colour_end - at - 13)
			var close := part.find("</font>", colour_end)
			stars = part.substr(part.find(">", colour_end) + 1, close - part.find(">", colour_end) - 1)
			part = part.substr(0, at)
		out.append([part, colour, italic, stars])
	return out


## The extracted strings, "key" "value" a line.
static func _read_usage() -> Dictionary:
	var found := {"": ""}
	var file := FileAccess.open(USAGE_FILE, FileAccess.READ)
	if file == null:
		return found
	var pattern := RegEx.create_from_string("\"([^\"]+)\"\\s+\"((?:[^\"\\\\]|\\\\.)*)\"")
	while not file.eof_reached():
		var matched := pattern.search(file.get_line())
		if matched != null:
			found[matched.get_string(1)] = matched.get_string(2).replace("\\\"", "\"")
	return found


## A card with round corners filled from `middle` at its centre to `edge` at
## its sides (CS2's radial gradient), drawn as a fan.
func _draw_rounded(box: Rect2, middle: Color, edge: Color) -> void:
	var outline := PackedVector2Array()
	var radius := 5.0
	for corner in 4:
		var centre := [Vector2(box.end.x - radius, box.position.y + radius), Vector2(box.end.x - radius, box.end.y - radius),
			Vector2(box.position.x + radius, box.end.y - radius), Vector2(box.position.x + radius, box.position.y + radius)][corner] as Vector2
		for step in 4:
			var angle := -PI * 0.5 + corner * PI * 0.5 + step * PI / 6.0
			outline.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	var points := PackedVector2Array([box.get_center()])
	var colours := PackedColorArray([middle])
	for point in outline:
		points.append(point)
		colours.append(edge)
	points.append(outline[0])
	colours.append(edge)
	var indices := PackedInt32Array()
	for i in range(1, points.size() - 1):
		indices.append_array([0, i, i + 1])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colours)


## Where an item is in its column (its key's number less one).
func _place_of(item: String) -> int:
	var side := _side()
	for column in COLUMN_ORDER:
		for place in Loadout.PLACES:
			if Loadout.item_at(side, column, place) == item:
				return place
	return 0


## The colour of each of your team who carries an item, you first.
func _carriers(item: String) -> Array:
	var out := []
	if economy.game == null:
		return out
	var side := _side()
	var mine := economy.game.inventory(userid)
	if mine != null and mine.has(item):
		out.append(_colour_of(userid))
	if match_state != null:
		for player in match_state.players:
			if player.userid != userid and player.team == side:
				var theirs := economy.game.inventory(player.userid)
				if theirs != null and theirs.has(item):
					out.append(GameHud.player_colour(match_state, player))
	return out


func _colour_of(who: int) -> Color:
	if match_state != null:
		for player in match_state.players:
			if player.userid == who:
				return GameHud.player_colour(match_state, player)
	return HudStyle.team_colour(_side())


## The least you will have next round: what you have now and your side's
## next loss bonus, at most the most there can be ($16,000 in warmup, as
## CS2's shows).
func next_round_minimum() -> int:
	return mini(economy.money(userid) + economy.loss_bonus(_side()), economy.rules.max_money)


## What is in your hand, for the agent to hold while the mouse is over
## nothing.
func _in_hand() -> String:
	var mine := economy.game.inventory(userid) if economy.game != null else null
	return mine.in_hand_class() if mine != null else ""


static func _two_digit_clock(seconds: float) -> String:
	var whole := ceili(seconds)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [whole / 60, whole % 60]


static func _thousands(amount: int) -> String:
	var digits := str(amount)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return "$" + out


## Whether this player can shop at all now; the menu closes when not.
func _may_shop() -> bool:
	return economy.shop_refusal(userid) == Economy.OK


func _side() -> String:
	return economy.game.roster.team_of(userid) if economy.game != null else ""
