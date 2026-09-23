class_name PlayerBody
extends CharacterBody3D

## Source-style collide-and-slide, step handling and ground detection.
##
## This deliberately does NOT use move_and_slide(). Godot's slide response is
## close to Source's but not the same, and the difference shows up exactly
## where it matters most: ramps, creases and surf. The port below is Source's
## TryPlayerMove and StepMove, which is what makes a surf ramp behave like a
## surf ramp rather than like a wall you skid down.
##
## Velocity is in Source units per second. See project.godot on scale.

const MAX_BUMPS := 4
const MAX_CLIP_PLANES := 5

## How far below the feet we look for ground each tick.
const GROUND_TRACE_DISTANCE := 2.0

## Source's StayOnGround traces up this far before looking down, so the
## downward trace starts from somewhere that is definitely not already inside
## the floor. gamemovement.cpp:1857.
const STAY_ON_GROUND_UP := 2.0

## StayOnGround ignores a correction smaller than this, the way Source ignores
## one below half a coordinate unit. Without it the body jitters by a fraction
## every tick on a perfectly flat floor.
const STAY_ON_GROUND_MIN_DELTA := 0.03

## The quadrant ground traces are inset this far from the hull corners, so they
## sample the floor under the corner rather than the wall beside it.
const QUADRANT_INSET := 1.0

@export var config: MovementConfig

var on_ground: bool = false
var ground_normal: Vector3 = Vector3.UP

## True once the hull has actually shrunk, which is not the same as holding the
## duck key: on the ground the hull only changes after duck_time has elapsed.
var is_ducked: bool = false

## 0 standing, 1 fully ducked. Drives the eye height. On the ground this eases
## over duck_time; in the air it snaps, because the hull snaps.
var duck_progress: float = 0.0

## Fly through geometry instead of colliding with it. A movement mode, as it
## is in Source, rather than a flag bolted onto the controller.
var noclip: bool = false

## Set by whatever drives this body (the player controller, or a bot). Normally
## horizontal; with noclip on it carries the full 3D fly direction.
var wish_dir: Vector3 = Vector3.ZERO
var wish_speed: float = 0.0
var wants_jump: bool = false
var wants_duck: bool = false

## Where inside this tick the jump key was actually pressed, 0..1, or -1 when
## there was no fresh press. CS2 sends this per button transition; see
## MovementConfig.subtick_jump.
var jump_fraction: float = -1.0

## Previous tick's position, so the camera can interpolate between physics
## ticks instead of stuttering at the 128 Hz tick boundary.
var previous_position: Vector3 = Vector3.ZERO

## How many times the hull has been traced: most of what a tick costs, at
## tens of microseconds a trace on dust2, counted so the checks can hold the
## movement to so many a tick.
var traces: int = 0

var _collision_shape: CollisionShape3D
var _jump_held_last_tick: bool = false
## Where the last ground check that looked left the body, and the height of
## the hull it looked with (_ground_known).
var _looked_from := Vector3.INF
var _looked_with := 0.0
var _hull_height := 0.0


func _ready() -> void:
	if config == null:
		config = MovementConfig.new()
	_collision_shape = _find_collision_shape()
	if _collision_shape != null and _collision_shape.shape != null:
		# Sub-resources are shared between instances of the same scene, so
		# resizing the hull would resize every player's. Take our own copy.
		_collision_shape.shape = _collision_shape.shape.duplicate()
	_set_hull(config.stand_height)
	previous_position = global_position
	# We run our own gravity in Source units, and our own collide-and-slide.
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	# Player clips stop bodies, not rounds: they are on a layer of their own.
	collision_mask |= MapImporter.PLAYER_CLIP_LAYER


func _find_collision_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null


