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

## Over native collision StayOnGround sweeps down from this far over where
## the move ended, without sweeping up to it. A walking move is level, and
## Box3D's sweep only looks at a triangle the swept hull reaches the plane
## of, so a level floor a fraction higher than the last is not met by the
## move: the hull ends a hair over it, or a hair in it, and a sweep down
## from there would start in overlap. A unit covers floors three quarters
## of a unit higher; a riser higher than that has a face the move meets.
const STAY_ON_GROUND_LIFT := 1.0

## The quadrant ground traces are inset this far from the hull corners, so they
## sample the floor under the corner rather than the wall beside it.
const QUADRANT_INSET := 1.0

## air_action's values, CS2's own (reference/animgraph/parameters.md).
const NO_AIR_ACTION := &""
const AIR_JUMP := &"air_action_jump"
const AIR_START_FALL := &"air_action_start_fall"
const AIR_LAND := &"air_action_land"
## How far below the feet an airborne body looks for the ground. CS2's
## graph stops caring beyond 50 units (the landing curve is flat from
## there), so a little more is enough.
const AIR_HEIGHT_REACH := 64.0

## Native casts stop 0.005 m (0.197 inches) short of a surface, but treat
## starts within about 0.246 inches as overlap, with no collision normal.
## This extra clearance keeps the next tangential/upward sweep usable.
## The half-inch recovery is only for those initial overlaps (for example,
## spawning exactly on the floor), never part of acceleration or sliding.
const NATIVE_QUERY_MARGIN := 0.06
const NATIVE_RECOVERY_REACH := 0.5
const NATIVE_RECOVERY_PADDING := 0.01
## The first correction tried along a direction that clears: the band's
## depth (0.246 less 0.197) and the query margin, with a little over.
const NATIVE_RECOVERY_STEP := 0.125

## The movement solver only needs how far a trace went and the plane it
## met. Keep that interface independent of the engine's collision object.
class TraceResult:
	var travel: Vector3
	var normal: Vector3
	## Positional depenetration belongs in travel, but consumes no move time.
	var recovery: Vector3

	func _init(p_travel: Vector3, p_normal: Vector3, p_recovery: Vector3 = Vector3.ZERO) -> void:
		travel = p_travel
		normal = p_normal
		recovery = p_recovery

	func get_travel() -> Vector3:
		return travel

	func get_normal() -> Vector3:
		return normal


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
## ticks instead of stuttering at the 64 Hz tick boundary.
var previous_position: Vector3 = Vector3.ZERO

## How many times the hull has been traced: most of what a tick costs, at
## tens of microseconds a trace on dust2, counted so the checks can hold the
## movement to so many a tick.
var traces: int = 0
## How many rays have looked for the ground under an airborne body
## (height_above_ground): one an airborne tick, none on the ground.
var ground_rays: int = 0

## The last thing the body did between the ground and the air, as CS2's
## air_action names it for the animation graph: AIR_JUMP when a jump left
## the ground, AIR_START_FALL when it left without one (off a ledge, down
## a drop), AIR_LAND when it came back down; NO_AIR_ACTION before any.
## Server state, like the rest of the body, so anyone drawing the player
## sees the take-off they did.
var air_action: StringName = NO_AIR_ACTION
## The simulation time it happened at (SimClock), the tick's end.
var air_action_usec: int = 0
## In the air, how far the ground is below the feet, up to
## AIR_HEIGHT_REACH, INF beyond it; 0 on the ground. CS2's
## air_height_above_ground, which poses the legs for the landing.
var height_above_ground: float = 0.0

