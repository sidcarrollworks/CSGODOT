extends "res://tests/check_suite.gd"

class Cards extends Node:
	var drawn: Array[Dictionary] = []
	func card(renderer: Dictionary, xform: Transform3D, sequence: int, frame: float, color: Color, threshold: float = -1.0) -> void:
		drawn.append({"renderer": renderer, "xform": xform, "seq": sequence, "frame": frame, "color": color, "threshold": threshold})

class Models extends Node:
	var drawn := 0
	var transforms: Array[Transform3D] = []
	func card(_renderer: Dictionary, xform: Transform3D, _sequence: int, _color: Color) -> void:
		drawn += 1
		transforms.append(xform)


func _initialize() -> void:
	_test_mapping()
	_test_fades()
	_test_authored_draw()
	_test_mist_tuning()
	_test_actual_renderers()
	_test_renderer_colour_and_size()
	_test_velocity_and_model_axes()
	_test_world_ejection()
	_test_puff_contact_origin()
	_test_hit_mist_origins()
	_test_authored_child_choice()
	_test_prepared_evaluation()
	_test_native_draw()
	_finish("hit-particles")


func _context(screen: bool = false) -> Dictionary:
	return {"at": Vector3.ZERO, "basis": Basis.IDENTITY, "born": 1000000,
		"distance": 128.0, "damage": 30.0, "screen": screen,
		"cps": {1: Vector3(30,0,0)}, "distance_ops": []}


func _test_mapping() -> void:
	_check_near(HitParticles.biased(0.25, 0.75), 0.5, "operator bias uses the Source rational curve")
	_check_near(HitParticles.biased(0.5, 0.75), 0.75, "operator bias is its midpoint")
	_check_near(HitParticles.parameter_bias(0.25, 0.5), 0.5, "float map bias converts [-1,1] to operator [0,1]")
	_check_near(HitParticles.parameter_bias(0.25, 0.0), 0.25, "zero float map parameter is identity")
	_check_near(HitParticles.parameter_bias(0.25, 0.5, "PF_BIAS_TYPE_GAIN"), 0.375, "gain has separate lower-half remapping")
	_check_near(HitParticles.parameter_bias(0.25, 0.5, "PF_BIAS_TYPE_EXPONENTIAL"), 0.5, "exponential bias follows its own parameterization")
	var map := {"map": "PF_MAP_TYPE_DIRECT", "input": [0,1], "output": [5,10], "multiplier": 4}
	_check_near(HitParticles.mapped(map, 2), 2, "direct map leaves its value unchanged without stray output remap or multiplication")
	map.map = "PF_MAP_TYPE_MULT"
	_check_near(HitParticles.mapped(map, 2), 8, "only multiply mapping applies multiplier")
	map.map = "PF_MAP_TYPE_REMAP"
	_check_near(HitParticles.mapped(map, 0.25), 6.25, "range mapping preserves authored outputs")
	map.input = [1,0]
	_check_near(HitParticles.mapped(map, 0.25), 8.75, "descending inputs retain endpoint pairing")
	map.input = [1,1]
	_check_near(HitParticles.mapped(map, 0.25), 5, "a zero-width remap selects below its step")
	_check_near(HitParticles.mapped(map, 1), 10, "a zero-width remap selects its upper endpoint")
	map = {"map":"PF_MAP_TYPE_CURVE", "curve":[[0,0],[0.25,0.8],[1,1]], "multiplier":4}
	_check_near(HitParticles.mapped(map, 0.25), 0.8, "curve follows its authored knot without a stray multiplier")
	map = {"map":"PF_MAP_TYPE_REMAP_BIASED", "input":[0,1], "output":[0,10], "bias":0.5}
	_check_near(HitParticles.mapped(map, 0.25), 5, "biased range mapping uses float parameterization")
	var runner := HitParticles.new()
	var context := _context()
	var p := {"life":2.0, "half":6.0}
	_check_near(runner.value({"type":"PF_TYPE_PARTICLE_AGE_NORMALIZED"}, context, 0, false, p, 0.5), 0.25, "normalized age uses this particle's lifetime")
	_check_near(runner.value({"type":"PF_TYPE_PARTICLE_AGE"}, context, 0, false, p, 0.5), 0.5, "age in seconds is independent of lifespan")
	_check_near(runner.value({"type":"PF_TYPE_PARTICLE_FLOAT", "attribute":1}, context, 0, false, p), 2, "attribute inputs read lifespan rather than arbitrary camera distance")
	_check_near(runner.value({"type":"PF_TYPE_CONTROL_POINT_COMPONENT", "cp":1, "component":0}, context, 0), 30, "damage CP input retains the event's scalar")
	context.distance_ops = [HitEffectTable.ROOT_PARAMS["blood_impact_med"].distance_cp]
	for pair in [[0,0.2], [128,0.2], [576,0.525], [1024,0.85], [2048,0.85]]:
		HitParticles.update_distance(context, pair[0])
		_check_near(context.cps[4].x, pair[1], "blood CP4 applies authored distance endpoints at %su" % pair[0])
	_check_near(context.cps[1].x, 30, "distance CP updates preserve other control points")
	var grow := {"grow":[0.1,3], "grow_time":[0.3,1], "grow_bias":0.65}
	_check_near(HitParticles.growth(grow, 0.1), 1, "radius before its operator window retains its initial value")
	_check_near(HitParticles.growth(grow, 0.65), 0.1 + 2.9 * 0.65, "authored radius scale uses rational bias inside its window")


