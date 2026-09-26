extends "res://tests/check_suite.gd"

## Checks that bots make way for their own side (BotSteering, and the bot's
## stuck handling): two teammates meeting head-on in a corridor, at a
## diagonal, in a corridor with just room to pass, and in a doorway one hull
## wide all get past each other without jumping at each other; a bot
## follows a slower teammate rather than hopping into it, and walks round
## one standing still; an enemy is not made way for; and the side's bots
## after the first go to spots spread round a site rather than all to its
## middle (reference/playtest-2026-09-25.md, issue 6).
##
##   godot --headless --path . --script tests/run_bot_move_checks.gd
##
## Needs nothing extracted: every floor is a hand-built nav mesh over boxes,
## as tests/run_sim_checks.gd's course is, and bots without their model
## wear the standard boxes. The world is stepped by hand, so a minute of
## game runs in a moment.

## Where the courses are, apart from each other.
const LONG_CORRIDOR := Vector3(0.0, 0.0, 0.0)
const DIAGONAL := Vector3(2000.0, 0.0, 0.0)
const NARROW := Vector3(4000.0, 0.0, 0.0)
const DOORWAY := Vector3(6000.0, 0.0, 0.0)
const FOLLOWING := Vector3(0.0, 0.0, 3000.0)
const STANDING := Vector3(2000.0, 0.0, 3000.0)
const ENEMIES := Vector3(4000.0, 0.0, 3000.0)
const STUCK := Vector3(6000.0, 0.0, 3000.0)

## A corridor 800 units long, walls 160 apart; its narrow one's 80 apart,
## just room for two 32-unit hulls side by side once both step to the wall.
const CORRIDOR_LENGTH := 800.0
const WIDE := 160.0
const NARROW_WIDTH := 80.0
## The nav mesh stops this far from every wall, as the game's does.
const ERODED := 16.0

var _world: Node3D
var _scene: PackedScene


func _initialize() -> void:
	_run()


func _run() -> void:
	# Eight ticks a frame (the project allows 16): every tick is still its own
	# physics step, so the hulls meet as they do in the game, in an eighth of
	# the wall-clock time.
	Engine.time_scale = 8.0
	_scene = load("res://src/bots/bot.tscn") as PackedScene
	_world = Node3D.new()
	root.add_child(_world)
	_build_floor()
	await physics_frame
	await physics_frame

	_test_the_steering_by_itself()
	await _test_head_on_in_a_corridor()
	await _test_head_on_at_a_diagonal()
	await _test_head_on_with_just_room()
	await _test_a_doorway_one_hull_wide()
	await _test_following_a_slower_teammate()
	await _test_round_a_teammate_standing()
	await _test_an_enemy_is_not_made_way_for()
	await _test_stuck_on_a_wall_it_wiggles_then_jumps()
	_test_site_goals_are_spread()
	_finish("bot_movement")


# --- BotSteering on its own -------------------------------------------------