var _collision_shape: CollisionShape3D
var _jump_held_last_tick: bool = false
## Whether a jump left the ground this tick (_update_air).
var _jumped := false
## Where the last ground check that looked left the body, and the height of
## the hull it looked with (_ground_known).
var _looked_from := Vector3.INF
var _looked_with := 0.0
var _hull_height := 0.0
var _motion_query := PhysicsShapeQueryParameters3D.new()
var _native_recovery_direction := Vector3.UP
var _last_native_trace_recovery := Vector3.ZERO
## The native physics while this body's tick runs (simulate), looked up
## once for its traces rather than by each; null between ticks.
var _adapter: Box3DDrops
## The native physics this body was last found in (_native_physics).
var _native: Box3DDrops
## The floor a walking move was put on, by its step's sweep down or by
## staying on the ground: where the body stood on it, with what hull, and
## the floor's normal. The ground check at the move's end takes it rather
## than sweeping for the same floor again, and forgets it.
var _floor_at := Vector3.INF
var _floor_with := 0.0
var _floor_normal := Vector3.UP


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
	# This is only a hint between sweeps of one tick, not replay state.
	_native_recovery_direction = Vector3.UP

	if noclip:
		velocity = wish_dir * config.noclip_speed
		global_position += velocity * dt
		on_ground = false
		jump_fraction = -1.0
		height_above_ground = INF
		if _native_physics() != null:
			_native.queries.sync_object(self, false)
		return

	var was_on_ground := on_ground
	_jumped = false
	# Nothing but this body moves until its tick is done, and every query it
	# makes excludes it, so the bridge synchronizes the others once for it.
	_adapter = _native_physics()
	if _adapter != null:
		_adapter.queries.begin_scope(get_rid())
		if _collision_shape != null and _collision_shape.shape != null:
			# What every sweep of the tick shares is set once, and the others
			# synchronized once, here rather than by each trace.
			_prepare_motion_query()
			_adapter.queries.sync_dynamic(_motion_query.collision_mask, _motion_query.exclude)

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
	_update_air(was_on_ground)
	if _adapter != null:
		_adapter.queries.end_scope()
		# Later players and shots in this same tick see the completed movement.
		_adapter.queries.sync_object(self, false)
	_adapter = null


## The native physics this body is in, found once and kept while both
## stand: the way to it is through the viewport and its world, which was
## three calls a trace and then two lookups a tick. Null on Godot's own
## physics, and then looked for again the next time: a match's physics is
## made after its players are.
func _native_physics() -> Box3DDrops:
	if is_instance_valid(_native) and _native.initialized and _native.is_inside_tree():
		return _native
	_native = PhysicsQueries.adapter_for_node(self)
	return _native


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		# Wherever it goes next may be another world.
		_native = null


## Records what the tick did between the ground and the air (air_action),
## and, in the air, the height above the ground: one ray a tick, and only
## in the air.
func _update_air(was_on_ground: bool) -> void:
	var action := NO_AIR_ACTION
	if _jumped:
		action = AIR_JUMP
	elif was_on_ground and not on_ground:
		action = AIR_START_FALL
	elif not was_on_ground and on_ground:
		action = AIR_LAND
	if action != NO_AIR_ACTION:
		air_action = action
		air_action_usec = SimClock.now_usec()
	if on_ground:
		height_above_ground = 0.0
		return
	ground_rays += 1
	height_above_ground = GroundProbe.height_below(
		get_world_3d().direct_space_state if is_inside_tree() else null,
		global_position, AIR_HEIGHT_REACH, [get_rid()]
	)


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
	PhysicsQueries.sync_object(self)


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
	_jumped = true
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
	if _adapter != null:
		_stay_on_native_ground()
		return

	var start := global_position

	_trace(Vector3.UP * STAY_ON_GROUND_UP)
	var raised := global_position
	# Keep separation from a starting floor/wall/player overlap, including a
	# vertical correction below the ordinary snap threshold. Only the probe's
	# intentional upward travel is discarded; losing the clearance repeats
	# the recovery during categorization and every later tangential sweep.
	start += _last_native_trace_recovery

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
		global_position.x += _last_native_trace_recovery.x
		global_position.z += _last_native_trace_recovery.z
		return
	global_position = landing


