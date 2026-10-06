class_name JumpCameraMotion
extends RefCounted

## A small dip of the eyes on takeoff and landing, then a smooth recovery.
## Presentation only: PlayerBody's eye height, aim and movement stay on the
## simulation. Driven by its air_action stamp and DrawClock, so a frame
## repeats no impulse, and the spring is the same at any drawing rate.
## The amounts are by eye for Sid's PR #160 feedback, not measured CS2
## constants (reference/research/jump-camera.md).

## A critically damped spring: about 1 unit of takeoff dip and 0.8 on landing,
## deepest after 50 ms and almost at rest after 0.3 s. No upward overshoot.
## The landing's was 1.6 until Sid found it too much (playtest 2026-10-05)
## and halved it.
const RESPONSE := 20.0
const TAKEOFF_PUSH := 55.0
const LAND_PUSH := 44.0
const MAX_DIP := 4.0
## Brief losses of ground on steps do not shake the camera. A full jump or
## a fall lasting at least 0.3 s gets the full landing response.
const LAND_MIN_AIR := 0.08
const LAND_FULL_AIR := 0.3

var height := 0.0
var _speed := 0.0
var _at_usec := 0
var _seen_action_usec := 0
var _air_since_usec := -1
var _started := false


## Drawn height relative to the usual eyes, in world-up units. A newly
## received action waits until the interpolated view reaches its tick.
func update_at(now_usec: int, action: StringName, action_usec: int) -> float:
	if not _started or now_usec < _at_usec:
		reset()
		_started = true
		_at_usec = now_usec
		_seen_action_usec = mini(action_usec, now_usec)
		return height
	if action_usec > _seen_action_usec and action_usec <= now_usec:
		_advance(action_usec)
		_seen_action_usec = action_usec
		if action == PlayerBody.AIR_JUMP:
			_air_since_usec = action_usec
			_speed -= TAKEOFF_PUSH
		elif action == PlayerBody.AIR_START_FALL:
			_air_since_usec = action_usec
		elif action == PlayerBody.AIR_LAND:
			if _air_since_usec >= 0:
				var in_air := float(action_usec - _air_since_usec) / 1000000.0
				_speed -= LAND_PUSH * smoothstep(LAND_MIN_AIR, LAND_FULL_AIR, in_air)
			_air_since_usec = -1
	_advance(now_usec)
	return height


## A spawn, teleport, death or noclip starts from the normal eye height,
## without replaying the body's last air action.
func reset() -> void:
	height = 0.0
	_speed = 0.0
	_air_since_usec = -1
	_started = false


## The exact spring solution, rather than Euler steps that change their
## shape with frame rate. The event adds velocity, so height is continuous
## even when a new jump interrupts the landing's recovery.
func _advance(now_usec: int) -> void:
	var seconds := float(maxi(now_usec - _at_usec, 0)) / 1000000.0
	_at_usec = now_usec
	if seconds <= 0.0 or (height == 0.0 and _speed == 0.0):
		return
	var combined := _speed + RESPONSE * height
	var decay := exp(-RESPONSE * seconds)
	height = (height + combined * seconds) * decay
	_speed = (_speed - RESPONSE * combined * seconds) * decay
	if height < -MAX_DIP:
		height = -MAX_DIP
		_speed = maxf(_speed, 0.0)
	if absf(height) < 0.0001 and absf(_speed) < 0.002:
		height = 0.0
		_speed = 0.0