## The decisions, from plain data: follow, step aside to its right when
## square on, away from a friend to one side, back off or hold where there
## is no room, and nothing for a friend behind, off its line or on another
## floor.
func _test_the_steering_by_itself() -> void:
	var here := Vector3.ZERO
	var north := Vector3(0.0, 0.0, -1.0)
	var none := PackedVector3Array()

	var clear := BotSteering.steer(here, north, 1, none, none, PackedInt32Array(), null)
	_check(clear.mode == BotSteering.CLEAR and clear.way.is_equal_approx(north) and clear.friend == -1, "nobody about, it walks its way")

	var ahead := PackedVector3Array([Vector3(0.0, 0.0, -80.0)])
	var going := PackedVector3Array([Vector3(0.0, 0.0, -150.0)])
	var follow := BotSteering.steer(here, north, 1, ahead, going, PackedInt32Array([2]), null)
	_check(follow.mode == BotSteering.FOLLOW and follow.way.is_equal_approx(north), "a friend ahead going its way it follows (%d)" % follow.mode)
	var close := PackedVector3Array([Vector3(0.0, 0.0, -50.0)])
	var held := BotSteering.steer(here, north, 1, close, going, PackedInt32Array([2]), null)
	_check(held.mode == BotSteering.FOLLOW and held.way == Vector3.ZERO, "and holds once inside the gap behind it")

	var coming := PackedVector3Array([Vector3(0.0, 0.0, 200.0)])
	var aside := BotSteering.steer(here, north, 1, ahead, coming, PackedInt32Array([2]), null)
	# North is -Z, so its right is +X.
	_check(
		aside.mode == BotSteering.SIDESTEP and aside.way.x > 0.0 and aside.way.z < 0.0,
		"a friend square on coming at it: aside to its right while going on (%s)" % aside.way
	)
	var their_view := BotSteering.steer(Vector3(0.0, 0.0, -80.0), -north, 2, PackedVector3Array([here]),
		PackedVector3Array([Vector3(0.0, 0.0, -200.0)]), PackedInt32Array([1]), null)
	_check(their_view.way.x < 0.0, "and the friend steps to its own right, the other way in the world, so they part (%s)" % their_view.way)
	var touching := BotSteering.steer(here, north, 1, PackedVector3Array([Vector3(0.0, 0.0, -33.0)]), coming, PackedInt32Array([2]), null)
	_check(touching.way.is_equal_approx(Vector3.RIGHT), "hull to hull, it steps straight aside (%s)" % touching.way)

	var to_its_right := PackedVector3Array([Vector3(12.0, 0.0, -80.0)])
	var left := BotSteering.steer(here, north, 1, to_its_right, PackedVector3Array([Vector3.ZERO]), PackedInt32Array([2]), null)
	_check(left.mode == BotSteering.SIDESTEP and left.way.x < 0.0, "a friend standing a little to its right: it steps left (%s)" % left.way)

	var behind := BotSteering.steer(here, north, 1, PackedVector3Array([Vector3(0.0, 0.0, 50.0)]), coming, PackedInt32Array([2]), null)
	var off_line := BotSteering.steer(here, north, 1, PackedVector3Array([Vector3(45.0, 0.0, -60.0)]), coming, PackedInt32Array([2]), null)
	var far := BotSteering.steer(here, north, 1, PackedVector3Array([Vector3(0.0, 0.0, -120.0)]), coming, PackedInt32Array([2]), null)
	var upstairs := BotSteering.steer(here, north, 1, PackedVector3Array([Vector3(0.0, 100.0, -60.0)]), coming, PackedInt32Array([2]), null)
	_check(
		behind.mode == BotSteering.CLEAR and off_line.mode == BotSteering.CLEAR
			and far.mode == BotSteering.CLEAR and upstairs.mode == BotSteering.CLEAR,
		"a friend behind it, clear of its line, past its look ahead or on another floor is not in its way"
	)

	# A mesh one hull wide (the eroded floor of a doorway 40 across): no room.
	var slot := _mesh_of([[Vector3(-4.0, 0.0, 200.0), Vector3(4.0, 0.0, -200.0)]], [])
	var yield_to := BotSteering.steer(here, north, 5, ahead, coming, PackedInt32Array([2]), slot)
	var wait_for := BotSteering.steer(here, north, 2, ahead, coming, PackedInt32Array([5]), slot)
	_check(
		yield_to.mode == BotSteering.YIELD and yield_to.way.is_equal_approx(-north)
			and wait_for.mode == BotSteering.WAIT and wait_for.way == Vector3.ZERO,
		"with no room either side, the higher userid backs off and the lower holds (%d, %d)" % [yield_to.mode, wait_for.mode]
	)
	var standing := BotSteering.steer(here, north, 5, ahead, PackedVector3Array([Vector3.ZERO]), PackedInt32Array([2]), slot)
	_check(standing.mode == BotSteering.YIELD, "and the same for a friend standing there, so two held up never both wait")
	var wide := _mesh_of([[Vector3(-100.0, 0.0, 200.0), Vector3(100.0, 0.0, -200.0)]], [])
	_check(
		BotSteering.steer(here, north, 5, ahead, coming, PackedInt32Array([2]), wide).mode == BotSteering.SIDESTEP,
		"on a floor with room, it steps aside instead"
	)


