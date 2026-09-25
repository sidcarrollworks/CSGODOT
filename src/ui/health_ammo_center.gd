class_name HealthAmmoCenter
extends HudElement

## CS2's health and ammo, the way today's HUD draws them: one cluster at the
## bottom in the middle (CSGOHudHealthAmmoCenter; CS2's
## panorama/layout/hud/hudhealthammocenter.xml and
## panorama/styles/hud/hudhealthammocenter.css, decompiled from the game).
## Health on the left over its bar, with the armour's shield and number
## beside it; the team's emblem in a ring in the middle, the ring orange for
## the terrorists and blue for the counter-terrorists (HudStyle.ring_colour);
## the magazine on the right over its bar, and beside it
## the reserve, in magazines for every gun but the shotguns loaded a shell at
## a time (the game's m_bReserveAmmoAsClips), with the icon of that gun's
## magazine. A thin line joins each side to the ring, fading away from it.
## Everything but the ring's dark disc adds its light, in the team's colour
## (HudStyle), as the game's `additive` class does.
##
## It moves as CS2's does: a hit throws a red copy of the health number that
## fades as it drops (the css's 'on-damage', 0.6 s) and jolts the number and
## its bar (jitter-number, jitter-bar, 0.15 s); each shot jolts the magazine's
## number (0.05 s); a new gun in hand pops its numbers in from three
## quarters size (weapon--change, 0.1 s); a reload drops the reserve's icon
## out and back in from above (reload, 0.3 s).
##
## It only draws the numbers GameHud gives it each frame, and redraws only
## when one changes or while something moves (HudElement).

## The cluster's row, from the css: 800 wide (HA-width) and 72 tall (.hud-HA).
## CS2 lays it 18 px off the bottom (#HudBottomCenter's 2 and the element's
## 16), but its screenshot has the ring's centre 1029 down, 15 off.
const WIDTH := 800.0
const HEIGHT := 72.0
const BOTTOM := 15.0
## The ring: 64 across with a 3 px border (.hud-HA-center, its __border);
## on the screenshot the border's outside is 62 across.
const RING := 64.0
const RING_OUTER := 31.0
const RING_BORDER := 3.0
const EMBLEM := 48.0
## Each side of the ring fills the rest of the row (width-fill-parent-flow),
## and the numbers stand 200 px in from the ring's end of it
## (.hud-HA-main-container margin-right, .hud-WPN-main margin-left), each in
## a 70 px box (hud-HA-text-width).
const SIDE := (WIDTH - RING) * 0.5
const INSET := 200.0
const TEXT_WIDTH := 70.0
const NUMBER_SIZE := 42
const ARMOUR_SIZE := 18
const RESERVE_SIZE := 32
## The css's `.HudHealthAmmoCenter Label { y: 2px }`.
const NUDGE := 2.0
## The health's bar: 65 by 8 with a black 1 px border, 10 px off the row's
## bottom and 2 px in from the box's right (.hud-HA-bar); the border adds
## nothing to an additive bar, so what shows is the 63 by 6 inside.
const HEALTH_BAR := Rect2(SIDE - INSET - 2.0 - 64.0, HEIGHT - 10.0 - 7.0, 63.0, 6.0)
## The magazine's: 65 by 4, 14 off the bottom, centred under its number
## (#AmmoClipBar); the 63 by 2 inside shows.
const CLIP_BAR := Rect2(SIDE + RING + INSET + (TEXT_WIDTH - 63.0) * 0.5, HEIGHT - 14.0 - 3.0, 63.0, 2.0)
## The reserve's number ends where CS2's screenshot has it (its right 738 px
## into the row), and the icon is an 18 px square after it, 1 px high
## (.hud-WPN-ammo-reserve__icon).
const RESERVE_RIGHT := 740.0
const RESERVE_ICON := Rect2(737.0, HEIGHT * 0.5 - 1.0 - 9.0, 18.0, 18.0)
## The strokes: half of each side, 1 px, brightest at the ring
## (.hud-HA__stroke.left and .right).
const STROKE := SIDE * 0.5

