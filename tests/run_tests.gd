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

## Running down the eight-step flight, long enough to cover the whole thing.
const STAIR_TICKS := 90

## Jump presses tested at different points inside one tick. A fraction of -1
## means there was no button transition to time, so the press lands on the tick
## boundary. The last entry repeats a mid-tick press with sub-tick timing off,
## which should land on the boundary like the first one.
const JUMP_PRESSES := [
	{"fraction": -1.0, "subtick": true},
	{"fraction": 0.25, "subtick": true},
	{"fraction": 0.5, "subtick": true},
	{"fraction": 0.75, "subtick": true},
	{"fraction": 0.75, "subtick": false},
]

## The speed each test hop is taken at. Above max_speed, so ground
## acceleration has nothing left to add and friction is the only thing acting,
## which is the state you land in mid-bunny-hop. Below 1.1 * max_speed, or
## clamp_bunnyhop would flatten every case to the same number and hide the
## difference being measured.
const SUBTICK_HOP_SPEED := 230.0

const SUBTICK_SETTLE_TICKS := 24

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

var _stair_airborne: int = 0
var _stair_peak: float = 0.0
var _stair_airborne_unglued: int = 0
var _stair_peak_unglued: float = 0.0

var _ledge_grounded: bool = false
var _ledge_height: float = 0.0

var _subtick_speeds: Array[float] = []
var _subtick_entry_speeds: Array[float] = []
var _subtick_airborne: Array[bool] = []

## Per weapon: ticks from full run to a standing-still cone, pressing the
## opposite key or letting go, and how many ticks the opposite key can be held
## before the cone opens again.
var _counter_strafe: Dictionary = {}


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
		_test_creep_stops()
		_test_traces_a_tick()
		return false

	_phase_tick += 1
	match _phase:
		0: _phase_jump(false)
		1: _phase_jump(true)
		2: _phase_crouch_jump()
		3: _phase_surf()
		4: _phase_climb()
		5: _phase_stairs(true)
		6: _phase_stairs(false)
		7: _phase_ledge()
		8: _phase_subtick_jump()
		9: _phase_counter_strafe()
		_:
			_test_jump_height()
			_test_crouch_jump()
			_test_surf()
			_test_climb()
			_test_stay_on_ground()
			_test_quadrant_ground()
			_test_subtick_jump()
			_test_counter_strafe()
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


## Running down the eight-step flight, with and without StayOnGround.
##
## Source glues the player to the ground for a full step height after every
## walk move. Without that, a descent spends half its ticks airborne, and
## airborne means no ground friction and no ground acceleration, so you never
## reach run speed and the whole thing feels floaty. The stairs are the
## cheapest place to catch that; dust2 is full of the same shape.
func _phase_stairs(glued: bool) -> void:
	# Top of the eighth step. The flight is built from origin (-512, 0, -256)
	# with a 16 unit rise and a 32 unit run, heading in -z, so running toward
	# +z goes down it.
	var top := Vector3(-512.0, 132.0, -256.0 - 32.0 * 7.0)

	if _phase_tick == 1:
		_player.config.stay_on_ground = glued
		_place(top)
		return
	if _phase_tick <= SETTLE_TICKS:
		_step()
		return

	if _phase_tick <= SETTLE_TICKS + STAIR_TICKS:
		_step(Vector3(0.0, 0.0, 1.0))
		var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
		if glued:
			if not _player.on_ground:
				_stair_airborne += 1
			_stair_peak = maxf(_stair_peak, speed)
		else:
			if not _player.on_ground:
				_stair_airborne_unglued += 1
			_stair_peak_unglued = maxf(_stair_peak_unglued, speed)
		return

	_player.config.stay_on_ground = true
	_advance_phase()


