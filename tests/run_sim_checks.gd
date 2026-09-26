extends "res://tests/check_suite.gd"

## Checks the split between the simulation and everything around it: that
## the simulation reads nothing but commands, that keys become commands at
## the right instants, that the same commands give the same game however
## fast they are run, that a bot plays through the same commands as you,
## and that being hit slows a player and throws their aim.
##
##   godot --headless --path . --script tests/run_sim_checks.gd
##
## Needs nothing extracted: bots without their model wear the standard boxes.

## The project's tick, in seconds and microseconds, whatever its rate.
var DT := SimClock.tick_seconds()
var TICK := SimClock.tick_usec()
@warning_ignore("integer_division")
var HALF_TICK := TICK / 2
@warning_ignore("integer_division")
var QUARTER_TICK := TICK / 4

## The files that make up the simulation. None of them may read the keys or
## the wall clock.
const SIMULATION_FILES := [
	"res://src/sim/user_cmd.gd",
	"res://src/sim/sim_clock.gd",
	"res://src/sim/game_world.gd",
	"res://src/player/player_sim.gd",
	"res://src/bots/bot.gd",
	"res://src/movement/player_body.gd",
	"res://src/movement/movement_solver.gd",
	"res://src/weapons/weapon.gd",
	"res://src/weapons/recoil_state.gd",
	"res://src/combat/hit_target.gd",
	"res://src/combat/hitscan.gd",
	"res://src/game/inventory.gd",
]

var _world: Node3D


## A player that notes when the world asks it for its command, and walks
## forward when told to.
class Scripted extends PlayerSim:
	var said: Array = []
	var walks := false

	func command_for(tick: int, dt: float) -> UserCmd:
		said.append("%s %d" % [name, tick])
		var cmd := super.command_for(tick, dt)
		if walks:
			cmd.move = Vector2(0.0, 1.0)
		return cmd


## A player that runs what the check asks of it, on the world's tick: the
## buttons it holds, a tap of one, a slot to take in hand, walking forward.
class Commanded extends PlayerSim:
	var held := 0
	var tap := 0
	var select := UserCmd.SELECT_NONE
	var walks := false

	func command_for(tick: int, dt: float) -> UserCmd:
		var cmd := super.command_for(tick, dt)
		cmd.buttons = held
		if tap != 0:
			cmd.steps.append(UserCmd.SubtickStep.new(tap, true, 0.0, yaw_degrees, pitch_degrees))
			tap = 0
		cmd.weapon_select = select
		select = UserCmd.SELECT_NONE
		if walks:
			cmd.move = Vector2(0.0, 1.0)
		return cmd


## A match that notes when the world runs it, and at what time.
class NotedMatch extends MatchState:
	var said: Array = []

	func tick(now_usec: int) -> void:
		said.append("match %d" % now_usec)


func _initialize() -> void:
	_run()


func _run() -> void:
	# First, before a check loads the bot's scene the usual way.
	_test_a_scene_read_ahead()
	_test_the_simulation_reads_only_commands()
	_test_presses_land_at_their_instant()
	_test_the_mouse_turns_as_far_at_any_window_size()
	_test_an_old_input_map_is_put_right()

	_world = Node3D.new()
	root.add_child(_world)
	_build_floor()
	await physics_frame
	await physics_frame

	await _test_the_world_runs_the_tick()
	await _test_a_world_stepped_by_hand()
	_test_the_world_gives_out_path_searches()
	await _test_nothing_runs_itself()
	await _test_joining_and_leaving()
	await _test_the_same_commands_give_the_same_game()
	await _test_a_held_trigger_fires_on_simulation_time()
	await _test_a_press_fires_from_where_the_player_was()
	await _test_a_semi_automatic_fires_once_a_click()
	await _test_the_hand()
	_test_shots_are_heard_from_the_events()
	await _test_a_running_tap_misses()
	await _test_a_bot_plays_through_commands()
	await _test_a_bot_finds_its_way()
	await _test_a_player_wears_hitboxes()
	await _test_a_hit_tags_the_player()
	await _test_a_hit_throws_the_aim()
	_test_the_hit_direction_on_screen()
	await _test_the_hud_shows_hits()
	_test_you_spawn_with_the_knife_and_pistol()
	_test_the_frame_meter()
	await _test_a_frame_draws_where_the_clock_is()
	_test_frames_are_held_under_the_refresh()
	_report()


# --- Nothing read from the disk in the tick ---------------------------------

## A scene read ahead on a worker thread (RigModel.read_ahead, which the
## views use for what a first buy or drop would otherwise read in the tick)
## is handed over by preload_scene as one read the usual way is: asked for
## twice it is read once, and what cannot be read is not asked for.
func _test_a_scene_read_ahead() -> void:
	var path := "res://src/bots/bot.tscn"
	var cached_before := ResourceLoader.has_cached(path)
	var started := RigModel.read_ahead(PackedStringArray([path, path, "res://src/no_such_scene.tscn", ""]))
	var packed := RigModel.preload_scene(path)
	_check(
		started == 1 and packed != null and packed.can_instantiate() and not RigModel.reading(path)
			and RigModel.preload_scene(path) == packed and RigModel.read_ahead(PackedStringArray([path])) == 0,
		"a scene read ahead is handed over when asked for, read once (%d started; %s cached before)" % [started, cached_before]
	)


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


## The view turns by the mouse's movement on the screen, CS2's 0.022 degrees
## a count times the sensitivity, whatever the window's size: in a
## 3840x2160 window the stretch halves the motion's relative, and aiming by
## it turned half as far.
func _test_the_mouse_turns_as_far_at_any_window_size() -> void:
	var input := PlayerInput.new()
	input.sensitivity = 2.0
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(100.0, -50.0)
	motion.relative = motion.screen_relative * 0.5
	input.handle_event(motion)
	_check(
		is_equal_approx(input.yaw_degrees, -100.0 * 2.0 * PlayerInput.CS_YAW_PER_COUNT)
			and is_equal_approx(input.pitch_degrees, 50.0 * 2.0 * PlayerInput.CS_YAW_PER_COUNT),
		"100 counts right and 50 up at sensitivity 2 turn the view 4.4 degrees and 2.2, stretched window or not (%.2f, %.2f)"
			% [input.yaw_degrees, input.pitch_degrees]
	)


