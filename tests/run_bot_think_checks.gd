extends "res://tests/check_suite.gd"

## Checks how the world asks for a tick's commands (GameWorld.commands_for):
## everyone's before anyone runs, each from the world as the last tick left
## it, and the bots' thought of on worker threads, all at once, to the same
## commands as on the thread that runs the tick. Eight bots, four a side,
## find their way over a nav mesh at each other through the gap between two
## walls and fight, none of them dying, one a side with a scoped rifle; a
## flash goes off before one side's faces and a smoke fills the gap. The
## same fight is played with the bots thinking on the threads and in turn,
## and every bot is where it was, facing as it faced, having fired as
## often, at every tick. And four thousand rays asked of the bridge from
## the worker threads at once meet what they meet asked one after another.
##
## What it does not play is a match: nobody buys, and no round is won. The
## dust2 walk (tests/run_dust2_bot_checks.gd) and the match on the native
## world (tests/run_box3d_match_checks.gd) run with the bots thinking on the
## threads, as the game does.
##
##   godot --headless --path . --script tests/run_bot_think_checks.gd
##
## Needs nothing extracted, and the Box3D addon: on Godot's own physics the
## bots think in turn.

const A_SIDE := 4
const TICKS := 448
## When the flash goes off before the Ts, and the smoke in the gap.
const FLASH_TICK := 96
const SMOKE_TICK := 192
const RAYS := 4096


## A bot that notes the thread it last thought on.
class Noting:
	extends Bot

	var thought_on := -1

	func think(tick: int, dt: float) -> UserCmd:
		thought_on = OS.get_thread_caller_id()
		return super(tick, dt)

	func think_apart(tick: int, dt: float) -> void:
		thought_on = OS.get_thread_caller_id()
		super(tick, dt)


## A player that notes, when it is asked for its command, where the one who
## runs before it stands.
class Watching:
	extends PlayerSim

	var watched: PlayerSim
	var saw: Array[Vector3] = []

	func command_for(tick: int, dt: float) -> UserCmd:
		saw.append(watched.global_position)
		return super(tick, dt)


## A player that walks forward.
class Walking:
	extends PlayerSim

	func command_for(tick: int, dt: float) -> UserCmd:
		var cmd := super(tick, dt)
		cmd.move = Vector2(0.0, 1.0)
		return cmd


var _host: Node3D
var _world: GameWorld
var _grenades: GrenadeSystem
var _mesh: SourceNavMesh
var _bots: Array[Bot] = []
var _space: PhysicsDirectSpaceState3D
var _rays: Array[PhysicsRayQueryParameters3D] = []
var _met: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run()


## Its passes say how much of each thing the fight had in it.
func _print_passes() -> bool:
	return true


