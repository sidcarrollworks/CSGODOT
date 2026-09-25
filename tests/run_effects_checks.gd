extends "res://tests/check_suite.gd"

## Checks what is seen of a shot (src/effects/): which guns' rounds draw a
## tracer, CS2's tracers' speeds, lives, lengths and fades, the sniper's
## short tracer, a round's impacts paired with it and drawn on the frame
## after the tick, never in it, the cards the effects are drawn with, the
## sprite sheets read back, where the first-person muzzle is drawn, and the
## muzzle flashes: which each gun and view plays, and their particles.
##
##   godot --headless --path . --script tests/run_effects_checks.gd
##
## Needs nothing extracted but for the last checks, which read the
## extracted effect textures and the guns' models (the muzzles held to
## CS2's own m_vecMuzzlePos), and are left out without them.

const SECOND := 1_000_000


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_which_rounds_draw_a_tracer()
	_test_a_sniper_round_off_target()
	_test_a_trail()
	_test_short_shots_and_ropes()
	_test_the_cards()
	_test_a_sprite_sheet()
	_test_the_drawn_muzzle()
	_test_which_flash_each_gun_plays()
	await _test_a_round_and_its_impacts()
	await _test_a_flash_s_particles()
	if SpriteSheet.named(Tracers.CORE_TEXTURE) != null:
		await _test_with_the_game_files()
		await _test_the_muzzles()
	else:
		print("The effect textures are not extracted (scripts/extract_assets.sh effects): their checks are left out.")
	_finish("effects")


## Every round of a gun with tracers draws one (CS2's client overrides the
## every-third, cl_tracer_frequency_override 1), a silenced gun none, and
## each gun's effect is the one its data names.
func _test_which_rounds_draw_a_tracer() -> void:
	var kinds := {
		"weapon_ak47": &"assrifle", "weapon_glock": &"pistol", "weapon_mp9": &"smg", "weapon_aug": &"assrifle_aug",
		"weapon_m249": &"mach", "weapon_awp": &"rifle", "weapon_ssg08": &"rifle_ssg", "weapon_scar20": &"rifle_scar",
		"weapon_nova": &"shot", "weapon_knife": &"", "weapon_taser": &"",
	}
	var wrong := PackedStringArray()
	for weapon_class: String in kinds:
		if Tracers.kind_of(weapon_class) != kinds[weapon_class]:
			wrong.append("%s: %s" % [weapon_class, Tracers.kind_of(weapon_class)])
	_check(wrong.is_empty(), "each gun's tracer is the effect its m_szTracerParticle names (wrong: %s)" % ", ".join(wrong))
	_check(
		Tracers.draws("weapon_ak47", 0, 0) and Tracers.draws("weapon_ak47", 0, 1) and Tracers.draws("weapon_ak47", 0, 2)
			and Tracers.draws("weapon_mp9", 0, 1) and Tracers.draws("weapon_usp_silencer", 0, 5),
		"every round draws one, the AK-47's and MP9's every-third overridden as CS2's client does"
	)
	_check(
		not Tracers.draws("weapon_m4a1_silencer", 1, 0) and not Tracers.draws("weapon_usp_silencer", 1, 0)
			and not Tracers.draws("weapon_mp5sd", 0, 0) and Tracers.draws("weapon_m4a1_silencer", 0, 0),
		"a silenced round draws none (the M4A1-S and USP-S with the silencer on, the MP5-SD), the M4A1-S's off does"
	)


## sv_sniper_tracer_mode 1: a sniper's round more than 0.085 off draws 200
## units; an accurate one, or a rifle's, the whole way.
func _test_a_sniper_round_off_target() -> void:
	_check(
		is_equal_approx(Tracers.reach("weapon_awp", 0.1, 3000.0), 200.0)
			and is_equal_approx(Tracers.reach("weapon_awp", 0.02, 3000.0), 3000.0)
			and is_equal_approx(Tracers.reach("weapon_ak47", 0.1, 3000.0), 3000.0)
			and is_equal_approx(Tracers.reach("weapon_ssg08", 0.2, 150.0), 150.0),
		"a noscope's tracer stops 200 units out; an accurate sniper round's, or a rifle's, goes the whole way"
	)


