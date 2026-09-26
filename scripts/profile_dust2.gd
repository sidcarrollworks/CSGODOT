extends SceneTree

## What every system costs on dust2, with as many players as asked for: a
## tick's share and a frame's for each kind of node, what a shot's marks and
## sounds cost, and single operations timed many times over (an animation
## step, a run_command, a path search, a ragdoll, a side swap). It is what
## reference/performance.md was measured with.
##
##   godot --headless --path . --script scripts/profile_dust2.gd -- 5 3 round --physics box3d --skip-single-operations --immortal
## Positional arguments remain team size, five-second windows, and round.
## --physics accepts box3d or legacy. --immortal must be used on BOTH sides
## of a comparison; it removes deaths, ragdolls, respawns and death drops.
##
## Team size 5 is ten players (you and nine bots); windows are five seconds
## each. With round, warmup is ended as it starts, so the windows go through
## a round's freeze time, everyone still, and on into the round, everyone
## moving; each window says the phase it ended in.
##
## It runs every node's callbacks itself, with a clock round each, so
## the time is by system rather than by the engine's phases: every node's
## _physics_process and _process, taken over as the node arrives and run in
## the order the engine would run them (by priority, then the tree's), and every
## AnimationTree, switched to manual and stepped here, the skeleton posed
## straight after so the hitboxes and pins that follow it are counted too.
## The players' bodies step their own (PlayerModel.step_off_tick_frames),
## so theirs is counted under player_model.gd, their skeletons with the
## rest; headless nobody sees them, so they step only in frames without a
## tick, fewer times than drawn.
## The world's tick it runs in the world's own order and parts (begin_tick,
## each player's command_for and run_command, end_tick), timing each. A node
## after all the tree's physics callbacks marks where they end; the step from
## there to the next tick in the same frame is an engine-remainder estimate,
## not a direct physics-server timer. Inclusive callback wall times, frame
## intervals and nested event times are reported separately, never summed.
## This instrumented takeover is for attribution: it changes callback and
## animation scheduling and adds timer/bookkeeping overhead. Engine internals,
## deferred work, render-thread CPU work and GPU time are outside its sums.
## Use profile_combat.gd for ordinary drawn-frame intervals and profile_render.gd
## for renderer timings. Rendering is absent headless; animation visibility
## and therefore the workload also differ from a visible game.

const WINDOW_USEC := 5_000_000

