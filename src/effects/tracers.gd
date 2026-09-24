class_name Tracers
extends RefCounted

## A round's tracer, as CS2's particle files draw it: which rounds draw one,
## where it runs, how fast, how long and how bright, from the ten tracer
## effects the guns name (m_szTracerParticle), decompiled with Source 2
## Viewer (particles/weapons/cs_weapon_fx/weapon_tracers_*.vpcf, CS2
## 1.41.8.3, read 2026-09-24).
##
## Two kinds. The trails (pistols, shotguns, rifles, snipers) are one
## particle flying from the muzzle to where the round stopped, dying there,
## drawn as a streak behind it: a white-hot core and a wider glow, each
## the length its trail time gives at its speed, growing in over its first
## hundredth of a second and capped. The ropes (the SMGs, the AUG and
## SG 553, the machine guns) are a still beam from the muzzle to the end
## with one streak sliding down it; drawn here as that streak, without the
## heat shimmer CS2 gives the beam.
##
## How the files read, where it is not written in them (inferred, from the
## operators' Source 1 behaviour): a trail's life is the distance over its
## speed, cut short on a short shot; its trail time in seconds times its
## speed is its length; its fades are shares of its life; its width is its
## radius times the renderer's scale, either side. Your own first-person
## tracer is twice as long as anyone else's (CP3.x, set 1 in first person,
## a designer's note says). Where the round went through walls, the tracer
## ends at the first and a fainter, slower streak goes on from there to
## where it stopped (impact_wallbang's weapon_wallbang_risidual_tracers).
##
## Which rounds: every round of a gun that has tracers at all, as CS2's
## client overrides the guns' every-third to every one
## (cl_tracer_frequency_override 1, development-only, so fixed in the
## shipped game; that it leaves a silenced gun's 0 alone is inferred). A
## sniper's round more than 0.085 inaccurate draws only 200 units of
## tracer (sv_sniper_tracer_mode 1), so a noscope's does not show where it
## went.

## cl_tracer_frequency_override: every nth round draws one; -1 leaves the
## gun's own m_nTracerFrequency.
const FREQUENCY_OVERRIDE := 1
## sv_sniper_tracer_innacuracy and sv_sniper_tracer_innacuracy_length.
const SNIPER_INACCURACY := 0.085
const SNIPER_LENGTH := 200.0

## The core's colour by its texture's brightness (a 1D lookup), and the
## glow's (weapon_tracers_*.vpcf, the renderers' gradients).
const CORE_GRADIENT := [[0.377261, Color8(255, 68, 21)], [0.470284, Color8(255, 165, 0)], [1.0, Color8(255, 255, 255)]]
const GLOW_GRADIENT := [[0.571059, Color8(0, 0, 0)], [0.757106, Color8(255, 68, 21)], [0.819121, Color8(255, 165, 0)], [1.0, Color8(255, 255, 255)]]
const WALLBANG_GLOW_GRADIENT := [[0.0, Color8(0, 0, 0)], [0.48062, Color8(255, 68, 21)], [0.677003, Color8(255, 165, 0)], [1.0, Color8(255, 255, 255)]]
## The core's texture, and the glow's sheet and its sequence.
const CORE_TEXTURE := "materials/effects/spark.vtex"
const GLOW_TEXTURE := "materials/particle/sparks/sparks.vtex"

