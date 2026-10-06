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
## This extra clearance keeps the next tangential/upward sweep usable, and
## the bridge sweeps a hull an eighth of a unit smaller all round
## (Box3DQueries.CAST_INSET), so a hull is in overlap within 0.12 of what
## it is near and rests 0.257 from it.
## The half-inch recovery is only for those initial overlaps (for example,
## spawning exactly on the floor), never part of acceleration or sliding.
const NATIVE_QUERY_MARGIN := 0.06
const NATIVE_RECOVERY_REACH := 0.5
const NATIVE_RECOVERY_PADDING := 0.01
## The first correction tried along a direction that clears: as deep as a
## hull is in overlap from (0.12), a little over.
const NATIVE_RECOVERY_STEP := 0.125

## The movement solver only needs how far a trace went and the plane it
## met. Keep that interface independent of the engine's collision object.
class TraceResult:
	var travel: Vector3
	var normal: Vector3
	## Positional depenetration belongs in travel, but consumes no move time.
	var recovery: Vector3
	## The actual supporting entity, not a world-only probe beside it.
	var is_world: bool

	func _init(p_travel: Vector3, p_normal: Vector3, p_recovery: Vector3 = Vector3.ZERO, p_is_world: bool = false) -> void:
		travel = p_travel
		normal = p_normal
		recovery = p_recovery
		is_world = p_is_world

	func get_travel() -> Vector3:
		return travel

	func get_normal() -> Vector3:
		return normal


## The project setting that says what runs the movement's step, "native" or
## "script"; the command line's --movement <which> wins over it.
const MOVEMENT_SETTING := "csgodot/simulation/movement"
## The native code's class (native/src/hull_mover.cpp), there once it has
## been built (scripts/build_native.sh, .ps1).
const NATIVE_CLASS := &"HullMover"
## Where the build puts what Godot finds the library by.
const NATIVE_LISTING := "res://addons/csgodot_native/csgodot_native.gdextension"
## The scripts the native code is a copy of, which it is built again after a
## change to (native/SConstruct has the same list, in the same order).
const NATIVE_COPIES: Array[String] = [
	"src/movement/player_body.gd",
	"src/movement/movement_solver.gd",
	"src/movement/movement_config.gd",
	"src/physics/box3d_queries.gd",
]
## The functions the native step stands in for. A body whose script has its
## own of any of them (a profile's timed bot, a check's double) is stepped by
## the script, or its own would not run (native_over_own_functions).
const STEP_FUNCTIONS: Array[StringName] = [
	&"_simulate_step", &"_ground_known", &"_update_duck", &"_duck_height_delta", &"_finish_duck",
	&"_finish_unduck", &"_can_unduck", &"_try_jump", &"_walk_move", &"_stay_on_ground",
	&"_stay_on_native_ground", &"_air_move", &"_step_move", &"_horizontal_distance", &"_trace_move",
	&"_try_player_move", &"_try_step", &"_categorize_position", &"_trace", &"_cast_from", &"_cast_hull",
	&"_recovery_blocked_by_player", &"_recover_trace_start", &"_ground_normal_in_quadrants",
	&"_apply_ground_friction", &"_defer_acceleration", &"_stop_movement",
	&"_update_friction_cache",
]

## Whether the step is run in native code where it can be: the library
## built, the game's physics Box3D, the hull an upright box. The script
## below is the reference and runs wherever it cannot; the two give the
## same body to the last bit (check_steps).
static var native_steps: bool = configured_movement() == "native"
## Whether every step is run both ways from the same start and the two
## held to the same result, the native one kept. Off in the game; every
## check has it on (tests/check_suite.gd), and a check file with a fault
## has failed.
static var check_steps := false
static var steps_checked: int = 0
static var step_faults: PackedStringArray = PackedStringArray()
## Why the native code runs no step here, or nothing where it may. Found
## out as the script is loaded, since it reads the sources: never in a tick.
static var native_missing: String = _why_no_native()
## Whether a script has its own of the step's functions, by script.
static var _own_functions: Dictionary = {}

@export var config: MovementConfig

var on_ground: bool = false
var ground_normal: Vector3 = Vector3.UP
## CS2 enables topology eyes on world support, never another player or a
## moving platform. Taken from the existing grounding trace, with no probe.
var ground_is_world: bool = false

## True once the hull has actually shrunk, which is not the same as holding the
## duck key: on the ground the hull only changes after duck_time has elapsed.
var is_ducked: bool = false

## 0 standing, 1 fully ducked: CS2's duck amount. On the ground this eases
## over duck_time; in the air it snaps, because the hull snaps.
var duck_progress: float = 0.0

