class_name WeaponSelection
extends HudElement

## What you carry, in the bottom right, shown for a moment each time what is
## in hand changes, as CS2's weapon selection shows it (CSGOHudWeaponSelection;
## GameTracking-CS2's panorama/layout/hud/hudweaponselection.xml and
## styles/hud/hudweaponselection.css, read 2026-09-28).
##
## A row for each slot you carry something in, the primary at the top and
## the C4 at the bottom, stacked up from above the always-on row CS2 keeps
## along the bottom (not built: its grenade pips and the kit). Each row is
## 300 px wide, 6 px in from the right; its slot's key in its top right
## corner (16 px Stratum2 Mono Bold), its items' icons in from the right,
## one after another leftwards (the grenades). An icon is washed in your
## team's colour, a little paler and darker (the css's hsv transform 0,
## 0.96, 0.9), at 0.7 of its size and 0.8 of its light; the one in hand at
## 0.9 of its size and half as bright again, with its name under it (16 px
## Stratum2 Medium). The guns' and knife's icons are turned to face right,
## as the css turns slots 0 to 2; the C4 is washed #f3e78b. A grenade you
## carry more than one of has its count by it.
##
## Each change of what is in hand pops it up, the icons sliding in from the
## right over 0.2 s (translateX 125% to 0, linear); it holds, then fades out
## in 0.1 s (weapon-selection--fade). How long it holds is set by CS2's code,
## not its styles: HOLD_SECONDS is a guess, for Sid to set beside CS2.
##
## Like every HudElement it draws only what GameHud hands it, and only
## animates while it is up or on its way out.

const ROW_WIDTH := 300.0
const ROW_RIGHT := 6.0
## The always-on row's height (.weapon-selection-list__always-on-container):
## the list stands on it.
const ALWAYS_ON := 84.0
## An icon's box (.weapon-selection-item-icon-main): 61.5 px tall with 7 of
## padding, 10 px margin on the right, inside the row's 10 px.
const ICON_BOX := 61.5
const ICON_PAD := 7.0
const ICON_MARGIN := 10.0
const INNER_MARGIN := 10.0
const SCALE := 0.7
const SELECTED_SCALE := 0.9
## The grenades and the C4 sit 6 px lower in their box (gear-slot--3, 4).
const LOW_SLOT_DROP := 6.0
## The name: 16 px, 12 px in from the item's right, 8 up into the icon's box
## and 4 above the next row.
const NAME_SIZE := 16
const NAME_RIGHT := 12.0
const NAME_LINE := 20.0
const ROW_HEIGHT := ICON_BOX - 8.0 + NAME_LINE + 4.0
const NUMBER_SIZE := 16
## The size of a name drawn where an icon was not extracted.
const FALLBACK_SIZE := 14
const COUNT_GREY := Color8(160, 160, 160)
const C4_WASH := Color8(243, 231, 139)
const SHADOW := Color(0, 0, 0, 0.533)
const SLIDE_SECONDS := 0.2
const FADE_SECONDS := 0.1
## How long it stays up after a change: a guess.
const HOLD_SECONDS := 2.0

var team: String = "T"
## One row for each slot carried in: [the slot's key (1 to 5), [[item class,
## count], ...]], the primary's first.
var rows: Array = []
var in_hand: String = ""

## How much of the list shows, 0 to 1, and how far its icons have slid in.
var opacity: float = 0.0
var _slide: float = 1.0
var _hold_left: float = 0.0
var _started := false


func _init() -> void:
	super()
	additive = true


func _ready() -> void:
	# Room for all five slots; the rows carried stand at its bottom.
	var height := ROW_HEIGHT * 5.0
	place(Vector2(1.0, 1.0), Rect2(-ROW_WIDTH - ROW_RIGHT, -ALWAYS_ON - height, ROW_WIDTH, height))


## Takes this frame's inventory. A change of what is in hand, or of what is
## carried, brings it up; the first one seen does not.
func show_inventory(side: String, carried: Array, holding: String) -> void:
	var changed := _started and (holding != in_hand or carried != rows)
	_started = true
	team = side
	rows = carried.duplicate(true)
	in_hand = holding
	if changed and not rows.is_empty():
		pop()
	show_state([side, rows, holding])


## Up now, sliding in if it was not showing, and holding from now.
func pop() -> void:
	if opacity <= 0.0:
		_slide = 0.0
	opacity = 1.0
	_hold_left = HOLD_SECONDS
	animate()


## Put away at once (dead, the buy menu open).
func hide_now() -> void:
	opacity = 0.0
	_hold_left = 0.0
	redraw()


func is_showing() -> bool:
	return opacity > 0.0


## The rows an inventory makes: each slot it carries something in, in
## order, with each item and its count.
static func rows_for(inventory: Inventory) -> Array:
	var out: Array = []
	if inventory == null:
		return out
	for entry in inventory.entries():
		var key := int(entry.item.slot) + 1
		if entry.item.slot == ItemDef.Slot.EQUIPMENT:
			continue
		if out.is_empty() or out[-1][0] != key:
			out.append([key, []])
		out[-1][1].append([entry.item.item_class, entry.count])
	return out


