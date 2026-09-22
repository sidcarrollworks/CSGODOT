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


## The punch spring is integrated at no coarser than this, whatever the
## caller's frame length. 128 Hz, the simulation tick the constants suit.
const PUNCH_MAX_STEP := 1.0 / WeaponData.SIMULATION_HZ

var data: WeaponData

var ammo: int = 0
var reserve: int = 0

## Seeds the per-shot spread. Same seed and shot index give the same offset.
var spray_seed: int = 1

var _view := WeaponData.Punch.new()
var _model := WeaponData.Punch.new()

## Where the recoil has pushed the VIEW, in degrees, as (right, up).
##
## The player's own look angles are never touched by recoil. The camera adds
## this on top, which is what lets letting go of the trigger return the view
## to exactly where the player was pointing rather than somewhere near it.
##
## This does NOT decide where bullets go. See fire().
var aim_punch: Vector2:
	get: return _view.value
	set(to): _view.value = to

## The punch angle's own velocity. A round pushes this rather than pushing the
## angle, so the view rises into a kick over a few ticks instead of teleporting
## to it, and the spring brings it back.
var aim_punch_velocity: Vector2:
	get: return _view.velocity
	set(to): _view.velocity = to

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

	_decay_inaccuracy(dt)


## Runs both punch springs forward: the camera's, which settles slowly enough
## that the crosshair climbs with a spray, and the weapon model's, which
## settles in the few hundred milliseconds measured off CS2.
##
## Running them every tick, including while firing, is deliberate. The old
## code only decayed between rounds, which is what made the view snap up to
## each bullet and then sag.
func _decay_punch(dt: float) -> void:
	_view.advance(dt, data.punch_damping(), data.punch_spring(), PUNCH_MAX_STEP)
	_model.advance(
		dt, data.model_punch_damping(), data.model_punch_spring(), PUNCH_MAX_STEP
	)


## The accuracy penalty decays exponentially toward zero and snaps to it once
## it is below what the game could show you.
##
## Exponential, not linear, for two reasons: it is what the measured accuracy
## box does (the steps shrink as it recovers, which is a straight line only on
## a log scale), and it is what CS:GO's accuracy penalty did. The time
## constant comes from data.accuracy_reset_time, so one standing shot recovers
## in exactly the measured time and a spray takes proportionally longer.
func _decay_inaccuracy(dt: float) -> void:
	if _inaccuracy <= 0.0:
		return
	_inaccuracy *= exp(-dt / data.accuracy_time_constant())
	if _inaccuracy < data.accuracy_reset_threshold():
		_inaccuracy = 0.0


## Whether the weapon has finished recovering its accuracy.
##
## Worth reading next to how far the view has settled, because the two do not
## agree: on both of these weapons the gun stops moving a couple of hundred
## milliseconds before this turns true.
func is_accuracy_reset() -> bool:
	return _inaccuracy <= 0.0


## Where the recoil has pushed the WEAPON MODEL, in degrees, before
## viewmodel_recoil scales it. Its own spring, settling in the few hundred
## milliseconds measured off CS2 rather than the camera's couple of seconds.
var model_punch: Vector2:
	get: return _model.value


## Where the weapon model should be pushed to, in degrees, over and above the
## camera it already hangs from. Cosmetic only: it moves the gun in the
## player's hands and changes nothing about aim or bullets.
##
## Sideways is scaled down against the climb, so the gun sways without
## wandering off the middle of the screen.
func viewmodel_punch() -> Vector2:
	return Vector2(
		_model.value.x * data.viewmodel_recoil * data.viewmodel_sway,
		_model.value.y * data.viewmodel_recoil
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


## The view kick of one round, in degrees.
##
## The same climb every round, with a small sideways lean whose DIRECTION
## comes from the pattern and whose size does not.
##
## Reading the size off the pattern too is the obvious thing to do and it is
## wrong. A pattern's vertical steps are front-loaded and its sideways steps
## are not: the AK climbs about two degrees a round for seven rounds and then
## goes flat, while its sideways steps grow to three degrees. Scale the kick
## by those and the view punches twice and then only sways, which is not what
## a gun does and is not what CS2 does either.
func _view_kick_for(shot_index: int) -> Vector2:
	var here := data.recoil_offset(shot_index)
	var sideways := data.recoil_offset(shot_index + 1).x - here.x
	if is_zero_approx(sideways) and shot_index > 0:
		# Past the end of the pattern, lean the way the last round did.
		sideways = here.x - data.recoil_offset(shot_index - 1).x
	return Vector2(signf(sideways) * data.view_kick_side(), data.view_kick_up())


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

	# The view gets kicked by this shot's own recoil, scaled down, and as a
	# push on the punch velocity rather than a jump in the angle, so it rises
	# into the kick over the next few ticks.
	var punch := _view_kick_for(_shot_index)

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

	_view.kick(punch * data.punch_impulse_scale())
	_model.kick(punch * data.model_punch_impulse_scale())
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