## The trails. speed in u/s; trail, seconds of flight the streak shows;
## fp_long, whether your own first-person one is twice as long (CP3.x);
## fp_wide, whether it is also twice as wide; flown, the trail stretching as
## the round flies ([from, to] units flown, [from, to] share); most, its
## longest in units; grow, seconds for the core and the glow to grow to
## their length; radius, and the core's and glow's scales of it (full width
## is twice radius times scale); screen, the least and most share of the
## screen's height its radius may take; fade_size, the screen share over
## which a sniper's fades out when it passes the eye; alpha; tint; fade,
## the shares of its life it fades in from and to and out from; cut, the
## shot's length [from, to] over which its life comes up from nothing (a
## short shot draws less or none); ahead, units in front of the muzzle it
## starts; glow_seq, the glow's sequence; core_alpha, the core's alpha
## scale; draw, how far off it is drawn.
const TRAILS := {
	&"pistol": {"speed": [18000.0, 18000.0], "trail": [0.05, 0.05], "fp_long": true, "fp_wide": false, "flown": [100.0, 4800.0, 1.0, 1.2],
		"most": 900.0, "grow": [0.05, 0.05], "radius": 1.0, "scale": [0.5, 0.65], "screen": [0.0005, 0.005], "fade_size": [],
		"alpha": [0.54902, 0.803922], "tint": [Color8(247, 213, 94), Color8(255, 245, 219)], "fade": [0.2, 0.35, 0.95],
		"cut": [], "ahead": 0.0, "glow_seq": 4, "core_alpha": 1.0, "draw": 10000.0},
	&"shot": {"speed": [24000.0, 24500.0], "trail": [0.03, 0.05], "fp_long": true, "fp_wide": false, "flown": [100.0, 1200.0, 1.0, 1.2],
		"most": 900.0, "grow": [0.05, 0.05], "radius": 1.0, "scale": [0.5, 0.65], "screen": [0.0005, 0.005], "fade_size": [],
		"alpha": [0.627451, 0.803922], "tint": [Color8(247, 134, 93), Color8(255, 236, 219)], "fade": [0.15, 0.25, 0.95],
		"cut": [150.0, 180.0], "ahead": 0.0, "glow_seq": 4, "core_alpha": 1.0, "draw": 10000.0},
	&"assrifle": {"speed": [20500.0, 20500.0], "trail": [0.085, 0.1], "fp_long": true, "fp_wide": false, "flown": [0.0, 8400.0, 0.8, 1.2],
		"most": 1200.0, "grow": [0.08, 0.095], "radius": 1.0, "scale": [0.5, 0.75], "screen": [0.00075, 0.002], "fade_size": [],
		"alpha": [0.627451, 0.686275], "tint": [Color8(255, 255, 255), Color8(255, 255, 255)], "fade": [0.2, 0.3, 0.95],
		"cut": [0.0, 180.0], "ahead": 0.0, "glow_seq": 4, "core_alpha": 1.0, "draw": 20000.0},
	&"rifle": {"speed": [30000.0, 30000.0], "trail": [0.1, 0.1], "fp_long": true, "fp_wide": true, "flown": [500.0, 6400.0, 1.0, 1.2],
		"most": 900.0, "grow": [0.1, 0.1], "radius": 2.0, "scale": [0.5, 0.65], "screen": [0.001, 0.01], "fade_size": [0.015, 0.025],
		"alpha": [0.54902, 0.705882], "tint": [Color8(247, 188, 94), Color8(255, 245, 219)], "fade": [0.2, 0.3, 0.95],
		"cut": [10.0, 180.0], "ahead": 20.0, "glow_seq": 4, "core_alpha": 1.0, "draw": 10000.0},
	&"rifle_ssg": {"speed": [30000.0, 30000.0], "trail": [0.1, 0.1], "fp_long": true, "fp_wide": false, "flown": [500.0, 6400.0, 1.0, 1.2],
		"most": 900.0, "grow": [0.1, 0.1], "radius": 2.0, "scale": [0.5, 0.65], "screen": [0.001, 0.01], "fade_size": [0.015, 0.025],
		"alpha": [0.54902, 0.705882], "tint": [Color8(247, 188, 94), Color8(255, 245, 219)], "fade": [0.2, 0.3, 0.95],
		"cut": [150.0, 180.0], "ahead": 20.0, "glow_seq": 4, "core_alpha": 1.0, "draw": 10000.0},
	&"rifle_scar": {"speed": [30000.0, 30000.0], "trail": [0.1, 0.1], "fp_long": false, "fp_wide": false, "flown": [0.0, 6400.0, 1.0, 1.2],
		"most": 900.0, "grow": [0.1, 0.1], "radius": 2.0, "scale": [0.5, 0.65], "screen": [0.001, 0.01], "fade_size": [0.015, 0.025],
		"alpha": [0.54902, 0.705882], "tint": [Color8(247, 188, 94), Color8(255, 245, 219)], "fade": [0.2, 0.3, 0.95],
		"cut": [], "ahead": 20.0, "glow_seq": 4, "core_alpha": 1.0, "draw": 10000.0},
	# particles/weapons/cs_weapon_fx/weapon_wallbang_risidual_tracers.vpcf,
	# a child of particles/impact_fx/impact_wallbang_heavy and _light.
	&"wallbang": {"speed": [10500.0, 10500.0], "trail": [0.025, 0.05], "fp_long": false, "fp_wide": false, "flown": [0.0, 8400.0, 0.8, 1.2],
		"most": 500.0, "grow": [0.02, 0.02], "radius": 1.0, "scale": [0.5, 0.75], "screen": [0.00075, 0.0075], "fade_size": [],
		"alpha": [0.627451, 0.686275], "tint": [Color8(255, 255, 255), Color8(255, 255, 255)], "fade": [0.2, 0.3, 0.95],
		"cut": [], "ahead": 0.0, "glow_seq": 7, "core_alpha": 0.5, "draw": 20000.0},
}

