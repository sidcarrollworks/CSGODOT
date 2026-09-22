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
## The recoil pattern punches your VIEW, not just the bullets. The crosshair
## climbs and the bullets follow it, which is why a spray is learnable: you
## pull down against a motion you can see. Applying the offset only to the
## bullets would look still and feel wrong.
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
	## The view punch this shot applied, in degrees.
	var view_punch: Vector2


var data: WeaponData

var ammo: int = 0
var reserve: int = 0

## Seeds the per-shot spread. Same seed and shot index give the same offset.
var spray_seed: int = 1

## Accumulated view punch not yet recovered, in degrees, as (right, up).
##
## The player's own look angles stay untouched by recoil. The camera and the
## bullets both add this on top. Keeping them separate is what stops the punch
## being counted twice, and it means letting go of the trigger returns the view
## to exactly where the player was pointing rather than somewhere near it.
var accumulated_punch: Vector2 = Vector2.ZERO

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

	# Recoil only starts coming back once the gun is no longer cycling,
	# otherwise holding the trigger would fight its own recovery.
	if since_shot > data.cycle_time:
		var recovery := data.recoil_recovery_rate * dt
		var length := accumulated_punch.length()
		if length > 0.0:
			accumulated_punch *= maxf(length - recovery, 0.0) / length
		if accumulated_punch.length() < 0.01:
			accumulated_punch = Vector2.ZERO

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
	var punch := (current - previous) * data.recoil_view_fraction

	# The bullet goes where the crosshair will be after this shot's kick, so
	# the hole on the wall lands at the pattern's entry for this shot index.
	var total := accumulated_punch + punch
	var spread := current_inaccuracy(state)
	var direction := _spread_direction(
		# Punch x is degrees to the RIGHT, and yaw decreases rightward.
		yaw_degrees - total.x,
		pitch_degrees + total.y,
		spread,
		_shot_index
	)

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

	accumulated_punch += punch
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
