extends SceneTree

## Headless test run.
##
##   godot --headless --path . --import
##   godot --headless --path . --script tests/run_tests.gd
##
## (scripts/run_tests.sh does both.)
##
## Two halves. The first checks the acceleration model against hand-computed
## values, which is the part that decides feel and the part most likely to be
## broken by a well-meaning edit. The second loads the real test course and
## drives the real body through it: jumps, crouch jumps, a surf ramp and a
## walk up a ramp. Those catch the things that are correct in the maths and
## wrong in the world, which is where the interesting bugs have been so far.

const DT := 1.0 / 128.0
const EPS := 0.001

## Frames of ordinary controller-driven simulation before the scripted phases
## start, so the player has fallen onto the floor and settled.
const FALL_FRAMES := 120

## Per-phase timing, in ticks.
const SETTLE_TICKS := 24
const JUMP_TICKS := 110
const SURF_TICKS := 160
const CLIMB_TICKS := 800

## Ducking a few ticks after leaving the ground, which is what a crouch jump
## is. Immediately at the apex would be optimal; this is a realistic input.
const CROUCH_DELAY_TICKS := 10

var _failures: int = 0
var _checks: int = 0
var _frames: int = 0

var _course: Node3D
var _player: PlayerBody

var _phase: int = 0
var _phase_tick: int = 0

var _jump_peak: float = 0.0
var _jump_peak_independent: float = 0.0
var _crouch_jump_peak: float = 0.0
var _reference_y: float = 0.0

var _surf_drop: float = 0.0
var _surf_speed: float = 0.0
var _surf_stuck: bool = true

var _climb_height: float = 0.0


func _process(_delta: float) -> bool:
	# The scene is loaded on the first frame rather than in _initialize,
	# because the tree root is not ready to parent into until then.
	if _frames == 0:
		_run_solver_tests()
		var scene: PackedScene = load("res://maps/test_movement/test_movement.tscn")
		_course = scene.instantiate() as Node3D
		root.add_child(_course)
		_player = _course.get_node("Player") as PlayerBody

	_frames += 1

	# Phase 1: let the controller run and the player fall onto the floor.
	if _frames < FALL_FRAMES:
		return false
	if _frames == FALL_FRAMES:
		_test_player_lands()
		# From here the body is driven directly, so jumps and walks can be
		# scripted without a keyboard. This still exercises the real
		# simulate() path, collision and all.
		_player.set_physics_process(false)
		return false

	_phase_tick += 1
	match _phase:
		0: _phase_jump(false)
		1: _phase_jump(true)
		2: _phase_crouch_jump()
		3: _phase_surf()
		4: _phase_climb()
		_:
			_test_jump_height()
			_test_crouch_jump()
			_test_surf()
			_test_climb()
			_report()
			return true
	return false


func _advance_phase() -> void:
	_phase += 1
	_phase_tick = 0


## Puts the player somewhere with no velocity and standing up.
func _place(position: Vector3) -> void:
	_player.global_position = position
	_player.velocity = Vector3.ZERO
	_player.wish_dir = Vector3.ZERO
	_player.wish_speed = 0.0
	_player.wants_jump = false
	_player.wants_duck = false


## One tick with the given intent.
func _step(
	wish_dir: Vector3 = Vector3.ZERO,
	jump: bool = false,
	duck: bool = false
) -> void:
	_player.wish_dir = wish_dir
	_player.wish_speed = 0.0 if wish_dir == Vector3.ZERO else _player.config.max_speed
	_player.wants_jump = jump
	_player.wants_duck = duck
	_player.simulate(DT)


# --- Scripted phases ------------------------------------------------------

## A standing jump from flat ground, measured through the real body.
func _phase_jump(tick_rate_independent: bool) -> void:
	if _phase_tick == 1:
		_player.config.tick_rate_independent_jump = tick_rate_independent
		_place(Vector3(0.0, 8.0, 256.0))
		return
	if _phase_tick <= SETTLE_TICKS:
		_step()
		return
	if _phase_tick == SETTLE_TICKS + 1:
		_reference_y = _player.global_position.y
		_step(Vector3.ZERO, true)
		return
	if _phase_tick <= SETTLE_TICKS + JUMP_TICKS:
		_step()
		var height := _player.global_position.y - _reference_y
		if tick_rate_independent:
			_jump_peak_independent = maxf(_jump_peak_independent, height)
		else:
			_jump_peak = maxf(_jump_peak, height)
		return
	_advance_phase()


