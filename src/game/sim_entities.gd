class_name SimEntities
extends RefCounted

## Every SimEntity in the game, and the one place they are ticked from.
##
## They run in the order they were spawned, so the same commands always give
## the same game. One spawned during a tick (a grenade's fire) first runs on
## the next, and one removed goes once the tick is over, so nothing is
## skipped or run twice in the tick it changes. Presenters draw them per
## frame and hear of them coming and going through spawned and removed.

signal spawned(entity: SimEntity)
signal removed(entity: SimEntity)

var _entities: Array[SimEntity] = []
var _next_id: int = 1


## Puts it in the world with an id of its own, which is returned.
func spawn(entity: SimEntity) -> int:
	entity.id = _next_id
	_next_id += 1
	entity.spawned_tick = SimClock.current_tick()
	entity.removed = false
	_entities.append(entity)
	spawned.emit(entity)
	return entity.id


## The one with that id, or null.
func find(id: int) -> SimEntity:
	for entity in _entities:
		if entity.id == id and not entity.removed:
			return entity
	return null


## Every one of a class, in spawn order. A copy.
func of_class(entity_class: String) -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for entity in _entities:
		if entity.entity_class == entity_class and not entity.removed:
			out.append(entity)
	return out


## Every one, in spawn order. A copy.
func all() -> Array[SimEntity]:
	var out: Array[SimEntity] = []
	for entity in _entities:
		if not entity.removed:
			out.append(entity)
	return out


func size() -> int:
	return all().size()


## Runs one tick of every entity there was when it began, then lets the
## removed ones go.
func tick_all(t: SimTick) -> void:
	var running := _entities.duplicate()
	for entity: SimEntity in running:
		if entity.removed:
			continue
		entity.previous_position = entity.position
		entity.tick(t)
	_let_go()


## Every entity gone: a round's start, as CS2 clears the map of grenades,
## fires and dropped guns.
func clear() -> void:
	for entity in _entities:
		entity.removed = true
	_let_go()


func _let_go() -> void:
	var kept: Array[SimEntity] = []
	var gone: Array[SimEntity] = []
	for entity in _entities:
		(gone if entity.removed else kept).append(entity)
	_entities = kept
	for entity in gone:
		removed.emit(entity)