## Which of CS2's reserve icons each gun has (hudhealthammocenter.xml has
## magazine, banana_mag, shotgun_shell, box, revolver_loader, bizon_tube and
## p90; which gun gets which is decided in the game's code, so this goes by
## the magazine each gun has, and any other gun gets the plain magazine).
const RESERVE_ICONS := {
	"weapon_p90": "ammo_reserve_p90",
	"weapon_bizon": "ammo_reserve_bizon_tube",
	"weapon_revolver": "ammo_reserve_revolver_loader",
	"weapon_m249": "ammo_reserve_box",
	"weapon_negev": "ammo_reserve_box",
	"weapon_nova": "ammo_reserve_shotgun_shell",
	"weapon_xm1014": "ammo_reserve_shotgun_shell",
	"weapon_sawedoff": "ammo_reserve_shotgun_shell",
	"weapon_ak47": "ammo_reserve_banana_mag",
	"weapon_galilar": "ammo_reserve_banana_mag",
}

## The animations' lengths, from the css.
const DAMAGE_SECONDS := 0.6
const JITTER_SECONDS := 0.15
const FIRED_SECONDS := 0.05
const CHANGE_SECONDS := 0.1
const RELOAD_SECONDS := 0.3

var team: String = "T"
var health: int = 100
var armour: int = 0
var helmet: bool = false
## A gun with a magazine in hand; the knife and grenades show no ammo.
var shows_ammo: bool = false
var weapon_class: String = ""
var clip: int = 0
var magazine: int = 1
## The reserve in rounds, and whether the HUD counts it in magazines.
var reserve: int = 0
var reserve_as_clips: bool = true
var reloading: bool = false

## How far into each animation it is, in seconds; negative when not running.
var _damage := -1.0
var _jitter := -1.0
var _fired := -1.0
var _change := -1.0
var _reload := -1.0
var _started := false


func _init() -> void:
	super()
	additive = true


func _ready() -> void:
	place(Vector2(0.5, 1.0), Rect2(-WIDTH * 0.5, -HEIGHT - BOTTOM, WIDTH, HEIGHT))


## Takes this frame's numbers and redraws if any changed.
func show_values(side: String, hp: int, armor: int, has_helmet: bool, gun: String,
		has_ammo: bool, in_clip: int, magazine_size: int, in_reserve: int, as_clips: bool, is_reloading: bool) -> void:
	if _started:
		if hp < health:
			_damage = 0.0
			_jitter = 0.0
		if gun != weapon_class:
			_change = 0.0
		elif has_ammo and in_clip < clip:
			_fired = 0.0
		if is_reloading and not reloading:
			_reload = 0.0
		if _damage >= 0.0 or _change >= 0.0 or _fired >= 0.0 or _reload >= 0.0:
			animate()
	_started = true
	team = side
	health = hp
	armour = armor
	helmet = has_helmet
	weapon_class = gun
	shows_ammo = has_ammo
	clip = in_clip
	magazine = maxi(magazine_size, 1)
	reserve = in_reserve
	reserve_as_clips = as_clips
	reloading = is_reloading
	show_state([side, hp, armor, has_helmet, gun, has_ammo, in_clip, magazine, in_reserve, as_clips])


func _advance(delta: float) -> bool:
	var running := false
	for name: StringName in [&"_damage", &"_jitter", &"_fired", &"_change", &"_reload"]:
		var t: float = get(name)
		if t < 0.0:
			continue
		t += delta
		var length: float = {&"_damage": DAMAGE_SECONDS, &"_jitter": JITTER_SECONDS, &"_fired": FIRED_SECONDS,
			&"_change": CHANGE_SECONDS, &"_reload": RELOAD_SECONDS}[name]
		if t >= length:
			t = -1.0
		else:
			running = true
		set(name, t)
	return running


## The reserve as the HUD shows it: in magazines where the game counts them
## so, a part-full one counting whole (an AK-47's 90 rounds read 3, a P90's
## 100 read 2, as CS2's screenshot shows), else in rounds (a Nova's 32).
static func reserve_shown(rounds: int, magazine_size: int, as_clips: bool) -> int:
	if rounds <= 0:
		return 0
	if not as_clips:
		return rounds
	return ceili(float(rounds) / float(maxi(magazine_size, 1)))