## Standing with the hull centre out past the edge of the top step.
##
## Source retries the ground trace in four quadrants of the hull when the
## centre finds nothing, so a player half off a crate stays on the crate. With
## only the centre trace they drop off, which is the difference between holding
## an angle on a box and sliding off it.
func _phase_ledge() -> void:
	# The top step spans 32 units in z, centred on z = -256 - 32*7. Its +z
	# face is the lip. Sitting 12 units past it leaves the hull centre over
	# open air and the -z half of the hull still over the step.
	var lip_z := -256.0 - 32.0 * 7.0 + 16.0
	var perch := Vector3(-512.0, 130.0, lip_z + 12.0)

	if _phase_tick == 1:
		_place(perch)
		return
	if _phase_tick <= SETTLE_TICKS:
		_step()
		return
	if _phase_tick == SETTLE_TICKS + 1:
		_ledge_grounded = _player.on_ground
		_ledge_height = _player.global_position.y
		return
	_advance_phase()


## The same hop pressed at four different points inside a tick.
##
## A press at the tick boundary gets a free tick of no ground friction, because
## the jump happens before friction is applied. Pressing part-way through the
## tick should cost the friction of the part you were still on the ground for,
## which is what splitting the tick buys: the hop reflects when you actually
## pressed rather than rounding to 7.8 ms.
func _phase_subtick_jump() -> void:
	var slot := _subtick_speeds.size()
	if slot >= JUMP_PRESSES.size():
		_player.config.subtick_jump = true
		_advance_phase()
		return

	var press: Dictionary = JUMP_PRESSES[slot]
	var per_slot := SUBTICK_SETTLE_TICKS + 2
	var local := _phase_tick - slot * per_slot

	if local == 1:
		_place(Vector3(0.0, 8.0, 256.0))
		_player.config.subtick_jump = press["subtick"]
		return
	if local <= SUBTICK_SETTLE_TICKS:
		# Run up to full speed on flat ground first.
		_step(Vector3(0.0, 0.0, -1.0))
		return
	if local == SUBTICK_SETTLE_TICKS + 1:
		# Land into the hop carrying more than run speed, the way a chained
		# hop does, so friction is the only thing acting on it.
		_player.velocity.x = 0.0
		_player.velocity.z = -SUBTICK_HOP_SPEED
		_subtick_entry_speeds.append(
			Vector2(_player.velocity.x, _player.velocity.z).length()
		)
		_player.jump_fraction = press["fraction"]
		_step(Vector3(0.0, 0.0, -1.0), true)
		_subtick_speeds.append(
			Vector2(_player.velocity.x, _player.velocity.z).length()
		)
		_subtick_airborne.append(not _player.on_ground)
		return
	_step()


## Counter-strafing, through the real body and the real cone. Running flat
## out, the player presses the opposite key (or lets go of everything) and
## the weapon is asked for its cone after every tick, exactly as the
## controller asks it before a shot.
func _phase_counter_strafe() -> void:
	var saved_max_speed := _player.config.max_speed
	for data: WeaponData in [WeaponLibrary.ak47(), WeaponLibrary.m4a1s()]:
		var weapon := Weapon.new(data)
		var result := {
			"running": 0.0, "expected_running": data.inaccuracy_moving,
			"counter": -1, "release": -1, "window": -1,
		}

		_run_flat_out(data)
		result["running"] = _cone(weapon)
		result["counter"] = _ticks_until(weapon, Vector3(0.0, 0.0, 1.0), true)
		# Keep holding it: the player stops, then starts running the other
		# way, and the cone opens again. The ticks in between are the window
		# a counter-strafe gives.
		var reopened := _ticks_until(weapon, Vector3(0.0, 0.0, 1.0), false)
		if reopened >= 0:
			result["window"] = reopened

		_run_flat_out(data)
		result["release"] = _ticks_until(weapon, Vector3.ZERO, true)

		_counter_strafe[data.display_name] = result
	_player.config.max_speed = saved_max_speed
	_advance_phase()


