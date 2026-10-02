extends "res://tests/check_suite.gd"

## Checks what is heard of the grenades (playtest issue 19): which of CS2's
## sound events each grenade event calls for (GrenadeSounds.cues_for), their
## levels by distance straight from the table, a bottle that lights a fire
## against one that fizzles, the decoy's gun, the flash's ring and muffle by
## how long the blind lasts (FlashMuffle), the ring bypassing the muffle, and
## the burn (HitSounds.burn_event). Then a view watching a game: played on
## the frame after the tick hands the events out, the bottle's loop following
## it until it breaks, a fire's loop until it ends, an ignite per new flame,
## nothing read from the disk as it plays, and silence without the files.
##
##   godot --headless --path . --script tests/run_grenade_sound_checks.gd
##
## Needs nothing extracted: headless Godot hears nothing, so the checks are
## on which events start, where, at what level and on which bus. Without the
## files a voice still starts and keeps its rules (SoundEvents.silent_length).

const TABLE_PATH := "res://reference/sounds/sound_events.json"


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_the_events_exist()
	_test_the_cues()
	_test_the_levels()
	_test_the_flash()
	_test_the_burn()
	await _test_the_muffle_on_the_buses()
	await _test_a_game_heard()
	await _test_a_burn_heard()
	_finish("grenade-sounds")


func _test_the_events_exist() -> void:
	for name in GrenadeSounds.all_events():
		_check(SoundEvents.has_event(name), "%s is one of CS2's events" % name)
	for name in [HitSounds.BURN_EVENT, HitSounds.BURN_KEVLAR_EVENT]:
		_check(SoundEvents.has_event(name), "%s is one of CS2's events" % name)
	# Every gun a decoy can imitate has its shot: each class in the weapon
	# data that is neither a grenade, the knife, the bomb nor the Zeus.
	var guns := {}
	var file := FileAccess.open("res://reference/weapons/vdata.csv", FileAccess.READ)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 0 and row[0].begins_with("weapon_"):
			guns[row[0]] = true
	var missing: Array[String] = []
	for gun: String in guns:
		if GrenadeRules.is_grenade(gun) or gun in ["weapon_knife", "weapon_c4", "weapon_taser"]:
			continue
		if not GrenadeSounds.DECOY_SHOTS.has(gun):
			missing.append(gun)
	_check(missing.is_empty(), "every gun a decoy can sound like has its shot (%s missing)" % [missing])
	var ak := SoundEvents.find("Weapon_AK47.Single")
	_check(ak != null and "Weapon_AK47.SingleDistant" in ak.children, "a gun's shot brings its distant layer with it")


