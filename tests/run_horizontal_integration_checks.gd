extends "res://tests/check_suite.gd"

## Numeric collision-free oracles plus real Box3D contacts for the continuous
## acceleration/deferred-velocity port. End velocity alone would miss the
## former full-step displacement, or a deferred half restored after a stop.
## Every ordinary PlayerBody below also runs script/native comparison.

const DT := 1.0 / 64.0
const START := Vector3(-256.0, 1.0, -256.0)
const AIR := Vector3(-256.0, 256.0, -256.0)

var _host: Node3D
var _world: GameWorld


func _initialize() -> void:
	_test_speed_quantization()
	if not Box3DDrops.available():
		_skip("horizontal-integration", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	_check(PlayerBody.native_built() or not PlayerBody.native_installed(),
		"an installed mover was built from the current sources (%s)" % PlayerBody.native_missing)
	await physics_frame
	await _test_ground_numbers()
	await _test_ground_cap()
	await _test_split_ground()
	await _test_subtick_stop()
	await _test_air_numbers()
	await _test_split_air()
	await _test_exact_apex()
	await _test_wall_slide()
	await _test_blocked_move()
	await _test_query_bounds()
	if PlayerBody.native_built():
		_check(PlayerBody.steps_checked >= 100,
			"the physical numeric and contact fixtures actually ran native comparison")
	_finish("horizontal-integration")


func _near_tolerance() -> float:
	return 0.0002


func _test_speed_quantization() -> void:
	# Independent decoded binary32 values from the signed 20-bit wire grid.
	# Zero bypasses the grid: its nearest positive code would decode to 1/64.
	var values := [
		[0.0, 0.0], [0.0625, 0.04687504470348358],
		[3.0, 2.984377861022949], [50.0, 49.98442077636719],
		[80.0, 79.98445129394531], [250.0, 249.984619140625],
		[1000.0, 999.9853515625], [20000.0, 16384.0],
		[-20000.0, -16384.0],
	]
	for pair: Array in values:
		_check_equal(MovementSolver.quantized_speed(pair[0]), pair[1],
			"speed %.4f decodes on the recovered grid" % pair[0])


func _test_ground_numbers() -> void:
	# name, initial x, signed wish speed, end x, travel x, acceleration x,
	# deferred x, friction overshoot. Values are scalar worked examples, not
	# calls to the production friction/acceleration helpers.
	var cases := [
		["accelerate from rest", 0.0, 250.0, 21.484375, 0.1678466796875, 1375.0, 10.7421875, 0.0],
		["coast below stop speed", 50.0, 0.0, 43.5, 0.73046875, -416.0, -3.25, 0.0],
		["coast at running speed", 250.0, 0.0, 229.68874969482422, 3.7475683569908145, -1299.92001953125, -10.155625152587891, 0.0],
		["replace only speed lost to friction", 250.0, 250.0, 250.0, 3.90625, 0.0, 0.0, 0.0],
		["subtract friction overshoot", 3.0, 250.0, 17.984375, 0.1639404296875, 959.0, 7.4921875, 3.5],
		["counter strafe", 50.0, -250.0, 22.015625, 0.5626220703125, -1791.0, -13.9921875, 0.0],
		["reverse through zero", 10.0, -250.0, -17.984375, -0.0623779296875, -1791.0, -13.9921875, 0.0],
		["stop under one unit per second", 7.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		["retain a small midpoint move", 9.25, 0.0, 2.75, 0.09375, -416.0, -3.25, 0.0],
	]
	for sample: Array in cases:
		_setup()
		var player := _player(START)
		_start()
		await physics_frame
		_settle(player)
		var origin := player.position
		player.velocity = Vector3(sample[1], 0.0, 0.0)
		player.wish_dir = Vector3.RIGHT if sample[2] >= 0.0 else Vector3.LEFT
		player.wish_speed = absf(sample[2])
		# A prior segment must not contribute any of these to this segment.
		player._move_acceleration = Vector3(900.0, 1200.0, 600.0)
		player._deferred_velocity = Vector3(100.0, 200.0, 300.0)
		player._friction_overshoot = 123.0
		player.simulate(DT)
		var label: String = sample[0]
		_vector_near(player.velocity, Vector3(sample[3], 0.0, 0.0), label + ": published velocity")
		_check_near(player.position.x - origin.x, sample[4], label + ": midpoint displacement")
		_check_near(player.position.z, origin.z, label + ": no stale sideways movement")
		_vector_near(player._move_acceleration, Vector3(sample[5], 0.0, 0.0), label + ": new acceleration")
		_vector_near(player._deferred_velocity, Vector3(sample[6], 0.0, 0.0), label + ": new deferred half")
		_check_near(player._friction_overshoot, sample[7], label + ": overshoot reset and recomputed")
		_check(player.on_ground, label + ": stays on the real Box3D floor")
		_close()
		await process_frame


func _test_ground_cap() -> void:
	_setup()
	var player := _player(START)
	_start()
	await physics_frame
	_settle(player)
	player.config.friction = 0.0
	player.velocity = Vector3.RIGHT * 85.0
	player.wish_dir = Vector3.FORWARD
	player.wish_speed = 85.0
	player.acceleration_speed = 250.0
	player.movement_speed_limit = 85.0
	var origin := player.position
	# Turning at an 85-unit cap: first accelerate by 21.484375, then shorten
	# the whole vector to 85. The cap's correction is continuous acceleration
	# too, so its actual delta contributes to the midpoint displacement.
	var uncapped := Vector3(85.0, 0.0, -21.484375)
	var expected := uncapped * (85.0 / sqrt(85.0 * 85.0 + 21.484375 * 21.484375))
	var acceleration := (expected - player.velocity) / DT
	var midpoint := (player.velocity + expected) * 0.5
	player.simulate(DT)
	_vector_near(player.velocity, expected, "the command speed cap limits the whole turn")
	_vector_near(player._move_acceleration, acceleration, "cap correction joins actual acceleration", 0.002)
	_vector_near(player._deferred_velocity, acceleration * DT * 0.5, "cap correction is half deferred")
	_vector_near(Vector3(player.position.x - origin.x, 0.0, player.position.z - origin.z), midpoint * DT,
		"capped turning uses the corrected midpoint")
	_close()
	await process_frame


func _test_split_ground() -> void:
	_setup()
	var player := _player(START)
	_start()
	await physics_frame
	_settle(player)
	var origin := player.position
	player.velocity = Vector3.RIGHT * 50.0
	player.wish_dir = Vector3.RIGHT
	player.wish_speed = 250.0
	player.movement_fraction = 0.25
	var compared := PlayerBody.steps_checked
	player.simulate(DT)
	# Both segments stay below 80: constant acceleration = 1375 - 416 = 959.
	_check_near(player.velocity.x, 50.0 + 959.0 * DT, "split ground intervals restore each endpoint")
	_check_near(player.position.x - origin.x, 50.0 * DT + 0.5 * 959.0 * DT * DT,
		"split constant acceleration composes to the analytic displacement")
	_check_near(player._deferred_velocity.x, 959.0 * (0.75 * DT) * 0.5,
		"second ground segment owns only its deferred half")
	if PlayerBody.native_built():
		_check_equal(PlayerBody.steps_checked - compared, 2, "a split command compares both native intervals")
	_close()
	await process_frame


func _test_subtick_stop() -> void:
	_setup()
	var player := _player(START)
	_start()
	await physics_frame
	_settle(player)
	var origin := player.position
	player.velocity = Vector3.RIGHT * 7.25
	# Friction leaves 5.625 at this quarter-segment's endpoint, and its
	# midpoint is 6.4375. Neither is below one, but CS2 projects to the fixed
	# 1/64 interval: 6.4375 - 416 * (1/64 - 1/512) = 0.75, which stops.
	player.simulate(DT * 0.25)
	_vector_near(player.position, origin, "the fixed 64 Hz stop predictor prevents a quarter-segment move")
	_vector_near(player.velocity, Vector3.ZERO, "a subtick stop clears a local endpoint above one")
	_vector_near(player._move_acceleration, Vector3.ZERO, "a subtick stop clears continuous acceleration")
	_vector_near(player._deferred_velocity, Vector3.ZERO, "a subtick stop clears the deferred half")
	_check(player.on_ground, "a subtick stop remains on the Box3D floor")
	_close()
	await process_frame


func _test_air_numbers() -> void:
	for wish: float in [100.0, 250.0]:
		_setup()
		var player := _player(AIR)
		_start()
		await physics_frame
		player.config.gravity = 0.0
		player.config.source_deadstrafe = false
		player.velocity = Vector3.RIGHT * 250.0
		player.wish_dir = Vector3.FORWARD
		player.wish_speed = wish
		var expected := _air_oracle(0.0, wish, DT)
		player.simulate(DT)
		var label := "air wish %.0f" % wish
		_check_near(player.velocity.x, 250.0, label + ": retains perpendicular speed")
		_check_near(player.velocity.z, -expected[0], label + ": restores capped endpoint")
		_check_near(player.position.x - AIR.x, 250.0 * DT, label + ": perpendicular travel")
		_check_near(player.position.z - AIR.z, -expected[1], label + ": only the leading half travels")
		_check_near(player._deferred_velocity.z, -expected[2], label + ": trailing half keeps its own cap")
		_vector_near(player._move_acceleration, Vector3.ZERO, label + ": air additions are discrete velocity")
		# The next command starts fresh, even though the last endpoint retains
		# the deferred field for inspection/native comparison.
		var second := _air_oracle(expected[0], wish, DT)
		var origin := player.position
		player.simulate(DT)
		_check_near(player.velocity.z, -second[0], label + ": second endpoint does not reapply deferred velocity")
		_check_near(player.position.z - origin.z, -second[1], label + ": second displacement")
		_check_near(player._deferred_velocity.z, -second[2], label + ": second deferred state is fresh")
		_close()
		await process_frame


func _test_split_air() -> void:
	for fraction: float in [0.25, 0.5, 0.75]:
		_setup()
		var player := _player(AIR)
		_start()
		await physics_frame
		player.config.gravity = 0.0
		player.config.source_deadstrafe = false
		player.velocity = Vector3.RIGHT * 250.0
		player.wish_dir = Vector3.FORWARD
		player.wish_speed = 250.0
		player.movement_fraction = fraction
		var first := _air_oracle(0.0, 250.0, DT * fraction)
		var second := _air_oracle(first[0], 250.0, DT * (1.0 - fraction))
		var compared := PlayerBody.steps_checked
		player.simulate(DT)
		var label := "air split %.2f" % fraction
		_check_near(player.velocity.z, -second[0], label + ": endpoint after separate caps")
		_check_near(player.position.z - AIR.z, -(first[1] + second[1]), label + ": composes the two leading halves")
		_check_near(player._deferred_velocity.z, -second[2], label + ": no deferred carry between segments")
		if PlayerBody.native_built():
			_check_equal(PlayerBody.steps_checked - compared, 2, label + ": native compares each segment")
		_close()
		await process_frame


func _air_oracle(speed: float, wish: float, dt: float) -> Array[float]:
	# Integral of a separately capped impulse at each side of the move. This
	# scalar oracle avoids the movement helpers, collision state and gravity.
	var allowance := maxf(minf(wish, 30.0) - speed, 0.0)
	var leading := minf(allowance, 6.0 * wish * dt)
	var trailing := minf(allowance - leading, 6.0 * wish * dt)
	return [speed + leading + trailing, (speed + leading) * dt, trailing]


func _test_exact_apex() -> void:
	_setup()
	var player := _player(AIR)
	_start()
	await physics_frame
	player.config.source_deadstrafe = false
	player.velocity = Vector3.UP * 6.25
	player.simulate(DT)
	_vector_near(player.position, AIR, "an exact zero midpoint attempts no movement")
	_vector_near(player.velocity, Vector3.DOWN * 6.25, "the unblocked apex restores its deferred gravity")
	_vector_near(player._deferred_velocity, Vector3.DOWN * 6.25, "no attempted motion is not a hard stop")
	_vector_near(player._move_acceleration, Vector3.DOWN * 800.0, "apex retains continuous gravity")
	_check(not player.on_ground, "the stationary midpoint remains airborne over the real floor")
	_check(not player.blocked_air_move(), "a no-motion apex is excluded from collision-stall recovery")
	_close()
	await process_frame


func _test_wall_slide() -> void:
	_setup()
	_box(Vector3(128.0, 292.0, 0.0), Vector3(16.0, 256.0, 512.0))
	var player := _player(Vector3(103.5, 256.0, 0.0))
	_start()
	await physics_frame
	player.config.source_deadstrafe = false
	player.velocity = Vector3.BACK * 250.0
	player.wish_dir = Vector3.RIGHT
	player.wish_speed = 250.0
	player.simulate(DT)
	_check(player.position.x > 103.5 and player.position.x < 104.1,
		"the real wall clips a move that made partial forward progress")
	_check_near(player.position.z, 250.0 * DT, "an ordinary slide retains its tangent displacement")
	_check_near(player.position.y - 256.0, -6.25 * DT, "wall sliding retains midpoint gravity")
	_vector_near(player.velocity, Vector3(6.5625, -12.5, 250.0),
		"ordinary plane clipping restores even the deferred half directed into the wall", 0.005)
	_vector_near(player._deferred_velocity, Vector3(6.5625, -6.25, 0.0),
		"ordinary plane clipping leaves both deferred air and gravity intact")
	_vector_near(player._move_acceleration, Vector3.DOWN * 800.0,
		"an ordinary wall slide retains continuous acceleration")
	_check(not player.on_ground, "the wall contact does not categorize as ground")
	_close()
	await process_frame


func _test_blocked_move() -> void:
	_setup()
	var player := _player(AIR)
	var blocker := _player(AIR)
	_check(not player.blocked_air_move(), "an unsimulated airborne spawn is not a completed hard stop")
	_start()
	await physics_frame
	player.config.source_deadstrafe = false
	player.velocity = Vector3.RIGHT * 250.0
	player.wish_dir = Vector3.FORWARD
	player.wish_speed = 250.0
	player.simulate(DT)
	_vector_near(player.position, AIR, "a deeply overlapping real player prevents motion")
	_vector_near(player.velocity, Vector3.ZERO, "a blocked start clears velocity, including trailing air and gravity")
	_vector_near(player._deferred_velocity, Vector3.ZERO, "a hard stop clears deferred velocity")
	_vector_near(player._move_acceleration, Vector3.ZERO, "a hard stop clears continuous acceleration")
	var queries := PhysicsQueries.native_queries + PhysicsQueries.legacy_queries
	_check(player.blocked_air_move(), "a completed unsupported hard stop is available to bot recovery")
	_check_equal(PhysicsQueries.native_queries + PhysicsQueries.legacy_queries, queries,
		"classifying a completed hard stop adds no collision query")
	player.noclip = true
	_check(not player.blocked_air_move(), "noclip is excluded from collision-stall recovery")
	player.noclip = false
	player.config.gravity = 0.0
	_check(not player.blocked_air_move(), "zero gravity is excluded from collision-stall recovery")
	player.config.gravity = 800.0
	blocker.position.x += 128.0
	PhysicsQueries.sync_object(blocker)
	player.velocity = Vector3.RIGHT * 250.0
	player.simulate(DT)
	_check_near(player.position.x - AIR.x, 250.0 * DT, "removing the blocker releases the very next command")
	_check_near(player.velocity.z, -30.0, "released movement gets a fresh air allowance")
	_check(not player.blocked_air_move(), "the next completed move clears the recovery classification after release")
	_close()
	await process_frame


func _test_query_bounds() -> void:
	_setup()
	var player := _player(START)
	_start()
	await physics_frame
	_settle(player)
	var traces := player.traces
	var eyes := player.ground_eyes.queries
	player.simulate(DT)
	_check_equal(player.traces - traces - (player.ground_eyes.queries - eyes), 1,
		"a settled idle tick keeps its one movement probe")
	player.wish_dir = Vector3.RIGHT
	player.wish_speed = 250.0
	var most := 0
	var most_eyes := 0
	for tick in 8:
		traces = player.traces
		eyes = player.ground_eyes.queries
		player.simulate(DT)
		var eye_delta := player.ground_eyes.queries - eyes
		most = maxi(most, player.traces - traces - eye_delta)
		most_eyes = maxi(most_eyes, eye_delta)
	_check(most <= 2, "continuous ground integration keeps at most two movement traces (%d)" % most)
	_check(most_eyes <= 5, "the same open run adds at most one row of terrain samples (%d)" % most_eyes)
	_close()
	await process_frame


func _vector_near(actual: Vector3, expected: Vector3, label: String, tolerance: float = 0.0002) -> void:
	_check(actual.distance_to(expected) <= tolerance,
		label if actual.distance_to(expected) <= tolerance else "%s (expected %s, got %s)" % [label, expected, actual])


func _setup() -> void:
	_host = Node3D.new()
	root.add_child(_host)
	_box(Vector3(0.0, -8.0, 0.0), Vector3(2048.0, 16.0, 2048.0))


func _start() -> void:
	_world = GameWorld.new()
	_host.add_child(_world)
	_world.set_physics_process(false)
	_world.initialize_drop_physics(_host, "box3d")


func _settle(player: PlayerBody) -> void:
	for tick in 16:
		player.simulate(DT)
	_check(player.on_ground, "the numeric fixture settled on Box3D")
	player.config.gravity = 0.0
	player.config.source_deadstrafe = false


func _close() -> void:
	_host.free()


func _box(at: Vector3, size: Vector3) -> void:
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