## An AK's tracer, as weapon_tracers_assrifle draws it: across 1000 units,
## and across 5000, where it has time to grow to its length.
func _test_a_trail() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var yours := Tracers.Trail.make(&"assrifle", Vector3.ZERO, Vector3(0.0, 0.0, -1000.0), true, rng)
	_check_near(yours.life, 1000.0 / 20500.0, "it flies at 20,500 u/s and is gone as it arrives: %.1f ms across 1000 units" % (yours.life * 1000.0))
	var early := 0.2 * yours.life
	_check(
		yours.length(yours.grow_core, early) <= yours.flown(early) and yours.length(yours.grow_core, early) > 0.7 * yours.flown(early),
		"growing in, its tail keeps near the muzzle and never behind it"
	)
	_check(
		yours.length(yours.grow_core, 0.99 * yours.life) < 1000.0,
		"across 1000 units it never grows to its length: its 0.08 s growing in outlasts its 49 ms"
	)
	var far_yours := Tracers.Trail.make(&"assrifle", Vector3.ZERO, Vector3(0.0, 0.0, -5000.0), true, rng)
	var far_theirs := Tracers.Trail.make(&"assrifle", Vector3.ZERO, Vector3(0.0, 0.0, -5000.0), false, rng)
	var theirs_long := far_theirs.length(far_theirs.grow_core, 0.99 * far_theirs.life)
	_check_near(far_yours.length(far_yours.grow_core, 0.99 * far_yours.life), 1200.0, "yours is 1200 units at its longest (capped)")
	_check(
		theirs_long > 697.0 * 1.0 and theirs_long < 1200.0,
		"anyone else's half as long before the cap, stretching as it flies (%.0f at 5000 units)" % theirs_long
	)
	_check(
		yours.alpha_at(0.1 * yours.life) == 0.0 and is_equal_approx(yours.alpha_at(0.5 * yours.life), yours.alpha)
			and yours.alpha_at(0.975 * yours.life) < yours.alpha and yours.alpha_at(yours.life) == 0.0,
		"it shows from a fifth of its way, full by 30%, fading over the last 5%"
	)
	_check(
		is_equal_approx(yours.half_core, 0.5) and is_equal_approx(yours.half_glow, 0.75),
		"a one-unit core in a 1.5-unit glow"
	)
	var awp_yours := Tracers.Trail.make(&"rifle", Vector3.ZERO, Vector3(0.0, 0.0, -1000.0), true, rng)
	var awp_theirs := Tracers.Trail.make(&"rifle", Vector3.ZERO, Vector3(0.0, 0.0, -1000.0), false, rng)
	_check(
		awp_yours.start.is_equal_approx(Vector3(0.0, 0.0, -20.0)) and is_equal_approx(awp_yours.half_core, 1.0)
			and is_equal_approx(awp_theirs.half_core, 0.5) and is_equal_approx(awp_yours.speed, 30000.0),
		"the AWP's starts 20 units out, at 30,000 u/s, two units wide as yours, one as anyone else's"
	)


func _test_short_shots_and_ropes() -> void:
	var rng := RandomNumberGenerator.new()
	_check(
		Tracers.Trail.make(&"shot", Vector3.ZERO, Vector3(0.0, 0.0, -140.0), false, rng) == null
			and Tracers.Trail.make(&"shot", Vector3.ZERO, Vector3(0.0, 0.0, -400.0), false, rng) != null,
		"a shotgun's pellet draws no tracer under 150 units"
	)
	var pistol := Tracers.Trail.make(&"pistol", Vector3.ZERO, Vector3(0.0, 0.0, -50.0), false, rng)
	_check(pistol != null and is_equal_approx(pistol.life, 50.0 / 18000.0), "a pistol's has no cut: 50 units, 2.8 ms")
	_check_near(Tracers.Rope.life_for(Tracers.ROPES[&"smg"], 1000.0), 0.1025, "an SMG's beam lasts 0.103 s over 1000 units")
	_check_near(Tracers.Rope.life_for(Tracers.ROPES[&"assrifle_aug"], 1000.0), 0.1583, "the AUG's 0.158 s")
	var rope := Tracers.Rope.make(&"smg", Vector3.ZERO, Vector3(0.0, 0.0, -1000.0))
	_check(
		rope.span(0.01).is_equal_approx(Vector2(0.0, 180.0)) and rope.span(0.05).is_equal_approx(Vector2(500.0, 900.0))
			and rope.span(0.08).x > rope.distance,
		"its 400-unit streak slides down the beam at 18,000 u/s and off the end"
	)


