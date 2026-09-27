extends "res://tests/check_suite.gd"

## Target-search ordering and live inputs, without extracted assets. The
## visibility checks use the real map-ray facade; the smoke provider supplies
## controlled lengths (real grenade smoke/flash checks live in bot-sight).

var _stage: Node3D
var _world: GameWorld
var _watcher: Bot
var _far: Bot
var _middle: Bot
var _near: Bot
var _friend: Bot
var _smoked: Bot
var _smoke_checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await physics_frame
	_stage = Node3D.new()
	root.add_child(_stage)
	_world = GameWorld.new()
	_stage.add_child(_world)
	_world.set_physics_process(false)
	_world.game.provide(&"smoke_length_between", _smoke_length)
	_watcher = _bot("T", Vector3.ZERO)
	_watcher.arm(WeaponLibrary.ak47())
	# Deliberately join farthest first: the search must preserve the nearest
	# result while avoiding rays to all earlier, farther roster entries.
	_far = _bot("CT", Vector3(0, 0, -700))
	_middle = _bot("CT", Vector3(-150, 0, -400))
	_near = _bot("CT", Vector3(100, 0, -200))
	_friend = _bot("T", Vector3(0, 0, -50))
	await physics_frame
	_check_nearest_and_ties()
	await _check_wall_and_smoke()
	_check_range_and_cone()
	_check_reaction_each_tick()
	_check_path_and_teammate_inputs()
	var game := _world.game
	_stage.free()
	for system in game.systems():
		if system is ItemDrops:
			system.game = null
	game.last_tick = null
	_finish("bot-target")


func _bot(side: String, at: Vector3) -> Bot:
	var bot := (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
	bot.team = side
	bot.holds_fire = true
	_stage.add_child(bot)
	_world.add_player(bot)
	bot.place(at, 0.0)
	return bot


func _casts() -> int:
	return PhysicsQueries.native_queries + PhysicsQueries.legacy_queries


func _check_nearest_and_ties() -> void:
	var before := _casts()
	_check(_watcher._look_for_target() == _near,
		"the nearest visible enemy wins despite joining after farther enemies")
	_check(_casts() - before == 1,
		"one clear nearest enemy needs one world ray, regardless of roster distance order")
	_near.place(Vector3(100, 0, -300), 0.0)
	_middle.place(Vector3(-100, 0, -300), 0.0)
	_check(_watcher._look_for_target() == _middle,
		"exact-distance ties preserve the first visible enemy in roster order")
	_world.players.erase(_near)
	_world.players.insert(1, _near)
	_check(_watcher._look_for_target() == _near,
		"a changed roster order changes the tie winner immediately")
	_near.alive = false
	_check(_watcher._look_for_target() == _middle,
		"a nearer teammate and a dead enemy are ineligible")
	_near.alive = true


func _check_wall_and_smoke() -> void:
	_near.place(Vector3(-150, 0, -200), 0.0)
	_middle.place(Vector3(150, 0, -400), 0.0)
	var wall := StaticBody3D.new()
	wall.position = Vector3(-75, 64, -100)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 128, 16)
	collision.shape = box
	wall.add_child(collision)
	_stage.add_child(wall)
	await physics_frame
	var before := _casts()
	_smoke_checks = 0
	_check(_watcher._look_for_target() == _middle,
		"a wall hiding the nearest enemy leaves the next visible enemy eligible")
	_check(_casts() - before == 2 and _smoke_checks == 1,
		"blocked sight uses its ray, but only an unobstructed candidate tests smoke")
	wall.free()
	await physics_frame
	_smoked = _near
	before = _casts()
	_smoke_checks = 0
	_check(_watcher._look_for_target() == _middle,
		"smoke hiding the nearest enemy leaves the next clear enemy eligible")
	_check(_casts() - before == 2 and _smoke_checks == 2,
		"nearest-first visibility retains smoke checks for each unobstructed candidate")
	_smoked = null
	_check(_watcher._look_for_target() == _near,
		"clearing smoke changes the selected enemy on the next search")


