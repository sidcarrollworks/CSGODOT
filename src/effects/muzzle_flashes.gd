class_name MuzzleFlashes
extends Node3D

## The muzzle flashes: each gun's flash, first person and third, played from
## FlashTable, which carries CS2's own flash effects worked out for each gun
## and view (particles/unified_weapon_fx/, decompiled): the flames, the
## beams and compensator streaks, the sparks, the smoke and the flash's
## light, each a handful of particles.
##
## A shot picks what its flash draws as CS2's effect does (every "always"
## layer, one of "pick1", two different of "pick2"), makes each layer's
## particles where the table says (down the barrel, round it, at random
## over a sphere) and runs them per frame: speeds, drag, gravity, growth,
## fades, colours and sprite-sheet frames. A layer that rides the gun
## (follow) keeps its particles in the muzzle's own frame, so the flame
## stays on the barrel as the gun kicks; the rest stay where they were made.
## First person, the cards take the view model's projection, as the gun
## does, but for the layers CS2 draws in the world (world_pass).
##
## Left out, as effects this rebuild does not have: the particles' noise
## and curl forces and wind, depth feathering, the smoke's shadows and each
## smoke's own self-illumination (all take 0.1), motion-vector sheets and
## extra texture layers, the trails' tapers, and CS2's bloom pass (stood in
## for by a glow card behind each flame, BLOOM_SIZE). The table's "bias"
## (skewed random draws) is drawn uniform.

## Seconds of CS2's drag step: velocity x (1 - drag) each 1/30 s.
const DRAG_STEP := 1.0 / 30.0
## How bright a flash's light is in Godot's energy per unit of CS2's
## intensity x alpha (C_OP_RenderStandardLight). Set by eye against the
## renders; a Local check compares a wall lit by a flash in CS2.
const LIGHT_ENERGY := 12.0
## Lights at once, the oldest reused.
const LIGHTS := 8
## CS2 draws every flame a second time into its effects bloom, which is
## blurred and added over the frame (the renderers with
## m_bOnlyRenderInEffectsBloomPass): it is most of how big and bright a flash
## looks. How far the blur spreads is not in the files, so it is stood in for
## by a soft glow card behind each flame (CS2's own particle_glow_04), this
## many times the flame's size and this bright, set by eye against Sid's
## screenshot of a Glock's flash (reference/cs2 _screenshots/
## Glock_muzzleflash.png): stronger, it hazes the gun white, where CS2's is
## a fireball.
const BLOOM_SIZE := 1.6
const BLOOM_STRENGTH := 0.2
const BLOOM_TEXTURE := "materials/particle/particle_glow_04.vtex"
## Whether CS2's particle colours (the 0-255 of a colour picker) are
## decoded from sRGB before they multiply the texture. Not for the flames and
## tracers: Sid's screenshot has the Glock's flame yellow-white at its core,
## which CS2's numbers give only as they are (overbright 4 on 0.78 x 0.70
## red, 2.2), and decoded they come out orange. The smoke, lit by the scene
## as a surface is, is decoded.
const DECODE_COLOURS := false
## Where the textures the table names by their short names are.
const TEXTURE_PATHS := {
	"spark": "materials/effects/spark.vtex",
	"particle_glow_04": "materials/particle/particle_glow_04.vtex",
}

var quads: EffectQuads
var _flashes: Array[Flash] = []
var _lights: Array[OmniLight3D] = []
var _light_until: Array[int] = []
## The particle each light is lit for: a light the pool hands a newer flash
## is that flash's.
var _light_owner: Array = []
var _next_light := 0


## One flash on its way: the gun it came from, where its muzzle was, and
## its particles.
class Flash:
	var gun: Node3D
	## The skeleton its muzzle is on, found once (Muzzles.skeleton_of).
	var skeleton: Skeleton3D
	var weapon_class: String
	var second := false
	var first_person := false
	## CP0 placed once (PATTACH_POINT): the flash stays where it was fired.
	var fixed := false
	var cp0_forward := 0.0
	var born_usec := 0
	var muzzle: Transform3D
	var particles: Array[Particle] = []