var _team_size := 5
var _windows := 3
## End warmup at the start, and measure a round (round).
var _round := false
var _immortal := false
var _single_operations_enabled := true
var _backend := ""
var _window := 0
var _marker: Node
var _started := false
var _window_start := 0
var _ticks := 0
var _frames := 0
var _sums := {}  # what was timed -> microseconds this window
var _counts := {}  # what was counted -> how many times this window
var _physics_nodes: Array[Node] = []
var _process_nodes: Array[Node] = []
var _trees: Array[AnimationTree] = []
var _skeletons := {}  # AnimationTree -> the skeleton it poses
var _arrived: Array[Node] = []
var _taken := {}  # node -> the order it was taken over in
var _last_frame := -1
var _nodes_done := 0
var _start_usec := 0
var _first_frame_usec := 0
var _previous_frame_stamp := 0
var _tick_samples: Array[float] = []
var _frame_samples: Array[float] = []
var _frame_intervals: Array[float] = []
var _engine_gaps: Array[float] = []
var _call_max := {}
var _tick_costs := {}
var _recording_tick := false
var _top_ticks: Array[Dictionary] = []
var _native_queries_start := 0
var _legacy_queries_start := 0
var _shot_hooks := {}
var _parked_process_nodes: Array[Node] = []
var _parked_physics_nodes: Array[Node] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var positional: Array[String] = []
	var index := 0
	while index < args.size():
		var argument := args[index]
		if argument in ["--physics", "--drop-physics"]:
			index += 1
			if index >= args.size() or args[index] not in ["box3d", "legacy"]:
				printerr("--physics requires box3d or legacy")
				quit(2)
				return
		elif argument.begins_with("--physics=") or argument.begins_with("--drop-physics="):
			if argument.get_slice("=", 1) not in ["box3d", "legacy"]:
				printerr("--physics requires box3d or legacy")
				quit(2)
				return
		elif argument == "--immortal":
			_immortal = true
		elif argument == "--skip-single-operations":
			_single_operations_enabled = false
		elif argument in ["round", "--round"]:
			_round = true
		elif argument.is_valid_int():
			positional.append(argument)
		else:
			printerr("Unknown profiler argument: " + argument)
			quit(2)
			return
		index += 1
	if positional.size() > 2:
		printerr("Expected at most team size and window count")
		quit(2)
		return
	_team_size = maxi(1, int(positional[0])) if positional.size() > 0 else _team_size
	_windows = maxi(1, int(positional[1])) if positional.size() > 1 else _windows
	_backend = GameWorld.configured_drop_physics()
	_start_usec = Time.get_ticks_usec()
	node_added.connect(_node_arrived)
	var dust2 := (load("res://maps/de_dust2/de_dust2.tscn") as PackedScene).instantiate()
	dust2.set("team_size", _team_size)
	# Competitive with bots, never the picker, which Ask would show only if
	# this were the scene being played.
	dust2.set("game_mode", "Competitive")
	root.add_child(dust2)
	# Before the first engine tick, including the forty-frame warmup.
	for player in _players():
		_prepare_player(player)
	var stamp := GDScript.new()
	stamp.source_code = "extends Node\nvar stamp := 0\nfunc _physics_process(_d: float) -> void:\n\tstamp = Time.get_ticks_usec()\n"
	stamp.reload()
	_marker = Node.new()
	_marker.set_script(stamp)
	_marker.process_physics_priority = 1 << 30
	root.add_child(_marker)


func _process(delta: float) -> bool:
	if not _started:
		if _first_frame_usec == 0:
			_first_frame_usec = Time.get_ticks_usec()
		if Engine.get_process_frames() < 40:
			return false
		_begin()
		return false
	var frame_start := Time.get_ticks_usec()
	if _previous_frame_stamp > 0:
		_frame_intervals.append(float(frame_start - _previous_frame_stamp))
	_previous_frame_stamp = frame_start
	_reclaim_callbacks(false)

	# Whatever arrived since the last frame is ready by now.
	if not _arrived.is_empty():
		var arrived := _arrived.duplicate()
		_arrived.clear()
		for node: Node in arrived:
			_take_over(node)

	_frames += 1
	for node in _process_nodes.duplicate():
		if not is_instance_valid(node) or not node.is_inside_tree():
			_process_nodes.erase(node)
			continue
		if not node.can_process():
			continue
		var a := Time.get_ticks_usec()
		# Preserve callbacks that turn themselves off. Merely holding the
		# flag false while calling them hid that state change in the old probe.
		node.set_process(true)
		node.call("_process", delta)
		var b := Time.get_ticks_usec()
		if not node.is_processing():
			_process_nodes.erase(node)
			_parked_process_nodes.append(node)
		else:
			node.set_process(false)
		_add("frame: " + _kind(node), b - a)
		# A body that steps its own animation (PlayerModel.step_off_tick_frames)
		# has its skeleton posed straight after it stepped, as a tree's below.
		var body := node as PlayerModel
		if body != null and body.stepped_by_hand and body.is_animating() and body._unstepped == 0.0 and body.character_rig != null:
			var pose_start := Time.get_ticks_usec()
			body.character_rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
			_add("frame: skeletons posed, and the hitboxes and pins on them", Time.get_ticks_usec() - pose_start)
	for tree in _trees.duplicate():
		if not is_instance_valid(tree) or not tree.is_inside_tree():
			_trees.erase(tree)
			continue
		if not tree.active:
			continue
		var a := Time.get_ticks_usec()
		tree.advance(delta)
		var b := Time.get_ticks_usec()
		var skeleton := _skeleton_of(tree)
		if skeleton != null:
			skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		var posed := Time.get_ticks_usec()
		_add("frame: animation trees stepped", b - a)
		_add("frame: skeletons posed, and the hitboxes and pins on them", posed - b)
		_count("animation trees stepped")

	var now := Time.get_ticks_usec()
	_frame_samples.append(float(now - frame_start))
	if now - _window_start < WINDOW_USEC:
		return false
	_report(now)
	_window += 1
	if _window < _windows:
		_reset_window()
		return false
	_print_objects("at the end")
	if _single_operations_enabled:
		_single_operations()
	quit(0)
	return true


