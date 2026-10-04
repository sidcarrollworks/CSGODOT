class_name HitParticles
extends RefCounted

## A bounded draw-time interpreter for the extracted impact layers.
## Random initial values are sampled once; motion is evaluated analytically
## from the event timestamp, so frame rate never changes a particle's path.
## Blood local +X follows the impact axis; world-impact local +Z follows
## the surface normal. Source +Z gravity remains world up in both cases.
## Unsupported shader/CP operators remain listed in the generated table.

const LIMIT := 512
const LOD := 2
const DRAG_STEP := 1.0 / 30.0
## Sid's playtest tuning: denser body mist that clears in half the time.
## The extracted table remains the unmodified authored reference.
const MIST_COUNT_SCALE := 2.0
const MIST_LIFE_SCALE := 0.5
const RENDER_DEFAULTS := {"radius_scale": 1.0, "overbright": 1.0, "max_length": 500.0, "frame_rate": 0.1, "alpha_threshold": 0.0}
const UNIT_RANGE := [0.0, 1.0]
const EMPTY_ARRAY := []
var live: Array[Dictionary] = []
var ground: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _layers := {}


func _init() -> void:
	for name: String in HitEffectTable.LAYERS:
		prepare(name, HitEffectTable.LAYERS[name])


func prepare(name: String, source: Dictionary) -> void:
	var layer := source.duplicate()
	var operations := {}
	for key: String in ["half", "alpha", "roll", "trail", "frame"]:
		var table_key := "trail_time" if key == "trail" else key
		var curve_key := table_key + "_curve"
		if source.has(curve_key):
			operations[key] = {"descriptor": source[curve_key], "constant_key": curve_key,
				"method": source.get(table_key + "_method", "PARTICLE_SET_REPLACE_VALUE")}
	layer._attribute_ops = operations
	var grow: Array = source.get("grow", [1,1])
	var window: Array = source.get("grow_time", [0,1])
	layer._growth = Vector4(float(grow[0]), float(grow[1]), float(window[0]), float(window[1]))
	layer._grow_bias = float(source.get("grow_bias", 0.5))
	layer._grow_ease = bool(source.get("grow_ease", false))
	layer._fade_prop = bool(source.get("fade_proportional", true))
	layer._fade_in_prop = bool(source.get("fade_in_proportional", layer._fade_prop))
	layer._fade_out_ease = bool(source.get("fade_out_ease", true))
	var renderers := []
	for renderer: Dictionary in source.get("renderers", []):
		var copy := renderer.duplicate()
		copy._hit_quad_key = HitQuads.key(renderer)
		renderers.append(copy)
	layer.renderers = renderers
	_layers[name] = layer


func spawn(effect: String, at: Vector3, direction: Vector3, born: int, eye: Vector3, damage: float = 30.0, screen: bool = false, world: bool = false) -> void:
	_rng.seed = hash([effect, at, born, damage])
	var context := {"at": at, "basis": impact_basis(direction), "born": born,
		"distance": eye.distance_to(at), "damage": damage, "screen": screen, "world": world,
		"cps": {1: Vector3(damage, 0, 0)}, "distance_ops": []}
	_open(effect, context, 0)


func _open(name: String, context: Dictionary, depth: int) -> void:
	if depth > 8 or HitEffectTable.GROUND.has(name):
		return
	var layer: Dictionary = _layers.get(name, {})
	var parameters: Dictionary = HitEffectTable.ROOT_PARAMS.get(name, layer)
	if parameters.has("distance_cp"):
		# Children inherit their parent's CPs. A child can add another distance
		# remap (world impacts use CP6) without changing its siblings' context.
		context = context.duplicate()
		context.cps = context.cps.duplicate()
		context.distance_ops = context.distance_ops.duplicate()
		context.distance_ops.append(parameters.distance_cp)
		update_distance(context, float(context.distance))
	if not layer.is_empty():
		_emit(name, layer, context)
	var children: Array = HitEffectTable.ROOTS.get(name, layer.get("children", []))
	var chosen := -1
	var choose_group := int(parameters.get("choose_child_group", -1))
	var groups: Array = parameters.get("child_groups", [])
	if choose_group >= 0:
		var candidates := []
		for index in children.size():
			if index < groups.size() and int(groups[index]) == choose_group:
				candidates.append(index)
		if not candidates.is_empty():
			# Duplicate children retain their authored selection weight.
			chosen = candidates[_rng.randi_range(0, candidates.size() - 1)]
	for index in children.size():
		if choose_group >= 0 and index < groups.size() and int(groups[index]) == choose_group and index != chosen:
			continue
		_open(children[index], context, depth + 1)