# --- Meetings ---------------------------------------------------------------

## Two teammates head-on down a corridor, the way Sid saw them at the B
## doors: both get to the other's end in about the time one takes alone,
## without a jump or a half-second stood still, and the same commands give
## the same walk tick for tick. Making way costs no hull traces (CLAUDE.md
## asks for the count): it traces nothing, so a meeting traces about what
## walking alone does. Without making way (the control) the same meeting
## takes longer, which shows the check can see the difference.
func _test_head_on_in_a_corridor() -> void:
	var mesh := _corridor(LONG_CORRIDOR, WIDE)
	var near := LONG_CORRIDOR + Vector3(0.0, 0.0, -40.0)
	var far := LONG_CORRIDOR + Vector3(0.0, 0.0, -CORRIDOR_LENGTH + 40.0)

	var alone := await _walk(mesh, [near], [far], ["CT"], 20.0)
	var lone_ticks: int = alone["arrived_at"][0]
	var meeting := await _walk(mesh, [near, far], [far, near], ["CT", "CT"], 20.0)
	var again := await _walk(mesh, [near, far], [far, near], ["CT", "CT"], 20.0)
	var control := await _walk(mesh, [near, far], [far, near], ["CT", "CT"], 20.0, false)

	var margin := SimClock.ticks_in(1.5)
	var arrived: Array = meeting["arrived_at"]
	_check(
		lone_ticks > 0 and arrived[0] > 0 and arrived[1] > 0 and arrived[0] <= lone_ticks + margin and arrived[1] <= lone_ticks + margin,
		"head-on in a corridor, both get to the other end within 1.5 s of one walking it alone (%s ticks, alone %d)" % [arrived, lone_ticks]
	)
	_check(meeting["jumps"] == [0, 0], "neither jumps (%s)" % [meeting["jumps"]])
	_check(
		meeting["longest_stall"] < SimClock.ticks_in(0.5),
		"and neither stands still for half a second (the longest %d ticks)" % meeting["longest_stall"]
	)
	var lone_rate: float = float(alone["traces"]) / alone["bot_ticks"]
	var meeting_rate: float = float(meeting["traces"]) / meeting["bot_ticks"]
	var control_rate: float = float(control["traces"]) / control["bot_ticks"]
	_check(
		meeting_rate <= lone_rate * 1.05 and meeting_rate <= control_rate,
		"making way traces nothing itself: %.2f hull traces a bot a tick, against %.2f alone (the odd brush of hulls) and %.2f walking into each other"
			% [meeting_rate, lone_rate, control_rate]
	)
	var control_arrived: Array = control["arrived_at"]
	_check(
		control_arrived.has(-1) or control_arrived.max() > (arrived as Array).max(),
		"without making way the same meeting takes longer, only the wiggle getting them past (%s ticks against %s)" % [control_arrived, arrived]
	)
	_check(meeting["positions"] == again["positions"], "the same meeting twice walks the same, tick for tick")


## The same meeting on an open floor, at a diagonal to the axes.
func _test_head_on_at_a_diagonal() -> void:
	var mesh := _mesh_of([[DIAGONAL + Vector3(-400.0, 0.0, 400.0), DIAGONAL + Vector3(400.0, 0.0, -400.0)]], [])
	var one := DIAGONAL + Vector3(-300.0, 0.0, 300.0)
	var other := DIAGONAL + Vector3(300.0, 0.0, -300.0)
	var alone := await _walk(mesh, [one], [other], ["T"], 20.0)
	var meeting := await _walk(mesh, [one, other], [other, one], ["T", "T"], 20.0)
	var arrived: Array = meeting["arrived_at"]
	var lone_ticks: int = alone["arrived_at"][0]
	_check(
		arrived[0] > 0 and arrived[1] > 0 and arrived.max() <= lone_ticks + SimClock.ticks_in(1.5) and meeting["jumps"] == [0, 0],
		"head-on at a diagonal, both get past in about the lone time, without a jump (%s ticks, alone %d, %s jumps)"
			% [arrived, lone_ticks, meeting["jumps"]]
	)


