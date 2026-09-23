class_name SimTick
extends RefCounted

## One simulation tick, as handed to every entity and system that runs in it:
## which tick, the stretch of simulation time it covers, the physics space
## to trace in, and the game (its events, entities, roster and inventories).

var tick: int = 0
## The tick covers (start_usec, now_usec] of simulation time (SimClock).
var start_usec: int = 0
var now_usec: int = 0
## Its length in seconds.
var dt: float = 0.0
## Where traces go; null in a test with no world.
var space: PhysicsDirectSpaceState3D
var game: GameSystems

var events: GameEvents:
	get: return game.events

var entities: SimEntities:
	get: return game.entities

var roster: Roster:
	get: return game.roster


func _init(p_game: GameSystems, p_tick: int, p_space: PhysicsDirectSpaceState3D = null) -> void:
	game = p_game
	tick = p_tick
	start_usec = SimClock.tick_start_usec(p_tick)
	now_usec = SimClock.tick_end_usec(p_tick)
	dt = SimClock.tick_seconds()
	space = p_space