## CS2's duck root offset (m_flDuckRootOffset, movement services +0x418): a
## duck or unduck in the air moves the body by half the hulls' difference, 9
## units (FinishDuck 180abdbe0, FinishUnDuck 180abe2f0), and this holds the
## eyes where they were, eased back to 0 by the eye update (GroundEyes) at
## that 9 over 0.1 s.
var duck_root_offset: float = 0.0
## CS2's duck view offset (m_flDuckViewOffset, +0x41c): eased by the eye
## update toward the hulls' difference (18) times the duck amount below the
## standing eyes, less the root offset, at 18 over 0.2 s. The eyes are the
## standing view's 64 plus the root and ground adjustment plus this.
var duck_view_offset: float = 0.0
## What a jump's vertical speed is multiplied by this movement interval
## (CS2 180ab21a0): below 1 for a jump soon after a hard landing. Worked
## out before each step from the last landing (_jump_scale); the step only
## reads it.
var jump_scale: float = 1.0
## The last landing, as CS2's landing recorder (180ad3840) keeps it: how
## long ago the hull reached the ground, counted to the start of the
## movement interval under way (seconds; INF for none since a spawn), and
## how fast it was coming down (u/s, negative). CS2 keeps the landing's
## tick and its fraction, to 1/64 of a tick; the time since it is the same
## counted interval by interval, and needs no clock.
var landed_ago: float = INF
var landed_speed: float = 0.0

## Fly through geometry instead of colliding with it. A movement mode, as it
## is in Source, rather than a flag bolted onto the controller.
var noclip: bool = false

## Set by whatever drives this body (the player controller, or a bot). Normally
## horizontal; with noclip on it carries the full 3D fly direction.
var wish_dir: Vector3 = Vector3.ZERO
var wish_speed: float = 0.0
## Explicit ground acceleration scale, independent of the speed target.
## PlayerSim supplies CS2's weapon/run/walk/duck acceleration scales.
## Zero lets plain bodies accelerate from wish_speed.
var acceleration_speed: float = 0.0
## Command-selected total ground speed cap, independent of acceleration.
## Plain bodies have no command cap until their driver supplies one.
var movement_speed_limit: float = INF
## Walking tapers acceleration over the last five u/s of this goal.
## Zero disables the taper, including while crouched and in AirMove.
var walk_acceleration_limit: float = 0.0
## Per movement segment: CS2's combined acceleration (+0x108), the velocity
## restored after collision (+0x114), and friction overshoot (+0x128).
## Ordinary contact clips only velocity; a hard stop clears velocity,
## acceleration and deferred velocity (overshoot is reset next segment).
var _move_acceleration := Vector3.ZERO
var _deferred_velocity := Vector3.ZERO
var _friction_overshoot: float = 0.0
## CS2 WalkMove keeps a quantized control speed until its saved tick phase.
## SetupMove clears only the command's refresh flag; FinishMove publishes it.
var _friction_cached := false
var _friction_until := 0.0
var _friction_speed := 0.0
var _friction_refreshed := false
var _last_movement_impulse := Vector3.ZERO
var movement_impulse := Vector3.INF
var movement_boundaries := PackedFloat64Array()
var _interval_start := 0.0
var wants_jump: bool = false
var wants_duck: bool = false

## Where inside this tick the jump key was actually pressed, 0..1, or -1 when
## there was no fresh press. CS2 sends this per button transition; see
## MovementConfig.subtick_jump.
var jump_fraction: float = -1.0

## An additional movement boundary this tick, or -1. A grenade snapshot
## uses it to finish a real collision step exactly at its deadline.
var movement_fraction: float = -1.0

## Previous tick's position, so the camera can interpolate between physics
## ticks instead of stuttering at the 64 Hz tick boundary.
var previous_position: Vector3 = Vector3.ZERO

## Eye/root adjustment belongs to movement, so snapshots and every view
## read the same completed state. GroundEyes queries only during movement;
## eye_height() is a pure read, including when bots think on worker threads.
var ground_eyes := GroundEyes.new()
var previous_eye_height: float = 64.0

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
var _floor_is_world := false
## The quadrant fallback shares its helper with native movement. Its owner
## flag travels beside the normal without repeating those four rays.
var _quadrant_is_world := false
## The native code's mover, made the first time a step can be run by it.
var _mover: Object
## Has the native code step this body though its script has its own of the
## step's functions, which then do not run: for what times the step from
## outside, or checks the comparison.
var native_over_own_functions := false
## Whether this body's script has its own: -1 before anyone has looked.
var _own_step_functions: int = -1


## What runs the step: "native", or "script" where the setting or the
## command line says so. Anything else is said to be neither, and is
## "native".
static func configured_movement() -> String:
	var which := String(ProjectSettings.get_setting(MOVEMENT_SETTING, "native"))
	which = movement_named(OS.get_cmdline_user_args(), movement_named(OS.get_cmdline_args(), which))
	if which not in ["native", "script"]:
		push_warning("--movement and %s take \"native\" or \"script\", not \"%s\": the movement is native" % [MOVEMENT_SETTING, which])
		return "native"
	return which


## What --movement <which> or --movement=<which> among args names, in small
## letters, or `otherwise` where neither is there. The last said wins.
static func movement_named(args: PackedStringArray, otherwise: String) -> String:
	var which := otherwise
	for i in args.size():
		if args[i] == "--movement" and i + 1 < args.size():
			which = args[i + 1]
		elif args[i].begins_with("--movement="):
			which = args[i].trim_prefix("--movement=")
	return which.to_lower()


