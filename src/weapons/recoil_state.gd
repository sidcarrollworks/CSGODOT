class_name RecoilState
extends RefCounted

## Where the recoil has carried the BULLETS, in degrees, as (right, up), and
## how that recovers when the trigger is let go.
##
## This is CS's aim punch, in the shape CS:GO's code gives it (CS2's own
## constants are not published): each round pushes the punch's VELOCITY, and
## every moment the punch decays exponentially and by a fixed rate towards
## zero while its velocity decays more slowly. Held down, the rounds come
## faster than it can recover and it climbs; let go, it comes home within a
## few tenths of a second. A round goes wherever it is when the trigger breaks.
##
## The spray patterns are measured positions, not pushes, so the pushes are
## SOLVED from them (solve_impulses): the push each round needs so that, held
## at the weapon's own rate of fire and decaying all the while, the next round
## lands exactly on the pattern's next entry. Held down, the bullets walk the
## measured pattern. Tapped, the same pushes decay between rounds, and the
## recoil index they are chosen by decays too (Weapon), so a tap lands short
## of where the spray would have got to, and further short the longer the gap.
##
## The view kick is a separate system entirely (Weapon.aim_punch and its
## springs, tuned by eye against CS2). This decides only where rounds go.

## Exponential decay of the punch, per second (CS:GO weapon_recoil_decay2_exp).
const DECAY_EXP := 8.0
## Linear decay of the punch, degrees per second of the punch itself
## (weapon_recoil_decay2_lin). The bullets move by the punch times
## BULLET_SCALE, so in the bullets' degrees it is this times that.
const DECAY_LIN := 18.0
## Exponential decay of the punch's velocity, per second
## (weapon_recoil_vel_decay).
const VELOCITY_DECAY := 4.5
## How far the bullets move per degree of punch (weapon_recoil_scale).
const BULLET_SCALE := 2.0

## The state is stepped no coarser than this. Finer than the tick because a
## round lands part-way through a tick, and the steps must come
## out the same however the time between two rounds is cut up; at 1/512 s
## the difference is under a hundredth of a degree over a magazine.
const MAX_STEP := 1.0 / 512.0

## Past this long without a round, the punch is back at zero for good: its
## linear decay pins it there once the velocity left is below it.
const SETTLED_AFTER := 1.0

var value: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO

## The pushes solve_impulses has worked out, by [pattern, cycle time]. Handed
## out as copies: a packed array comes back from a dictionary shared, and a
## weapon changing its own would change the one kept.
static var _solved := {}


func reset() -> void:
	value = Vector2.ZERO
	velocity = Vector2.ZERO


## Runs the punch forward by seconds.
func advance(seconds: float) -> void:
	if seconds <= 0.0:
		return
	if seconds > SETTLED_AFTER:
		value = Vector2.ZERO
		velocity *= exp(-VELOCITY_DECAY * seconds)
		return
	var steps := maxi(ceili(seconds / MAX_STEP - 0.000001), 1)
	var dt := seconds / float(steps)
	for i in steps:
		_step(dt)


## One step, in CS's order: the angle decays exponentially, then linearly
## towards zero (never through it), then moves by the velocity, which decays
## halfway through.
func _step(dt: float) -> void:
	value *= exp(-DECAY_EXP * dt)
	var size := value.length()
	if size > 0.0:
		value *= maxf(size - DECAY_LIN * BULLET_SCALE * dt, 0.0) / size
	value += velocity * dt * 0.5
	velocity *= exp(-VELOCITY_DECAY * dt)
	value += velocity * dt * 0.5


## The push each round of a held spray gives the velocity, solved so the
## rounds land on pattern, fired every cycle_time apart. Entry i is the push
## round i gives, taking the bullets from pattern entry i to entry i + 1.
##
## Solved round by round, each by Newton's method on the two components; the
## decay is nearly linear in the push, so it converges in two or three
## iterations. That is some fifteen thousand steps of the punch for a
## magazine, 15 ms of script, so each pattern and rate of fire is solved
## once (_solved) and every weapon built after takes a copy: a Weapon is built
## on every equip and every respawn, and each one froze the game for a frame.
static func solve_impulses(pattern: PackedVector2Array, cycle_time: float) -> PackedVector2Array:
	var key := [pattern.duplicate(), cycle_time]
	if _solved.has(key):
		return (_solved[key] as PackedVector2Array).duplicate()
	var impulses := PackedVector2Array()
	var state := RecoilState.new()
	for i in range(pattern.size() - 1):
		var target := pattern[i + 1]
		var push := (target - state.value) / maxf(cycle_time, 0.0001)
		var landed := _landing(state, push, cycle_time)
		for iteration in 40:
			var miss := target - landed
			if miss.length() < 0.000001:
				break
			var h := 0.001
			var dx := (_landing(state, push + Vector2(h, 0.0), cycle_time) - landed) / h
			var dy := (_landing(state, push + Vector2(0.0, h), cycle_time) - landed) / h
			var det := dx.x * dy.y - dy.x * dx.y
			if absf(det) < 0.0000001:
				break
			var step := Vector2(
				(dy.y * miss.x - dy.x * miss.y) / det,
				(-dx.y * miss.x + dx.x * miss.y) / det
			)
			# A step that misses by more is halved until it does not. From
			# rest, a small push is all eaten by the linear decay, so the
			# slope there is near flat and a full step flies off: the CZ75's
			# second round, 2 degrees in one, never came back without this.
			var tried := push + step
			var tried_landed := _landing(state, tried, cycle_time)
			var better := false
			for halving in 30:
				if (target - tried_landed).length() < miss.length():
					better = true
					break
				step *= 0.5
				tried = push + step
				tried_landed = _landing(state, tried, cycle_time)
			if not better:
				# As close as single-precision angles get.
				break
			push = tried
			landed = tried_landed
		impulses.append(push)
		state.velocity += push
		state.advance(cycle_time)
	_solved[key] = impulses.duplicate()
	return impulses


static func _landing(from: RecoilState, push: Vector2, seconds: float) -> Vector2:
	var trial := RecoilState.new()
	trial.value = from.value
	trial.velocity = from.velocity + push
	trial.advance(seconds)
	return trial.value