## The icon beside the reserve, by the gun in hand.
static func reserve_icon(gun: String) -> String:
	return "hud/" + RESERVE_ICONS.get(gun, "ammo_reserve_magazine")


## Where the ring's blur is.
func _blur_rect() -> Rect2:
	return Rect2(WIDTH * 0.5 - RING_OUTER, HEIGHT * 0.5 - RING_OUTER, RING_OUTER * 2.0, RING_OUTER * 2.0)


## The world behind the ring, blurred (.hud-HA-center's world-blur).
func _draw_blur(on: CanvasItem) -> void:
	on.draw_circle(Vector2(WIDTH * 0.5, HEIGHT * 0.5), RING_OUTER, Color.WHITE, true, -1.0, true)


## The dark disc in the ring, over the blur and under the rest.
func _draw_under(on: CanvasItem) -> void:
	on.draw_circle(Vector2(WIDTH * 0.5, HEIGHT * 0.5), RING_OUTER, HudStyle.PANEL_TINT, true, -1.0, true)


func _draw() -> void:
	var colour := HudStyle.team_colour(team)
	var centre_y := HEIGHT * 0.5

	# The strokes, brightest where they meet the ring.
	_draw_stroke(SIDE - STROKE, SIDE, centre_y, colour, false)
	_draw_stroke(SIDE + RING, SIDE + RING + STROKE, centre_y, colour, true)

	# Health: the number in its box, the bar under it, the jolt of a hit.
	var health_centre := Vector2(SIDE - INSET - TEXT_WIDTH * 0.5, centre_y)
	_draw_number(str(health), health_centre, _jolt(_jitter, JITTER_SECONDS, Vector2(-3, -4), Vector2(0, -2), Vector2(3, 5)),
		colour, Transform2D.IDENTITY)
	if _damage >= 0.0:
		_draw_damage_ghost(str(health), health_centre)
	var bar_jolt := _jolt(_jitter, JITTER_SECONDS, Vector2(-2, 2), Vector2(0, 2), Vector2(2, -3))
	_draw_bar(HEALTH_BAR, clampf(health / 100.0, 0.0, 1.0), colour, true, Vector2(bar_jolt.x, bar_jolt.y))
	if armour > 0:
		_draw_armour(Vector2(SIDE - INSET - TEXT_WIDTH - 23.0, centre_y), colour)

	_draw_ring(Vector2(WIDTH * 0.5, centre_y), colour)

	if not shows_ammo:
		return
	# The gun's numbers, popping in from three quarters size about their
	# middle when it changes.
	var ammo_left := SIDE + RING + INSET
	var pop := Transform2D.IDENTITY
	if _change >= 0.0:
		var scale := lerpf(0.75, 1.0, _ease_in_out(_change / CHANGE_SECONDS))
		var pivot := Vector2((ammo_left + RESERVE_ICON.end.x) * 0.5, centre_y)
		pop = Transform2D(0.0, Vector2.ONE * scale, 0.0, pivot * (1.0 - scale))
	_draw_number(str(clip), Vector2(ammo_left + TEXT_WIDTH * 0.5, centre_y),
		_jolt(_fired, FIRED_SECONDS, Vector2(-3, -4), Vector2(0, -2), Vector2(3, 5)), colour, pop)
	draw_set_transform_matrix(pop)
	_draw_bar(CLIP_BAR, clampf(float(clip) / magazine, 0.0, 1.0), colour, false, Vector2.ZERO)
	HudStyle.draw_text(self, Vector2(RESERVE_RIGHT, HudStyle.baseline_centred(centre_y, RESERVE_SIZE)),
		str(reserve_shown(reserve, magazine, reserve_as_clips)), RESERVE_SIZE, colour, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_reserve_icon(colour)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## A big number centred in its box, jolted by (x, y) and scaled by z about
## its middle (the jitter keyframes start at 1.15 times), inside `outer`.
func _draw_number(text: String, centre: Vector2, jolt: Vector3, colour: Color, outer: Transform2D) -> void:
	var at := centre + Vector2(jolt.x, jolt.y)
	draw_set_transform_matrix(outer * Transform2D(0.0, Vector2.ONE * jolt.z, 0.0, at * (1.0 - jolt.z)))
	HudStyle.draw_text(self, Vector2(at.x, HudStyle.baseline_centred(at.y, NUMBER_SIZE, &"bold_tf", NUDGE)),
		text, NUMBER_SIZE, colour, HORIZONTAL_ALIGNMENT_CENTER)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## The 'on-damage' copy of the health: red, five times as bright a tenth of
## the way in, half gone by three quarters and gone at the end, having
## dropped a quarter of its height from the tenth on.
func _draw_damage_ghost(text: String, centre: Vector2) -> void:
	var t := _damage / DAMAGE_SECONDS
	var alpha := lerpf(1.0, 0.5, clampf((t - 0.1) / 0.65, 0.0, 1.0)) if t < 0.75 else lerpf(0.5, 0.0, (t - 0.75) / 0.25)
	var brightness := lerpf(1.0, 5.0, t / 0.1) if t < 0.1 else lerpf(5.0, 1.0, clampf((t - 0.1) / 0.65, 0.0, 1.0))
	var drop := maxf(t - 0.1, 0.0) / 0.9 * 0.25 * HudStyle.face().get_height(NUMBER_SIZE)
	var red := Color(HudStyle.DAMAGE_RED.r * brightness, HudStyle.DAMAGE_RED.g * brightness,
		HudStyle.DAMAGE_RED.b * brightness, alpha)
	HudStyle.draw_text(self, Vector2(centre.x, HudStyle.baseline_centred(centre.y, NUMBER_SIZE, &"bold_tf", NUDGE) + drop),
		text, NUMBER_SIZE, red, HORIZONTAL_ALIGNMENT_CENTER)


## A bar: the team's colour for what is left. Behind the health's, what is
## gone shows red, solid to the middle and fading out towards the right end
## (.hud-HA-bar's gradient); behind the magazine's, a faint wash of the
## colour (#AmmoClipBar's rgba(255,255,255,0.1)). Panorama draws a bar
## whole and then adds it, so only what the fill leaves is drawn behind.
func _draw_bar(rect: Rect2, fraction: float, colour: Color, red_behind: bool, offset: Vector2) -> void:
	rect.position += offset
	var filled := rect.size.x * fraction
	if filled > 0.0:
		draw_rect(Rect2(rect.position, Vector2(filled, rect.size.y)), colour)
	if filled >= rect.size.x:
		return
	var from_x := rect.position.x + filled
	if not red_behind:
		draw_rect(Rect2(from_x, rect.position.y, rect.end.x - from_x, rect.size.y), Color(colour, 0.1))
		return
	# The red, split where its fade starts half way along.
	var middle := rect.position.x + rect.size.x * 0.5
	var stops := [from_x] if from_x >= middle else [from_x, middle]
	stops.append(rect.end.x)
	for i in stops.size() - 1:
		var a: float = stops[i]
		var b: float = stops[i + 1]
		var left := Color(1, 0, 0, _red_alpha(a, rect))
		var right := Color(1, 0, 0, _red_alpha(b, rect))
		draw_polygon(
			PackedVector2Array([Vector2(a, rect.position.y), Vector2(b, rect.position.y), Vector2(b, rect.end.y), Vector2(a, rect.end.y)]),
			PackedColorArray([left, right, right, left]))


## The health bar's red at `x`: solid to the middle, 0.1 at the right end.
static func _red_alpha(x: float, rect: Rect2) -> float:
	var half := rect.size.x * 0.5
	return 1.0 if x <= rect.position.x + half else lerpf(1.0, 0.1, (x - rect.position.x - half) / half)


## The thin line from a number's side to the ring, the team's colour at the
## ring fading to nothing half way out.
func _draw_stroke(from_x: float, to_x: float, y: float, colour: Color, fades_right: bool) -> void:
	var near := Color(colour, 1.0)
	var far := Color(colour, 0.0)
	var rect := Rect2(from_x, y - 0.5, to_x - from_x, 1.0)
	draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([near, far, far, near] if fades_right else [far, near, near, far]))