func _run() -> void:
	if not Box3DDrops.available():
		_skip("bot-think", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	await process_frame
	await _test_commands_first()
	await _test_rays_together()
	var apart := await _play(true)
	var threads: Dictionary = apart["threads"]
	var in_turn := await _play(false)
	var turn_threads: Dictionary = in_turn["threads"]
	var main := OS.get_main_thread_id()
	# As many workers as the machine has cores, unless the project says.
	var configured := int(ProjectSettings.get_setting("threading/worker_pool/max_threads", -1))
	var workers := configured if configured > 0 else OS.get_processor_count()
	_check(threads.size() >= mini(2, workers) and not threads.has(main),
		"thinking apart, eight bots think on worker threads, more than one of them where there is more than one (%d threads of %d)" % [
			threads.size(), workers])
	_check(turn_threads.size() == 1 and turn_threads.has(main),
		"thinking in turn, they think on the thread that runs the tick")
	_check(int(apart["shots"]) > 0 and float(apart["walked"]) > 50.0,
		"they walk and they fight (%d rounds between them, the first %.0f units from where it began)" % [apart["shots"], apart["walked"]])
	_check(int(apart["blind"]) > 0 and int(apart["smoked"]) > 0 and int(apart["ways"]) == 2 * A_SIDE and int(apart["scoped"]) > 0,
		"with a flash that blinds (%d ticks of a bot blind), smoke in the way (%d ticks of a line through more than a bot sees through), a way found over the nav mesh by each (%d) and a scoped rifle fired (%d rounds)" % [
			apart["blind"], apart["smoked"], apart["ways"], apart["scoped"]])
	var a: PackedStringArray = apart["ticks"]
	var b: PackedStringArray = in_turn["ticks"]
	var differs := -1
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			differs = i
			break
	_check(a.size() == TICKS and b.size() == TICKS and differs < 0,
		"apart or in turn every bot is where it was, facing as it faced, its view as kicked, and has fired as often at every tick%s" % (
			"" if differs < 0 else " (tick %d: %s against %s)" % [differs, a[differs], b[differs]]))
	_check(int(apart["queries"]) == int(in_turn["queries"]) and int(apart["queries"]) > 0,
		"and as many queries are counted either way (%d and %d)" % [apart["queries"], in_turn["queries"]])
	_finish("bot-think")


## Everyone's command is asked for before anyone runs: the second player,
## asked, sees the first where the last tick left it, though the first runs
## before it and walks.
func _test_commands_first() -> void:
	_stage()
	var walker := Walking.new()
	walker.name = "Walker"
	var watcher := Watching.new()
	watcher.name = "Watcher"
	watcher.watched = walker
	for player: PlayerSim in [walker, watcher]:
		_hull(player)
		_host.add_child(player)
		_world.add_player(player)
	walker.place(Vector3(0.0, 1.0, 0.0), 0.0)
	watcher.place(Vector3(200.0, 1.0, 0.0), 0.0)
	await physics_frame
	var ends: Array[Vector3] = []
	for tick in 32:
		ends.append(walker.global_position)
		_world.step()
	var as_left := true
	for tick in 32:
		if not watcher.saw[tick].is_equal_approx(ends[tick]):
			as_left = false
	_check(as_left and walker.global_position.distance_to(ends[0]) > 20.0 and watcher.saw.size() == 32,
		"asked for its command, a player sees the one who runs before it where the last tick left it (it walked %.0f units)"
			% walker.global_position.distance_to(ends[0]))
	_host.free()
	await process_frame


## Rays asked of the bridge from the worker threads at once, while it is
## reading, as the bots' sight asks them: each meets what it meets asked by
## itself. Through the walls, the floor and eight hulls.
func _test_rays_together() -> void:
	_stage()
	for i in 8:
		var player := PlayerSim.new()
		player.name = "Stood%d" % i
		_hull(player)
		_host.add_child(player)
		_world.add_player(player)
		player.place(Vector3((i - 3.5) * 200.0, 1.0, -300.0 if i % 2 == 0 else 300.0), 0.0)
	await physics_frame
	_space = _host.get_world_3d().direct_space_state
	var queries := PhysicsQueries.for_space(_space)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260928
	_rays.clear()
	for i in RAYS:
		var from := Vector3(rng.randf_range(-1200.0, 1200.0), rng.randf_range(4.0, 120.0), rng.randf_range(-1200.0, 1200.0))
		var to := from + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.1), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(100.0, 2400.0)
		_rays.append(PhysicsRayQueryParameters3D.create(from, to, Hitscan.WORLD_LAYER | PlayerSim.PLAYER_LAYER))
	var alone := PackedStringArray()
	for i in RAYS:
		alone.append(_meeting(PhysicsQueries.intersect_ray(_space, _rays[i])))
	_met = PackedStringArray()
	_met.resize(RAYS)
	queries.begin_reading()
	var task := WorkerThreadPool.add_group_task(_ask, RAYS, -1, true, "Rays asked together")
	WorkerThreadPool.wait_for_group_task_completion(task)
	queries.end_reading()
	var differ := 0
	var hits := 0
	var hulls := 0
	for i in RAYS:
		if alone[i] != _met[i]:
			differ += 1
		if alone[i] != "":
			hits += 1
		if alone[i].begins_with("Stood"):
			hulls += 1
	_check(differ == 0 and hits > RAYS / 4 and hulls > 0,
		"%d rays asked from the worker threads at once meet what they meet asked one after another (%d meet something, %d of them a hull, %d differ)" % [
			RAYS, hits, hulls, differ])
	_rays.clear()
	_host.free()
	await process_frame


func _ask(index: int) -> void:
	# As the world has its thinkers ask (GameWorld._think_apart): nodes are
	# read, none written.
	Thread.set_thread_safety_checks_enabled(false)
	_met[index] = _meeting(PhysicsQueries.intersect_ray(_space, _rays[index]))
	Thread.set_thread_safety_checks_enabled(true)