## Placed on flat ground running at the weapon's top speed toward -Z.
func _run_flat_out(data: WeaponData) -> void:
	_player.config.max_speed = data.max_player_speed
	_place(Vector3(0.0, 8.0, 256.0))
	# Down onto the floor first: in the air there is no friction to stop
	# with, and the jump's cone is added on top.
	for i in SETTLE_TICKS:
		_step()
	_player.velocity = Vector3(0.0, 0.0, -data.max_player_speed)
	for i in 8:
		_step(Vector3(0.0, 0.0, -1.0))


func _cone(weapon: Weapon) -> float:
	return weapon.current_inaccuracy(Weapon.ShooterState.new(
		Vector2(_player.velocity.x, _player.velocity.z).length(),
		_player.on_ground, _player.is_ducked
	))


## Ticks with this intent until the cone is (or, with accurate false, stops
## being) the standing one. -1 if it never happens within a second.
func _ticks_until(weapon: Weapon, wish_dir: Vector3, accurate: bool) -> int:
	var standing := weapon.data.inaccuracy_standing
	for tick in range(1, 129):
		_step(wish_dir)
		var at_standing := absf(_cone(weapon) - standing) < 1e-6
		if at_standing == accurate:
			return tick
	return -1


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
	print("stairs: %d/%d ticks airborne at %.1f u/s glued, %d/%d at %.1f u/s unglued" % [
		_stair_airborne, STAIR_TICKS, _stair_peak,
		_stair_airborne_unglued, STAIR_TICKS, _stair_peak_unglued
	])
	var hops := PackedStringArray()
	for i in _subtick_speeds.size():
		hops.append("%.2f: %.2f" % [JUMP_PRESSES[i]["fraction"], _subtick_speeds[i]])
	print("hop speed by press fraction, from %.1f u/s: %s" % [
		SUBTICK_HOP_SPEED, ", ".join(hops)
	])
	for weapon_name: String in _counter_strafe:
		var r: Dictionary = _counter_strafe[weapon_name]
		print("counter-strafe %s: running cone %.2f deg, standing cone after %.1f ms (letting go %.1f ms), for %.1f ms before the other way opens it" % [
			weapon_name, r["running"], r["counter"] * DT * 1000.0,
			r["release"] * DT * 1000.0, r["window"] * DT * 1000.0,
		])
	if _failures == 0:
		print("%d checks passed." % _checks)
		quit(0)
	else:
		printerr("%d of %d checks failed." % [_failures, _checks])
		quit(1)


func _test_stay_on_ground() -> void:
	_check(
		_stair_airborne == 0,
		"running down the stairs never leaves the ground (%d of %d ticks airborne)"
			% [_stair_airborne, STAIR_TICKS]
	)
	_check(
		_stair_peak > _player.config.max_speed - 1.0,
		"running down the stairs reaches full run speed (%.2f of %.2f u/s)"
			% [_stair_peak, _player.config.max_speed]
	)
	# The other half of the claim: without StayOnGround the same descent is
	# airborne for a large part of it and never gets up to speed. If this ever
	# stops being true, the fix above has stopped doing anything.
	_check(
		_stair_airborne_unglued > STAIR_TICKS / 4,
		"without StayOnGround the same descent goes airborne (%d of %d ticks)"
			% [_stair_airborne_unglued, STAIR_TICKS]
	)
	_check(
		_stair_peak_unglued < _stair_peak - 5.0,
		"without StayOnGround the descent is slower (%.2f vs %.2f u/s)"
			% [_stair_peak_unglued, _stair_peak]
	)


func _test_quadrant_ground() -> void:
	_check(
		_ledge_grounded,
		"standing with the hull centre past a step edge stays grounded"
	)
	_check(
		_ledge_height > 100.0,
		"and stays up on the step rather than falling off it (y %.1f)"
			% _ledge_height
	)