func _test_fades() -> void:
	var p := {"life":4.0, "fade_in":0.25, "fade_out":0.25, "layer":{"fade_proportional":true}}
	_check_near(HitParticles.fade(p, 0.25), 0.15625, "random fade-in uses smoothstep over proportional lifespan")
	_check_near(HitParticles.fade(p, 3.75), 0.15625, "random fade-out uses smoothstep over proportional lifespan")
	p.layer.fade_out_ease = false
	_check_near(HitParticles.fade(p, 3.75), 0.25, "simple fade-out is linear")
	p.layer = {"fade_proportional":false, "fade_in_proportional":false}
	_check_near(HitParticles.fade(p, 0.125), 0.5, "non-proportional fade-in duration is seconds")
	_check_near(HitParticles.fade(p, 3.875), 0.5, "non-proportional fade-out duration is seconds")
	p.layer = {"fade_in_start_frac":0.1, "fade_in_frac":0.3, "fade_in_start_alpha":0.0,
		"fade_out_frac":0.6, "fade_out_end_frac":0.8, "fade_out_end_alpha":0.0}
	_check_near(HitParticles.fade(p, 0.8), 0.5, "combined fade uses its authored fade-in window")
	_check_near(HitParticles.fade(p, 2.8), 0.5, "combined fade uses its authored fade-out window")
	_check_near(HitParticles.fade(p, 3.6), 0, "a combined fade ending early stays invisible until lifespan expiry")
	_check_near(HitParticles.fade(p, -1), 0, "a particle cannot draw before its event")
	_check_near(HitParticles.fade(p, 4), 0, "a particle cannot draw at or after expiry")


