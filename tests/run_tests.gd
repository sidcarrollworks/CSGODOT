extends SceneTree

## Headless test run.
##
##   godot --headless --path . --script tests/run_tests.gd
##
## Two halves. The first checks the acceleration model against hand-computed
## values, which is the part that decides feel and the part most likely to be
## broken by a well-meaning edit. The second loads the real test map and steps
## it, which catches the collide-and-slide falling through the floor.

const DT := 1.0 / 128.0
const EPS := 0.001

var _failures: int = 0
var _checks: int = 0
var _frames: int = 0
var _player: PlayerBody
var _ground_y: float = 0.0
var _jump_peak: float = 0.0
var _jump_peak_independent: float = 0.0

## Long enough for a full jump at 128 Hz: apex is about 48 ticks in, and the
## landing about 96.
const JUMP_TICKS := 110
const FALL_FRAMES := 120


func _initialize() -> void:
	_test_friction()
	_test_ground_acceleration()
	_test_air_acceleration()
	_test_clip_velocity()
	_test_walkable()
	_test_deadstrafe()
	_test_bunnyhop_clamp()


func _process(_delta: float) -> bool:
	# The scene is loaded on the first frame rather than in _initialize,
	# because the tree root is not ready to parent into until then.
	if _frames == 0:
		var scene: PackedScene = load("res://maps/test_movement/test_movement.tscn")
		var instance := scene.instantiate()
		root.add_child(instance)
		_player = instance.get_node("Player") as PlayerBody

	_frames += 1

	# Phase 1: let the controller run and the player fall onto the floor.
	if _frames < FALL_FRAMES:
		return false
	if _frames == FALL_FRAMES:
		_test_player_lands()
		_begin_jump_measurement()
		return false

	# Phase 2: drive the body directly so a jump can be measured without an
	# actual keyboard. This exercises the real simulate() path, collision and
	# all, rather than a reimplementation of the integrator.
	var since_landing := _frames - FALL_FRAMES
	if since_landing <= JUMP_TICKS:
		_step_jump(since_landing == 1)
		_jump_peak = maxf(_jump_peak, _player.global_position.y - _ground_y)
		return false

	# Phase 3: the same jump with the tick-rate-independent impulse, which
	# should come out at the textbook height instead of Source's.
	if since_landing == JUMP_TICKS + 1:
		_player.config.tick_rate_independent_jump = true
		_ground_y = _player.global_position.y
		return false

	var since_second := since_landing - JUMP_TICKS - 1
	if since_second <= JUMP_TICKS:
		_step_jump(since_second == 1)
		_jump_peak_independent = maxf(
			_jump_peak_independent, _player.global_position.y - _ground_y
		)
		return false

	_test_jump_height()
	_report()
	return true


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
	if _failures == 0:
		print("%d checks passed." % _checks)
		quit(0)
	else:
		printerr("%d of %d checks failed." % [_failures, _checks])
		quit(1)


# --- Solver tests ---------------------------------------------------------

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


# --- Scene test -----------------------------------------------------------

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
		_player.global_position.y > -32.0,
		"player did not fall through the floor"
	)
	_check(
		absf(_player.velocity.y) < 1.0,
		"player is at rest vertically (vy = %.3f)" % _player.velocity.y
	)


func _begin_jump_measurement() -> void:
	if _player == null:
		return
	_player.set_physics_process(false)
	_ground_y = _player.global_position.y
	_jump_peak = 0.0


## One tick of standing still, optionally jumping on this tick.
func _step_jump(jump_now: bool) -> void:
	_player.wish_dir = Vector3.ZERO
	_player.wish_speed = 0.0
	_player.wants_jump = jump_now
	_player.simulate(DT)


## With sv_jump_impulse 301.993 and sv_gravity 800 a standing jump has to peak
## at about 57 units. That number is why a 56-unit ledge is reachable in CS and
## a 64-unit one is not, so it is worth pinning down.
##
## It also guards the gravity split in PlayerBody.simulate(). Applying gravity
## in one lump instead of two halves loses over a unit of jump height at
## 128 Hz, and more at lower tick rates, which would silently change how every
## ledge in the game plays.
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