func _test_the_cards() -> void:
	var tail := Vector3(0.0, 10.0, 0.0)
	var head := Vector3(0.0, 10.0, -300.0)
	var card := EffectQuads.streak(tail, head, 2.0, Vector3(100.0, 10.0, -150.0))
	_check(
		(card * Vector3(0.0, 0.5, 0.0)).is_equal_approx(head) and (card * Vector3(0.0, -0.5, 0.0)).is_equal_approx(tail)
			and is_equal_approx(card.basis.x.length(), 4.0) and absf(card.basis.z.normalized().x) > 0.99,
		"a streak's card runs tail to head, its top the head, 2 units either side, facing the eye"
	)
	var eye := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 50.0))
	var sprite := EffectQuads.sprite(Vector3.ZERO, 3.0, 0.0, eye)
	_check(
		is_equal_approx(sprite.basis.x.length(), 6.0) and sprite.basis.x.normalized().is_equal_approx(Vector3.RIGHT)
			and sprite.basis.z.is_equal_approx(Vector3.BACK),
		"a sprite's card is 3 units either side, square to the view"
	)

	# A frame's cards reach the batch's MultiMesh whole, in one buffer, past
	# its first room too: each card's transform by rows, colour, rectangle.
	var quads := EffectQuads.new()
	root.add_child(quads)
	var texture := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	quads.begin()
	for i in EffectQuads.FIRST_CAPACITY + 36:
		quads.quad(texture, &"add", false, Transform3D(Basis.IDENTITY, Vector3(i, 2.0 * i, 3.0)),
			Rect2(0.1, 0.2, 0.3, 0.4), Color(1.0, 0.5, 0.25, 0.75))
	quads.finish()
	var multimesh := (quads.get_child(0) as MultiMeshInstance3D).multimesh
	var sent := multimesh.buffer
	var card_70 := sent.slice(70 * EffectQuads.FLOATS, 71 * EffectQuads.FLOATS)
	var expected := PackedFloat32Array([1.0, 0.0, 0.0, 70.0, 0.0, 1.0, 0.0, 140.0, 0.0, 0.0, 1.0, 3.0,
		1.0, 0.5, 0.25, 0.75, 0.1, 0.2, 0.4, 0.6])
	var same := card_70.size() == expected.size()
	for i in mini(card_70.size(), expected.size()):
		same = same and is_equal_approx(card_70[i], expected[i])
	_check(
		quads.cards() == 100 and multimesh.visible_instance_count == 100
			and sent.size() == multimesh.instance_count * EffectQuads.FLOATS and same,
		"a frame's 100 cards go to their batch in one buffer, past its first 64, each where it was put (%s)" % card_70
	)
	quads.free()