## An input map an open editor wrote back from before the inventory: no
## drop, and the range's never-die still on G. The keys come back as CS2
## has them, and G does one thing.
func _test_an_old_input_map_is_put_right() -> void:
	var kept := {}
	for action: StringName in [&"drop", &"dummy_immortal"]:
		kept[action] = InputMap.action_get_events(action) if InputMap.has_action(action) else []
	if InputMap.has_action(&"drop"):
		InputMap.erase_action(&"drop")
	if not InputMap.has_action(&"dummy_immortal"):
		InputMap.add_action(&"dummy_immortal", 0.2)
	InputMap.action_erase_events(&"dummy_immortal")
	var g := InputEventKey.new()
	g.physical_keycode = KEY_G
	InputMap.action_add_event(&"dummy_immortal", g)
	PlayerInput.ensure_actions()
	var keys_of := func(action: StringName) -> Array:
		return InputMap.action_get_events(action).map(func(event: InputEvent) -> int:
			return (event as InputEventKey).physical_keycode if event is InputEventKey else -1)
	_check(
		keys_of.call(&"drop") == [KEY_G] and keys_of.call(&"dummy_immortal") == [KEY_BRACKETLEFT],
		"an old input map gets drop on G and the range's never-die moved to [ (%s, %s)"
			% [keys_of.call(&"drop"), keys_of.call(&"dummy_immortal")]
	)
	for action: StringName in kept:
		InputMap.action_erase_events(action)
		for event: InputEvent in kept[action]:
			InputMap.action_add_event(action, event)


# --- The world that runs the tick -------------------------------------------

## Each tick the world asks each player for one command, in the order they
## joined, runs it, and then runs the match on the tick they have just run.
## It counts its ticks from its start, and that count is simulation time.
func _test_the_world_runs_the_tick() -> void:
	var world := GameWorld.new()
	_world.add_child(world)
	# Stepped here rather than by the engine's ticks. (Once in the tree: a
	# node with a _physics_process has it turned on when it is ready.)
	world.set_physics_process(false)
	var said: Array = []
	var players: Array[PlayerSim] = []
	for i in 3:
		var player := Scripted.new()
		player.name = ["A", "B", "C"][i]
		player.said = said
		_new_player(Vector3(1536.0 + 100.0 * i, 0.0, 1536.0), "T", player)
		world.add_player(player)
		players.append(player)
	var game := NotedMatch.new()
	game.said = said
	_world.add_child(game)
	world.match_state = game
	world.step()
	world.step()

	var expected := [
		"A 1", "B 1", "C 1", "match %d" % SimClock.tick_end_usec(1),
		"A 2", "B 2", "C 2", "match %d" % SimClock.tick_end_usec(2),
	]
	_check(
		said == expected,
		"each tick the world asks each player for one command, in the order they joined, then runs the match at the end of the tick they have just run (%s)" % [said]
	)
	_check(
		players.all(func(player: PlayerSim) -> bool: return player.last_command.tick == 2),
		"every player has run the command for the tick"
	)
	_check(game.players.size() == 3, "everyone in the world plays in its match")
	_check(
		world.tick == 2 and SimClock.current_tick() == 2 and SimClock.now_usec() == 2 * TICK,
		"the world counts its ticks from its start, and simulation time is its count (tick %d, %d us)" % [SimClock.current_tick(), SimClock.now_usec()]
	)
	await physics_frame
	await physics_frame
	_check(
		world.tick == 2 and said.size() == expected.size(),
		"the engine's ticks run none of it while the world is stepped by hand (%d asked)" % said.size()
	)
	var gone: Array[Node] = [game, world]
	gone.append_array(players)
	for node in gone:
		node.queue_free()
	await physics_frame
	_check(GameWorld.current == null, "and once the world is gone there is no world to run")


## A check can hold the world and step it itself: a second of the game in
## one frame, and the player goes as far as a second of running takes it.
func _test_a_world_stepped_by_hand() -> void:
	var world := GameWorld.new()
	_world.add_child(world)
	world.set_physics_process(false)
	var runner := Scripted.new()
	runner.walks = true
	_new_player(Vector3(1536.0, 0.0, -1536.0), "T", runner)
	world.add_player(runner)
	var from := runner.global_position
	var frame := Engine.get_process_frames()
	for i in SimClock.ticks_in(1.0):
		world.step()
	var moved := Vector2(runner.global_position.x - from.x, runner.global_position.z - from.z).length()
	_check(
		Engine.get_process_frames() == frame and world.tick == SimClock.ticks_in(1.0) and moved > 200.0 and moved < 250.0,
		"a second of the game stepped in one frame: %d ticks, and the player ran %.0f units from a standstill" % [world.tick, moved]
	)
	runner.queue_free()
	world.queue_free()
	await physics_frame


## Bots find their way over the nav mesh a few a tick, and the rest on the
## next, rather than every bot on the tick a round starts: the world gives
## out the searches, afresh each tick.
func _test_the_world_gives_out_path_searches() -> void:
	var world := GameWorld.new()
	world.begin_tick()
	var granted := []
	for i in GameWorld.PATH_SEARCHES_PER_TICK + 1:
		granted.append(world.may_search_path())
	var expected := []
	for i in GameWorld.PATH_SEARCHES_PER_TICK:
		expected.append(true)
	expected.append(false)
	world.begin_tick()
	_check(
		granted == expected and world.may_search_path(),
		"%d bots a tick may search the nav mesh, and the next waits for the next tick (%s)" % [GameWorld.PATH_SEARCHES_PER_TICK, granted]
	)
	world.free()