func _emit(name: String, layer: Dictionary, context: Dictionary) -> void:
	layer = _layers.get(name, layer)
	var body_mist := name.begins_with("blood_") and name.contains("mist") and not bool(context.get("screen", false)) and not name.contains("local")
	var count_scale := MIST_COUNT_SCALE if body_mist else 1.0
	var count := mini(roundi(value(layer.get("count", [1, 1, 1, 1]), context, 0, true) * count_scale), roundi(float(layer.get("count_cap", 64)) * count_scale))
	var basis: Basis = context.basis
	# The authored wall dust/burst layers emit along local +Z, whereas
	# blood spray emits along local +X. Children inherit the event frame.
	var local_frame := Basis(-basis.z, basis.y, basis.x) if bool(context.get("world", false)) else basis
	for index in count:
		if live.size() >= LIMIT:
			break
		var life := value(layer.get("life", [0.2, 0.2]), context, index)
		life *= value(layer.get("life_scale", [1, 1]), context, index)
		if body_mist:
			life *= MIST_LIFE_SCALE
		if life <= 0.0:
			continue
		var initial := {"life": life}
		var radius := value(layer.get("half", [1, 1]), context, index, false, initial)
		radius *= value(layer.get("half_scale", [1, 1]), context, index, false, initial)
		var sphere := random_vector().normalized()
		var offset := vector_range(layer.get("offset_min", [0, 0, 0]), layer.get("offset_max", [0, 0, 0]))
		offset += sphere * value(layer.get("sphere", [0, 0]), context, index)
		var velocity := vector_range(layer.get("velocity_min", [0, 0, 0]), layer.get("velocity_max", [0, 0, 0]))
		velocity += sphere * value(layer.get("sphere_speed", [0, 0]), context, index)
		var noise := vector_range(layer.get("noise_velocity_min", [0, 0, 0]), layer.get("noise_velocity_max", [0, 0, 0]))
		var c := vector_range(layer.get("color_min", [255, 255, 255]), layer.get("color_max", [255, 255, 255])) / 255.0
		var world_offset := local_frame * offset
		if layer.has("normal_offset"):
			var normal_offset := vector_range(layer.normal_offset, layer.get("normal_offset_max", layer.normal_offset))
			world_offset += normal_offset_world(normal_offset, basis)
		if body_mist:
			# Sid's hit-location tuning: mist starts at the pellet's surface
			# contact, with at most one inch of variation, then spreads.
			world_offset = world_offset.limit_length(1.0)
		var constants := {}
		for key: String in layer:
			if key.ends_with("_curve") and layer[key] is Array:
				constants[key] = value(layer[key], context, index)
		var render_constants := []
		for renderer: Dictionary in layer.get("renderers", []):
			var samples := {}
			for key: String in RENDER_DEFAULTS:
				var input: Variant = renderer.get(key, RENDER_DEFAULTS[key])
				if not input is Dictionary:
					samples[key] = value(input, context, index)
			render_constants.append(samples)
		var fade_in := value(layer.get("fade_in", [0,0]), context, index)
		var fade_out := value(layer.get("fade_out", [0.1,0.1]), context, index)
		var drag := clampf(float(layer.get("drag", 0.0)), 0.0, 0.9999)
		live.append({"name": name, "layer": layer, "context": context, "born": context.born,
			"origin": context.at + world_offset, "velocity": local_frame * velocity + noise_velocity(layer, noise, local_frame),
			"gravity": source_world(layer.get("gravity", [0, 0, 0])), "life": life,
			"drag_k": -log(1.0 - drag) / DRAG_STEP if drag > 0.0 else 0.0,
			"half": radius, "alpha": value(layer.get("alpha", [1, 1]), context, index),
			"color": Color(c.x, c.y, c.z).srgb_to_linear(), "roll": deg_to_rad(value(layer.get("roll", [0, 360]), context, index)),
			"seq": roundi(value(layer.get("seq", [0, 0]), context, index)),
			"index": index,
			"curve_constants": constants,
			"render_constants": render_constants,
			"spin": value(layer.get("spin", 0.0), context, index),
			"frame": value(layer.get("frame", [0, 0]), context, index),
			"fade_in": fade_in, "fade_out": fade_out,
			"fade_enter": fade_in * (life if bool(layer.get("_fade_in_prop", true)) else 1.0),
			"fade_leave": fade_out * (life if bool(layer.get("_fade_prop", true)) else 1.0),
			"trail": value(layer.get("trail_time", [0.1, 0.1]), context, index)})