func _test_authored_draw() -> void:
	var runner := HitParticles.new()
	runner.spawn("blood_impact_low", Vector3.ZERO, Vector3.RIGHT, 1000000, Vector3(0,0,128))
	var spray: Dictionary
	for p in runner.live:
		if p.name == "blood_impact_low_forw_spray":
			spray = p
			break
	_check(not spray.is_empty(), "current low root opens its forward spray layer")
	if spray.is_empty():
		return
	spray.life = 1.0
	runner.live = [spray]
	var quads := Cards.new()
	var models := Cards.new()
	runner.draw(quads, models, Transform3D(Basis.IDENTITY, Vector3(0,0,128)), 1368377)
	_check_equal(quads.drawn.size(), 2, "both forward-spray renderers share the particle but draw separate cards")
	if quads.drawn.size() >= 2:
		_check_near(quads.drawn[0].frame, 0.62216, "manual animation evaluates the real authored normalized-age curve")
		_check_near(quads.drawn[0].threshold, 0.2, "near-camera CP4 reaches per-card alpha threshold")
		_check_near(quads.drawn[1].threshold, 0, "secondary smoke renderer keeps its own zero threshold")
	quads.drawn.clear()
	runner.draw(quads, models, Transform3D(Basis.IDENTITY, Vector3(0,0,1024)), 1368377)
	if not quads.drawn.is_empty():
		_check_near(quads.drawn[0].threshold, 0.85, "threshold tracks current draw eye after emission")
	quads.drawn.clear()
	runner.draw(quads, models, Transform3D.IDENTITY, 2000000)
	_check_equal(quads.drawn.size(), 0, "drawing independently of advance cannot show expired particles")
	var curve: Dictionary = spray.layer.frame_curve
	_check_near(runner.value(curve, spray.context, spray.index, false, spray, 0.368377), 0.62216, "descriptor does not read camera distance for normalized-age curves")
	var samples := {"frame":2.0, "index":0, "context":_context(), "life":1.0, "layer":{
		"frame_curve":{"type":"PF_TYPE_PARTICLE_AGE", "map":"PF_MAP_TYPE_DIRECT"}, "frame_method":"PARTICLE_SET_ADD_TO_INITIAL_VALUE"}}
	_check_near(runner.attribute(samples, "frame", 0.25, 99), 2.25, "add-to-initial curves start from the stored initial value")
	samples.layer.frame_method = "PARTICLE_SET_SCALE_INITIAL_VALUE"
	_check_near(runner.attribute(samples, "frame", 0.25, 99), 0.5, "scale-initial curves avoid accumulating per frame")
	samples.layer.frame_method = "PARTICLE_SET_REPLACE_VALUE"
	_check_near(runner.attribute(samples, "frame", 0.25, 99), 0.25, "replace curves overwrite initial frame")
	var cache_count := SpriteSheet._loaded.size()
	_check_near(HitParticles.animation_passes({"tex":"unprepared/missing", "frame_rate":2, "animate_in_fps":true}, {"seq":0}, 0.25), 0.5, "absent prepared sprite cache remains a safe playback fallback")
	_check_equal(SpriteSheet._loaded.size(), cache_count, "draw-time playback never calls named or touches an unprepared asset")
	quads.free()
	models.free()


func _test_mist_tuning() -> void:
	var name := "blood_impact_low_mist_away"
	var layer: Dictionary = HitEffectTable.LAYERS[name]
	var authored_count := mini(roundi(layer.count[HitParticles.LOD]), int(layer.count_cap))
	var runner := HitParticles.new()
	runner._emit(name, layer, _context())
	_check_equal(runner.live.size(), authored_count * 2, "body mist emits twice the authored density with scaled layer capacity")
	var last_expiry := 1000000
	for p in runner.live:
		_check(p.life >= float(layer.life[0]) * 0.5 and p.life <= float(layer.life[1]) * 0.5, "body mist retains the authored random lifetime range at half duration")
		last_expiry = maxi(last_expiry, int(p.born) + ceili(float(p.life) * 1e6))
	runner.advance(last_expiry)
	_check_equal(runner.live.size(), 0, "denser mist expires by the shortened authored deadline")
	runner._emit(name, layer, _context(true))
	_check_equal(runner.live.size(), authored_count, "local screen reactions keep their authored density")
	for p in runner.live:
		_check(p.life >= float(layer.life[0]) and p.life <= float(layer.life[1]), "local screen reactions retain the authored lifetime")
	runner.live.clear()
	for index in 100:
		runner._emit(name, layer, _context())
	_check_equal(runner.live.size(), HitParticles.LIMIT, "denser mist still respects the total particle budget")
	_check_near(layer.life[0], HitEffectTable.LAYERS[name].life[0], "playtest tuning leaves source table lifetimes untouched")


func _test_actual_renderers() -> void:
	var runner := HitParticles.new()
	var quads := Cards.new()
	var models := Models.new()
	var eye := Transform3D(Basis.IDENTITY, Vector3(0,0,256))
	for name: String in HitEffectTable.ROOTS:
		runner.live.clear()
		runner.spawn(name, Vector3.ZERO, Vector3.RIGHT, 1000000, eye.origin)
		runner.draw(quads, models, eye, 1040000)
		runner.draw(quads, models, eye, 1200000)
	_check(quads.drawn.size() > 100 and models.drawn > 0, "all extracted roots execute real sprite/trail/model draw paths with dynamic renderer inputs")
	var valid := true
	for card in quads.drawn:
		valid = valid and is_finite(card.frame) and is_finite(card.threshold) and is_finite(card.color.a) and card.xform.is_finite()
	_check(valid, "all authored renderer inputs produce finite frame, threshold, alpha and transforms")
	var turned := true
	for xform in models.transforms:
		turned = turned and xform.basis.determinant() > 0.0
	_check(turned, "every impact mesh is drawn through a turn, never a mirror image that would light it inside out")
	quads.free()
	models.free()