## Whether the native code is there to run a step, and was built from the
## sources and scripts that are here (native_missing says why not).
static func native_built() -> bool:
	return native_missing.is_empty()


## Whether the build has put a library here for Godot to load, loaded or
## not.
static func native_installed() -> bool:
	return FileAccess.file_exists(NATIVE_LISTING)


static func _why_no_native() -> String:
	if not ClassDB.class_exists(NATIVE_CLASS):
		if native_installed():
			return "it is installed and Godot did not load it (what Godot says as it starts says why): build it again"
		return "it has not been built"
	var here := native_sources()
	if here.is_empty():
		# An exported game has no sources to hold its library to.
		return ""
	var made: Object = ClassDB.instantiate(NATIVE_CLASS)
	var built_from := ""
	if made != null and made.has_method(&"get_sources"):
		built_from = String(made.call(&"get_sources"))
	if built_from != here:
		# The library is a copy of the script, and a copy of another script
		# would move a body as this game does not.
		push_warning("The native code was built from other sources than are here, and the script runs the movement until it is built again (scripts/build_native.sh, .ps1).")
		return "it was built from other sources than are here: build it again"
	return ""


## The stamp of what the native code is built from, as the build works it
## out (native/SConstruct): its own sources and the scripts they copy. Empty
## where there are no sources, as in an exported game. It reads them, so it
## is not for a tick.
static func native_sources() -> String:
	if not FileAccess.file_exists("res://native/SConstruct"):
		return ""
	var names: Array[String] = ["native/SConstruct"]
	var own := DirAccess.get_files_at("res://native/src")
	own.sort()
	for file_name in own:
		if file_name.get_extension() in ["cpp", "h"]:
			names.append("native/src/" + file_name)
	names.append_array(NATIVE_COPIES)
	var texts: Array[String] = []
	for source in names:
		texts.append(FileAccess.get_file_as_string("res://" + source))
	return stamp_of(names, texts)


## The stamp of these sources: each by its name, in order, its line endings
## left out, since a checkout on Windows may have changed them.
static func stamp_of(names: Array[String], texts: Array[String]) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	for i in names.size():
		hashing.update((names[i] + "\n" + texts[i].replace("\r", "") + "\n").to_utf8_buffer())
	return hashing.finish().hex_encode()


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
	reset_eye_state()
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
## Ordinary CS2 movement uses a shared deferred half-step:
##
##   1. jump check
##   2. ground friction/acceleration, or split air acceleration and gravity
##   3. transfer half continuous acceleration to deferred velocity
##   4. collision movement and deferred restoration
##   5. re-categorise ground and clear grounded vertical state
##
## Gravity shares the collision state, rather than applying another
## independent half afterward. A hard stop can clear its deferred half.
##
## A jump pressed part-way through the tick splits the tick in two and runs
## both halves, so the impulse lands at the instant it was pressed. CS2 does
## the same thing with CSubtickMoveStep, and it is what makes chained hops land
## when you pressed them rather than up to a tick later.
func simulate(dt: float) -> void:
	previous_position = global_position
	previous_eye_height = eye_height()
	# This is only a hint between sweeps of one tick, not replay state.
	_native_recovery_direction = Vector3.UP
	_friction_refreshed = false

	if noclip:
		reset_eye_state()
		velocity = wish_dir * config.noclip_speed
		global_position += velocity * dt
		on_ground = false
		ground_is_world = false
		jump_fraction = -1.0
		movement_fraction = -1.0
		movement_boundaries.clear()
		movement_impulse = Vector3.INF
		_friction_cached = false
		_last_movement_impulse = Vector3.ZERO
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

	var mover := _native_mover()
	var split_jump := config.subtick_jump and wants_jump and jump_fraction > 0.0 and jump_fraction < 1.0
	var split_snapshot := movement_fraction > 0.0 and movement_fraction < 1.0
	var split_friction := _friction_cached and _friction_until > 0.0 and _friction_until < 1.0
	if movement_boundaries.is_empty() and not split_jump and not split_snapshot and not split_friction:
		_movement_interval(mover, dt, 0.0, 1.0)
	else:
		var boundaries := movement_boundaries.duplicate()
		if split_jump:
			boundaries.append(jump_fraction)
		if split_snapshot:
			boundaries.append(movement_fraction)
		if split_friction:
			boundaries.append(_friction_until)
		boundaries.append(1.0)
		boundaries.sort()
		var start := 0.0
		for end: float in boundaries:
			if end <= start or end > 1.0:
				continue
			if split_jump:
				wants_jump = start >= jump_fraction
			_movement_interval(mover, dt, start, end)
			start = end

	_jump_held_last_tick = wants_jump
	_friction_cached = _friction_refreshed
	jump_fraction = -1.0
	movement_fraction = -1.0
	movement_boundaries.clear()
	movement_impulse = Vector3.INF
	_interval_start = 0.0
	_update_air(was_on_ground)
	if _adapter != null:
		_adapter.queries.end_scope()
		# Later players and shots in this same tick see the completed movement.
		_adapter.queries.sync_object(self, false)
	_adapter = null


