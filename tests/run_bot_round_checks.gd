extends "res://tests/check_suite.gd"

## Goals must produce real commands and complete through BombSystem, not
## mutate the bomb to simulate success. Worker and sequential thinking
## must agree. Navigation/lanes are also checked on extracted Dust2.
var _host: Node3D
var _world: GameWorld
var _bomb: BombSystem
var _data: Dictionary

class BarePlayer extends PlayerSim:
	func _ready() -> void:
		inventory = Inventory.new()

func _initialize() -> void:
	await process_frame
	_test_assignments()
	await _test_objectives(false)
	await _test_objectives(true)
	await _test_memory_and_routes()
	_test_dust2_lanes()
	_finish("bot-round")

func _test_assignments() -> void:
	var a := BarePlayer.new()
	var b := BarePlayer.new()
	var human := BarePlayer.new()
	a.is_bot = true
	b.is_bot = true
	for player in [a, b, human]:
		root.add_child(player)
	a.team = "CT"
	b.team = "CT"
	human.team = "CT"
	a.userid = 1
	b.userid = 2
	human.userid = 3
	a.position = Vector3(10, 0, 0)
	b.position = Vector3(100, 0, 0)
	b.inventory = Inventory.new()
	a.inventory = Inventory.new()
	b.inventory.has_defuser = true
	var players: Array[PlayerSim] = [a, b, human]
	_check_equal(BotRoundPlan.assigned(players, "CT", Vector3.ZERO, -1, true), 2, "a nearby kit carrier is preferred")
	_check_equal(BotRoundPlan.assigned(players, "CT", Vector3.ZERO, 3, true), 3, "an active human defuser keeps the assignment")
	b.alive = false
	_check_equal(BotRoundPlan.assigned(players, "CT", Vector3.ZERO, 2, true), 1, "a dead defuser is replaced")
	a.controlled_by = human
	_check_equal(BotRoundPlan.assigned(players, "CT", Vector3.ZERO), -1, "a controlled bot is left to its human")
	human.team = "T"
	_check(BotRoundPlan.defers(players, true), "a living human T owns the objective")
	human.alive = false
	_check(not BotRoundPlan.defers(players, true), "bots recover the objective after the human dies")
	for player in players:
		player.free()

func _stage(apart: bool) -> void:
	_host = Node3D.new()
	root.add_child(_host)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(2000, 16, 2000)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = -8.0
	ground.add_child(collision)
	_host.add_child(ground)
	_world = GameWorld.new()
	_host.add_child(_world)
	_world.set_physics_process(false)
	_world.think_on_threads = apart
	_world.initialize_drop_physics(_host, "box3d")
	var site := BombSite.of_box("A", AABB(Vector3(-100, -1, -100), Vector3(200, 100, 200)))
	_bomb = BombSystem.new([site])
	_world.game.add_system(_bomb)
	var state := MatchState.new()
	_host.add_child(state)
	state.phase = MatchState.Phase.LIVE
	state.round_number = 1
	state.phase_ends_usec = 1_000_000_000
	_world.match_state = state
	_data = {"sites": PackedVector3Array([Vector3.ZERO]),
		"plant_sites": PackedVector3Array([Vector3.ZERO]),
		"lanes": {"T": [PackedVector3Array([Vector3.ZERO])], "CT": [PackedVector3Array([Vector3(300, 0, 0)])]},
		"search": PackedVector3Array([Vector3(400, 0, 0), Vector3(-400, 0, 0)]),
		"enemy_spawn": {"T": Vector3(800, 0, 0), "CT": Vector3(-800, 0, 0)}}