## A sheet as scripts/effect_textures.gd writes it: frames by fraction, a
## clamped sequence holding its last, a looping one going round.
func _test_a_sprite_sheet() -> void:
	var sheet := SpriteSheet.new()
	sheet.read({"sequences": [
		{"clamp": true, "frames": [[0.0, 0.0, 0.25, 0.5], [0.25, 0.0, 0.5, 0.5]]},
		{"clamp": false, "frames": [[0.0, 0.5, 0.5, 1.0], [0.5, 0.5, 1.0, 1.0]]},
		{"clamp": true, "frames": [[0.0, 0.0, 0.1, 0.1], [0.1, 0.0, 0.2, 0.1], [0.2, 0.0, 0.3, 0.1]], "times": [1.0, 1.0, 0.0]},
	]})
	_check(
		sheet.frame(0, 0.0) == Rect2(0.0, 0.0, 0.25, 0.5) and sheet.frame(0, 0.75) == Rect2(0.25, 0.0, 0.25, 0.5)
			and sheet.frame(0, 3.0) == Rect2(0.25, 0.0, 0.25, 0.5) and sheet.frame(1, 1.0) == Rect2(0.0, 0.5, 0.5, 0.5)
			and sheet.frame(4, 0.0) == sheet.frame(1, 0.0),
		"a sheet's frame by fraction: a clamped sequence holds its last, a looping one goes round"
	)
	_check(
		sheet.frame(2, 0.49) == Rect2(0.0, 0.0, 0.1, 0.1) and sheet.frame(2, 0.99) == Rect2(0.1, 0.0, 0.1, 0.1)
			and sheet.frame(2, 1.0) == Rect2(0.2, 0.0, 0.1, 0.1),
		"each frame shows for its own display time: one shown for none (the steam's last) is only at the very end"
	)
	var dump := "\n".join([
		"[3/12] materials/particle/fire_gas/fire_gas_batch_b_top.vtex_c",
		"Width        = 4096",
		"Height       = 2048",
		"                 [Sequence 0]:",
		"                   m_bClamp          = True",
		"                     [Sequence 0 Frame 0]:",
		"                       m_flDisplayTime  = 0.000000",
		"                         [0.0.0] uvCropped    = { ( 0.007385, 0.023315 ), ( 0.023132, 0.058228 ) }",
		"                         [0.0.0] uvUncropped  = { ( 0.000061, 0.000122 ), ( 0.045105, 0.090210 ) }",
		"                 [Sequence 1]:",
		"                   m_bClamp          = False",
		"                     [Sequence 1 Frame 0]:",
		"                         [1.0.0] uvCropped    = { ( 0.491394, 0.119507 ), ( 0.491394, 0.119507 ) }",
		"                         [1.0.0] uvUncropped  = { ( 0.468811, 0.074341 ), ( 0.513855, 0.164429 ) }",
	])
	var parsed: Array = (load("res://scripts/effect_textures.gd") as GDScript).call(&"parse_data", dump)
	var sequences: Array = parsed[0]["sequences"] if parsed.size() == 1 else []
	_check(
		parsed.size() == 1 and parsed[0]["path"] == "materials/particle/fire_gas/fire_gas_batch_b_top.vtex"
			and parsed[0]["width"] == 4096 and sequences.size() == 2 and sequences[0]["clamp"] and not sequences[1]["clamp"]
			and (sequences[0]["frames"][0]["uncropped"] as Rect2).is_equal_approx(Rect2(0.000061, 0.000122, 0.045044, 0.090088))
			and not (sequences[1]["frames"][0]["cropped"] as Rect2).has_area()
			and is_equal_approx(float(sequences[0]["frames"][0]["time"]), 0.0) and is_equal_approx(float(sequences[1]["frames"][0]["time"]), 1.0),
		"a texture's data block reads back: its path, size, sequences, each frame's rectangles and display time, a burnt-out frame empty"
	)


## Your tracer starts where the gun is drawn: the view model's narrower
## field of view widens a point's place in the view.
func _test_the_drawn_muzzle() -> void:
	var eye := Transform3D(Basis.IDENTITY, Vector3(0.0, 64.0, 0.0))
	var ahead := Muzzles.as_drawn(eye, Vector3(0.0, 64.0, -37.0))
	var aside := Muzzles.as_drawn(eye, Vector3(4.94, 60.61, -37.42))
	var k := ViewModelProjection.fov_narrowing()
	_check(
		ahead.is_equal_approx(Vector3(0.0, 64.0, -37.0))
			and aside.is_equal_approx(Vector3(4.94 * k, 64.0 - 3.39 * k, -37.42)),
		"a point on the first-person gun is drawn widened by the fov ratio (%.3f), its depth kept" % k
	)
	# A scope narrows the camera's field of view, and the arms' with it: your
	# tracer starts, and the first-person cards are drawn, at the scope's.
	var camera := Camera3D.new()
	camera.fov = ViewModelProjection.vertical_fov(45.0)
	var scoped := ViewModelProjection.narrowing_under(camera)
	camera.free()
	var scoped_aside := Muzzles.as_drawn(eye, Vector3(4.94, 60.61, -37.42), scoped)
	var quads := EffectQuads.new()
	root.add_child(quads)
	var texture := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	quads.begin(k)
	quads.quad(texture, &"add", true, Transform3D.IDENTITY, Rect2(0.0, 0.0, 1.0, 1.0), Color.WHITE)
	quads.finish()
	quads.begin(scoped)
	var drawn_at: Variant = (quads.get_child(0) as GeometryInstance3D).get_instance_shader_parameter(&"view_model_projection")
	quads.free()
	_check(
		is_equal_approx(scoped, ViewModelProjection.fov_narrowing(45.0)) and scoped < k
			and scoped_aside.is_equal_approx(Vector3(4.94 * scoped, 64.0 - 3.39 * scoped, -37.42))
			and drawn_at is Vector2 and is_equal_approx((drawn_at as Vector2).x, scoped),
		"scoped to 45, your tracer starts and the first-person cards are drawn at the scope's narrowing (%.3f, %s)" % [scoped, drawn_at]
	)


