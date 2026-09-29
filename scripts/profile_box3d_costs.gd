extends "res://scripts/profile_box3d_match.gd"

## Disjoint CPU attribution for the same seeded Dust2 workload as
## profile_box3d_match.gd. Run serially on an otherwise idle machine:
## godot --headless --path . --script scripts/profile_box3d_costs.gd -- --physics box3d
## godot --headless --path . --script scripts/profile_box3d_costs.gd -- --physics box3d --sync-counts
##
## The first run times nested spans; only EXCLUSIVE times are additive.
## The second inspects every synchronization call and reports counts only:
## its heavier bookkeeping must not be used as a performance measurement.
## Compare the first run to profile_box3d_match.gd to quantify instrumentation
## overhead. Timers and virtual wrappers themselves still have a small cost.
##
## This is a simulation audit, not a rendered-frame benchmark. It splits
## GameWorld.step into its existing ordered phases and refreshes all player
## animation poses once after each tick. That pose batch is reported separately
## and is not the game's actual per-render-frame animation schedule.
## Native interval covers four native step calls plus dropped-item state
## transfer, between our pre/post callbacks. Listener inclusion depends on
## connection order; this immortal workload has no ragdoll listeners.
## Native step telemetry describes
## ONLY the last of those four calls; it is never multiplied into a tick total.


class CostMeter:
	extends RefCounted

	enum Part {
		TICK, BEGIN, COMMAND, PLAYER, END, POSES, SYNC, RAY, CAST,
		NATIVE_CAST, EXCLUDE, OVERLAP, REST, NATIVE_INTERVAL, MODEL_PARAMETERS,
	}
	const LABELS := [
		"tick_dispatch", "begin_tick", "command_for", "run_command", "end_tick",
		"pose_batch", "sync_dynamic", "intersect_ray", "shape_cast",
		"native_cast_wrapper", "disable_excluded", "intersect_shape", "get_rest_info",
		"native_interval", "model_parameters",
	]
	var enabled := false
	var calls := PackedInt64Array()
	var inclusive := PackedInt64Array()
	var exclusive := PackedInt64Array()
	var pose_calls := PackedInt64Array()
	var pose_inclusive := PackedInt64Array()
	var pose_exclusive := PackedInt64Array()
	var _parts := PackedInt32Array()
	var _starts := PackedInt64Array()
	var _children := PackedInt64Array()
	var _depth := 0
	var _root_part := -1

	func _init() -> void:
		calls.resize(LABELS.size())
		inclusive.resize(LABELS.size())
		exclusive.resize(LABELS.size())
		pose_calls.resize(LABELS.size())
		pose_inclusive.resize(LABELS.size())
		pose_exclusive.resize(LABELS.size())
		_parts.resize(32)
		_starts.resize(32)
		_children.resize(32)

	func enter(part: int) -> void:
		if not enabled:
			return
		if _depth == 0:
			_root_part = part
		_parts[_depth] = part
		_children[_depth] = 0
		_starts[_depth] = Time.get_ticks_usec()
		_depth += 1
		calls[part] += 1
		if _root_part == Part.POSES:
			pose_calls[part] += 1

	func leave() -> void:
		if not enabled:
			return
		var ended := Time.get_ticks_usec()
		_depth -= 1
		var elapsed := ended - _starts[_depth]
		var part := _parts[_depth]
		inclusive[part] += elapsed
		exclusive[part] += elapsed - _children[_depth]
		if _root_part == Part.POSES:
			pose_inclusive[part] += elapsed
			pose_exclusive[part] += elapsed - _children[_depth]
		if _depth > 0:
			_children[_depth - 1] += elapsed