## Staying on the ground over native collision: one sweep down to a step's
## height under where the move ended, and none where the step's own sweep
## down has just put the body on a floor. Source sweeps up two units and
## down from there, so that a hull sunk a little in the floor sweeps down
## from clear of it; this starts STAY_ON_GROUND_LIFT up without sweeping
## there, which is a cast fewer, and sweeps from where the hull stands,
## getting clear first (_trace), only where something is over its head.
## The body is put on the floor found whatever the distance: under Source's
## half unit it used to be left, and the ground check then closed the gap
## by its own sweep. The floor is kept for that check to take (_floor_at).
func _stay_on_native_ground() -> void:
	if _floor_at == global_position and _floor_with == _hull_height:
		return
	if _collision_shape == null or _collision_shape.shape == null:
		return
	var start := global_position
	var lift := Vector3.UP * STAY_ON_GROUND_LIFT
	var motion := Vector3.DOWN * (STAY_ON_GROUND_LIFT + config.step_height)
	var hit := _cast_from(lift, motion, _adapter.queries)
	if hit.is_empty():
		# Nothing to stand on within a step.
		return
	var normal: Vector3 = hit["normal"]
	var landing: Vector3
	if normal.is_zero_approx():
		# Something over its head where it would start: from where it
		# stands, then, clear of what it stands in first.
		var collision := _trace(Vector3.DOWN * config.step_height, true)
		if collision == null or not MovementSolver.is_walkable(collision.get_normal(), config):
			global_position = start + _last_native_trace_recovery
			return
		normal = collision.get_normal()
		landing = start + collision.get_travel()
	elif not MovementSolver.is_walkable(normal, config):
		return
	else:
		landing = start + lift + motion * float(hit["fraction"]) + (hit.get("offset", Vector3.ZERO) as Vector3)
	global_position = landing
	_floor_at = global_position
	_floor_with = _hull_height
	_floor_normal = normal


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
	var landing := _trace(Vector3.DOWN * step)

	var step_distance := _horizontal_distance(start_position, global_position)

	# Only accept the stepped move if it landed on something walkable,
	# otherwise we would happily "step" onto a surf ramp. What it landed on
	# is what the trace down met, as Source reads it (StepMove: the down
	# trace's plane normal), not a trace of its own.
	var landed_walkable := landing != null and MovementSolver.is_walkable(landing.get_normal(), config)

	if step_distance > flat_distance and landed_walkable:
		# Source takes the stepped path but keeps the FLAT move's vertical
		# velocity (gamemovement.cpp:1515). Keeping the stepped one instead
		# carries the step-down trace's Z into the next tick, which reads as a
		# small downward kick every stair.
		velocity.y = flat_velocity.y
		if _adapter != null:
			# The sweep down put it on this floor: nothing more to find.
			_floor_at = global_position
			_floor_with = _hull_height
			_floor_normal = landing.get_normal()
		return
	global_position = flat_position
	velocity = flat_velocity


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


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
		# An unresolved initial overlap has neither progress nor a plane to
		# clip against. Retrying the same motion cannot change that result:
		# nobody else moves during this player's slide. In the native path
		# each retry otherwise repeats the entire local recovery search.
		# Keep any velocity from earlier progress, as the loop did before;
		# all_fraction below still stops a move that made no progress at all.
		if collision.get_travel() == Vector3.ZERO and collision.get_normal() == Vector3.ZERO:
			break

		var motion_length := motion.length()
		var fraction := 0.0
		if motion_length > 0.0:
			# Native overlap recovery can be longer than a low-speed move.
			# Only commanded motion consumes the time left for sliding.
			fraction = clampf((collision.get_travel() - collision.recovery).length() / motion_length, 0.0, 1.0)
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
		_floor_at = Vector3.INF
		return
	if _floor_at == global_position and _floor_with == _hull_height:
		# The walking move has just been put on this floor by a sweep of its
		# own, which is the sweep this would make.
		on_ground = true
		ground_normal = _floor_normal
		_looked_from = global_position
		_looked_with = _hull_height
		_floor_at = Vector3.INF
		return
	_floor_at = Vector3.INF

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


