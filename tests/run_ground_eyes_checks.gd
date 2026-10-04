extends "res://tests/check_suite.gd"

## Topology changes the simulated eyes, not the collision hull. These
## oracles use flat planes, their analytic slope, and isolated full steps;
## they do not compare the sampler with a second copy of its algorithm.
## Physical cases use Box3D, including a zero-height square over triangles.
const DT := 1.0 / 64.0
const ANGLE := 20.0
var _host: Node3D
var _adapter: Box3DDrops
var _game: GameSystems


func _initialize() -> void:
	_check_analytic_planes()
	_check_discontinuous_support()
	if not Box3DDrops.available():
		print("Physical terrain-eye cases require the patched Box3D addon.")
		_finish("ground-eyes")
		return
	await physics_frame
	await _check_native_square()
	await _check_physical_planes()
	await _check_raised_support()
	await _check_void_edge_budget()
	await _check_cache_and_transitions()
	await _check_world_support_gate()
	await _check_neighbor_exclusion()
	_finish("ground-eyes")


func _filled(height: float) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(25)
	heights.fill(height)
	return heights


func _check_analytic_planes() -> void:
	var first := Vector2i(-20, -20)
	_check_near(GroundEyes.compute_drop(Vector3(0, 10, 0), first, _filled(10)), 0.0,
		"a level support at the pawn origin keeps the base eye height")
	_check_near(GroundEyes.compute_drop(Vector3(0, 10, 0), first, _filled(7)), 3.0,
		"a uniform three-unit support gap becomes a three-unit root drop")
	_check_near(GroundEyes.compute_drop(Vector3.ZERO, first, _filled(INF)), 0.0,
		"missing terrain never invents a camera-height correction")
	_check(GroundEyes.quantized_position(Vector3(-0.004, 0.009, 8.001)).is_equal_approx(Vector3(-0.01, 0.0, 8.0)),
		"pawn quantization floors negative as well as positive coordinates to hundredths")
	_check_equal(GroundEyes.first_cell(Vector3.ZERO), Vector2i(-20, -20),
		"the grid retains the audited zero-coordinate boundary")
	_check_equal(GroundEyes.first_cell(Vector3(1, 0, -1)), Vector2i(-12, -20),
		"positive and negative positions select the correct audited first cells")
	# A 32-unit hull rests on a planar slope at its high edge, 16 units
	# from the center. Every 7.98-unit square sees its own high edge at
	# 3.99 units. Symmetric area weights remove the cell-center slope,
	# leaving exactly (16 - 3.99) * abs(tan(angle)).
	var slope := tan(deg_to_rad(ANGLE))
	var expected := (16.0 - 3.99) * slope
	for sign_value in [-1.0, 1.0]:
		for x in [0.0, 2.37, -2.37]:
			var q := Vector3(x, x * slope * sign_value + 16.0 * slope, 0.0)
			var start := GroundEyes.first_cell(q)
			var heights := _filled(0.0)
			for ix in 5:
				for iz in 5:
					heights[iz * 5 + ix] = (start.x + ix * 8.0) * slope * sign_value + 3.99 * slope
			_check(absf(GroundEyes.compute_drop(q, start, heights) - expected) < 0.0001,
				"analytic %.0f-degree slope has the area-weighted support drop at x=%.2f" % [ANGLE * sign_value, x])
	var eyes := GroundEyes.new()
	eyes.offset = -3.25
	_check_near(eyes.height(64.0), 60.75,
		"a 3.25-unit topology drop gives the supplied mid-door effective eye height")
	_check_near(eyes.height(46.0), 42.75,
		"the same topology state applies to the crouched base without a second terrain estimate")
	_check_near(eyes.height(64.0) - eyes.height(46.0), 18.0,
		"the standing/crouched base separation is preserved by shared root state")
	eyes.offset = -0.0625
	_check_near(eyes.height(64.0), 63.9375,
		"view quantization retains the B-doors reference's small eye deficit")
	eyes.offset = -0.01
	_check_near(eyes.height(64.0), 63.984375,
		"view offsets use float32 one-sixty-fourth precision")
	eyes.offset = -1.0 / 128.0
	_check_near(eyes.height(64.0), 64.0,
		"an exact half-quantum view tie rounds to its even upper value")
	eyes.offset = -3.0 / 128.0
	_check_near(eyes.height(64.0), 63.96875,
		"the next half-quantum view tie rounds to its even lower value")