## The same jump with duck held from a few ticks in. Ducking in the air pulls
## the feet up, so the height a crouch jump can land on is well above what a
## standing jump clears. This is the difference between reaching a 64 unit
## ledge and not.
func _phase_crouch_jump() -> void:
	if _phase_tick == 1:
		_player.config.tick_rate_independent_jump = false
		_place(Vector3(0.0, 8.0, 256.0))
		return
	if _phase_tick <= SETTLE_TICKS:
		_step()
		return
	if _phase_tick == SETTLE_TICKS + 1:
		_reference_y = _player.global_position.y
		_step(Vector3.ZERO, true)
		return
	if _phase_tick <= SETTLE_TICKS + JUMP_TICKS:
		var airborne_ticks := _phase_tick - SETTLE_TICKS - 1
		_step(Vector3.ZERO, false, airborne_ticks >= CROUCH_DELAY_TICKS)
		_crouch_jump_peak = maxf(
			_crouch_jump_peak, _player.global_position.y - _reference_y
		)
		return
	_advance_phase()


## Dropped onto the face of a 55 degree ramp, the player must slide down it and
## pick up speed, not stand on it. Walking on this was the bug: the ramps were
## built as tall boxes rotated 55 degrees, which presents a 35 degree surface.
func _phase_surf() -> void:
	if _phase_tick == 1:
		_place(_course.surf_left_surface_point + Vector3(24.0, 24.0, 0.0))
		_surf_stuck = true
		return
	if _phase_tick <= SURF_TICKS:
		_step()
		if not _player.on_ground:
			_surf_stuck = false
		_surf_drop = _course.surf_left_surface_point.y - _player.global_position.y
		_surf_speed = Vector2(_player.velocity.x, _player.velocity.z).length()
		return
	_advance_phase()


## Walking up the access ramp to the top of the surf lane, starting on the
## floor short of it so the seam where ramp meets floor is tested too. "I could
## not reach the top" is a movement bug, not a level design opinion.
func _phase_climb() -> void:
	if _phase_tick == 1:
		_place(_course.access_ramp_bottom + Vector3(0.0, 8.0, 64.0))
		return
	if _phase_tick <= CLIMB_TICKS:
		_step(Vector3(0.0, 0.0, -1.0))
		_climb_height = maxf(_climb_height, _player.global_position.y)
		return
	_advance_phase()


# --- Assertions -----------------------------------------------------------

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	printerr("FAIL: %s" % description)


func _check_near(actual: float, expected: float, description: String) -> void:
	_checks += 1
	if absf(actual - expected) <= EPS:
		return
	_failures += 1
	printerr("FAIL: %s (expected %.6f, got %.6f)" % [description, expected, actual])


func _report() -> void:
	# Worth printing even on success: these are the numbers the whole project
	# is tuned against, and seeing them move is how you notice a change that
	# the assertions were not tight enough to catch.
	print("measured: standing jump %.2f, crouch jump %.2f, surf drop %.1f at %.1f u/s, climb %.1f" % [
		_jump_peak, _crouch_jump_peak, _surf_drop, _surf_speed, _climb_height
	])
	if _failures == 0:
		print("%d checks passed." % _checks)
		quit(0)
	else:
		printerr("%d of %d checks failed." % [_failures, _checks])
		quit(1)


# --- Solver tests ---------------------------------------------------------

func _run_solver_tests() -> void:
	_test_friction()
	_test_ground_acceleration()
	_test_air_acceleration()
	_test_clip_velocity()
	_test_walkable()
	_test_deadstrafe()
	_test_bunnyhop_clamp()


func _test_friction() -> void:
	var cfg := MovementConfig.new()

	# Above stop_speed, drop is proportional to current speed:
	# 250 * 5.2 / 128 = 10.15625
	var fast := MovementSolver.apply_friction(
		Vector3(0, 0, -250), true, 1.0, cfg, DT
	)
	_check_near(fast.length(), 239.84375, "friction above stop_speed")

	# Below stop_speed, stop_speed is used as the control value instead, which
	# is what makes stopping crisp: 80 * 5.2 / 128 = 3.25
	var slow := MovementSolver.apply_friction(
		Vector3(0, 0, -50), true, 1.0, cfg, DT
	)
	_check_near(slow.length(), 46.75, "friction below stop_speed uses stop_speed")

	# No air drag at all.
	var airborne := MovementSolver.apply_friction(
		Vector3(0, 0, -250), false, 1.0, cfg, DT
	)
	_check_near(airborne.length(), 250.0, "no friction in the air")