class Particle:
	var layer: Dictionary
	var kind: StringName
	var index := 0
	## Seconds after the shot it appears, and how long it lives.
	var delay := 0.0
	var life := 0.1
	var age := 0.0
	## How far into its life it starts (age_start).
	var head_start := 0.0
	## Whether its delay has run out and it is drawn.
	var born := false
	## Where it is, and how fast it goes: in the muzzle's frame (inches,
	## +X down the barrel, +Y left, +Z up) while it rides the gun, in the
	## world once it does not.
	var local := true
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var accel := Vector3.ZERO
	var half := 1.0
	var roll := 0.0
	var alpha := 1.0
	var color := Color.WHITE
	var sequence := 0
	var frame := 0.0
	var trail_seconds := 0.0
	## Seconds before its death it starts to fade, and when it is culled.
	var fade_window := 0.0
	var dies_at := INF
	var light: OmniLight3D


func _ready() -> void:
	for i in LIGHTS:
		var light := OmniLight3D.new()
		light.visible = false
		light.shadow_enabled = false
		add_child(light)
		_lights.append(light)
		_light_until.append(0)
		_light_owner.append(null)


## A round's flash: weapon_class fired in mode (1 silenced), its nth round,
## seen first_person or not, from gun (the ViewModel or the PlayerModel
## holding it), at its second muzzle (the silencer's tip, the Berettas' left
## pistol) or its first; fired_usec in simulation time.
func fire(weapon_class: String, mode: int, nth: int, first_person: bool, gun: Node3D, second: bool, fired_usec: int, rng: RandomNumberGenerator) -> void:
	var key := flash_for(weapon_class, mode, second and weapon_class == "weapon_elite", first_person)
	if key.is_empty() or not FlashTable.FLASHES.has(key):
		return
	var flash := Flash.new()
	flash.gun = gun
	flash.weapon_class = weapon_class
	flash.second = second
	flash.first_person = first_person
	var entry: Dictionary = FlashTable.FLASHES[key]
	flash.fixed = bool(entry.get("fixed", false))
	flash.cp0_forward = float(entry.get("cp0_fwd", 0.0))
	flash.born_usec = fired_usec
	flash.skeleton = Muzzles.skeleton_of(gun)
	var at: Variant = _muzzle(flash)
	if at == null:
		return
	flash.muzzle = at
	for layer in layers_of(entry, rng):
		_spawn(flash, layer, rng)
	_flashes.append(flash)


## The FlashTable.FLASHES key a shot plays: the gun's view's, its silenced
## one in mode 1, the Berettas' left pistol's for left; "" for a gun
## without one.
static func flash_for(weapon_class: String, mode: int, left: bool, first_person: bool) -> String:
	var gun: Dictionary = FlashTable.GUNS.get(weapon_class, {})
	var view := "fp" if first_person else "tp"
	if mode == 1 and gun.has(view + "_silenced"):
		return gun[view + "_silenced"]
	if left and gun.has(view + "_left"):
		return gun[view + "_left"]
	return gun.get(view, "")


