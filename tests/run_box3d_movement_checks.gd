extends "res://tests/check_suite.gd"

## Native query integration under the existing Source movement solver.
## The general movement suite covers its course, jumps, stairs and surf;
## these fixtures exercise native self exclusion, query tolerance, test-only
## traces, duck resizing and same-tick player proxy movement.
## godot --headless --path . --script tests/run_box3d_movement_checks.gd

var _host: Node3D
var _world: GameWorld
var DT := SimClock.tick_seconds()


## A controlled corner contact: a quarter-inch floor correction followed
## by a wall halfway through a much smaller commanded move. The second
## trace observes the actual remaining slide chosen by TryPlayerMove.
class RecoveryTraceBody:
	extends PlayerBody
	var motions: Array[Vector3] = []
	var blocked_after_first := false

	func _trace(motion: Vector3, test_only: bool = false) -> PlayerBody.TraceResult:
		motions.append(motion)
		if motions.size() == 1:
			var recovery := Vector3.UP * 0.25
			var travel := recovery + motion * 0.5
			if not test_only:
				global_position += travel
			return PlayerBody.TraceResult.new(travel, Vector3.RIGHT, recovery)
		if blocked_after_first:
			return PlayerBody.TraceResult.new(Vector3.ZERO, Vector3.ZERO)
		if not test_only:
			global_position += motion
		return null