func _test_the_cues() -> void:
	var he := GrenadeRules.HE
	_check_equal(Array(GrenadeSounds.cues_for(&"grenade_thrown", {"userid": 2, "weapon": he})), ["HEGrenade.Throw"], "an HE's throw")
	_check_equal(Array(GrenadeSounds.cues_for(&"grenade_thrown", {"userid": 2, "weapon": GrenadeRules.FLASHBANG})), ["Flashbang.Throw"], "a flash's")
	_check_equal(Array(GrenadeSounds.cues_for(&"grenade_thrown", {"userid": 2, "weapon": GrenadeRules.INCENDIARY})), ["IncGrenade.Throw"], "an incendiary's")
	_check(SoundEvents.find("HEGrenade.Throw").children.has("Grenade.Throw.Gear"), "a throw brings the gear's rustle")
	for weapon_class: String in GrenadeSounds.BOUNCES:
		_check_equal(Array(GrenadeSounds.cues_for(&"grenade_bounce", {"userid": 2}, {"weapon_class": weapon_class})),
			[GrenadeSounds.BOUNCES[weapon_class]], "a bounce of a %s: its own" % weapon_class)
	_check(GrenadeSounds.cues_for(&"grenade_bounce", {"userid": 2}, {"weapon_class": GrenadeRules.DECOY}).is_empty(),
		"a decoy's bounce: none, as in CS2's files")
	_check(SoundEvents.find("SmokeGrenade.Bounce").children.has("SmokeGrenade.Bounce_Can"), "a smoke's bounce brings the can")
	_check_equal(Array(GrenadeSounds.cues_for(&"hegrenade_detonate", {})), ["BaseGrenade.Explode"], "an HE going off")
	_check(SoundEvents.find("BaseGrenade.Explode").children.has("BaseGrenade.ExplodeDistant"), "with its distant layer")
	_check_equal(Array(GrenadeSounds.cues_for(&"flashbang_detonate", {})), ["Flashbang.Explode"], "a flash going off")
	_check(SoundEvents.find("Flashbang.Explode").children.has("Flashbang.ExplodeDistant"), "with its distant layer")
	_check_equal(Array(GrenadeSounds.cues_for(&"smokegrenade_detonate", {})), ["BaseSmokeEffect.Sound"], "a smoke popping")
	_check(SoundEvents.find("BaseSmokeEffect.Sound").children.has("BaseSmokeEffect.SoundDistant"), "with its distant layer")
	_check_equal(Array(GrenadeSounds.cues_for(&"smokegrenade_expired", {})), ["SmokeGrenade.Clear"], "a smoke clearing")
	_check(GrenadeSounds.cues_for(&"decoy_detonate", {}).is_empty(), "a decoy's pop: none of its own in CS2's files")

	var molotov := GrenadeRules.MOLOTOV
	var incendiary := GrenadeRules.INCENDIARY
	_check_equal(Array(GrenadeSounds.cues_for(&"molotov_detonate", {}, {"weapon_class": molotov, "lit": true})), ["Molotov.Start"], "a molotov that lights")
	_check(SoundEvents.find("Molotov.Start").children.has("Molotov.Smash") and SoundEvents.find("Molotov.Start").children.has("Molotov.StartDistant"),
		"with the bottle's smash and the distant layer")
	_check_equal(Array(GrenadeSounds.cues_for(&"molotov_detonate", {}, {"weapon_class": molotov, "lit": false})), ["Molotov.StartFailed"], "one that fizzles")
	_check_equal(Array(GrenadeSounds.cues_for(&"molotov_detonate", {}, {"weapon_class": incendiary, "lit": true})), ["IncGrenade.Start"], "an incendiary that lights")
	_check(SoundEvents.find("IncGrenade.Start").children.has("IncGrenade.Pop"), "with its pop")
	_check_equal(Array(GrenadeSounds.cues_for(&"molotov_detonate", {}, {"weapon_class": incendiary, "lit": false})), ["IncGrenade.StartFailed"], "one that fizzles")
	_check(SoundEvents.find("IncGrenade.StartFailed").children.has("IncGrenade.Distant"), "keeping the distant layer")
	_check_equal(Array(GrenadeSounds.cues_for(&"molotov_detonate", {})), ["Molotov.StartFailed"], "a bottle nobody knows of: a molotov's, unlit")
	_check_equal(Array(GrenadeSounds.cues_for(&"inferno_startburn", {})), ["Inferno.Loop"], "a fire starting: its loop")
	_check_equal(Array(GrenadeSounds.cues_for(&"inferno_expire", {})), ["Inferno.FadeOut"], "burning out: the fade")
	_check_equal(Array(GrenadeSounds.cues_for(&"inferno_extinguish", {})), ["Molotov.Extinguish"], "put out by smoke: the hiss")

	_check_equal(Array(GrenadeSounds.cues_for(&"decoy_firing", {}, {"decoy_weapon": "weapon_ak47"})), ["Weapon_AK47.Single"], "a decoy thrown by an AK's owner fires AK shots")
	_check_equal(Array(GrenadeSounds.cues_for(&"decoy_firing", {}, {"decoy_weapon": "weapon_m4a1_silencer"})), ["Weapon_M4A1.Silenced"], "an M4A1-S owner's, silenced ones")
	_check(GrenadeSounds.cues_for(&"decoy_firing", {}, {"decoy_weapon": ""}).is_empty(), "a decoy with no gun to imitate is silent")

	_check_equal(Array(GrenadeSounds.cues_for(&"player_blind", {"userid": 4, "blind_duration": 4.87}, {}, 4)), ["Flashbang.Ring.Long"], "your own full blind: the long ring")
	_check(GrenadeSounds.cues_for(&"player_blind", {"userid": 5, "blind_duration": 4.87}, {}, 4).is_empty(), "someone else's: nothing in your ears")