func _test_ground_acceleration() -> void:
	var cfg := MovementConfig.new()
	var forward := Vector3(0, 0, -1)

	# From rest: 5.5 * (1/128) * 250 = 10.7421875
	var stepped := MovementSolver.accelerate(
		Vector3.ZERO, forward, cfg.max_speed, cfg.accelerate, 1.0, DT
	)
	_check_near(stepped.length(), 10.7421875, "ground accel from rest")

	# Already at wish speed: nothing is added.
	var capped := MovementSolver.accelerate(
		forward * cfg.max_speed, forward, cfg.max_speed, cfg.accelerate, 1.0, DT
	)
	_check_near(capped.length(), cfg.max_speed, "ground accel does not exceed wish speed")


func _test_air_acceleration() -> void:
	var cfg := MovementConfig.new()
	var forward := Vector3(0, 0, -1)

	# Holding forward while already moving forward fast does nothing, because
	# air_max_wishspeed clamps the target to 30 u/s along the wish direction.
	# This is why you cannot gain speed in the air by holding W.
	var straight := MovementSolver.air_accelerate(
		forward * 250.0, forward, cfg.max_speed, cfg.air_accelerate, 1.0, cfg, DT
	)
	_check_near(straight.length(), 250.0, "holding forward in air adds nothing")

	# Pointing the wish direction sideways does gain speed, because current
	# speed along that axis is zero. This is an air strafe.
	# accel_speed = 12 * 250 * (1/128) = 23.4375, clamped by addspeed 30.
	var strafed := MovementSolver.air_accelerate(
		Vector3(250, 0, 0), forward, cfg.max_speed, cfg.air_accelerate, 1.0, cfg, DT
	)
	_check_near(strafed.z, -23.4375, "air strafe adds along the wish direction")
	_check(strafed.length() > 250.0, "air strafe increases total speed")

	# The asymmetry that makes the above work: addspeed is clamped by 30 but
	# accelspeed scales with the full wish speed. A low wish speed accelerates
	# more slowly even though the clamp is the same.
	var slow_wish := MovementSolver.air_accelerate(
		Vector3(250, 0, 0), forward, 100.0, cfg.air_accelerate, 1.0, cfg, DT
	)
	_check_near(slow_wish.z, -9.375, "air accel scales with unclamped wish speed")


func _test_clip_velocity() -> void:
	# Landing on flat ground removes all vertical velocity.
	var landed := MovementSolver.clip_velocity(Vector3(0, -100, 0), Vector3.UP)
	_check_near(landed.length(), 0.0, "clip against flat ground kills vertical speed")

	# Sliding along a wall keeps the tangential component untouched.
	var along_wall := MovementSolver.clip_velocity(
		Vector3(100, 0, -100), Vector3(-1, 0, 0)
	)
	_check_near(along_wall.x, 0.0, "clip removes the into-wall component")
	_check_near(along_wall.z, -100.0, "clip keeps the along-wall component")


func _test_walkable() -> void:
	var cfg := MovementConfig.new()
	# Source's threshold sits between these two, which is exactly why a ramp
	# steeper than about 45.6 degrees can be surfed rather than walked.
	var shallow := Vector3(0, cos(deg_to_rad(44.0)), sin(deg_to_rad(44.0))).normalized()
	var steep := Vector3(0, cos(deg_to_rad(50.0)), sin(deg_to_rad(50.0))).normalized()
	_check(MovementSolver.is_walkable(shallow, cfg), "44 degree slope is walkable")
	_check(not MovementSolver.is_walkable(steep, cfg), "50 degree slope is not walkable")