## Starts projected ground children only when their parent actually dies.
## The physics owner takes these requests once, casts the authored 256u
## trace, then gives the splat its own authored lifetime (5–10 or 20s).
func advance(now: int) -> void:
	for index in range(live.size() - 1, -1, -1):
		var p := live[index]
		var age := float(now - int(p.born)) / 1e6
		if age < float(p.life):
			continue
		var children: Array = p.layer.get("children", [])
		var candidates: Array = children.filter(func(n: String) -> bool: return HitEffectTable.GROUND.has(n))
		if not candidates.is_empty():
			_rng.seed = hash([p.name, p.born, p.origin])
			var child: String = candidates[_rng.randi_range(0, candidates.size() - 1)]
			var layer: Dictionary = HitEffectTable.GROUND[child]
			var context: Dictionary = p.context
			var count := value(layer.get("count", [0, 0, 1, 1]), context, 0, true)
			if count > 0.0:
				var at := position(p, float(p.life)) + source_world(layer.get("offset_min", [0, 0, 32]))
				ground.append({"effect": child, "at": at, "born": int(p.born) + int(float(p.life) * 1e6),
					"life": value(layer.get("life", [5, 10]), context, 0), "half": value(layer.get("half", [20, 25]), context, 0),
					"roll": deg_to_rad(value(layer.get("roll", [0, 360]), context, 0)),
					"fade_in": value(layer.get("fade_in", [0.125, 0.15]), context, 0),
					"fade_out": value(layer.get("fade_out", [0.1, 0.1]), context, 0)})
		live.remove_at(index)