## Advances one simulation tick.
##
## The order below is Source's FullWalkMove, and the order matters:
##
##   1. half gravity      (StartGravity)
##   2. jump check        (CheckJumpButton)
##   3. zero vertical speed and apply friction, if still on the ground
##   4. walk move or air move
##   5. re-categorise ground
##   6. half gravity      (FinishGravity)
##
## Splitting gravity into two halves around the move is velocity Verlet, and
## it is the reason a jump peaks at the same height no matter what the tick
## rate is. Applying it all at once would make jump height drift with tick
## rate, which would quietly change how every ledge in the game plays.
##
## A jump pressed part-way through the tick splits the tick in two and runs
## both halves, so the impulse lands at the instant it was pressed. CS2 does
## the same thing with CSubtickMoveStep, and it is what makes chained hops land
## when you pressed them rather than up to a tick later.
func simulate(dt: float) -> void:
	previous_position = global_position

	if noclip:
		velocity = wish_dir * config.noclip_speed
		global_position += velocity * dt
		on_ground = false
		jump_fraction = -1.0
		return

	if (
		config.subtick_jump
		and wants_jump
		and jump_fraction > 0.0
		and jump_fraction < 1.0
	):
		# Run up to the press with the key still up, then the rest with it
		# down, so the impulse happens at the fraction it was pressed at.
		var pressed := wants_jump
		wants_jump = false
		_simulate_step(dt * jump_fraction)
		wants_jump = pressed
		_simulate_step(dt * (1.0 - jump_fraction))
	else:
		_simulate_step(dt)

	_jump_held_last_tick = wants_jump
	jump_fraction = -1.0


## One (possibly partial) simulation step. This is Source's FullWalkMove.
func _simulate_step(dt: float) -> void:
	if not _ground_known():
		_categorize_position()
	_update_duck(dt)

	var surface_friction := MovementSolver.surface_friction_for(
		velocity.y, on_ground, config
	)

	velocity = MovementSolver.check_velocity(velocity, config)

	# StartGravity.
	velocity.y -= config.gravity * 0.5 * dt

	_try_jump(dt)

	if on_ground:
		velocity.y = 0.0
		velocity = MovementSolver.apply_friction(
			velocity, true, surface_friction, config, dt
		)

	if on_ground:
		_walk_move(surface_friction, dt)
	else:
		_air_move(surface_friction, dt)

	_categorize_position()

	# FinishGravity.
	velocity.y -= config.gravity * 0.5 * dt
	if on_ground:
		velocity.y = 0.0

	velocity = MovementSolver.check_velocity(velocity, config)


## Whether the ground the last move found is still what is under the body,
## so the check at the start of this one can be left out, as Source leaves it
## out (PlayerMove, with sv_optimizedmovement on, its default): nothing has
## moved the body since that check looked, nor changed its hull, and it is
## not rising too fast to stand on anything. The world does not move; only a
## player walking out from under it is noticed a move later, as in Source.
## Every tick's move still ends with a check, so this is one trace a tick.
func _ground_known() -> bool:
	return (
		global_position == _looked_from
		and _hull_height == _looked_with
		and velocity.y <= config.non_jump_velocity
	)


## Ducking, as Source does it.
##
## On the ground the hull shrinks from the top after duck_time, so your feet
## stay put and your head comes down. In the air it happens instantly and the
## other way round: the hull shrinks and the whole body moves UP by the
## difference, so your head stays put and your feet come up. That second case
## is the crouch jump, and it is the only way to reach a ledge higher than a
## standing jump clears.
func _update_duck(dt: float) -> void:
	var rate := 1.0 / maxf(config.duck_time, 0.0001)

	if wants_duck:
		duck_progress = minf(duck_progress + rate * dt, 1.0)
		if not is_ducked and (not on_ground or duck_progress >= 1.0):
			_finish_duck()
		return

	if is_ducked:
		if not _can_unduck():
			# Still under something. Stay ducked rather than clipping into it.
			duck_progress = 1.0
			return
		_finish_unduck()

	duck_progress = maxf(duck_progress - rate * dt, 0.0)


func _duck_height_delta() -> float:
	return config.stand_height - config.duck_height


func _finish_duck() -> void:
	var delta := _duck_height_delta()
	var airborne := not on_ground

	# Shrink first. A smaller hull can never collide with something the larger
	# one did not, so this is always safe, and it gives the move below the
	# headroom it needs.
	_set_hull(config.duck_height)

	if airborne:
		_trace(Vector3.UP * delta)
		# Head stays where it was and the eye offset drops by the same amount,
		# so the view does not jump. That only holds if the view snaps too.
		duck_progress = 1.0

	is_ducked = true


