extends "res://scripts/profile_box3d_match.gd"

## Isolate the terrain sampler in the seeded, ten-player Dust2 fixture.
## Run each in its own otherwise idle process; repeat in reversed order:
## godot --headless --path . --script scripts/profile_ground_eyes.gd -- --physics box3d --movement native
## godot --headless --path . --script scripts/profile_ground_eyes.gd -- --physics box3d --movement native --without-terrain
## The control disables update() after warmup; it is not a main-branch run.
## --script-eyes has the script sample where the native code would
## (GroundEyes.native_samples off): the native sample's A/B, in one build.
## --time-eyes splits what the eyes cost: each update(), and inside it the
## native sample's call (the C++ grid and Box3D's casts); its clocks add to
## the tick, so take its mean from a run without it.
## Inherited timing includes GameWorld.step(), excluding render/audio/UI.
## Query counters and endpoint collection are outside the timed interval.
var terrain_counts: Array[int] = []


class DisabledEyes extends GroundEyes:
	func update(_body: PlayerBody, _dt: float, _mover: Object = null, _bridge: Box3DQueries = null) -> void:
		pass


class TimedEyes extends GroundEyes:
	static var update_usec := 0
	static var updates := 0
	static var native_usec := 0
	static var native_calls := 0
	static var native_casts := 0
	static var cast_free_usec := 0
	static var cast_free_calls := 0

	static func reset_clocks() -> void:
		update_usec = 0
		updates = 0
		native_usec = 0
		native_calls = 0
		native_casts = 0
		cast_free_usec = 0
		cast_free_calls = 0

	func update(body: PlayerBody, dt: float, mover: Object = null, bridge: Box3DQueries = null) -> void:
		var start := Time.get_ticks_usec()
		super(body, dt, mover, bridge)
		update_usec += Time.get_ticks_usec() - start
		updates += 1

	func _native_sample(body: PlayerBody, mover: Object, bridge: Box3DQueries, q: Vector3, first: Vector2i, step: float, half: float, mask: int) -> float:
		var before := queries
		var start := Time.get_ticks_usec()
		var by_native := super(body, mover, bridge, q, first, step, half, mask)
		var took := Time.get_ticks_usec() - start
		native_usec += took
		native_calls += 1
		native_casts += queries - before
		if queries == before:
			cast_free_usec += took
			cast_free_calls += 1
		return by_native


## The same eyes, timed: everything they hold carried over, so the run
## samples as the others do.
static func _timed(eyes: GroundEyes) -> TimedEyes:
	var timed := TimedEyes.new()
	timed.offset = eyes.offset
	timed.residual = eyes.residual
	timed.using_topology = eyes.using_topology
	timed.queries = eyes.queries
	timed.drop = eyes.drop
	timed._last_q = eyes._last_q
	timed._last_step = eyes._last_step
	timed._last_half = eyes._last_half
	timed._last_mask = eyes._last_mask
	timed._cache.assign(eyes._cache)
	return timed


func _load_match(backend: String) -> void:
	await super(backend)
	if ClassDB.class_exists(&"HullMover"):
		var native_mover: Object = ClassDB.instantiate(&"HullMover")
		print("TERRAIN MATCH stamp=", native_mover.call(&"get_sources"))
	var disabled := "--without-terrain" in OS.get_cmdline_user_args()
	if disabled:
		for player in world.players:
			player.ground_eyes = DisabledEyes.new()
	elif "--time-eyes" in OS.get_cmdline_user_args():
		for player in world.players:
			player.ground_eyes = _timed(player.ground_eyes)
		print("TERRAIN MATCH timing the eyes")
	print("TERRAIN MATCH sampler=", "disabled" if disabled else ("native" if GroundEyes.native_samples else "script"),
		" players=", world.players.size())


func _tick() -> void:
	if terrain_counts.is_empty():
		TimedEyes.reset_clocks()
	var before := _terrain_queries()
	super()
	terrain_counts.append(_terrain_queries() - before)


func _terrain_queries() -> int:
	var count := 0
	for player in world.players:
		count += player.ground_eyes.queries
	return count


func _report_costs(label: String) -> void:
	super(label)
	var total := 0
	var most := 0
	for count in terrain_counts:
		total += count
		most = maxi(most, count)
	var endpoints := []
	for player in world.players:
		endpoints.append({"team": player.team, "position": var_to_str(player.position), "velocity": var_to_str(player.velocity)})
	print("TERRAIN MATCH ", JSON.stringify({"terrain_casts": total, "most_per_tick": most,
		"mean_per_tick": float(total) / terrain_counts.size(), "endpoints": endpoints}))
	if TimedEyes.updates > 0:
		var ticks := float(terrain_counts.size())
		var cast_free := float(TimedEyes.cast_free_usec) / maxi(TimedEyes.cast_free_calls, 1)
		print("TERRAIN TIMES ", JSON.stringify({
			"update_ms_per_tick": TimedEyes.update_usec / ticks / 1000.0,
			"native_sample_ms_per_tick": TimedEyes.native_usec / ticks / 1000.0,
			"script_around_it_ms_per_tick": (TimedEyes.update_usec - TimedEyes.native_usec) / ticks / 1000.0,
			"updates_per_tick": TimedEyes.updates / ticks,
			"native_samples_per_tick": TimedEyes.native_calls / ticks,
			"casts_per_tick": TimedEyes.native_casts / ticks,
			"sample_without_casts_us": cast_free,
			"each_cast_us": (TimedEyes.native_usec - cast_free * TimedEyes.native_calls) / maxi(TimedEyes.native_casts, 1),
		}))
