extends "res://tests/check_suite.gd"

## September 2026 CS2 constants/timers, including boundary and stale-state
## cases. Physical contact geometry is checked by projectile_trace.
func _initialize() -> void:
	_hold_and_release()
	_jump_snapshot()
	_flight_rules()
	_fuse_rules()
	_activation()
	_finish("grenade-port")


func _hold_and_release() -> void:
	var state := GrenadeThrowState.new()
	state.hold(false, true, 1)
	_check_near(state.strength, 0.0, "first right-button hold assigns the target directly")
	state.hold(true, false, 2)
	_check_near(state.strength, 0.0203124992549, "switching to left approaches by the recovered hold increment")
	state.hold(true, false, 2)
	_check_near(state.strength, 0.0203124992549, "a duplicate update in one hold tick cannot add strength")
	for tick in range(3, 26):
		state.hold(true, false, tick)
	_check_near(GrenadeRules.launch_strength(state.strength), 0.5, "a strength in the middle band snaps for launch")
	_check_near(GrenadeRules.launch_strength(0.399), 0.399, "below the middle band retains the actual strength")
	_check_near(GrenadeRules.launch_strength(0.601), 0.601, "above the middle band retains the actual strength")
	state.release(GrenadeRules.HE, 1_000_000)
	_check(state.consume(1_100_000).is_empty(), "release deadline uses strict greater-than")
	_check_equal(state.consume(1_100_001), GrenadeRules.HE, "ordinary release spawns after 0.1 seconds")
	_check(state.consume(1_200_000).is_empty(), "one release can be consumed only once")
	state.release(GrenadeRules.HE, 2_000_000)
	state.reset()
	_check(state.consume(3_000_000).is_empty(), "death/respawn reset cancels a pending throw")


func _jump_snapshot() -> void:
	var state := GrenadeThrowState.new()
	state.jumped(1_003_906, 15_625)
	_check_equal(state.stash_usec, 1_119_531, "subtick jump schedules the stash one movement interval plus 0.1 seconds later")
	var saved := {"eye": Vector3(10.0, 96.0, 20.0), "center": Vector3(10.0, 68.0, 20.0),
		"yaw": 15.0, "pitch": 25.0, "velocity": Vector3(120.0, 220.0, -30.0)}
	state.finish_movement(state.stash_usec - 1, saved)
	_check(state.snapshot.is_empty(), "movement finish before the scheduled instant captures nothing")
	state.finish_movement(state.stash_usec, saved)
	saved["yaw"] = 99.0
	_check_equal(state.snapshot.yaw, 15.0, "the snapshot owns its parameters")
	var live := {"yaw": -45.0}
	_check_equal(state.launch(state.stash_usec, live).yaw, -45.0, "snapshot age zero uses live parameters")
	_check_equal(state.launch(state.stash_usec + 1, live).yaw, 15.0, "ready snapshot with positive age supplies launch aim")
	_check_equal(state.launch(state.stash_usec + 200_000, live).yaw, 15.0, "the 0.2-second age endpoint includes the snapshot")
	_check_equal(state.launch(state.stash_usec + 200_001, live).yaw, -45.0, "an expired snapshot falls back to live parameters")
	state.release(GrenadeRules.HE, 1_010_000)
	_check(state.consume(1_110_001).is_empty() and state.jump_throw and state.due_usec == 1_210_001,
		"a qualifying first timer consume defers a jump throw once by 0.1 seconds")
	_check_equal(state.consume(1_210_002), GrenadeRules.HE, "the deferred timer releases once")
	state.release(GrenadeRules.FLASHBANG, 1_220_000)
	_check(state.jump_throw, "release already inside the snapshot age range marks jump throw immediately")
	_check_equal(state.consume(1_320_001), GrenadeRules.FLASHBANG, "an already marked jump release is not deferred twice")
	state.jumped(2_000_000, 15_625)
	_check(state.snapshot.is_empty(), "another actual jump invalidates the previous snapshot")