func _movement_interval(mover: Object, dt: float, start: float, end: float) -> void:
	_interval_start = start
	_movement_inputs(start, end)
	jump_scale = _jump_scale(dt)
	var airborne := not on_ground
	var height_before := global_position.y
	var falling_at := velocity.y
	_step(mover, dt * (end - start))
	if airborne and on_ground and not _jumped:
		_record_landing(start, end, dt, height_before, falling_at)
	else:
		landed_ago += dt * (end - start)
	_last_movement_impulse = movement_impulse if movement_impulse.is_finite() else wish_dir * wish_speed
	_jump_held_last_tick = wants_jump
	ground_eyes.update(self, dt * (end - start))
	_movement_finished(start, end)


## Command input changes at boundaries, before the next collision interval.
func _movement_inputs(_start: float, _end: float) -> void:
	pass


## Called outside _step: native/script comparison must not save state twice.
func _movement_finished(_start: float, _end: float) -> void:
	pass


## A jump's scale at the start of a movement interval, as CS2's 180ab21a0
## works it out (constants checked in its disassembly): the landing's speed
## sets a floor, min(1, max(0.2, 1 + 0.0005 v)), and the time since the
## landing, plus a tick, raises it 0.6 a second up to 1. A standing jump
## landed flat (about -302 u/s) and taken again at once rises 0.86 as fast,
## and to full height 0.24 s after the landing. Bodies that have not landed
## since spawning jump whole.
func _jump_scale(dt: float) -> float:
	if not is_finite(landed_ago):
		return 1.0
	var floor_scale := clampf(1.0 + landed_speed * 0.0005, 0.2, 1.0)
	return minf(floor_scale + (landed_ago + dt) * 0.6, 1.0)


## Where in an interval the hull came down on the ground and how fast, as
## CS2's landing recorder (180ad3840) solves it: the drop over the interval
## under gravity from the vertical speed it began with, d = v t + a t^2 / 2,
## for the moment t, clamped to the interval; the speed then is v + a t. A
## landing it cannot solve (not falling, or rising onto the ground) is at
## the interval's end at the speed it began with. The fraction is rounded to
## 1/64 of a tick, as CS2 rounds it (+131072, -131072, in single precision,
## whose step at 131072 is 1/64); CS2 also quantizes the speed to 20 bits
## over +-16384, a thirty-second of a unit a second, which is left out.
func _record_landing(start: float, end: float, dt: float, height_before: float, falling_at: float) -> void:
	var interval := dt * (end - start)
	var drop := global_position.y - height_before
	var gravity := -config.gravity
	var at := interval
	var speed := falling_at
	if drop < 0.0 and falling_at < 0.0:
		var discriminant := 2.0 * gravity * drop + falling_at * falling_at
		if discriminant >= 0.0:
			at = clampf((-falling_at - sqrt(discriminant)) / gravity, 0.0, interval)
			speed = gravity * at + falling_at
	var fraction := float(Vector3(start + at / dt + 131072.0, 0.0, 0.0).x) - 131072.0
	landed_ago = (end - fraction) * dt
	landed_speed = speed


## The native code's mover when this tick's steps can be run by it, else
## null and the script runs them. It takes the hull as an upright box
## standing half its height over the body's feet, in a world the body's
## place is told to as it is (nothing above it turned, moved or scaled, so
## that a place written and read back is the place written): anything else
## is the script's, and so is a body whose script has its own of the step's
## functions, or whose bridge has a script of its own. Inside the body's own
## tick, after its scope has begun.
func _native_mover() -> Object:
	if not native_steps or _adapter == null or _collision_shape == null:
		return null
	# The native code asks the physics itself: a bridge with a script of its
	# own over the game's (a profile's, timing its parts) would be gone past.
	if _adapter.queries.get_script() != Box3DQueries:
		return null
	if not native_over_own_functions:
		if _own_step_functions < 0:
			_own_step_functions = 1 if _has_own_step_functions() else 0
		if _own_step_functions == 1:
			return null
	if not _collision_shape.shape is BoxShape3D:
		return null
	if _mover == null:
		if not native_built():
			return null
		_mover = ClassDB.instantiate(NATIVE_CLASS)
		if _mover == null:
			return null
	var over := get_parent_node_3d()
	if over != null and over.global_transform != Transform3D.IDENTITY:
		return null
	if _collision_shape.global_transform != Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, _hull_height * 0.5, 0.0)):
		return null
	if (_collision_shape.shape as BoxShape3D).size != Vector3(config.hull_width, _hull_height, config.hull_width):
		return null
	return _mover


## Whether this body's script has its own of any function the native step
## stands in for. A script lists what it has with what it inherits, so its
## own of one is that one listed twice. Looked up once for each script.
func _has_own_step_functions() -> bool:
	var script: Script = get_script()
	if script == null:
		return false
	if not _own_functions.has(script):
		var listed := {}
		var own := false
		for method: Dictionary in script.get_script_method_list():
			var method_name := StringName(method["name"])
			if method_name not in STEP_FUNCTIONS:
				continue
			if listed.has(method_name):
				own = true
				break
			listed[method_name] = true
		_own_functions[script] = own
	return _own_functions[script]