## What a ray met, and where, to the ten-thousandth.
static func _meeting(hit: Dictionary) -> String:
	if hit.is_empty():
		return ""
	var at: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	return "%s %.4f %.4f %.4f %.3f %.3f %.3f" % [(hit["collider"] as Node).name, at.x, at.y, at.z, normal.x, normal.y, normal.z]


## The fight, with the bots thinking on the worker threads or in turn: what
## every bot was at every tick, the threads they thought on, the rounds
## they fired, how far the first walked, the queries counted, and how much
## of what a bot thinks with the fight had in it.
func _play(apart: bool) -> Dictionary:
	_stage()
	_world.think_on_threads = apart
	_bots.clear()
	var scene := load("res://src/bots/bot.tscn") as PackedScene
	for side: String in ["T", "CT"]:
		for i in A_SIDE:
			var bot := scene.instantiate() as Bot
			# The scene sets none of the script's variables.
			bot.set_script(Noting)
			bot.name = "%s%d" % [side, i]
			bot.team = side
			# One a side fires through a scope.
			bot.weapon_data = WeaponLibrary.build("weapon_awp") if i == 0 else WeaponLibrary.ak47()
			bot.nav_mesh = _mesh
			var z := -900.0 if side == "T" else 900.0
			var x := (i - 1.5) * 96.0
			# Across to where the other side starts and back: past the walls
			# and each other.
			bot.route = PackedVector3Array([Vector3(x, 1.0, z), Vector3(-x, 1.0, -z)])
			_host.add_child(bot)
			_world.add_player(bot)
			bot.place(Vector3(x, 1.0, z), 180.0 if side == "T" else 0.0)
			bot.set("_next", 1)
			# Its aim's error from who it is and when, as a spawn seeds it.
			bot.call("_seed_aim")
			bot.hit_target.immortal = true
			_bots.append(bot)
	# The bodies are posed on the tick, here, and not by the frames that
	# happen to be drawn: a body a frame further into its stride has its
	# hitboxes elsewhere, and a round that met one play's misses the
	# other's.
	_host.process_mode = Node.PROCESS_MODE_DISABLED
	await physics_frame
	var began := _bots[0].global_position
	var asked := PhysicsQueries.native_queries
	var ticks := PackedStringArray()
	var threads := {}
	var blind := 0
	var smoked := 0
	var found := {}
	for tick in TICKS:
		if tick == FLASH_TICK:
			# Before the Ts' faces, thrown by the other side.
			_set_off(GrenadeRules.FLASHBANG, _bots[1].global_position + Vector3(0.0, 56.0, 120.0), _bots[A_SIDE].userid)
		if tick == SMOKE_TICK:
			_set_off(GrenadeRules.SMOKE, Vector3(0.0, 1.0, 0.0), _bots[0].userid)
		_world.step()
		for bot in _bots:
			if bot.model != null and bot.model.is_animating():
				bot.model.step(SimClock.tick_seconds())
				if bot.model.character_rig != null:
					bot.model.character_rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		var line := PackedStringArray()
		for bot in _bots:
			var punch := bot.view_punch()
			line.append("%s %.4f %.4f %.4f %.3f %.3f %d %.3f %.3f" % [
				bot.name, bot.global_position.x, bot.global_position.y, bot.global_position.z,
				bot.yaw_degrees, bot.pitch_degrees, bot.rounds_fired, punch.x, punch.y])
			threads[(bot as Noting).thought_on] = true
			if bot.is_blind():
				blind += 1
			if bot.get("_path") != null:
				found[bot.name] = true
		for i in A_SIDE:
			var eyes := _bots[i].global_position + Vector3.UP * 64.0
			var theirs := _bots[A_SIDE + i].global_position + Vector3.UP * 64.0
			if float(_world.game.query(&"smoke_length_between", [eyes, theirs], 0.0)) > Bot.MAX_VISIBLE_SMOKE_LENGTH:
				smoked += 1
		ticks.append("; ".join(line))
	var shots := 0
	for bot in _bots:
		shots += bot.rounds_fired
	var out := {
		"ticks": ticks, "threads": threads, "shots": shots,
		"walked": _bots[0].global_position.distance_to(began),
		"queries": PhysicsQueries.native_queries - asked,
		"blind": blind, "smoked": smoked, "ways": found.size(),
		"scoped": _bots[0].rounds_fired + _bots[A_SIDE].rounds_fired,
	}
	_host.free()
	await process_frame
	return out