func _check_discontinuous_support() -> void:
	var first := Vector2i(-20, -20)
	var heights := _filled(0.0)
	heights[12] = 18.0
	_check_near(GroundEyes.compute_drop(Vector3(-4, 18, -4), first, heights), 0.0,
		"a narrow full-height ledge excludes the lower disconnected floor from the eyes")
	# Joining cells one step lower must not pull the eyes halfway into the
	# riser. An ordinary 17-unit change is deliberately still connected.
	heights = _filled(0.0)
	for iz in 5:
		heights[iz * 5 + 2] = 18.0
		for ix in range(3, 5):
			heights[iz * 5 + ix] = 18.0
	_check_near(GroundEyes.compute_drop(Vector3(4, 18, -4), first, heights), 0.0,
		"the lower adjacent full step is not averaged into the supported plateau")
	for i in heights.size():
		if heights[i] == 18.0:
			heights[i] = 17.0
	var connected_drop := GroundEyes.compute_drop(Vector3(4, 17, -4), first, heights)
	_check(connected_drop > 0.0 and connected_drop < 17.0,
		"a height change below one full step remains connected for ordinary ramp and stair smoothing")
	heights[12] = INF
	_check(is_finite(GroundEyes.compute_drop(Vector3(4, 18, -4), first, heights)),
		"an invalid interior cell cannot poison connected support with INF or NaN")
	_check_near(GroundEyes.compute_drop(Vector3(0, 36, 0), first, _filled(0.0)), 0.0,
		"a floor beyond grounded step reach is not treated as a support correction")
	# Source X/Y become Godot Z/X. Equidistant, disconnected supports
	# must select the first Source-ordered sample, at (+4, -4), height 12.
	# The opposite diagonal is height 28; the surrounding height 46 is
	# unreachable from either seed (including the strict 18-unit boundary).
	heights = _filled(46.0)
	heights[13] = 12.0
	heights[17] = 28.0
	_check_near(GroundEyes.compute_drop(Vector3(0, 20, 0), first, heights), 8.0,
		"equidistant disconnected supports preserve Source X/Y order after mapping to Godot Z/X")


func _setup() -> void:
	_host = Node3D.new()
	root.add_child(_host)


func _start() -> bool:
	_adapter = Box3DDrops.new()
	_host.add_child(_adapter)
	_game = GameSystems.new()
	var initialized := _adapter.initialize(_game, _host, true)
	_check(initialized, "the terrain-eye fixture initializes native world collision")
	return initialized


func _close() -> void:
	_host.free()
	_host = null
	_adapter = null
	if _game != null:
		for system in _game.systems():
			if system is ItemDrops:
				system.game = null
	_game = null