func _physics_process(delta: float) -> bool:
	if not _started:
		return false
	var arrived_at := Time.get_ticks_usec()
	if _ticks > 0 and _marker.stamp >= _nodes_done:
		_add("gap: after managed tick, before last engine callback", _marker.stamp - _nodes_done)
		_count("gap: after managed tick, before last engine callback")
		if _last_frame == Engine.get_process_frames():
			_engine_gaps.append(float(arrived_at - _marker.stamp))
	_last_frame = Engine.get_process_frames()
	var before := _workload()
	_reclaim_callbacks(true)
	_tick_costs = {}
	_recording_tick = true
	var start := Time.get_ticks_usec()
	for node in _physics_nodes.duplicate():
		if not is_instance_valid(node) or not node.is_inside_tree():
			_physics_nodes.erase(node)
			continue
		if not node.can_process():
			continue
		if node is GameWorld:
			_run_world(node as GameWorld, delta)
			continue
		var e := Time.get_ticks_usec()
		node.set_physics_process(true)
		node.call("_physics_process", delta)
		if not node.is_physics_processing():
			_physics_nodes.erase(node)
			_parked_physics_nodes.append(node)
		else:
			node.set_physics_process(false)
		_add("tick: " + _kind(node), Time.get_ticks_usec() - e)
	var finished := Time.get_ticks_usec()
	_recording_tick = false
	var took := finished - start
	_tick_samples.append(float(took))
	_record_tick(took, before, _workload())
	_ticks += 1
	_nodes_done = Time.get_ticks_usec()
	return false


## The world's tick, as GameWorld.step runs it, with a clock round each part.
func _run_world(world: GameWorld, _delta: float) -> void:
	var began := Time.get_ticks_usec()
	world.begin_tick()
	_add("tick: begin_tick (clock, budgets, native query sync)", Time.get_ticks_usec() - began)
	# GameWorld.step uses the fixed simulation dt, never the engine delta.
	var delta := SimClock.tick_seconds()
	for player: PlayerSim in world.players.duplicate():
		if not player.is_inside_tree():
			continue
		var bot := player as Bot
		if bot != null and bot.alive:
			_count("bots alive, over the ticks")
		var a := Time.get_ticks_usec()
		var cmd := player.command_for(world.tick, delta)
		var b := Time.get_ticks_usec()
		player.run_command(cmd, delta)
		var c := Time.get_ticks_usec()
		if bot != null:
			_add("tick: bots thinking", b - a)
			_add("tick: bots' run_command", c - b)
		else:
			_add("tick: your command and run_command", c - a)
	var d := Time.get_ticks_usec()
	world.end_tick()
	_add("tick: end_tick (match, entities, native physics, systems, events)", Time.get_ticks_usec() - d)