class TimedQueries:
	extends Box3DQueries

	var meter: CostMeter
	var sync_scan_depth := 0
	var scans_world_only := 0
	var scans_hulls := 0
	var scans_hitboxes := 0
	var hull_entries := 0
	var hitbox_entries := 0
	## The sets of hitboxes a ray in a tick looked at, and how many of
	## their hitboxes it brought up to date (Box3DQueries._sync_sets).
	var sets_looked_at := 0
	var sets_put := 0

	func sync_dynamic(mask: int = ALL_LAYERS, exclude: Array[RID] = []) -> void:
		if meter.enabled:
			if mask & _dynamic_layers == 0:
				scans_world_only += 1
			if mask & _hull_layers != 0:
				scans_hulls += 1
				hull_entries += _hulls.size()
			if mask & _hitbox_layers != 0:
				scans_hitboxes += 1
				hitbox_entries += _hitboxes.size()
		meter.enter(CostMeter.Part.SYNC)
		sync_scan_depth += 1
		super.sync_dynamic(mask, exclude)
		sync_scan_depth -= 1
		meter.leave()

	# A round's ray brings the bodies' hitboxes up to date by their sets,
	# not through sync_dynamic: counted as synchronizing all the same.
	func _sync_sets(by_line: bool, from: Vector3, to: Vector3, exclude: Array[RID]) -> void:
		if meter.enabled:
			scans_hitboxes += 1
			sets_looked_at += _sets.size()
		meter.enter(CostMeter.Part.SYNC)
		sync_scan_depth += 1
		super._sync_sets(by_line, from, to, exclude)
		sync_scan_depth -= 1
		meter.leave()

	func _put(of_set: Dictionary, hung: SkinnedHitboxes, at: Transform3D, live: bool) -> void:
		if meter.enabled:
			sets_put += 1
			hitbox_entries += (of_set["members"] as Dictionary).size()
		super._put(of_set, hung, at, live)

	func intersect_ray(query: PhysicsRayQueryParameters3D) -> Dictionary:
		meter.enter(CostMeter.Part.RAY)
		var result := super.intersect_ray(query)
		meter.leave()
		return result

	# Ordinary and prepared recovery casts share this result path. Measuring
	# the outer shape_cast alone would miss PlayerBody's prepared probes.
	func shape_cast_prepared(query: PhysicsShapeQueryParameters3D) -> Dictionary:
		meter.enter(CostMeter.Part.CAST)
		var result := super.shape_cast_prepared(query)
		meter.leave()
		return result

	func _native_cast(query: PhysicsShapeQueryParameters3D, motion: Vector3, inset: float = 0.0) -> Dictionary:
		meter.enter(CostMeter.Part.NATIVE_CAST)
		var result := super._native_cast(query, motion, inset)
		meter.leave()
		return result

	func _disable_excluded(exclude: Array[RID]) -> Array:
		meter.enter(CostMeter.Part.EXCLUDE)
		var result := super._disable_excluded(exclude)
		meter.leave()
		return result

	func intersect_shape(query: PhysicsShapeQueryParameters3D, max_results: int = 32) -> Array[Dictionary]:
		meter.enter(CostMeter.Part.OVERLAP)
		var result := super.intersect_shape(query, max_results)
		meter.leave()
		return result

	func get_rest_info(query: PhysicsShapeQueryParameters3D) -> Dictionary:
		meter.enter(CostMeter.Part.REST)
		var result := super.get_rest_info(query)
		meter.leave()
		return result


class CountedQueries:
	extends TimedQueries

	var rows := {}
	var _seen_this_tick := {}

	func next_tick() -> void:
		_seen_this_tick.clear()

	func sync_object(source: CollisionObject3D, refresh_shapes: bool = true) -> void:
		if meter.enabled and is_instance_valid(source):
			var kind := "hitbox" if source is Hitbox else ("hull" if source is CharacterBody3D else "other")
			if not rows.has(kind):
				rows[kind] = {"calls": 0, "repeat_same_tick": 0, "from_scan": 0,
					"explicit": 0, "fast_skip": 0, "changed_pose_or_layer": 0, "same_pose_forced_refresh": 0, "geometry_dirty": 0}
			var row: Dictionary = rows[kind]
			var id := source.get_instance_id()
			row["calls"] += 1
			row["from_scan" if sync_scan_depth > 0 else "explicit"] += 1
			if _seen_this_tick.has(id):
				row["repeat_same_tick"] += 1
			_seen_this_tick[id] = true
			var record: Dictionary = _objects.get(id, {})
			var same: bool = record.get("at") == source.global_transform and int(record.get("layer", -1)) == source.collision_layer
			if record.get("geometry_dirty", false):
				row["geometry_dirty"] += 1
			elif same and not refresh_shapes:
				row["fast_skip"] += 1
			elif same:
				# A same-pose refresh can still be necessary after resizing or
				# disabling a shape; this is a candidate count, not proof of waste.
				row["same_pose_forced_refresh"] += 1
			else:
				row["changed_pose_or_layer"] += 1
		super.sync_object(source, refresh_shapes)