## Out of a world nothing runs: a bot and your own player stay where they
## are through the engine's ticks, and a match stays where it is. Only a
## world runs the game.
func _test_nothing_runs_itself() -> void:
	var bot := (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	bot.team = "CT"
	bot.route = PackedVector3Array([Vector3(2500.0, 0.0, 2500.0), Vector3(2500.0, 0.0, 2000.0)])
	bot.position = Vector3(2500.0, 0.0, 2500.0)
	_world.add_child(bot)
	var you := (load("res://src/player/player.tscn") as PackedScene).instantiate() as PlayerController
	_world.add_child(you)
	# In the air, where anything that ran it would drop it.
	you.place(Vector3(2700.0, 100.0, 2500.0), 0.0)
	var game := MatchState.new()
	game.rules = MatchRules.new()
	game.rules.warmup_seconds = 0.01
	_world.add_child(game)
	game.add_player(bot)
	game.start(0)
	for i in 8:
		await physics_frame
	_check(
		bot.last_command.tick == 0 and bot.global_position.is_equal_approx(Vector3(2500.0, 0.0, 2500.0)),
		"a bot in no world stands where it was put, having run no command (%s)" % bot.global_position
	)
	_check(
		you.last_command.tick == 0 and is_equal_approx(you.global_position.y, 100.0),
		"nor does your own player run, even in the air (%.1f up)" % you.global_position.y
	)
	_check(game.phase == MatchState.Phase.WARMUP, "and a match nobody runs stays in its warmup past its end")
	for node: Node in [bot, you, game]:
		node.queue_free()
	await physics_frame


## Joining puts a player in the world and in its match, once; a player out
## of the scene is out of the game.
func _test_joining_and_leaving() -> void:
	var world := GameWorld.new()
	_world.add_child(world)
	world.set_physics_process(false)
	var game := MatchState.new()
	_world.add_child(game)
	world.match_state = game
	var a := _new_player(Vector3(-1536.0, 0.0, 1536.0), "T")
	var b := _new_player(Vector3(-1536.0, 0.0, 1636.0), "CT")
	world.add_player(a)
	world.add_player(b)
	world.add_player(a)
	_check(
		world.players.size() == 2 and game.players.size() == 2 and a.world == world and b.world == world,
		"joining puts a player in the world and in its match, once however often it is asked"
	)
	a.queue_free()
	await physics_frame
	_check(
		world.players.size() == 1 and world.players[0] == b and game.players.size() == 1,
		"a player freed leaves the world, and its match, by itself"
	)
	world.step()
	_check(b.last_command.tick == 1, "and the world runs on with those still in it")
	world.remove_player(b)
	_check(world.players.is_empty() and b.world == null, "one taken out is out")
	for node: Node in [b, game, world]:
		node.queue_free()
	await physics_frame


# --- Same commands, same game -----------------------------------------------

## A script of commands, timed in seconds whatever the tick rate: run up,
## strafe, a sub-tick jump, a spray with taps in it, a reload.
func _script(seconds: float) -> Array[UserCmd]:
	var run_up := SimClock.ticks_in(0.47)
	var strafe := SimClock.ticks_in(0.156)
	var jump := SimClock.ticks_in(0.547)
	var spray_from := SimClock.ticks_in(0.9375)
	var spray_to := SimClock.ticks_in(1.5625)
	var taps := [SimClock.ticks_in(1.797), SimClock.ticks_in(2.031)]
	var reload := SimClock.ticks_in(2.344)
	var cmds: Array[UserCmd] = []
	for i in SimClock.ticks_in(seconds):
		var cmd := UserCmd.new()
		cmd.tick = 10_000 + i
		cmd.yaw_degrees = 30.0 + 12.8 * i * DT
		cmd.pitch_degrees = -2.0
		cmd.move = Vector2(0.0, 1.0) if i < run_up else Vector2(1.0 if floori(float(i) / strafe) % 2 == 0 else -1.0, 0.0)
		if i == jump:
			cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.JUMP, true, 0.37, cmd.yaw_degrees, -2.0))
		if i >= spray_from and i < spray_to:
			cmd.buttons |= UserCmd.ATTACK
		if i in taps:
			cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, true, 0.6, cmd.yaw_degrees, -2.5))
		if i == reload:
			cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.RELOAD, true, 0.1, cmd.yaw_degrees, -2.0))
		cmds.append(cmd)
	return cmds


func _test_the_same_commands_give_the_same_game() -> void:
	var cmds := _script(2.8125)
	var first := await _play(cmds, Vector3(-512.0, 0.0, 0.0), false)
	var second := await _play(cmds, Vector3(-512.0, 0.0, 0.0), true)

	# 625 ms held: rounds at 0, 100 ... 600 ms, then two taps.
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
	for i in SimClock.ticks_in(1.0):
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
	var run_up := SimClock.ticks_in(0.3125)
	for i in run_up:
		var run := UserCmd.new()
		run.tick = 60_000 + i
		run.move = Vector2(1.0, 0.0)
		player.run_command(run, DT)
	var origins: Array[Vector3] = []
	player.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void:
		origins.append(shot.origin))
	var cmd := UserCmd.new()
	cmd.tick = 60_000 + run_up
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