## A grenade of a kind set off at a point, as if it had come to rest there
## past its fuse: it goes off on the next tick or two.
func _set_off(weapon_class: String, at: Vector3, thrower: int) -> void:
	var space := _host.get_world_3d().direct_space_state
	var grenade := _grenades.throw_from(thrower, weapon_class, at, 0.0, -89.0, Vector3.ZERO, 0.0, space)
	grenade.flight.position = at
	grenade.flight.velocity = Vector3.ZERO
	grenade.flight.at_rest = weapon_class == GrenadeRules.SMOKE
	grenade.position = at
	grenade.thrown_usec = SimClock.now_usec() - 2_000_000 + SimClock.tick_usec()


## A nav mesh of the stage: each side's floor, and the gap between the
## walls that joins them.
static func _mesh_of_stage() -> SourceNavMesh:
	var rectangles := [
		[Vector3(-1024.0, 0.0, -1024.0), Vector3(1024.0, 0.0, -16.0)],
		[Vector3(-120.0, 0.0, -16.0), Vector3(120.0, 0.0, 16.0)],
		[Vector3(-1024.0, 0.0, 16.0), Vector3(1024.0, 0.0, 1024.0)],
	]
	var list: Array[SourceNavMesh.Area] = []
	for i in rectangles.size():
		var low: Vector3 = rectangles[i][0]
		var high: Vector3 = rectangles[i][1]
		var area := SourceNavMesh.Area.new()
		area.id = i + 1
		# Edges run from corner i to i + 1: 0 the near z, 2 the far z.
		area.corners = PackedVector3Array([
			Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z),
			Vector3(high.x, low.y, high.z), Vector3(low.x, low.y, high.z),
		])
		area.edges = [[], [], [], []]
		list.append(area)
	for pair: Array in [[0, 1], [1, 2]]:
		var forth := SourceNavMesh.Link.new()
		forth.area = pair[1] + 1
		forth.edge = 0
		(list[pair[0]].edges[2] as Array).append(forth)
		var back := SourceNavMesh.Link.new()
		back.area = pair[0] + 1
		back.edge = 2
		(list[pair[1]].edges[0] as Array).append(back)
	return SourceNavMesh.from_areas(list)


## A floor of triangles, as a map's is, two walls between the sides with a
## gap between them, the world on the native physics, its grenades, and a
## nav mesh of it.
func _stage() -> void:
	_host = Node3D.new()
	root.add_child(_host)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var faces := PackedVector3Array()
	for ix in range(-16, 16):
		for iz in range(-16, 16):
			var a := Vector3(ix * 128.0, 0.0, iz * 128.0)
			var b := a + Vector3(128.0, 0.0, 0.0)
			var c := a + Vector3(128.0, 0.0, 128.0)
			var d := a + Vector3(0.0, 0.0, 128.0)
			faces.append_array([a, b, c, a, c, d])
	var triangles := ConcavePolygonShape3D.new()
	triangles.set_faces(faces)
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = triangles
	ground.add_child(floor_shape)
	_host.add_child(ground)
	for x: float in [-420.0, 420.0]:
		var wall := StaticBody3D.new()
		wall.collision_layer = 1
		wall.collision_mask = 0
		wall.position = Vector3(x, 64.0, 0.0)
		var box := BoxShape3D.new()
		box.size = Vector3(600.0, 128.0, 32.0)
		var wall_shape := CollisionShape3D.new()
		wall_shape.shape = box
		wall.add_child(wall_shape)
		_host.add_child(wall)
	_world = GameWorld.new()
	_host.add_child(_world)
	_world.set_physics_process(false)
	_world.initialize_drop_physics(_host, "box3d")
	_grenades = GrenadeSystem.new()
	_world.game.add_system(_grenades)
	_mesh = _mesh_of_stage()


## A player made in code wears the hull a scene would give it.
func _hull(player: PlayerSim) -> void:
	player.collision_layer = 2
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(32.0, 72.0, 32.0)
	collision.shape = shape
	collision.position.y = 36.0
	player.add_child(collision)