func _begin() -> void:
	if GameWorld.current == null or GameWorld.current.drop_physics_backend != _backend:
		printerr("Requested physics backend did not initialize: " + _backend)
		quit(1)
		return
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	print("dust2: first frame %.1f s after starting, playing at %.1f s; %d players" % [
		(_first_frame_usec - _start_usec) / 1e6, (Time.get_ticks_usec() - _start_usec) / 1e6, _players().size(),
	])
	print("profile: physics=%s, display=%s, fixed_dt=%.6f, immortal=%s, single_operations=%s, frame_cap=0 (V-Sync unchanged)" % [
		_backend, DisplayServer.get_name(), SimClock.tick_seconds(), _immortal, _single_operations_enabled])
	print("Instrumented callback attribution; inclusive times include probe overhead. Event rows are nested, not additive. Frame intervals include untimed engine work and waits.")
	print("Manual takeover changes animation scheduling; external changes to a captured callback's process flag cannot always be observed. Validate ordinary frame intervals with profile_combat.gd.")
	# In the tree's order, which is the engine's among nodes of one priority.
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var children := node.get_children()
		children.reverse()
		stack.append_array(children)
		_take_over(node)
	_arrived.clear()
	for player in _players():
		_prepare_player(player)
		_hook_shots(player)
	_print_objects("at the start")
	if _round and GameWorld.current != null and GameWorld.current.match_state != null:
		GameWorld.current.match_state.end_warmup_on_next_tick()
	_started = true
	_reset_window()


func _node_arrived(node: Node) -> void:
	_arrived.append(node)
	if node is PlayerSim:
		_prepare_player.call_deferred(node)


func _prepare_player(node: Node) -> void:
	if not is_instance_valid(node) or not node is PlayerSim:
		return
	var player := node as PlayerSim
	if _immortal and player.hit_target != null:
		player.hit_target.immortal = true
	if _started:
		_hook_shots(player)


func _hook_shots(player: PlayerSim) -> void:
	if not player is Bot or _shot_hooks.has(player.get_instance_id()):
		return
	var bot := player as Bot
	if not bot.shot_traced.is_connected(bot._on_shot_traced):
		return
	bot.shot_traced.disconnect(bot._on_shot_traced)
	bot.shot_traced.connect(_timed_shot.bind(bot))
	_shot_hooks[bot.get_instance_id()] = true


func _reset_window() -> void:
	_sums.clear()
	_counts.clear()
	_call_max.clear()
	_tick_samples.clear()
	_frame_samples.clear()
	_frame_intervals.clear()
	_engine_gaps.clear()
	_top_ticks.clear()
	_ticks = 0
	_frames = 0
	_previous_frame_stamp = 0
	_nodes_done = 0
	_last_frame = -1
	_native_queries_start = PhysicsQueries.native_queries
	_legacy_queries_start = PhysicsQueries.legacy_queries
	_window_start = Time.get_ticks_usec()