func _advance(delta: float) -> bool:
	_slide = minf(_slide + delta / SLIDE_SECONDS, 1.0)
	if _hold_left > 0.0:
		_hold_left = maxf(_hold_left - delta, 0.0)
		return true
	opacity = maxf(opacity - delta / FADE_SECONDS, 0.0)
	return opacity > 0.0


func _draw() -> void:
	if opacity <= 0.0:
		return
	var right := ROW_WIDTH
	for r in rows.size():
		var top := size.y - ROW_HEIGHT * (rows.size() - r)
		var key: int = rows[r][0]
		var items: Array = rows[r][1]
		HudStyle.draw_text(self, Vector2(right - 4.0, top + HudStyle.baseline_from_top(0.0, NUMBER_SIZE, &"mono_bold")),
			str(key), NUMBER_SIZE, Color(1, 1, 1, opacity), HORIZONTAL_ALIGNMENT_RIGHT, &"mono_bold",
			Color(SHADOW, SHADOW.a * opacity), 1)
		var x := right - INNER_MARGIN
		for item: Array in items:
			x = _draw_item(item[0], item[1], key, x, top)


## One item, its box's right edge at `right`; returns where the next one to
## its left ends.
func _draw_item(item_class: String, count: int, key: int, right: float, top: float) -> float:
	var selected := item_class == in_hand
	var texture := HudStyle.item_icon(item_class)
	var image_height := ICON_BOX - ICON_PAD * 2.0
	var image_width := image_height * 2.0
	if texture != null and texture.get_height() > 0:
		image_width = image_height * texture.get_width() / texture.get_height()
	elif texture == null:
		# The name stands in, as wide as it reads at its size once scaled.
		image_width = HudStyle.face(&"bold").get_string_size(_name(item_class), HORIZONTAL_ALIGNMENT_LEFT, -1,
			FALLBACK_SIZE).x / SCALE
	var box_width := image_width + ICON_PAD * 2.0
	var box := Rect2(right - ICON_MARGIN - box_width, top, box_width, ICON_BOX)
	if key >= 4:
		box.position.y += LOW_SLOT_DROP
	# Slid in from the right by 125% of its width until the slide is over.
	var slide := (1.0 - _slide) * box_width * 1.25
	var scale := SELECTED_SCALE if selected else SCALE
	var pivot := Vector2(box.end.x + slide, box.get_center().y)
	var image := Rect2(box.position + Vector2(ICON_PAD + slide, ICON_PAD), Vector2(image_width, image_height))
	image = Rect2(pivot + (image.position - pivot) * scale, image.size * scale)
	var colour := wash(team, item_class, selected)
	colour.a *= opacity
	if texture != null:
		var mirrored := key <= 3
		if mirrored:
			draw_set_transform(Vector2(image.get_center().x * 2.0, 0.0), 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(texture, image, false, colour)
		if mirrored:
			draw_set_transform(Vector2.ZERO)
	else:
		# Not extracted: the item's name in the icon's place.
		HudStyle.draw_text(self, Vector2(image.end.x, image.end.y - 4.0), _name(item_class), FALLBACK_SIZE, colour,
			HORIZONTAL_ALIGNMENT_RIGHT, &"bold", Color(SHADOW, SHADOW.a * opacity), 1)
	if count > 1:
		HudStyle.draw_text(self, Vector2(box.end.x + slide, box.end.y - 20.0 + NAME_SIZE * 0.5), str(count), NAME_SIZE,
			Color(Color.WHITE if selected else COUNT_GREY, opacity), HORIZONTAL_ALIGNMENT_RIGHT, &"medium",
			Color(SHADOW, SHADOW.a * opacity), 1)
	if selected:
		var baseline := box.end.y - 8.0 + HudStyle.baseline_from_top(0.0, NAME_SIZE, &"medium")
		HudStyle.draw_text(self, Vector2(right - NAME_RIGHT, baseline), _name(item_class), NAME_SIZE,
			Color(1, 1, 1, opacity), HORIZONTAL_ALIGNMENT_RIGHT, &"medium", Color(SHADOW, SHADOW.a * opacity), 1)
	return box.position.x


## An icon's colour: the team's, or the C4's, turned as the css turns it
## (hsv-transform 0, 0.96, 0.9) at 0.8 of its light; in hand, half as bright
## again (brightness 1.5) and at full light.
static func wash(side: String, item_class: String, selected: bool) -> Color:
	var base := C4_WASH if item_class == "weapon_c4" else HudStyle.team_colour(side)
	var turned := Color.from_hsv(base.h, base.s * 0.96, base.v * 0.9)
	if selected:
		return Color(minf(turned.r * 1.5, 1.0), minf(turned.g * 1.5, 1.0), minf(turned.b * 1.5, 1.0), 1.0)
	return Color(turned, 0.8)


static func _name(item_class: String) -> String:
	return ItemRegistry.item(item_class).name if ItemRegistry.has(item_class) else item_class.trim_prefix("weapon_")