## Walls 80 apart: room for the two to pass only once each has stepped to its
## wall.
func _test_head_on_with_just_room() -> void:
	var mesh := _corridor(NARROW, NARROW_WIDTH)
	var near := NARROW + Vector3(0.0, 0.0, -40.0)
	var far := NARROW + Vector3(0.0, 0.0, -CORRIDOR_LENGTH + 40.0)
	var alone := await _walk(mesh, [near], [far], ["CT"], 20.0)
	var meeting := await _walk(mesh, [near, far], [far, near], ["CT", "CT"], 20.0)
	var arrived: Array = meeting["arrived_at"]
	var lone_ticks: int = alone["arrived_at"][0]
	_check(
		arrived[0] > 0 and arrived[1] > 0 and arrived.max() <= lone_ticks + SimClock.ticks_in(2.0) and meeting["jumps"] == [0, 0],
		"in a corridor with just room to pass, both do, without a jump (%s ticks, alone %d, %s jumps)"
			% [arrived, lone_ticks, meeting["jumps"]]
	)


## Two rooms joined by a doorway 40 units wide and 64 deep, one hull at a
## time. Both head for the other room through it at once: one backs out
## and stands aside, the other comes through, then the first goes, and each
## jumps at most once.
func _test_a_doorway_one_hull_wide() -> void:
	var o := DOORWAY
	# The wall across, at z -400 to -464, with the gap at x -20 to 20.
	_box(o + Vector3(-400.0, 0.0, -464.0), o + Vector3(-20.0, 120.0, -400.0))
	_box(o + Vector3(20.0, 0.0, -464.0), o + Vector3(400.0, 120.0, -400.0))
	_side_walls(o, 400.0, 864.0)
	# Room, doorway, room; each rectangle [near corner, far corner], eroded.
	var mesh := _mesh_of([
		[o + Vector3(-384.0, 0.0, -16.0), o + Vector3(384.0, 0.0, -384.0)],
		[o + Vector3(-4.0, 0.0, -384.0), o + Vector3(4.0, 0.0, -480.0)],
		[o + Vector3(-384.0, 0.0, -480.0), o + Vector3(384.0, 0.0, -848.0)],
	], [[0, 1], [1, 2]])
	var one := o + Vector3(0.0, 0.0, -150.0)
	var other := o + Vector3(0.0, 0.0, -714.0)
	var meeting := await _walk(mesh, [one, other], [other, one], ["T", "T"], 30.0)
	var arrived: Array = meeting["arrived_at"]
	var jumps: Array = meeting["jumps"]
	_check(
		arrived[0] > 0 and arrived[1] > 0 and jumps[0] <= 1 and jumps[1] <= 1,
		"through a doorway one hull wide, one makes way and both get through (%s ticks, %s jumps)" % [arrived, jumps]
	)
	_check(meeting["yielded"].has(true), "and the one making way backs off to let the other through (%s)" % [meeting["yielded"]])


## A bot with a knife (250 units a second) behind one with a rifle (215)
## going the same way: it follows, never jumps, and gets there after it,
## taking the goal as reached with its teammate stood on it.
func _test_following_a_slower_teammate() -> void:
	var mesh := _corridor(FOLLOWING, WIDE)
	var front := FOLLOWING + Vector3(0.0, 0.0, -120.0)
	var back := FOLLOWING + Vector3(0.0, 0.0, -40.0)
	var goal := FOLLOWING + Vector3(0.0, 0.0, -CORRIDOR_LENGTH + 40.0)
	var walk := await _walk(mesh, [front, back], [goal, goal], ["CT", "CT"], 20.0, true, [WeaponLibrary.ak47(), null])
	var arrived: Array = walk["arrived_at"]
	_check(
		arrived[0] > 0 and arrived[1] > arrived[0] and walk["jumps"] == [0, 0],
		"a quicker bot behind a slower one follows it, never jumps, and gets there after it (%s ticks, %s jumps)"
			% [arrived, walk["jumps"]]
	)
	_check(walk["followed"][1], "following it rather than stepping round it")