## Runs a node's callbacks from here from now on, if it has any, in the
## order the engine would: by priority (the world before everything, so
## what is drawn reads the tick just run), then in the order taken over.
func _take_over(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or node == _marker:
		return
	if node is AnimationTree:
		var tree := node as AnimationTree
		if tree.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			_trees.append(tree)
		return
	if not _taken.has(node):
		_taken[node] = _taken.size()
	if node.is_physics_processing() and not _physics_nodes.has(node):
		node.set_physics_process(false)
		_physics_nodes.append(node)
		_parked_physics_nodes.erase(node)
		_in_order(_physics_nodes, true)
	elif node.has_method("_physics_process") and not _physics_nodes.has(node) and not _parked_physics_nodes.has(node):
		_parked_physics_nodes.append(node)
	if node.is_processing() and not _process_nodes.has(node):
		node.set_process(false)
		_process_nodes.append(node)
		_parked_process_nodes.erase(node)
		_in_order(_process_nodes, false)
	elif node.has_method("_process") and not _process_nodes.has(node) and not _parked_process_nodes.has(node):
		_parked_process_nodes.append(node)


func _reclaim_callbacks(physics: bool) -> void:
	var parked := _parked_physics_nodes if physics else _parked_process_nodes
	for node in parked.duplicate():
		if not is_instance_valid(node) or not node.is_inside_tree():
			parked.erase(node)
		elif (node.is_physics_processing() if physics else node.is_processing()):
			_take_over(node)


## Sorts the nodes by their priority, then by when they were taken over,
## leaving out any that have gone.
func _in_order(nodes: Array[Node], physics: bool) -> void:
	for i in range(nodes.size() - 1, -1, -1):
		if not is_instance_valid(nodes[i]):
			nodes.remove_at(i)
	nodes.sort_custom(func(a: Node, b: Node) -> bool:
		var first := a.process_physics_priority if physics else a.process_priority
		var second := b.process_physics_priority if physics else b.process_priority
		if first != second:
			return first < second
		return _taken[a] < _taken[b])


func _skeleton_of(tree: AnimationTree) -> Skeleton3D:
	if not _skeletons.has(tree):
		var node: Node = tree
		while node != null and not node is RigModel:
			node = node.get_parent()
		_skeletons[tree] = (node as RigModel).character_rig if node != null else null
	return _skeletons[tree]


func _timed_shot(shot: Weapon.Shot, result: Hitscan.Result, bot: Bot) -> void:
	var a := Time.get_ticks_usec()
	bot._on_shot_traced(shot, result)
	_add("event: a bot's shot: its marks, sound and body", Time.get_ticks_usec() - a)
	_count("event: a bot's shot: its marks, sound and body")


func _report(now: int) -> void:
	var seconds := (now - _window_start) / 1e6
	var ticks := float(maxi(_ticks, 1))
	var frames := float(maxi(_frames, 1))
	var phase := ""
	if GameWorld.current != null and GameWorld.current.match_state != null:
		phase = ", ended in %s" % String(MatchState.Phase.keys()[GameWorld.current.match_state.phase]).to_lower()
	print("\nwindow %d: %.1f frames/s, %.1f ticks/s, %.1f bots alive%s" % [
		_window + 1, _frames / seconds, _ticks / seconds, _counts.get("bots alive, over the ticks", 0) / ticks, phase,
	])
	var keys := _sums.keys()
	keys.sort()
	var tick_total := 0.0
	var frame_total := 0.0
	for key: String in keys:
		var each: float
		var unit: String
		if key.begins_with("tick"):
			each = _sums[key] / ticks
			unit = "ms a tick"
		elif key.begins_with("frame"):
			each = _sums[key] / frames
			unit = "ms a frame"
		else:
			each = _sums[key] / float(maxi(_counts.get(key, 1), 1))
			unit = "ms each (%d)" % _counts.get(key, 0)
		if key.begins_with("tick"):
			tick_total += each
		elif key.begins_with("frame"):
			frame_total += each
		print("  %-72s %7.3f %s; max call %.3f ms" % [key, each / 1000.0, unit, float(_call_max.get(key, 0)) / 1000.0])
	print("  %-72s %7.3f ms a tick" % ["sum of timed tick components (events excluded)", tick_total / 1000.0])
	print("  %-62s %7.3f ms a frame (%.1f animation trees)" % [
		"sum of timed frame components", frame_total / 1000.0, _counts.get("animation trees stepped", 0) / frames,
	])
	_distribution("inclusive managed tick, with profiler overhead", _tick_samples)
	_distribution("inclusive managed frame callbacks, with profiler overhead", _frame_samples)
	_distribution("wall frame interval (ticks, callbacks, engine work and waits)", _frame_intervals)
	_distribution("engine remainder between same-frame ticks, sampled only", _engine_gaps)
	print("  workload: shots=%d hull_traces=%d ground_rays=%d native_queries=%d legacy_queries=%d" % [
		_counts.get("shots", 0), _counts.get("hull traces", 0), _counts.get("ground rays", 0),
		PhysicsQueries.native_queries - _native_queries_start, PhysicsQueries.legacy_queries - _legacy_queries_start])
	for spike: Dictionary in _top_ticks:
		var costs: Dictionary = spike["costs"]
		var order := costs.keys()
		order.sort_custom(func(a: String, b: String) -> bool: return int(costs[a]) > int(costs[b]))
		var parts := PackedStringArray()
		for key: String in order.slice(0, 3):
			parts.append("%s %.3f ms" % [key, float(costs[key]) / 1000.0])
		print("  slow tick %d: %.3f ms, shots=%d traces=%d alive=%d ragdolls=%d; %s" % [
			spike["tick"], float(spike["usec"]) / 1000.0, spike["shots"], spike["traces"],
			spike["alive"], spike["ragdolls"], "; ".join(parts)])


static func _distribution(label: String, samples: Array[float]) -> void:
	if samples.is_empty():
		print("  %s: no samples (not zero cost)" % label)
		return
	var ordered := samples.duplicate()
	ordered.sort()
	var sum := 0.0
	for sample in ordered:
		sum += sample
	print("  %s: n=%d mean=%.3f p50=%.3f p95=%.3f p99=%.3f max=%.3f ms" % [
		label, ordered.size(), sum / ordered.size() / 1000.0,
		_percentile(ordered, 0.5) / 1000.0, _percentile(ordered, 0.95) / 1000.0,
		_percentile(ordered, 0.99) / 1000.0, ordered[-1] / 1000.0])


static func _percentile(ordered: Array[float], fraction: float) -> float:
	return ordered[clampi(ceili(ordered.size() * fraction) - 1, 0, ordered.size() - 1)]


func _workload() -> Dictionary:
	var totals := {"shots": 0, "traces": 0, "ground": 0, "alive": 0, "ragdolls": 0}
	for player in _players():
		totals["shots"] += player.rounds_fired
		totals["traces"] += player.traces
		totals["ground"] += player.ground_rays
		totals["alive"] += 1 if player.alive else 0
		totals["ragdolls"] += 1 if is_instance_valid(player.ragdoll) else 0
	return totals


func _record_tick(took: int, before: Dictionary, after: Dictionary) -> void:
	var shots := maxi(0, int(after["shots"]) - int(before["shots"]))
	var traces := maxi(0, int(after["traces"]) - int(before["traces"]))
	_counts["shots"] = int(_counts.get("shots", 0)) + shots
	_counts["hull traces"] = int(_counts.get("hull traces", 0)) + traces
	_counts["ground rays"] = int(_counts.get("ground rays", 0)) + maxi(0, int(after["ground"]) - int(before["ground"]))
	_top_ticks.append({"tick": GameWorld.current.tick if GameWorld.current != null else _ticks,
		"usec": took, "shots": shots, "traces": traces, "alive": after["alive"],
		"ragdolls": after["ragdolls"], "costs": _tick_costs.duplicate()})
	_top_ticks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["usec"]) > int(b["usec"]))
	if _top_ticks.size() > 5:
		_top_ticks.resize(5)