## A semi-automatic gun through the real body and real commands: holding
## the button fires one round, every click fires its own, a click held from
## before the gun is ready fires when it is, and one let go before then
## fires nothing. The gun is the AK with the Desert Eagle's numbers, the
## game's m_bIsFullAuto false among them.
func _test_a_semi_automatic_fires_once_a_click() -> void:
	var player := _new_player(Vector3(-512.0, 0.0, 512.0), "T")
	var deagle := WeaponLibrary.ak47()
	WeaponVData.apply(deagle, "weapon_deagle")
	player.equip(deagle)
	await physics_frame
	var times: Array[int] = []
	player.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void:
		times.append(shot.timestamp_usec))
	# In an array so the lambda below moves it on: it captures a plain int
	# by value.
	var tick := [80_000]
	# Which ticks the button is down for, as [first, last] pairs; each goes
	# down 0.3 into its first tick.
	# Each part starts with a full magazine: the Deagle holds seven.
	var run := func(presses: Array, ticks: int) -> void:
		player.weapon.ammo = deagle.magazine_size
		for i in ticks:
			var cmd := UserCmd.new()
			cmd.tick = tick[0] + i
			for click: Array in presses:
				if i == click[0]:
					cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, true, 0.3, 0.0, 0.0))
				if i >= click[0] and i <= click[1]:
					cmd.buttons |= UserCmd.ATTACK
				if i == click[1] + 1:
					cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, false, 0.1, 0.0, 0.0))
			player.run_command(cmd, DT)
		tick[0] += ticks

	var second := SimClock.ticks_in(1.0)
	run.call([[0, second - 1]], second + 1)
	_check_equal(times.size(), 1, "a Desert Eagle held down for a second fires one round")

	# Five clicks, each down for three ticks, a third of a second apart:
	# slower than the gun's 0.225 s cycle, so every one of them fires.
	times.clear()
	var apart := SimClock.ticks_in(0.33)
	var clicks := []
	for n in 5:
		clicks.append([n * apart, n * apart + 3])
	run.call(clicks, 5 * apart)
	_check_equal(times.size(), 5, "five clicks a third of a second apart fire five rounds")

	# A click five ticks after a round, held for twenty: too soon, so it
	# waits, and fires the instant the gun is ready rather than on a tick.
	times.clear()
	run.call([[0, 0], [6, 25]], 40)
	var cycle := int(round(deagle.cycle_time * 1_000_000.0))
	@warning_ignore("integer_division")
	_check(
		times.size() == 2 and times[1] - times[0] == cycle,
		"a click held from before the gun is ready fires the moment it is, %d ms after the last round (%s)" % [cycle / 1000, times]
	)

	# The same early click let go after three ticks, before the gun is ready.
	times.clear()
	run.call([[0, 0], [6, 8]], 40)
	_check_equal(times.size(), 1, "a click let go before the gun is ready fires nothing, then or later")
	player.queue_free()
	await physics_frame