## A round's impacts go with it, the first wall ending its tracer and the
## round's end the wallbang streak after it; nothing is drawn until the
## frame after the tick that sent them.
func _test_a_round_and_its_impacts() -> void:
	var game := GameSystems.new()
	var effects := ShotEffects.new()
	root.add_child(effects)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	effects.watch(game, 1)
	# In the tree, with the camera it draws for.
	await process_frame
	game.events.send(&"fire_bullets", {"userid": 2, "weapon": "weapon_ak47", "x": 0.0, "y": 64.0, "z": 0.0, "pitch": 0.0, "yaw": 0.0})
	game.events.send(&"bullet_impact", {"userid": 2, "x": 0.0, "y": 64.0, "z": -600.0})
	game.events.send(&"bullet_impact", {"userid": 3, "x": 50.0, "y": 64.0, "z": -50.0})
	game.events.send(&"bullet_impact", {"userid": 2, "x": 0.0, "y": 64.0, "z": -900.0})
	_check(effects._pending.is_empty(), "nothing is taken while the tick is running")
	game.events.flush()
	var pending: Array = effects._pending.duplicate()
	_check(
		pending.size() == 1 and (pending[0]["impacts"] as Array) == [Vector3(0.0, 64.0, -600.0), Vector3(0.0, 64.0, -900.0)]
			and effects._trails.is_empty(),
		"the round's own impacts go with it, another's not, and it waits for the frame"
	)
	# The frame, run here: waiting for one lets the clock run past a
	# tracer that lives 29 ms.
	effects._process(0.0)
	var kinds := effects._trails.map(func(trail: Tracers.Trail) -> StringName: return trail.kind)
	var own := effects._trails.filter(func(trail: Tracers.Trail) -> bool: return trail.kind == &"assrifle")
	_check(
		kinds.has(&"assrifle") and kinds.has(&"wallbang") and not own.is_empty()
			and (own[0] as Tracers.Trail).end.is_equal_approx(Vector3(0.0, 64.0, -600.0)),
		"drawn on the frame: its tracer to the wall, and the fainter one through it (%s)" % [kinds]
	)
	# Fired into nothing: the tracer goes as far as the gun reaches.
	game.events.send(&"fire_bullets", {"userid": 2, "weapon": "weapon_ak47", "x": 0.0, "y": 64.0, "z": 0.0, "pitch": 0.0, "yaw": 0.0})
	game.events.flush()
	effects._trails.clear()
	effects._process(0.0)
	var into_nothing := effects._trails.filter(func(trail: Tracers.Trail) -> bool: return trail.kind == &"assrifle")
	_check(
		not into_nothing.is_empty() and is_equal_approx((into_nothing[0] as Tracers.Trail).end.z, -WeaponVData.number("weapon_ak47", "m_flRange")),
		"a round that meets nothing draws its tracer to the gun's range (%s)" % [into_nothing.map(func(t: Tracers.Trail) -> Vector3: return t.end)]
	)
	# A shotgun's pellets are a round each: a tracer to each one's own end,
	# none run on from one pellet's end to another's.
	for pellet in 3:
		game.events.send(&"fire_bullets", {"userid": 2, "weapon": "weapon_nova", "x": 0.0, "y": 64.0, "z": 0.0, "yaw": pellet * 2.0, "pellet": pellet})
		game.events.send(&"bullet_impact", {"userid": 2, "x": -pellet * 20.0, "y": 64.0, "z": -600.0})
	game.events.flush()
	effects._trails.clear()
	effects._process(0.0)
	var ends := effects._trails.map(func(trail: Tracers.Trail) -> String: return "%s %.0f" % [trail.kind, trail.end.x])
	_check(ends == ["shot 0", "shot -20", "shot -40"], "a shotgun's pellets draw a tracer each, to its own end (%s)" % [ends])
	effects.queue_free()
	camera.queue_free()
	await process_frame