## A counted hull trace; both engines supply travel and a collision plane
## to the same Source movement solver. Test traces never move the player.
func _trace(motion: Vector3, test_only: bool = false) -> TraceResult:
	_last_native_trace_recovery = Vector3.ZERO
	# Inside the body's own tick the bridge is known, the others are
	# synchronized and its own hull is out of the world (simulate).
	var in_scope := _adapter != null
	var adapter := _adapter if in_scope else PhysicsQueries.adapter_for_node(self)
	if adapter == null:
		traces += 1
		var collision := move_and_collide(motion, test_only)
		return TraceResult.new(collision.get_travel(), collision.get_normal()) if collision != null else null
	if _collision_shape == null or _collision_shape.shape == null:
		if not test_only:
			global_position += motion
		return null
	if not in_scope:
		_prepare_motion_query()
	_motion_query.transform = _collision_shape.global_transform
	_motion_query.motion = motion
	# These casts only move the query's starting transform. No game object
	# moves until the group ends, so synchronize proxies and exclude our
	# own hull once for the whole synchronous recovery search.
	var queries := adapter.queries
	var excluded: Array = [] if in_scope else queries.begin_shape_cast(_motion_query)
	var hit := _cast_hull(queries)
	var recovery := Vector3.ZERO
	if not hit.is_empty() and (hit["normal"] as Vector3).is_zero_approx():
		# Player hulls are axis-aligned. Their current separation identifies
		# the nearest side to try even when this is the first sweep this tick.
		# It is only a candidate: the native sweep must verify it clears.
		var other := hit.get("collider") as CharacterBody3D
		if is_instance_valid(other):
			var away := global_position - other.global_position
			if absf(away.x) > absf(away.z):
				_native_recovery_direction = Vector3.RIGHT * signf(away.x)
			elif absf(away.z) > 0.000001:
				_native_recovery_direction = Vector3.BACK * signf(away.z)
		if not _recovery_blocked_by_player(hit):
			recovery = _recover_trace_start(queries)
		if not recovery.is_zero_approx():
			_motion_query.transform.origin += recovery
			hit = _cast_hull(queries)
	if not in_scope:
		queries.end_shape_cast(excluded)
	if not hit.is_empty() and not (hit["normal"] as Vector3).is_zero_approx():
		var normal: Vector3 = hit["normal"]
		# The ordinary floor probe between side sweeps must not erase the
		# useful wall/player plane. Fresh bodies still prefer upward recovery.
		if not MovementSolver.is_walkable(normal, config):
			_native_recovery_direction = normal
	# A grazing hit's push off its plane is kept as a recovery is: part of
	# the travel, none of the move's time.
	recovery += hit.get("offset", Vector3.ZERO) as Vector3
	_last_native_trace_recovery = recovery
	var travel := recovery + motion * float(hit.get("fraction", 1.0))
	if not test_only:
		global_position += travel
		# The next query that can hit this body refreshes its proxy. Our own
		# next sweep excludes it; simulate publishes the final pose once.
	return TraceResult.new(travel, hit["normal"], recovery) if not hit.is_empty() else null


## What every sweep of the hull asks alike: its shape, its margin, what it
## meets and that it leaves itself out.
func _prepare_motion_query() -> void:
	_motion_query.shape = _collision_shape.shape
	_motion_query.margin = maxf(safe_margin, NATIVE_QUERY_MARGIN)
	_motion_query.collision_mask = collision_mask
	_motion_query.exclude = [get_rid()]


## One sweep of the hull from where it stands moved by from, as the bridge
## answers it: nothing, a hit, or a start in overlap (a hit with no
## normal), with no getting clear of that. Inside the body's own tick.
func _cast_from(from: Vector3, motion: Vector3, queries: Box3DQueries) -> Dictionary:
	_motion_query.transform = _collision_shape.global_transform.translated(from)
	_motion_query.motion = motion
	return _cast_hull(queries)


func _cast_hull(queries: Box3DQueries) -> Dictionary:
	traces += 1
	PhysicsQueries.native_queries += 1
	return queries.shape_cast_prepared(_motion_query)