## What a player carries and holds, through commands on a world's ticks: a
## spawn's loadout, drawn on the world's clock; each gun its own, keeping its
## rounds through a switch; asking for what is in hand leaving it as it is,
## as Source does (no draw, not a full magazine); anything else drawn, and
## firing only once the draw is over; a switch stopping a reload; the knife;
## a grenade thrown from the hand; a gun dropped and picked up again with
## its rounds; and the bomb holding the player still. Every round is the
## game's: weapon_fire, and the hurt it does is the shooter's.
func _test_the_hand() -> void:
	var player := Commanded.new()
	player.starting_gun = WeaponLibrary.ak47()
	_new_player(Vector3(2048.0, 0.0, 2048.0), "T", player)
	# Armed before there is a world, on the engine's clock.
	player.respawn()
	var world := GameWorld.new()
	_world.add_child(world)
	world.set_physics_process(false)
	world.game.add_system(GrenadeSystem.new())
	var events: Array[GameEvent] = []
	world.game.events.listen_all(func(event: GameEvent) -> void: events.append(event))
	world.add_player(player)
	var ak := player.weapon
	var inventory := player.inventory
	var ak_ready := int(roundf(ItemRegistry.item("weapon_ak47").deploy_seconds * 1_000_000.0))
	_check(
		ak != null and ak.data.item_class == "weapon_ak47" and inventory.has("weapon_knife") and inventory.has("weapon_glock")
			and world.game.inventory(player.userid) == inventory,
		"a terrorist spawns with the knife and the Glock and the AK-47 handed out, in hand; the game knows the inventory by the player's userid"
	)
	_check_equal(ak.next_shot_usec(), ak_ready, "armed before the world was made, joining it draws the AK-47 again on its clock")
	var steps := func(seconds: float) -> void:
		for i in maxi(SimClock.ticks_in(seconds), 1):
			world.step()

	# Held from the spawn, the first round goes the moment the draw is over,
	# into another player, as the game's.
	var victim := _new_player(Vector3(2048.0, 0.0, 1748.0), "CT")
	world.add_player(victim)
	var victim_id := victim.userid
	# Its hitboxes are where the physics space sees them once it has stepped.
	await physics_frame
	await physics_frame
	var shots: Array[int] = []
	player.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void: shots.append(shot.timestamp_usec))
	player.held = UserCmd.ATTACK
	steps.call(float(ak_ready) / 1_000_000.0 + 0.2)
	player.held = 0
	steps.call(DT)
	_check(not shots.is_empty() and shots[0] == ak_ready,
		"held from the spawn, the AK-47 fires the moment its draw is over, %.2f s in (%s)" % [float(ak_ready) / 1_000_000.0, shots.slice(0, 1)])
	var fired := _named(events, &"weapon_fire")
	_check(
		fired.size() == shots.size() and fired.all(func(event: GameEvent) -> bool:
			return int(event.fields["userid"]) == player.userid and event.fields["weapon"] == "weapon_ak47"),
		"every round sends weapon_fire, saying who fired it and with what (%d of %d)" % [fired.size(), shots.size()]
	)
	# And fire_bullets, CS2's message a tracer is drawn from: where it left
	# and which way, after its weapon_fire and before where it landed.
	var bullets := _named(events, &"fire_bullets")
	var names := events.map(func(event: GameEvent) -> String: return String(event.name))
	var first_order := names.slice(names.find("weapon_fire"), names.find("weapon_fire") + 3)
	var round_way := PlayerInput.aim_direction(float(bullets[0].fields["yaw"]), float(bullets[0].fields["pitch"])) if not bullets.is_empty() else Vector3.ZERO
	var toward := PlayerInput.aim_direction(0.0, 0.0)
	_check(
		bullets.size() == shots.size() and int(bullets[0].fields["userid"]) == player.userid
			and bullets[0].fields["weapon"] == "weapon_ak47" and int(bullets[0].fields["mode"]) == 0
			and first_order == ["weapon_fire", "fire_bullets", "bullet_impact"]
			and round_way.dot(toward) > 0.999 and float(bullets[0].fields["y"]) > player.global_position.y + 50.0,
		"every round sends fire_bullets too, from the eye toward where it went, between its weapon_fire and its impacts (%s)" % [first_order]
	)
	var hurt := _named(events, &"player_hurt")
	_check(
		not hurt.is_empty() and int(hurt[0].fields["attacker"]) == player.userid and int(hurt[0].fields["userid"]) == victim_id
			and hurt[0].fields["weapon"] == "weapon_ak47",
		"and the round that finds the other side hurts them as the shooter's (player_hurt from %s)" % [hurt[0].fields if not hurt.is_empty() else {}]
	)
	world.remove_player(victim)
	victim.queue_free()

	var drawn: Array[String] = []
	player.equipped.connect(func(entry: Inventory.Entry) -> void:
		drawn.append(entry.item.item_class if entry != null else ""))
	ak.ammo = 12
	player.select = 1
	steps.call(DT)
	_check(player.weapon == ak and ak.ammo == 12 and drawn.is_empty(),
		"asking for the AK-47 in hand leaves it as it is: no draw, and the %d rounds it had" % ak.ammo)

	player.select = 2
	steps.call(DT)
	var glock := player.weapon
	_check(glock != null and glock.data.item_class == "weapon_glock" and drawn.size() == 1 and drawn[0] == "weapon_glock",
		"2 draws the Glock (%s)" % [drawn])
	_check(is_equal_approx(player.config.max_speed, glock.data.max_player_speed), "and runs at its speed")
	shots.clear()
	player.held = UserCmd.ATTACK
	var glock_draw := ItemRegistry.item("weapon_glock").deploy_seconds
	steps.call(glock_draw * 0.5)
	_check(shots.is_empty(), "held while it is drawn, it does not fire")
	steps.call(glock_draw * 0.5 + 0.25)
	_check_equal(shots.size(), 1, "then fires once for the held trigger, a semi-automatic")
	player.held = 0

	player.select = 1
	steps.call(DT)
	_check(player.weapon == ak and ak.ammo == 12, "1 draws the same AK-47 again, with its 12 rounds")
	steps.call(float(ak_ready) / 1_000_000.0)
	player.tap = UserCmd.RELOAD
	steps.call(DT)
	var reloading := ak.is_reloading(SimClock.now_usec())
	player.select = 2
	steps.call(DT)
	player.select = UserCmd.SELECT_LAST
	steps.call(ak.data.reload_time + 0.1)
	_check(reloading and player.weapon == ak and ak.ammo == 12 and not ak.is_reloading(SimClock.now_usec()),
		"a reload is stopped by a switch, without its rounds; Q takes the AK-47 back (%d rounds)" % ak.ammo)

	player.select = 3
	steps.call(DT)
	_check(player.weapon == null and player.in_hand_class() == "weapon_knife"
			and is_equal_approx(player.config.max_speed, ItemRegistry.item("weapon_knife").max_speed),
		"3 takes the knife, at its speed (%.0f)" % player.config.max_speed)

	# A grenade: the pin once it is drawn, the throw on letting go.
	inventory.add(GrenadeRules.HE)
	player.select = 4
	steps.call(DT)
	_check_equal(player.in_hand_class(), GrenadeRules.HE, "4 takes the HE out")
	var pulled := [0]
	var released: Array[bool] = []
	player.pin_pulled.connect(func() -> void: pulled[0] += 1)
	player.grenade_released.connect(func(underhand: bool) -> void: released.append(underhand))
	player.held = UserCmd.ATTACK2
	steps.call(0.25)
	_check_equal(pulled[0], 0, "the right button pulls no pin while the HE is drawn")
	steps.call(ItemRegistry.item(GrenadeRules.HE).deploy_seconds)
	_check_equal(pulled[0], 1, "and once it is out, pulls it")
	events.clear()
	player.held = 0
	steps.call(DT)
	var thrown := _named(events, &"grenade_thrown")
	_check(
		released.size() == 1 and released[0] and thrown.size() == 1 and int(thrown[0].fields["userid"]) == player.userid
			and not inventory.has(GrenadeRules.HE) and world.game.entities.of_class("hegrenade_projectile").size() == 1,
		"let go, the right button alone throws it underhand, from the hand: grenade_thrown, the HE in the world and out of the inventory"
	)
	# Not to go off at the thrower's feet.
	for grenade in world.game.entities.of_class("hegrenade_projectile"):
		grenade.remove()
	_check(player.in_hand_class() == GrenadeRules.HE and player.weapon == null, "the throw keeps the hand while it lasts")
	steps.call(PlayerSim.THROW_UNDERHAND_SECONDS)
	_check_equal(player.in_hand_class(), "weapon_knife", "and then the last thing held is drawn")

	# Dropped, the AK-47 keeps its rounds on the ground, and comes back with
	# them when picked up.
	player.select = 1
	steps.call(float(ak_ready) / 1_000_000.0 + DT)
	events.clear()
	var view := DroppedItemView.new()
	_world.add_child(view)
	view.watch(world.game)
	var held := player.held_transform()
	world.game.command(player.userid, "drop")
	steps.call(DT)
	var on_ground := world.game.entities.of_class("weapon_ak47")
	var dropped: DroppedItem = on_ground[0] if not on_ground.is_empty() else null
	_check(
		dropped != null and dropped.entry.weapon == ak and ak.ammo == 12 and inventory.item_in(ItemDef.Slot.PRIMARY) == null
			and player.in_hand_class() == "weapon_knife" and _named(events, &"item_remove").size() == 1,
		"G drops the AK-47 in hand, its own Weapon with its 12 rounds on the ground, item_remove, and the knife comes back to the hand"
	)
	_check(dropped != null and view.model_of(dropped.id) == null and view.drawn() == 0,
		"its model is not built in the tick it fell on, which it would hold up, but on the next frame")
	if dropped != null:
		var aim :=PlayerInput.aim_direction(player.yaw_degrees, player.pitch_degrees)
		var went := dropped.position - dropped.previous_position
		var across := Vector2(went.x, went.z).length() / DT
		_check(
			dropped.previous_position.is_equal_approx(held.origin) and dropped.previous_basis.is_equal_approx(held.basis)
				and held.basis.z.dot(aim) > 0.99,
			"it leaves from where the gun was held, pointing where the player looks"
		)
		var right := Vector3(cos(deg_to_rad(player.yaw_degrees)), 0.0, -sin(deg_to_rad(player.yaw_degrees)))
		var off := held.origin - (player.global_position + Vector3.UP * player.eye_height())
		_check(
			absf(off.dot(aim) - HeldPose.RIFLE_STAND.x) < 0.01 and absf(off.dot(right) - HeldPose.RIFLE_STAND.y) < 0.01
				and absf(off.dot(right.cross(aim)) - HeldPose.RIFLE_STAND.z) < 0.01,
			"held where CS2's third-person hold has the AK-47, from the game's state alone: 13.7 ahead of the eyes, 4.7 right, 3.7 down"
		)
		_check(
			absf(across - ItemDrops.THROW_SPEED / Vector3(aim + Vector3.UP * ItemDrops.THROW_LIFT).length()) < 1.0
				and Vector2(went.x, went.z).normalized().dot(Vector2(aim.x, aim.z).normalized()) > 0.999,
			"thrown the way the player looks at CS2's 300 u/s, a little lifted (%.0f u/s across)" % across
		)
		_check(not dropped.basis.is_equal_approx(dropped.previous_basis), "and it turns as it flies")
	steps.call(1.0)
	if dropped != null:
		_check(
			dropped.resting and absf(dropped.position.y) < 0.5 and dropped.position.distance_to(player.global_position) > 32.0,
			"thrown ahead, it comes to rest on the floor %.0f units off" % dropped.position.distance_to(player.global_position)
		)
		view._process(0.0)
		var model := view.model_of(dropped.id)
		# Measured on what is drawn, not by the view's own sums: the drawn
		# box's height is the model's thinnest size, its bottom the floor,
		# and the muzzle's axis along the way it was heading.
		var own := DroppedItemView.bounds(model) if model != null else AABB()
		var lying_box := model.transform * own if model != null else AABB()
		var way := DroppedItemView.heading(dropped.basis)
		var muzzle := (model.transform.basis * Vector3.BACK).normalized() if model != null else Vector3.ZERO
		_check(
			model != null and absf(lying_box.position.y - dropped.position.y) < 0.1
				and absf(lying_box.size.y - minf(own.size.x, minf(own.size.y, own.size.z))) < 0.1
				and absf(muzzle.dot(Vector3(sin(way), 0.0, cos(way)))) > 0.99,
			"drawn, it lies on its thinnest side, the way it was heading, its lowest point on the floor (%.2f high, bottom %.2f off)" % [lying_box.size.y, lying_box.position.y - dropped.position.y]
		)
		player.global_position = dropped.position
		player.previous_position = dropped.position
	steps.call(1.0)
	var primary := inventory.item_in(ItemDef.Slot.PRIMARY)
	_check(primary != null and primary.weapon == ak and ak.ammo == 12 and world.game.entities.of_class("weapon_ak47").is_empty(),
		"walked over, once whoever dropped it may take it back, it is picked up with its rounds")

	# Held still by the game: planting or defusing, which the bomb says.
	player.select = 1
	steps.call(float(ak_ready) / 1_000_000.0 + DT)
	world.game.provide(&"holds_still", func(_userid: int) -> bool: return true)
	shots.clear()
	var from := player.global_position
	player.held = UserCmd.ATTACK
	player.walks = true
	steps.call(0.5)
	_check(player.held_still and shots.is_empty() and Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length() < 1.0,
		"held still by the game, the player neither fires nor moves")
	player.held = 0
	player.walks = false
	world.remove_player(player)
	player.queue_free()
	view.queue_free()
	world.queue_free()
	await physics_frame


