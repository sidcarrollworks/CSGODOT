extends SceneTree

## Where a walking bot's tick goes, function by function: bots walk dust2's
## site routes as tests/run_dust2_bot_checks.gd has them, holding fire, and
## a bot script overrides each function of the tick to put a clock round
## it. A function's own time is what is left once the functions it called
## are taken out, and the clocks' own cost with them (measured first, on
## empty pairs). scripts/profile_box3d_costs.gd splits the same tick by the
## bridge's parts; this splits it by the movement's
## (reference/research/box3d-walking-hitch-2026-09-28.md). The clocks are
## one thread's, so the bots think in turn here, which is the same
## commands as on the worker threads.
##
##   godot --headless --path . --script scripts/profile_player_tick.gd -- 5 60
##   godot --headless --path . --script scripts/profile_player_tick.gd -- 5 60 --movement native
##
## Bots (5) and seconds of game (60), run at eight ticks a frame. The
## overrides must keep the signatures of the functions they wrap. Needs
## dust2 and its nav mesh extracted.
##
## The script runs the movement's step here, the clocks being in its
## functions (a body with its own of them is the script's to step,
## PlayerBody.STEP_FUNCTIONS). `--movement native` has the native code run
## it, as the game does where it is built: the step is then one call,
## inside `simulate`'s own time, and the lines under it are gone.

class TimedBot:
	extends Bot

	static var labels: PackedStringArray = []
	static var inclusive := PackedInt64Array()
	static var exclusive := PackedInt64Array()
	static var calls := PackedInt64Array()
	static var child_calls := PackedInt64Array()
	static var stack_id := PackedInt32Array()
	static var stack_start := PackedInt64Array()
	static var stack_children := PackedInt64Array()
	static var depth := 0

	static func id_of(label: String) -> int:
		var at := labels.find(label)
		if at < 0:
			at = labels.size()
			labels.append(label)
			inclusive.append(0)
			exclusive.append(0)
			calls.append(0)
			child_calls.append(0)
		return at

	static func enter(id: int) -> void:
		if depth >= stack_id.size():
			stack_id.append(0)
			stack_start.append(0)
			stack_children.append(0)
		stack_id[depth] = id
		stack_children[depth] = 0
		depth += 1
		stack_start[depth - 1] = Time.get_ticks_usec()

	static func leave() -> void:
		var now := Time.get_ticks_usec()
		depth -= 1
		var id := stack_id[depth]
		var took := now - stack_start[depth]
		inclusive[id] += took
		exclusive[id] += took - stack_children[depth]
		calls[id] += 1
		if depth > 0:
			stack_children[depth - 1] += took
			child_calls[stack_id[depth - 1]] += 1

	static var PREPARE := id_of("prepare_to_think (its shopping, its way found)")
	static var COMMAND_FOR := id_of("think (the bot thinks)")
	static var LOOK := id_of("  _look_for_target")
	static var WAY := id_of("  _way_on")
	static var RUN_COMMAND := id_of("run_command (and the body's animation parameters)")
	static var RUN := id_of("  _run")
	static var WEAPON := id_of("    _update_weapon")
	static var HITS := id_of("    _recover_from_hits")
	static var HELD := id_of("    _held_by_the_game")
	static var SIMULATE := id_of("    simulate")
	static var STEP := id_of("      _simulate_step")
	static var DUCK := id_of("        _update_duck")
	static var WALK := id_of("        _walk_move")
	static var AIR := id_of("        _air_move")
	static var STEP_MOVE := id_of("          _step_move")
	static var TRY := id_of("            _try_player_move")
	static var STAY := id_of("          _stay_on_ground")
	static var GROUND := id_of("        _categorize_position")
	static var UPDATE_AIR := id_of("      _update_air")
	static var TRACE := id_of("              _trace (each)")
	static var CAST := id_of("                _cast_hull (the bridge and the native cast)")

	func prepare_to_think(tick: int) -> void:
		enter(PREPARE)
		super(tick)
		leave()

	func think(tick: int, dt: float) -> UserCmd:
		enter(COMMAND_FOR)
		var cmd := super(tick, dt)
		leave()
		return cmd

	func _look_for_target() -> Node3D:
		enter(LOOK)
		var found := super()
		leave()
		return found

	func _way_on(cmd: UserCmd, delta: float) -> Vector3:
		enter(WAY)
		var way := super(cmd, delta)
		leave()
		return way

	func run_command(cmd: UserCmd, dt: float) -> void:
		enter(RUN_COMMAND)
		super(cmd, dt)
		leave()

	func _run(cmd: UserCmd, dt: float) -> void:
		enter(RUN)
		super(cmd, dt)
		leave()

	func _update_weapon(cmd: UserCmd, dt: float, still: bool) -> void:
		enter(WEAPON)
		super(cmd, dt, still)
		leave()

	func _recover_from_hits(dt: float) -> void:
		enter(HITS)
		super(dt)
		leave()

	func _held_by_the_game() -> bool:
		enter(HELD)
		var held := super()
		leave()
		return held

	func simulate(dt: float) -> void:
		enter(SIMULATE)
		super(dt)
		leave()

	func _simulate_step(dt: float) -> void:
		enter(STEP)
		super(dt)
		leave()

	func _update_duck(dt: float) -> void:
		enter(DUCK)
		super(dt)
		leave()

	func _walk_move(surface_friction: float, dt: float) -> void:
		enter(WALK)
		super(surface_friction, dt)
		leave()

	func _air_move(surface_friction: float, dt: float) -> void:
		enter(AIR)
		super(surface_friction, dt)
		leave()

	func _step_move(dt: float) -> bool:
		enter(STEP_MOVE)
		var moved := super(dt)
		leave()
		return moved

	func _try_player_move(dt: float) -> bool:
		enter(TRY)
		var met := super(dt)
		leave()
		return met

	func _stay_on_ground() -> void:
		enter(STAY)
		super()
		leave()

	func _categorize_position() -> void:
		enter(GROUND)
		super()
		leave()

	func _update_air(was_on_ground: bool) -> void:
		enter(UPDATE_AIR)
		super(was_on_ground)
		leave()

	func _trace(motion: Vector3, test_only: bool = false) -> PlayerBody.TraceResult:
		enter(TRACE)
		var result := super(motion, test_only)
		leave()
		return result

	func _cast_hull(queries: Box3DQueries) -> Dictionary:
		enter(CAST)
		var hit := super(queries)
		leave()
		return hit