## One step, by the native code where there is a mover and by the script
## where there is none.
func _step(mover: Object, dt: float) -> void:
	if mover == null:
		_simulate_step(dt)
		return
	if check_steps:
		_step_both_ways(mover, dt)
		return
	_native_step(mover, dt)


func _native_step(mover: Object, dt: float) -> void:
	var queries := _adapter.queries
	if not mover.call(&"step", self, queries.native_world, dt, cos(deg_to_rad(config.max_ground_angle_deg))):
		# It moved nothing: the physics has no sweep by the name it asks for.
		# The script runs this step and every one after.
		native_steps = false
		push_warning("The native code could not run the movement's step (%s in %s), and the script runs it from here on." % [name, queries.native_world])
		_simulate_step(dt)
		return
	PhysicsQueries.native_queries += int(mover.call(&"get_casts"))
	if int(mover.call(&"get_hits")) > 0:
		# A sweep that met something is the last the bridge remembers.
		queries.forget_cast()


## What a step reads and writes of the body, for a step run twice from the
## same start (check_steps).
func _step_state() -> Dictionary:
	return {
		"position": global_position, "velocity": velocity, "on_ground": on_ground,
		"move_acceleration": _move_acceleration, "deferred_velocity": _deferred_velocity,
		"friction_overshoot": _friction_overshoot,
		"friction_cached": _friction_cached, "friction_until": _friction_until,
		"friction_speed": _friction_speed, "friction_refreshed": _friction_refreshed,
		"ground_normal": ground_normal, "ground_is_world": ground_is_world,
		"is_ducked": is_ducked, "duck_progress": duck_progress, "duck_root_offset": duck_root_offset,
		"jumped": _jumped, "looked_from": _looked_from, "looked_with": _looked_with,
		"hull_height": _hull_height, "floor_at": _floor_at, "floor_with": _floor_with,
		"floor_normal": _floor_normal, "floor_is_world": _floor_is_world,
		"quadrant_is_world": _quadrant_is_world, "recovery_direction": _native_recovery_direction,
		"last_recovery": _last_native_trace_recovery, "traces": traces,
	}


func _restore_step_state(state: Dictionary) -> void:
	if _hull_height != float(state["hull_height"]):
		_set_hull(state["hull_height"])
	global_position = state["position"]
	velocity = state["velocity"]
	_move_acceleration = state["move_acceleration"]
	_deferred_velocity = state["deferred_velocity"]
	_friction_overshoot = state["friction_overshoot"]
	_friction_cached = state["friction_cached"]
	_friction_until = state["friction_until"]
	_friction_speed = state["friction_speed"]
	_friction_refreshed = state["friction_refreshed"]
	on_ground = state["on_ground"]
	ground_normal = state["ground_normal"]
	ground_is_world = state["ground_is_world"]
	is_ducked = state["is_ducked"]
	duck_progress = state["duck_progress"]
	duck_root_offset = state["duck_root_offset"]
	_jumped = state["jumped"]
	_looked_from = state["looked_from"]
	_looked_with = state["looked_with"]
	_floor_at = state["floor_at"]
	_floor_with = state["floor_with"]
	_floor_normal = state["floor_normal"]
	_floor_is_world = state["floor_is_world"]
	_quadrant_is_world = state["quadrant_is_world"]
	_native_recovery_direction = state["recovery_direction"]
	_last_native_trace_recovery = state["last_recovery"]
	traces = state["traces"]


## The step by the script and then by the native code, from the same
## start, the native one's result kept and the two held to be the same in
## every part, to the last bit. A difference is a fault, said with where
## the body stood and what differed.
func _step_both_ways(mover: Object, dt: float) -> void:
	var start := _step_state()
	var queries_before := PhysicsQueries.native_queries
	_simulate_step(dt)
	var by_script := _step_state()
	var script_queries := PhysicsQueries.native_queries - queries_before
	_restore_step_state(start)
	PhysicsQueries.native_queries = queries_before
	_native_step(mover, dt)
	var by_native := _step_state()
	var native_queries := PhysicsQueries.native_queries - queries_before
	steps_checked += 1
	var differs := PackedStringArray()
	for part: String in by_script:
		var a: Variant = by_script[part]
		var b: Variant = by_native[part]
		if typeof(a) != typeof(b) or a != b:
			differs.append("%s: the script %s, the native code %s" % [part, var_to_str(a), var_to_str(b)])
	if script_queries != native_queries:
		differs.append("queries: the script %d, the native code %d" % [script_queries, native_queries])
	if not differs.is_empty() and step_faults.size() < 40:
		step_faults.append("%s stepped %s s from %s going %s (on the ground %s, ducked %s, wishing %s at %s, jump %s, duck %s): %s" % [
			name, var_to_str(dt), var_to_str(start["position"]), var_to_str(start["velocity"]), start["on_ground"], start["is_ducked"],
			var_to_str(wish_dir), var_to_str(wish_speed), wants_jump, wants_duck, "; ".join(differs)])


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
	_move_acceleration = Vector3.ZERO
	_deferred_velocity = Vector3.ZERO
	_friction_overshoot = 0.0
	if not _ground_known():
		_categorize_position()
	_update_duck(dt)

	var surface_friction := MovementSolver.surface_friction_for(
		velocity.y, on_ground, config
	)

	velocity = MovementSolver.check_velocity(velocity, config)

	_try_jump(dt)

	if on_ground:
		velocity.y = 0.0
		_update_friction_cache()
		_apply_ground_friction(surface_friction, dt)

	if on_ground:
		_walk_move(surface_friction, dt)
	else:
		_air_move(surface_friction, dt)

	_categorize_position()

	if on_ground:
		velocity.y = 0.0
		_move_acceleration.y = 0.0
		_deferred_velocity.y = 0.0

	velocity = MovementSolver.check_velocity(velocity, config)


