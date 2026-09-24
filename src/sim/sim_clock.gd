class_name SimClock
extends RefCounted

## The simulation's time, counted in ticks rather than read off the wall.
##
## Every timer the game keeps (a weapon's next round, a reload, the recoil
## decaying, a respawn) is measured in microseconds of simulation time: tick
## number times the tick length, plus how far into the tick something
## happened. Nothing in the simulation calls Time.get_ticks_usec(), so a tick
## run late, run twice on a client predicting, or run on a server, comes out
## the same. The wall clock stays where it belongs, in input (when a key went
## down) and drawing (how far between two ticks a frame falls).


## One tick, in microseconds of simulation time.
static func tick_usec() -> int:
	return int(1_000_000.0 / float(Engine.physics_ticks_per_second))


## One tick, in seconds.
static func tick_seconds() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


## How many ticks a stretch of simulation time takes, to the nearest.
static func ticks_in(seconds: float) -> int:
	return roundi(seconds * float(Engine.physics_ticks_per_second))


## The tick being simulated now: the world's count (GameWorld.tick), which
## starts with the game. With no world (a check that runs its players by
## hand), the engine's.
static func current_tick() -> int:
	var world := GameWorld.current
	if world != null and is_instance_valid(world):
		return world.tick
	return Engine.get_physics_frames()


## A tick covers the stretch of simulation time that ends at tick x tick
## length: tick N runs the game from where tick N - 1 left it to N ticks in.
## Its commands' sub-tick fractions are fractions of that stretch.
static func tick_start_usec(tick: int) -> int:
	return (tick - 1) * tick_usec()


static func tick_end_usec(tick: int) -> int:
	return tick * tick_usec()


## Simulation time a fraction of the way through a tick.
static func usec_at(tick: int, fraction: float) -> int:
	return tick_start_usec(tick) + int(roundf(clampf(fraction, 0.0, 1.0) * float(tick_usec())))


## Simulation time now: the end of the current tick, which is where the game
## stands once it has run. Outside a tick (a frame being drawn) it is the end
## of the last one.
static func now_usec() -> int:
	return tick_end_usec(current_tick())


## The simulation time a frame being drawn falls at: between the last two
## ticks, as far as the frame is between them. For what is drawn and heard,
## never for the simulation.
static func draw_usec() -> int:
	var tick := tick_usec()
	return now_usec() - tick + int(clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0) * tick)