var _meter := CostMeter.new()
var _queries: TimedQueries
var _count_sync := false
var _adapter: Box3DDrops
var _native_steps_before := 0
var _last_native_step_ms := PackedFloat64Array()


func _initialize() -> void:
	if GameWorld.configured_drop_physics() != "box3d":
		push_error("This attribution profiler requires --physics box3d; use profile_box3d_match.gd for the legacy baseline.")
		quit(1)
		return
	_count_sync = OS.get_cmdline_user_args().has("--sync-counts")
	super._initialize()


func _load_match(backend: String) -> void:
	await super._load_match(backend)
	_adapter = world.game.drop_physics
	# Replace only the query facade after the normal warmup. Its close()
	# restores source RIDs but leaves native mirrors for adapter teardown.
	# Remove those mirrors before the replacement scans, so old self bodies
	# cannot remain collidable beside the replacement's excluded proxies.
	for native in _adapter.native_world.get_children():
		var source_id := int(native.get_meta(&"source_id", 0))
		var source := instance_from_id(source_id) if source_id != 0 else null
		if source is CharacterBody3D or source is Hitbox:
			native.free()
	_adapter.queries.close()
	_queries = CountedQueries.new() if _count_sync else TimedQueries.new()
	_queries.meter = _meter
	_adapter.queries = _queries
	_queries.initialize(_adapter, scene)
	_adapter.pre_step.connect(_native_started)
	_adapter.post_step.connect(_native_finished)
	_native_steps_before = _adapter.native_steps
	print("COST_SCOPE mode=%s players=%d hull_proxies=%d hitboxes=%d triangles=%d collision_steps=%d solver_substeps=%d" % [
		"counts_only" if _count_sync else "exclusive_timing", world.players.size(), _queries._hulls.size(),
		_queries._hitboxes.size(), _adapter.captured_triangles, Box3DDrops.COLLISION_STEPS,
		int(_adapter.native_world.get(&"substep_count"))])
	print("COST_SCOPE explicit hull sync remains in caller self time; pose_batch is one manual ten-player batch per simulation tick, not render-frame time")
	print("COST_SCOPE the bots think in turn here whatever --think says, the clocks being one thread's; the game has them think on worker threads, and scripts/profile_dust2.gd times that")


func _tick() -> void:
	var before := 0
	for player in world.players:
		before += player.traces
	if _count_sync:
		(_queries as CountedQueries).next_tick()
	_meter.enabled = true
	var started := Time.get_ticks_usec()
	_meter.enter(CostMeter.Part.TICK)
	_meter.enter(CostMeter.Part.BEGIN)
	world.begin_tick()
	_meter.leave()
	var dt := SimClock.tick_seconds()
	var running := world.playing()
	# The clocks are this thread's: the bots think in turn for them, which
	# is the same commands (tests/run_bot_think_checks.gd).
	world.think_on_threads = false
	_meter.enter(CostMeter.Part.COMMAND)
	var commands := world.commands_for(running, dt)
	_meter.leave()
	for i in running.size():
		if running[i].is_inside_tree():
			_meter.enter(CostMeter.Part.PLAYER)
			_run_player(running[i], commands[i], dt)
			_meter.leave()
	_meter.enter(CostMeter.Part.END)
	world.end_tick()
	_meter.leave()
	_meter.leave()
	tick_costs.append(float(Time.get_ticks_usec() - started))
	var after := 0
	for player in world.players:
		after += player.traces
	total_traces += after - before
	max_traces = maxi(max_traces, after - before)
	_meter.enter(CostMeter.Part.POSES)
	_pose_players()
	_meter.leave()
	_meter.enabled = false


