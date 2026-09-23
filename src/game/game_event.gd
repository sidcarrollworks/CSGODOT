class_name GameEvent
extends RefCounted

## One thing that happened in the game, as CS2 reports it: a name from
## GameEvents.SCHEMA and that event's keys, as plain values (ints, floats,
## bools, strings) with players named by userid, never by node. Plain data
## is what can be sent to a client, recorded, or compared in a test.
##
## Listeners read fields and never change them: every listener is handed
## the same event.

var name: StringName
## The tick it happened on.
var tick: int = 0
## When in that tick it happened, in microseconds of simulation time: a
## round's own instant, or the tick's end for whatever has no instant of
## its own.
var at_usec: int = 0
var fields: Dictionary = {}


func _init(p_name: StringName = &"", p_fields: Dictionary = {}, p_tick: int = 0, p_at_usec: int = 0) -> void:
	name = p_name
	fields = p_fields
	tick = p_tick
	at_usec = p_at_usec


func _to_string() -> String:
	return "%s@%d %s" % [name, tick, fields]
