class_name HealthAmmoCenter
extends HudElement

## CS2's health and ammo, the way today's HUD draws them: one cluster at the
## bottom in the middle (CSGOHudHealthAmmoCenter, hudhealthammocenter.xml
## and .css). Health on the left over its bar, the armour's shield beside
## it; the team's emblem in a 64 px ring in the middle; the magazine on the
## right over its bar, and beside it the magazines left in reserve with a
## magazine's icon, as the game counts them (an AK-47's 90 rounds read "3").
## Thin lines join the numbers to the ring, fading away from it. All of it
## in the team's colour. A hit flashes the health red, as the game's
## 'on-damage' does.
##
## It only draws the numbers GameHud gives it each frame, and redraws only
## when one changes (HudElement).

## The cluster, as hudhealthammocenter.css sizes it: 800 px wide, the
## numbers 42 px, a bar 65 by 8 px under each, the ring 64 px across with a
## 3 px border and a 48 px emblem. Where the numbers sit off the middle is
## measured from CS2 at 4K (reference/cs2 _screenshots/In_game_ui.webp),
## halved to the base size.
const WIDTH := 800.0
const HEIGHT := 72.0
const BOTTOM_MARGIN := 16.0
const NUMBER_SIZE := 42
const NUMBER_OFFSET := 268.0
const RESERVE_SIZE := 30
const ARMOUR_SIZE := 18
const BAR_SIZE := Vector2(65, 6)
const RING_RADIUS := 32.0
const RING_BORDER := 3.0
const EMBLEM_SIZE := 48.0
## How long the health stays red after a hit, fading back (the game's
## 'on-damage' keyframes run about this long).
const DAMAGE_FLASH_SECONDS := 0.6

var team: String = "T"
var health: int = 100
var armour: int = 0
var helmet: bool = false
## A gun with a magazine in hand; the knife and grenades show no ammo.
var shows_ammo: bool = false
var clip: int = 0
var magazine: int = 1
var reserve: int = 0

var _flash_left: float = 0.0


func _ready() -> void:
	place(Vector2(0.5, 1.0), Rect2(-WIDTH * 0.5, -HEIGHT - BOTTOM_MARGIN, WIDTH, HEIGHT))


## Takes this frame's numbers and redraws if any changed.
func show_values(side: String, hp: int, armor: int, has_helmet: bool, has_ammo: bool,
		in_clip: int, magazine_size: int, in_reserve: int) -> void:
	if hp < health:
		_flash_left = DAMAGE_FLASH_SECONDS
		animate()
	team = side
	health = hp
	armour = armor
	helmet = has_helmet
	shows_ammo = has_ammo
	clip = in_clip
	magazine = maxi(magazine_size, 1)
	reserve = in_reserve
	show_state([side, hp, armor, has_helmet, has_ammo, in_clip, magazine, in_reserve])


func _advance(delta: float) -> bool:
	_flash_left = maxf(_flash_left - delta, 0.0)
	return _flash_left > 0.0


## The reserve as the HUD counts it: in magazines, a part-full one counting
## whole (so 90 rounds of an AK-47 read 3, and 100 of a P90 read 2, as CS2
## shows them).
static func reserve_magazines(rounds: int, magazine_size: int) -> int:
	if rounds <= 0:
		return 0
	return ceili(float(rounds) / float(maxi(magazine_size, 1)))


func _draw() -> void:
	var colour := HudStyle.team_colour(team)
	var middle := Vector2(WIDTH * 0.5, HEIGHT * 0.5)
	var baseline := middle.y + HudStyle.cap_height(NUMBER_SIZE) * 0.5
	var bar_y := baseline + 6.0

	# Health, over its bar, flashing red for a moment after a hit.
	var health_x := middle.x - NUMBER_OFFSET
	var flash := _flash_left / DAMAGE_FLASH_SECONDS
	var health_colour := colour.lerp(HudStyle.DAMAGE_RED, flash)
	var health_width := HudStyle.draw_text(self, Vector2(health_x, baseline), str(health), NUMBER_SIZE,
		health_colour, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_bar(Vector2(health_x, bar_y), clampf(health / 100.0, 0.0, 1.0), colour, true)
	_draw_stroke(health_x + maxf(health_width, BAR_SIZE.x) * 0.5 + 10.0, middle.x - RING_RADIUS - 6.0, middle.y, colour, false)
	if armour > 0:
		_draw_armour(Vector2(health_x - 78.0, middle.y), colour)

	_draw_ring(middle, colour)

	if not shows_ammo:
		return
	var ammo_x := middle.x + NUMBER_OFFSET
	var clip_width := HudStyle.draw_text(self, Vector2(ammo_x, baseline), str(clip), NUMBER_SIZE,
		colour, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_bar(Vector2(ammo_x, bar_y), clampf(float(clip) / magazine, 0.0, 1.0), colour, false)
	_draw_stroke(middle.x + RING_RADIUS + 6.0, ammo_x - maxf(clip_width, BAR_SIZE.x) * 0.5 - 10.0, middle.y, colour, true)
	# The reserve's number stands as tall as the magazine's from the same top.
	var top := baseline - HudStyle.cap_height(NUMBER_SIZE)
	var reserve_x := ammo_x + maxf(clip_width, BAR_SIZE.x) * 0.5 + 14.0
	var reserve_width := HudStyle.draw_text(self, Vector2(reserve_x, top + HudStyle.cap_height(RESERVE_SIZE)),
		str(reserve_magazines(reserve, magazine)), RESERVE_SIZE, colour)
	_draw_magazine_icon(Vector2(reserve_x + reserve_width + 12.0, top + HudStyle.cap_height(RESERVE_SIZE) * 0.6), colour)


## A bar under a number: filled in the team's colour for what is left. For
## health, what is gone is red, fading out towards the right end, as the
## game's health bar is.
func _draw_bar(centre_top: Vector2, fraction: float, colour: Color, red_behind: bool) -> void:
	var rect := Rect2(centre_top.x - BAR_SIZE.x * 0.5, centre_top.y, BAR_SIZE.x, BAR_SIZE.y)
	draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.55))
	var filled := rect.size.x * fraction
	if filled > 0.0:
		draw_rect(Rect2(rect.position, Vector2(filled, rect.size.y)), colour)
	if filled >= rect.size.x:
		return
	var rest := Rect2(rect.position + Vector2(filled, 0), Vector2(rect.size.x - filled, rect.size.y))
	if red_behind:
		var solid := Color(1, 0, 0, 1)
		var faint := Color(1, 0, 0, 0.1)
		draw_polygon(
			PackedVector2Array([rest.position, rest.position + Vector2(rest.size.x, 0), rest.end, rest.position + Vector2(0, rest.size.y)]),
			PackedColorArray([solid, faint, faint, solid]))
	else:
		draw_rect(rest, Color(colour, 0.18))


