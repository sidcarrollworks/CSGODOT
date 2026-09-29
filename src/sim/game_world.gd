class_name GameWorld
extends Node

## The simulation's owner: it runs the tick.
##
## Every tick it asks each player for one command (your keys, a bot's
## choices, later what a client sends: PlayerSim.command_for), all of them
## from the world as the last tick left it, as a server has its clients'
## commands before it runs any; then runs the players one after another in
## the order they joined, and then the rules on the tick they have just
## run: the match, and after it the economy when there is one (roadmap item
## 13). The bots think on worker threads, all at once (commands_for). No player ticks itself and neither does the
## match, so nothing that decides the game runs anywhere else, and the order
## things run in is this one rather than whatever order they were added to the
## scene. It is what CS2's server is to its players; single player is this
## running on the same machine as the one who plays, a listen server.
##
## It counts its own ticks from the moment it starts, and SimClock reads the
## count, so simulation time starts with the game rather than with the
## process, and a check can hold the world and step it itself (step()). What
## is only drawn or heard of the players (the view and footsteps) runs
## on the engine's ticks as before, after the world's, so it reads the tick
## just run. Ragdoll physics advances in this world's shared native step;
## only its skeleton drawing runs between ticks.
##
## It also holds what a tick gives out, so each tick starts afresh: the nav
## mesh's path searches, and the game's shared state (game): its events,
## its simulated things (grenades, the bomb, dropped guns), who is playing
## and what each carries, and the systems that run after the match
## (reference/systems/contracts.md).

## How many paths over the nav mesh may be searched for in one tick. A search
## takes half a millisecond, and at a round's start every bot wants one on the
## same tick: nine to twenty searches, a tick of five to ten ms. The rest wait
## a tick or two, standing, which freeze time hides.
const PATH_SEARCHES_PER_TICK := 2

## How many have to be thinking for the worker threads to be woken for it.
const THINK_TOGETHER_FROM := 2
## How many worker threads the thinking is shared between at most. Waking a
## thread costs, and nine bots' thinking is a third of a millisecond: in
## dust2's match four threads were worth 0.2 ms at the tick's 95th and
## nothing at its mean, every thread the machine has (16) no more at the
## 95th and 0.05 ms worse at the mean, and two nothing at either
## (reference/research/box3d-walking-hitch-2026-09-28.md).
const THINK_THREADS := 4
## The project setting that says where the bots think, "threads" or "main";
## the command line's --think <where> wins over it.
const THINK_SETTING := "csgodot/simulation/think"

## The world being run, whose tick SimClock reads: the last one into the
## scene tree. There is one at a time, as a server runs one match.
static var current: GameWorld

## Everyone in the game, in the order they run in a tick, which is the order
## they joined in.
var players: Array[PlayerSim] = []

## The match, run after the players every tick; null where there is none
## (the test range). Everyone in the world is in it, whenever they joined,
## and it says what the round is doing into the world's events.
var match_state: MatchState:
	set(value):
		if is_instance_valid(match_state) and match_state != value:
			match_state.events = null
		match_state = value
		if value != null:
			value.events = game.events
			for player in players:
				value.add_player(player)

## The tick being run, or between ticks the last one run. The first is 1.
var tick: int = 0

## The game's events, entities, roster, inventories and systems, stepped at
## the end of every tick, after the match (GameSystems.step).
var game := GameSystems.new()

## Whether the bots think on worker threads (configured_thinking).
var think_on_threads: bool = configured_thinking() == "threads"
## How many worker threads the bots' thinking is shared between at most; -1
## for as many as there are thinkers and workers.
var think_tasks: int = THINK_THREADS

var _path_searches_left: int = PATH_SEARCHES_PER_TICK
## Who is thinking on the worker threads, for the tick being run.
var _thinkers: Array[PlayerSim] = []
var _think_dt := 0.0
var _drop_physics_initialized: bool = false
var drop_physics_backend: String = ""