func _check_range_and_cone() -> void:
	_middle.place(Vector3(0, 0, 500), 0.0)
	_far.place(Vector3(0, 0, 700), 0.0)
	_near.place(Vector3(0, 0, -Bot.SIGHT_RANGE), 0.0)
	_check(_watcher._look_for_target() == null,
		"the target search retains its strict feet-distance range limit")
	_near.place(Vector3(0, 0, -Bot.SIGHT_RANGE + 1), 0.0)
	_check(_watcher._look_for_target() == _near and _watcher.can_see(_near),
		"search and direct visibility agree just inside the range")
	_near.place(Vector3(sin(deg_to_rad(74.9)), 0, -cos(deg_to_rad(74.9))) * 500, 0.0)
	_check(_watcher._look_for_target() == _near and _watcher.can_see(_near),
		"the outer edge inside the existing sight cone stays visible")
	_near.place(Vector3(sin(deg_to_rad(75.1)), 0, -cos(deg_to_rad(75.1))) * 500, 0.0)
	var before := _casts()
	_check(_watcher._look_for_target() == null and not _watcher.can_see(_near),
		"an enemy just outside the sight cone stays hidden")
	_check(_casts() == before, "cone rejection still avoids all world rays")


func _check_reaction_each_tick() -> void:
	_near.place(Vector3(0, 0, -200), 0.0)
	_watcher.holds_fire = false
	_watcher._seen_for = 0.0
	var reaction_ticks := SimClock.ticks_in(Bot.REACTION_SECONDS)
	var early_fire := false
	for tick in range(1, reaction_ticks):
		var cmd := _watcher.command_for(tick, SimClock.tick_seconds())
		early_fire = early_fire or (cmd.buttons & UserCmd.ATTACK != 0)
	_check(not early_fire and _watcher.target == _near,
		"a visible target is tracked each tick without firing before the reaction delay")
	var ready := _watcher.command_for(reaction_ticks, SimClock.tick_seconds())
	_check(ready.buttons & UserCmd.ATTACK != 0, "the existing reaction tick still starts automatic fire")
	_smoked = _near
	var hidden := _watcher.command_for(reaction_ticks + 1, SimClock.tick_seconds())
	_check(_watcher.target == null and hidden.buttons & UserCmd.ATTACK == 0,
		"smoke appearing on the next tick immediately stops acquisition and fire")
	_smoked = null
	var seen := _watcher.command_for(reaction_ticks + 2, SimClock.tick_seconds())
	_check(_watcher.target == _near and seen.buttons & UserCmd.ATTACK == 0,
		"cleared sight reacquires on the next tick and restarts the reaction delay")


func _check_path_and_teammate_inputs() -> void:
	var low := _area(Vector3.ZERO, SourceNavMesh.FLAG_CROUCH)
	var ordinary := _area(Vector3.ZERO, 0)
	var first := SourceNavMesh.WalkPath.new()
	first.areas.assign([ordinary, low])
	_watcher._path = first
	_check(_watcher._under_low_ceiling(), "a crouch area on the path is detected near the bot")
	_watcher.position.x = 400
	_check(not _watcher._under_low_ceiling(), "cached crouch areas still use the current position")
	_watcher.position = Vector3(0, 80, 0)
	_check(not _watcher._under_low_ceiling(), "a crouch area on another floor does not force ducking")
	_watcher.position = Vector3.ZERO
	var second := SourceNavMesh.WalkPath.new()
	second.areas.assign([ordinary])
	_watcher._path = second
	_check(not _watcher._under_low_ceiling(), "a replacement path does not retain old crouch areas")
	_watcher._path = null
	_watcher._path = first
	_check(_watcher._under_low_ceiling(), "finding the former path again restores its crouch requirement")
	_friend.position = Vector3(0, 0, -30)
	var earlier := _watcher._friends()
	_friend.position.x = 64
	var later := _watcher._friends()
	_check((earlier[0] as PackedVector3Array)[0] == Vector3(0, 0, -30)
		and (later[0] as PackedVector3Array)[0] == _friend.position,
		"teammate snapshots are independent and see movement from earlier in the same tick")


func _area(at: Vector3, flags: int) -> SourceNavMesh.Area:
	var area := SourceNavMesh.Area.new()
	area.flags = flags
	area.centre = at
	area.corners = PackedVector3Array([
		at + Vector3(-32, 0, -32), at + Vector3(32, 0, -32),
		at + Vector3(32, 0, 32), at + Vector3(-32, 0, 32),
	])
	return area


func _smoke_length(_from: Vector3, to: Vector3) -> float:
	_smoke_checks += 1
	if _smoked != null and to.is_equal_approx(_smoked.global_position + Vector3.UP * _smoked.eye_height()):
		return Bot.MAX_VISIBLE_SMOKE_LENGTH + 1.0
	return 0.0