func draw(quads: Node, models: Node, eye: Transform3D, now: int, fov: float = 90.0) -> void:
	var height_at_unit := 2.0 * tan(deg_to_rad(fov) * 0.5)
	for p in live:
		var age := float(now - int(p.born)) / 1e6
		if age < 0.0 or age >= float(p.life):
			continue
		var layer: Dictionary = p.layer
		var context: Dictionary = p.context
		if int(context.get("distance_at_usec", -1)) != now or context.get("distance_eye", Vector3.INF) != eye.origin:
			update_distance(context, eye.origin.distance_to(context.at))
			context.distance_at_usec = now
			context.distance_eye = eye.origin
		var through := clampf(age / float(p.life), 0.0, 1.0)
		var centre := position(p, age)
		if float(layer.get("max_distance", 0.0)) > 0.0 and eye.origin.distance_to(centre) > float(layer.max_distance):
			continue
		var radius := attribute(p, "half", age, float(p.half) * growth(layer, through))
		var alpha := attribute(p, "alpha", age, float(p.alpha) * fade(p, age))
		var color: Color = p.color
		var roll := attribute(p, "roll", age, float(p.roll) + deg_to_rad(float(p.spin)) * age)
		var trail := attribute(p, "trail", age, float(p.trail))
		var frame := attribute(p, "frame", age, float(p.frame))
		var renderers: Array = layer.get("renderers", [])
		for renderer_index in renderers.size():
			var renderer: Dictionary = renderers[renderer_index]
			var kind := String(renderer.get("kind", "sprite"))
			if kind == "projected" or kind == "light":
				continue
			var half := radius * render_value(renderer, "radius_scale", p, renderer_index, age, 1.0)
			var a := alpha
			var screen_fade: Array = renderer.get("screen_fade", [])
			if not screen_fade.is_empty():
				var share := 2.0 * half / maxf(eye.origin.distance_to(centre) * height_at_unit, 1.0)
				var fade_start := value(screen_fade[0], context, int(p.index), false, p, age)
				var fade_end := value(screen_fade[1], context, int(p.index), false, p, age)
				a *= clampf(inverse_lerp(fade_end, fade_start, share), 0.0, 1.0) if fade_end != fade_start else float(share <= fade_start)
			var bright := render_value(renderer, "overbright", p, renderer_index, age, 1.0)
			var shade := Color(color.r * bright, color.g * bright, color.b * bright, a)
			if a <= 0.0 or half <= 0.0:
				continue
			var xform: Transform3D
			if kind == "model":
				var scale := half * 39.3700787 # glTF metre coordinates -> Source inches.
				xform = Transform3D(model_basis(p.context.basis, bool(renderer.get("orient_z", false)), roll).scaled(Vector3.ONE * scale), centre)
				models.card(renderer, xform, int(p.seq), shade)
				continue
			if kind == "trail":
				var tail := position(p, maxf(age - trail, 0.0))
				var max_length := render_value(renderer, "max_length", p, renderer_index, age, 500.0)
				if tail.distance_to(centre) > max_length:
					tail = centre + (tail - centre).normalized() * max_length
				if tail.distance_squared_to(centre) < 0.0001:
					continue
				xform = EffectQuads.streak(tail, centre, half, eye.origin)
			else:
				xform = EffectQuads.sprite(centre, half, roll, eye)
			if bool(p.context.screen):
				# CP positions for local screen particles are client code. Put
				# their extracted glow/alpha on a small camera-facing plane;
				# keep them clear of the centre and never alter aim/camera.
				var offset: Vector3 = p.origin - p.context.at
				var screen_at: Vector3 = eye.origin - eye.basis.z * 8.0 + eye.basis.x * offset.x * 0.035 + eye.basis.y * offset.y * 0.035
				xform = EffectQuads.sprite(screen_at, clampf(half * 0.025, 0.1, 1.5), roll, eye)
			var threshold := render_value(renderer, "alpha_threshold", p, renderer_index, age, 0.0)
			var rate := render_value(renderer, "frame_rate", p, renderer_index, age, 0.1)
			quads.card(renderer, xform, int(p.seq), animation_frame(renderer, p, frame, age, rate), shade, threshold)


## Exponential drag evaluated exactly with constant gravity, matching the
## authored drag fraction per 1/30s without per-frame Euler integration.
static func position(p: Dictionary, age: float) -> Vector3:
	var k := float(p.get("drag_k", -1.0))
	if k < 0.0:
		var drag := clampf(float(p.layer.get("drag", 0.0)), 0.0, 0.9999)
		k = -log(1.0 - drag) / DRAG_STEP if drag > 0.0 else 0.0
	if k <= 0.0:
		return p.origin + p.velocity * age + p.gravity * (0.5 * age * age)
	var integral := (1.0 - exp(-k * age)) / k
	return p.origin + p.velocity * integral + p.gravity * ((age - integral) / k)


static func impact_basis(direction: Vector3) -> Basis:
	var forward := direction.normalized() if direction.length_squared() > 1e-8 else Vector3.FORWARD
	var side := forward.cross(Vector3.UP if absf(forward.y) < 0.99 else Vector3.RIGHT).normalized()
	return Basis(forward, side, side.cross(forward).normalized())


static func source_world(v: Array) -> Vector3:
	return Vector3(float(v[0]), float(v[2]), -float(v[1]))


