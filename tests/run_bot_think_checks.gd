extends "res://tests/check_suite.gd"

## Checks how the world asks for a tick's commands (GameWorld.commands_for):
## everyone's before anyone runs, each from the world as the last tick left
## it, and the bots' thought of on worker threads, all at once, to the same
## commands as on the thread that runs the tick. Eight bots, four a side,
## walk at each other round two walls and fight, none of them dying; the
## same fight is played with the bots thinking on the threads and in turn,
## and every bot is where it was, facing as it faced, having fired as
## often, at every tick.
##
##   godot --headless --path . --script tests/run_bot_think_checks.gd
##
## Needs nothing extracted, and the Box3D addon: on Godot's own physics the
## bots think in turn.

const A_SIDE := 4
const TICKS := 448


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
var _bots: Array[Bot] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	if not Box3DDrops.available():
		_skip("bot-think", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	await process_frame
	await _test_commands_first()
	var apart := await _play(true)
	var threads: Dictionary = apart["threads"]
	var in_turn := await _play(false)
	var turn_threads: Dictionary = in_turn["threads"]
	var main := OS.get_main_thread_id()
	_check(threads.size() > 1 and not threads.has(main),
		"thinking apart, eight bots think on worker threads, more than one of them (%d threads)" % threads.size())
	_check(turn_threads.size() == 1 and turn_threads.has(main),
		"thinking in turn, they think on the thread that runs the tick")
	_check(int(apart["shots"]) > 0 and float(apart["walked"]) > 50.0,
		"they walk and they fight (%d rounds between them, the first %.0f units from where it began)" % [apart["shots"], apart["walked"]])
	var a: PackedStringArray = apart["ticks"]
	var b: PackedStringArray = in_turn["ticks"]
	var differs := -1
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			differs = i
			break
	_check(a.size() == TICKS and b.size() == TICKS and differs < 0,
		"apart or in turn every bot is where it was, facing as it faced and has fired as often at every tick%s" % (
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


## The fight, with the bots thinking on the worker threads or in turn: what
## every bot was at every tick, the threads they thought on, the rounds
## they fired, how far the first walked, and the queries counted.
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
			bot.weapon_data = WeaponLibrary.ak47()
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
	await physics_frame
	var began := _bots[0].global_position
	var asked := PhysicsQueries.native_queries
	var ticks := PackedStringArray()
	var threads := {}
	for tick in TICKS:
		_world.step()
		var line := PackedStringArray()
		for bot in _bots:
			line.append("%s %.4f %.4f %.4f %.3f %.3f %d" % [
				bot.name, bot.global_position.x, bot.global_position.y, bot.global_position.z,
				bot.yaw_degrees, bot.pitch_degrees, bot.rounds_fired])
			threads[(bot as Noting).thought_on] = true
		ticks.append("; ".join(line))
	var shots := 0
	for bot in _bots:
		shots += bot.rounds_fired
	var out := {
		"ticks": ticks, "threads": threads, "shots": shots,
		"walked": _bots[0].global_position.distance_to(began),
		"queries": PhysicsQueries.native_queries - asked,
	}
	_host.free()
	await process_frame
	return out


## A floor of triangles, as a map's is, two walls between the sides with a
## gap between them, and the world on the native physics.
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


## A player made in code wears the hull a scene would give it.
func _hull(player: PlayerSim) -> void:
	player.collision_layer = 2
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(32.0, 72.0, 32.0)
	collision.shape = shape
	collision.position.y = 36.0
	player.add_child(collision)