## With the extracted textures: the sheets read, and the trails' looks baked.
func _test_with_the_game_files() -> void:
	var fire := SpriteSheet.named("materials/particle/fire_gas/fire_gas_batch_b_top.vtex")
	_check(
		fire != null and fire.texture != null
			and fire.sequences.map(func(frames: Array) -> int: return frames.size()) == [34, 35, 34, 34],
		"the flames' sheet is back together, its four sequences 34, 35, 34 and 34 frames, as the game has it"
	)
	var effects := ShotEffects.new()
	root.add_child(effects)
	_check(
		effects._core_texture != null and effects._glow_texture != null,
		"the trails' core and glow are baked from CS2's spark and sparks textures"
	)
	var core := effects._core_texture.get_image() if effects._core_texture != null else null
	if core != null:
		var head := core.get_pixel(8, 4)
		var tail := core.get_pixel(8, 60)
		_check(head.a > tail.a and head.r > 0.8, "the core is brightest at its head, fading to its tail (%s, %s)" % [head, tail])
	effects.queue_free()
	await process_frame


## Every gun's flash, both views, is in the table, every layer it draws is
## too, and every texture a layer draws with is one the extraction fetches.
func _test_which_flash_each_gun_plays() -> void:
	var missing := PackedStringArray()
	for weapon_class: String in FlashTable.GUNS:
		var gun: Dictionary = FlashTable.GUNS[weapon_class]
		for key: String in gun:
			if key.begins_with("fp") or key.begins_with("tp"):
				if not FlashTable.FLASHES.has(gun[key]):
					missing.append("%s %s" % [weapon_class, key])
	var guns := 0
	for weapon_class: String in WeaponVData.classes():
		if Tracers.kind_of(weapon_class) != &"":
			guns += 1
			if not FlashTable.GUNS.has(weapon_class):
				missing.append(weapon_class)
	_check(missing.is_empty() and guns >= 33, "every gun (%d) has a flash in each view, and each is in the table (missing: %s)" % [guns, ", ".join(missing)])

	var layers := PackedStringArray()
	var kinds := PackedStringArray()
	var textures := PackedStringArray()
	var fetched := _extracted_textures()
	for key: String in FlashTable.FLASHES:
		var entry: Dictionary = FlashTable.FLASHES[key]
		for list: String in ["always", "pick1", "pick2"]:
			for item: Variant in entry.get(list, []):
				for name in _names_in(item):
					if not FlashTable.LAYERS.has(name):
						layers.append("%s: %s" % [key, name])
	for name: String in FlashTable.LAYERS:
		var layer: Dictionary = FlashTable.LAYERS[name]
		if not (String(layer.get("kind", "")) in ["sprite", "trail", "spark", "smoke", "light"]):
			kinds.append(name)
		if layer.get("kind", "") != "light":
			var path := MuzzleFlashes.texture_path(String(layer.get("tex", "")))
			if path.is_empty() or not fetched.has(path):
				textures.append("%s (%s)" % [name, layer.get("tex", "")])
	_check(layers.is_empty(), "every layer a flash names is in the table (not: %s)" % ", ".join(layers))
	_check(kinds.is_empty(), "every layer is a sprite, trail, spark, smoke or light (not: %s)" % ", ".join(kinds))
	_check(textures.is_empty(), "every texture a layer draws with is one scripts/extract_assets.sh effects fetches (not: %s)" % ", ".join(textures))

	_check(
		MuzzleFlashes.flash_for("weapon_ak47", 0, false, true) == "uweapon_muzflsh_ak47_fps/fp/game"
			and MuzzleFlashes.flash_for("weapon_ak47", 0, false, false) == "uweapon_muzflsh_ak47/tp/game"
			and MuzzleFlashes.flash_for("weapon_m4a1_silencer", 1, false, true) == "uweapon_muzsilenced_rif_fps/fp/fps_view"
			and MuzzleFlashes.flash_for("weapon_m4a1_silencer", 0, false, false) == "uweapon_muzflsh_ak47/tp/game"
			and MuzzleFlashes.flash_for("weapon_elite", 0, true, false) == "uweapon_muzzleflash_pist/tp/alternate"
			and MuzzleFlashes.flash_for("weapon_knife", 0, false, true) == "",
		"a shot plays its gun's flash for the view: the AK's own, the silenced M4A1-S's, the Berettas' left pistol's, the knife none"
	)
	var rng := RandomNumberGenerator.new()
	var sizes := {}
	for i in 200:
		rng.seed = i
		var picked := MuzzleFlashes.layers_of(FlashTable.FLASHES["uweapon_muzflsh_aug/tp/game"], rng)
		sizes[picked.size()] = true
	_check(sizes.keys() == [4], "a flash with no picks draws every layer, every time (the AUG's four)")
	var drawn := {}
	for i in 400:
		rng.seed = i
		for layer: Dictionary in MuzzleFlashes.layers_of(FlashTable.FLASHES["uweapon_muzflsh_ak47/tp/game"], rng):
			drawn[layer["name"]] = true
	_check(
		drawn.has("smoke_rifle") and drawn.has("light_rifle") and drawn.has("rifle_fire") and drawn.has("rifle_fire_alt")
			and drawn.has("beam3") and drawn.has("comp_side") and drawn.has("spark_rifle"),
		"the AK's flash picks among its flames, the beam, the compensator and the sparks shot to shot (%s)" % [drawn.keys()]
	)