func _finish_unduck() -> void:
	var delta := _duck_height_delta()
	if not on_ground:
		_trace(Vector3.DOWN * delta)
		duck_progress = 0.0
	_set_hull(config.stand_height)
	is_ducked = false


## Is there room to stand up? Sweeping the ducked hull through the distance the
## body is about to grow covers exactly the volume the standing hull will
## occupy, so a clear sweep means it fits.
func _can_unduck() -> bool:
	var delta := _duck_height_delta()
	var direction := Vector3.UP if on_ground else Vector3.DOWN
	return _trace(direction * delta, true) == null


func _set_hull(height: float) -> void:
	if _collision_shape == null:
		return
	var shape := _collision_shape.shape as BoxShape3D
	if shape == null:
		return
	shape.size = Vector3(config.hull_width, height, config.hull_width)
	_collision_shape.position.y = height * 0.5
	_hull_height = height


## The eye offset above the feet for the current duck state.
##
## Splined rather than linear, because Source runs duck_progress through
## SimpleSpline before SetDuckedEyeOffset (gamemovement.cpp:4421). Ducking is
## constant in CS, so an ease is a visible difference from a slide.
func eye_height() -> float:
	return lerpf(
		config.stand_eye_height,
		config.duck_eye_height,
		MovementSolver.simple_spline(duck_progress)
	)


## Jumping requires a fresh press unless auto bunnyhop is on, which is the CS2
## default and the reason chaining hops is a timing skill rather than a held
## key. Source tracks this with m_nOldButtons; this is the same thing.
func _try_jump(dt: float) -> void:
	if not wants_jump or not on_ground:
		return
	if not config.auto_bunnyhop and _jump_held_last_tick:
		return
	velocity = MovementSolver.clamp_bunnyhop(velocity, config)
	velocity.y = config.jump_impulse
	if config.tick_rate_independent_jump:
		# Put back the leading half-step of gravity that the impulse just
		# overwrote. See MovementConfig.tick_rate_independent_jump.
		velocity.y -= config.gravity * 0.5 * dt
	on_ground = false


func _walk_move(surface_friction: float, dt: float) -> void:
	# Source keeps the move direction flat and never consults the ground
	# normal. Projecting onto the slope bleeds less speed uphill, which is
	# nicer and is a divergence, so it is a flag.
	var dir := wish_dir
	if config.project_wish_dir_on_ground and ground_normal != Vector3.UP:
		dir = MovementSolver.clip_velocity(dir, ground_normal)
		if dir.length_squared() > 0.0:
			dir = dir.normalized()

	velocity = MovementSolver.accelerate(
		velocity, dir, wish_speed, config.accelerate, surface_friction, dt
	)
	velocity.y = 0.0
	# Source's WalkMove stops anyone slower than a unit a second dead where
	# they stand (gamemovement.cpp, WalkMove: spd < 1.0f), and traces nothing
	# for them: a player standing still costs no trace here.
	if velocity.length() < 1.0:
		velocity = Vector3.ZERO
		return
	_step_move(dt)
	_stay_on_ground()


## Source's StayOnGround (gamemovement.cpp:1857), run at the end of every walk
## move. Trace up 2, then down a full step height, and glue the body to
## whatever walkable surface that finds.
##
## Without it, running down stairs or off any shallow decline goes airborne for
## a few ticks, which drops ground friction and ground acceleration and makes
## the descent feel floaty and fast. Snapping only GROUND_TRACE_DISTANCE, which
## is what _categorize_position does, is nine times too short to catch a step.
func _stay_on_ground() -> void:
	if not config.stay_on_ground:
		return

	var start := global_position

	_trace(Vector3.UP * STAY_ON_GROUND_UP)
	var raised := global_position

	# Down to a full step height below where the move ended, from wherever the
	# upward trace actually got to.
	var distance := raised.y - (start.y - config.step_height)
	var collision := _trace(Vector3.DOWN * distance, true)

	global_position = start

	if collision == null:
		return
	# Travelling nowhere means we started inside something. Source bails on
	# that case too rather than teleporting up to the raised position.
	if collision.get_travel().length_squared() == 0.0:
		return
	if not MovementSolver.is_walkable(collision.get_normal(), config):
		return

	var landing := raised + collision.get_travel()
	if absf(landing.y - start.y) < STAY_ON_GROUND_MIN_DELTA:
		return
	global_position = landing