## Sid's flickering squares (2026-10-07): the light flash's halo was drawn
## white from a texture CS2 switches off, and the darken sprite white at its
## world size. Each renderer now has CS2's colour, alpha and screen limits.
func _test_renderer_colour_and_size() -> void:
	var runner := HitParticles.new()
	var quads := Cards.new()
	var models := Models.new()
	var height_at_unit := 2.0 * tan(deg_to_rad(90.0) * 0.5)
	var near := Transform3D(Basis.IDENTITY, Vector3(0, 0, 20))
	runner.spawn("impact_light_flash", Vector3.ZERO, Vector3.BACK, 1000000, near.origin, 30.0, false, true)
	runner.draw(quads, models, near, 1010000)
	var halo := {}
	var flash := {}
	for card: Dictionary in quads.drawn:
		var texture := String(card.renderer.get("tex", ""))
		if texture.ends_with("particle_glow_04.vtex"):
			halo = card
		elif texture.ends_with("ash_flecks.vtex"):
			flash = card
	_check(not halo.is_empty() and halo.color.r == 0.0 and halo.color.g == 0.0 and halo.color.a > 0.0 and halo.color.a <= 0.4 + 1e-6,
		"the light flash's halo is CS2's glow drawn black at 40%, not its switched-off flecks drawn white")
	_check(not flash.is_empty() and flash.color.r > flash.color.b,
		"the flash itself keeps its warm 231/205/182 colour")
	if not halo.is_empty() and not flash.is_empty():
		var halo_screen: float = near.origin.distance_to(halo.xform.origin) * height_at_unit
		var flash_screen: float = near.origin.distance_to(flash.xform.origin) * height_at_unit
		_check(flash.xform.basis.x.length() <= 0.02 * flash_screen * 1.0001,
			"twenty units from the wall the flash is held to 2% of the screen's height")
		_check(halo.xform.basis.x.length() >= 0.012 * halo_screen * 0.9999 and halo.xform.basis.x.length() <= 0.03 * halo_screen * 1.0001,
			"and its halo between 1.2% and 3%")
	runner.live.clear()
	quads.drawn.clear()
	runner.spawn("impact_fx_hit_darken", Vector3.ZERO, Vector3.BACK, 1000000, Vector3(0, 0, 40), 30.0, false, true)
	var sprites := 0
	for p in runner.live:
		if p.name == "impact_fx_hit_darken":
			sprites += 1
			_check_near(p.alpha, 0.0, "nearer than about 76 units the darken sprite's distance curve leaves it no alpha")
	_check(sprites > 0, "the darken root spawns its sprite")
	runner.live.clear()
	var middle := Transform3D(Basis.IDENTITY, Vector3(0, 0, 300))
	runner.spawn("impact_fx_hit_darken", Vector3.ZERO, Vector3.BACK, 1000000, middle.origin, 30.0, false, true)
	runner.draw(quads, models, middle, 1010000)
	var dark := {}
	for card: Dictionary in quads.drawn:
		if String(card.renderer.get("tex", "")).ends_with("aircraft_hot.vtex"):
			dark = card
	_check(not dark.is_empty() and dark.color.a > 0.0 and dark.color.r < 0.02,
		"at 300 units the darken sprite is drawn, dark (33/27/27), where it was white")
	if not dark.is_empty():
		var screen: float = middle.origin.distance_to(dark.xform.origin) * height_at_unit
		_check(dark.xform.basis.x.length() >= 0.005 * screen * 0.9999 and dark.xform.basis.x.length() <= 0.008 * screen * 1.0001,
			"and it is a dot between 0.5% and 0.8% of the screen's height")
	# Concrete's chips run from 105/105/105 to 215/230/234 by one blend, not
	# a draw a channel (which made them green, purple and red).
	runner.live.clear()
	for shot in 12:
		runner.spawn("impact_concrete", Vector3.ZERO, Vector3.BACK, 1000000 + shot, Vector3(0, 0, 60), 30.0, false, true)
	var chips := 0
	var blended := true
	for p in runner.live:
		if p.name != "impact_concrete":
			continue
		chips += 1
		var srgb: Color = (p.color as Color).linear_to_srgb()
		var t := (srgb.r * 255.0 - 105.0) / 110.0
		blended = blended and t > -0.01 and t < 1.01 and absf(srgb.g * 255.0 - (105.0 + t * 125.0)) < 1.0 and absf(srgb.b * 255.0 - (105.0 + t * 129.0)) < 1.0
	_check(chips > 0 and blended, "concrete's chips take one blend of their two colours")
	quads.free()
	models.free()