func _box(at: Vector3, size: Vector3, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_host.add_child(body)
	return body


func _plane(angle: float, at: Vector3 = Vector3.ZERO, reach: float = 1024.0) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var slope := tan(deg_to_rad(angle))
	var a := Vector3(-reach, -reach * slope, -reach)
	var b := Vector3(reach, reach * slope, -reach)
	var c := Vector3(reach, reach * slope, reach)
	var d := Vector3(-reach, -reach * slope, reach)
	var geometry := ConcavePolygonShape3D.new()
	geometry.set_faces(PackedVector3Array([a, b, c, a, c, d]))
	var collision := CollisionShape3D.new()
	collision.shape = geometry
	body.add_child(collision)
	_host.add_child(body)


func _body(at: Vector3) -> PlayerBody:
	var body := PlayerBody.new()
	body.position = at
	body.collision_layer = 2
	body.collision_mask = 1 | 2 | MapImporter.PLAYER_CLIP_LAYER
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	_host.add_child(body)
	return body


func _query(from: Vector3, motion: Vector3, mask: int = 1) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	var thin := BoxShape3D.new()
	thin.size = Vector3(7.98, 0.002, 7.98)
	query.shape = thin
	query.transform.origin = from
	query.motion = motion
	query.collision_mask = mask
	query.margin = 0.0
	return query


func _check_native_square() -> void:
	_setup()
	var floor_body := _box(Vector3(0, -8, 0), Vector3(128, 16, 128))
	_plane(ANGLE, Vector3(200, 0, 0), 64.0)
	_plane(0.0, Vector3(600, 0, 0), 64.0)
	_box(Vector3(800, -8, 0), Vector3(128, 16, 128))
	_box(Vector3(800, 10, 0), Vector3(128, 2, 128), MapImporter.PLAYER_CLIP_LAYER)
	_box(Vector3(800, 20, 0), Vector3(128, 2, 128), GrenadeRules.GRENADE_CLIP_LAYER)
	_box(Vector3(800, 30, 0), Vector3(128, 2, 128), MapImporter.SKY_LAYER)
	if not _start():
		_close()
		return
	await physics_frame
	var space := _host.get_world_3d().direct_space_state
	var before := PhysicsQueries.native_queries
	var legacy_before := PhysicsQueries.legacy_queries
	for x in [0.0, 600.0]:
		var query := _query(Vector3(x, 40, 0), Vector3.DOWN * 80.0)
		var hit := PhysicsQueries.terrain_square(space, query)
		_check(not hit.is_empty() and not hit.get("blocked_start", false)
			and absf((hit.get("end", Vector3.INF) as Vector3).y) < 0.002,
			"a zero-height square samples the true flat surface over %s" % ("solid" if x == 0.0 else "triangles"))
		_check((hit.get("normal", Vector3.ZERO) as Vector3).y > 0.99,
			"the terrain square returns the upward floor plane")
	var slope_query := _query(Vector3(200, 40, 0), Vector3.DOWN * 80.0)
	var slope_hit := PhysicsQueries.terrain_square(space, slope_query)
	_check(not slope_hit.is_empty()
		and absf((slope_hit.get("end", Vector3.INF) as Vector3).y - 3.99 * tan(deg_to_rad(ANGLE))) < 0.002,
		"the square sees the slope's high corner rather than a center ray or movement clearance")
	_check(PhysicsQueries.native_queries - before == 3 and PhysicsQueries.legacy_queries == legacy_before,
		"each terrain sweep is counted once and never passes on an engine fallback")
	var exclusion := _query(Vector3(0, 40, 0), Vector3.DOWN * 80.0)
	exclusion.exclude = [floor_body.get_rid()]
	_check(PhysicsQueries.terrain_square(space, exclusion).is_empty(),
		"the terrain boundary honors original collider exclusions")
	exclusion.exclude = []
	_check(not PhysicsQueries.terrain_square(space, exclusion).is_empty(),
		"an exclusion is restored before the next terrain sweep")
	for mask in [1, MapImporter.PLAYER_CLIP_LAYER, GrenadeRules.GRENADE_CLIP_LAYER, MapImporter.SKY_LAYER]:
		var hit := PhysicsQueries.terrain_square(space, _query(Vector3(800, 40, 0), Vector3.DOWN * 80.0, mask))
		var expected := 0.0 if mask == 1 else (11.0 if mask == MapImporter.PLAYER_CLIP_LAYER else (21.0 if mask == GrenadeRules.GRENADE_CLIP_LAYER else 31.0))
		_check(not hit.is_empty() and absf((hit.get("end", Vector3.INF) as Vector3).y - expected) < 0.002,
			"terrain sweep collision flags select only the requested layer %d" % mask)
	var embedded := PhysicsQueries.terrain_square(space, _query(Vector3(0, -1, 0), Vector3.DOWN * 4.0))
	_check(not embedded.is_empty() and embedded.get("blocked_start", false),
		"an embedded zero-height square cannot invent a valid support plane")
	_check(PhysicsQueries.terrain_square(space, _query(Vector3(0, 0.01, 0), Vector3.UP * 4.0)).is_empty(),
		"a square leaving its floor does not create a false terrain contact")
	_close()
	await process_frame


func _check_physical_planes() -> void:
	var offsets: Array[float] = []
	for angle in [0.0, ANGLE, -ANGLE]:
		_setup()
		_plane(angle)
		var player := _body(Vector3(0, 24, 0))
		if not _start():
			_close()
			return
		await physics_frame
		for tick in 80:
			player.simulate(DT)
		var eye_world := player.global_position.y + player.eye_height()
		var expected := 64.0 + 3.99 * absf(tan(deg_to_rad(angle)))
		_check(player.on_ground and absf(eye_world - expected) < 0.08,
			"the actual %.0f-degree floor places shared eyes at its analytic sampled support (%.4f vs %.4f)" % [angle, eye_world, expected])
		_check(player.ground_eyes.using_topology and player.ground_eyes.offset <= 0.0,
			"grounded terrain state is completed by the body on the slope")
		offsets.append(player.ground_eyes.offset)
		var before := player.ground_eyes.queries
		var standing := player.eye_height()
		player.duck_progress = 1.0
		var ducked := player.eye_height()
		_check(absf(standing - ducked - 18.0) < 0.0001 and player.ground_eyes.queries == before,
			"standing and ducked eye getters read the same sampled slope state without querying")
		_close()
		await process_frame
	_check(absf(offsets[1] - offsets[2]) < 0.05,
		"opposite equal slopes produce symmetric camera drops")


func _check_raised_support() -> void:
	_setup()
	_box(Vector3(0, -8, 0), Vector3(256, 16, 256))
	_box(Vector3(-4, 10, -4), Vector3(8, 20, 8))
	var player := _body(Vector3(-4, 20, -4))
	if not _start():
		_close()
		return
	await physics_frame
	# A support above a full step is deliberately disconnected from the
	# surrounding floor. Sampling must retain the narrow support itself.
	player.on_ground = true
	player.ground_is_world = true
	for tick in 32:
		player.ground_eyes.update(player, DT)
	_check(absf(player.eye_height() - 64.0) < 0.03,
		"standing on a narrow raised ledge does not lower the eyes toward the disconnected floor")
	_close()
	await process_frame


func _check_cache_and_transitions() -> void:
	_setup()
	_plane(ANGLE)
	var slope := tan(deg_to_rad(ANGLE))
	var player := _body(Vector3(0, 16.0 * slope, 0))
	if not _start():
		_close()
		return
	await physics_frame
	player.on_ground = true
	player.ground_is_world = true
	var eyes := player.ground_eyes
	eyes.update(player, DT)
	_check(eyes.queries > 0 and eyes.queries <= 25,
		"the cold sampler has a bounded five-by-five query budget")
	var before := eyes.queries
	for tick in 64:
		eyes.update(player, DT)
	_check(eyes.queries == before,
		"idle grounded ticks reuse terrain without any additional sweeps")
	var held := eyes.offset
	player.position.x = -1.0
	player.position.y = 15.0 * slope
	eyes.update(player, DT)
	_check(eyes.queries == before and absf(eyes.offset - held) < 0.08,
		"movement within the same grid reweights cached cells without re-casting them")
	player.position.x = -9.0
	player.position.y = 7.0 * slope
	eyes.update(player, DT)
	_check(eyes.queries - before <= 5,
		"crossing one terrain cell queries only the new grid row")
	before = eyes.queries
	player.on_ground = false
	player.velocity.y = 200.0
	var residual_start := absf(eyes.offset)
	eyes.update(player, 0.02)
	_check(not eyes.using_topology and eyes.queries == before
		and absf(eyes.offset) < residual_start and absf(eyes.offset) > 0.0,
		"takeoff decays the topology residual instead of snapping or querying airborne terrain")
	for tick in 8:
		eyes.update(player, 0.02)
	_check(absf(eyes.offset) < 0.0001 and eyes.queries == before,
		"ordinary jump velocity clears slope residual before the 100-ms grenade snapshot")
	player.on_ground = true
	player.ground_is_world = true
	player.velocity = Vector3.ZERO
	eyes.update(player, DT)
	_check(eyes.using_topology and absf(eyes.offset) < 8.0,
		"landing restores bounded terrain state without an invented large correction")
	# Crossing enough cells exercises bounded storage, rather than merely
	# retaining the first stationary grid forever.
	for tick in 100:
		player.position.x = -16.0 - tick * 8.0
		player.position.y = (player.position.x + 16.0) * slope
		eyes.update(player, DT)
	_check(eyes.cache_size() <= GroundEyes.CACHE_LIMIT + GroundEyes.SIDE * GroundEyes.SIDE,
		"long grounded travel cannot grow the per-pawn terrain cache without bound")
	player.noclip = true
	eyes.update(player, DT)
	_check(eyes.offset == 0.0 and eyes.residual == 0.0 and eyes.cache_size() == 0,
		"noclip clears grounded root adjustment and stale terrain cache")
	_check(eyes.queries >= before,
		"noclip state reset preserves cumulative terrain-query accounting")
	_close()
	await process_frame


func _check_void_edge_budget() -> void:
	_setup()
	_box(Vector3(-4, 10, -4), Vector3(8, 20, 8))
	var player := _body(Vector3(-4, 20, -4))
	if not _start():
		_close()
		return
	await physics_frame
	player.on_ground = true
	player.ground_is_world = true
	var eyes := player.ground_eyes
	eyes.update(player, DT)
	var before := eyes.queries
	eyes.update(player, DT)
	_check(eyes.queries == before,
		"even a void-backed ledge reuses the entire result at identical pawn coordinates")
	# CS2 stores successful heights only. Moving near a void therefore
	# retries failed cells; report this worst case rather than claim it
	# benefits from the successful-floor cache.
	var max_queries := 0
	var measured_queries := 0
	var start_usec := Time.get_ticks_usec()
	for tick in 128:
		player.position.x = -4.0 if tick % 2 == 0 else -5.0
		before = eyes.queries
		eyes.update(player, DT)
		var added := eyes.queries - before
		measured_queries += added
		max_queries = maxi(max_queries, added)
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	_check(max_queries > 0 and max_queries <= 25,
		"moving beside void retries missing support within the fixed 25-sweep budget")
	_check(eyes.cache_size() > 0 and eyes.cache_size() <= 25,
		"void-backed terrain retains only the valid nearby support heights")
	print("TERRAIN VOID ", JSON.stringify({"ticks": 128, "casts": measured_queries,
		"most_casts_per_tick": max_queries, "mean_usec": float(elapsed_usec) / 128.0}))
	_close()
	await process_frame


func _check_world_support_gate() -> void:
	_setup()
	_box(Vector3(0, -8, 0), Vector3(512, 16, 512))
	var lower := _body(Vector3(0, 8, 0))
	var upper := _body(Vector3(0, 90, 0))
	if not _start():
		_close()
		return
	await physics_frame
	for tick in 96:
		lower.simulate(DT)
		upper.simulate(DT)
	_check(lower.on_ground and lower.ground_is_world,
		"the bottom pawn reports its real static floor as world support")
	_check(upper.on_ground and not upper.ground_is_world
		and upper.position.y > lower.position.y + 71.0,
		"a pawn standing on another pawn keeps ground contact without classifying it as world terrain")
	var before := upper.ground_eyes.queries
	for tick in 8:
		upper.simulate(DT)
	_check(not upper.ground_eyes.using_topology and upper.ground_eyes.queries == before
		and absf(upper.eye_height() - 64.0) < 0.03,
		"standing on a pawn does not sample the distant world floor or lower the shared eyes")
	_close()
	await process_frame
	# Animatable bodies belong to the engine comparison backend; the
	# current native world deliberately captures static map geometry.
	_setup()
	var platform := AnimatableBody3D.new()
	platform.position = Vector3(0, -8, 0)
	platform.collision_layer = 1
	platform.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(512, 16, 512)
	collision.shape = shape
	platform.add_child(collision)
	_host.add_child(platform)
	var player := _body(Vector3(0, 8, 0))
	await physics_frame
	for tick in 96:
		player.simulate(DT)
	_check(player.on_ground and not player.ground_is_world,
		"an animatable support is grounded without pretending to be static map terrain")
	before = player.ground_eyes.queries
	for tick in 8:
		player.simulate(DT)
	_check(not player.ground_eyes.using_topology and player.ground_eyes.queries == before,
		"moving-platform comparison contact does not issue static terrain samples")
	_close()
	await process_frame


func _check_neighbor_exclusion() -> void:
	_setup()
	_plane(ANGLE)
	var player := _body(Vector3(0, 16.0 * tan(deg_to_rad(ANGLE)), 0))
	# Put the top of a second pawn inside the sample range, on a lower
	# level. Its hull overlaps the footprint, while the observer's support
	# remains the world slope. Including layer 2 would sample that top.
	var neighbor := _body(Vector3(0, -52, 0))
	if not _start():
		_close()
		return
	await physics_frame
	player.on_ground = true
	player.ground_is_world = true
	player.ground_eyes.update(player, DT)
	var with_neighbor := player.ground_eyes.drop
	var casts := player.ground_eyes.queries
	neighbor.position.x = 200.0
	PhysicsQueries.sync_object(neighbor)
	player.ground_eyes.update(player, DT)
	_check(player.ground_eyes.queries == casts,
		"a neighboring pawn crossing the terrain footprint does not invalidate static terrain heights")
	player.reset_eye_state()
	player.ground_eyes.update(player, DT)
	var without_neighbor := player.ground_eyes.drop
	var expected := (16.0 - 3.99) * tan(deg_to_rad(ANGLE))
	_check(absf(with_neighbor - expected) < 0.08 and absf(with_neighbor - without_neighbor) < 0.0001,
		"a neighboring pawn cannot hide slope cells or enter the static terrain cache")
	_close()
	await process_frame