func _initialize() -> void:
	if not Box3DDrops.available():
		_skip("box3d-movement", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	await physics_frame
	_check_recovery_slide_time()
	_check_blocked_after_progress()
	await _check_traces()
	await _check_floor_wall_spawn()
	await _check_small_ground_recovery()
	await _check_duck_clearance()
	await _check_player_blocking()
	await _check_blocked_crowd_budget()
	await _check_shallow_player_recovery()
	await _check_steps_and_jump()
	await _check_ramps()
	_finish("box3d-movement")


func _print_passes() -> bool:
	return true


func _check_recovery_slide_time() -> void:
	var player := RecoveryTraceBody.new()
	root.add_child(player)
	player.velocity = Vector3(-1.0, 0.0, 1.0)
	player._try_player_move(DT)
	_check(player.motions.size() == 2
		and player.motions[1].is_equal_approx(Vector3.BACK * DT * 0.5)
		and is_equal_approx(player.position.z, DT)
		and is_equal_approx(player.position.y, 0.25),
		"overlap recovery greater than a low-speed move keeps the full remaining forward slide, without consuming time or reversing it")
	player.free()


func _check_blocked_after_progress() -> void:
	var player := RecoveryTraceBody.new()
	player.blocked_after_first = true
	root.add_child(player)
	player.velocity = Vector3(-1.0, 0.0, 1.0)
	player._try_player_move(DT)
	_check(player.motions.size() == 2 and player.velocity == Vector3.BACK
		and player.position.is_equal_approx(Vector3(-DT * 0.5, 0.25, DT * 0.5)),
		"an unresolved overlap after a partial slide preserves prior travel and clipped velocity without repeating the blocked sweep")
	player.free()


func _check_traces() -> void:
	_setup()
	_box(Vector3(128.0, 100.0, 0.0), Vector3(16.0, 200.0, 256.0))
	var clip := _box(Vector3(0.0, 20.0, 128.0), Vector3(256.0, 40.0, 16.0))
	clip.collision_layer = MapImporter.PLAYER_CLIP_LAYER
	var player := _player(Vector3.ZERO)
	_start()
	await physics_frame
	_check(PhysicsQueries.adapter_for_node(player) != null,
		"the fixture's movement queries use its native world")
	var native_before := PhysicsQueries.native_queries
	var legacy_before := PhysicsQueries.legacy_queries
	for tick in 24:
		player.simulate(DT)
	# Native sweeps retain about a quarter inch of clearance, documented in
	# PlayerBody; do not mistake that tolerance for an inch/metre scale error.
	_check(player.on_ground and player.position.y >= -0.01 and player.position.y < 0.5,
		"a spawn exactly on the floor recovers and settles within native query clearance")
	var before := player.position
	var traces_before := player.traces
	var hit := player._trace(Vector3.RIGHT * 200.0, true)
	_check(hit != null and hit.get_normal().x < -0.99 and absf(hit.get_travel().x - 104.0) < 0.5
		and player.position == before and player.traces == traces_before + 1,
		"a test-only wall trace keeps position, ignores its own body, and reports Source-unit travel")
	hit = player._trace(Vector3.RIGHT * 200.0)
	_check(hit != null and player.position.is_equal_approx(before + hit.get_travel()),
		"the real trace moves by the same safe travel as the test trace")
	hit = player._trace(Vector3.LEFT * 32.0)
	_check(hit == null and player.position.x < 73.0,
		"the next sweep can move away from a wall while tangent to its floor")
	var height := GroundProbe.height_below(_host.get_world_3d().direct_space_state,
		Vector3(0.0, 40.0, 0.0), 64.0, [player.get_rid()])
	_check(absf(height - 40.0) < 0.05, "the native ground ray returns height in Source units")
	hit = player._trace(Vector3.BACK * 200.0, true)
	_check(hit != null and hit.get_normal().z < -0.99 and absf(hit.get_travel().z - 104.0) < 0.5,
		"native player-clip geometry blocks the movement hull")
	height = GroundProbe.height_below(_host.get_world_3d().direct_space_state,
		Vector3(0.0, 80.0, 128.0), 100.0)
	_check(absf(height - 80.0) < 0.05, "the ground-height ray sees through player clips to the real floor")
	_check(PhysicsQueries.native_queries > native_before and PhysicsQueries.legacy_queries == legacy_before,
		"the fixture's movement and ground queries never fall back to the Godot physics server")
	_close()
	await process_frame


func _check_floor_wall_spawn() -> void:
	_setup()
	_box(Vector3(128.0, 100.0, 0.0), Vector3(16.0, 200.0, 256.0))
	var player := _player(Vector3(104.0, 0.0, 0.0))
	_start()
	await physics_frame
	for tick in 24:
		player.simulate(DT)
	var before := player.position
	player._trace(Vector3.FORWARD * 16.0)
	_check(player.on_ground and before.y >= 0.0 and before.y < 0.5
		and before.x > 103.5 and before.x < 104.0 and player.position.z < -15.9,
		"a spawn touching both floor and wall recovers locally and can slide along their corner")
	_close()
	await process_frame


func _check_small_ground_recovery() -> void:
	_setup()
	# Inside native initial-contact tolerance by less than Source's 0.03-inch
	# ground-snap threshold: separation still has to survive the probe reset.
	var player := _player(Vector3.UP * 0.23)
	_start()
	await physics_frame
	player._stay_on_ground()
	var before := player.position
	var traces := player.traces
	var hit := player._trace(Vector3.RIGHT * 16.0, true)
	_check(before.y > 0.25 and before.y < 0.5 and hit == null
		and player.position == before and player.traces == traces + 1,
		"a sub-threshold floor recovery survives ground probing and leaves a one-cast tangential sweep")
	_close()
	await process_frame


func _check_duck_clearance() -> void:
	_setup()
	_box(Vector3(128.0, 70.0, 0.0), Vector3(128.0, 20.0, 128.0))
	var player := _player(Vector3.ZERO)
	_start()
	await physics_frame
	for tick in 24:
		player.simulate(DT)
	player.wants_duck = true
	for tick in 40:
		player.simulate(DT)
	_check(player.is_ducked, "the grounded player reaches the shorter native duck hull")
	var passage := player._trace(Vector3.RIGHT * 128.0)
	_check(passage == null and player.position.x > 127.9,
		"the resized duck hull fits under a sixty-inch ceiling")
	player.wants_duck = false
	for tick in 4:
		player.simulate(DT)
	_check(player.is_ducked and player.duck_progress == 1.0,
		"a blocked upward sweep prevents standing through the ceiling")
	player._trace(Vector3.LEFT * 128.0)
	for tick in 40:
		player.simulate(DT)
	_check(not player.is_ducked and player.on_ground and player.position.y < 0.5,
		"leaving the ceiling restores the standing hull while keeping the feet grounded")
	_close()
	await process_frame


func _check_player_blocking() -> void:
	_setup()
	var first := _player(Vector3.ZERO)
	var second := _player(Vector3(128.0, 0.0, 0.0))
	_start()
	await physics_frame
	for tick in 24:
		first.simulate(DT)
		second.simulate(DT)
	var hit := first._trace(Vector3.RIGHT * 300.0, true)
	_check(hit != null and absf(hit.get_travel().x - 96.0) < 0.5,
		"another player's native hull blocks movement at the combined half-widths")
	var reverse := second._trace(Vector3.LEFT * 300.0, true)
	_check(reverse != null and absf(reverse.get_travel().x + 96.0) < 0.5,
		"a test-only hit restores the querying player's collision for the next player's sweep")
	second._trace(Vector3.RIGHT * 64.0)
	hit = first._trace(Vector3.RIGHT * 300.0, true)
	_check(hit != null and absf(hit.get_travel().x - 160.0) < 0.5,
		"a later query in the same tick sees the other player's completed move")
	_close()
	await process_frame


func _check_blocked_crowd_budget() -> void:
	_setup()
	var first := _player(Vector3.ZERO)
	var second := _player(Vector3(128.0, 0.0, 0.0))
	_start()
	await physics_frame
	for tick in 24:
		first.simulate(DT)
		second.simulate(DT)
	# A crowded spawn can overlap farther than the half-inch local recovery
	# is allowed to move. Repeating that same recovery cannot release it.
	second.global_position = first.global_position
	PhysicsQueries.sync_object(second)
	var before := first.global_position
	var traces := first.traces
	var native_queries := PhysicsQueries.native_queries
	var legacy_queries := PhysicsQueries.legacy_queries
	first.velocity = Vector3.FORWARD * 250.0
	var blocked := first._try_player_move(DT)
	_check(blocked and first.global_position == before and first.velocity == Vector3.ZERO
		and first.traces == traces + 1,
		"a deeply overlapping player box stops safely after one native cast (%d traces)" % (first.traces - traces))
	_check(PhysicsQueries.native_queries - native_queries == first.traces - traces
		and PhysicsQueries.legacy_queries == legacy_queries,
		"the deep-overlap cast remains counted as a native query, with no legacy fallback")
	var query := PhysicsRayQueryParameters3D.create(before + Vector3(-64.0, 36.0, 0.0),
		before + Vector3(64.0, 36.0, 0.0), 2, [second.get_rid()])
	var seen := PhysicsQueries.intersect_ray(_host.get_world_3d().direct_space_state, query)
	_check(seen.get("collider") == first,
		"a failed recovery restores the player's native collision before another query")
	# A failed move is not cached across changing world state: a later player
	# leaving must make the next move possible in this same simulation tick.
	second.global_position += Vector3.RIGHT * 128.0
	PhysicsQueries.sync_object(second)
	traces = first.traces
	first.velocity = Vector3.FORWARD * 250.0
	blocked = first._try_player_move(DT)
	_check(not blocked and first.global_position.is_equal_approx(before + Vector3.FORWARD * 250.0 * DT)
		and first.traces == traces + 1,
		"a blocked player moves immediately with one trace after the crowd clears")
	query.from = first.global_position + Vector3(-64.0, 36.0, 0.0)
	query.to = first.global_position + Vector3(64.0, 36.0, 0.0)
	seen = PhysicsQueries.intersect_ray(_host.get_world_3d().direct_space_state, query)
	_check(seen.get("collider") == first,
		"an unobstructed move restores collision and publishes its new native hull pose")
	_close()
	await process_frame


func _check_shallow_player_recovery() -> void:
	_setup()
	var first := _player(Vector3.ZERO)
	var second := _player(Vector3(128.0, 0.0, 0.0))
	_start()
	await physics_frame
	for tick in 24:
		first.simulate(DT)
		second.simulate(DT)
	# The hulls overlap by 0.1 inch: the existing bounded recovery can clear
	# that plus native contact tolerance, so the deep-overlap proof must not
	# reject it. A test-only sweep must still leave the real hull in place.
	second.global_position = first.global_position + Vector3.RIGHT * 31.9
	PhysicsQueries.sync_object(second)
	var before := first.global_position
	var traces := first.traces
	var native_queries := PhysicsQueries.native_queries
	var hit := first._trace(Vector3.LEFT * 16.0, true)
	var recovery := first._last_native_trace_recovery
	_check(hit == null and first.global_position == before and first.traces > traces + 1
		and PhysicsQueries.native_queries - native_queries == first.traces - traces
		and recovery.x < -0.1 and recovery.x > -PlayerBody.NATIVE_RECOVERY_REACH
		and is_zero_approx(recovery.y) and is_zero_approx(recovery.z),
		"a shallow player overlap counts every recovery cast and keeps a test-only hull in place")
	hit = first._trace(Vector3.LEFT * 16.0)
	_check(hit == null and first.global_position.is_equal_approx(before + recovery + Vector3.LEFT * 16.0),
		"the real shallow-overlap move applies only the verified local recovery and requested motion")
	_close()
	await process_frame


func _check_steps_and_jump() -> void:
	_setup()
	_box(Vector3(132.0, 8.0, 0.0), Vector3(136.0, 16.0, 128.0))
	var player := _player(Vector3.ZERO)
	_start()
	await physics_frame
	for tick in 24:
		player.simulate(DT)
	player.wish_dir = Vector3.RIGHT
	player.wish_speed = player.config.max_speed
	var highest := player.position.y
	for tick in 40:
		player.simulate(DT)
		highest = maxf(highest, player.position.y)
	_check(player.position.x > 100.0 and highest > 15.9 and highest < 16.5 and player.on_ground,
		"the unchanged step solver climbs a sixteen-inch obstacle using native sweeps")
	player.wish_dir = Vector3.ZERO
	player.wish_speed = 0.0
	player.velocity = Vector3.ZERO
	var start_y := player.position.y
	var peak := start_y
	player.wants_jump = true
	player.simulate(DT)
	player.wants_jump = false
	for tick in 60:
		player.simulate(DT)
		peak = maxf(peak, player.position.y)
	_check(peak - start_y > 58.0 and peak - start_y < 60.0 and player.on_ground,
		"native sweeps preserve the Source jump arc and landing")
	_close()
	await process_frame


func _check_ramps() -> void:
	for angle in [30.0, 60.0]:
		_setup()
		var rotation := Basis(Vector3.BACK, deg_to_rad(angle))
		var ramp := _box(Vector3.UP * 200.0 - rotation.y * 8.0, Vector3(512.0, 16.0, 256.0))
		ramp.basis = rotation
		var x := -100.0 if angle == 30.0 else -60.0
		var top := 200.0 + (x + 16.0) * tan(deg_to_rad(angle))
		var player := _player(Vector3(x, top + 12.0, 0.0))
		_start()
		await physics_frame
		for tick in (24 if angle == 30.0 else 12):
			player.simulate(DT)
		var before := player.position
		if angle == 30.0:
			player.wish_dir = Vector3.RIGHT
			player.wish_speed = player.config.max_speed
			var grounded := 0
			var most_traces := 0
			for tick in 48:
				var traces := player.traces
				player.simulate(DT)
				most_traces = maxi(most_traces, player.traces - traces)
				if player.on_ground:
					grounded += 1
			_check(player.position.x > before.x + 100.0 and player.position.y > before.y + 50.0
				and grounded == 48 and most_traces <= 10,
				"a walkable native ramp keeps its slope, ground contact and ordinary trace budget (%d traces)" % most_traces)
		else:
			# The steep plane remains airborne; gravity clips along it rather
			# than classifying it as ground or trapping the next native cast.
			player.velocity.z = -120.0
			for tick in 16:
				player.simulate(DT)
			_check(not player.on_ground and player.position.y < before.y - 15.0
				and player.position.z < before.z - 20.0,
				"the Source solver keeps sliding and falling along a steep native surf ramp")
		_close()
		await process_frame


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