func _test_velocity_and_model_axes() -> void:
	var horizontal := HitParticles.impact_basis(Vector3.RIGHT)
	var vertical := HitParticles.impact_basis(Vector3.UP)
	var noise := Vector3(4,5,6)
	var world := {"noise_transform":"PT_TYPE_INVALID", "noise_cp":0}
	_check(HitParticles.noise_velocity(world, noise, horizontal).is_equal_approx(Vector3(4,6,-5)), "invalid noise transform preserves Source-world axes")
	_check_equal(HitParticles.noise_velocity(world, noise, horizontal), HitParticles.noise_velocity(world, noise, vertical), "world noise direction is independent of the shot direction")
	_check_equal(HitParticles.noise_velocity({}, noise, horizontal), Vector3(4,6,-5), "absent noise transform uses the identity Source frame")
	_check(HitParticles.noise_velocity({"noise_cp":1}, noise, horizontal).is_equal_approx(horizontal * noise), "explicit impact CP keeps its authored local velocity transform")
	var normal := Vector3(0.3,0.4,0.5).normalized()
	var impact := HitParticles.impact_basis(normal)
	var puff := HitParticles.model_basis(impact, true, 0.0)
	_check(puff.y.is_equal_approx(normal), "orient_z puff native +Y extrudes along the impact normal")
	_check(absf(puff.x.dot(normal)) < 1e-6 and absf(puff.z.dot(normal)) < 1e-6, "puff native X/Z span the wall plane")
	_check(HitParticles.model_basis(impact, true, 1.25).y.is_equal_approx(normal), "puff roll stays around the extrusion axis")
	var fleck := HitParticles.model_basis(impact, false, 0.0)
	_check(fleck.x.is_equal_approx(impact.y) and fleck.y.is_equal_approx(-impact.z) and fleck.z.is_equal_approx(impact.x), "unoriented models reverse the verified Source-to-glTF axis permutation, through the impact frame made a turn")
	_check(impact.determinant() < 0.0 and puff.determinant() > 0.0 and fleck.determinant() > 0.0 and HitParticles.model_basis(impact, true, 1.25).determinant() > 0.0,
		"the impact frame is a mirror image; the meshes drawn through it are turned, not mirrored")
	_check(HitParticles.normal_offset_world(Vector3(0,0,10), impact).is_equal_approx(normal * 10), "normal-offset +Z displaces puff outward along the surface normal")
	_check(absf(HitParticles.normal_offset_world(Vector3(1,1,0), impact).dot(normal)) < 1e-6, "normal-offset X/Y remain in the surface plane")


