extends "res://tests/check_suite.gd"

## The movement's step in native code (native/src/hull_mover.cpp) held to the
## script's (PlayerBody._simulate_step), which is the reference: the same
## body, to the last bit, from the same start.
##
##   godot --headless --path . --script tests/run_native_movement_checks.gd
##
## Every check file already runs each native step both ways
## (tests/check_suite.gd, PlayerBody.check_steps). This one drives bodies
## where the others do not go: a course of floors, stairs, ramps a body
## walks and ramps it slides down, a wall, a ceiling to duck under, a ledge
## and other players, walked by seeded chance for tens of thousands of
## ticks, jumping part-way through a tick, ducking on the ground and in the
## air, and put down inside the floor and inside each other. And it checks
## the comparison itself: that it is made, that a difference is found, and
## that what the native code cannot run is left to the script.
##
## Where the native code has not been built (scripts/build_native.sh,
## .ps1) only what needs none of it is checked.

const TICKS := 24000
const SEED := 20260929

var _host: Node3D
var _world: GameWorld
var DT := SimClock.tick_seconds()


## A body whose script step is not the native one: it drifts. The native
## code steps it all the same, for the two to be compared.
class Drifting:
	extends PlayerBody

	func _init() -> void:
		native_over_own_functions = true

	func _simulate_step(dt: float) -> void:
		super._simulate_step(dt)
		velocity.x += 0.001


## A body with its own of one of the step's functions, as a profile's timed
## bot has.
class Counting:
	extends PlayerBody

	var ducks := 0

	func _update_duck(dt: float) -> void:
		ducks += 1
		super._update_duck(dt)


## A bridge with a script of its own, as a profile's timed bridge has.
class OwnBridge:
	extends Box3DQueries


