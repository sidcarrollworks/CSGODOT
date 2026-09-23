extends SceneTree

## Checks the split between the simulation and everything around it: that
## the simulation reads nothing but commands, that keys become commands at
## the right instants, that the same commands give the same game however
## fast they are run, that a bot plays through the same commands as you,
## and that being hit slows a player and throws their aim.
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
	await _test_a_bot_finds_its_way()
	await _test_a_player_wears_hitboxes()
	await _test_a_hit_tags_the_player()
	await _test_a_hit_throws_the_aim()
	_test_the_hit_direction_on_screen()
	await _test_the_hud_shows_hits()
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


## Where the nav mesh course is, out of the way of everything else.
const COURSE := Vector3(-3500.0, 0.0, 3500.0)


## A bot sent round a corner, up a ledge and under a low ceiling, over a nav
## mesh built for the course, and back: it walks the path pulled taut, not
## the straight line through the wall, stays on the mesh, jumps the ledge,
## crouches under the ceiling, and comes back down and round.
func _test_a_bot_finds_its_way() -> void:
	# A block inside the corner, the ledge 40 up, and a ceiling 60 over the
	# ledge's far end. The mesh stops 16 short of every wall, as the game's
	# does, eroded by the hull's radius.
	_box(Vector3(116.0, 0.0, -784.0), Vector3(1600.0, 200.0, 200.0))
	_box(Vector3(900.0, 0.0, -1100.0), Vector3(1600.0, 40.0, -785.0))
	_box(Vector3(1220.0, 100.0, -1100.0), Vector3(1600.0, 140.0, -785.0))
	var mesh := _course_mesh()
	var start := COURSE + Vector3(0.0, 0.0, -50.0)
	var goal := COURSE + Vector3(1400.0, 40.0, -900.0)

	var path := mesh.walk_path(start, goal)
	var expected := [
		start, COURSE + Vector3(90.0, 0.0, -800.0), COURSE + Vector3(100.0, 0.0, -810.0),
		COURSE + Vector3(884.0, 0.0, -900.0), COURSE + Vector3(912.0, 40.0, -900.0), goal,
	]
	var as_expected := path.points.size() == expected.size()
	for i in mini(path.points.size(), expected.size()):
		as_expected = as_expected and path.points[i].is_equal_approx(expected[i])
	_check(
		as_expected and path.jumps == PackedByteArray([0, 0, 0, 1, 0, 0]),
		"pulled taut, the way turns only at the corner, kept 10 units in from each end of the edges there, and jumps once, at the ledge (%s, %s)"
			% [path.points, path.jumps]
	)

	var bot := (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	bot.team = "CT"
	bot.route = PackedVector3Array([start, goal])
	bot.nav_mesh = mesh
	bot.position = start
	_world.add_child(bot)
	bot.place(start, 0.0)
	bot.set("_next", 1)
	var arrived := []
	var off_mesh := 0
	var highest := -INF
	var ducked_under := 0
	var standing_under := 0
	var jumps := 0
	var was_on_ground := true
	for i in 128 * 40:
		var heading: int = bot.get("_next")
		await physics_frame
		if bot.get("_next") != heading:
			arrived.append(bot.global_position)
		var at := bot.global_position - COURSE
		if mesh.nearest_area(bot.global_position, 16.0) == null:
			off_mesh += 1
		highest = maxf(highest, at.y)
		if at.x > 1240.0 and at.y > 35.0:
			if bot.is_ducked:
				ducked_under += 1
			else:
				standing_under += 1
		# Off the ground going up; walking off the ledge on the way back is
		# a drop.
		if was_on_ground and not bot.on_ground and bot.velocity.y > 100.0:
			jumps += 1
		was_on_ground = bot.on_ground
		if arrived.size() >= 2:
			break

	_check(
		arrived.size() >= 1 and (arrived[0] as Vector3).distance_to(goal) < 32.0,
		"the bot gets to the far end of the course, over the ledge and under the ceiling (%s)" % [arrived]
	)
	_check(
		arrived.size() >= 2 and (arrived[1] as Vector3).distance_to(start) < 32.0,
		"and comes back down and round to where it started (%s)" % [arrived]
	)
	_check(off_mesh == 0, "never leaving the mesh by more than the hull's radius (%d ticks off it)" % off_mesh)
	_check(
		highest > 40.0 and jumps == 1,
		"it jumps up the ledge, once (%d jumps, its feet %.0f up at the highest)" % [jumps, highest]
	)
	_check(
		ducked_under > 0 and standing_under == 0,
		"and crouches under the low ceiling before it gets there (%d ticks crouched under it, %d standing)"
			% [ducked_under, standing_under]
	)
	bot.queue_free()
	await physics_frame


## The course's floor as a nav mesh: a corridor going -Z, a corner, one
## going +X to the foot of the ledge, the ledge's top, and its far end under
## the ceiling, marked for crouching. Each area's corners run round it, and
## edge i goes from corner i to corner i + 1.
func _course_mesh() -> SourceNavMesh:
	var squares := [
		[-100.0, 100.0, 0.0, -800.0, 0.0, 0],
		[-100.0, 100.0, -800.0, -1000.0, 0.0, 0],
		[100.0, 884.0, -800.0, -1000.0, 0.0, 0],
		[900.0, 1200.0, -800.0, -1000.0, 40.0, 0],
		[1200.0, 1500.0, -800.0, -1000.0, 40.0, SourceNavMesh.FLAG_CROUCH],
	]
	# [area, edge, the area across, its edge]; edges 0 to 3 are the near z,
	# the far x, the far z and the near x sides.
	var links := [
		[1, 2, 2, 0], [2, 0, 1, 2], [2, 1, 3, 3], [3, 3, 2, 1],
		[3, 1, 4, 3], [4, 3, 3, 1], [4, 1, 5, 3], [5, 3, 4, 1],
	]
	var list: Array[SourceNavMesh.Area] = []
	for i in squares.size():
		var square: Array = squares[i]
		var area := SourceNavMesh.Area.new()
		area.id = i + 1
		area.flags = square[5]
		area.corners = PackedVector3Array([
			COURSE + Vector3(square[0], square[4], square[2]), COURSE + Vector3(square[1], square[4], square[2]),
			COURSE + Vector3(square[1], square[4], square[3]), COURSE + Vector3(square[0], square[4], square[3]),
		])
		area.edges = [[], [], [], []]
		list.append(area)
	for entry: Array in links:
		var link := SourceNavMesh.Link.new()
		link.area = entry[2]
		link.edge = entry[3]
		(list[entry[0] - 1].edges[entry[1]] as Array).append(link)
	return SourceNavMesh.from_areas(list)


## A solid box of the world between two corners, relative to the course.
func _box(low: Vector3, high: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (high - low).abs()
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	body.global_position = COURSE + (low + high) * 0.5


# --- Being shot -------------------------------------------------------------

## Without the character extracted, a player wears the four standard boxes
## and says so; with it (tests/run_model_checks.gd), the game's capsules.
func _test_a_player_wears_hitboxes() -> void:
	var player := _new_player(Vector3(1024.0, 0.0, 1024.0), "T")
	await physics_frame
	var extracted := player.model != null
	_check(
		player.hit_target.hitboxes().size() == (19 if extracted else 4)
			and player.hitbox_source().begins_with("19 CS2 capsules" if extracted else "4 stand-in boxes")
			and not player.hitboxes_missing(),
		"a player wears %s, and says which (%s)" % [
			"the game's capsules" if extracted else "the stand-in boxes", player.hitbox_source(),
		]
	)
	player.queue_free()
	await physics_frame


## One round of `data` into the chest of `victim`, fired from `from_side`
## units to its right, square on. Returns what it hit.
func _hit(victim: PlayerSim, data: WeaponData, from_side: float = 300.0) -> Hitscan.Result:
	var shot := Weapon.Shot.new()
	shot.origin = victim.global_position + Vector3(from_side, 50.0, 0.0)
	shot.direction = Vector3.LEFT
	return Hitscan.fire_at(victim.get_world_3d().direct_space_state, shot, data)


## A player running forward (-Z) for `ticks` ticks from `tick`.
func _run_forward(player: PlayerSim, tick: int, ticks: int) -> int:
	for i in ticks:
		var cmd := UserCmd.new()
		cmd.tick = tick + i
		cmd.move = Vector2(0.0, 1.0)
		player.run_command(cmd, DT)
	return tick + ticks


## Running flat out, a hit from an AK-47 leaves the player 40% of their
## speed (its 60% tagging power, from the game's weapons.vdata), two CS2
## ticks after it landed, and it comes back over 1.5 s. A second hit takes it
## back to 40%, not lower. An SMG's round (100%) stops them.
func _test_a_hit_tags_the_player() -> void:
	var player := _new_player(Vector3(2048.0, 0.0, 0.0), "T")
	player.equip(WeaponLibrary.ak47())
	var tick := _run_forward(player, 80_000, 128)
	var top := Vector2(player.velocity.x, player.velocity.z).length()
	await physics_frame
	await physics_frame
	var heard: Array[Vector3] = []
	player.hurt.connect(func(_amount: float, _zone: StringName, from: Vector3) -> void: heard.append(from))
	var ak := WeaponLibrary.ak47()
	var result := _hit(player, ak)
	_check(
		result.hitbox != null and result.hitbox.target == player.hit_target and player.hit_target.health < 100.0,
		"a round from the side lands in the running player (%s, health %.0f)" % [result.zone, player.hit_target.health]
	)
	_check(
		heard.size() == 1 and heard[0].is_equal_approx(player.global_position + Vector3(300.0, 50.0, 0.0)),
		"and the player hears where it was fired from"
	)
	tick = _run_forward(player, tick, 3)
	var before := player.velocity_modifier
	tick = _run_forward(player, tick, 1)
	_check(
		is_equal_approx(before, 1.0) and is_equal_approx(player.velocity_modifier, 1.0 - ak.tagging_power),
		"the tag lands two CS2 ticks (four of ours) after the hit: %.2f, then %.2f of full speed" % [before, player.velocity_modifier]
	)
	tick = _run_forward(player, tick, 32)
	var slowed := Vector2(player.velocity.x, player.velocity.z).length()
	_check(
		top > 210.0 and slowed < top * 0.6,
		"a quarter of a second on, running flat out has slowed from %.0f to %.0f u/s" % [top, slowed]
	)
	tick = _run_forward(player, tick, 64)
	var second_hit_from := player.velocity_modifier
	await physics_frame
	await physics_frame
	_hit(player, ak)
	tick = _run_forward(player, tick, 4)
	_check(
		second_hit_from > 0.55 and is_equal_approx(player.velocity_modifier, 1.0 - ak.tagging_power),
		"a second hit takes it back to %.2f from %.2f, no lower" % [player.velocity_modifier, second_hit_from]
	)
	var back_at := -1
	for i in 256:
		tick = _run_forward(player, tick, 1)
		if player.velocity_modifier >= 1.0:
			back_at = i + 1
			break
	_check(
		absi(back_at - 192) <= 1,
		"and it is all back 1.5 s later (%d ticks)" % back_at
	)
	var smg := WeaponLibrary.ak47()
	smg.tagging_power = 1.0
	await physics_frame
	await physics_frame
	_hit(player, smg)
	tick = _run_forward(player, tick, 4)
	_check(is_zero_approx(player.velocity_modifier), "a round tagging at 100%, as an SMG's does, stops the player")
	player.queue_free()
	await physics_frame


## Unarmoured, a hit throws the aim about 2 degrees up and it is back
## within a third of a second; armour that takes a share keeps it to about
## half a degree. A round fired while it is thrown goes where it points.
func _test_a_hit_throws_the_aim() -> void:
	var player := _new_player(Vector3(-2048.0, 0.0, 0.0), "T")
	player.equip(WeaponLibrary.ak47())
	await physics_frame
	await physics_frame
	var peaks := {}
	var settled := {}
	var tick := 90_000
	for armored in [false, true]:
		player.hit_target.wear(100.0 if armored else 0.0, armored)
		player.hit_target.reset()
		_hit(player, WeaponLibrary.ak47())
		var peak := Vector2.ZERO
		for i in 48:
			var cmd := UserCmd.new()
			cmd.tick = tick
			tick += 1
			player.run_command(cmd, DT)
			if player.hit_punch.value.y > peak.y:
				peak = player.hit_punch.value
		peaks[armored] = peak
		settled[armored] = player.hit_punch.value.length()
		for i in 64:
			var cmd := UserCmd.new()
			cmd.tick = tick
			tick += 1
			player.run_command(cmd, DT)
	_check(
		peaks[false].y > 1.5 and peaks[false].y < 2.5 and absf(peaks[false].x) > 0.1 and settled[false] < 0.05,
		"unarmoured, a chest hit throws the aim %.2f degrees up and %.2f aside, and 0.375 s on it is back to within %.3f" % [peaks[false].y, peaks[false].x, settled[false]]
	)
	_check(
		peaks[true].y > 0.2 and peaks[true].y < 0.8,
		"with kevlar, %.2f degrees" % peaks[true].y
	)

	player.hit_target.wear(0.0, false)
	player.hit_target.reset()
	_hit(player, WeaponLibrary.ak47())
	for i in 12:
		var cmd := UserCmd.new()
		cmd.tick = tick
		tick += 1
		player.run_command(cmd, DT)
	var thrown := player.hit_punch.value
	var shots: Array[Weapon.Shot] = []
	player.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void: shots.append(shot))
	var fire := UserCmd.new()
	fire.tick = tick
	fire.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, true, 0.0, 0.0, 0.0))
	player.run_command(fire, DT)
	_check(
		shots.size() == 1 and thrown.y > 1.0
			and absf(shots[0].base_pitch - player.hit_punch.value.y) < 0.2 and absf(shots[0].base_yaw + player.hit_punch.value.x) < 0.2,
		"a round fired with the aim thrown %.2f degrees up leaves %.2f degrees up" % [
			thrown.y, shots[0].base_pitch if not shots.is_empty() else 0.0,
		]
	)
	player.queue_free()
	await physics_frame


