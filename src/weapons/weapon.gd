class_name Weapon
extends RefCounted

## Firing state for one weapon: rate of fire, recoil, inaccuracy and ammo.
##
## Deliberately a plain object rather than a node, so the whole firing model
## can be driven and asserted on headless without a scene. The view model and
## effects are a separate concern and hang off the controller.
##
## Two things here are load-bearing for how CS feels:
##
## The view kick and the bullet trajectory are SEPARATE. Bullets follow the
## spray pattern exactly. The view gets a smaller, spring-damped nudge that
## only suggests the pattern, so you cannot read your own recoil off the
## screen: you learn the pattern and pull against it. Gluing the two together
## gives a view that snaps to each bullet and sags between them, which is
## neither what CS looks like nor how it plays.
##
## Spread is deterministic, seeded per shot. Same shot index, same offset,
## every time. That is what makes the first bullet reliable and the pattern
## worth learning, and it is also what lets a server and a client agree on
## where a bullet went without sending the bullet.

## The state of whoever is firing, which decides inaccuracy.
class ShooterState:
	var speed: float = 0.0
	var on_ground: bool = true
	var ducked: bool = false

	func _init(
		p_speed: float = 0.0, p_on_ground: bool = true, p_ducked: bool = false
	) -> void:
		speed = p_speed
		on_ground = p_on_ground
		ducked = p_ducked


## One bullet, with everything needed to trace it and to explain it later.
class Shot:
	var origin: Vector3
	var direction: Vector3
	var shot_index: int
	var timestamp_usec: int
	## Where in the simulation tick the trigger was actually pulled, 0 to 1.
	var tick_fraction: float
	## Degrees of cone this shot was fired into, for debugging a miss.
	var inaccuracy: float
	## The player's own aim when the trigger was pulled, before recoil. The
	## reference a recorded spray is measured against.
	var base_yaw: float
	var base_pitch: float
	## The view kick this shot applied, in degrees. Recorded for debugging;
	## it has no bearing on where this bullet went.
	var view_punch: Vector2


var data: WeaponData

var ammo: int = 0
var reserve: int = 0

## Seeds the per-shot spread. Same seed and shot index give the same offset.
var spray_seed: int = 1

## Where the recoil has pushed the VIEW, in degrees, as (right, up).
##
## The player's own look angles are never touched by recoil. The camera adds
## this on top, which is what lets letting go of the trigger return the view
## to exactly where the player was pointing rather than somewhere near it.
##
## This does NOT decide where bullets go. See fire().
var aim_punch: Vector2 = Vector2.ZERO

## The punch angle's own velocity. A shot pushes this rather than pushing the
## angle, so the view rises into a kick over a few ticks instead of teleporting
## to it, and the spring below brings it back.
var aim_punch_velocity: Vector2 = Vector2.ZERO

var _last_shot_usec: int = -1_000_000_000
var _shot_index: int = 0
var _inaccuracy: float = 0.0
var _reloading_until_usec: int = -1


func _init(p_data: WeaponData) -> void:
	data = p_data
	ammo = data.magazine_size
	reserve = data.reserve_ammo


## How far through the spray we are. Resets when you stop firing long enough
## for the recoil to recover.
func shot_index() -> int:
	return _shot_index


func is_reloading(now_usec: int) -> bool:
	return now_usec < _reloading_until_usec


func can_fire(now_usec: int) -> bool:
	if ammo <= 0 or is_reloading(now_usec):
		return false
	var elapsed := float(now_usec - _last_shot_usec) / 1_000_000.0
	return elapsed >= data.cycle_time


## Advances recoil recovery and inaccuracy decay. Call once per simulation
## tick, whether or not anything was fired.
func update(dt: float, now_usec: int) -> void:
	var since_shot := float(now_usec - _last_shot_usec) / 1_000_000.0

	_decay_punch(dt)

	# Back to the top of the pattern once the trigger has been off long enough.
	#
	# Keyed on time, not on how far the view has recovered. Every pattern's
	# first entry is (0, 0), so the punch after shot one is zero and a
	# recovery test would reset the spray before it had begun: every shot came
	# out as shot one and the gun had no pattern at all.
	if since_shot > data.recoil_reset_time:
		_shot_index = 0

	_inaccuracy = maxf(
		_inaccuracy - data.inaccuracy_recovery_rate * dt, 0.0
	)


## Source's DecayPunchAngle: the punch angle carries its own velocity, which
## is damped, and a spring pulls the angle back toward zero.
##
## Running every tick, including while firing, is deliberate. The old code
## only decayed between shots, which is what made the view snap up to each
## bullet and then sag. A spring that is always acting gives the rise and the
## settle that CS actually has.
func _decay_punch(dt: float) -> void:
	if aim_punch.length_squared() < 0.000001 \
			and aim_punch_velocity.length_squared() < 0.000001:
		aim_punch = Vector2.ZERO
		aim_punch_velocity = Vector2.ZERO
		return

	aim_punch += aim_punch_velocity * dt
	aim_punch_velocity *= maxf(1.0 - data.punch_damping * dt, 0.0)
	# Clamped because a long frame would otherwise overshoot the spring into
	# an oscillation that grows instead of settling.
	aim_punch_velocity -= aim_punch * clampf(data.punch_spring * dt, 0.0, 2.0)


