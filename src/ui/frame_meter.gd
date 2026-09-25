class_name FrameMeter
extends RefCounted

## The frame rate, for the HUDs' readouts: the frames drawn over each second
## and the slowest of them, since an average hides a hitch (a body built, a
## texture read for the first time) that the slowest frame shows. CS2 has
## the same behind cl_showfps, off by default, and shows the frame rate on
## its HUD by itself only when frames are poor
## (cl_hud_telemetry_frametime_show 1).
##
## Its time is the wall clock, Time.get_ticks_usec(), handed in each frame:
## it measures the frames, not the simulation, which keeps SimClock's time.

const WINDOW_USEC := 1000000

## Frames a second over the last whole second; 0 until one has passed.
var fps: float = 0.0
## The longest frame in that second, in milliseconds.
var slowest_ms: float = 0.0

var _last_usec: int = -1
var _window_start_usec: int = -1
var _frames: int = 0
var _slowest_usec: int = 0


## A frame began at now_usec: the one before it ended.
func frame(now_usec: int) -> void:
	if _last_usec < 0:
		_window_start_usec = now_usec
	else:
		_frames += 1
		_slowest_usec = maxi(_slowest_usec, now_usec - _last_usec)
	_last_usec = now_usec
	var elapsed := now_usec - _window_start_usec
	if elapsed >= WINDOW_USEC:
		fps = _frames * 1000000.0 / elapsed
		slowest_ms = _slowest_usec / 1000.0
		_window_start_usec = now_usec
		_frames = 0
		_slowest_usec = 0


## "fps 144   slowest 9.8 ms", or "fps -" until a second has passed.
func line() -> String:
	if fps <= 0.0:
		return "fps -"
	return "fps %d   slowest %.1f ms" % [roundi(fps), slowest_ms]
