extends SceneTree

## What the players' hull traces come to on dust2, and whether walking
## hitches: bots walk Competitive's site routes as
## tests/run_dust2_bot_checks.gd has them, holding fire, and every trace
## each makes is counted by its kind (the move, the step up and down, the
## sweep that stays on the ground, the ground check), with the casts it took,
## whether it started in overlap and with what, whether it was pushed clear
## (a recovery, or a grazing hit's offset) and whether it went nowhere yet
## met a plane. A tick that starts at a run on the ground with a move held
## and ends at no speed is a stop: a hitch where none of its traces met
## anything too steep to walk on, a stop against a wall where one did
## (walked into a corner, anyone stops). The first few hitches are printed
## trace by trace. It found playtest issue 26
## (reference/research/box3d-walking-hitch-2026-09-28.md).
##
##   godot --headless --path . --script scripts/profile_hull_traces.gd -- 5 60
##
## Bots (5) and seconds of game (60), run at eight ticks a frame. It counts,
## and times nothing: scripts/profile_box3d_match.gd times the tick. Needs
## dust2 and its nav mesh extracted.

const SHOWN := 4
const HITCH_FROM := 100.0
const HITCH_TO := 1.0


## A bot whose hull traces are written down as it makes them.
class TracedBot:
	extends Bot

	var trace_log: Array[Dictionary] = []

	func _trace(motion: Vector3, test_only: bool = false) -> PlayerBody.TraceResult:
		var before := traces
		var overlap := ""
		var adapter := PhysicsQueries.adapter_for_node(self)
		if adapter != null and _collision_shape != null and _collision_shape.shape != null:
			# The same sweep, asked of the bridge before the move makes it:
			# a hit with no plane is a start in overlap.
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = _collision_shape.shape
			query.transform = _collision_shape.global_transform
			query.motion = motion
			query.margin = maxf(safe_margin, NATIVE_QUERY_MARGIN)
			query.collision_mask = collision_mask
			query.exclude = [get_rid()]
			var hit := adapter.queries.shape_cast(query)
			if not hit.is_empty() and (hit["normal"] as Vector3).is_zero_approx():
				overlap = "player" if hit.get("collider") is CharacterBody3D else "world"
		var result := super(motion, test_only)
		# Null where the trace met nothing.
		var travel: Variant = null
		var normal: Variant = null
		if result != null:
			travel = result.travel
			normal = result.normal
		trace_log.append({
			"motion": motion, "test": test_only, "overlap": overlap, "casts": traces - before,
			"travel": travel, "normal": normal, "pushed": _last_native_trace_recovery,
		})
		return result

	## The sweep that stays on the ground, which is a cast of its own and
	## no trace: written down as one, from where it started.
	func _cast_from(from: Vector3, motion: Vector3, queries: Box3DQueries) -> Dictionary:
		var hit := super(from, motion, queries)
		var travel: Variant = null
		var normal: Variant = null
		if not hit.is_empty():
			normal = hit["normal"]
			travel = from + motion * float(hit["fraction"])
		trace_log.append({
			"motion": motion, "test": true, "floor": true, "casts": 1,
			"overlap": "world" if normal != null and (normal as Vector3).is_zero_approx() else "",
			"travel": travel, "normal": normal, "pushed": hit.get("offset", Vector3.ZERO),
		})
		return hit


var _bots_wanted := 5
var _seconds := 60.0
var _world: GameWorld
var _bots: Array[Bot] = []
var _ticks := 0
var _end_tick := 0
var _hitches := 0
var _wall_stops := 0
var _busy_ticks := 0
var _most_traces := 0
var _shown := 0
var _started := false
## The kind of trace -> what was counted of it.
var _kinds := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_bots_wanted = maxi(1, int(args[0]))
	if args.size() > 1:
		_seconds = maxf(1.0, float(args[1]))
	_run()


func _run() -> void:
	# The tree takes nodes in from its first frame on.
	await process_frame
	var loader := MapLoader.new()
	loader.map_name = "de_dust2"
	root.add_child(loader)
	var contents := loader.contents
	if loader.importer == null or contents.nav_mesh == null or not contents.has_both_sides():
		printerr("dust2 and its nav mesh have not been extracted.")
		quit(2)
		return
	var sites := Competitive.site_floors(contents.nav_mesh, contents.places, contents.bomb_sites)
	Engine.time_scale = 8.0
	_world = GameWorld.new()
	loader.add_child(_world)
	var scene := load("res://src/bots/bot.tscn") as PackedScene
	var spawns: Array = contents.spawns["T"]
	for i in _bots_wanted:
		var bot := scene.instantiate() as Bot
		# The scene sets none of the script's variables, so the script can
		# be changed for the one that writes its traces down.
		bot.set_script(TracedBot)
		bot.name = "Walker%d" % i
		bot.team = "T"
		bot.holds_fire = true
		bot.nav_mesh = contents.nav_mesh
		bot.route = Competitive.bot_route(contents.spawns, "T", i, sites, contents.nav_mesh)
		loader.add_child(bot)
		_world.add_player(bot)
		var spawn: Dictionary = spawns[i % spawns.size()]
		bot.place(spawn["position"], float(spawn.get("yaw", 0.0)))
		bot.set("_next", 1)
		_bots.append(bot)
	await physics_frame
	# The world's tick is run from here, so each bot can be looked at before
	# and after its own command.
	_world.set_physics_process(false)
	_end_tick = SimClock.ticks_in(_seconds)
	print("hull traces: %d bots for %d ticks, physics %s" % [_bots.size(), _end_tick, _world.drop_physics_backend])
	_started = true


