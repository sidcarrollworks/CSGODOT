class_name SimEntity
extends RefCounted

## A simulated thing that is not a player: a grenade in flight, a fire, a
## smoke, the planted bomb, a gun or the C4 lying on the ground.
##
## It lives in SimEntities, which gives it an id and runs its tick() once a
## simulation tick; whatever draws it reads it per frame, between
## previous_position and position. Its timers are deadlines in microseconds
## of simulation time (SimClock), so they save and restore as plain numbers.
## A system extends this for its own things and overrides tick(), and
## save_state() and load_state() for what it adds.

## Given by SimEntities.spawn; what events call entityid. 0 until spawned.
var id: int = 0
## CS2's class for it: "hegrenade_projectile", "smokegrenade_projectile",
## "inferno", "planted_c4", or a dropped item's own ("weapon_c4",
## "weapon_ak47").
var entity_class: String = ""
## Whose it is, by userid: the thrower, the planter, who dropped it.
var owner_id: int = GameEvents.NOBODY
var position := Vector3.ZERO
## Where the tick before left it, for drawing between the two.
var previous_position := Vector3.ZERO
## The tick it was spawned on.
var spawned_tick: int = 0
## Set by remove(): SimEntities lets it go after the tick.
var removed: bool = false


func _init(p_entity_class: String = "", p_owner_id: int = GameEvents.NOBODY, p_position := Vector3.ZERO) -> void:
	entity_class = p_entity_class
	owner_id = p_owner_id
	position = p_position
	previous_position = p_position


## One tick of it. SimEntities keeps previous_position; what moves it sets
## position.
func tick(_t: SimTick) -> void:
	pass


## Takes it out of the world once this tick is over.
func remove() -> void:
	removed = true


## What it is, as plain data. A subclass adds its own and calls this.
func save_state() -> Dictionary:
	return {
		"id": id, "entity_class": entity_class, "owner_id": owner_id,
		"position": position, "previous_position": previous_position,
		"spawned_tick": spawned_tick, "removed": removed,
	}


func load_state(state: Dictionary) -> void:
	id = state.get("id", id)
	entity_class = state.get("entity_class", entity_class)
	owner_id = state.get("owner_id", owner_id)
	position = state.get("position", position)
	previous_position = state.get("previous_position", previous_position)
	spawned_tick = state.get("spawned_tick", spawned_tick)
	removed = state.get("removed", removed)