## Prove a local recovery cannot escape the actual player box just hit.
## Every search offset has at most half an inch on each axis. If even that
## leaves the two real boxes intersecting on all axes, native tolerance can
## only make the overlap larger. No candidate needs to be cast in that case.
## Restrict the proof to one enabled, axis-aligned box shape; rotated or
## compound hulls and shallow contact bands keep the ordinary native search.
func _recovery_blocked_by_player(hit: Dictionary) -> bool:
	var other := hit.get("collider") as PlayerBody
	var shape := _motion_query.shape as BoxShape3D
	var index := int(hit.get("shape", -1))
	if not is_instance_valid(other) or shape == null or index < 0:
		return false
	var owners := other.get_shape_owners()
	if owners.size() != 1:
		return false
	var shape_owner: int = owners[0]
	if other.is_shape_owner_disabled(shape_owner) or other.shape_owner_get_shape_count(shape_owner) != 1 \
		or other.shape_owner_get_shape_index(shape_owner, 0) != index:
		return false
	var other_shape := other.shape_owner_get_shape(shape_owner, 0) as BoxShape3D
	if other_shape == null:
		return false
	var at := _motion_query.transform
	var other_at := other.global_transform * other.shape_owner_get_transform(shape_owner)
	var own_scale := at.basis.get_scale()
	var other_scale := other_at.basis.get_scale()
	# Exact diagonal bases rule out rotation and shear. Positive scale is
	# enough for the player hulls; uncommon transforms take the native path.
	if at.basis != Basis.from_scale(own_scale) or other_at.basis != Basis.from_scale(other_scale) \
		or minf(own_scale.x, minf(own_scale.y, own_scale.z)) <= 0.0 \
		or minf(other_scale.x, minf(other_scale.y, other_scale.z)) <= 0.0:
		return false
	var half_extents := (shape.size * own_scale + other_shape.size * other_scale) * 0.5
	var overlap := half_extents - (at.origin - other_at.origin).abs()
	# The measured direction is normally a unit normal. Include its actual
	# component reach and the existing padding as a conservative float guard.
	var reach := _native_recovery_direction.abs().max(Vector3.ONE) * NATIVE_RECOVERY_REACH \
		+ Vector3.ONE * NATIVE_RECOVERY_PADDING
	return overlap.x > reach.x and overlap.y > reach.y and overlap.z > reach.z


## Search only the native tolerance around the starting hull. A candidate
## must give a usable sweep; a zero normal remains blocked, never invented
## as a plane. A recent side plane, then up, precedes wall/corner escapes.
## A hull is nearly always just inside the contact band (a twentieth of an
## inch, and the clearance on top), so once a direction is known to clear
## at the full reach, NATIVE_RECOVERY_STEP is tried before the binary
## search that keeps a deeper correction close to the minimum: two casts
## for the usual recovery, where eight were.
func _recover_trace_start(queries: Box3DQueries) -> Vector3:
	var original := _motion_query.transform
	var directions := [Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, Vector3.DOWN]
	# Sliding usually re-enters the tolerance of the plane just encountered.
	# Try its measured normal first, then the general spawn/corner search.
	directions.erase(_native_recovery_direction)
	directions.push_front(_native_recovery_direction)
	for horizontal in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK,
		Vector3(-1.0, 0.0, -1.0), Vector3(-1.0, 0.0, 1.0),
		Vector3(1.0, 0.0, -1.0), Vector3(1.0, 0.0, 1.0)]:
		directions.append(Vector3.UP + horizontal)
	for direction: Vector3 in directions:
		var offset := direction * NATIVE_RECOVERY_REACH
		_motion_query.transform = original.translated(offset)
		var hit := _cast_hull(queries)
		if not hit.is_empty() and (hit["normal"] as Vector3).is_zero_approx():
			continue
		var low := 0.0
		var high := 1.0
		var step := NATIVE_RECOVERY_STEP / NATIVE_RECOVERY_REACH
		_motion_query.transform = original.translated(offset * step)
		hit = _cast_hull(queries)
		if hit.is_empty() or not (hit["normal"] as Vector3).is_zero_approx():
			high = step
		else:
			low = step
			for i in 5:
				var middle := (low + high) * 0.5
				_motion_query.transform = original.translated(offset * middle)
				hit = _cast_hull(queries)
				if hit.is_empty() or not (hit["normal"] as Vector3).is_zero_approx():
					high = middle
				else:
					low = middle
		_motion_query.transform = original
		return offset * high + direction.normalized() * NATIVE_RECOVERY_PADDING
	_motion_query.transform = original
	return Vector3.ZERO


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
		var hit := PhysicsQueries.intersect_ray(space, query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		if MovementSolver.is_walkable(normal, config):
			return normal
	return Vector3.ZERO