## Where the arc round the crosshair goes for a round fired from ahead, the
## right, behind and the left, looking the game's yaw 0 (down -Z) and then
## turned a quarter to the left.
func _test_the_hit_direction_on_screen() -> void:
	var at := Vector3(100.0, 0.0, 100.0)
	var ahead := DamageIndicator.screen_angle(at, 0.0, at + Vector3(0.0, 40.0, -500.0))
	var right := DamageIndicator.screen_angle(at, 0.0, at + Vector3(500.0, 0.0, 0.0))
	var behind := DamageIndicator.screen_angle(at, 0.0, at + Vector3(0.0, 0.0, 500.0))
	var left := DamageIndicator.screen_angle(at, 0.0, at + Vector3(-500.0, 0.0, 0.0))
	var turned := DamageIndicator.screen_angle(at, 90.0, at + Vector3(-500.0, 0.0, 0.0))
	_check(
		absf(ahead) < 0.001 and absf(right - PI * 0.5) < 0.001 and absf(absf(behind) - PI) < 0.001
			and absf(left + PI * 0.5) < 0.001,
		"a hit's arc sits ahead, right, behind or left of the crosshair as the round came"
	)
	_check(absf(turned) < 0.001, "and a round from the left is ahead once you turn to face it")


## The HUD you play with shows your armour, and an arc for a hit that
## fades out.
func _test_the_hud_shows_hits() -> void:
	var player := (load("res://src/player/player.tscn") as PackedScene).instantiate() as PlayerController
	_world.add_child(player)
	player.place(Vector3(0.0, 0.0, 2048.0), 0.0)
	var hud := GameHud.new()
	hud.player = player
	_world.add_child(hud)
	await process_frame
	await process_frame
	_check(
		hud._armor.visible and hud._armor.text == "100" and hud._shield.visible and not hud.damage_indicator.showing(),
		"the HUD shows 100 armour and no hits (%s)" % hud._armor.text
	)
	await physics_frame
	await physics_frame
	var result := _hit(player, WeaponLibrary.ak47())
	await process_frame
	await process_frame
	_check(
		result.hitbox != null and hud.damage_indicator.showing() == 1 and hud._armor.text != "100",
		"a hit puts an arc round the crosshair, and the armour it wore down shows (%s, %d arcs)" % [hud._armor.text, hud.damage_indicator.showing()]
	)
	hud.damage_indicator._process(DamageIndicator.SHOW_SECONDS + 0.1)
	_check(hud.damage_indicator.showing() == 0, "and the arc is gone %.1f s later" % DamageIndicator.SHOW_SECONDS)
	player.hit_target.wear(0.0, false)
	await process_frame
	await process_frame
	_check(not hud._armor.visible and not hud._shield.visible, "with no armour, no armour is shown")
	hud.queue_free()
	player.queue_free()
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
