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

## Pushed a hair out of surfaces to avoid re-colliding with the plane we just
## resolved against.
const TRACE_EPSILON := 0.03

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

## Previous tick's position, so the camera can interpolate between physics
## ticks instead of stuttering at the 128 Hz tick boundary.
var previous_position: Vector3 = Vector3.ZERO

var _collision_shape: CollisionShape3D
var _jump_held_last_tick: bool = false


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
func simulate(dt: float) -> void:
	previous_position = global_position

	if noclip:
		velocity = wish_dir * config.noclip_speed
		global_position += velocity * dt
		on_ground = false
		return

	_categorize_position()
	_update_duck(dt)

	var surface_friction := MovementSolver.surface_friction_for(
		velocity.y, on_ground, config
	)

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

	_jump_held_last_tick = wants_jump


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
		move_and_collide(Vector3.UP * delta)
		# Head stays where it was and the eye offset drops by the same amount,
		# so the view does not jump. That only holds if the view snaps too.
		duck_progress = 1.0

	is_ducked = true


func _finish_unduck() -> void:
	var delta := _duck_height_delta()
	if not on_ground:
		move_and_collide(Vector3.DOWN * delta)
		duck_progress = 0.0
	_set_hull(config.stand_height)
	is_ducked = false


## Is there room to stand up? Sweeping the ducked hull through the distance the
## body is about to grow covers exactly the volume the standing hull will
## occupy, so a clear sweep means it fits.
func _can_unduck() -> bool:
	var delta := _duck_height_delta()
	var direction := Vector3.UP if on_ground else Vector3.DOWN
	return move_and_collide(direction * delta, true) == null


func _set_hull(height: float) -> void:
	if _collision_shape == null:
		return
	var shape := _collision_shape.shape as BoxShape3D
	if shape == null:
		return
	shape.size = Vector3(config.hull_width, height, config.hull_width)
	_collision_shape.position.y = height * 0.5


## The eye offset above the feet for the current duck state.
func eye_height() -> float:
	return lerpf(config.stand_eye_height, config.duck_eye_height, duck_progress)


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
	# On a slope, project the wish direction onto the slope so that walking
	# uphill does not bleed speed into the ground plane.
	var dir := wish_dir
	if ground_normal != Vector3.UP:
		dir = MovementSolver.clip_velocity(dir, ground_normal)
		if dir.length_squared() > 0.0:
			dir = dir.normalized()

	velocity = MovementSolver.accelerate(
		velocity, dir, wish_speed, config.accelerate, surface_friction, dt
	)
	velocity.y = 0.0
	_step_move(dt)


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

	_try_player_move(dt)
	var flat_position := global_position
	var flat_velocity := velocity

	var flat_distance := _horizontal_distance(start_position, flat_position)

	# Reset and try again with a step up first.
	global_position = start_position
	velocity = start_velocity

	_trace_move(Vector3.UP * config.step_height)
	_try_player_move(dt)
	_trace_move(Vector3.DOWN * config.step_height)

	var step_distance := _horizontal_distance(start_position, global_position)

	# Only accept the stepped move if it landed on something walkable,
	# otherwise we would happily "step" onto a surf ramp.
	var landed_walkable := _ground_below_is_walkable()

	if step_distance > flat_distance and landed_walkable:
		return
	global_position = flat_position
	velocity = flat_velocity


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


func _ground_below_is_walkable() -> bool:
	var collision := move_and_collide(
		Vector3.DOWN * GROUND_TRACE_DISTANCE, true
	)
	if collision == null:
		return false
	return MovementSolver.is_walkable(collision.get_normal(), config)


## Moves without any slide response, stopping at the first obstruction.
func _trace_move(motion: Vector3) -> void:
	move_and_collide(motion)


## Source's TryPlayerMove: up to four collide-and-slide iterations, clipping
## velocity against every plane accumulated so far, and sliding along the
## crease when two planes both block.
func _try_player_move(dt: float) -> void:
	var primal_velocity := velocity
	var original_velocity := velocity
	var planes: Array[Vector3] = []
	var time_left := dt
	var all_fraction := 0.0

	for bump in MAX_BUMPS:
		if velocity.length_squared() == 0.0:
			break

		var motion := velocity * time_left
		var collision := move_and_collide(motion)

		if collision == null:
			all_fraction += 1.0
			break

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
		# Nudge out of the surface so the next iteration does not immediately
		# re-collide with the plane we just resolved.
		global_position += normal * TRACE_EPSILON

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


## Determines whether we are standing on something, and on what.
func _categorize_position() -> void:
	# Moving up fast enough means we definitively left the ground, which stops
	# a jump from being cancelled on its first tick.
	if velocity.y > config.jump_impulse * 0.5:
		on_ground = false
		ground_normal = Vector3.UP
		return

	var collision := move_and_collide(
		Vector3.DOWN * GROUND_TRACE_DISTANCE, true
	)
	if collision == null:
		on_ground = false
		ground_normal = Vector3.UP
		return

	var normal := collision.get_normal()
	if not MovementSolver.is_walkable(normal, config):
		on_ground = false
		ground_normal = Vector3.UP
		return

	on_ground = true
	ground_normal = normal
	# Snap down onto the surface so we do not hover a fraction above it.
	move_and_collide(Vector3.DOWN * GROUND_TRACE_DISTANCE)