func _apply_ground_friction(surface_friction: float, dt: float) -> void:
	var speed := velocity.length()
	var control := _friction_speed if _friction_cached else MovementSolver.quantized_speed(speed)
	var rate := 0.0 if control < 0.1 else maxf(control, config.stop_speed) * config.friction * surface_friction
	if dt <= 0.0 or rate <= 0.0:
		return
	var drop := rate * dt
	_friction_overshoot = maxf(drop - speed, 0.0)
	if speed > 0.0:
		_move_acceleration -= (velocity / speed) * minf(rate, speed / dt)
		velocity *= maxf(speed - drop, 0.0) / speed


func _update_friction_cache() -> void:
	var at_boundary := _friction_cached and _friction_until == _interval_start
	if _friction_cached and not at_boundary:
		return
	_friction_cached = false
	var speed := MovementSolver.quantized_speed(Vector2(velocity.x, velocity.z).length())
	var impulse := movement_impulse if movement_impulse.is_finite() else wish_dir * wish_speed
	if (at_boundary and speed != _friction_speed) or impulse != _last_movement_impulse:
		_friction_cached = true
		_friction_until = _interval_start
		_friction_speed = speed
		_friction_refreshed = true


## Move at the half-step velocity, then restore this same state after
## collision. Gravity uses this vector too; there is no second finish-gravity.
func _defer_acceleration(dt: float) -> void:
	var half := _move_acceleration * dt * 0.5
	velocity -= half
	_deferred_velocity += half


func _stop_movement() -> void:
	velocity = Vector3.ZERO
	_move_acceleration = Vector3.ZERO
	_deferred_velocity = Vector3.ZERO


## An unsupported completed move stopped by collision. Under positive
## gravity, normal flight (including a zero-velocity apex) retains gravity
## in acceleration/deferred state; only a hard stop clears all three.
## Bot recovery can sample this state without another collision query.
func blocked_air_move() -> bool:
	return not on_ground and not noclip and config.gravity > 0.0 \
		and _ground_known() and velocity == Vector3.ZERO \
		and _move_acceleration == Vector3.ZERO and _deferred_velocity == Vector3.ZERO


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


## Ducking.
##
## On the ground the hull shrinks from the top after duck_time, so your feet
## stay put and your head comes down. In the air it happens at once and
## about the hull's middle: CS2 lifts the body half the difference (9; Source
## lifted all 18, the head staying put), so your feet come up, and the eyes
## are eased down after (_finish_duck). That is the crouch jump, and it is
## the only way to reach a ledge higher than a standing jump clears.
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
	var airborne := not on_ground

	# Shrink first. A smaller hull can never collide with something the larger
	# one did not, so this is always safe, and it gives the move below the
	# headroom it needs.
	_set_hull(config.duck_height)

	if airborne:
		# CS2's FinishDuck (180abdbe0): in the air the hull shrinks about its
		# middle, the body lifted half the hulls' difference (9 units, where
		# Source lifted all 18), and the root offset holds the eyes where they
		# were until the eye update eases them down.
		var lift := _duck_height_delta() * 0.5
		var from := global_position.y
		_trace(Vector3.UP * lift)
		duck_root_offset -= global_position.y - from
		duck_progress = 1.0

	is_ducked = true


func _finish_unduck() -> void:
	if not on_ground:
		# CS2's FinishUnDuck (180abe2f0): the body lowered half the
		# difference, the eyes held up by as much.
		var from := global_position.y
		_trace(Vector3.DOWN * (_duck_height_delta() * 0.5))
		duck_root_offset -= global_position.y - from
		duck_progress = 0.0
	_set_hull(config.stand_height)
	is_ducked = false


## Is there room to stand up? On the ground, sweeping the ducked hull up
## through the distance it grows covers the standing hull's volume. In the
## air CS2 (180ab3f50) sweeps the standing hull from where it would grow to
## half the difference below, needing it to start clear and go the whole
## way: the ducked hull swept up the whole difference and down the half
## covers the same volume.
func _can_unduck() -> bool:
	var delta := _duck_height_delta()
	if on_ground:
		return _trace(Vector3.UP * delta, true) == null
	return _trace(Vector3.UP * delta, true) == null and _trace(Vector3.DOWN * (delta * 0.5), true) == null


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


