class_name DrawClock
extends RefCounted

## Where between the last two ticks a frame being drawn falls, and the
## simulation time it shows. For what is drawn and heard, never for the
## simulation, which keeps SimClock's ticks.
##
## Godot's own fraction (Engine.get_physics_interpolation_fraction()) is
## taken at the start of a frame, before that frame's ticks run. A frame
## that runs a tick (4.5 ms with ten players on dust2, measured on Sid's
## machine) is drawn that much later than its fraction says, so every third
## or fourth frame showed the world a little behind: judder, 1.6 ms off a
## steady motion. This takes the fraction from the wall clock when it is
## asked, measured from where on the clock the frame's last tick stood (the
## frame's start, less Godot's fraction of a tick), and holds it at the
## latest tick rather than guess past it: 0.5 to 0.7 ms off. It needs the
## ticks kept to the clock, physics_jitter_fix 0 (project.godot).

static var _tick_clock_usec := -1
static var _frame := -1
static var _listening := false


## How far between the last two ticks a frame drawn now falls, 0 to 1.
static func fraction() -> float:
	if not _listening:
		_listen()
	if _tick_clock_usec < 0:
		return clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	return clampf(float(Time.get_ticks_usec() - _tick_clock_usec) / float(SimClock.tick_usec()), 0.0, 1.0)


## The simulation time a frame drawn now shows: between the last two ticks,
## as far as fraction() says.
static func usec() -> int:
	var tick := SimClock.tick_usec()
	return SimClock.now_usec() - tick + int(fraction() * tick)


static func _listen() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.physics_frame.connect(_ticked)
	_listening = true


## At a frame's first tick, before it runs: where on the clock the last
## tick of the frame stands.
static func _ticked() -> void:
	if Engine.get_process_frames() == _frame:
		return
	_frame = Engine.get_process_frames()
	_tick_clock_usec = Time.get_ticks_usec() - int(Engine.get_physics_interpolation_fraction() * SimClock.tick_usec())