## A teammate standing in the middle of the corridor, a player with no bot
## in it: the bot walks round it without a jump.
func _test_round_a_teammate_standing() -> void:
	var mesh := _corridor(STANDING, WIDE)
	var still := _new_player(STANDING + Vector3(0.0, 0.0, -400.0), "T")
	var near := STANDING + Vector3(0.0, 0.0, -40.0)
	var far := STANDING + Vector3(0.0, 0.0, -CORRIDOR_LENGTH + 40.0)
	var walk := await _walk(mesh, [near], [far], ["T"], 20.0, true, [], [still])
	_check(
		walk["arrived_at"][0] > 0 and walk["jumps"] == [0],
		"a teammate standing in its way it walks round, without a jump (%s ticks, %s jumps)" % [walk["arrived_at"], walk["jumps"]]
	)
	still.queue_free()
	await physics_frame


## An enemy standing in the way is not made way for: the steering leaves the
## bot on its line, since what it does about an enemy is the fight's.
func _test_an_enemy_is_not_made_way_for() -> void:
	var mesh := _corridor(ENEMIES, WIDE)
	var enemy := _new_player(ENEMIES + Vector3(0.0, 0.0, -400.0), "T")
	var near := ENEMIES + Vector3(0.0, 0.0, -40.0)
	var far := ENEMIES + Vector3(0.0, 0.0, -CORRIDOR_LENGTH + 40.0)
	var walk := await _walk(mesh, [near], [far], ["CT"], 3.0, true, [], [enemy])
	_check(
		walk["modes"][0].keys() == [BotSteering.CLEAR],
		"an enemy in the way is not made way for (the modes it took: %s)" % [walk["modes"][0].keys()]
	)
	enemy.queue_free()
	await physics_frame


## Walking straight at a wall the mesh does not know of (a lip, a prop): it
## wiggles first, and only after that jumps and finds its way again.
func _test_stuck_on_a_wall_it_wiggles_then_jumps() -> void:
	var mesh := _corridor(STUCK, WIDE)
	_box(STUCK + Vector3(-80.0, 0.0, -300.0), STUCK + Vector3(80.0, 120.0, -280.0))
	var near := STUCK + Vector3(0.0, 0.0, -40.0)
	var far := STUCK + Vector3(0.0, 0.0, -CORRIDOR_LENGTH + 40.0)
	var walk := await _walk(mesh, [near], [far], ["CT"], 4.0)
	var first_jump: int = walk["first_jump"][0]
	var first_wiggle: int = walk["first_wiggle"][0]
	_check(
		first_wiggle > 0 and first_jump > first_wiggle,
		"held up by a wall, it wiggles first (tick %d) and jumps only after (tick %d)" % [first_wiggle, first_jump]
	)


# --- Site goals -------------------------------------------------------------