## The ropes: the streak's texture; how fast it slides (the texture's
## scroll, u/s); how long the beam lasts, 1.1 x min(shot / cut, 1) x
## lerp(life_min, 1, min(shot / life_span, 1)) seconds; its width either
## side at the muzzle and at the end (radius x the rope's scale); its colour
## at birth, easing to color; overbright. The streak is 400 units long: the
## texture's V, 4 times over a world size of 100 (inferred).
const ROPES := {
	&"smg": {"texture": "materials/particle/effects/bullet_tracer_seq.vtex", "scroll": 18000.0, "cut": 180.0, "life_min": 0.05, "life_span": 22000.0,
		"half": [1.875, 1.875], "color": Color8(247, 210, 185), "birth": Color8(229, 172, 112), "overbright": 2.0},
	&"assrifle_aug": {"texture": "materials/particle/effects/bullet_tracer_tintable.vtex", "scroll": 20500.0, "cut": 180.0, "life_min": 0.1, "life_span": 20500.0,
		"half": [2.0, 3.0], "color": Color8(255, 255, 255), "birth": Color8(229, 172, 112), "overbright": 2.0},
	&"mach": {"texture": "materials/particle/effects/bullet_tracer_tintable.vtex", "scroll": 15500.0, "cut": 300.0, "life_min": 0.1, "life_span": 20500.0,
		"half": [1.25, 3.75], "color": Color8(255, 255, 255), "birth": Color8(229, 172, 112), "overbright": 2.0},
}
const ROPE_STREAK := 400.0
## The rope's streak texture is wider than the streak it draws: of its
## width, the rope shows 1 / 0.75 (the texture's U scale), so the bright
## middle is about a quarter of the rope's (inferred).
const ROPE_TEXTURE_SCALE_U := 0.75


## The tracer effect a gun names, by its kind ("assrifle", "smg"): &"" for
## a gun without one (the knife) or whose effect is not rebuilt (the Zeus).
static func kind_of(weapon_class: String) -> StringName:
	var fields: Dictionary = WeaponVData.classes().get(weapon_class, {})
	var effect := String(fields.get("m_szTracerParticle", "")).get_file().get_basename()
	if not effect.begins_with("weapon_tracers_"):
		return &""
	var kind := StringName(effect.trim_prefix("weapon_tracers_"))
	return kind if TRAILS.has(kind) or ROPES.has(kind) else &""


## Whether a gun's nth round (from 0) draws a tracer: never for a gun whose
## frequency is 0 in this mode (mode 1: silencer on, or scoped), otherwise
## every round (FREQUENCY_OVERRIDE), or, without the override, every
## frequency-th starting with the first.
static func draws(weapon_class: String, mode: int, nth: int) -> bool:
	if kind_of(weapon_class) == &"":
		return false
	var frequency := int(WeaponVData.number(weapon_class, "m_nTracerFrequency", mode == 1))
	if frequency <= 0:
		return false
	if FREQUENCY_OVERRIDE > 0:
		frequency = FREQUENCY_OVERRIDE
	return nth % frequency == 0


## How far a round's tracer runs: the whole way, but for a sniper's round
## more inaccurate than SNIPER_INACCURACY (CS2's own units, the tangent),
## which draws SNIPER_LENGTH.
static func reach(weapon_class: String, inaccuracy: float, distance: float) -> float:
	var item := ItemRegistry.item(weapon_class)
	if item != null and item.type == "sniper" and inaccuracy > SNIPER_INACCURACY:
		return minf(distance, SNIPER_LENGTH)
	return distance


## A trail's colour at a brightness, from a gradient's stops.
static func gradient(stops: Array, brightness: float) -> Color:
	if brightness <= float(stops[0][0]):
		return stops[0][1]
	for i in range(1, stops.size()):
		if brightness <= float(stops[i][0]):
			var from: float = stops[i - 1][0]
			var weight := inverse_lerp(from, float(stops[i][0]), brightness)
			return (stops[i - 1][1] as Color).lerp(stops[i][1], weight)
	return stops[stops.size() - 1][1]