## The simulation eye offset above the feet, as CS2's eye update
## (180ae23e0) builds it: the standing view's 64, the root and ground
## adjustment and the duck view offset, all updated at the movement
## segment's end (GroundEyes.update). The crouched 46 is the standing 64
## less the hulls' difference, as CS2 has them.
func eye_height() -> float:
	return ground_eyes.height(config.stand_eye_height + duck_view_offset)


## The same temporal sample as previous_position.lerp(global_position).
## Interpolating only the feet would leave terrain/crouch eyes a tick ahead.
func interpolated_eye_height(fraction: float) -> float:
	return lerpf(previous_eye_height, eye_height(), clampf(fraction, 0.0, 1.0))


## A spawn or teleport must not carry the previous floor's residual or
## sample cache, nor interpolate from the old location's eye adjustment.
func reset_eye_state() -> void:
	ground_eyes.reset()
	landed_ago = INF
	duck_root_offset = 0.0
	duck_view_offset = -(config.stand_height - config.duck_height) * duck_progress
	previous_eye_height = eye_height()


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
	if config.cs2_jump:
		# CS2 (180adf830) sets impulse - gravity * 0.5 * (1/128), then
		# applies full gravity through the same deferred state as horizontal
		# acceleration; ducked or ducking it gives the whole impulse. Then
		# the whole is scaled by how soon after a landing it is (jump_scale).
		if not (is_ducked or duck_progress > 0.0):
			velocity.y -= config.gravity * 0.5 / 128.0
		velocity.y *= jump_scale
	elif not config.tick_rate_independent_jump:
		# Compatibility: Source 1 overwrote StartGravity with its impulse,
		# so its first move travelled at the full impulse.
		velocity.y += config.gravity * 0.5 * dt
	on_ground = false
	ground_is_world = false


func _walk_move(surface_friction: float, dt: float) -> void:
	# Source keeps the move direction flat and never consults the ground
	# normal. Projecting onto the slope bleeds less speed uphill, which is
	# nicer and is a divergence, so it is a flag.
	var dir := wish_dir
	if config.project_wish_dir_on_ground and ground_normal != Vector3.UP:
		dir = MovementSolver.clip_velocity(dir, ground_normal)
		if dir.length_squared() > 0.0:
			dir = dir.normalized()

	var accelerate := config.accelerate
	if walk_acceleration_limit > 0.0:
		accelerate *= MovementSolver.walk_acceleration_fraction(velocity.dot(dir), walk_acceleration_limit)
	var rate := MovementSolver.ground_acceleration_rate(
		velocity, dir, wish_speed, accelerate, surface_friction, dt,
		acceleration_speed, _friction_overshoot
	)
	_move_acceleration += dir * rate
	velocity += dir * (rate * dt)
	velocity.y = 0.0
	_move_acceleration.y = 0.0
	_deferred_velocity.y = 0.0
	var speed := velocity.length()
	if speed > movement_speed_limit:
		var before_cap := velocity
		velocity *= movement_speed_limit / speed
		if dt > 0.0:
			_move_acceleration += (velocity - before_cap) / dt
	_defer_acceleration(dt)
	# CS2 predicts toward its fixed 64-Hz interval for the <1 u/s stop;
	# for a whole tick this is the final speed, for a subtick it is not.
	var predicted := velocity + _move_acceleration * (1.0 / 64.0 - dt * 0.5)
	if predicted.length() < 1.0:
		_stop_movement()
		return
	var start := global_position
	var midpoint := velocity
	if not _step_move(dt):
		var midpoint_speed := midpoint.length()
		if midpoint_speed > 0.0 and midpoint_speed < config.step_move_velocity_min and wish_dir != Vector3.ZERO:
			# WalkMove retries only the raised path, using the saved midpoint
			# start. Cleared acceleration/deferred state stays cleared.
			_try_step(dt, start, midpoint * (config.step_move_velocity_min / midpoint_speed))
	velocity += _deferred_velocity
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
	var world_ground := _is_world_ground(hit.get("collider"))
	var landing: Vector3
	if normal.is_zero_approx():
		# Something over its head where it would start: from where it
		# stands, then, clear of what it stands in first.
		var collision := _trace(Vector3.DOWN * config.step_height, true)
		if collision == null or not MovementSolver.is_walkable(collision.get_normal(), config):
			global_position = start + _last_native_trace_recovery
			return
		normal = collision.get_normal()
		world_ground = collision.is_world
		landing = start + collision.get_travel()
	elif not MovementSolver.is_walkable(normal, config):
		return
	else:
		landing = start + lift + motion * float(hit["fraction"]) + (hit.get("offset", Vector3.ZERO) as Vector3)
	global_position = landing
	_floor_at = global_position
	_floor_with = _hull_height
	_floor_normal = normal
	_floor_is_world = world_ground