## A side's first bot to a site goes to its middle, as before; the ones
## after go to spots spread round it, on the mesh, apart from each other.
func _test_site_goals_are_spread() -> void:
	var site := Vector3(0.0, 0.0, -300.0)
	var mesh := _mesh_of([[Vector3(-400.0, 0.0, 0.0), Vector3(400.0, 0.0, -600.0)]], [])
	var spawns := {"T": [{"position": Vector3(0.0, 0.0, 900.0)}, {"position": Vector3(40.0, 0.0, 900.0)}]}
	var sites := PackedVector3Array([site, Vector3(0.0, 0.0, -2000.0)])
	var goals := []
	for nth in [0, 2, 4]:
		goals.append(Competitive.bot_route(spawns, "T", nth, sites, mesh)[1])
	var apart := true
	for i in goals.size():
		for j in range(i + 1, goals.size()):
			apart = apart and (goals[i] as Vector3).distance_to(goals[j]) >= 64.0
	var on_mesh := true
	for goal: Vector3 in goals:
		on_mesh = on_mesh and mesh.area_at(goal) != null
	_check(
		(goals[0] as Vector3).is_equal_approx(site) and apart and on_mesh,
		"a side's first bot to a site goes to its middle, the next ones to spots round it, on the floor and at least 64 apart (%s)" % [goals]
	)
	_check_equal(
		Competitive.bot_route(spawns, "T", 2, sites, mesh), Competitive.bot_route(spawns, "T", 2, sites, mesh),
		"and the same bot is sent to the same spot every time"
	)
	_check_equal(Competitive.bot_route(spawns, "T", 2, sites)[1], site, "with no mesh to ask, the middle as before")


# --- Walking ------------------------------------------------------------------

## Bots from `starts` to `goals` over `mesh`, one a side each, in a world
## stepped by hand for up to `seconds`; each stands where it is once it
## arrives. What it returns, per bot: the tick it arrived (-1 if not), its
## jumps, the tick of its first jump and first wiggle, the modes it steered
## by, and whether it ever backed off or followed; and, over all of them:
## the longest a bot on its way stood still (under the stuck speed on the
## ground), the most hull traces one bot took in a tick, and every position,
## tick by tick. `others` are players already in the world, who join first.
func _walk(
	mesh: SourceNavMesh, starts: Array, goals: Array, teams: Array, seconds: float,
	makes_way: bool = true, guns: Array = [], others: Array = []
) -> Dictionary:
	var world := GameWorld.new()
	_world.add_child(world)
	for other: PlayerSim in others:
		world.add_player(other)
	var bots: Array[Bot] = []
	for i in starts.size():
		var bot := _scene.instantiate() as Bot
		bot.name = "Walker%d" % i
		bot.team = teams[i]
		bot.route = PackedVector3Array([starts[i], goals[i]])
		bot.nav_mesh = mesh
		bot.makes_way = makes_way
		bot.position = starts[i]
		_world.add_child(bot)
		world.add_player(bot)
		if i < guns.size() and guns[i] != null:
			bot.arm(guns[i])
		var to_goal: Vector3 = goals[i] - starts[i]
		bot.place(starts[i], rad_to_deg(atan2(-to_goal.x, -to_goal.z)))
		bot.set("_next", 1)
		bots.append(bot)

	var out := {
		"arrived_at": [], "jumps": [], "first_jump": [], "first_wiggle": [], "modes": [],
		"yielded": [], "followed": [], "longest_stall": 0, "most_traces": 0, "traces": 0, "bot_ticks": 0, "positions": [],
	}
	var stalled: Array[int] = []
	var was_on_ground: Array[bool] = []
	for bot in bots:
		out["arrived_at"].append(-1)
		out["jumps"].append(0)
		out["first_jump"].append(-1)
		out["first_wiggle"].append(-1)
		out["modes"].append({})
		out["yielded"].append(false)
		out["followed"].append(false)
		stalled.append(0)
		was_on_ground.append(true)

	for t in SimClock.ticks_in(seconds):
		var traces_before: Array[int] = []
		for bot in bots:
			traces_before.append(bot.traces)
		await physics_frame
		var tick_positions := PackedVector3Array()
		for i in bots.size():
			var bot := bots[i]
			tick_positions.append(bot.global_position)
			if out["arrived_at"][i] >= 0:
				continue
			out["most_traces"] = maxi(out["most_traces"], bot.traces - traces_before[i])
			out["traces"] += bot.traces - traces_before[i]
			out["bot_ticks"] += 1
			(out["modes"][i] as Dictionary)[bot.steering] = true
			if bot.steering == BotSteering.YIELD:
				out["yielded"][i] = true
			if bot.steering == BotSteering.FOLLOW:
				out["followed"][i] = true
			if out["first_wiggle"][i] < 0 and int(bot.get("_wiggle_until")) > world.tick:
				out["first_wiggle"][i] = world.tick
			if was_on_ground[i] and not bot.on_ground and bot.velocity.y > 100.0:
				out["jumps"][i] += 1
				if out["first_jump"][i] < 0:
					out["first_jump"][i] = world.tick
			was_on_ground[i] = bot.on_ground
			if bot.on_ground and Vector2(bot.velocity.x, bot.velocity.z).length() < BotSteering.MOVING:
				stalled[i] += 1
				out["longest_stall"] = maxi(out["longest_stall"], stalled[i])
			else:
				stalled[i] = 0
			if int(bot.get("_next")) != 1:
				out["arrived_at"][i] = world.tick
				# There, it stands where it is: no route, no walking.
				bot.route = PackedVector3Array()
		out["positions"].append(tick_positions)
		if not out["arrived_at"].has(-1):
			break

	for bot in bots:
		bot.queue_free()
	world.queue_free()
	await physics_frame
	return out