## Moving costs accuracy, and pressing the opposite key is the fast way to
## get it back, as in CS: friction and the opposite key's acceleration
## together bring a rifle under a third of its top speed, where the cone is
## the standing one, in well under half the time friction alone takes.
func _test_counter_strafe() -> void:
	for weapon_name: String in ["AK-47", "M4A1-S"]:
		if not _counter_strafe.has(weapon_name):
			_check(false, "counter-strafe phase ran for the %s" % weapon_name)
			continue
		var r: Dictionary = _counter_strafe[weapon_name]
		var ms := func(ticks: int) -> float: return ticks * DT * 1000.0
		_check(
			absf(r["running"] - r["expected_running"]) < 1e-4,
			"the %s at a full run on the ground has the sheet's running cone (%.2f deg)"
				% [weapon_name, r["running"]]
		)
		_check(
			r["counter"] > 0 and r["counter"] <= 11,
			"a counter-strafe gives the %s its standing cone within 86 ms (%.1f ms)"
				% [weapon_name, ms.call(r["counter"])]
		)
		_check(
			r["release"] > 0 and r["release"] >= 2 * r["counter"],
			"letting go instead takes over twice as long (%.1f ms against %.1f ms)"
				% [ms.call(r["release"]), ms.call(r["counter"])]
		)
		_check(
			r["window"] > 8,
			"held too long, the opposite key runs the %s the other way, but only after %.1f ms of standing accuracy"
				% [weapon_name, ms.call(r["window"])]
		)


func _test_subtick_jump() -> void:
	if _subtick_speeds.size() != JUMP_PRESSES.size():
		_check(false, "sub-tick jump phase ran for every press")
		return

	for i in JUMP_PRESSES.size():
		_check(
			_subtick_airborne[i],
			"a jump pressed at fraction %.2f leaves the ground"
				% JUMP_PRESSES[i]["fraction"]
		)

	# All five hops start from the same run-up, so any difference in the speed
	# they leave with is the timing and nothing else.
	for i in range(1, JUMP_PRESSES.size()):
		_check_near(
			_subtick_entry_speeds[i], _subtick_entry_speeds[0],
			"every hop starts from the same speed"
		)

	# Taking the jump at the tick boundary skips that tick's ground friction
	# entirely, because the jump happens before friction is applied. Above run
	# speed there is no ground acceleration left to earn back, so pressing
	# later in the tick costs friction for the part of the tick you were still
	# on the ground: the hop reflects when you actually pressed instead of
	# being rounded up to 7.8 ms earlier and handed speed you did not keep.
	var boundary: float = _subtick_speeds[0]
	for i in range(1, 4):
		_check(
			_subtick_speeds[i] < boundary,
			"a jump pressed at fraction %.2f keeps less speed than one rounded to the tick boundary (%.3f vs %.3f u/s)"
				% [JUMP_PRESSES[i]["fraction"], _subtick_speeds[i], boundary]
		)
	for i in range(2, 4):
		_check(
			_subtick_speeds[i] < _subtick_speeds[i - 1],
			"pressing later in the tick costs more friction (%.2f: %.3f, %.2f: %.3f u/s)"
				% [
					JUMP_PRESSES[i - 1]["fraction"], _subtick_speeds[i - 1],
					JUMP_PRESSES[i]["fraction"], _subtick_speeds[i]
				]
		)

	# And with sub-tick timing off, the same mid-tick press is rounded to the
	# boundary, which is the behaviour the flag exists to turn back on.
	_check_near(
		_subtick_speeds[4], boundary,
		"with subtick_jump off, a mid-tick press lands on the tick boundary"
	)


# --- Solver tests ---------------------------------------------------------

func _run_solver_tests() -> void:
	_test_friction()
	_test_ground_acceleration()
	_test_air_acceleration()
	_test_clip_velocity()
	_test_walkable()
	_test_deadstrafe()
	_test_bunnyhop_clamp()
	_test_check_velocity()
	_test_simple_spline()