func _test_world_ejection() -> void:
	var runner := HitParticles.new()
	var normals := [Vector3.RIGHT, Vector3.BACK, Vector3.UP, Vector3.DOWN, Vector3(0.3,0.4,0.5).normalized()]
	# Exercise the shipped layers, including CP1 dirt and transformed metal
	# noise, rather than only checking a hand-built frame helper.
	for effect: String in ["impact_concrete_child_base", "impact_concrete_child_smoke", "impact_plaster_base", "impact_tile_child_base", "impact_dirt_child_burst", "impact_metal_child_base", "impact_wood_child_base", "ricochet_sparks_dir"]:
		for normal: Vector3 in normals:
			runner.live.clear()
			runner.spawn(effect, Vector3.ZERO, normal, 1000000, normal * 128.0, 30.0, false, true)
			_check(not runner.live.is_empty(), "%s emits on %s" % [effect,normal])
			for p in runner.live:
				if p.name != effect:
					continue
				_check(p.velocity.dot(normal) > 0.0, "%s ejects outward on %s" % [effect,normal])
				var expected_gravity := HitParticles.source_world(p.layer.get("gravity", [0,0,0]))
				_check(p.gravity.is_equal_approx(expected_gravity), "%s gravity stays in world space on %s" % [effect,normal])
				if effect.ends_with("_base"):
					_check(p.velocity.normalized().is_equal_approx(normal), "%s axial dust follows the normal on %s" % [effect,normal])
	# Selecting the world frame must not change the authored blood +X frame.
	for normal: Vector3 in normals:
		runner.live.clear()
		runner.spawn("blood_impact_low_forw_spray", Vector3.ZERO, normal, 1000000, normal * 128.0)
		_check(not runner.live.is_empty(), "body spray still emits on %s" % normal)
		for p in runner.live:
			_check(p.velocity.dot(normal) >= 150.0, "body spray retains its authored +X speed on %s" % normal)


func _test_puff_contact_origin() -> void:
	var runner := HitParticles.new()
	var models := Models.new()
	var quads := Cards.new()
	var at := Vector3(100,64,-300)
	for normal: Vector3 in [Vector3.RIGHT, Vector3.BACK, Vector3.UP, Vector3(0.3,0.4,0.5).normalized()]:
		runner.live.clear()
		models.transforms.clear()
		runner.spawn("impact_fx_hit_darken_model", at, normal, 1000000, at + Vector3(128,0,64), 30.0, false, true)
		_check(not runner.live.is_empty(), "puff emits at the contact on %s" % normal)
		for p in runner.live:
			_check(p.origin.is_equal_approx(at), "NormalOffset does not move the puff ten inches off %s" % normal)
			_check(p.normal.is_equal_approx(normal), "local normal offset orients the puff along %s" % normal)
			# Freeze ejection to separate mesh placement from intended motion.
			p.velocity = Vector3.ZERO
		for eye_offset: Vector3 in [normal * 128.0, Vector3(128,0,64), Vector3(-128,64,32)]:
			models.transforms.clear()
			runner.draw(quads, models, Transform3D(Basis.IDENTITY, at + eye_offset), 1050000)
			_check(not models.transforms.is_empty(), "puff draws from the oblique eye %s" % eye_offset)
			for xform in models.transforms:
				_check(xform.origin.is_equal_approx(at), "changing viewing angle keeps the mesh rooted at the impact")
				_check(xform.basis.y.normalized().is_equal_approx(normal), "puff extrusion remains normal to the surface")
	models.free()
	quads.free()


func _test_hit_mist_origins() -> void:
	var runner := HitParticles.new()
	var points := [Vector3(0,68,0), Vector3(0,45,0), Vector3(14,42,2)]
	for at: Vector3 in points:
		runner.live.clear()
		runner.spawn("blood_impact_med", at, Vector3.RIGHT, 1000000, Vector3(0,60,256))
		var count := 0
		var near_contact := true
		for p in runner.live:
			if p.name.contains("mist"):
				count += 1
				near_contact = near_contact and p.origin.distance_to(at) <= 1.0001
		_check(count > 0 and near_contact, "head/chest/arm mist originates within one unit of its distinct pellet contact %s" % at)


