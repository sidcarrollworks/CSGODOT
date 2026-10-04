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
	await _check_gentle_slopes()
	await _check_slope_beside()
	await _check_lips()
	await _check_under_a_friend()
	await _check_sweep_contract()
	await _check_other_sweeps()
	await _check_respawn_in_a_tick()
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
	# Inside the tolerance a hull is in overlap from (0.12, the sweep's
	# shape being an eighth smaller all round), and once clear of it within
	# Source's 0.03-inch ground-snap threshold of where it rests: the
	# separation still has to survive the probe reset.
	var player := _player(Vector3.UP * 0.1)
	_start()
	await physics_frame
	player._stay_on_ground()
	var before := player.position
	var traces := player.traces
	var hit := player._trace(Vector3.RIGHT * 16.0, true)
	_check(before.y > 0.2 and before.y < 0.5 and hit == null
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
	# The audited CS2 take-off and restored leading half-gravity give a
	# 55.8255-inch sampled arc at 64 Hz, rather than the legacy Source arc.
	_check(absf(peak - start_y - 55.8255) < 0.02 and player.on_ground,
		"native sweeps preserve the CS2 jump arc and landing (peak %.6f, ground %s)" % [peak - start_y, player.on_ground])
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


## Floors rising a few degrees, as dust2's do everywhere: walked up at a
## run, a hull keeps its speed, stays on the ground and spends an ordinary
## tick's traces (playtest issue 26: a move grazing the floor ahead backed
## off further than it went, the step that should have saved it found no
## floor on its way down, and the hull stopped dead for a tick).
func _check_gentle_slopes() -> void:
	for angle: float in [1.0, 2.0, 3.0, 5.0]:
		_setup()
		var rotation := Basis(Vector3.BACK, deg_to_rad(angle))
		# Its top through the origin, rising toward +x from the flat floor.
		var ramp := _box(-rotation.y * 8.0, Vector3(1024.0, 16.0, 256.0))
		ramp.basis = rotation
		var player := _player(Vector3(-60.0, 1.0, 0.0))
		_start()
		await physics_frame
		for tick in 24:
			player.simulate(DT)
		player.wish_dir = Vector3.RIGHT
		player.wish_speed = player.config.max_speed
		var slowest := INF
		var grounded := 0
		var most_traces := 0
		var ticks := 96
		for tick in ticks:
			var traces := player.traces
			player.simulate(DT)
			most_traces = maxi(most_traces, player.traces - traces)
			if player.on_ground:
				grounded += 1
			# Up to speed, and on the slope, by then.
			if tick >= 32:
				slowest = minf(slowest, Vector2(player.velocity.x, player.velocity.z).length())
		# Its uphill edge is what rests on the slope.
		var over := player.position.y - (player.position.x + 16.0) * tan(deg_to_rad(angle))
		_check(slowest > 0.9 * player.config.max_speed and player.position.x > 250.0 and grounded == ticks
			and most_traces <= 10 and over > 0.0 and over < 0.6,
			"a floor rising %d degrees is walked up at a run: never under %.0f u/s, on the ground, %.2f over it, %d traces a tick at most" % [
				int(angle), slowest, over, most_traces])
		_close()
		await process_frame


## A floor rising to one side of the way walked, met a few degrees off
## its foot: where dust2 stopped a hull dead (playtest issue 26). The move
## comes at the slope's plane so shallowly that its clearance, taken along
## the motion, was more than the whole move.
func _check_slope_beside() -> void:
	for drift: float in [1.0, 2.0, 5.0, 10.0]:
		_setup()
		var rotation := Basis(Vector3.BACK, deg_to_rad(4.0))
		# Rising toward +x from the line x = 0 on the flat floor.
		var slope := _box(-rotation.y * 8.0 + Vector3.FORWARD * 400.0, Vector3(1024.0, 16.0, 2048.0))
		slope.basis = rotation
		var player := _player(Vector3(-30.0, 1.0, 0.0))
		_start()
		await physics_frame
		for tick in 24:
			player.simulate(DT)
		# Along the slope's foot, -z, and a little toward it.
		player.wish_dir = Vector3.FORWARD.rotated(Vector3.UP, -deg_to_rad(drift))
		player.wish_speed = player.config.max_speed
		var slowest := INF
		var slowest_at := -1
		var grounded := 0
		var most_traces := 0
		var most_eye_traces := 0
		var ticks := 192
		for tick in ticks:
			var traces := player.traces
			var eye_traces := player.ground_eyes.queries
			player.simulate(DT)
			var eye_delta := player.ground_eyes.queries - eye_traces
			most_eye_traces = maxi(most_eye_traces, eye_delta)
			most_traces = maxi(most_traces, player.traces - traces - eye_delta)
			if player.on_ground:
				grounded += 1
			var speed := Vector2(player.velocity.x, player.velocity.z).length()
			if tick >= 32 and speed < slowest:
				slowest = speed
				slowest_at = tick
		# Keep the movement budget independent of the new terrain sampler.
		# Near the slope's edge failed cells can retry, up to the 5x5 grid.
		_check(slowest > 0.9 * player.config.max_speed and grounded == ticks and most_traces <= 10 and most_eye_traces <= 25
			and player.position.z < -600.0,
			"a slope beside the way, met %d degrees off its foot, is walked along at a run: never under %.0f u/s (tick %d), at most %d movement + %d terrain traces a tick, to x %.1f" % [
				int(drift), slowest, slowest_at, most_traces, most_eye_traces, player.position.x])
		_close()
		await process_frame


## A level floor of triangles a fraction higher than the last, as dust2's
## floors meet: Box3D's sweep only looks at a triangle the swept hull
## reaches the plane of, so a level move does not meet it and ends a hair
## over it, or in it. Staying on the ground sweeps down from a unit up
## (STAY_ON_GROUND_LIFT), so it lands on the higher floor in one cast, at
## its clearance, and the walk goes on at a run.
func _check_lips() -> void:
	for lip: float in [0.05, 0.2, 0.5]:
		# The most traces a tick: the move and the floor's sweep, and two
		# more where the lip is deeper than the hull's clearance and the
		# hull has to get clear of it.
		var budget := 2 if lip < 0.25 else 4
		_host = Node3D.new()
		root.add_child(_host)
		_triangles(-1024.0, 0.0, 0.0)
		_triangles(0.0, 1024.0, lip)
		var player := _player(Vector3(-100.0, 1.0, 0.0))
		_start()
		await physics_frame
		for tick in 24:
			player.simulate(DT)
		player.wish_dir = Vector3.RIGHT
		player.wish_speed = player.config.max_speed
		var slowest := INF
		var grounded := 0
		var most_traces := 0
		var most_eye_traces := 0
		var ticks := 96
		for tick in ticks:
			var traces := player.traces
			var eye_traces := player.ground_eyes.queries
			player.simulate(DT)
			var eye_delta := player.ground_eyes.queries - eye_traces
			most_eye_traces = maxi(most_eye_traces, eye_delta)
			most_traces = maxi(most_traces, player.traces - traces - eye_delta)
			if player.on_ground:
				grounded += 1
			if tick >= 32:
				slowest = minf(slowest, Vector2(player.velocity.x, player.velocity.z).length())
		var over := player.position.y - lip
		_check(slowest > 0.9 * player.config.max_speed and player.position.x > 150.0 and grounded == ticks
			and most_traces <= budget and most_eye_traces <= 5 and over > 0.2 and over < 0.3,
			"a level floor %.2f higher is walked onto at a run: never under %.0f u/s, on the ground, %.3f over it, at most %d movement + %d terrain traces a tick" % [
				lip, slowest, over, most_traces, most_eye_traces])
		_close()
		await process_frame


## Someone standing on a player's head, as a boost has them and as bots
## walking a stair end up: the one underneath rests its clearance over the
## floor and the one on top its clearance over the head under it, and the
## one underneath walks out from under at a run. Box3D's overlap band is
## nearly that clearance deep, and with a whole hull swept it held the one
## underneath between the two, going nowhere.
func _check_under_a_friend() -> void:
	_host = Node3D.new()
	root.add_child(_host)
	_triangles(-1024.0, 1024.0, 0.0)
	var under := _player(Vector3(0.0, 1.0, 0.0))
	var over := _player(Vector3(6.0, 80.0, 4.0))
	_start()
	await physics_frame
	for tick in 48:
		under.simulate(DT)
		over.simulate(DT)
	var stood := over.position.y - (under.position.y + 72.0)
	_check(under.on_ground and over.on_ground and stood > 0.2 and stood < 0.3,
		"a player comes to rest on another's head, its clearance over it (%.3f)" % stood)
	# As dust2 left the one underneath when it stopped dead: 0.21 over the
	# floor, a little under where it rests, the other as far over its head
	# as before.
	under.position.y -= 0.045
	over.position.y -= 0.045
	PhysicsQueries.sync_object(under, false)
	PhysicsQueries.sync_object(over, false)
	under.wish_dir = Vector3.RIGHT
	under.wish_speed = under.config.max_speed
	var most_traces := 0
	var stalled := 0
	for tick in 32:
		var before := under.position
		var traces := under.traces
		under.simulate(DT)
		over.simulate(DT)
		most_traces = maxi(most_traces, under.traces - traces)
		if tick >= 2 and under.position.distance_to(before) < 0.01:
			stalled += 1
	_check(under.position.x > 60.0 and stalled == 0 and most_traces <= 10,
		"the one underneath walks out from under at a run (to x %.1f, stalled %d ticks, %d traces a tick at most)" % [
			under.position.x, stalled, most_traces])
	_close()
	await process_frame


## A level floor of triangles from x = from to x = to, at a height, facing
## up: squares of 64 units, two triangles each, as a map's floor is.
func _triangles(from: float, to: float, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var faces := PackedVector3Array()
	var x := from
	while x < to:
		for iz in range(-4, 4):
			var a := Vector3(x, height, iz * 64.0)
			var b := Vector3(x + 64.0, height, iz * 64.0)
			var c := Vector3(x + 64.0, height, (iz + 1) * 64.0)
			var d := Vector3(x, height, (iz + 1) * 64.0)
			faces.append_array([a, b, c, a, c, d])
		x += 64.0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	_host.add_child(body)
	return body


## What a native sweep hands back (Box3DQueries.shape_cast_prepared): a
## motion that would end inside the contact band without touching is a hit,
## stopped with its clearance; one that ends clear of the band is none; and
## one grazing a floor goes on, pushed off the floor for its clearance.
func _check_sweep_contract() -> void:
	_setup()
	_start()
	await physics_frame
	var shape := BoxShape3D.new()
	shape.size = Vector3(32.0, 72.0, 32.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.margin = PlayerBody.NATIVE_QUERY_MARGIN
	# Its feet an inch over the floor, down 0.9: it would end a tenth over.
	query.transform.origin = Vector3(0.0, 37.0, 0.0)
	query.motion = Vector3.DOWN * 0.9
	var near := _hull_sweep(query)
	var rest := 1.0 - 0.9 * float(near.get("fraction", 1.0))
	_check(not near.is_empty() and rest > 0.24 and rest < 0.28
		and (near.get("normal", Vector3.ZERO) as Vector3).is_equal_approx(Vector3.UP)
		and (near.get("offset", Vector3.ONE) as Vector3) == Vector3.ZERO,
		"a sweep that would end inside the contact band stops with its clearance (%.3f over the floor)" % rest)
	query.motion = Vector3.DOWN * 0.5
	_check(_hull_sweep(query).is_empty(),
		"a sweep that ends clear of the band meets nothing")
	# Along the floor and a little into it: four units on and three tenths
	# down, from 0.3 over.
	query.transform.origin = Vector3(0.0, 36.3, 0.0)
	query.motion = Vector3(4.0, -0.3, 0.0)
	var grazing := _hull_sweep(query)
	var fraction := float(grazing.get("fraction", 0.0))
	var offset: Vector3 = grazing.get("offset", Vector3.ZERO)
	var over := 0.3 - 0.3 * fraction + offset.y
	_check(not grazing.is_empty() and fraction > 0.5 and fraction <= 1.0 and offset.y > 0.0
		and is_zero_approx(offset.x) and is_zero_approx(offset.z) and over > 0.24 and over < 0.28,
		"a sweep grazing the floor goes on (%.2f of its motion) and is pushed off it for its clearance (%.3f over)" % [fraction, over])
	_close()
	await process_frame


## What anything but a hull sweeps with (PhysicsQueries.cast_motion: a
## grenade, a dropped item, handed two fractions and nothing else): it
## stops its clearance off where the native cast stopped, backed off along
## the motion however shallowly it came, with no push to take besides, and
## a motion that ends short of that meets nothing. The native cast stops
## a box 0.197 short of touching and a sphere 0.197 past it (v0.4.3), so a
## grenade rests 0.137 into a floor and a dropped box 0.257 over it.
func _check_other_sweeps() -> void:
	_setup()
	_start()
	await physics_frame
	var space := _host.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = GrenadeRules.RADIUS
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 4.0, 16.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	for shape: Shape3D in [sphere, box]:
		query.shape = shape
		var half := GrenadeRules.RADIUS
		var rests := -0.137 if shape == sphere else 0.257
		var named := "a grenade's" if shape == sphere else "a dropped box's"
		for motion: Vector3 in [Vector3(0.0, -2.0, 0.0), Vector3(4.0, -2.0, 0.0), Vector3(24.0, -2.0, 0.0), Vector3(30.0, -1.5, 0.0)]:
			query.transform.origin = Vector3(-60.0, half + 1.0, 0.0)
			query.motion = motion
			var fractions := PhysicsQueries.cast_motion(space, query)
			var met := PhysicsQueries.shape_cast(space, query)
			var over := 1.0 + motion.y * fractions[0]
			_check(fractions[1] < 1.0 and fractions[0] < fractions[1] and absf(over - rests) < 0.01
				and not met.has("offset") and (met.get("normal", Vector3.ZERO) as Vector3).is_equal_approx(Vector3.UP),
				"%s sweep %s into the floor stops its clearance off where the native cast did (%.3f over), with no push to take" % [
					named, motion, over])
		# A tenth short of where the native cast would stop.
		query.transform.origin = Vector3(0.0, half + 1.0, 0.0)
		query.motion = Vector3(4.0, -(1.0 - rests - 0.06 - 0.1), 0.0)
		var short := PhysicsQueries.cast_motion(space, query)
		_check(short[0] == 1.0 and short[1] == 1.0 and PhysicsQueries.shape_cast(space, query).is_empty(),
			"%s sweep that ends short of there meets nothing" % named)
	_close()
	await process_frame


## A bot that walks a route and was given no spawn point comes back at the
## route's start (Bot.respawn), in a tick, after the tick's one look at the
## hulls: whoever sweeps or shoots later in that tick finds it there, and
## not where it died.
func _check_respawn_in_a_tick() -> void:
	_setup()
	var bot := (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	bot.route = PackedVector3Array([Vector3(200.0, 1.0, 0.0), Vector3(400.0, 1.0, 0.0)])
	bot.position = Vector3(0.0, 1.0, 0.0)
	_host.add_child(bot)
	_start()
	_world.add_player(bot)
	await physics_frame
	var space := _host.get_world_3d().direct_space_state
	var queries := PhysicsQueries.for_space(space)
	var across := func(at: Vector3) -> Dictionary:
		return PhysicsQueries.intersect_ray(space, PhysicsRayQueryParameters3D.create(
			at + Vector3(0.0, 36.0, 64.0), at + Vector3(0.0, 36.0, -64.0), PlayerSim.PLAYER_LAYER))
	queries.begin_tick()
	var died_at := bot.global_position
	_check(across.call(died_at).get("collider") == bot, "the tick's first look finds the bot where it stands")
	bot.respawn()
	_check(bot.global_position.is_equal_approx(bot.route[0])
		and across.call(bot.route[0]).get("collider") == bot and across.call(died_at).is_empty(),
		"a bot back at its route's start is found there by the same tick's queries, and not where it died")
	queries.end_tick()
	_close()
	await process_frame


## The hull's sweep, asked of the bridge as the movement asks it.
func _hull_sweep(query: PhysicsShapeQueryParameters3D) -> Dictionary:
	var queries := PhysicsQueries.for_space(_host.get_world_3d().direct_space_state)
	var disabled := queries.begin_shape_cast(query)
	var hit := queries.shape_cast_prepared(query)
	queries.end_shape_cast(disabled)
	return hit


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