## A shot is heard from the game's events, never from inside the tick: the
## shooter's own weapon_fire is noted as the tick hands it out, one for
## each round and with the gun it names, and played on the next frame
## drawn; another player's shots are theirs to hear.
func _test_shots_are_heard_from_the_events() -> void:
	var world := GameWorld.new()
	_world.add_child(world)
	world.set_physics_process(false)
	var player := Commanded.new()
	player.starting_gun = WeaponLibrary.ak47()
	_new_player(Vector3(-2048.0, 0.0, 2048.0), "T", player)
	player.respawn()
	world.add_player(player)
	var other := _new_player(Vector3(-2048.0, 0.0, 1748.0), "T")
	world.add_player(other)
	var sounds := WeaponSounds.new()
	player.add_child(sounds)
	# Frames are the test's to draw.
	sounds.set_process(false)
	sounds.watch(player)
	var fired: Array[GameEvent] = []
	var heard_in_tick: Array[int] = []
	world.game.events.listen(&"weapon_fire", func(event: GameEvent) -> void: fired.append(event))
	player.shot_traced.connect(func(_shot: Weapon.Shot, _result: Hitscan.Result) -> void:
		heard_in_tick.append(sounds.pending_shots().size() - fired.size()))

	player.held = UserCmd.ATTACK
	for i in SimClock.ticks_in(ItemRegistry.item("weapon_ak47").deploy_seconds + 0.3):
		world.step()
	player.held = 0
	var noted := sounds.pending_shots()
	_check(
		not fired.is_empty() and noted.size() == fired.size()
			and Array(noted).all(func(item_class: String) -> bool: return item_class == "weapon_ak47"),
		"every round the player fires is noted from its weapon_fire, as the gun it names (%d noted, %d sent)" % [noted.size(), fired.size()]
	)
	_check(
		not heard_in_tick.is_empty() and heard_in_tick.all(func(ahead: int) -> bool: return ahead == 0),
		"none of it from the shot inside the tick: a round is noted only once the tick hands its event out (%s)" % [heard_in_tick]
	)
	world.game.events.send(&"weapon_fire", {"userid": other.userid, "weapon": "weapon_glock"})
	world.game.events.flush()
	_check_equal(sounds.pending_shots().size(), noted.size(), "another player's shot is not heard as this one's")
	sounds._process(0.0)
	_check(sounds.pending_shots().is_empty(), "and the next frame drawn plays what was noted")

	world.remove_player(player)
	sounds._process(0.0)
	world.game.events.send(&"weapon_fire", {"userid": 1, "weapon": "weapon_ak47"})
	world.game.events.flush()
	_check(sounds.pending_shots().is_empty(), "out of the world, nothing is noted from its events")
	world.remove_player(other)
	player.queue_free()
	other.queue_free()
	world.queue_free()


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
	var run_up := SimClock.ticks_in(1.0)
	var every := SimClock.ticks_in(1.5)
	for i in run_up + 12 * every:
		var cmd := UserCmd.new()
		cmd.tick = 70_000 + i
		cmd.move = Vector2(0.0, 1.0)
		if i >= run_up and (i - run_up) % every == 0:
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
	# Run by a world on the engine's ticks, as on a map.
	var world := GameWorld.new()
	_world.add_child(world)
	for player: PlayerSim in [enemy, friend, bot]:
		world.add_player(player)
	var times: Array[int] = []
	bot.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void:
		times.append(shot.timestamp_usec))

	_check(bot.weapon != null and bot.hit_target.hitboxes().size() > 0, "a bot without its model still has its weapon and the standard boxes")
	for i in SimClock.ticks_in(2.0):
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
	world.queue_free()
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
	var world := GameWorld.new()
	_world.add_child(world)
	world.add_player(bot)
	bot.place(start, 0.0)
	bot.set("_next", 1)
	var arrived := []
	var off_mesh := 0
	var highest := -INF
	var ducked_under := 0
	var standing_under := 0
	var jumps := 0
	var was_on_ground := true
	for i in SimClock.ticks_in(40.0):
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
	world.queue_free()
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
	var tick := _run_forward(player, 80_000, SimClock.ticks_in(1.0))
	var top := Vector2(player.velocity.x, player.velocity.z).length()
	# CS2's two ticks of its own, in ours.
	var delay := SimClock.ticks_in(PlayerSim.TAG_DELAY_SECONDS)
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
	tick = _run_forward(player, tick, delay - 1)
	var before := player.velocity_modifier
	tick = _run_forward(player, tick, 1)
	_check(
		is_equal_approx(before, 1.0) and is_equal_approx(player.velocity_modifier, 1.0 - ak.tagging_power),
		"the tag lands two CS2 ticks (%d of ours) after the hit: %.2f, then %.2f of full speed" % [delay, before, player.velocity_modifier]
	)
	tick = _run_forward(player, tick, SimClock.ticks_in(0.25))
	var slowed := Vector2(player.velocity.x, player.velocity.z).length()
	_check(
		top > 210.0 and slowed < top * 0.6,
		"a quarter of a second on, running flat out has slowed from %.0f to %.0f u/s" % [top, slowed]
	)
	tick = _run_forward(player, tick, SimClock.ticks_in(0.5))
	var second_hit_from := player.velocity_modifier
	await physics_frame
	await physics_frame
	_hit(player, ak)
	tick = _run_forward(player, tick, delay)
	_check(
		second_hit_from > 0.55 and is_equal_approx(player.velocity_modifier, 1.0 - ak.tagging_power),
		"a second hit takes it back to %.2f from %.2f, no lower" % [player.velocity_modifier, second_hit_from]
	)
	var back_at := -1
	for i in SimClock.ticks_in(2.0):
		tick = _run_forward(player, tick, 1)
		if player.velocity_modifier >= 1.0:
			back_at = i + 1
			break
	_check(
		absi(back_at - SimClock.ticks_in(1.5)) <= 1,
		"and it is all back 1.5 s later (%d ticks)" % back_at
	)
	var smg := WeaponLibrary.ak47()
	smg.tagging_power = 1.0
	await physics_frame
	await physics_frame
	_hit(player, smg)
	tick = _run_forward(player, tick, delay)
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
		for i in SimClock.ticks_in(0.375):
			var cmd := UserCmd.new()
			cmd.tick = tick
			tick += 1
			player.run_command(cmd, DT)
			if player.hit_punch.value.y > peak.y:
				peak = player.hit_punch.value
		peaks[armored] = peak
		settled[armored] = player.hit_punch.value.length()
		for i in SimClock.ticks_in(0.5):
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
	for i in SimClock.ticks_in(0.094):
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