## Invalid/no transform means identity in Source space, not the hit axis.
## Explicit CP1 velocity noise is aligned with the client impact normal.
static func noise_velocity(layer: Dictionary, noise: Vector3, basis: Basis) -> Vector3:
	if String(layer.get("noise_transform", "")) == "PT_TYPE_INVALID" or int(layer.get("noise_cp", 0)) == 0 and String(layer.get("noise_transform", "")) == "":
		return Vector3(noise.x, noise.z, -noise.y)
	return basis * noise


## Exported native (x,y,z) is Source (y,z,x). The puff's native +Y is
## its authored Source +Z extrusion: orient_z aligns it with the normal.
static func model_basis(impact: Basis, orient_z: bool, roll: float) -> Basis:
	var frame := impact.rotated(impact.x, roll)
	return Basis(frame.y, frame.x, -frame.z) if orient_z else Basis(frame.y, frame.z, frame.x)


static func normal_offset_world(offset: Vector3, impact: Basis) -> Vector3:
	return -impact.z * offset.x + impact.y * offset.y + impact.x * offset.z


func vector_range(a: Array, b: Array) -> Vector3:
	return Vector3(_rng.randf_range(float(a[0]), float(b[0])), _rng.randf_range(float(a[1]), float(b[1])), _rng.randf_range(float(a[2]), float(b[2])))


func random_vector() -> Vector3:
	return Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))


func value(v: Variant, context: Dictionary, index: int, count: bool = false, p: Dictionary = {}, age: float = 0.0) -> float:
	if v is Array:
		if v.size() == 4 and count:
			return float(v[LOD])
		return _rng.randf_range(float(v[0]), float(v[-1]))
	if v is Dictionary:
		var x := 0.0
		match String(v.get("type", "")):
			"PF_TYPE_CONTROL_POINT_COMPONENT":
				var point: Vector3 = context.get("cps", {}).get(int(v.get("cp", 0)), Vector3.ZERO)
				x = point[clampi(int(v.get("component", 0)), 0, 2)]
			"PF_TYPE_PARTICLE_NUMBER":
				x = float(index)
			"PF_TYPE_PARTICLE_AGE", "PF_TYPE_COLLECTION_AGE":
				x = age
			"PF_TYPE_PARTICLE_AGE_NORMALIZED":
				x = age / float(p.get("life", 1.0))
			"PF_TYPE_PARTICLE_FLOAT", "PF_TYPE_PARTICLE_INITIAL_FLOAT":
				x = float(p.get({1: "life", 3: "half", 4: "roll", 7: "alpha", 10: "trail", 38: "frame"}.get(int(v.get("attribute", 0)), ""), 0.0))
			"PF_TYPE_PARTICLE_SPEED":
				var velocity: Vector3 = p.get("velocity", Vector3.ZERO)
				x = velocity.length()
		return mapped(v, x)
	return float(v)


static func biased(x: float, bias: float) -> float:
	if bias <= 0.0:
		return 0.0
	if bias >= 1.0:
		return 1.0
	x = clampf(x, 0.0, 1.0)
	return x / ((1.0 - x) * (1.0 / bias - 2.0) + 1.0)


## Source's float-map bias parameter [-1,1] differs from operator bias [0,1].
static func parameter_bias(x: float, parameter: float, type: String = "PF_BIAS_TYPE_STANDARD") -> float:
	if type == "PF_BIAS_TYPE_EXPONENTIAL":
		var exponent := 1.0 - clampf(parameter, 0, 1) if parameter >= 0.0 else 20.0 - clampf(parameter + 1.0, 0, 1) * 19.0
		return 1.0 if exponent <= 0.0 else pow(clampf(x, 0, 1), exponent)
	var bias := clampf((parameter + 1.0) * 0.5, 0, 1)
	if type == "PF_BIAS_TYPE_GAIN":
		return biased(x * 2.0, bias) * 0.5 if x < 0.5 else 1.0 - biased(2.0 - x * 2.0, bias) * 0.5
	return biased(x, bias)