func _bot(side: String, at: Vector3, slot: int = 0) -> Bot:
	var bot := (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	bot.team = side
	bot.holds_fire = true
	bot.respawns = false
	_host.add_child(bot)
	_world.add_player(bot)
	bot.place(at + Vector3.UP, 30.0)
	bot.round_plan = BotRoundPlan.new(_bomb, _data, slot)
	return bot

func _test_objectives(apart: bool) -> void:
	_stage(apart)
	var planter := _bot("T", Vector3(40, 0, 0))
	var ct := _bot("CT", Vector3(500, 0, 0))
	ct.inventory.has_defuser = true
	await physics_frame
	_bomb.give_to(planter.userid)
	var commands := 0
	for i in 64 * 8:
		_world.step()
		if planter.last_command.held(UserCmd.ATTACK) and planter.in_hand_class() == "weapon_c4":
			commands += 1
		if _bomb.bomb.state == C4.State.PLANTED:
			break
	_check(_bomb.bomb.state == C4.State.PLANTED and commands > 100, "bot equips and holds a real plant (%s thinking)" % ("worker" if apart else "sequential"))
	var held := 0
	for i in 64 * 12:
		_world.step()
		if ct.last_command.held(UserCmd.USE):
			held += 1
		if _bomb.bomb.state == C4.State.DEFUSED:
			break
	_check(_bomb.bomb.state == C4.State.DEFUSED and held >= 64 * 5, "CT travels, aims down and completes a real kit defuse (%s; %d use ticks)" % ["worker" if apart else "sequential", held])
	_check(ct.position.distance_to(_bomb.bomb.position) < BotRoundPlan.USE_DISTANCE + 1.0, "defuse occurs at the bomb, not remotely")
	_host.free()
	await process_frame

func _test_memory_and_routes() -> void:
	_stage(false)
	var hunter := _bot("CT", Vector3.ZERO)
	var enemy := _bot("T", Vector3(800, 0, 0))
	hunter.last_enemy_position = Vector3(200, 0, -200)
	hunter.last_enemy_tick = 1
	hunter.round_plan.update(hunter, 2)
	_check_equal(hunter.round_plan.task, BotRoundPlan.Task.HUNT, "a seen enemy changes the opening goal")
	_check_equal(hunter.route[-1], Vector3(200, 0, -200), "the remembered pose is pursued")
	enemy.position = Vector3(-800, 0, -800)
	hunter.round_plan.update(hunter, 34)
	_check_equal(hunter.route[-1], Vector3(200, 0, -200), "hidden enemy movement does not move the goal")
	hunter.round_plan.update(hunter, 700)
	hunter.set_round_route(PackedVector3Array([Vector3(10, 0, 0)]))
	hunter._arrive()
	_check(hunter.round_goal_reached and hunter.route.size() == 1, "round routes stop at their final goal")
	hunter.round_plan.update(hunter, 740)
	_check(not hunter.round_goal_reached and hunter.route[-1] != Vector3(10, 0, 0), "after searching a point it chooses another area")
	_bomb.bomb.state = C4.State.DROPPED
	_bomb.bomb.position = Vector3(100, 0, 100)
	var human := PlayerSim.new()
	human.team = "T"
	_host.add_child(human)
	_world.add_player(human)
	enemy.round_plan.update(enemy, 741)
	_check(enemy.round_plan.task != BotRoundPlan.Task.PICKUP, "a living human T is left the dropped bomb")
	human.alive = false
	enemy.round_plan.update(enemy, 780)
	_check_equal(enemy.round_plan.task, BotRoundPlan.Task.PICKUP, "after the human dies a bot goes to recover it")
	_host.free()
	await process_frame

func _test_dust2_lanes() -> void:
	var paths := MapPaths.of("de_dust2")
	if not FileAccess.file_exists(paths.nav_file):
		print("Dust2 lane check skipped: extracted nav mesh is absent")
		return
	var map := MapContents.new()
	map.name = "de_dust2"
	map.nav_mesh = SourceNavMesh.load_file(paths.nav_file)
	var entities := SourceEntities.parse(paths.entity_models_dir.path_join("default_ents.vents"))
	map.places = SourceEntities.places(entities)
	map.spawns = SourceEntities.player_spawns(entities)
	map.bomb_sites = BombSite.from_volumes(BrushVolume.bomb_sites(entities, paths.map_dir))
	var sites := Competitive.site_floors(map.nav_mesh, map.places, [])
	var data := BotRoundMap.prepare(map, sites)
	_check((data["plant_sites"] as PackedVector3Array).size() == map.bomb_sites.size(), "each actual plant volume has a navigable goal")
	for i in map.bomb_sites.size():
		_check(map.bomb_sites[i].contains(data["plant_sites"][i]), "plant goal is inside %s's func_bomb_target" % map.bomb_sites[i].letter)
	var long_floor: Vector3 = Competitive._floor_under(map.nav_mesh, map.places["LongA"][0], 300.0)
	for side in ["T", "CT"]:
		var lane: PackedVector3Array = data["lanes"][side][0]
		_check(lane.has(long_floor), "%s has an opening through Long" % side)
		for opening: PackedVector3Array in data["lanes"][side]:
			var here: Vector3 = map.spawns[side][0]["position"]
			for goal in opening:
				var path := map.nav_mesh.walk_path(here, goal)
				_check(not path.is_empty(), "%s lane has a nav path from %s to %s" % [side, here, goal])
				here = goal
