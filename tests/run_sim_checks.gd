extends SceneTree

## Checks the split between the simulation and everything around it: that
## the simulation reads nothing but commands, that keys become commands at
## the right instants, that the same commands give the same game however
## fast they are run, and that a bot plays through the same commands as you.
##
##   godot --headless --path . --script tests/run_sim_checks.gd
##
## Needs nothing extracted: bots without their model wear the standard boxes.

const DT := 1.0 / 128.0
const TICK := 7812
const HALF_TICK := 3906
const QUARTER_TICK := 1953

## The files that make up the simulation. None of them may read the keys or
## the wall clock.
const SIMULATION_FILES := [
	"res://src/sim/user_cmd.gd",
	"res://src/sim/sim_clock.gd",
	"res://src/player/player_sim.gd",
	"res://src/bots/bot.gd",
	"res://src/movement/player_body.gd",
	"res://src/movement/movement_solver.gd",
	"res://src/weapons/weapon.gd",
	"res://src/weapons/recoil_state.gd",
	"res://src/combat/hit_target.gd",
	"res://src/combat/hitscan.gd",
]

var _failures: int = 0
var _checks: int = 0
var _world: Node3D


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_the_simulation_reads_only_commands()
	_test_presses_land_at_their_instant()

	_world = Node3D.new()
	root.add_child(_world)
	_build_floor()
	await physics_frame
	await physics_frame

	await _test_the_same_commands_give_the_same_game()
	await _test_a_held_trigger_fires_on_simulation_time()
	await _test_a_press_fires_from_where_the_player_was()
	await _test_a_running_tap_misses()
	await _test_a_bot_plays_through_commands()
	_report()


# --- No keys, no wall clock -------------------------------------------------

func _test_the_simulation_reads_only_commands() -> void:
	var keys := RegEx.create_from_string("(?<![A-Za-z_])Input\\.")
	var clock := RegEx.create_from_string("Time\\.get_ticks|Time\\.get_unix")
	for path: String in SIMULATION_FILES:
		var code := ""
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var trimmed := line.strip_edges()
			if trimmed.begins_with("#"):
				continue
			code += line + "\n"
		_check(not code.is_empty(), "%s is there to read" % path.get_file())
		_check(keys.search(code) == null, "%s never reads the keys" % path.get_file())
		_check(clock.search(code) == null, "%s never reads the wall clock" % path.get_file())


## A press is placed at its share of the stretch since the last command was
## sampled: the stretch the tick that runs it stands for.
func _test_presses_land_at_their_instant() -> void:
	var input := PlayerInput.new()
	var start := 5_000_000
	input.build_command(1, start)
	input._pending.append(PlayerInput.ButtonEvent.new(&"attack", true, start + HALF_TICK, 12.0, -3.0))
	input._pending.append(PlayerInput.ButtonEvent.new(&"attack", false, start + HALF_TICK + QUARTER_TICK, 12.5, -3.0))
	input._pending.append(PlayerInput.ButtonEvent.new(&"jump", true, start + QUARTER_TICK, 11.0, -3.0))
	var cmd := input.build_command(2, start + TICK)

	_check(cmd.tick == 2 and cmd.steps.size() == 3, "every press and release is in the command (%d)" % cmd.steps.size())
	if cmd.steps.size() != 3:
		return
	var shot := cmd.steps[0]
	_check(
		shot.button == UserCmd.ATTACK and shot.pressed and absf(shot.when - 0.5) < 0.001
			and is_equal_approx(shot.yaw_degrees, 12.0),
		"a click half way between two samples fires half way through the tick, where the mouse was then (%.3f)" % shot.when
	)
	_check(
		absf(cmd.steps[1].when - 0.75) < 0.001 and not cmd.steps[1].pressed,
		"and its release is placed too (%.3f)" % cmd.steps[1].when
	)
	var jump := cmd.first_press(UserCmd.JUMP)
	_check(
		jump != null and absf(jump.when - 0.25) < 0.001,
		"a jump a quarter of the way through jumps a quarter of the way through (%.3f)" % (jump.when if jump else -1.0)
	)
	_check(
		cmd.pressed_during(UserCmd.ATTACK) and not cmd.held(UserCmd.ATTACK),
		"a click shorter than a tick still fires, though the button is up by the tick's end"
	)

	# The old way measured from when the tick began, after the events, and
	# put every press at 0.
	var stale := PlayerInput.tick_fraction(start + HALF_TICK, start + TICK + 100, TICK)
	_check(is_zero_approx(stale), "measured from the tick's own start, the same click would have been at 0")


# --- Same commands, same game -----------------------------------------------