static func remapped(x: float, input: Array, output: Array) -> float:
	if float(input[0]) == float(input[1]):
		return float(output[1] if x >= float(input[1]) else output[0])
	return lerpf(float(output[0]), float(output[1]), clampf(inverse_lerp(float(input[0]), float(input[1]), x), 0, 1))


static func mapped(descriptor: Dictionary, x: float) -> float:
	var input: Array = descriptor.get("input", UNIT_RANGE)
	var output: Array = descriptor.get("output", UNIT_RANGE)
	if descriptor.get("input_mode", "") == "PF_INPUT_MODE_LOOPED" and float(input[1]) != 0.0:
		x = fposmod(x, float(input[1]))
	match String(descriptor.get("map", "PF_MAP_TYPE_DIRECT")):
		"PF_MAP_TYPE_MULT":
			return x * float(descriptor.get("multiplier", 1.0))
		"PF_MAP_TYPE_REMAP":
			return remapped(x, input, output)
		"PF_MAP_TYPE_REMAP_BIASED":
			var t := clampf(inverse_lerp(float(input[0]), float(input[1]), x), 0, 1) if float(input[0]) != float(input[1]) else float(x >= float(input[1]))
			return lerpf(float(output[0]), float(output[1]), parameter_bias(t, float(descriptor.get("bias", 0.0)), String(descriptor.get("bias_type", "PF_BIAS_TYPE_STANDARD"))))
		"PF_MAP_TYPE_CURVE":
			return MuzzleFlashes._sample(descriptor.get("curve", EMPTY_ARRAY), x)
		"PF_MAP_TYPE_NOTCHED":
			var window: Array = descriptor.get("notched_range", [0, 1])
			var values: Array = descriptor.get("notched_output", [0, 1])
			return float(values[1] if x >= float(window[0]) and x <= float(window[1]) else values[0])
	return x


## The engine recomputes distance CPs before emission/operators. Recompute
## inherited thresholds against the current eye without mutating the table.
static func update_distance(context: Dictionary, distance: float) -> void:
	context.distance = distance
	var points: Dictionary = context.get("cps", {})
	for op: Dictionary in context.get("distance_ops", []):
		var cp := int(op.get("cp", 0))
		var point: Vector3 = points.get(cp, Vector3.ZERO)
		point[clampi(int(op.get("output_component", 0)), 0, 2)] = remapped(distance, op.get("input", [0, 128]), op.get("output", [0, 1]))
		points[cp] = point
	context.cps = points


func attribute(p: Dictionary, key: String, age: float, current: float) -> float:
	var layer: Dictionary = p.layer
	var op: Dictionary
	if layer.has("_attribute_ops"):
		if not layer._attribute_ops.has(key):
			return current
		op = layer._attribute_ops[key]
	else:
		# Synthetic/standalone callers can still use the public evaluator.
		var table_key := "trail_time" if key == "trail" else key
		if not layer.has(table_key + "_curve"):
			return current
		op = {"descriptor":layer[table_key + "_curve"], "constant_key":table_key + "_curve", "method":layer.get(table_key + "_method", "PARTICLE_SET_REPLACE_VALUE")}
	var method := String(op.method)
	var sample: float = p.get("curve_constants", {}).get(op.constant_key, 0.0) if op.descriptor is Array else value(op.descriptor, p.context, int(p.index), false, p, age)
	if key == "roll" and method not in ["PARTICLE_SET_SCALE_INITIAL_VALUE", "PARTICLE_SET_SCALE_CURRENT_VALUE"]:
		sample = deg_to_rad(sample)
	match method:
		"PARTICLE_SET_SCALE_INITIAL_VALUE":
			return float(p[key]) * sample
		"PARTICLE_SET_ADD_TO_INITIAL_VALUE":
			return float(p[key]) + sample
		"PARTICLE_SET_SCALE_CURRENT_VALUE":
			return current * sample
		"PARTICLE_SET_ADD_TO_CURRENT_VALUE":
			return current + sample
	return sample


func render_value(renderer: Dictionary, key: String, p: Dictionary, index: int, age: float, fallback: float) -> float:
	var samples: Dictionary = p.render_constants[index]
	if samples.has(key):
		return float(samples[key])
	return value(renderer.get(key, fallback), p.context, int(p.index), false, p, age)