func _init() -> void:
	# Before every other node's physics callback, so what is drawn or heard of
	# the players reads the tick they have just run.
	process_physics_priority = -1000


func _enter_tree() -> void:
	current = self


func _ready() -> void:
	# The containing map builds collision after adding this world. Prepare
	# once after its scene setup, before allowing automatic simulation ticks.
	initialize_drop_physics.call_deferred()


## Explicit for fixtures and profilers. A missing requested addon is an
## error, never a silent switch back to the legacy solver.
func initialize_drop_physics(geometry_root: Node = null, backend: String = "") -> bool:
	if _drop_physics_initialized:
		return true
	if backend.is_empty():
		backend = configured_drop_physics()
	if backend == "legacy":
		drop_physics_backend = backend
		_drop_physics_initialized = true
		return true
	if backend != "box3d":
		push_error("Unknown game physics '%s'; use --physics box3d or legacy." % backend)
		return false
	var adapter := Box3DDrops.new()
	adapter.name = "Box3DPhysics"
	add_child(adapter)
	if not adapter.initialize(game, geometry_root if geometry_root != null else get_parent(), true):
		adapter.free()
		return false
	drop_physics_backend = backend
	_drop_physics_initialized = true
	print("Game physics: Box3D (%d static shapes, %d triangles)" % [adapter.captured_shapes, adapter.captured_triangles])
	return true


static func configured_drop_physics() -> String:
	var backend := String(ProjectSettings.get_setting("csgodot/physics/backend", "box3d"))
	for args in [OS.get_cmdline_args(), OS.get_cmdline_user_args()]:
		for i in args.size():
			if args[i] in ["--physics", "--drop-physics"] and i + 1 < args.size():
				backend = args[i + 1]
			elif String(args[i]).begins_with("--physics="):
				backend = String(args[i]).trim_prefix("--physics=")
			elif String(args[i]).begins_with("--drop-physics="):
				backend = String(args[i]).trim_prefix("--drop-physics=")
	return backend.to_lower()


## Where the bots think: "threads", all at once on the worker threads, or
## "main", one after another on the thread that runs the tick. The same
## commands either way. Anything else is said to be neither, and is
## "threads".
static func configured_thinking() -> String:
	var where := String(ProjectSettings.get_setting(THINK_SETTING, "threads"))
	for args in [OS.get_cmdline_args(), OS.get_cmdline_user_args()]:
		for i in args.size():
			if args[i] == "--think" and i + 1 < args.size():
				where = args[i + 1]
			elif String(args[i]).begins_with("--think="):
				where = String(args[i]).trim_prefix("--think=")
	where = where.to_lower()
	if where not in ["threads", "main"]:
		push_warning("--think and %s take \"threads\" or \"main\", not \"%s\": the bots think on the worker threads" % [THINK_SETTING, where])
		return "threads"
	return where


func _exit_tree() -> void:
	if current == self:
		current = null


## Someone joins, to run from the next tick on, after everyone already here.
func add_player(player: PlayerSim) -> void:
	if players.has(player):
		return
	players.append(player)
	player.world = self
	player.userid = game.add_player(player, player.hit_target, player.inventory)
	# What is in hand is drawn on this world's clock, from now.
	player.draw_again()
	if match_state != null:
		match_state.add_player(player)


## Someone leaves the game, and its match; a player out of the scene tree
## leaves by itself.
func remove_player(player: PlayerSim) -> void:
	players.erase(player)
	game.roster.remove(game.roster.userid_of(player))
	if player.world == self:
		player.world = null
		player.userid = GameEvents.NOBODY
	if is_instance_valid(match_state):
		match_state.remove_player(player)


func _physics_process(_delta: float) -> void:
	if not _drop_physics_initialized:
		return
	step()


## One tick: everyone's command, then each run, in order, then the rules.
func step() -> void:
	begin_tick()
	var dt := SimClock.tick_seconds()
	var running := playing()
	var commands := commands_for(running, dt)
	for i in running.size():
		if running[i].is_inside_tree():
			running[i].run_command(commands[i], dt)
	end_tick()