## A script of commands: run up, strafe, a sub-tick jump, a spray with taps
## in it, a reload.
func _script(ticks: int) -> Array[UserCmd]:
	var cmds: Array[UserCmd] = []
	for i in ticks:
		var cmd := UserCmd.new()
		cmd.tick = 10_000 + i
		cmd.yaw_degrees = 30.0 + 0.1 * i
		cmd.pitch_degrees = -2.0
		cmd.move = Vector2(0.0, 1.0) if i < 60 else Vector2(1.0 if floori(i / 20.0) % 2 == 0 else -1.0, 0.0)
		if i == 70:
			cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.JUMP, true, 0.37, cmd.yaw_degrees, -2.0))
		if i >= 120 and i < 200:
			cmd.buttons |= UserCmd.ATTACK
		if i == 230 or i == 260:
			cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, true, 0.6, cmd.yaw_degrees, -2.5))
		if i == 300:
			cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.RELOAD, true, 0.1, cmd.yaw_degrees, -2.0))
		cmds.append(cmd)
	return cmds


func _test_the_same_commands_give_the_same_game() -> void:
	var cmds := _script(360)
	var first := await _play(cmds, Vector3(-512.0, 0.0, 0.0), false)
	var second := await _play(cmds, Vector3(-512.0, 0.0, 0.0), true)

	# 80 ticks held is 625 ms: rounds at 0, 100 ... 600 ms, then two taps.
	_check(first["shots"].size() == 9, "the script fires a seven-round spray and two taps (%d rounds)" % first["shots"].size())
	_check(
		(first["end"] as Vector3).is_equal_approx(second["end"]) and (first["velocity"] as Vector3).is_equal_approx(second["velocity"]),
		"run all in one frame or one tick a frame, the same commands end in the same place at the same speed (%s, %s)"
			% [first["end"], second["end"]]
	)
	_check(first["peak"] > 40.0, "the jump in the script left the ground (%.1f units)" % first["peak"])
	var same: bool = first["shots"].size() == second["shots"].size()
	if same:
		for i in first["shots"].size():
			var a: Dictionary = first["shots"][i]
			var b: Dictionary = second["shots"][i]
			same = same and a["time"] == b["time"] and (a["direction"] as Vector3).is_equal_approx(b["direction"]) \
				and (a["origin"] as Vector3).is_equal_approx(b["origin"])
	_check(same, "and every round goes at the same instant, from the same place, the same way")
	_check(
		first["ammo"] == second["ammo"] and first["reserve"] == second["reserve"],
		"with the same rounds left (%d / %d)" % [first["ammo"], first["reserve"]]
	)


## Plays the commands on a fresh player standing at `at`, either all inside
## one frame or one per physics frame, and says where it ended and what it
## fired.
func _play(cmds: Array[UserCmd], at: Vector3, one_per_frame: bool) -> Dictionary:
	var player := _new_player(at, "T")
	player.equip(WeaponLibrary.ak47())
	await physics_frame
	var shots: Array[Dictionary] = []
	player.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void:
		shots.append({
			"time": shot.timestamp_usec,
			"direction": shot.direction,
			"origin": shot.origin - at,
		}))
	var floor_y := player.global_position.y
	var peak := 0.0
	for cmd in cmds:
		player.run_command(cmd, DT)
		peak = maxf(peak, player.global_position.y - floor_y)
		if one_per_frame:
			await physics_frame
	var result := {
		"end": player.global_position - at, "velocity": player.velocity, "shots": shots,
		"peak": peak, "ammo": player.weapon.ammo, "reserve": player.weapon.reserve,
	}
	player.queue_free()
	await physics_frame
	return result


func _test_a_held_trigger_fires_on_simulation_time() -> void:
	var player := _new_player(Vector3(0.0, 0.0, 512.0), "T")
	player.equip(WeaponLibrary.ak47())
	await physics_frame
	var times: Array[int] = []
	player.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void:
		times.append(shot.timestamp_usec))
	for i in 128:
		var cmd := UserCmd.new()
		cmd.tick = 50_000 + i
		cmd.buttons = UserCmd.ATTACK
		player.run_command(cmd, DT)

	var even := times.size() >= 10
	for i in range(1, times.size()):
		even = even and times[i] - times[i - 1] == 100_000
	_check(
		even,
		"a second of ticks, run in no time at all, fires the AK every 100 ms of simulation time (%d rounds)" % times.size()
	)
	player.queue_free()
	await physics_frame


## A click mid-tick while strafing fires from half way between where the
## tick started and ended, not from its end.
func _test_a_press_fires_from_where_the_player_was() -> void:
	var player := _new_player(Vector3(0.0, 0.0, -512.0), "T")
	player.equip(WeaponLibrary.ak47())
	await physics_frame
	for i in 40:
		var run := UserCmd.new()
		run.tick = 60_000 + i
		run.move = Vector2(1.0, 0.0)
		player.run_command(run, DT)
	var origins: Array[Vector3] = []
	player.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void:
		origins.append(shot.origin))
	var cmd := UserCmd.new()
	cmd.tick = 60_040
	cmd.move = Vector2(1.0, 0.0)
	cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, true, 0.5, 0.0, 0.0))
	player.run_command(cmd, DT)

	var halfway := player.previous_position.lerp(player.global_position, 0.5) + Vector3.UP * player.eye_height()
	_check(
		origins.size() == 1 and origins[0].is_equal_approx(halfway)
			and player.previous_position.distance_to(player.global_position) > 1.0,
		"a click half way through a strafing tick fires from half way along it"
	)
	player.queue_free()
	await physics_frame