func animation_frame(renderer: Dictionary, p: Dictionary, frame: float, age: float, rate: float = -1.0) -> float:
	match String(renderer.get("animation_type", "ANIMATION_TYPE_FIXED_RATE")):
		"ANIMATION_TYPE_MANUAL_FRAMES":
			return frame
		"ANIMATION_TYPE_FIXED_RATE":
			return animation_passes(renderer, p, age, rate)
	return animation_passes(renderer, p, age / float(p.life), rate)


static func animation_passes(renderer: Dictionary, p: Dictionary, time: float, rate: float = -1.0) -> float:
	var passes := time * (rate if rate >= 0.0 else float(renderer.get("frame_rate", 0.1)))
	if bool(renderer.get("animate_in_fps", false)):
		# prepare() prewarms this cache; draw never starts an asset read.
		var sheet: SpriteSheet = SpriteSheet._loaded.get(String(renderer.get("tex", "")))
		if sheet != null and not sheet.sequences.is_empty():
			var sequence := posmod(int(p.seq), sheet.sequences.size())
			var seconds := float(sheet._sequence_seconds[sequence])
			passes /= seconds if seconds > 0.0 else maxf(sheet.sequences[sequence].size(), 1)
	return passes


static func growth(layer: Dictionary, through: float) -> float:
	var data: Vector4
	if layer.has("_growth"):
		data = layer._growth
	else:
		var grow: Array = layer.get("grow", [1, 1])
		var window: Array = layer.get("grow_time", [0, 1])
		data = Vector4(float(grow[0]), float(grow[1]), float(window[0]), float(window[1]))
	if data.w <= data.z:
		return 1.0
	if through < data.z:
		return 1.0
	var t := clampf(inverse_lerp(data.z, data.w, through), 0, 1)
	var bias := float(layer._grow_bias) if layer.has("_growth") else float(layer.get("grow_bias", 0.5))
	var ease := bool(layer._grow_ease) if layer.has("_growth") else bool(layer.get("grow_ease", false))
	t = smoothstep(0, 1, t) if ease else biased(t, 0.5 if bias == 0.0 else bias)
	return lerpf(data.x, data.y, t)


static func fade(p: Dictionary, age: float) -> float:
	if age < 0.0 or age >= float(p.life):
		return 0.0
	var layer: Dictionary = p.layer
	if layer.has("fade_in_frac") or layer.has("fade_out_frac"):
		var through := age / float(p.life)
		var fade_start := float(layer.get("fade_in_start_frac", 0.0))
		var fade_end := float(layer.get("fade_in_frac", 0.5))
		var leave_start := float(layer.get("fade_out_frac", 0.5))
		var leave_end := float(layer.get("fade_out_end_frac", 1.0))
		var alpha := 1.0
		if through < fade_end and fade_end > fade_start:
			alpha = lerpf(float(layer.get("fade_in_start_alpha", 1.0)), 1.0, smoothstep(fade_start, fade_end, through))
		if through >= leave_start and leave_end > leave_start:
			alpha = lerpf(1.0, float(layer.get("fade_out_end_alpha", 0.0)), smoothstep(leave_start, leave_end, through))
		return alpha
	var enter: float
	var leave: float
	if p.has("fade_enter"):
		enter = p.fade_enter
		leave = p.fade_leave
	else:
		var proportional := bool(p.layer.get("fade_proportional", true))
		enter = float(p.fade_in) * (float(p.life) if bool(p.layer.get("fade_in_proportional", proportional)) else 1.0)
		leave = float(p.fade_out) * (float(p.life) if proportional else 1.0)
	var a := smoothstep(0, enter, age) if enter > 0 else 1.0
	var out := clampf((float(p.life) - age) / leave, 0, 1) if leave > 0 else 1.0
	if bool(layer._fade_out_ease) if layer.has("_fade_out_ease") else bool(layer.get("fade_out_ease", true)):
		out = smoothstep(0, 1, out)
	return a * out