## A flash's particles, as the table has them: the AK's flame down the
## barrel from 3 to 20 units, riding it, gone in 0.05 s; its sparks thrown
## forward, left where they were made.
func _test_a_flash_s_particles() -> void:
	var flashes := MuzzleFlashes.new()
	root.add_child(flashes)
	flashes.quads = EffectQuads.new()
	flashes.add_child(flashes.quads)
	await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# A muzzle pointing down -Z (the barrel), its left -X, its top +Y.
	var muzzle := Transform3D(Basis(Vector3(0.0, 0.0, -1.0), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)), Vector3(0.0, 60.0, 0.0))
	var flash := MuzzleFlashes.Flash.new()
	flash.muzzle = muzzle
	flashes._spawn(flash, (FlashTable.LAYERS["rifle_fire"] as Dictionary).duplicate(), rng)
	var along := flash.particles.map(func(p: MuzzleFlashes.Particle) -> float: return p.position.x)
	_check(
		flash.particles.size() == 6 and along.min() >= 3.0 - 0.001 and along.max() <= 20.0 + 0.001
			and flash.particles.all(func(p: MuzzleFlashes.Particle) -> bool: return p.local and is_equal_approx(p.life, 0.05)),
		"the AK's flame: six sprites 3 to 20 units down the barrel, riding it, for 0.05 s (%s)" % [along]
	)
	_check(
		not flash.particles.is_empty() and flashes._step(flash, flash.particles[0], 0.03) and not flashes._step(flash, flash.particles[0], 0.06),
		"and gone by 0.06 s"
	)
	var sparks := MuzzleFlashes.Flash.new()
	sparks.muzzle = muzzle
	flashes._spawn(sparks, (FlashTable.LAYERS["spark_rifle"] as Dictionary).duplicate(), rng)
	var spark: MuzzleFlashes.Particle = sparks.particles[0] if not sparks.particles.is_empty() else null
	var went := Vector3.ZERO
	if spark != null:
		var from := spark.position
		spark.head_start = 0.0
		spark.age = 0.0
		spark.life = 1.0
		spark.dies_at = INF
		flashes._step(sparks, spark, 0.02)
		went = spark.position - from
	_check(
		sparks.particles.size() >= 4 and sparks.particles.size() <= 12 and spark != null and not spark.local
			and went.dot(Vector3(0.0, 0.0, -1.0)) > 2.0,
		"the sparks: 4 to 12, left in the world, thrown down the barrel (%d, %s in 0.02 s)" % [sparks.particles.size(), went]
	)
	flashes.queue_free()
	await process_frame