## Levels by distance, from each event's own curve in the table.
func _test_the_levels() -> void:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))["events"]
	# [event, distance, its share by the table's own points]
	for row: Array in [
		["BaseGrenade.Explode", 231.0], ["BaseGrenade.Explode", 779.0], ["BaseGrenade.Explode", 2700.0],
		["BaseGrenade.ExplodeDistant", 944.0], ["BaseGrenade.ExplodeDistant", 2800.0],
		["Flashbang.Explode", 84.0], ["Flashbang.Explode", 2740.0],
		["HEGrenade.Bounce", 28.0], ["HEGrenade.Bounce", 306.0], ["HEGrenade.Bounce", 1700.0],
		["Molotov.Start", 977.0], ["IncGrenade.Start", 742.0], ["Inferno.Loop", 1200.0],
	]:
		var name: String = row[0]
		var distance: float = row[1]
		var fields: Dictionary = table[name]
		var share := SoundEvent.curve_at(fields["distance_volume_mapping_curve"], distance)
		var volume := float(fields.get("volume", 1.0))
		_check_near(SoundEvents.find(name).gain(distance), share * volume, "%s at %d units: %.3f" % [name, distance, share * volume])
	_check_near(SoundEvents.find("BaseGrenade.Explode").gain(2700.0), 0.0, "an HE is silent near by 2700 units")
	_check(SoundEvents.find("BaseGrenade.ExplodeDistant").gain(2700.0) > 0.4, "while its distant layer carries on")
	_check_near(SoundEvents.find("HEGrenade.Bounce").gain(1700.0), 0.0, "a bounce is silent at 1700")
	_check_near(SoundEvents.find("Flashbang.Ring.Long").gain(0.0, 4.2), 0.0, "the long ring is over by 4.18 s")
	_check(SoundEvents.find("Molotov.Throw.Loop").gain(100.0, 0.0) == 0.0 and SoundEvents.find("Molotov.Throw.Loop").gain(100.0, 0.5) > 0.6,
		"the bottle's loop fades in over its first half second")


func _test_the_flash() -> void:
	_check_near(FlashMuffle.ring_length("Short"), 2.0, "the short ring lasts 2 s")
	_check_near(FlashMuffle.ring_length("Medium"), 3.0, "the medium 3 s")
	_check_near(FlashMuffle.ring_length("Long"), 4.182857, "the long 4.18 s")
	_check_equal(FlashMuffle.ring_for(0.5), "Short", "a glance: the short ring")
	_check_equal(FlashMuffle.ring_for(2.4), "Short", "2.4 s: still short, nearest 2")
	_check_equal(FlashMuffle.ring_for(2.6), "Medium", "2.6 s: medium")
	_check_equal(FlashMuffle.ring_for(3.5), "Medium", "3.5 s: medium")
	_check_equal(FlashMuffle.ring_for(GrenadeRules.FLASH_MAX_SECONDS), "Long", "a full flash: the long ring")
	_check_near(FlashMuffle.amount_at("Long", 0.0), 1.0, "the long muffle is full at once")
	_check_near(FlashMuffle.amount_at("Long", 4.1), 1.0, "and until its fade, 4.1 s in")
	_check_near(FlashMuffle.amount_at("Long", 4.8), 0.5, "halfway down 0.7 s into its 1.4 s fade")
	_check_near(FlashMuffle.amount_at("Long", 5.5), 0.0, "and gone at 5.5 s")
	_check_near(FlashMuffle.amount_at("Short", 0.6), 0.5, "the short one halfway out at 0.6 s of 0.7")
	_check_near(FlashMuffle.amount_at("", 0.1), 0.0, "no flash, no muffle")
	for name: String in FlashMuffle.RINGS.values():
		_check(SoundEvents.find(name).dsp_bypass > 0.0, "%s bypasses the DSP (dsp_bypass)" % name)


