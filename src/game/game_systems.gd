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

var _systems: Array = []
var _inventories := {}
var _queries := {}


func _init() -> void:
	# Everything read from disk is read now, before play.
	ItemRegistry.load_all()


## Adds a system, to run after those already added.
func add_system(system: Object) -> void:
	assert(system.has_method(&"tick"), "A system has tick(t: SimTick)")
	_systems.append(system)
	if system.has_method(&"attach"):
		system.call(&"attach", self)


func systems() -> Array:
	return _systems.duplicate()


## Adds a player to the roster, with an empty inventory holding their armour
## on hit_target. Their userid.
func add_player(player: Node3D, hit_target: HitTarget = null) -> int:
	var userid := roster.add(player, hit_target)
	if not _inventories.has(userid):
		_inventories[userid] = Inventory.new(userid, hit_target)
	return userid


## What a player carries; null for a userid not playing.
func inventory(userid: int) -> Inventory:
	return _inventories.get(userid)


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


## One tick: every entity, then every system, then the tick's events handed
## out. space is where traces go (null with no world, in a test).
func step(tick: int, space: PhysicsDirectSpaceState3D = null) -> SimTick:
	var t := SimTick.new(self, tick, space)
	entities.tick_all(t)
	for system in _systems:
		system.call(&"tick", t)
	events.flush()
	return t