func _flight_rules() -> void:
	_check_equal(GrenadeFlight.physics_steps(1.0 / 64.0), 2, "64 Hz flight runs two 1/128-second steps")
	_check_equal(GrenadeFlight.physics_steps(1.0 / 32.0), 4, "an integral interval retains the same physics cadence")
	_check_equal(GrenadeFlight.physics_steps(0.04), 1, "non-integral intervals use the recovered single-step fallback")
	var flight := GrenadeFlight.throw_from(null, GrenadeRules.HE, Vector3(0.0, 64.0, 0.0), 0.0, 0.0,
		Vector3(80.0, 0.0, 0.0), 1.0, [], Vector3(0.0, 36.0, 0.0))
	_check_near(flight.position.z, -16.0 * cos(deg_to_rad(10.0)), "clear launch is 16 units forward from the lowered eye")
	_check_near(flight.velocity.x, 100.0, "launch retains 1.25 of pawn velocity")
	var start := flight.position
	var velocity := flight.velocity
	flight.step(null, 1.0 / 64.0)
	_check_near(flight.position.y, start.y + velocity.y / 64.0 - 160.0 / (64.0 * 64.0), "substeps preserve the midpoint-gravity free arc")
	_check_near(flight.velocity.y, velocity.y - 5.0, "gravity removes five vertical units per 64 Hz tick")
	flight.velocity = Vector3(100.0, -100.0, 0.0)
	flight._bounce(Vector3.UP, true)
	_check_near(flight.velocity.y, 45.0140625, "a player surface uses clip push plus elasticity")
	_check_near(flight.velocity.x, 45.0, "player surfaces do not apply the separate body-hit factor")
	flight.bounces = 21
	flight._bounce(Vector3.UP, false)
	_check(flight.at_rest and flight.velocity == Vector3.ZERO, "contact after the 21st counted bounce stops flight")


func _fuse_rules() -> void:
	var grenade := GrenadeEntity.new()
	grenade.flight = GrenadeFlight.new()
	grenade.thrown_usec = 1_000_000
	var game := GameSystems.new()
	var t := SimTick.new(game, 64, null)
	t.now_usec = 1_000_000
	_check(grenade._think_due(t), "ordinary fuse starts thinking at spawn")
	t.now_usec = 1_199_999
	_check(not grenade._think_due(t), "next danger think waits 0.2 seconds")
	t.now_usec = 1_203_125
	_check(grenade._think_due(t) and grenade.next_think_usec == 1_403_125,
		"think cadence reschedules from its actual tick, preserving tick quantization")
	grenade.flight.velocity = Vector3.RIGHT * 100.0
	_check(not grenade._fire_due(3_000_000), "fire air deadline uses strict greater-than")
	_check(grenade._fire_due(3_000_001), "fire air deadline starts at projectile spawn")
	grenade.fire_extension_usec = 4_000_000
	_check(not grenade._fire_due(3_000_001), "one enemy body hit extends the air deadline by four seconds")
	grenade.flight.velocity = Vector3.ZERO
	_check(not grenade._fire_due(2_000_000), "low-speed fallback starts a separate timer")
	_check(not grenade._fire_due(2_500_000) and grenade._fire_due(2_500_001), "low-speed fallback waits more than 0.5 seconds")
	for system in game.systems():
		if system is ItemDrops:
			system.game = null


func _activation() -> void:
	var game := GameSystems.new()
	var system := GrenadeSystem.new()
	game.add_system(system)
	var grenade := _FuseProbe.new()
	grenade.system = system
	grenade.flight = GrenadeFlight.new()
	grenade.flight.at_rest = true
	grenade.weapon_class = GrenadeRules.SMOKE
	var t := SimTick.new(game, 1, null)
	t.now_usec = 1_187_999
	grenade._fly(t)
	_check_equal(grenade.pops, 0, "a settled smoke waits for the recovered minimum age")
	t.now_usec = 1_188_000
	grenade._fly(t)
	_check_equal(grenade.pops, 1, "smoke activates at age 1.188 seconds without waiting for a 0.2-second rest poll")
	grenade.weapon_class = GrenadeRules.DECOY
	grenade.next_think_usec = -1
	grenade.pops = 0
	t.now_usec = 1_999_999
	grenade._fly(t)
	_check_equal(grenade.pops, 0, "a settled decoy waits for its two-second initial think")
	t.now_usec = 2_000_000
	grenade._fly(t)
	_check_equal(grenade.pops, 1, "decoy activates at its initial think when speed is at most 0.2")
	grenade.pops = 0
	grenade.flight.velocity = Vector3.RIGHT * 0.201
	t.now_usec = 2_200_000
	grenade._fly(t)
	_check_equal(grenade.pops, 0, "decoy activation uses actual speed rather than the resting flag")
	for existing in game.systems():
		if existing is ItemDrops or existing is GrenadeSystem:
			existing.game = null


class _FuseProbe extends GrenadeEntity:
	var pops := 0
	func _detonate(_t: SimTick) -> void:
		pops += 1
