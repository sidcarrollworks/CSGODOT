extends "res://tests/check_suite.gd"

## Checks that a side of bots walking Competitive's site routes on the
## extracted dust2 never jams: five Ts, holding fire, walk from their spawn
## points to the sites and back for a minute of game, solid to each other as
## in CS2, and no bot's average speed over a second stays under the stuck
## speed for more than three seconds (reference/playtest-2026-09-25.md,
## issue 6; tests/run_bot_move_checks.gd checks the same on hand-built
## corridors, without the map).
##
##   godot --headless --path . --script tests/run_dust2_bot_checks.gd
##
## Needs dust2 and its nav mesh extracted (scripts/extract_assets.sh map,
## nav); it skips without them, as in CI.

const BOTS := 5
const TEAM := "T"
## A minute of game, and the most a bot may stand still in it.
const SECONDS := 60.0
const LONGEST_STALL_SECONDS := 3.0

var _world: GameWorld
var _bots: Array[Bot] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	# The tree takes nodes in from its first frame on: added in _initialize,
	# the loader has not read the map yet, and the check skipped as if dust2
	# were not extracted.
	await process_frame
	var loader := MapLoader.new()
	loader.map_name = "de_dust2"
	root.add_child(loader)
	var contents := loader.contents
	if loader.importer == null or contents.nav_mesh == null or not contents.has_both_sides():
		_skip("dust2_bots", "dust2 and its nav mesh have not been extracted; nothing to check.")
		return
	var sites := Competitive.site_floors(contents.nav_mesh, contents.places, contents.bomb_sites)
	_check(sites.size() == 2, "dust2's two sites are on its nav mesh (%s)" % sites)
	if sites.size() != 2:
		_finish("dust2_bots")
		return

	# A tick a physics step, eight a frame: the hulls meet as in the game.
	Engine.time_scale = 8.0
	_world = GameWorld.new()
	loader.add_child(_world)
	var scene := load("res://src/bots/bot.tscn") as PackedScene
	var spawns: Array = contents.spawns[TEAM]
	for i in BOTS:
		var bot := scene.instantiate() as Bot
		bot.name = "Walker%d" % i
		bot.team = TEAM
		bot.holds_fire = true
		bot.nav_mesh = contents.nav_mesh
		bot.route = Competitive.bot_route(contents.spawns, TEAM, i, sites, contents.nav_mesh)
		loader.add_child(bot)
		_world.add_player(bot)
		var spawn: Dictionary = spawns[i % spawns.size()]
		bot.place(spawn["position"], float(spawn.get("yaw", 0.0)))
		bot.set("_next", 1)
		_bots.append(bot)
	await physics_frame

	var window := SimClock.ticks_in(1.0)
	var longest_allowed := SimClock.ticks_in(LONGEST_STALL_SECONDS)
	var speeds: Array[PackedFloat32Array] = []
	var stalled: Array[int] = []
	var longest: Array[int] = []
	var where: Array[Vector3] = []
	for bot in _bots:
		var ring := PackedFloat32Array()
		ring.resize(window)
		ring.fill(1000.0)
		speeds.append(ring)
		stalled.append(0)
		longest.append(0)
		where.append(Vector3.ZERO)
	var jumps := 0
	for t in SimClock.ticks_in(SECONDS):
		var in_air_before: Array[bool] = []
		for bot in _bots:
			in_air_before.append(not bot.on_ground)
		await physics_frame
		for i in _bots.size():
			var bot := _bots[i]
			speeds[i][t % window] = Vector2(bot.velocity.x, bot.velocity.z).length()
			var total := 0.0
			for speed in speeds[i]:
				total += speed
			if total / window < Bot.STUCK_SPEED:
				stalled[i] += 1
				if stalled[i] > longest[i]:
					longest[i] = stalled[i]
					where[i] = bot.global_position
			else:
				stalled[i] = 0
			if not in_air_before[i] and not bot.on_ground and bot.velocity.y > 100.0:
				jumps += 1

	var worst := longest.max() as int
	var worst_bot := longest.find(worst)
	_check(
		worst <= longest_allowed,
		"five Ts walking dust2's site routes for a minute, solid to each other, never stand still for more than %.0f s (the longest %.1f s, %s at %s; %d jumps between them)"
			% [LONGEST_STALL_SECONDS, worst * SimClock.tick_seconds(), _bots[worst_bot].name, where[worst_bot].round(), jumps]
	)
	Engine.time_scale = 1.0
	loader.queue_free()
	await physics_frame
	_finish("dust2_bots")
