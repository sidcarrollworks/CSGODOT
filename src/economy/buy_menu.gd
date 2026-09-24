class_name BuyMenu
extends Control

## CS2's buy menu: five columns (pistols, mid-tier, rifles, equipment,
## grenades) of the player's loadout, with each item's price, what it would
## do now and whether it can be bought.
##
## It only reads the economy and asks it for purchases (Economy.buy and
## undo), which the next tick carries out, so it is drawing, not game state,
## and would work the same on a client.
##
## B opens and closes it, as in CS2, and so does Escape. With it open the
## mouse is free and the view holds still; moving still works. Click an item
## to buy it, right-click one bought this round to undo it. The keys work
## as CS2's do: a number picks a column, a second number an item in it
## (B 3 2 is the AK-47 or the M4A1-S), and no other key press gets past it
## while it is open. It closes itself when buying is over
## for you: buy time ends, you leave the buy zone, or you die.

const COLUMN_WIDTH := 200.0
const ICON_ROOT := "res://assets/hud/panorama/images/icons/equipment"

## The economy it shows and the player it is for.
var economy: Economy
var userid: int = -1

var _buttons := {}
var _column_titles: Array[Label] = []
var _header: Label
var _footer: Label
var _picked_column: int = -1
## The side the buttons were built for; rebuilt when the player's changes.
var _built_for: String = ""
var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return visible


func open() -> void:
	if economy == null or visible or not _may_shop():
		return
	_build()
	_picked_column = -1
	visible = true
	_mouse_before = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func close() -> void:
	if not visible:
		return
	visible = false
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


func _press_number(number: int) -> void:
	if _picked_column < 0:
		_picked_column = number
		return
	var item := Loadout.item_at(_side(), _picked_column, number)
	_picked_column = -1
	if not item.is_empty():
		economy.buy(userid, item)


func _process(_delta: float) -> void:
	if not visible:
		return
	if not _may_shop():
		close()
		return
	if _built_for != _side():
		_build()
	var seconds := economy.buy_seconds_left(SimClock.now_usec())
	_header.text = "$%d        %s" % [
		economy.money(userid),
		"buying open" if is_inf(seconds) else "buy time %d s" % ceili(seconds),
	]
	for column in _column_titles.size():
		_column_titles[column].modulate = Color(1.0, 0.8, 0.3) if column == _picked_column else Color.WHITE
	var said := ""
	for item: String in _buttons:
		var button: Button = _buttons[item]
		var why := economy.refusal(userid, item)
		var owned := why == Economy.ALREADY_HAVE or economy.can_undo(userid, item)
		button.text = "%s\n$%d%s" % [
			ItemRegistry.item(item).name, economy.price_for(userid, item),
			"   owned" if owned else "",
		]
		button.modulate = Color.WHITE if why == Economy.OK else Color(1.0, 1.0, 1.0, 0.45)
		if button.is_hovered() and why != Economy.OK:
			said = Economy.MESSAGES.get(why, "")
	_footer.text = said if not said.is_empty() \
		else "click: buy    right-click: undo    1-5 then 1-5: buy by keys    B / Esc: close"


## Whether this player can shop at all now; the menu closes when not.
func _may_shop() -> bool:
	return economy.shop_refusal(userid) == Economy.OK


func _side() -> String:
	return economy.game.roster.team_of(userid) if economy.game != null else ""


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_buttons.clear()
	_column_titles.clear()
	_built_for = _side()

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.88)
	style.set_content_margin_all(18.0)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	panel.add_child(rows)
	_header = _label(22)
	rows.add_child(_header)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	rows.add_child(columns)
	for column in Loadout.COLUMNS.size():
		var list := VBoxContainer.new()
		list.custom_minimum_size.x = COLUMN_WIDTH
		columns.add_child(list)
		var title := _label(18)
		title.text = "%d  %s" % [column + 1, Loadout.COLUMNS[column]["name"]]
		list.add_child(title)
		_column_titles.append(title)
		for place in Loadout.PLACES:
			var item := Loadout.item_at(_built_for, column, place)
			if item.is_empty() or not ItemRegistry.has(item):
				var gap := Control.new()
				gap.custom_minimum_size.y = 64.0
				list.add_child(gap)
				continue
			list.add_child(_item_button(item, place))

	_footer = _label(16)
	rows.add_child(_footer)


func _item_button(item: String, place: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(COLUMN_WIDTH, 64.0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "%d" % (place + 1)
	button.icon = _icon(item)
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", 64)
	button.pressed.connect(func() -> void: economy.buy(userid, item))
	button.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
			economy.undo(userid, item))
	_buttons[item] = button
	return button


## The game's icon for an item, where the HUD icons are extracted
## (scripts/extract_assets.sh hud); none, and the name alone, where not.
static func _icon(item: String) -> Texture2D:
	var icon_name := item.trim_prefix("weapon_").trim_prefix("item_")
	var path := ICON_ROOT.path_join(icon_name + ".svg")
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label