# --- Building the courses -------------------------------------------------------

## A corridor from `origin` going -Z, CORRIDOR_LENGTH long with walls `width`
## apart and closed at both ends, and its floor as a nav mesh.
func _corridor(origin: Vector3, width: float) -> SourceNavMesh:
	_side_walls(origin, width * 0.5, CORRIDOR_LENGTH)
	var inside := width * 0.5 - ERODED
	return _mesh_of([[origin + Vector3(-inside, 0.0, -ERODED), origin + Vector3(inside, 0.0, -CORRIDOR_LENGTH + ERODED)]], [])


## Walls either side of x = origin ± half, and across both ends, `length` long.
func _side_walls(origin: Vector3, half: float, length: float) -> void:
	_box(origin + Vector3(-half - 32.0, 0.0, -length), origin + Vector3(-half, 120.0, 0.0))
	_box(origin + Vector3(half, 0.0, -length), origin + Vector3(half + 32.0, 120.0, 0.0))
	_box(origin + Vector3(-half - 32.0, 0.0, 0.0), origin + Vector3(half + 32.0, 120.0, 32.0))
	_box(origin + Vector3(-half - 32.0, 0.0, -length - 32.0), origin + Vector3(half + 32.0, 120.0, -length))


## A nav mesh of flat rectangles, each [the corner at its near z and low x,
## the corner at its far z and high x], linked [i, j] from i's far z edge to
## j's near z edge and back. Edges run from corner i to i + 1: 0 the near z,
## 1 the high x, 2 the far z, 3 the low x.
func _mesh_of(rectangles: Array, links: Array) -> SourceNavMesh:
	var list: Array[SourceNavMesh.Area] = []
	for i in rectangles.size():
		var low: Vector3 = rectangles[i][0]
		var high: Vector3 = rectangles[i][1]
		var area := SourceNavMesh.Area.new()
		area.id = i + 1
		area.corners = PackedVector3Array([
			Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z),
			Vector3(high.x, low.y, high.z), Vector3(low.x, low.y, high.z),
		])
		area.edges = [[], [], [], []]
		list.append(area)
	for pair: Array in links:
		var forth := SourceNavMesh.Link.new()
		forth.area = pair[1] + 1
		forth.edge = 0
		(list[pair[0]].edges[2] as Array).append(forth)
		var back := SourceNavMesh.Link.new()
		back.area = pair[0] + 1
		back.edge = 2
		(list[pair[1]].edges[0] as Array).append(back)
	return SourceNavMesh.from_areas(list)


## A solid box of the world between two corners.
func _box(low: Vector3, high: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (high - low).abs()
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	body.global_position = (low + high) * 0.5


func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16384.0, 32.0, 16384.0)
	shape.shape = box
	shape.position = Vector3(0.0, -16.0, 0.0)
	floor_body.add_child(shape)
	_world.add_child(floor_body)


## A player with no bot in it, standing on the floor with a player's hull.
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
	return player