func _test_the_burn() -> void:
	_check_equal(HitSounds.burn_event({"weapon": GrenadeRules.MOLOTOV, "armor": 0}), HitSounds.BURN_EVENT, "a molotov's fire burns")
	_check_equal(HitSounds.burn_event({"weapon": GrenadeRules.INCENDIARY, "armor": 100}), HitSounds.BURN_KEVLAR_EVENT, "through armour: the kevlar burn")
	_check_equal(HitSounds.burn_event({"weapon": "weapon_ak47", "armor": 0}), "", "a bullet is no burn")
	_check(HitSounds.for_hit({"weapon": GrenadeRules.MOLOTOV, "userid": 2, "attacker": 3}, 4).is_empty(), "and fire plays no bullet hit")


## The muffle on the buses: the low-pass and dip on each bus with DSP, as
## far as its mixgroup's dsp, none on the music, and the ring's twin bus
## left alone.
func _test_the_muffle_on_the_buses() -> void:
	var buses := FlashMuffle.muffled_buses()
	_check(buses.has(&"Explosions") and is_equal_approx(float(buses[&"Explosions"]), 1.0), "the explosions take the muffle in full")
	_check(buses.has(&"UI") and is_equal_approx(float(buses[&"UI"]), 0.1), "the UI a tenth, its dsp")
	_check(not buses.has(&"Music") and not buses.has(&"WeaponsDistant"), "the music and the distant guns none (dsp 0)")
	_check(buses.has(FlashMuffle.UNMIXED_BUS), "and the older views' bus in full")
	var ring_bus := SoundEvents.bypass_bus(&"Explosions")
	_check(AudioServer.get_bus_index(ring_bus) > 0, "the ring's bus is made, %s" % ring_bus)
	var explosions := AudioServer.get_bus_index(&"Explosions")
	_check_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(ring_bus)), AudioServer.get_bus_volume_db(explosions), "at the explosions' level")
	var before := AudioServer.get_bus_effect_count(explosions)
	var muffle := FlashMuffle.new()
	muffle.flash("Long", 0.0)
	muffle.apply(1.0)
	_check_equal(AudioServer.get_bus_effect_count(explosions), before + 2, "a flash puts a low-pass and a dip on the explosions")
	var low_pass := AudioServer.get_bus_effect(explosions, before) as AudioEffectLowPassFilter
	var dip := AudioServer.get_bus_effect(explosions, before + 1) as AudioEffectAmplify
	_check(low_pass != null and is_equal_approx(low_pass.cutoff_hz, FlashMuffle.CUTOFF_HZ) and AudioServer.is_bus_effect_enabled(explosions, before),
		"the low-pass at its full, %d Hz" % FlashMuffle.CUTOFF_HZ)
	_check(dip != null and is_equal_approx(dip.volume_db, FlashMuffle.DIP_DB), "the dip at %.0f dB" % FlashMuffle.DIP_DB)
	_check_equal(AudioServer.get_bus_effect_count(AudioServer.get_bus_index(ring_bus)), 0, "and nothing on the ring's bus")
	var ui := AudioServer.get_bus_index(&"UI")
	var ui_dip := AudioServer.get_bus_effect(ui, AudioServer.get_bus_effect_count(ui) - 1) as AudioEffectAmplify
	_check(ui_dip != null and is_equal_approx(ui_dip.volume_db, FlashMuffle.DIP_DB * 0.1), "the UI dips a tenth as far")
	muffle.apply(6.0)
	_check(not AudioServer.is_bus_effect_enabled(explosions, before) and is_equal_approx(low_pass.cutoff_hz, FlashMuffle.OPEN_HZ),
		"once it is over, the low-pass is open and off")
	muffle.remove()
	_check_equal(AudioServer.get_bus_effect_count(explosions), before, "and taken off, the bus is as it was")
	await process_frame


func _add_player(game: GameSystems, team: String, at: Vector3) -> int:
	var player := PlayerSim.new()
	player.team = team
	root.add_child(player)
	player.global_position = at
	return game.add_player(player)