func _physics_process(_delta: float) -> bool:
	if not _started:
		return false
	_world.begin_tick()
	var dt := SimClock.tick_seconds()
	var running := _world.playing()
	var commands := _world.commands_for(running, dt)
	for i in running.size():
		var player := running[i]
		if not player.is_inside_tree():
			continue
		var bot := player as TracedBot
		var speed_before := Vector2(player.velocity.x, player.velocity.z).length()
		var ground_before: bool = player.on_ground
		var traces_before: int = player.traces
		var from: Vector3 = player.global_position
		bot.trace_log.clear()
		var cmd := commands[i]
		player.run_command(cmd, dt)
		var traces := player.traces - traces_before
		_most_traces = maxi(_most_traces, traces)
		if traces > 12:
			_busy_ticks += 1
		for entry in bot.trace_log:
			_count(entry)
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		if (
			ground_before and speed_before >= HITCH_FROM and speed < HITCH_TO
			and player.wish_speed > 0.0 and not player.frozen and not player.held_still
		):
			if _met_a_wall(bot):
				_wall_stops += 1
			else:
				_hitches += 1
				if _shown < SHOWN:
					_shown += 1
					_show(bot, from, speed_before, cmd, traces)
	_world.end_tick()
	_ticks += 1
	if _ticks < _end_tick:
		return false
	_report()
	quit(0)
	return true


## Whether any of the tick's traces met something too steep to walk on, or
## started in something and found no way out.
func _met_a_wall(bot: TracedBot) -> bool:
	for entry in bot.trace_log:
		if entry["normal"] == null:
			continue
		var normal: Vector3 = entry["normal"]
		if normal.is_zero_approx() or not MovementSolver.is_walkable(normal, bot.config):
			return true
	return false


func _count(entry: Dictionary) -> void:
	var motion: Vector3 = entry["motion"]
	var kind := "move"
	if entry.get("floor", false):
		kind = "the floor, from %.1f up" % (absf(motion.y) - _bots[0].config.step_height)
	elif motion.x == 0.0 and motion.z == 0.0:
		kind = "%s %.1f%s" % ["up" if motion.y > 0.0 else "down", absf(motion.y), " (test)" if entry["test"] else ""]
	if not _kinds.has(kind):
		_kinds[kind] = {"calls": 0, "casts": 0, "searched": 0, "world": 0, "player": 0, "pushed": 0, "nowhere": 0}
	var counts: Dictionary = _kinds[kind]
	counts["calls"] += 1
	counts["casts"] += entry["casts"]
	if entry["overlap"] != "":
		counts[entry["overlap"]] += 1
	if int(entry["casts"]) > 2:
		counts["searched"] += 1
	if not (entry["pushed"] as Vector3).is_zero_approx():
		counts["pushed"] += 1
	if not entry.get("floor", false) and entry["travel"] != null and (entry["travel"] as Vector3).is_zero_approx() and not (entry["normal"] as Vector3).is_zero_approx():
		counts["nowhere"] += 1


func _show(bot: TracedBot, from: Vector3, speed_before: float, cmd: UserCmd, traces: int) -> void:
	print("\nhitch at tick %d, %s at %s: %.1f u/s to %.1f, wishing %s, in %d traces" % [
		_world.tick, bot.name, from, speed_before, Vector2(bot.velocity.x, bot.velocity.z).length(), cmd.wish_direction(), traces])
	for entry in bot.trace_log:
		print("  %-32s %2d casts%s, travel %s, plane %s, pushed %s%s" % [
			str(entry["motion"]), entry["casts"], "" if entry["overlap"] == "" else ", in overlap with the " + entry["overlap"],
			str(entry["travel"]), str(entry["normal"]), str(entry["pushed"]), " (test)" if entry["test"] else ""])


func _report() -> void:
	var casts := 0
	for kind: String in _kinds:
		casts += _kinds[kind]["casts"]
	print("\nover %d ticks and %d bots: %d hitches, %d stops against a wall, %d casts (%.2f a bot a tick), %d ticks of more than 12 traces, the most in one %d" % [
		_ticks, _bots.size(), _hitches, _wall_stops, casts, float(casts) / maxf(_ticks * _bots.size(), 1.0), _busy_ticks, _most_traces])
	var kinds := _kinds.keys()
	kinds.sort()
	print("%-24s %8s %8s %9s %10s %10s %8s %8s" % ["trace", "calls", "casts", "searched", "in world", "in player", "pushed", "nowhere"])
	for kind: String in kinds:
		var counts: Dictionary = _kinds[kind]
		# Only the kinds that matter: a duck's or a landing's odd lengths
		# come to a handful.
		if int(counts["calls"]) < 20:
			continue
		print("%-24s %8d %8d %9d %10d %10d %8d %8d" % [
			kind, counts["calls"], counts["casts"], counts["searched"], counts["world"], counts["player"], counts["pushed"], counts["nowhere"]])