## Taps at a run, through the real body: every one is fired into the
## running cone, and they land all over it rather than on one spot. Sid,
## 2026-09-22: the first shot while running was still perfectly accurate.
func _test_a_running_tap_misses() -> void:
	var player := _new_player(Vector3(512.0, 0.0, 0.0), "T")
	player.equip(WeaponLibrary.ak47())
	await physics_frame
	var shots: Array[Weapon.Shot] = []
	player.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void:
		shots.append(shot))
	# Run flat out, then tap once every 1.5 s at a different point of the
	# tick, still running, so each round is the first of its own spray.
	for i in 128 + 12 * 192:
		var cmd := UserCmd.new()
		cmd.tick = 70_000 + i
		cmd.move = Vector2(0.0, 1.0)
		if i >= 128 and (i - 128) % 192 == 0:
			cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, true, fmod(0.13 * i, 1.0), 0.0, 0.0))
		player.run_command(cmd, DT)

	var running_cone := WeaponLibrary.ak47().inaccuracy_moving
	var offsets: Array[float] = []
	var at_a_run := shots.size() == 12
	for shot in shots:
		at_a_run = at_a_run and shot.shot_index == 0 and shot.inaccuracy >= running_cone - 0.01
		offsets.append(rad_to_deg(PlayerInput.aim_direction(shot.base_yaw, shot.base_pitch).angle_to(shot.direction)))
	offsets.sort()
	_check(at_a_run, "twelve taps at a run are each a first round, fired into the %.1f degree running cone" % running_cone)
	_check(
		not offsets.is_empty() and offsets[-1] > running_cone * 0.5 and offsets[-1] - offsets[0] > running_cone * 0.3,
		"and they land all over it, not on one spot (%.2f to %.2f degrees off the aim)"
			% [offsets[0] if not offsets.is_empty() else 0.0, offsets[-1] if not offsets.is_empty() else 0.0]
	)
	player.queue_free()
	await physics_frame


# --- Bots -------------------------------------------------------------------

## A bot turns on a player of the other side and fires, through commands and
## the same weapon path; one of its own side it leaves alone.
func _test_a_bot_plays_through_commands() -> void:
	var enemy := _new_player(Vector3(0.0, 0.0, -1200.0), "T")
	var friend := _new_player(Vector3(-300.0, 0.0, -1400.0), "CT")
	var bot := (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	bot.team = "CT"
	bot.weapon_data = WeaponLibrary.ak47()
	bot.position = Vector3(0.0, 0.0, -1600.0)
	bot.yaw_degrees = 180.0
	_world.add_child(bot)
	var times: Array[int] = []
	bot.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void:
		times.append(shot.timestamp_usec))

	_check(bot.weapon != null and bot.hit_target.hitboxes().size() > 0, "a bot without its model still has its weapon and the standard boxes")
	for i in 256:
		await physics_frame
		if not enemy.alive:
			break

	_check(bot.rounds_fired > 0 and bot.target == enemy, "the bot turns on the enemy and fires (%d rounds)" % bot.rounds_fired)
	_check(
		enemy.hit_target.health < 100.0 or not enemy.alive,
		"and its rounds land through the same hitscan as yours (health %.0f)" % enemy.hit_target.health
	)
	_check(friend.hit_target.health == 100.0, "its own side it leaves alone")
	var cadence := times.size() >= 2
	for i in range(1, times.size()):
		var gap := times[i] - times[i - 1]
		cadence = cadence and (gap == 100_000 or gap > 150_000)
	_check(cadence, "inside a burst its rounds go exactly a cycle apart, as a held trigger's do")
	bot.queue_free()
	enemy.queue_free()
	friend.queue_free()
	await physics_frame


# --- The world --------------------------------------------------------------

func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8192.0, 32.0, 8192.0)
	shape.shape = box
	shape.position = Vector3(0.0, -16.0, 0.0)
	floor_body.add_child(shape)
	_world.add_child(floor_body)


## A player in the simulation with nothing drawing it, standing on the floor.
func _new_player(at: Vector3, team: String) -> PlayerSim:
	var player := PlayerSim.new()
	player.team = team
	player.collision_layer = 2
	var hull := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(32.0, 72.0, 32.0)
	hull.shape = box
	hull.position = Vector3(0.0, 36.0, 0.0)
	player.add_child(hull)
	player.position = at
	_world.add_child(player)
	player.place(at, 0.0)
	# Down onto the floor.
	for i in 4:
		var settle := UserCmd.new()
		settle.tick = 1 + i
		player.run_command(settle, DT)
	return player


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % description)
	else:
		_failures += 1
		print("  FAIL %s" % description)


func _report() -> void:
	if _failures == 0:
		print("%d simulation checks passed." % _checks)
		quit(0)
	else:
		print("%d of %d simulation checks failed." % [_failures, _checks])
		quit(1)