func _voices(sounds: GrenadeSounds, event_name: String) -> Array:
	return sounds.events.voices().filter(func(v: Dictionary) -> bool: return v["event"] == event_name and not v["stopped"])


func _send(game: GameSystems, name: StringName, fields: Dictionary) -> void:
	game.events.send(name, fields)
	game.events.flush()


func _grenade(game: GameSystems, weapon_class: String, owner: int, at: Vector3) -> GrenadeEntity:
	var grenade := GrenadeEntity.new()
	grenade.weapon_class = weapon_class
	grenade.owner_id = owner
	grenade.position = at
	grenade.previous_position = at
	game.entities.spawn(grenade)
	return grenade


func _gone(game: GameSystems, entity: SimEntity) -> void:
	entity.remove()
	game.entities._let_go()


func _test_a_game_heard() -> void:
	# Exercise missing-file behavior even on a developer's extracted install.
	var availability := SoundBank._available
	SoundBank._available = 0
	var game := GameSystems.new()
	var me := _add_player(game, "CT", Vector3.ZERO)
	var them := _add_player(game, "T", Vector3(500.0, 0.0, 0.0))
	var sounds := GrenadeSounds.new()
	root.add_child(sounds)
	sounds.events.silent_length = 100.0
	sounds.watch(game, me)
	var loads := SoundEvents.late_loads
	var effects_before := AudioServer.get_bus_effect_count(AudioServer.get_bus_index(&"Explosions"))

	# A throw of theirs, from where they stand.
	_send(game, &"grenade_thrown", {"userid": them, "weapon": GrenadeRules.HE})
	_check(sounds.events.voices().is_empty() and sounds.pending().size() == 1, "handed out at the tick's end, a throw is noted, not played")
	sounds._process(0.0)
	var throws := _voices(sounds, "HEGrenade.Throw")
	_check(throws.size() == 1 and (throws[0]["position"] as Vector3).is_equal_approx(Vector3(500.0, 0.0, 0.0)), "on the next frame, from the thrower")
	_check(_voices(sounds, "Grenade.Throw.Gear").size() == 1, "with the gear's rustle")
	_send(game, &"grenade_thrown", {"userid": me, "weapon": GrenadeRules.SMOKE})
	_check(sounds.pending()[0][3] == null, "your own throw plays in your ears, not placed")
	sounds._process(0.0)

	# Their HE bounces: its own bounce, matched to it.
	var he := _grenade(game, GrenadeRules.HE, them, Vector3(400.0, 0.0, 0.0))
	var smoke := _grenade(game, GrenadeRules.SMOKE, them, Vector3(-400.0, 0.0, 0.0))
	_send(game, &"grenade_bounce", {"userid": them, "x": 398.0, "y": 0.0, "z": 0.0})
	sounds._process(0.0)
	var bounces := _voices(sounds, "HEGrenade.Bounce")
	_check(bounces.size() == 1 and int(bounces[0]["source"]) == he.id, "a bounce near their HE is the HE's")
	_check(_voices(sounds, "SmokeGrenade.Bounce").is_empty(), "not their smoke's, further off")
	_send(game, &"grenade_bounce", {"userid": them, "x": 398.0, "y": 0.0, "z": 0.0})
	sounds._process(0.0)
	_check_equal(_voices(sounds, "HEGrenade.Bounce").size(), 1, "a second bounce within 0.1 s is held off (the event's block)")
	sounds.events.advance(0.2)
	_send(game, &"hegrenade_detonate", {"userid": them, "entityid": he.id, "x": 400.0, "y": 0.0, "z": 0.0})
	_gone(game, he)
	sounds._process(0.0)
	_check(_voices(sounds, "BaseGrenade.Explode").size() == 1 and _voices(sounds, "BaseGrenade.ExplodeDistant").size() == 1,
		"it goes off, near and distant")
	_gone(game, smoke)

	# A molotov in flight: its loop follows it, and stops as it breaks,
	# unlit in the air.
	var molotov := _grenade(game, GrenadeRules.MOLOTOV, them, Vector3(0.0, 100.0, 0.0))
	sounds._process(0.0)
	var loop := _voices(sounds, "Molotov.Throw.Loop")
	_check(loop.size() == 1 and _voices(sounds, "Molotov.ThrowFire").size() == 1, "a molotov in flight: its loop, with the flare")
	molotov.previous_position = molotov.position
	molotov.position = Vector3(0.0, 100.0, 300.0)
	sounds._process(0.0)
	sounds.events.advance(0.0)
	var moved := _voices(sounds, "Molotov.Throw.Loop")
	_check(moved.size() == 1 and (moved[0]["position"] as Vector3).z > 0.0, "and follows it as it flies (%s)" % [moved.map(func(v): return v["position"])])
	sounds.events.advance(7.5)
	_check(_voices(sounds, "Molotov.Throw.Loop").size() == 1, "looping, 7.5 s on (it stops itself at 8 s, its self_destruct_time)")
	_send(game, &"molotov_detonate", {"userid": them, "x": 0.0, "y": 100.0, "z": 300.0})
	_gone(game, molotov)
	sounds._process(0.0)
	_check(_voices(sounds, "Molotov.Throw.Loop").is_empty(), "the loop stops as it breaks")
	_check(_voices(sounds, "Molotov.StartFailed").size() == 1 and _voices(sounds, "Molotov.Start").is_empty(), "no fire: it fizzles")
	sounds.events.advance(1.1)

	# An incendiary that lights: read off the fire it started.
	var ground := Vector3(200.0, 0.0, 200.0)
	var bottle := _grenade(game, GrenadeRules.INCENDIARY, them, ground + Vector3.UP * GrenadeRules.RADIUS)
	var inferno := InfernoEntity.new()
	inferno.owner_id = them
	inferno.weapon_class = GrenadeRules.INCENDIARY
	inferno.fire = FireSpread.new(GrenadeRules.INCENDIARY, ground, 0, 7)
	inferno.position = ground
	inferno.previous_position = ground
	# As in the tick: the fire is in the world when the event is handed out.
	game.entities.spawn(inferno)
	_send(game, &"molotov_detonate", {"userid": them, "x": ground.x, "y": ground.y, "z": ground.z})
	_gone(game, bottle)
	sounds._process(0.0)
	_check(_voices(sounds, "IncGrenade.Start").size() == 1 and _voices(sounds, "IncGrenade.Pop").size() == 1, "an incendiary that lights: its start and pop")
	_check(_voices(sounds, "IncGrenade.StartFailed").is_empty(), "not the fizzle")
	_check_equal(_voices(sounds, "Inferno.Fire.Ignite").size(), 1, "its first flame ignites")
	_send(game, &"inferno_startburn", {"entityid": inferno.id, "x": ground.x, "y": ground.y, "z": ground.z})
	sounds._process(0.0)
	_check_equal(_voices(sounds, "Inferno.Loop").size(), 1, "the fire's loop")
	for i in 6:
		inferno.fire.flames.append(ground + Vector3(40.0 * (i + 1), 0.0, 0.0))
	sounds._process(0.0)
	var ignites := _voices(sounds, "Inferno.Fire.Ignite").size()
	_check(ignites > 1 and ignites <= 3, "new flames ignite, three at most at once (%d)" % ignites)
	sounds.events.advance(7.5)
	_check_equal(_voices(sounds, "Inferno.Loop").size(), 1, "the loop plays on until the fire ends, 7.5 s on (past a 7 s fire; it stops itself at 8 s)")
	_send(game, &"inferno_extinguish", {"entityid": inferno.id, "x": ground.x, "y": ground.y, "z": ground.z})
	_gone(game, inferno)
	sounds._process(0.0)
	_check(_voices(sounds, "Inferno.Loop").is_empty() and _voices(sounds, "Molotov.Extinguish").size() == 1, "put out: the loop stops, the hiss plays")

	# A decoy sounds like the gun it was given.
	var decoy := _grenade(game, GrenadeRules.DECOY, them, Vector3(-200.0, 0.0, 0.0))
	decoy.decoy_weapon = "weapon_awp"
	_send(game, &"decoy_firing", {"userid": them, "entityid": decoy.id, "x": -200.0, "y": 0.0, "z": 0.0})
	sounds._process(0.0)
	var shots := _voices(sounds, "Weapon_AWP.Single")
	_check(shots.size() == 1 and (shots[0]["position"] as Vector3).is_equal_approx(Vector3(-200.0, 0.0, 0.0)), "a decoy fires an AWP's shot, from the decoy")
	_check_equal(_voices(sounds, "Weapon_AWP.SingleDistant").size(), 1, "with its distant layer")
	_gone(game, decoy)

	# A flash in your eyes: the ring, on the bus the muffle leaves alone.
	_send(game, &"player_blind", {"userid": them, "attacker": them, "entityid": 99, "blind_duration": 4.0})
	sounds._process(0.0)
	_check(_voices(sounds, "Flashbang.Ring.Long").is_empty() and sounds.muffle.amount(sounds._clock) == 0.0, "their blinding rings nothing for you")
	_send(game, &"player_blind", {"userid": me, "attacker": them, "entityid": 99, "blind_duration": 4.5})
	sounds._process(0.0)
	var ring := _voices(sounds, "Flashbang.Ring.Long")
	_check(ring.size() == 1 and ring[0]["bus"] == SoundEvents.bypass_bus(&"Explosions"), "yours: the long ring, on the explosions' twin that bypasses the muffle")
	_check_near(sounds.muffle.amount(sounds._clock), 1.0, "and the long muffle, full")
	var explosions := AudioServer.get_bus_index(&"Explosions")
	var enabled := false
	for i in AudioServer.get_bus_effect_count(explosions):
		enabled = enabled or AudioServer.is_bus_effect_enabled(explosions, i)
	_check(enabled, "the muffle is on the explosions' bus")
	_send(game, &"player_death", {"userid": me, "attacker": them, "weapon": "weapon_ak47"})
	sounds._process(0.0)
	_check(_voices(sounds, "Flashbang.Ring.Long").is_empty() and sounds.muffle.amount(sounds._clock) == 0.0, "dying clears the ring and the muffle")

	_check_equal(SoundEvents.late_loads, loads, "nothing read from the disk as it played")
	_check(sounds.events.voices().all(func(v: Dictionary) -> bool: return not v["has_player"]), "and without the files, nothing sounds")
	sounds.queue_free()
	await process_frame
	_check_equal(AudioServer.get_bus_effect_count(explosions), effects_before, "the view gone, its effects are off the buses")
	for node in root.get_children():
		if node is PlayerSim:
			node.queue_free()
	await process_frame
	SoundBank._available = availability


