extends SceneTree

## What every system costs on dust2, with as many players as asked for: a
## tick's share and a frame's for each kind of node, what a shot's marks and
## sounds cost, and single operations timed many times over (an animation
## step, a run_command, a path search, a ragdoll, a side swap). It is what
## reference/performance.md was measured with.
##
##   godot --headless --path . --script scripts/profile_dust2.gd -- [team size] [windows] [round]
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
## there to the next tick in the same frame is the physics server. Headless
## there is no drawing, so a frame here is its script alone.

const WINDOW_USEC := 5_000_000

var _team_size := 5
var _windows := 3
## End warmup at the start, and measure a round (round).
var _round := false
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


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_team_size = int(args[0])
	if args.size() >= 2:
		_windows = int(args[1])
	_round = args.has("round")
	_start_usec = Time.get_ticks_usec()
	var dust2 := (load("res://maps/de_dust2/de_dust2.tscn") as PackedScene).instantiate()
	dust2.set("team_size", _team_size)
	root.add_child(dust2)
	var stamp := GDScript.new()
	stamp.source_code = "extends Node\nvar stamp := 0\nfunc _physics_process(_d: float) -> void:\n\tstamp = Time.get_ticks_usec()\n"
	stamp.reload()
	_marker = Node.new()
	_marker.set_script(stamp)
	_marker.process_physics_priority = 1 << 30
	root.add_child(_marker)
	node_added.connect(func(node: Node) -> void: _arrived.append(node))


func _process(delta: float) -> bool:
	if not _started:
		if _first_frame_usec == 0:
			_first_frame_usec = Time.get_ticks_usec()
		if Engine.get_process_frames() < 40:
			return false
		_begin()
		return false

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
		var a := Time.get_ticks_usec()
		node.call("_process", delta)
		var b := Time.get_ticks_usec()
		_add("frame: " + _kind(node), b - a)
		# A body that steps its own animation (PlayerModel.step_off_tick_frames)
		# has its skeleton posed straight after it stepped, as a tree's below.
		var body := node as PlayerModel
		if body != null and body.stepped_by_hand and body._unstepped == 0.0 and body.character_rig != null:
			body.character_rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
			_add("frame: skeletons posed, and the hitboxes and pins on them", Time.get_ticks_usec() - b)
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
		_add("frame: animation trees stepped", b - a)
		_add("frame: skeletons posed, and the hitboxes and pins on them", Time.get_ticks_usec() - b)
		_count("animation trees stepped")

	var now := Time.get_ticks_usec()
	if now - _window_start < WINDOW_USEC:
		return false
	_report(now)
	_window += 1
	if _window < _windows:
		_sums.clear()
		_counts.clear()
		_ticks = 0
		_frames = 0
		_window_start = Time.get_ticks_usec()
		return false
	_print_objects("at the end")
	_single_operations()
	quit(0)
	return true


func _physics_process(delta: float) -> bool:
	if not _started:
		return false
	var start := Time.get_ticks_usec()
	if _ticks > 0 and _marker.stamp >= _nodes_done:
		_add("tick: the engine's own callbacks", _marker.stamp - _nodes_done)
		if _last_frame == Engine.get_process_frames():
			_add("tick: the physics server's step", start - _marker.stamp)
			_count("ticks after a tick in the same frame")
	_last_frame = Engine.get_process_frames()
	for node in _physics_nodes.duplicate():
		if not is_instance_valid(node) or not node.is_inside_tree():
			_physics_nodes.erase(node)
			continue
		if node is GameWorld:
			_run_world(node as GameWorld, delta)
			continue
		var e := Time.get_ticks_usec()
		node.call("_physics_process", delta)
		_add("tick: " + _kind(node), Time.get_ticks_usec() - e)
	_nodes_done = Time.get_ticks_usec()
	_ticks += 1
	return false


## The world's tick, as GameWorld.step runs it, with a clock round each part.
func _run_world(world: GameWorld, delta: float) -> void:
	world.begin_tick()
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
	_add("tick: the match", Time.get_ticks_usec() - d)


func _begin() -> void:
	print("dust2: first frame %.1f s after starting, playing at %.1f s; %d players" % [
		(_first_frame_usec - _start_usec) / 1e6, (Time.get_ticks_usec() - _start_usec) / 1e6, _players().size(),
	])
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
		if player is Bot:
			(player as Bot).shot_traced.disconnect((player as Bot)._on_shot_traced)
			(player as Bot).shot_traced.connect(_timed_shot.bind(player))
	_print_objects("at the start")
	if _round and GameWorld.current != null and GameWorld.current.match_state != null:
		GameWorld.current.match_state.end_warmup_on_next_tick()
	_started = true
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
		_in_order(_physics_nodes, true)
	if node.is_processing() and not _process_nodes.has(node):
		node.set_process(false)
		_process_nodes.append(node)
		_in_order(_process_nodes, false)


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
		if key == "tick: the physics server's step":
			each = _sums[key] / float(maxi(_counts.get("ticks after a tick in the same frame", 0), 1))
			unit = "ms a tick"
		elif key.begins_with("tick"):
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
		print("  %-62s %7.3f %s" % [key, each / 1000.0, unit])
	print("  %-62s %7.3f ms a tick" % ["the tick", tick_total / 1000.0])
	print("  %-62s %7.3f ms a frame (%.1f animation trees)" % [
		"the frame's script", frame_total / 1000.0, _counts.get("animation trees stepped", 0) / frames,
	])


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
	if model != null and not capsules.is_empty():
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


func _count(label: String) -> void:
	_counts[label] = _counts.get(label, 0) + 1


func _kind(node: Node) -> String:
	var script := node.get_script() as Script
	return script.resource_path.get_file() if script != null and script.resource_path != "" else node.get_class()


func _players() -> Array[PlayerSim]:
	if GameWorld.current == null:
		return []
	return GameWorld.current.players