## The frame meter, handed the times frames began: made up here, the wall
## clock in the game. A second of 10 ms frames with one of 50 ms in it reads
## 96 a second and 50 ms, and the next second starts over.
func _test_the_frame_meter() -> void:
	var meter := FrameMeter.new()
	var now := 5000000
	meter.frame(now)
	for i in 50:
		now += 10000
		meter.frame(now)
	_check(meter.line() == "fps -" and is_zero_approx(meter.fps), "the frame rate says nothing before a second has passed")
	now += 50000
	meter.frame(now)
	while now < 5000000 + FrameMeter.WINDOW_USEC:
		now += 10000
		meter.frame(now)
	# 95 frames of 10 ms and one of 50: 96 frames in exactly one second.
	_check(
		is_equal_approx(meter.fps, 96.0) and is_equal_approx(meter.slowest_ms, 50.0)
			and meter.line() == "fps 96   slowest 50.0 ms",
		"after a second, the frames in it and the slowest of them (%s)" % meter.line()
	)
	for i in 125:
		now += 8000
		meter.frame(now)
	_check(
		is_equal_approx(meter.fps, 125.0) and is_equal_approx(meter.slowest_ms, 8.0),
		"and each second is counted afresh: the hitch is gone from the next (%s)" % meter.line()
	)