func _air_move(surface_friction: float, dt: float) -> void:
	velocity = MovementSolver.air_accelerate(
		velocity, wish_dir, wish_speed, config.air_accelerate,
		surface_friction, config, dt
	)
	_try_player_move(dt)


## Source's StepMove. Run the move flat, then run it again stepping up and back
## down, and keep whichever covered more ground horizontally. This is what
## walks you up stairs without a ramp under them, and it is why the result is
## compared rather than the step always being preferred.
func _step_move(dt: float) -> void:
	var start_position := global_position
	var start_velocity := velocity

	# A flat move that met nothing is taken as it is, as Source's WalkMove
	# takes it before ever trying the step: the stepped one could go no
	# further, so it is only tried against something in the way.
	if not _try_player_move(dt):
		return
	var flat_position := global_position
	var flat_velocity := velocity

	var flat_distance := _horizontal_distance(start_position, flat_position)

	# Reset and try again with a step up first. Source steps by
	# stepsize + DIST_EPSILON so the down trace lands on the step rather than
	# stopping a hair above its lip.
	global_position = start_position
	velocity = start_velocity

	var step := config.step_height + STAY_ON_GROUND_MIN_DELTA
	_trace_move(Vector3.UP * step)
	_try_player_move(dt)
	_trace_move(Vector3.DOWN * step)

	var step_distance := _horizontal_distance(start_position, global_position)

	# Only accept the stepped move if it landed on something walkable,
	# otherwise we would happily "step" onto a surf ramp.
	var landed_walkable := _ground_below_is_walkable()

	if step_distance > flat_distance and landed_walkable:
		# Source takes the stepped path but keeps the FLAT move's vertical
		# velocity (gamemovement.cpp:1515). Keeping the stepped one instead
		# carries the step-down trace's Z into the next tick, which reads as a
		# small downward kick every stair.
		velocity.y = flat_velocity.y
		return
	global_position = flat_position
	velocity = flat_velocity


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


func _ground_below_is_walkable() -> bool:
	var collision := _trace(
		Vector3.DOWN * GROUND_TRACE_DISTANCE, true
	)
	if collision == null:
		return false
	return MovementSolver.is_walkable(collision.get_normal(), config)


## Moves without any slide response, stopping at the first obstruction.
func _trace_move(motion: Vector3) -> void:
	_trace(motion)


## Source's TryPlayerMove: up to four collide-and-slide iterations, clipping
## velocity against every plane accumulated so far, and sliding along the
## crease when two planes both block. Returns whether anything was in the way.
func _try_player_move(dt: float) -> bool:
	var primal_velocity := velocity
	var original_velocity := velocity
	var planes: Array[Vector3] = []
	var time_left := dt
	var all_fraction := 0.0
	var met_something := false

	for bump in MAX_BUMPS:
		if velocity.length_squared() == 0.0:
			break

		var motion := velocity * time_left
		var collision := _trace(motion)

		if collision == null:
			all_fraction += 1.0
			break
		met_something = true

		var motion_length := motion.length()
		var fraction := 0.0
		if motion_length > 0.0:
			fraction = collision.get_travel().length() / motion_length
		all_fraction += fraction

		if fraction > 0.0:
			original_velocity = velocity
			planes.clear()

		time_left -= time_left * fraction

		if planes.size() >= MAX_CLIP_PLANES:
			velocity = Vector3.ZERO
			break

		var normal := collision.get_normal()
		planes.append(normal)
		# Source adds no position here, and neither do we by default: Godot's
		# safe_margin already stops the trace short of the geometry. See
		# MovementConfig.trace_epsilon.
		if config.trace_epsilon != 0.0:
			global_position += normal * config.trace_epsilon

		if planes.size() == 1 and not on_ground:
			# Airborne against a single plane. Walkable surfaces slide you
			# along them; steep ones (ramps) clip without preserving the
			# downward component, which is what makes surfing work.
			velocity = MovementSolver.clip_velocity(original_velocity, planes[0])
			original_velocity = velocity
		else:
			var resolved := false
			for i in planes.size():
				var candidate := MovementSolver.clip_velocity(
					original_velocity, planes[i]
				)
				var blocked := false
				for j in planes.size():
					if j == i:
						continue
					if candidate.dot(planes[j]) < 0.0:
						blocked = true
						break
				if not blocked:
					velocity = candidate
					resolved = true
					break

			if not resolved:
				if planes.size() != 2:
					velocity = Vector3.ZERO
					break
				# Two planes forming a crease: slide along their intersection.
				var crease := planes[0].cross(planes[1])
				if crease.length_squared() == 0.0:
					velocity = Vector3.ZERO
					break
				crease = crease.normalized()
				velocity = crease * crease.dot(velocity)

			# If clipping reversed us relative to where we wanted to go, stop
			# rather than getting shot backwards out of a corner.
			if velocity.dot(primal_velocity) <= 0.0:
				velocity = Vector3.ZERO
				break

	if all_fraction == 0.0:
		velocity = Vector3.ZERO
	return met_something