## The thin line from a number to the ring, brightest at the ring.
func _draw_stroke(from_x: float, to_x: float, y: float, colour: Color, fades_right: bool) -> void:
	if to_x <= from_x:
		return
	var near := Color(colour, 0.85)
	var far := Color(colour, 0.2)
	draw_polyline_colors(
		PackedVector2Array([Vector2(from_x, y), Vector2(to_x, y)]),
		PackedColorArray([near, far] if fades_right else [far, near]), 1.0)


## The ring in the middle: dark inside, the team's colour round it, the
## team's emblem in it.
func _draw_ring(centre: Vector2, colour: Color) -> void:
	draw_circle(centre, RING_RADIUS, HudStyle.PANEL_TINT)
	draw_arc(centre, RING_RADIUS - RING_BORDER * 0.5, 0.0, TAU, 64, colour, RING_BORDER, true)
	var emblem := HudStyle.icon("icons/ui/ct_logo_1c" if team == "CT" else "icons/ui/t_logo_1c")
	var box := Rect2(centre - Vector2.ONE * EMBLEM_SIZE * 0.5, Vector2.ONE * EMBLEM_SIZE)
	if emblem != null:
		HudStyle.draw_fitted(self, emblem, box.grow(-4.0), colour)
		return
	# Without CS2's emblem: a star over two crossed blades, the shape of the
	# terrorists' one, or a star in a laurel's arc for the counter-terrorists.
	_draw_star(centre + Vector2(0, -6), 9.0, colour)
	if team == "CT":
		draw_arc(centre + Vector2(0, -2), 16.0, deg_to_rad(20), deg_to_rad(160), 16, colour, 2.5, true)
	else:
		draw_line(centre + Vector2(-13, 4), centre + Vector2(11, 16), colour, 3.0, true)
		draw_line(centre + Vector2(13, 4), centre + Vector2(-11, 16), colour, 3.0, true)


func _draw_star(centre: Vector2, radius: float, colour: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.42
		var angle := -PI * 0.5 + i * PI / 5.0
		points.append(centre + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, colour)


## The armour's shield, with a helmet on it when there is one, and its
## number.
func _draw_armour(centre: Vector2, colour: Color) -> void:
	var texture := HudStyle.icon("hud/armor_helmet" if helmet else "hud/armor")
	var box := Rect2(centre + Vector2(-13, -14), Vector2(26, 28))
	if texture != null:
		HudStyle.draw_fitted(self, texture, box, colour)
	else:
		var top := box.position.y + (6.0 if helmet else 0.0)
		var outline := PackedVector2Array([
			Vector2(box.position.x, top), Vector2(box.end.x, top),
			Vector2(box.end.x, top + (box.end.y - top) * 0.5), Vector2(box.get_center().x, box.end.y),
			Vector2(box.position.x, top + (box.end.y - top) * 0.5),
		])
		draw_colored_polygon(outline, colour)
		if helmet:
			draw_arc(Vector2(box.get_center().x, top), 8.0, PI, TAU, 12, colour, 3.0, true)
	HudStyle.draw_text(self, Vector2(box.end.x + 6.0, centre.y + HudStyle.cap_height(ARMOUR_SIZE) * 0.5),
		str(armour), ARMOUR_SIZE, Color.WHITE)


## A magazine, leaning as CS2's reserve icon does.
func _draw_magazine_icon(centre: Vector2, colour: Color) -> void:
	var texture := HudStyle.icon("hud/ammo_reserve_magazine")
	if texture != null:
		HudStyle.draw_fitted(self, texture, Rect2(centre - Vector2(10, 10), Vector2(20, 20)), colour)
		return
	var along := Vector2(1, -1).normalized()
	var across := Vector2(1, 1).normalized()
	var points := PackedVector2Array([
		centre - along * 10.0 - across * 3.5, centre + along * 10.0 - across * 3.5,
		centre + along * 10.0 + across * 3.5, centre - along * 10.0 + across * 3.5,
	])
	draw_colored_polygon(points, colour)
	for i in 4:
		var t := -6.0 + i * 4.0
		draw_line(centre + along * t - across * 3.5, centre + along * t + across * 3.5, Color(0, 0, 0, 0.45), 1.0)