## Where the weapon model should be pushed to, in degrees. Cosmetic only.
func viewmodel_punch() -> Vector2:
	return aim_punch * data.viewmodel_recoil


## The current cone half-angle in degrees, given what the shooter is doing.
##
## This is the part that makes counter-strafing matter: stopping drops you
## below the speed threshold, and the cone collapses.
func current_inaccuracy(state: ShooterState) -> float:
	var base := data.inaccuracy_standing
	if state.ducked:
		base = data.inaccuracy_crouching
	if not state.on_ground:
		base = maxf(base, data.inaccuracy_jumping)
	elif state.speed > data.inaccuracy_speed_threshold:
		# Scales with how fast you are going, so a slow walk is nearly free
		# and a full sprint is hopeless.
		var over := (state.speed - data.inaccuracy_speed_threshold) / maxf(
			data.max_player_speed - data.inaccuracy_speed_threshold, 1.0
		)
		base = maxf(base, data.inaccuracy_moving * clampf(over, 0.0, 1.0))
	return base + _inaccuracy


## Fires one round. Returns null if the weapon could not fire.
##
## yaw and pitch are the angles at the instant the trigger was pulled, which
## for a player come off the timestamped input event rather than from the tick
## boundary. That is the whole point of sub-tick shooting.
func fire(
	now_usec: int,
	tick_fraction: float,
	origin: Vector3,
	yaw_degrees: float,
	pitch_degrees: float,
	state: ShooterState
) -> Shot:
	if not can_fire(now_usec):
		return null

	var previous := Vector2.ZERO
	if _shot_index > 0:
		previous = data.recoil_offset(_shot_index - 1)
	var current := data.recoil_offset(_shot_index)

	# The bullet goes exactly to this shot's entry in the pattern, measured
	# from where the player is actually pointing. Nothing about the view is
	# involved: not the punch that has built up, not how much of it has sprung
	# back, not how large the view kick is configured to be. Turning the view
	# kick off entirely would leave every bullet hole where it is.
	#
	# This is the whole point. The pattern is the truth and it is the same
	# every spray, which is what makes it learnable. The view only suggests it.
	var spread := current_inaccuracy(state)
	var direction := _spread_direction(
		# Pattern x is degrees to the RIGHT, and yaw decreases rightward.
		yaw_degrees - current.x,
		pitch_degrees + current.y,
		spread,
		_shot_index
	)

	# The view gets kicked by this shot's step through the pattern, scaled
	# down, and as a push on the punch velocity rather than a jump in the
	# angle, so it rises into the kick over the next few ticks.
	var punch := (current - previous) * data.recoil_view_fraction

	var shot := Shot.new()
	shot.origin = origin
	shot.direction = direction
	shot.shot_index = _shot_index
	shot.timestamp_usec = now_usec
	shot.tick_fraction = tick_fraction
	shot.inaccuracy = spread
	shot.view_punch = punch
	shot.base_yaw = yaw_degrees
	shot.base_pitch = pitch_degrees

	aim_punch_velocity += punch * data.punch_impulse_scale
	_inaccuracy += data.inaccuracy_per_shot
	_shot_index += 1
	_last_shot_usec = now_usec
	ammo -= 1

	return shot


func start_reload(now_usec: int) -> bool:
	if reserve <= 0 or ammo >= data.magazine_size or is_reloading(now_usec):
		return false
	_reloading_until_usec = now_usec + int(data.reload_time * 1_000_000.0)
	return true


## Completes a reload whose time has elapsed. Returns true if it did anything.
func finish_reload_if_due(now_usec: int) -> bool:
	if _reloading_until_usec < 0 or now_usec < _reloading_until_usec:
		return false
	var wanted: int = data.magazine_size - ammo
	var taken: int = mini(wanted, reserve)
	ammo += taken
	reserve -= taken
	_reloading_until_usec = -1
	return true


## Applies the spread cone to an aim direction. Uniform over the disc rather
## than over the radius, so shots are not bunched toward the centre.
func _spread_direction(
	yaw_degrees: float, pitch_degrees: float, spread_degrees: float, shot: int
) -> Vector3:
	var direction := PlayerInput.aim_direction(yaw_degrees, pitch_degrees)
	if spread_degrees <= 0.0:
		return direction

	var rng := RandomNumberGenerator.new()
	rng.seed = _shot_seed(shot)

	var angle := rng.randf() * TAU
	var radius := sqrt(rng.randf()) * spread_degrees

	var right := direction.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		# Looking straight up or down; any perpendicular will do.
		right = direction.cross(Vector3.RIGHT)
	right = right.normalized()
	var up := right.cross(direction).normalized()

	var offset := (right * cos(angle) + up * sin(angle)) * tan(deg_to_rad(radius))
	return (direction + offset).normalized()


func _shot_seed(shot: int) -> int:
	# Mixed rather than concatenated so nearby shot indices do not produce
	# visibly related offsets.
	return hash(Vector2i(spray_seed, shot))