## The ring round the emblem, orange for the terrorists and blue for the
## counter-terrorists, and the emblem in the team's colour.
func _draw_ring(centre: Vector2, colour: Color) -> void:
	draw_arc(centre, RING_OUTER - RING_BORDER * 0.5, 0.0, TAU, 96, HudStyle.ring_colour(team), RING_BORDER, true)
	var emblem := HudStyle.icon("icons/ui/ct_logo_1c" if team == "CT" else "icons/ui/t_logo_1c")
	var box := Rect2(centre - Vector2.ONE * EMBLEM * 0.5, Vector2.ONE * EMBLEM)
	if emblem != null:
		HudStyle.draw_fitted(self, emblem, box, colour)
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


## The armour's shield (or shield and helmet) left of the health, its number
## on it: the css sets the pair 5 px low, the icons 3 px lower still and the
## helmet's back up 3, the number 3 below the middle and 2 more.
func _draw_armour(centre: Vector2, colour: Color) -> void:
	var texture := HudStyle.icon("hud/armor_helmet" if helmet else "hud/armor")
	var icon_centre := centre + Vector2(0, 5.0 + 3.0 - (3.0 if helmet else 0.0))
	var width := 46.0 if helmet else 42.0
	if texture != null:
		var size := texture.get_size()
		var drawn := Vector2(width, width * size.y / maxf(size.x, 1.0))
		draw_texture_rect(texture, Rect2(icon_centre - drawn * 0.5, drawn), false, colour)
	else:
		var box := Rect2(icon_centre - Vector2(13, 14), Vector2(26, 28))
		draw_rect(box, colour, false, 2.0)
	HudStyle.draw_text(self, Vector2(centre.x, HudStyle.baseline_centred(centre.y + 5.0 + 3.0, ARMOUR_SIZE, &"bold_tf", NUDGE)),
		str(armour), ARMOUR_SIZE, colour, HORIZONTAL_ALIGNMENT_CENTER)