## Source clamps each axis to sv_maxvelocity separately rather than clamping
## the magnitude, which is not the same thing: it changes the direction of an
## over-speed vector. At surf speeds that is what decides the exit angle.
func _test_check_velocity() -> void:
	var cfg := MovementConfig.new()

	var under := Vector3(100.0, -200.0, 300.0)
	_check(
		MovementSolver.check_velocity(under, cfg) == under,
		"check_velocity leaves ordinary speeds alone"
	)

	var over := MovementSolver.check_velocity(
		Vector3(5000.0, -9000.0, 100.0), cfg
	)
	_check_near(over.x, 3500.0, "check_velocity clamps a fast axis to sv_maxvelocity")
	_check_near(over.y, -3500.0, "check_velocity clamps a negative axis too")
	_check_near(over.z, 100.0, "check_velocity leaves a slow axis on the same vector alone")


## The ducked eye offset runs through Source's SimpleSpline, which is
## smoothstep, so the view eases rather than sliding.
func _test_simple_spline() -> void:
	_check_near(MovementSolver.simple_spline(0.0), 0.0, "spline starts at 0")
	_check_near(MovementSolver.simple_spline(1.0), 1.0, "spline ends at 1")
	_check_near(MovementSolver.simple_spline(0.5), 0.5, "spline is symmetric about the middle")
	_check(
		MovementSolver.simple_spline(0.25) < 0.25,
		"spline eases in (%.4f at a quarter)" % MovementSolver.simple_spline(0.25)
	)
	_check(
		MovementSolver.simple_spline(0.75) > 0.75,
		"spline eases out (%.4f at three quarters)" % MovementSolver.simple_spline(0.75)
	)


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

	cfg.source_deadstrafe = false
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


## What a tick costs, in traces of the hull, which are tens of microseconds
## each on dust2 and most of a tick. Standing still, one: the ground check
## at the end of the move (Source's WalkMove moves nobody slower than a unit
## a second, and the check at the start is the last one's while nothing has
## moved the body, sv_optimizedmovement). Running in the open, four: the
## move, StayOnGround's two, the check. A third and a fourth running tick
## are counted, the first ones having started from where the body was put.
func _test_traces_a_tick() -> void:
	_place(Vector3(0.0, 8.0, 256.0))
	for i in SETTLE_TICKS:
		_step()
	var before := _player.traces
	_step()
	var standing := _player.traces - before
	var forward := Vector3(0.0, 0.0, -1.0)
	for i in 2:
		_step(forward)
	before = _player.traces
	_step(forward)
	_step(forward)
	var running := _player.traces - before
	_check(
		standing == 1 and running == 8 and _player.on_ground,
		"a tick traces the hull once standing still and four times running in the open (%d, then %d in two)" % [standing, running]
	)
	_place(Vector3(0.0, 8.0, 256.0))


## Source's WalkMove stops a player slower than a unit a second dead, where
## they stand. Friction takes 4 u/s to 0.75, which stops; 6 u/s to 2.75,
## which still moves, so the stop is what makes the difference.
func _test_creep_stops() -> void:
	var start := _player.global_position
	_player.velocity = Vector3(4.0, 0.0, 0.0)
	_step()
	var crept := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	_check(
		_player.velocity == Vector3.ZERO and crept == 0.0,
		"a player left under a unit a second by friction stops dead (%.2f u/s, moved %.4f)"
			% [_player.velocity.length(), crept]
	)
	start = _player.global_position
	_player.velocity = Vector3(6.0, 0.0, 0.0)
	_step()
	var moved := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	_check(
		is_equal_approx(_player.velocity.x, 2.75) and is_equal_approx(moved, 2.75 * DT),
		"and one left at 2.75 u/s moves on (%.2f u/s, moved %.4f)" % [_player.velocity.length(), moved]
	)
	_player.velocity = Vector3.ZERO


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