func _print_objects(when: String) -> void:
	print("%s: %d objects, %d nodes, %d resources, %d orphan nodes; static memory %.0f MB" % [
		when, Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	])


## One living bot's operations, each many times over.
func _single_operations() -> void:
	print("\nsingle operations, one bot:")
	var bot: Bot = null
	for player in _players():
		if player is Bot and (player as Bot).alive and (player as Bot).on_ground:
			bot = player
			break
	if bot == null:
		print("  (no bot alive on the ground)")
		return
	var position := bot.global_position
	var velocity := bot.velocity
	var dt := SimClock.tick_seconds()
	var model := bot.model
	if model != null and model.animation_tree != null:
		var tree := model.animation_tree
		var skeleton := model.character_rig
		_time("an animation step (AnimationTree.advance)", 500, func() -> void: tree.advance(1.0 / 144.0))
		_time("the skeleton posed, and what rides it", 500, func() -> void:
			skeleton.set_bone_pose_position(0, skeleton.get_bone_pose_position(0))
			skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON))
	if bot.hitboxes != null:
		_time("the 19 hitboxes moved to their bones", 500, func() -> void: bot.hitboxes.follow())
	var still := UserCmd.new()
	still.tick = SimClock.current_tick()
	_time("run_command, standing", 500, func() -> void:
		bot.velocity = Vector3.ZERO
		bot.run_command(still, dt)
		bot.global_position = position)
	var run := UserCmd.new()
	run.tick = SimClock.current_tick()
	run.move = Vector2(0.0, 1.0)
	run.yaw_degrees = bot.yaw_degrees
	var forward := Vector3(-sin(deg_to_rad(bot.yaw_degrees)), 0.0, -cos(deg_to_rad(bot.yaw_degrees)))
	_time("run_command, running the way it faces", 500, func() -> void:
		bot.velocity = forward * 250.0
		bot.run_command(run, dt)
		bot.global_position = position)
	bot.velocity = velocity
	bot.global_position = position
	_time("looking for a target", 500, func() -> void: bot.call("_look_for_target"))
	if bot.nav_mesh != null and bot.route.size() >= 2:
		var nav := bot.nav_mesh
		var from := bot.route[0]
		var to := bot.route[bot.route.size() - 1]
		_time("a path search over the nav mesh, spawn to site", 20, func() -> void: nav.walk_path(from, to))
	if bot.weapon_data != null:
		var shot := Weapon.Shot.new()
		shot.origin = position + Vector3.UP * 64.0
		shot.direction = forward
		var exclude: Array[RID] = [bot.get_rid()]
		exclude.append_array(bot.hit_target.rids())
		var space := bot.get_world_3d().direct_space_state
		var data := bot.weapon_data
		var result := Hitscan.trace(space, shot, data, exclude)
		_time("a round traced the way it faces (%d walls)" % result.walls.size(), 500, func() -> void: Hitscan.trace(space, shot, data, exclude))
		var impacts := get_first_node_in_group(&"bullet_impacts") as BulletImpacts
		if impacts != null:
			_time("that round's holes and sounds", 200, func() -> void: impacts.mark(result))
		if bot.weapon_sounds != null:
			_time("a shot's sound", 200, func() -> void: bot.weapon_sounds.shot(data.item_class))
	var capsules: Array[Dictionary] = bot.get("_capsules")
	if model != null and not capsules.is_empty() and PhysicsQueries.adapter_for_node(bot) != null:
		_time("a ragdoll built and taken down", 20, func() -> void:
			var ragdoll := Ragdoll.new()
			root.add_child(ragdoll)
			ragdoll.build(model.character_rig, capsules, MapImporter.SOURCE2_VIEWER_SCALE, Vector3.ZERO, Vector3.FORWARD)
			ragdoll.clear()
			ragdoll.free())
		model.pose_now()
	_time("spawn_at", 50, func() -> void: bot.spawn_at(position, bot.yaw_degrees))
	var team := bot.team
	var other := "CT" if team == "T" else "T"
	_time("a side swap there and back (two bodies built)", 3, func() -> void:
		bot.change_team(other)
		bot.change_team(team))


func _time(label: String, runs: int, work: Callable) -> void:
	work.call()
	var start := Time.get_ticks_usec()
	for i in runs:
		work.call()
	print("  %-52s %9.1f us" % [label, float(Time.get_ticks_usec() - start) / runs])


func _add(label: String, usec: int) -> void:
	_sums[label] = _sums.get(label, 0) + usec
	_call_max[label] = maxi(int(_call_max.get(label, 0)), usec)
	if _recording_tick and label.begins_with("tick:"):
		_tick_costs[label] = int(_tick_costs.get(label, 0)) + usec


func _count(label: String) -> void:
	_counts[label] = _counts.get(label, 0) + 1


func _kind(node: Node) -> String:
	var script := node.get_script() as Script
	return script.resource_path.get_file() if script != null and script.resource_path != "" else node.get_class()


func _players() -> Array[PlayerSim]:
	if GameWorld.current == null:
		return []
	return GameWorld.current.players
