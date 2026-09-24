class_name GameSystems
extends RefCounted

## The game's shared state and the systems that run on it: the events, the
## simulated things that are not players, who is playing and what each of
## them carries, and the rules (the bomb, money, and later the match) in the
## order they run.
##
## Whatever owns the tick (the GameWorld, when it lands) runs the players'
## commands and then calls step() once, which runs a tick of every entity,
## then every system in the order added, then hands out the tick's events.
## Systems never call each other; they meet here, through the events, the
## damage record and the inventories (reference/systems/contracts.md).
##
## A system is any object with tick(t: SimTick). If it also has
## attach(game: GameSystems), that is called when it is added, and is where
## it listens for the events it wants.

var events := GameEvents.new()
var entities := SimEntities.new()
var roster := Roster.new()
## The tick being run, or the last one run: for what happens between ticks
## (an event handed out, a command) to know when it is. Null before the
## first step.
var last_tick: SimTick

var _systems: Array = []
var _inventories := {}
var _queries := {}
var _command_handlers := {}
var _commands: Array[Array] = []


func _init() -> void:
	# Everything read from disk is read now, before play.
	ItemRegistry.load_all()
	# The items contract's own system: items on the ground.
	add_system(ItemDrops.new())


## Adds a system, to run after those already added.
func add_system(system: Object) -> void:
	assert(system.has_method(&"tick"), "A system has tick(t: SimTick)")
	_systems.append(system)
	if system.has_method(&"attach"):
		system.call(&"attach", self)


func systems() -> Array:
	return _systems.duplicate()


## Adds a player to the roster, with an inventory holding their armour on
## hit_target: the one the player carries already (a PlayerSim's own, which
## the game then names by their userid), or an empty one. Their userid.
func add_player(player: Node3D, hit_target: HitTarget = null, carried: Inventory = null) -> int:
	var userid := roster.add(player, hit_target)
	if carried != null:
		carried.userid = userid
		if carried.body == null:
			carried.body = hit_target
		_inventories[userid] = carried
	elif not _inventories.has(userid):
		_inventories[userid] = Inventory.new(userid, hit_target)
	return userid


## What a player carries; null for a userid not playing.
func inventory(userid: int) -> Inventory:
	var carried: Inventory = _inventories.get(userid)
	if carried != null and carried.body == null:
		# A player who joined before building their hit target wears their
		# armour on it once they have one.
		carried.body = roster.hit_target(userid)
	return carried


## Answers a question about the game's state for anyone who asks it by
## name: the grenades answer how much smoke lies between two points, for
## bots' sight and a death's thrusmoke, and how blind a player is. The one
## who knows provides it, usually in attach(); the one who asks never holds
## the system that answers. The names and what they take are listed in
## reference/systems/contracts.md. A second provider replaces the first.
func provide(query_name: StringName, answer: Callable) -> void:
	_queries[query_name] = answer


## The answer to a named question, with args; fallback when nothing has
## answered it (no grenades system: no smoke, nobody blind).
func query(query_name: StringName, args: Array = [], fallback: Variant = null) -> Variant:
	var answer: Callable = _queries.get(query_name, Callable())
	if not answer.is_valid():
		return fallback
	return answer.callv(args)


func provides(query_name: StringName) -> bool:
	return _queries.has(query_name) and (_queries[query_name] as Callable).is_valid()


## A player's command, as CS2's console has them: "buy ak47", "drop". Not
## part of a UserCmd, since a command is sent once rather than held; queued,
## and run at the start of the next step in the order they came.
func command(userid: int, line: String) -> void:
	var words := line.strip_edges().split(" ", false)
	if words.is_empty():
		return
	_commands.append([userid, StringName(words[0]), words.slice(1)])


## Takes a command by its name. handler(userid: int, args: PackedStringArray,
## t: SimTick) -> bool says whether it took it. Several may take the same
## command, each for its own case ("drop" is ItemDrops' for what is in hand,
## the bomb's with the C4 in hand); they are asked in the order they were
## added until one takes it, so each must take only its own case.
func on_command(command_name: StringName, handler: Callable) -> void:
	if not _command_handlers.has(command_name):
		var list: Array[Callable] = []
		_command_handlers[command_name] = list
	(_command_handlers[command_name] as Array[Callable]).append(handler)


## Simulation time now: the end of the tick being run or last run.
func now_usec() -> int:
	return last_tick.now_usec if last_tick != null else SimClock.now_usec()


## One tick: the players' commands, every entity, then every system, then the
## tick's events handed out. space is where traces go (null with no world,
## in a test).
func step(tick: int, space: PhysicsDirectSpaceState3D = null) -> SimTick:
	var t := SimTick.new(self, tick, space)
	last_tick = t
	_run_commands(t)
	entities.tick_all(t)
	for system in _systems:
		system.call(&"tick", t)
	events.flush()
	return t


func _run_commands(t: SimTick) -> void:
	var queued := _commands
	_commands = []
	for queued_command in queued:
		var handlers: Array = _command_handlers.get(queued_command[1], [])
		for handler: Callable in handlers:
			if handler.is_valid() and handler.call(queued_command[0], queued_command[2], t):
				break