## What one shot of a flash draws: every "always" layer, one "pick1", two
## different "pick2"s, groups opened, each a layer with its overrides laid
## over it. "" (a pick of nothing) draws nothing.
static func layers_of(entry: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var picked: Array = (entry.get("always", []) as Array).duplicate()
	var one: Array = entry.get("pick1", [])
	if not one.is_empty():
		picked.append(one[rng.randi_range(0, one.size() - 1)])
	var two: Array = (entry.get("pick2", []) as Array).duplicate()
	for i in mini(2, two.size()):
		picked.append(two.pop_at(rng.randi_range(0, two.size() - 1)))
	var out: Array[Dictionary] = []
	for item: Variant in picked:
		_open(item, out)
	return out


static func _open(item: Variant, out: Array[Dictionary]) -> void:
	if item is Dictionary and (item as Dictionary).has("group"):
		for inner: Variant in item["group"]:
			_open(inner, out)
		return
	var name := ""
	var overrides := {}
	if item is String or item is StringName:
		name = String(item)
	elif item is Array and not (item as Array).is_empty():
		name = String(item[0])
		if (item as Array).size() > 1:
			overrides = item[1]
	if name.is_empty() or not FlashTable.LAYERS.has(name):
		return
	var layer: Dictionary = (FlashTable.LAYERS[name] as Dictionary).duplicate()
	layer.merge(overrides, true)
	layer["name"] = name
	out.append(layer)


## Where a flash's muzzle is now: on the gun as it is posed, or, fixed or
## with the gun gone, where it was.
func _muzzle(flash: Flash) -> Variant:
	var at: Variant = null
	if is_instance_valid(flash.skeleton) and flash.skeleton.is_inside_tree():
		at = Muzzles.on_skeleton(flash.skeleton, flash.weapon_class, flash.second)
	if at == null:
		return null
	var muzzle := (at as Transform3D).orthonormalized()
	muzzle.origin += muzzle.basis.x * flash.cp0_forward
	return muzzle


## A layer's particles, as its initializers make them.
func _spawn(flash: Flash, layer: Dictionary, rng: RandomNumberGenerator) -> void:
	var kind := StringName(layer.get("kind", "sprite"))
	var count := _count(layer, rng)
	# One draw a burst, shared by its particles (CS2's InitFloatCollection).
	var shared := rng.randf()
	var half_shared := _range(layer.get("half_shared", [1.0, 1.0]), rng)
	var trail_shared := _range(layer.get("trail_time_shared", [0.0, 0.0]), rng)
	var ring_start := rng.randf() * TAU
	for i in count:
		var p := Particle.new()
		p.layer = layer
		p.kind = kind
		p.index = i
		p.delay = float(layer.get("delay", 0.0))
		if layer.has("emit_rate"):
			p.delay += float(i) / float(layer["emit_rate"])
		p.life = _by_index(layer, "life_by_index", i, shared, rng) if layer.has("life_by_index") else _range(layer.get("life", [0.1, 0.1]), rng)
		p.life *= float(layer.get("life_scale", 1.0))
		if p.life <= 0.0:
			continue
		if layer.has("age_start"):
			p.head_start = _range(layer["age_start"], rng) * p.life
			p.age = p.head_start
		p.local = float(layer.get("follow", 0.0)) > 0.0 and not flash.fixed
		p.position = _place(layer, i, count, shared, ring_start, rng)
		p.velocity = _speed(layer, i, shared, p.position, rng)
		p.accel = Vector3(_range(layer.get("accel_fwd", 0.0), rng) + _range(layer.get("force_fwd", 0.0), rng),
			_range(layer.get("force_side", 0.0), rng), 0.0)
		if kind == &"light":
			p.half = float(layer.get("range", 80.0))
		elif layer.has("half_by_index"):
			p.half = _by_index(layer, "half_by_index", i, shared, rng)
		elif layer.has("half_shared"):
			p.half = half_shared * _range(layer.get("half_scale", [1.0, 1.0]), rng)
		else:
			p.half = _range(layer.get("half", [1.0, 1.0]), rng)
		p.roll = deg_to_rad(_range(layer.get("roll", [0.0, 0.0]), rng)) * (-1.0 if layer.get("roll_flip", false) and rng.randf() < 0.5 else 1.0)
		p.alpha = _range(layer.get("alpha", [1.0, 1.0]), rng)
		if layer.has("alpha2_by_index"):
			p.alpha *= float((layer["alpha2_by_index"] as Array)[mini(i, (layer["alpha2_by_index"] as Array).size() - 1)])
		elif layer.has("alpha2"):
			p.alpha *= float(layer["alpha2"])
		var low: Color = layer.get("color_min", Color.WHITE)
		var high: Color = layer.get("color_max", Color.WHITE)
		p.color = low.lerp(high, rng.randf())
		var seq: Array = layer.get("seq", [0, 0])
		p.sequence = rng.randi_range(int(seq[0]), int(seq[1]))
		p.frame = _by_index(layer, "frame_by_index", i, shared, rng) if layer.has("frame_by_index") else _range(layer.get("frame", [0.0, 0.0]), rng)
		if layer.has("trail_time_shared"):
			p.trail_seconds = trail_shared * _range(layer.get("trail_scale", [1.0, 1.0]), rng)
		else:
			p.trail_seconds = _range(layer.get("trail_time", [0.0, 0.0]), rng)
		p.fade_window = _fade_window(layer, p.life, rng)
		var cull: Array = layer.get("cull", [])
		if not cull.is_empty() and rng.randf() < float(cull[0]):
			p.dies_at = float(cull[1]) * p.life
		if not p.local:
			# Made in the world, where the muzzle was: it does not ride the gun.
			p.position = flash.muzzle * p.position
			p.velocity = flash.muzzle.basis * p.velocity
			p.accel = flash.muzzle.basis * p.accel
			if layer.has("on_ground") and not _to_ground(p, float(layer["on_ground"]), float(layer.get("on_ground_radius_offset", 0.0))):
				continue
		flash.particles.append(p)


## Moves every flash on to the frame's simulation time and draws it.
func advance(now_usec: int, eye: Transform3D) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var height_at_unit := 2.0 * tan(deg_to_rad(camera.fov if camera != null else 73.7) * 0.5)
	var kept: Array[Flash] = []
	for flash in _flashes:
		var since := float(now_usec - flash.born_usec) / 1_000_000.0
		if not flash.fixed:
			var at: Variant = _muzzle(flash)
			if at != null:
				flash.muzzle = at
		var alive: Array[Particle] = []
		for p in flash.particles:
			if _step(flash, p, since):
				alive.append(p)
				if p.born:
					_draw(flash, p, eye, height_at_unit)
		flash.particles = alive
		if not alive.is_empty():
			kept.append(flash)
	_flashes = kept
	_update_lights(now_usec)


## Runs a particle on to since seconds after the shot; false once it is dead.
func _step(flash: Flash, p: Particle, since: float) -> bool:
	var age := since - p.delay + p.head_start
	if age < p.head_start:
		return true
	p.born = true
	var dt := maxf(age - p.age, 0.0)
	p.age = maxf(age, p.age)
	if p.age >= p.life or p.age >= p.dies_at:
		return false
	if p.local and p.layer.has("follow_release") and p.age >= float(p.layer["follow_release"]):
		p.local = false
		p.position = flash.muzzle * p.position
		p.velocity = flash.muzzle.basis * p.velocity
		p.accel = flash.muzzle.basis * p.accel
	if dt > 0.0:
		var gravity := Vector3(0.0, float(p.layer.get("gravity", 0.0)), 0.0)
		if p.local:
			gravity = flash.muzzle.basis.inverse() * gravity
		p.velocity += (p.accel + gravity) * dt
		var drag := float(p.layer.get("drag", 0.0))
		if drag > 0.0:
			p.velocity *= pow(1.0 - drag, dt / DRAG_STEP)
		var most := float(p.layer.get("max_speed", 0.0))
		if most > 0.0 and p.velocity.length() > most:
			p.velocity = p.velocity.normalized() * most
		p.position += p.velocity * dt
	return true


func _draw(flash: Flash, p: Particle, eye: Transform3D, height_at_unit: float) -> void:
	var layer := p.layer
	var through := p.age / p.life
	var at := flash.muzzle * p.position if p.local else p.position
	if p.kind == &"light":
		_light(flash, p, at)
		return
	var alpha := p.alpha * _fade(layer, p, through)
	var curve: Array = layer.get("alpha_curve", [])
	if not curve.is_empty():
		alpha *= _sample(curve, through)
	var color := p.color
	if layer.has("birth_tint"):
		color = (layer["birth_tint"] as Color).lerp(p.color, clampf(through / maxf(float(layer.get("birth_tint_until", 1.0)), 0.001), 0.0, 1.0))
	if layer.has("color_end"):
		var from := float(layer.get("color_end_from", 0.0))
		var to := float(layer.get("color_end_to", 1.0))
		color = color.lerp(layer["color_end"], clampf(inverse_lerp(from, to, through), 0.0, 1.0))
	var decode := DECODE_COLOURS or p.kind == &"smoke"
	var tint: Color = layer.get("tint", Color.WHITE)
	if decode:
		tint = tint.srgb_to_linear()
		color = color.srgb_to_linear()
	var bright := float(layer.get("overbright", 1.0))
	color = Color(color.r * tint.r * bright, color.g * tint.g * bright, color.b * tint.b * bright)
	var half := p.half * _grow(layer, through)
	for rate: Array in layer.get("radius_rate", []):
		half += float(rate[0]) * clampf(p.age - float(rate[1]), 0.0, float(rate[2]) - float(rate[1]))
	var added: Array = layer.get("radius_add_curve", [])
	if not added.is_empty():
		half += _sample_at(added, p.age)
	var distance := maxf(eye.origin.distance_to(at), 1.0)
	var share := 2.0 * half / (distance * height_at_unit)
	var screen_fade: Array = layer.get("screen_fade", [])
	if not screen_fade.is_empty():
		alpha *= clampf(inverse_lerp(float(screen_fade[1]), float(screen_fade[0]), share), 0.0, 1.0)
	if layer.has("max_screen"):
		half = minf(half, float(layer["max_screen"]) * distance * height_at_unit * 0.5)
	if alpha <= 0.0 or half <= 0.0:
		return
	var first_person: bool = flash.first_person and not layer.get("world_pass", false)
	# Smoke is lit by the scene, as CS2's is; its lighten blend (a max) is
	# drawn as a mix, which Godot's spatial shaders have.
	var blend := &"add" if String(layer.get("blend", "add")) == "add" else (&"lit" if p.kind == &"smoke" else &"mix")
	var texture_name := String(layer.get("tex", "spark"))
	var sheet := SpriteSheet.named(texture_path(texture_name))
	if sheet == null:
		return
	var frame := p.frame + float(layer.get("frame_rate", 0.0)) * p.age
	if layer.has("frame_age_bias"):
		frame = (frame if frame > 0.0 else 1.0) * pow(through, log(float(layer["frame_age_bias"])) / log(0.5))
	var uv := sheet.frame(p.sequence, frame)
	var shade := Color(color.r, color.g, color.b, alpha)
	if p.kind == &"sprite" or p.kind == &"smoke":
		quads.quad(sheet.texture, blend, first_person, EffectQuads.sprite(at, half, p.roll, eye), uv, shade)
		if p.kind == &"sprite" and blend == &"add" and BLOOM_STRENGTH > 0.0:
			var bloom := SpriteSheet.named(BLOOM_TEXTURE)
			if bloom != null:
				quads.quad(bloom.texture, &"add", first_person, EffectQuads.sprite(at, half * BLOOM_SIZE, 0.0, eye),
					Rect2(0.0, 0.0, 1.0, 1.0), Color(shade.r * BLOOM_STRENGTH, shade.g * BLOOM_STRENGTH, shade.b * BLOOM_STRENGTH, shade.a))
		return
	# A trail or spark: drawn back from the particle along its way, its
	# head (the card's top) at the particle.
	var velocity := flash.muzzle.basis * p.velocity if p.local else p.velocity
	var speed := velocity.length()
	if speed < 1e-3:
		return
	var seconds := p.trail_seconds + float(layer.get("trail_rate", 0.0)) * p.age
	var zero_at := float(layer.get("trail_time_zero_at", 0.0))
	if zero_at > 0.0:
		seconds *= clampf(1.0 - through / zero_at, 0.0, 1.0)
	var trail_curve: Array = layer.get("trail_time_curve", [])
	if not trail_curve.is_empty():
		seconds = _sample(trail_curve, through)
	var ends := []
	if layer.has("head") or layer.has("tail"):
		ends = [layer.get("head", Color.WHITE), layer.get("tail", Color.WHITE)]
	var passes: Array = layer.get("passes", [{}])
	for render_pass: Dictionary in passes:
		var length := speed * seconds * float(render_pass.get("length_scale", layer.get("length_scale", 1.0)))
		var fade_in := float(render_pass.get("length_fade_in", 0.0))
		if fade_in > 0.0:
			length *= clampf(p.age / fade_in, 0.0, 1.0)
		length = clampf(length, float(layer.get("min_length", 0.0)), float(render_pass.get("max_length", layer.get("max_length", INF))))
		if length <= 0.0:
			continue
		var width := half * float(render_pass.get("width", 1.0))
		# A renderer's own size limit, a share of the screen's height.
		if render_pass.has("max_screen"):
			width = minf(width, float(render_pass["max_screen"]) * distance * height_at_unit * 0.5)
		var tail := at - velocity / speed * length
		var spark_uv := Rect2(uv.position.x, uv.end.y, uv.size.x, -uv.size.y) if texture_name == "spark" else uv
		quads.quad(sheet.texture, blend, first_person, EffectQuads.streak(tail, at, width, eye.origin), spark_uv, shade, ends)


## The light of a flash: one of the pool, lit for the layer's life.
func _light(flash: Flash, p: Particle, at: Vector3) -> void:
	if p.light == null:
		p.light = _lights[_next_light]
		_next_light = (_next_light + 1) % _lights.size()
		var offset: Vector3 = p.layer.get("offset", Vector3.ZERO)
		offset.y += randf_range(-1.0, 1.0) * float(p.layer.get("offset_side", 0.0))
		p.position = offset if p.local else flash.muzzle * offset
		p.light.omni_range = p.half
		p.light.light_color = p.color.srgb_to_linear()
		p.light.light_energy = float(p.layer.get("energy", 0.2)) * p.alpha * LIGHT_ENERGY
		p.light.visible = true
		var slot := _lights.find(p.light)
		_light_until[slot] = flash.born_usec + int((p.delay + p.life) * 1_000_000.0)
		_light_owner[slot] = p
	if _light_owner[_lights.find(p.light)] != p:
		return
	p.light.global_position = flash.muzzle * p.position if p.local else p.position


func _update_lights(now_usec: int) -> void:
	for i in _lights.size():
		if _lights[i].visible and now_usec >= _light_until[i]:
			_lights[i].visible = false
			_light_owner[i] = null


## Where the texture a layer names by its short name is, as CS2's path.
static func texture_path(short_name: String) -> String:
	if FlashTable.SHEETS.has(short_name):
		return FlashTable.SHEETS[short_name]["path"]
	if TEXTURE_PATHS.has(short_name):
		return TEXTURE_PATHS[short_name]
	for path: String in FlashTable.TEXTURES:
		if path.get_file().get_basename() == short_name:
			return path
	return ""


static func _count(layer: Dictionary, rng: RandomNumberGenerator) -> int:
	var count: Variant = layer.get("count", 1)
	var n := rng.randi_range(int(count[0]), int(count[1])) if count is Array else int(count)
	if layer.has("emit_rate") and layer.has("emit_for"):
		n = maxi(roundi(float(layer["emit_rate"]) * float(layer["emit_for"])), 1)
	return mini(n, int(layer.get("count_cap", n)))


## A number from a [min, max] range, or the number itself.
static func _range(value: Variant, rng: RandomNumberGenerator) -> float:
	if value is Array:
		var pair := value as Array
		return float(pair[0]) if pair.size() < 2 else rng.randf_range(float(pair[0]), float(pair[1]))
	return float(value)


## A value given per particle index: a number, a [min, max] drawn per
## particle, or for positions and frames [at t 0, at t 1] of the burst's
## one shared t.
static func _by_index(layer: Dictionary, key: String, i: int, shared: float, rng: RandomNumberGenerator) -> float:
	var list: Array = layer[key]
	var value: Variant = list[mini(i, list.size() - 1)]
	if value is Array:
		if key in ["x_by_index", "yz_by_index", "frame_by_index"]:
			return lerpf(float(value[0]), float(value[1]), shared)
		return rng.randf_range(float(value[0]), float(value[1]))
	return float(value)


## Where a particle is made, in the muzzle's frame.
static func _place(layer: Dictionary, i: int, count: int, shared: float, ring_start: float, rng: RandomNumberGenerator) -> Vector3:
	var at := Vector3(_range(layer.get("x", 0.0), rng), _range(layer.get("y", 0.0), rng), _range(layer.get("z", 0.0), rng))
	if layer.has("x_by_index"):
		at.x += _by_index(layer, "x_by_index", i, shared, rng)
	if layer.has("yz_by_index"):
		var yz := _by_index(layer, "yz_by_index", i, shared, rng)
		at.y += yz
		at.z += yz
	var side := float(layer.get("side", 0.0))
	if side > 0.0:
		at.y += rng.randf_range(-side, side)
		at.z += rng.randf_range(-side, side)
	var sphere := float(layer.get("sphere", 0.0))
	if sphere > 0.0:
		var bias: Vector3 = layer.get("sphere_bias", Vector3.ONE)
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * bias
		if layer.get("sphere_fwd_only", false):
			direction.x = absf(direction.x)
		at += direction.normalized() * sphere * rng.randf()
	var ring := float(layer.get("ring", 0.0))
	if ring > 0.0:
		var per: Variant = layer.get("ring_count", [count, count])
		var spokes := maxi(int(per[0]) if per is Array else int(per), 1)
		var angle := ring_start + TAU * float(i % spokes) / float(spokes)
		if layer.has("ring_yaw"):
			at += Vector3(cos(angle), sin(angle), 0.0) * ring
		else:
			at += Vector3(0.0, cos(angle), sin(angle)) * ring
	return at


## How fast a particle is made going, in the muzzle's frame.
static func _speed(layer: Dictionary, i: int, shared: float, at: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var forward := _by_index(layer, "vel_fwd_by_index", i, shared, rng) if layer.has("vel_fwd_by_index") else _range(layer.get("vel_fwd", 0.0), rng)
	var side := _by_index(layer, "vel_side_by_index", i, shared, rng) if layer.has("vel_side_by_index") else _range(layer.get("vel_side", 0.0), rng)
	var velocity := Vector3(forward, side, _range(layer.get("vel_up", 0.0), rng))
	var out := 0.0
	if layer.has("vel_out_by_index"):
		out = _by_index(layer, "vel_out_by_index", i, shared, rng)
	out += _range(layer.get("ring_speed", 0.0), rng)
	if out != 0.0:
		var across := Vector3(at.x, at.y, 0.0) if layer.has("ring_yaw") else Vector3(0.0, at.y, at.z)
		if across.length_squared() > 1e-8:
			velocity += across.normalized() * out
	return velocity


## Seconds before death a particle starts to fade: fade_out's window, or
## fade_frac's share of its life.
static func _fade_window(layer: Dictionary, life: float, rng: RandomNumberGenerator) -> float:
	if layer.has("fade_out"):
		return _range(layer["fade_out"], rng)
	if layer.has("fade_frac"):
		return _range(layer["fade_frac"], rng) * life
	return 0.0


static func _fade(layer: Dictionary, p: Particle, through: float) -> float:
	var shown := 1.0
	var into := float(layer.get("fade_in_frac", 0.0))
	if into > 0.0:
		shown *= clampf(through / into, 0.0, 1.0)
	if p.fade_window > 0.0:
		var left := p.life - p.age
		var out := clampf(left / minf(p.fade_window, p.life), 0.0, 1.0)
		if layer.get("fade_ease", true):
			out = smoothstep(0.0, 1.0, out)
		shown *= out
	return shown


## A radius's multiplier over its life: grow [start, end], eased by CS2's
## bias (0.5 straight).
static func _grow(layer: Dictionary, through: float) -> float:
	var grow: Array = layer.get("grow", [1.0, 1.0])
	var bias := float(layer.get("grow_bias", 0.5))
	var eased := through / ((1.0 / bias - 2.0) * (1.0 - through) + 1.0) if bias != 0.5 else through
	return lerpf(float(grow[0]), float(grow[1]), clampf(eased, 0.0, 1.0))


## A curve of [x, y] points, straight between them, held at the ends.
static func _sample(curve: Array, x: float) -> float:
	return _sample_at(curve, x)


static func _sample_at(curve: Array, x: float) -> float:
	if x <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(1, curve.size()):
		if x <= float(curve[i][0]):
			return lerpf(float(curve[i - 1][1]), float(curve[i][1]), inverse_lerp(float(curve[i - 1][0]), float(curve[i][0]), x))
	return float(curve[curve.size() - 1][1])


## Drops a world particle onto the floor within reach below it (CS2's
## PositionPlaceOnGround), sunk by sink times its radius; false, and it is
## not made, over nothing.
func _to_ground(p: Particle, reach: float, sink: float = 0.0) -> bool:
	if not is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters3D.create(p.position, p.position + Vector3.DOWN * reach, Hitscan.WORLD_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	p.position = hit["position"] + Vector3.UP * sink * p.half
	return true