func _air_move(surface_friction: float, dt: float) -> void:
	var available := minf(wish_speed, config.air_max_wishspeed) - velocity.dot(wish_dir)
	if available > 0.0 and dt > 0.0:
		# The cap applies separately to the two halves, not to a full
		# addition that is then averaged (server 180ab07c0).
		var half := wish_speed * config.air_accelerate * surface_friction * dt * 0.5
		var before := minf(available, half)
		var after := minf(available - before, half)
		velocity += wish_dir * before
		_deferred_velocity += wish_dir * after
	# AddGravity (180ab0670), followed by the same half-step transfer used
	# on the ground. Collision can clear its deferred half on a hard stop.
	velocity.y -= config.gravity * dt
	_move_acceleration.y -= config.gravity
	_defer_acceleration(dt)
	_try_player_move(dt)
	velocity += _deferred_velocity


## Source's StepMove. Run the move flat, then run it again stepping up and back
## down, and keep whichever covered more ground horizontally. This is what
## walks you up stairs without a ramp under them, and it is why the result is
## compared rather than the step always being preferred.
func _step_move(dt: float) -> bool:
	var start_position := global_position
	var start_velocity := velocity

	# A flat move that met nothing is taken as it is, as Source's WalkMove
	# takes it before ever trying the step: the stepped one could go no
	# further, so it is only tried against something in the way.
	if not _try_player_move(dt):
		return true
	return _try_step(dt, start_position, start_velocity)


## The raised candidate only. CS2 calls it a second time after a failed
## low-speed step; repeating the flat move would clip state twice.
func _try_step(dt: float, start_position: Vector3, start_velocity: Vector3) -> bool:
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
	var landed_walkable := landing != null and (landing.travel - landing.recovery).dot(Vector3.DOWN) > 0.0 \
		and MovementSolver.is_walkable(landing.get_normal(), config)

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
			_floor_is_world = landing.is_world
		return true
	global_position = flat_position
	velocity = flat_velocity
	# A valid landing suppresses the retry even when the flat path wins.
	return landed_walkable


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
			_stop_movement()
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
					_stop_movement()
					break
				# Two planes forming a crease: slide along their intersection.
				var crease := planes[0].cross(planes[1])
				if crease.length_squared() == 0.0:
					_stop_movement()
					break
				crease = crease.normalized()
				velocity = crease * crease.dot(velocity)

			# If clipping reversed us relative to where we wanted to go, stop
			# rather than getting shot backwards out of a corner.
			if velocity.dot(primal_velocity) <= 0.0:
				_stop_movement()
				break

	# A stationary half-step can still have velocity waiting to be restored
	# (notably the exact jump apex). Only a blocked move clears that state.
	if all_fraction == 0.0 and met_something:
		_stop_movement()
	return met_something


## Determines whether we are standing on something, and on what.
func _categorize_position() -> void:
	# Moving up faster than NON_JUMP_VELOCITY means we definitively left the
	# ground, so Source skips the trace entirely for the tick. That is also
	# what bounds the dead-strafe friction zone.
	if velocity.y > config.non_jump_velocity:
		on_ground = false
		ground_is_world = false
		ground_normal = Vector3.UP
		_looked_from = Vector3.INF
		_floor_at = Vector3.INF
		return
	if _floor_at == global_position and _floor_with == _hull_height:
		# The walking move has just been put on this floor by a sweep of its
		# own, which is the sweep this would make.
		on_ground = true
		ground_normal = _floor_normal
		ground_is_world = _floor_is_world
		_looked_from = global_position
		_looked_with = _hull_height
		_floor_at = Vector3.INF
		return
	_floor_at = Vector3.INF

	var collision := _trace(
		Vector3.DOWN * GROUND_TRACE_DISTANCE, true
	)
	var normal := Vector3.ZERO
	var world_ground := collision != null and collision.is_world
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
		world_ground = _quadrant_is_world
		if normal == Vector3.ZERO:
			on_ground = false
			ground_is_world = false
			ground_normal = Vector3.UP
			_looked_from = global_position
			_looked_with = _hull_height
			return

	on_ground = true
	ground_normal = normal
	ground_is_world = world_ground
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
		return TraceResult.new(collision.get_travel(), collision.get_normal(), Vector3.ZERO,
			_is_world_ground(collision.get_collider())) if collision != null else null
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
	return TraceResult.new(travel, hit["normal"], recovery, _is_world_ground(hit.get("collider"))) if not hit.is_empty() else null


## The map importer and bare fixtures author fixed world geometry as
## StaticBody3D. AnimatableBody3D inherits it, but is a moving entity.
static func _is_world_ground(collider: Object) -> bool:
	return collider is StaticBody3D and not collider is AnimatableBody3D


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
	return _ground_normal_in_quadrants_at(global_position)


## The same for a body standing at `at`: the native step asks from where it
## has the body, which the node is told when the step is over.
func _ground_normal_in_quadrants_at(at: Vector3) -> Vector3:
	_quadrant_is_world = false
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
		var from: Vector3 = at + corner + Vector3.UP * QUADRANT_INSET
		var to: Vector3 = from + Vector3.DOWN * (GROUND_TRACE_DISTANCE + QUADRANT_INSET)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = collision_mask
		query.exclude = [get_rid()]
		var hit := PhysicsQueries.intersect_ray(space, query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		if MovementSolver.is_walkable(normal, config):
			_quadrant_is_world = _is_world_ground(hit.get("collider"))
			return normal
	return Vector3.ZERO