func _test_a_burn_heard() -> void:
	var game := GameSystems.new()
	var me := _add_player(game, "CT", Vector3.ZERO)
	var them := _add_player(game, "T", Vector3(300.0, 0.0, 0.0))
	var hits := HitSounds.new()
	root.add_child(hits)
	hits.events.silent_length = 100.0
	hits.watch(game, me)
	_send(game, &"player_hurt", {"userid": them, "attacker": me, "weapon": GrenadeRules.MOLOTOV, "health": 90, "armor": 0, "dmg_health": 10})
	hits._process(0.0)
	var burns := hits.events.voices().filter(func(v: Dictionary) -> bool: return v["event"] == HitSounds.BURN_EVENT)
	_check(burns.size() == 1 and (burns[0]["position"] as Vector3).is_equal_approx(Vector3(300.0, 0.0, 0.0)), "a burn is heard from the one burning")
	_send(game, &"player_hurt", {"userid": them, "attacker": me, "weapon": GrenadeRules.MOLOTOV, "health": 80, "armor": 0, "dmg_health": 10})
	hits._process(0.0)
	burns = hits.events.voices().filter(func(v: Dictionary) -> bool: return v["event"] == HitSounds.BURN_EVENT)
	_check_equal(burns.size(), 1, "one per 0.6 s, as CS2's block")
	hits.queue_free()
	for node in root.get_children():
		if node is PlayerSim:
			node.queue_free()
	await process_frame