## Determines whether we are standing on something, and on what.
func _categorize_position() -> void:
	# Moving up faster than NON_JUMP_VELOCITY means we definitively left the
	# ground, so Source skips the trace entirely for the tick. That is also
	# what bounds the dead-strafe friction zone.
	if velocity.y > config.non_jump_velocity:
		on_ground = false
		ground_normal = Vector3.UP
		_looked_from = Vector3.INF
		return

	var collision := _trace(
		Vector3.DOWN * GROUND_TRACE_DISTANCE, true
	)
	var normal := Vector3.ZERO
	# Where the trace stopped, which is where moving down would stop.
	var travel := Vector3.ZERO
	if collision != null:
		normal = collision.get_normal()
		travel = collision.get_travel()

	if normal == Vector3.ZERO or not MovementSolver.is_walkable(normal, config):
		# The centre of the hull found nothing walkable. Source retries with
		# four sub-boxes of the hull before giving up, so that standing with
		# most of yourself off a crate edge keeps you on the crate.
		normal = _ground_normal_in_quadrants()
		if normal == Vector3.ZERO:
			on_ground = false
			ground_normal = Vector3.UP
			_looked_from = global_position
			_looked_with = _hull_height
			return

	on_ground = true
	ground_normal = normal
	# Snap down onto the surface so we do not hover a fraction above it: by
	# the trace's own travel when the centre met something, rather than
	# tracing the same move again; moved when only a corner found the ground.
	if collision != null:
		global_position += travel
	else:
		_trace(Vector3.DOWN * GROUND_TRACE_DISTANCE)
	_looked_from = global_position
	_looked_with = _hull_height


## A trace of the hull along motion, as move_and_collide makes it, counted
## (traces).
func _trace(motion: Vector3, test_only: bool = false) -> KinematicCollision3D:
	traces += 1
	return move_and_collide(motion, test_only)


## Source's TryTouchGroundInQuadrants (gamemovement.cpp:3731): when the centre
## trace finds nothing walkable, check the four quadrants of the hull and stay
## grounded if any of them is over something walkable.
##
## Source traces four sub-boxes; this casts a ray just inside each hull corner,
## which is the outer extent those boxes reach and is what decides whether an
## edge holds you up. Returns the normal found, or ZERO for none.
func _ground_normal_in_quadrants() -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return Vector3.ZERO

	var inset := config.hull_width * 0.5 - QUADRANT_INSET
	var corners := [
		Vector3(inset, 0.0, inset),
		Vector3(-inset, 0.0, inset),
		Vector3(inset, 0.0, -inset),
		Vector3(-inset, 0.0, -inset),
	]

	for corner in corners:
		var from: Vector3 = global_position + corner + Vector3.UP * QUADRANT_INSET
		var to: Vector3 = from + Vector3.DOWN * (GROUND_TRACE_DISTANCE + QUADRANT_INSET)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = collision_mask
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		if MovementSolver.is_walkable(normal, config):
			return normal
	return Vector3.ZERO