## The icon of the gun's magazine beside the reserve, dropping out and back
## in from above while a reload starts.
func _draw_reserve_icon(colour: Color) -> void:
	var box := RESERVE_ICON
	if _reload >= 0.0:
		var t := _ease_in(_reload / RELOAD_SECONDS)
		box.position.y += 50.0 * t * 2.0 if t < 0.5 else -50.0 * (1.0 - t) * 2.0
	var texture := HudStyle.icon(reserve_icon(weapon_class))
	if texture != null:
		HudStyle.draw_fitted(self, texture, box, colour)
		return
	var centre := box.get_center()
	var along := Vector2(1, -1).normalized()
	var across := Vector2(1, 1).normalized()
	draw_colored_polygon(PackedVector2Array([
		centre - along * 9.0 - across * 3.0, centre + along * 9.0 - across * 3.0,
		centre + along * 9.0 + across * 3.0, centre - along * 9.0 + across * 3.0,
	]), colour)


## Where a jolt is `t` seconds into `length`: the three keyframes' offsets at
## 0, 25 and 50 %, back to rest at 100 %, and the scale from 1.15 at the
## start. Returns (x, y, scale).
static func _jolt(t: float, length: float, first: Vector2, second: Vector2, third: Vector2) -> Vector3:
	if t < 0.0:
		return Vector3(0, 0, 1)
	var f := clampf(t / length, 0.0, 1.0)
	var at: Vector2
	var scale := 1.0
	if f < 0.25:
		at = first.lerp(second, f / 0.25)
		scale = lerpf(1.15, 1.0, f / 0.25)
	elif f < 0.5:
		at = second.lerp(third, (f - 0.25) / 0.25)
	else:
		at = third.lerp(Vector2.ZERO, (f - 0.5) / 0.5)
	return Vector3(at.x, at.y, scale)


static func _ease_in(t: float) -> float:
	return t * t


static func _ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