## Who runs this tick, in the order they run: everyone in the scene tree.
func playing() -> Array[PlayerSim]:
	var running: Array[PlayerSim] = []
	for player in players:
		if player.is_inside_tree():
			running.append(player)
	return running


## Everyone's command for the tick, in their order, each from the world as
## the last tick left it. Whoever can think apart (the bots) does what of
## its thinking touches what is shared first, here, in its turn
## (PlayerSim.prepare_to_think: its shopping, its way found), and the rest
## on a worker thread, all of them at once, while this thread waits: they
## read the world and write only themselves. Everyone else, you among them,
## is asked here, in turn.
func commands_for(running: Array[PlayerSim], dt: float) -> Array[UserCmd]:
	var commands: Array[UserCmd] = []
	commands.resize(running.size())
	_thinkers.clear()
	var places := PackedInt32Array()
	for i in running.size():
		var player := running[i]
		if player.thinks_apart():
			player.prepare_to_think(tick)
			_thinkers.append(player)
			places.append(i)
		else:
			commands[i] = player.command_for(tick, dt)
	# On Godot's own physics they think in turn: its space is for the thread
	# that runs the tick.
	var queries := _native_queries()
	# Those with something to think about: in freeze time nobody has, and
	# the threads' waking was a fifth of a millisecond for nothing.
	var busy := 0
	for thinker in _thinkers:
		if thinker.alive and not thinker.frozen:
			busy += 1
	if not think_on_threads or queries == null or busy < THINK_TOGETHER_FROM:
		for i in _thinkers.size():
			commands[places[i]] = _thinkers[i].think(tick, dt)
		_thinkers.clear()
		return commands
	queries.begin_reading()
	# Where a node is in the world is worked out when it is first asked
	# for after a move, and kept: asked for here, so that the threads only
	# read what is kept.
	for player in running:
		var _kept := player.global_transform
	_think_dt = dt
	var task := WorkerThreadPool.add_group_task(_think_apart, _thinkers.size(), think_tasks, true, "The bots thinking")
	WorkerThreadPool.wait_for_group_task_completion(task)
	queries.end_reading()
	for i in _thinkers.size():
		var cmd := _thinkers[i].thought()
		if cmd == null:
			# Its thinking failed on its thread, and said why there: it
			# stands this tick rather than the tick fail with it.
			cmd = _thinkers[i].standing(tick)
		commands[places[i]] = cmd
	_thinkers.clear()
	return commands


## One of the thinkers, on a worker thread.
func _think_apart(index: int) -> void:
	# Nodes are read here, none written but the thinker's own: the checks
	# that keep a thread off the scene tree are for writers.
	Thread.set_thread_safety_checks_enabled(false)
	_thinkers[index].think_apart(tick, _think_dt)
	Thread.set_thread_safety_checks_enabled(true)


## A tick starts: its number, and what it has to give out.
func begin_tick() -> void:
	tick += 1
	_path_searches_left = PATH_SEARCHES_PER_TICK
	var queries := _native_queries()
	if queries != null:
		queries.begin_tick()


## The tick ends, every player having run it: the match judges it, then the
## game's own systems run and the tick's events are handed out.
func end_tick() -> void:
	if is_instance_valid(match_state):
		match_state.tick(SimClock.tick_end_usec(tick))
	var viewport := get_viewport() if is_inside_tree() else null
	game.step(tick, viewport.find_world_3d().direct_space_state if viewport != null else null)
	var queries := _native_queries()
	if queries != null:
		queries.end_tick()


## The native physics' queries, which are told when a tick begins and ends;
## null on Godot's own physics.
func _native_queries() -> Box3DQueries:
	return game.drop_physics.queries if is_instance_valid(game.drop_physics) else null


## Whether a path over the nav mesh may be searched for this tick, counting
## the search if so (PATH_SEARCHES_PER_TICK).
func may_search_path() -> bool:
	if _path_searches_left <= 0:
		return false
	_path_searches_left -= 1
	return true