## The game starts in exclusive fullscreen with V-Sync, where G-Sync and
## FreeSync engage, and holds its frames just under the screen's refresh,
## as NVIDIA Reflex holds CS2's. Headless nothing is drawn, so nothing is
## held (the players built above have their views).
func _test_frames_are_held_under_the_refresh() -> void:
	_check(
		int(ProjectSettings.get_setting("display/window/size/mode")) == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			and int(ProjectSettings.get_setting("display/window/vsync/vsync_mode", 1)) == DisplayServer.VSYNC_ENABLED,
		"the game starts in exclusive fullscreen, V-Sync on"
	)
	_check(
		PlayerView.frame_cap(240.0) == 224 and PlayerView.frame_cap(144.0) == 138 and PlayerView.frame_cap(60.0) == 59
			and PlayerView.frame_cap(0.0) == 0 and PlayerView.frame_cap(-1.0) == 0,
		"frames held just under the refresh: 224 at 240 Hz, 138 at 144, 59 at 60, none when it is not known"
	)
	_check(Engine.max_fps == 0, "and headless, no cap (%d)" % Engine.max_fps)


## A frame is drawn as far between the ticks as the clock says when it is
## drawn: a frame that runs a tick is drawn after it, later than Godot's
## fraction, taken at the frame's start, says. For that the ticks keep to
## the clock.
func _test_a_frame_draws_where_the_clock_is() -> void:
	_check(
		is_zero_approx(float(ProjectSettings.get_setting("physics/common/physics_jitter_fix"))),
		"the ticks keep to the clock (physics_jitter_fix 0)"
	)
	DrawClock.fraction()
	await physics_frame
	var grew := -1.0
	var expected := 0.0
	var engine_still := false
	for attempt in 30:
		await physics_frame
		var first := DrawClock.fraction()
		if first > 0.6:
			continue
		var engine := Engine.get_physics_interpolation_fraction()
		# A sleep is as long as the system's timer makes it, so what passed
		# is measured rather than assumed.
		var started := Time.get_ticks_usec()
		OS.delay_usec(4000)
		var passed := Time.get_ticks_usec() - started
		grew = DrawClock.fraction() - first
		expected = minf(float(passed) / SimClock.tick_usec(), 1.0 - first)
		engine_still = is_equal_approx(Engine.get_physics_interpolation_fraction(), engine)
		break
	_check(
		grew > 0.2 and absf(grew - expected) < 0.05 and engine_still,
		"a few ms on in a frame, the drawn fraction has moved on with the clock (%.2f of a tick, %.2f by the clock), where Godot's stays put" % [grew, expected]
	)
	var at := DrawClock.usec()
	_check(
		at >= SimClock.now_usec() - SimClock.tick_usec() and at <= SimClock.now_usec(),
		"and the time drawn is between the last two ticks"
	)


## You spawn as CS2 spawns a player: the knife and your side's pistol
## (mp_t_default_secondary, mp_ct_default_secondary), the pistol in hand,
## and nothing else taken in hand on the way; a rifle is bought.
func _test_you_spawn_with_the_knife_and_pistol() -> void:
	for side: String in ["T", "CT"]:
		var you := (load("res://src/player/player.tscn") as PackedScene).instantiate() as PlayerController
		you.team = side
		var drawn := PackedStringArray()
		you.equipped.connect(func(entry: Inventory.Entry) -> void:
			drawn.append(entry.item.item_class if entry != null else ""))
		_world.add_child(you)
		var carried := PackedStringArray()
		for entry in you.inventory.entries():
			carried.append(entry.item.item_class)
		carried.sort()
		var pistol: String = Inventory.STARTING_PISTOLS[side]
		var expected := PackedStringArray([pistol, "weapon_knife"])
		expected.sort()
		_check(
			carried == expected and you.in_hand_class() == pistol and not drawn.is_empty() and drawn.count(pistol) == drawn.size(),
			"a %s spawns with the knife and the %s, the pistol in hand, having taken nothing else in hand (carries %s, drew %s)" % [side, pistol, carried, drawn]
		)
		you.free()


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
		hud.health_ammo.armour == 100 and hud.health_ammo.health == 100 and not hud.damage_indicator.showing(),
		"the HUD shows 100 armour and no hits (%d)" % hud.health_ammo.armour
	)
	await physics_frame
	await physics_frame
	var result := _hit(player, WeaponLibrary.ak47())
	await process_frame
	await process_frame
	_check(
		result.hitbox != null and hud.damage_indicator.showing() == 1 and hud.health_ammo.armour < 100,
		"a hit puts an arc round the crosshair, and the armour it wore down shows (%d, %d arcs)" % [hud.health_ammo.armour, hud.damage_indicator.showing()]
	)
	hud.damage_indicator._process(DamageIndicator.SHOW_SECONDS + 0.1)
	_check(hud.damage_indicator.showing() == 0, "and the arc is gone %.1f s later" % DamageIndicator.SHOW_SECONDS)
	player.hit_target.wear(0.0, false)
	await process_frame
	await process_frame
	_check(hud.health_ammo.armour == 0, "with no armour, no armour is shown")
	_check(
		hud._where.text.begins_with("pos ") and hud._where.text.get_slice("\n", 1).begins_with("fps "),
		"under where you stand, the frame rate (%s)" % hud._where.text.c_escape()
	)
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


## The events of one name among those heard.
static func _named(events: Array[GameEvent], event_name: StringName) -> Array[GameEvent]:
	var out: Array[GameEvent] = []
	for event in events:
		if event.name == event_name:
			out.append(event)
	return out


## A player in the simulation with nothing drawing it, standing on the floor:
## a plain one, or the one given.
func _new_player(at: Vector3, team: String, player: PlayerSim = null) -> PlayerSim:
	if player == null:
		player = PlayerSim.new()
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


func _report() -> void:
	_finish("simulation")


func _print_passes() -> bool:
	return true