## One trail on its way: made by Trail.make, drawn from its head, length,
## width and alpha at each age.
class Trail:
	var kind: StringName
	var rules: Dictionary
	var start: Vector3
	var end: Vector3
	var direction: Vector3
	var distance: float
	var speed: float
	## Seconds until the head reaches the end, when the whole streak goes.
	var life: float
	var trail_seconds: float
	var grow_core: float
	var grow_glow: float
	var alpha: float
	var tint: Color
	var half_core: float
	var half_glow: float
	## When the round was fired, in simulation time, and how long ago that
	## is at the frame being drawn.
	var fired_usec := 0
	var age := 0.0

	## A trail from start to end, or null where CS2 draws none (a shot
	## shorter than its cut, or none at all). first_person: your own, seen
	## from the first-person gun.
	static func make(p_kind: StringName, from: Vector3, to: Vector3, first_person: bool, rng: RandomNumberGenerator) -> Trail:
		var p_rules: Dictionary = TRAILS.get(p_kind, {})
		if p_rules.is_empty():
			return null
		var trail := Trail.new()
		trail.kind = p_kind
		trail.rules = p_rules
		trail.direction = (to - from).normalized()
		trail.start = from + trail.direction * float(p_rules["ahead"])
		trail.end = to
		trail.distance = maxf((to - trail.start).dot(trail.direction), 0.0)
		trail.speed = rng.randf_range(p_rules["speed"][0], p_rules["speed"][1])
		trail.life = trail.distance / trail.speed
		var cut: Array = p_rules["cut"]
		if not cut.is_empty():
			trail.life *= clampf(inverse_lerp(float(cut[0]), float(cut[1]), (to - from).length()), 0.0, 1.0)
		if trail.life <= 0.0:
			return null
		var short := 1.0 if first_person or not p_rules["fp_long"] else 0.5
		trail.trail_seconds = rng.randf_range(p_rules["trail"][0], p_rules["trail"][1]) * short
		trail.grow_core = p_rules["grow"][0]
		trail.grow_glow = p_rules["grow"][1]
		trail.alpha = rng.randf_range(p_rules["alpha"][0], p_rules["alpha"][1])
		trail.tint = (p_rules["tint"][0] as Color).lerp(p_rules["tint"][1], rng.randf())
		var narrow := 1.0 if first_person or not p_rules["fp_wide"] else 0.5
		trail.half_core = float(p_rules["radius"]) * float(p_rules["scale"][0]) * narrow
		trail.half_glow = float(p_rules["radius"]) * float(p_rules["scale"][1]) * narrow
		return trail

	func alive() -> bool:
		return age < life

	## How far the head has flown.
	func flown(at: float = age) -> float:
		return minf(speed * at, distance)

	func head(at: float = age) -> Vector3:
		return start + direction * flown(at)

	## The streak's length behind the head, for a layer that grows over
	## grow seconds: its trail time at its speed, stretched as it flies,
	## growing in, capped, and never behind the muzzle.
	func length(grow: float, at: float = age) -> float:
		var stretch: Array = rules["flown"]
		var share := lerpf(stretch[2], stretch[3], clampf(inverse_lerp(stretch[0], stretch[1], flown(at)), 0.0, 1.0))
		var grown := clampf(at / grow, 0.0, 1.0) if grow > 0.0 else 1.0
		return minf(minf(speed * trail_seconds * share * grown, float(rules["most"])), flown(at))

	## Its alpha at an age: none until it has come fade[0] of its life, up
	## to its own by fade[1], held, and out from fade[2] to its end.
	func alpha_at(at: float = age) -> float:
		var fade: Array = rules["fade"]
		var through := at / life
		if through < fade[0] or through >= 1.0:
			return 0.0
		if through < fade[1]:
			return alpha * inverse_lerp(fade[0], fade[1], through)
		if through > fade[2]:
			return alpha * inverse_lerp(1.0, fade[2], through)
		return alpha


## One rope's streak: made by Rope.make.
class Rope:
	var kind: StringName
	var rules: Dictionary
	var start: Vector3
	var end: Vector3
	var direction: Vector3
	var distance: float
	var life: float
	var fired_usec := 0
	var age := 0.0

	static func make(p_kind: StringName, from: Vector3, to: Vector3) -> Rope:
		var p_rules: Dictionary = ROPES.get(p_kind, {})
		if p_rules.is_empty():
			return null
		var rope := Rope.new()
		rope.kind = p_kind
		rope.rules = p_rules
		rope.start = from
		rope.end = to
		rope.distance = from.distance_to(to)
		rope.direction = (to - from).normalized()
		rope.life = life_for(p_rules, rope.distance)
		return rope if rope.life > 0.0 else null

	static func life_for(p_rules: Dictionary, distance: float) -> float:
		return 1.1 * minf(distance / float(p_rules["cut"]), 1.0) \
			* lerpf(p_rules["life_min"], 1.0, minf(distance / float(p_rules["life_span"]), 1.0))

	func alive() -> bool:
		return age < life

	## The streak's head and tail along the beam, in units from the muzzle,
	## at an age; the tail past the end once it has gone by.
	func span(at: float = age) -> Vector2:
		var head := float(rules["scroll"]) * at
		return Vector2(maxf(head - ROPE_STREAK, 0.0), minf(head, distance))

	## Its colour: the birth colour easing to its own over its life.
	func color_at(at: float = age) -> Color:
		var through := clampf(at / life, 0.0, 1.0)
		return (rules["birth"] as Color).lerp(rules["color"], through)