var _bots_wanted := 5
var _seconds := 60.0
var _world: GameWorld
var _bots: Array[Bot] = []
var _ticks := 0
var _end_tick := 0
var _started := false
var _pair_usec := 0.0
var _moving := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_bots_wanted = maxi(1, int(args[0]))
	if args.size() > 1:
		_seconds = maxf(1.0, float(args[1]))
	_run()


## Whether the command line asks for the native code by name.
func _native_asked_for() -> bool:
	return PlayerBody.movement_named(OS.get_cmdline_user_args(), "") == "native"


func _run() -> void:
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
		bot.set_script(TimedBot)
		bot.native_over_own_functions = _native_asked_for()
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
	_world.set_physics_process(false)
	# What a pair of clocks costs by itself.
	var probe := TimedBot.id_of("(an empty pair of clocks)")
	var outer := Time.get_ticks_usec()
	for i in 200000:
		TimedBot.enter(probe)
		TimedBot.leave()
	_pair_usec = float(Time.get_ticks_usec() - outer) / 200000.0
	for i in TimedBot.labels.size():
		TimedBot.inclusive[i] = 0
		TimedBot.exclusive[i] = 0
		TimedBot.calls[i] = 0
		TimedBot.child_calls[i] = 0
	_end_tick = SimClock.ticks_in(_seconds)
	print("player tick: %d bots for %d ticks, physics %s, a pair of clocks %.2f us" % [_bots.size(), _end_tick, _world.drop_physics_backend, _pair_usec])
	print("the bots think in turn here whatever --think says, the clocks being one thread's")
	if not _native_asked_for():
		print("the script runs the movement's step (--movement native for the native code, the step then one call in simulate's own time)")
	elif PlayerBody.native_built():
		print("the native code runs the movement's step, inside simulate's own time")
	else:
		print("the native code was asked for and the script runs the movement's step: %s" % PlayerBody.native_missing)
	_started = true


func _physics_process(_delta: float) -> bool:
	if not _started:
		return false
	_world.begin_tick()
	var dt := SimClock.tick_seconds()
	_world.think_on_threads = false
	var running := _world.playing()
	var commands := _world.commands_for(running, dt)
	for i in running.size():
		var player := running[i]
		if player.is_inside_tree():
			player.run_command(commands[i], dt)
			if Vector2(player.velocity.x, player.velocity.z).length() > 100.0:
				_moving += 1
	_world.end_tick()
	_ticks += 1
	if _ticks < _end_tick:
		return false
	var bot_ticks := float(_ticks * _bots.size())
	print("\n%d of %d bot ticks at a run. Microseconds a bot a tick, the clocks' own cost taken out:" % [_moving, int(bot_ticks)])
	print("%-66s %9s %9s %9s" % ["", "calls", "inclusive", "own"])
	# The clocks inside a function's own time: a pair for each function it
	# called.
	for i in TimedBot.labels.size():
		if TimedBot.calls[i] == 0:
			continue
		var own := float(TimedBot.exclusive[i]) - float(TimedBot.child_calls[i]) * _pair_usec
		print("%-66s %9.2f %9.1f %9.1f" % [
			TimedBot.labels[i], float(TimedBot.calls[i]) / bot_ticks,
			float(TimedBot.inclusive[i]) / bot_ticks, own / bot_ticks])
	quit(0)
	return true