func _test_deadstrafe() -> void:
	var cfg := MovementConfig.new()
	_check_near(
		MovementSolver.surface_friction_for(70.0, false, cfg), 0.25,
		"CS2 dead strafe applies while rising slowly"
	)
	_check_near(
		MovementSolver.surface_friction_for(200.0, false, cfg), 1.0,
		"no dead strafe above the vertical speed threshold"
	)
	_check_near(
		MovementSolver.surface_friction_for(-50.0, false, cfg), 1.0,
		"no dead strafe while falling"
	)
	_check_near(
		MovementSolver.surface_friction_for(70.0, true, cfg), 1.0,
		"no dead strafe while on the ground"
	)

	cfg.cs2_deadstrafe = false
	_check_near(
		MovementSolver.surface_friction_for(70.0, false, cfg), 1.0,
		"dead strafe can be turned off for GoldSrc feel"
	)


func _test_bunnyhop_clamp() -> void:
	var cfg := MovementConfig.new()
	var clamped := MovementSolver.clamp_bunnyhop(Vector3(400, 100, 0), cfg)
	_check_near(
		Vector2(clamped.x, clamped.z).length(), 275.0,
		"chained jump is clamped to 1.1x max speed"
	)
	_check_near(clamped.y, 100.0, "bunnyhop clamp leaves vertical speed alone")

	cfg.enable_bunnyhopping = true
	var unclamped := MovementSolver.clamp_bunnyhop(Vector3(400, 100, 0), cfg)
	_check_near(
		Vector2(unclamped.x, unclamped.z).length(), 400.0,
		"bunnyhop clamp can be turned off"
	)


# --- Scene tests ----------------------------------------------------------

## The cheap but load-bearing check: does the player, dropped above the floor,
## land on it rather than falling through. Collide-and-slide bugs usually show
## up here first.
func _test_player_lands() -> void:
	_check(_player != null, "player exists in the test map")
	if _player == null:
		return
	_check(_player.on_ground, "player is on the ground after falling")
	_check(
		absf(_player.global_position.y) < 2.0,
		"player settled on the floor (y = %.3f)" % _player.global_position.y
	)
	_check(
		absf(_player.velocity.y) < 1.0,
		"player is at rest vertically (vy = %.3f)" % _player.velocity.y
	)


func _test_jump_height() -> void:
	var cfg := MovementConfig.new()

	# Textbook height, which is what the impulse and gravity alone give.
	var ideal := cfg.jump_impulse * cfg.jump_impulse / (2.0 * cfg.gravity)

	# Source's actual height, because the impulse lands after the leading
	# half-step of gravity and so the first tick travels at full speed. This
	# is tick-rate dependent, which is exactly why it is pinned here.
	var source_height := ideal + cfg.jump_impulse * DT * 0.5

	_check(
		absf(_jump_peak - source_height) < 0.2,
		"Source-faithful jump peaks at %.2f units (got %.2f)" % [
			source_height, _jump_peak
		]
	)
	_check(
		absf(_jump_peak_independent - ideal) < 0.2,
		"tick-rate-independent jump peaks at %.2f units (got %.2f)" % [
			ideal, _jump_peak_independent
		]
	)
	_check(
		_jump_peak > _jump_peak_independent,
		"Source ordering jumps higher than the textbook value"
	)


## The course has ledges at 32, 48, 56 and 64 units. A standing jump clears 56
## and not 64; a crouch jump has to clear 64, because that is what a crouch
## jump is for.
func _test_crouch_jump() -> void:
	_check(
		_crouch_jump_peak > _jump_peak + 8.0,
		"crouch jump gets the feet meaningfully higher than a standing jump (%.2f vs %.2f)" % [
			_crouch_jump_peak, _jump_peak
		]
	)
	_check(
		_crouch_jump_peak > 64.0,
		"crouch jump clears the 64 unit ledge (peaked at %.2f)" % _crouch_jump_peak
	)


func _test_surf() -> void:
	_check(
		not _surf_stuck,
		"player does not stand on the 55 degree surf ramp"
	)
	_check(
		_surf_drop > 64.0,
		"player slides down the surf ramp (dropped %.1f units)" % _surf_drop
	)
	_check(
		_surf_speed > 100.0,
		"sliding down the surf ramp builds speed (%.1f u/s)" % _surf_speed
	)


func _test_climb() -> void:
	_check(
		_climb_height > _course.surf_channel_top_height - 32.0,
		"player can walk up the access ramp to the top of the surf lane (reached %.1f of %.1f)" % [
			_climb_height, _course.surf_channel_top_height
		]
	)