func _initialize() -> void:
	_test_which_runs_the_step()
	_test_what_it_was_built_from()
	if not Box3DDrops.available():
		_skip("native-movement", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	await physics_frame
	if not PlayerBody.native_built():
		await _test_the_script_runs_alone()
		print("The native code does not run here (%s; scripts/build_native.sh, .ps1): the script runs every step and nothing is compared." % PlayerBody.native_missing)
		_finish("native-movement")
		return
	await _test_the_course()
	await _test_what_is_left_to_the_script()
	await _test_a_difference_is_found()
	await _test_what_it_costs()
	_finish("native-movement")


func _print_passes() -> bool:
	return true


func _test_which_runs_the_step() -> void:
	_check_equal(PlayerBody.movement_named(PackedStringArray(["--movement", "script"]), "native"), "script",
		"--movement script has the script run the step")
	_check_equal(PlayerBody.movement_named(PackedStringArray(["--mode", "practice", "--movement=Native"]), "script"), "native",
		"--movement=Native, in any case, the native code")
	_check_equal(PlayerBody.movement_named(PackedStringArray(["--mode", "practice"]), "native"), "native",
		"and neither leaves what the setting says")
	_check_equal(PlayerBody.movement_named(PackedStringArray(["--movement"]), "native"), "native",
		"a --movement with nothing after it is not a choice")
	_check(PlayerBody.configured_movement() in ["native", "script"], "what is configured is one of the two (%s)" % PlayerBody.configured_movement())


## The library is a copy of scripts, and runs only where it was built from
## the ones that are here. One that was built and does not run is a fault:
## nothing would be compared, and nothing would say so.
func _test_what_it_was_built_from() -> void:
	var names: Array[String] = ["a", "b"]
	_check_equal(PlayerBody.stamp_of(names, ["x", "y z"]), "ed57b9d11eeca8ecfd21f93bb4e187265459f237b7b1761943476603e8497349",
		"a stamp is the SHA-256 of each source's name and text, a line each, as the build works it out")
	_check_equal(PlayerBody.stamp_of(names, ["one\r\ntwo\r\n", "y"]), PlayerBody.stamp_of(names, ["one\ntwo\n", "y"]),
		"whatever a checkout made of the line endings")
	_check(PlayerBody.stamp_of(names, ["x", "y z"]) != PlayerBody.stamp_of(names, ["x", "y  z"]),
		"a space more in a source is another stamp")
	var others: Array[String] = ["a", "c"]
	_check(PlayerBody.stamp_of(names, ["x", "y z"]) != PlayerBody.stamp_of(others, ["x", "y z"]),
		"and so is a source by another name")
	var here := PlayerBody.native_sources()
	_check(here.length() == 64 and here.is_valid_hex_number(),
		"the sources here have a stamp (%s)" % here.left(12))
	for copied in PlayerBody.NATIVE_COPIES:
		_check(FileAccess.file_exists("res://" + copied), "%s, which the native code copies, is here" % copied)
	if PlayerBody.native_built():
		var made: Object = ClassDB.instantiate(PlayerBody.NATIVE_CLASS)
		_check_equal(String(made.call(&"get_sources")), here, "the library that runs was built from them")
	else:
		_check(not PlayerBody.native_installed(),
			"no native code is installed here that does not run (%s)" % PlayerBody.native_missing)


## Without the library a body moves by the script, asked for native steps
## or not.
func _test_the_script_runs_alone() -> void:
	_setup()
	var player := _player(Vector3(0.0, 1.0, 0.0))
	_start()
	await physics_frame
	var checked := PlayerBody.steps_checked
	var wanted := PlayerBody.native_steps
	PlayerBody.native_steps = true
	player.wish_dir = Vector3.RIGHT
	player.wish_speed = 250.0
	for tick in 64:
		player.simulate(DT)
	PlayerBody.native_steps = wanted
	_check(player.on_ground and player.position.x > 100.0 and PlayerBody.steps_checked == checked,
		"with no native code built a body walks by the script (%.0f units in a second), and nothing is compared" % player.position.x)
	_close()
	await process_frame


## The course, walked by chance.
func _test_the_course() -> void:
	_setup()
	_build_course()
	var walkers: Array[PlayerBody] = [_player(Vector3(0.0, 1.0, 0.0)), _player(Vector3(80.0, 1.0, 0.0))]
	# One who stands where they are, to be walked into and stood on.
	var standing := _player(Vector3(0.0, 1.0, -120.0))
	_start()
	await physics_frame
	for tick in 8:
		standing.simulate(DT)
	var chance := RandomNumberGenerator.new()
	chance.seed = SEED
	var checked := PlayerBody.steps_checked
	var faults := PlayerBody.step_faults.size()
	var spots: Array[Vector3] = [
		Vector3(0.0, 1.0, 0.0), Vector3(250.0, 1.0, 0.0), Vector3(-250.0, 1.0, 0.0), Vector3(0.0, 1.0, 180.0),
		Vector3(0.0, 1.0, -250.0), Vector3(0.0, 1.0, 380.0), Vector3(500.0, 70.0, 500.0), Vector3(440.0, 1.0, 380.0),
		# In the floor, in the one who stands, under the ceiling standing, on the stairs' edge.
		Vector3(60.0, -0.3, 60.0), Vector3(10.0, 1.0, -110.0), Vector3(0.0, 1.0, 400.0), Vector3(12.0, 13.0, 236.0),
		Vector3(0.0, 80.0, -120.0), Vector3(-330.0, 60.0, 0.0), Vector3(0.0, 120.0, -330.0),
		# At the foot of the stairs, and of the ramp.
		Vector3(40.0, 1.0, 170.0), Vector3(-40.0, 1.0, 175.0), Vector3(-330.0, 1.0, 130.0),
	]
	var ways: Array[Vector3] = [
		Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK,
		Vector3(1.0, 0.0, 1.0).normalized(), Vector3(-1.0, 0.0, 1.0).normalized(),
		Vector3(1.0, 0.0, -1.0).normalized(), Vector3(-1.0, 0.0, -1.0).normalized(),
	]
	var seen := {"ground": 0, "air": 0, "ducked": 0, "recovered": 0, "stepped": 0, "split": 0, "swept": 0, "landed": 0, "slid": 0}
	var settings := [0]
	for tick in TICKS:
		# Half of it as the game runs it, inside a tick of the world's.
		var in_tick := tick % 2000 < 1000
		if in_tick:
			_world.begin_tick()
		for walker in walkers:
			if chance.randf() < 0.0025:
				walker.global_position = spots[chance.randi_range(0, spots.size() - 1)]
				var thrown := Vector3(chance.randf_range(-300.0, 300.0), chance.randf_range(-200.0, 200.0), chance.randf_range(-300.0, 300.0))
				walker.velocity = thrown if chance.randf() < 0.5 else Vector3.ZERO
				# Half the time on towards the stairs, the ceiling and the ledge.
				if chance.randf() < 0.5:
					walker.wish_dir = Vector3.BACK
					walker.wish_speed = 250.0
				PhysicsQueries.sync_object(walker, false)
			if chance.randf() < 0.05:
				walker.wish_dir = ways[chance.randi_range(0, ways.size() - 1)]
				walker.wish_speed = [250.0, 130.0, 85.0, 215.0][chance.randi_range(0, 3)]
			if chance.randf() < 0.02:
				walker.wants_duck = not walker.wants_duck
			walker.wants_jump = chance.randf() < (0.5 if walker.wants_jump else 0.04)
			walker.jump_fraction = -1.0
			if walker.wants_jump and chance.randf() < 0.6:
				walker.jump_fraction = chance.randf_range(0.0, 1.0)
				if walker.jump_fraction > 0.0 and walker.jump_fraction < 1.0 and walker.config.subtick_jump:
					seen["split"] += 1
			if chance.randf() < 0.004:
				# The settings a match leaves alone, each way.
				var config := walker.config
				match chance.randi_range(0, 12):
					0: config.auto_bunnyhop = not config.auto_bunnyhop
					1: config.enable_bunnyhopping = not config.enable_bunnyhopping
					2: config.tick_rate_independent_jump = not config.tick_rate_independent_jump
					12: config.cs2_jump = not config.cs2_jump
					3: config.project_wish_dir_on_ground = not config.project_wish_dir_on_ground
					4: config.source_deadstrafe = not config.source_deadstrafe
					5: config.stay_on_ground = not config.stay_on_ground
					6: config.subtick_jump = not config.subtick_jump
					7: config.trace_epsilon = 0.0 if config.trace_epsilon != 0.0 else 0.03125
					8: config.gravity = [800.0, 600.0, 1000.0][chance.randi_range(0, 2)]
					9: config.max_ground_angle_deg = [45.57, 30.0, 60.0][chance.randi_range(0, 2)]
					10: config.step_height = [18.0, 12.0, 24.0][chance.randi_range(0, 2)]
					11: config.duck_time = [0.4, 0.1, 0.0][chance.randi_range(0, 2)]
				settings[0] += 1
			var was_on_ground := walker.on_ground
			var traces := walker.traces
			var from := walker.global_position
			walker.simulate(DT)
			seen["ground" if walker.on_ground else "air"] += 1
			if walker.is_ducked:
				seen["ducked"] += 1
			if walker._last_native_trace_recovery != Vector3.ZERO:
				seen["recovered"] += 1
			if walker.on_ground and was_on_ground and walker.global_position.y - from.y > 4.0:
				seen["stepped"] += 1
			if walker.on_ground and not was_on_ground:
				seen["landed"] += 1
			if not walker.on_ground and walker.velocity.y < -50.0 and walker.traces - traces >= 2:
				seen["slid"] += 1
			seen["swept"] += walker.traces - traces
		if in_tick:
			_world.end_tick()
	var compared := PlayerBody.steps_checked - checked
	var found := PlayerBody.step_faults.size() - faults
	_check(compared >= TICKS * walkers.size(),
		"every step of %d ticks of two bodies on the course was run by the script and by the native code (%d steps, %d of them halves of a tick a jump split)"
			% [TICKS, compared, seen["split"] * 2])
	_check(found == 0,
		"and the two gave the same body every time, to the last bit (%d differed%s)"
			% [found, "" if found == 0 else "; the first: " + PlayerBody.step_faults[faults]])
	_check(
		seen["ground"] > 5000 and seen["air"] > 5000 and seen["ducked"] > 3000 and seen["recovered"] > 20
			and seen["stepped"] > 20 and seen["landed"] > 300 and seen["slid"] > 300 and seen["split"] > 300,
		"on the ground and in the air, ducked, stepping up, landing, sliding on what it met in the air, and getting clear of what it stood in: %s"
			% [seen]
	)
	_check(settings[0] > 100, "with the movement's settings changed under them %d times: bunny hopping, the jump's gravity, the wish along the slope, the dead strafe, staying on the ground, the split tick, the trace's epsilon, gravity, the steepest floor, the step and the duck's time" % settings[0])
	_check(walkers.all(func(walker: PlayerBody) -> bool: return walker.global_position.is_finite() and walker.velocity.is_finite()),
		"and both bodies are still somewhere (%s and %s)" % [walkers[0].global_position.snapped(Vector3.ONE), walkers[1].global_position.snapped(Vector3.ONE)])
	_close()
	await process_frame


## What the native code does not run is the script's: a body under
## something moved or turned, a body turned itself, a hull that is no box,
## a body or a bridge with functions of its own in the step's place, and
## any body once native steps are switched off.
func _test_what_is_left_to_the_script() -> void:
	for case: String in ["as the game has it", "under something moved", "under something turned", "turned itself",
			"a capsule for a hull", "a function of its own", "a function of its own, and the native code asked for",
			"a bridge of its own", "native steps off"]:
		_setup()
		var over := Node3D.new()
		_host.add_child(over)
		if case == "under something moved":
			over.position = Vector3(3.0, 0.0, 0.0)
		elif case == "under something turned":
			over.rotation.y = 0.5
		var player: PlayerBody = Counting.new() if case.begins_with("a function of its own") else PlayerBody.new()
		player.native_over_own_functions = case.ends_with("asked for")
		player.position = Vector3(0.0, 1.0, 0.0)
		player.collision_layer = 2
		player.collision_mask = 1 | 2 | MapImporter.PLAYER_CLIP_LAYER
		var collision := CollisionShape3D.new()
		if case == "a capsule for a hull":
			var capsule := CapsuleShape3D.new()
			capsule.radius = 16.0
			capsule.height = 72.0
			collision.shape = capsule
		else:
			var shape := BoxShape3D.new()
			shape.size = Vector3(32.0, 72.0, 32.0)
			collision.shape = shape
		collision.position.y = 36.0
		player.add_child(collision)
		over.add_child(player)
		if case == "turned itself":
			player.rotation.y = 0.3
		_start()
		if case == "a bridge of its own":
			var physics: Box3DDrops = _world.game.drop_physics
			# As scripts/profile_box3d_costs.gd changes bridges: the first
			# one's copy of the body goes, or the body stands inside it.
			for native in physics.native_world.get_children():
				var source_id := int(native.get_meta(&"source_id", 0))
				if source_id != 0 and instance_from_id(source_id) is CharacterBody3D:
					native.free()
			physics.queries.close()
			physics.queries = OwnBridge.new()
			physics.queries.initialize(physics, _host)
		await physics_frame
		var wanted := PlayerBody.native_steps
		PlayerBody.native_steps = case != "native steps off"
		var checked := PlayerBody.steps_checked
		player.wish_dir = Vector3.RIGHT
		player.wish_speed = 250.0
		for tick in 32:
			player.simulate(DT)
		PlayerBody.native_steps = wanted
		var compared := PlayerBody.steps_checked - checked
		if case == "as the game has it" or case.ends_with("asked for"):
			_check(compared == 32 and player.velocity.length() > 100.0,
				"%s, the native code runs a body's steps (%d of 32 compared)" % [case, compared])
		elif case == "a function of its own":
			_check(compared == 0 and (player as Counting).ducks == 32 and player.velocity.length() > 100.0,
				"%s in the step's place: the script runs the steps and its function with them (%d compared, %d of its own run)" % [
					case, compared, (player as Counting).ducks])
		else:
			_check(compared == 0 and player.velocity.length() > 100.0,
				"%s: the script runs the steps, and the body walks (%d compared, going %.0f)" % [case, compared, player.velocity.length()])
		_close()
		await process_frame


## The comparison finds a difference when there is one: a body whose script
## step drifts a thousandth of a unit a second from the native one's.
func _test_a_difference_is_found() -> void:
	_setup()
	var player := Drifting.new()
	player.position = Vector3(0.0, 1.0, 0.0)
	player.collision_layer = 2
	player.collision_mask = 1 | 2 | MapImporter.PLAYER_CLIP_LAYER
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(32.0, 72.0, 32.0)
	collision.shape = shape
	collision.position.y = 36.0
	player.add_child(collision)
	_host.add_child(player)
	_start()
	await physics_frame
	var faults := PlayerBody.step_faults.duplicate()
	var checked := PlayerBody.steps_checked
	player.simulate(DT)
	var found := PlayerBody.step_faults.size() - faults.size()
	var said := PlayerBody.step_faults[-1] if found > 0 else ""
	# Its own doing, not the native code's: taken back out.
	PlayerBody.step_faults = faults
	PlayerBody.steps_checked = checked
	_check(found == 1 and said.contains("velocity"),
		"a step that comes out a thousandth of a unit a second apart is a fault, and says what differed (%s)" % said.right(110))
	_check(player.velocity.x == 0.0,
		"and the native code's result is the one kept (%s)" % var_to_str(player.velocity))
	_close()
	await process_frame


## What a tick of a body costs either way, on the course: said, not held to.
func _test_what_it_costs() -> void:
	_setup()
	_build_course()
	var player := _player(Vector3(0.0, 1.0, 0.0))
	_start()
	await physics_frame
	var checking := PlayerBody.check_steps
	var wanted := PlayerBody.native_steps
	PlayerBody.check_steps = false
	var took := {}
	var ended := {}
	for which: String in ["script", "native", "script", "native"]:
		PlayerBody.native_steps = which == "native"
		player.global_position = Vector3(0.0, 1.0, 0.0)
		player.velocity = Vector3.ZERO
		PhysicsQueries.sync_object(player, false)
		var started := Time.get_ticks_usec()
		for tick in 4000:
			# Round a square, a jump now and then.
			player.wish_dir = [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD][int(tick / 96.0) % 4]
			player.wish_speed = 250.0
			player.wants_jump = tick % 150 == 0
			player.simulate(DT)
		took[which] = minf(float(took.get(which, INF)), float(Time.get_ticks_usec() - started) / 4000.0)
		ended[which] = [player.global_position, player.velocity]
	PlayerBody.check_steps = checking
	PlayerBody.native_steps = wanted
	_check(ended["script"] == ended["native"],
		"four thousand ticks round a square end at the same place at the same speed either way (%s)" % [(ended["native"][0] as Vector3).snapped(Vector3.ONE * 0.01)])
	print("  a tick of a body on the course: %.1f us by the script, %.1f us by the native code" % [took["script"], took["native"]])
	_close()
	await process_frame


# --- The course ---------------------------------------------------------------

func _build_course() -> void:
	# A wall.
	_box(Vector3(300.0, 100.0, 0.0), Vector3(16.0, 200.0, 400.0))
	# Stairs, a step 12 high and 24 deep, up to 60.
	for step in 5:
		_box(Vector3(0.0, 6.0 + 12.0 * step - 6.0 * step, 212.0 + 24.0 * step), Vector3(160.0, 12.0 + 12.0 * step, 24.0))
	# A ceiling to duck under: its underside 60 up.
	_box(Vector3(0.0, 68.0, 400.0), Vector3(200.0, 16.0, 120.0))
	# A ramp to walk up, and one to slide down.
	_ramp(Vector3(-330.0, 0.0, 0.0), 30.0, Vector3.FORWARD)
	_ramp(Vector3(0.0, 0.0, -330.0), 60.0, Vector3.RIGHT)
	# A platform with a ledge to walk off, and a lip before it.
	_box(Vector3(500.0, 32.0, 500.0), Vector3(200.0, 64.0, 200.0))
	_box(Vector3(440.0, 8.0, 380.0), Vector3(80.0, 16.0, 40.0))
	# What stops a body and lets a round by.
	var clip := _box(Vector3(-100.0, 40.0, -250.0), Vector3(120.0, 80.0, 16.0))
	clip.collision_layer = MapImporter.PLAYER_CLIP_LAYER


## A slab tilted `degrees` about `axis`, its middle at `at`.
func _ramp(at: Vector3, degrees: float, axis: Vector3) -> StaticBody3D:
	var ramp := _box(at, Vector3(200.0, 16.0, 200.0))
	ramp.transform = Transform3D(Basis(axis, deg_to_rad(degrees)), at)
	return ramp


func _setup() -> void:
	_host = Node3D.new()
	root.add_child(_host)
	_box(Vector3(0.0, -8.0, 0.0), Vector3(2048.0, 16.0, 2048.0))


func _start() -> void:
	_world = GameWorld.new()
	_host.add_child(_world)
	_world.set_physics_process(false)
	_world.initialize_drop_physics(_host, "box3d")


func _close() -> void:
	_host.free()


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_host.add_child(body)
	return body


func _player(at: Vector3) -> PlayerBody:
	var player := PlayerBody.new()
	player.position = at
	player.collision_layer = 2
	player.collision_mask = 1 | 2 | MapImporter.PLAYER_CLIP_LAYER
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(32.0, 72.0, 32.0)
	collision.shape = shape
	collision.position.y = 36.0
	player.add_child(collision)
	_host.add_child(player)
	return player