func _test_authored_child_choice() -> void:
	var runner := HitParticles.new()
	var high := 0
	var cheap := 0
	var exclusive := true
	for stamp in range(1000000,1000060):
		runner.live.clear()
		runner.spawn("impact_plaster", Vector3.ZERO, Vector3.RIGHT, stamp, Vector3(0,0,256))
		var names := {}
		for p in runner.live:
			if p.name in ["impact_plaster_high", "impact_plaster_cheap"]:
				names[p.name] = true
		exclusive = exclusive and names.size() == 1
		high += int(names.has("impact_plaster_high"))
		cheap += int(names.has("impact_plaster_cheap"))
	_check(exclusive, "plaster starts exactly one authored group0 child rather than all three entries")
	_check(high > 0 and cheap > high, "duplicated cheap entries retain weight and both variants can be selected")
	var renderer: Dictionary = runner._layers["blood_impact_low_forw_spray"].renderers[0]
	var source: Dictionary = HitEffectTable.LAYERS["blood_impact_low_forw_spray"].renderers[0]
	_check(renderer.has("_hit_quad_key") and not source.has("_hit_quad_key"), "startup caches material keys on private copies without mutating generated data")
	_check_equal(HitQuads.key(renderer), HitQuads.key(source), "cached interned key retains the exact prepared material identity")
	runner.live.clear()
	runner.spawn("blood_impact_low", Vector3.ZERO, Vector3.RIGHT, 1000000, Vector3(0,0,128))
	var prepared := true
	for p in runner.live:
		for r: Dictionary in p.layer.renderers:
			prepared = prepared and r.has("_hit_quad_key")
	_check(prepared, "actually spawned particles carry their private startup renderer keys into draw")


func _test_prepared_evaluation() -> void:
	var runner := HitParticles.new()
	for effect in ["blood_impact_med", "impact_concrete", "impact_metal", "impact_plaster"]:
		runner.spawn(effect, Vector3.ZERO, Vector3.RIGHT, 1000000, Vector3(0,0,256))
	var same := true
	for p in runner.live:
		var plain := p.duplicate()
		plain.erase("drag_k")
		plain.erase("fade_enter")
		plain.erase("fade_leave")
		plain.layer = HitEffectTable.LAYERS[p.name]
		for age in [0.0, 0.075, 0.25]:
			same = same and HitParticles.position(p,age).distance_to(HitParticles.position(plain,age)) < 1e-5
			same = same and absf(HitParticles.fade(p,age)-HitParticles.fade(plain,age)) < 1e-5
			same = same and absf(HitParticles.growth(p.layer,age/p.life)-HitParticles.growth(plain.layer,age/p.life)) < 1e-5
			for key in ["half", "alpha", "roll", "trail", "frame"]:
				same = same and absf(runner.attribute(p,key,age,p[key])-runner.attribute(plain,key,age,plain[key])) < 1e-5
	_check(same, "prepared growth/fade/drag/attribute caches preserve unprepared evaluation across current blood and impact particles")


## Every authored root, on a body and on a wall, drawn into the game's own
## batches at several ages and from several eyes: where the native code is
## built, each draw is made by it and by the script, and the cards held to
## the same (check_suite fails the file on a difference).
func _test_native_draw() -> void:
	if not PlayerBody.native_built():
		print("The native particle draw needs the native library (scripts/build_native.sh, .ps1).")
		return
	var host := Node3D.new()
	root.add_child(host)
	var quads := HitQuads.new()
	host.add_child(quads)
	var models := HitModels.new()
	host.add_child(models)
	for layer: Dictionary in HitEffectTable.LAYERS.values():
		for renderer: Dictionary in layer.get("renderers", []):
			quads.prepare(renderer)
			if String(renderer.get("kind", "")) == "model":
				models.prepare(renderer)
	var runner := HitParticles.new()
	var checked := HitParticles.draws_checked
	var eyes: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(0, 0, 256)),
		Transform3D(Basis.IDENTITY, Vector3(40, 30, 900)).looking_at(Vector3.ZERO),
		Transform3D(Basis.IDENTITY, Vector3(-30, 8, 60)).looking_at(Vector3(10, 0, 0)),
	]
	var cards := 0
	for name: String in HitEffectTable.ROOTS:
		runner.live.clear()
		runner.spawn(name, Vector3.ZERO, Vector3.RIGHT, 1000000, eyes[0].origin, 30.0)
		runner.spawn(name, Vector3(64, 0, 0), Vector3.UP, 1004000, eyes[0].origin, 30.0, false, true)
		for now: int in [1000000, 1016000, 1040000, 1200000, 1600000]:
			for eye in eyes:
				quads.begin()
				models.begin()
				runner.draw(quads, models, eye, now)
				cards += quads.cards()
	_check(HitParticles.draws_checked - checked >= HitEffectTable.ROOTS.size() * 15 and cards > 0,
		"every root, on a body and on a wall, drawn by the native code and by the script alike (%d draws, %d cards)" % [HitParticles.draws_checked - checked, cards])
	host.free()