## Mirror PlayerSim.run_command's ordering only in this attribution run, so
## animation parameter preparation is separate from movement/weapon work.
## The ordinary profile_box3d_match run still calls the production method;
## compare its workload counts and timing to expose instrumentation overhead.
func _run_player(player: PlayerSim, command: UserCmd, dt: float) -> void:
	player.previous_yaw_degrees = player.yaw_degrees
	player.previous_pitch_degrees = player.pitch_degrees
	player.previous_view_punch = player.view_punch()
	player.previous_viewmodel_punch = player.weapon.viewmodel_punch() if player.weapon != null else Vector2.ZERO
	player._run(command, dt)
	if player.alive and player.model != null:
		_meter.enter(CostMeter.Part.MODEL_PARAMETERS)
		player.model.update_motion(player.velocity, player.yaw_degrees, player.duck_progress,
			player.on_ground, player.air_action, player.air_action_usec, player.height_above_ground)
		_meter.leave()


func _native_started(_t: SimTick) -> void:
	_meter.enter(CostMeter.Part.NATIVE_INTERVAL)


func _native_finished(_t: SimTick) -> void:
	_meter.leave()
	if _meter.enabled and not _count_sync:
		_last_native_step_ms.append(float(_adapter.native_world.call(&"get_step_time_ms")))


func _report_costs(label: String) -> void:
	if _count_sync:
		print("COST_COUNTS_ONLY elapsed times intentionally omitted; extra per-object inspection changes CPU cost")
		print("COST_COUNTS_SCOPE object rows count sync_object calls only; registry entries skipped in _sync_group are included in COST_SYNC_SCANS, not object fast_skip")
		for kind: String in (_queries as CountedQueries).rows:
			print("COST_SYNC_OBJECT kind=%s counts=%s" % [kind, JSON.stringify((_queries as CountedQueries).rows[kind])])
	else:
		super._report_costs(label)
		print("COST_TIMING exclusive columns are disjoint; inclusive columns overlap and must not be added; tick and pose columns are separate workloads")
		var sum_exclusive := 0
		var sum_pose_exclusive := 0
		for part in CostMeter.LABELS.size():
			if _meter.calls[part] == 0:
				continue
			sum_exclusive += _meter.exclusive[part]
			sum_pose_exclusive += _meter.pose_exclusive[part]
			print("COST category=%s tick_calls=%d exclusive_ms_per_tick=%.4f inclusive_ms_per_tick=%.4f pose_calls=%d exclusive_ms_per_pose_batch=%.4f inclusive_ms_per_pose_batch=%.4f" % [
				CostMeter.LABELS[part], _meter.calls[part] - _meter.pose_calls[part],
				(_meter.exclusive[part] - _meter.pose_exclusive[part]) / (TICKS * 1000.0),
				(_meter.inclusive[part] - _meter.pose_inclusive[part]) / (TICKS * 1000.0),
				_meter.pose_calls[part], _meter.pose_exclusive[part] / (TICKS * 1000.0),
				_meter.pose_inclusive[part] / (TICKS * 1000.0)])
		print("COST_ACCOUNTING tick_difference_us=%d pose_difference_us=%d" % [
			sum_exclusive - sum_pose_exclusive - _meter.inclusive[CostMeter.Part.TICK],
			sum_pose_exclusive - _meter.inclusive[CostMeter.Part.POSES]])
		var native_step_sum := 0.0
		for sample in _last_native_step_ms:
			native_step_sum += sample
		_last_native_step_ms.sort()
		print("COST_NATIVE_LAST_CALL samples=%d mean_ms=%.4f p95_ms=%.4f scope=b3World_Step_last_of_four_calls" % [
			_last_native_step_ms.size(), native_step_sum / _last_native_step_ms.size(),
			_last_native_step_ms[int(ceil(_last_native_step_ms.size() * 0.95)) - 1]])
	print("COST_SYNC_SCANS world_only=%d with_hulls=%d with_hitboxes=%d hull_entries=%d hitbox_entries=%d hitbox_sets_looked_at=%d hitbox_sets_put=%d" % [
		_queries.scans_world_only, _queries.scans_hulls, _queries.scans_hitboxes, _queries.hull_entries, _queries.hitbox_entries,
		_queries.sets_looked_at, _queries.sets_put])
	print("COST_NATIVE_STEPS calls=%d most=%d (none on a tick with nothing awake)" % [_adapter.native_steps - _native_steps_before, TICKS * Box3DDrops.COLLISION_STEPS])