## The muzzles in the guns as drawn: each gun's view model posed at its
## idle's first frame puts the attachment where CS2's own m_vecMuzzlePos0
## (and 1) say, from the eye; and a body's gun has it at the barrel's end.
func _test_the_muzzles() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	var off := PackedStringArray()
	var checked := 0
	for weapon_class: String in Muzzles.POINTS:
		# The R8's own muzzle is 0.2 in off its data, and the live bone is
		# the one trusted; the Zeus is not built as a gun.
		if weapon_class in ["weapon_revolver", "weapon_taser"]:
			continue
		var data := WeaponLibrary.build(weapon_class)
		var view := ViewModel.new()
		camera.add_child(view)
		if not view.setup("T", data.model_path, data.clip_set):
			view.free()
			continue
		view.play(view.idle)
		view.animation_player.seek(0.0, true)
		view.animation_player.pause()
		await process_frame
		await process_frame
		for second in [false, true]:
			if second and not Muzzles.has_second(weapon_class):
				continue
			var at: Variant = Muzzles.in_view(view, weapon_class, second)
			var field := "m_vecMuzzlePos1" if second else "m_vecMuzzlePos0"
			var parts := String((WeaponVData.classes()[weapon_class] as Dictionary).get(field, "")).split("|")
			var want := Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float()) if parts.size() == 3 else Vector3.INF
			var local := camera.global_transform.affine_inverse() * (at as Transform3D).origin if at != null else Vector3.INF
			# Source's eye space: +x ahead, +y left, +z up.
			var eye := Vector3(-local.z, -local.x, local.y)
			checked += 1
			if not (eye.distance_to(want) <= 0.01):
				off.append("%s%s %s vs %s" % [weapon_class, " 2" if second else "", eye, want])
		view.free()
	_check(off.is_empty() and checked >= 34, "every gun's muzzle (%d) sits where CS2's m_vecMuzzlePos puts it from the eye, at idle (off: %s)" % [checked, "; ".join(off)])

	var body := PlayerModel.new()
	root.add_child(body)
	var ak := WeaponLibrary.ak47()
	if body.setup("T", ak.model_path, ak.world_clip_set) and body.held_weapon != null:
		for i in 4:
			await process_frame
		var at: Variant = Muzzles.in_hand(body, "weapon_ak47")
		var tip := (at as Transform3D).origin if at != null else Vector3.INF
		_check(
			at != null and absf(tip.y - 59.5) < 3.0 and tip.z < -30.0
				and (at as Transform3D).basis.x.normalized().dot(Vector3.FORWARD) > 0.95,
			"a body's AK has its muzzle at the barrel's end, 60 up and over 30 ahead, pointing where it faces (%s)" % tip
		)
	body.free()
	camera.free()


## The texture paths scripts/extract_assets.sh's effects step fetches.
static func _extracted_textures() -> PackedStringArray:
	var script := FileAccess.get_file_as_string("res://scripts/extract_assets.sh")
	var found := RegEx.create_from_string("EFFECT_TEXTURES=\"([^\"]*)\"").search(script)
	var out := PackedStringArray()
	if found != null:
		for path in found.get_string(1).split(","):
			out.append(path.trim_suffix("_c"))
	return out


static func _names_in(item: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if item is Dictionary and (item as Dictionary).has("group"):
		for inner: Variant in item["group"]:
			out.append_array(_names_in(inner))
	elif item is Array and not (item as Array).is_empty():
		out.append(String(item[0]))
	elif (item is String or item is StringName) and not String(item).is_empty():
		out.append(String(item))
	return out
