extends "res://tests/check_suite.gd"

## Replay a quiet Dust2 round so objective behavior is independently
## observable: no bots shoot, but they use the real movement, nav mesh,
## inventories, planted-C4 and MatchState. Both teams must travel Long,
## a T must plant in the real brush, and a CT must complete a defuse.
func _initialize() -> void:
	var paths := MapPaths.of("de_dust2")
	if not FileAccess.file_exists(paths.nav_file) or not DirAccess.dir_exists_absolute(paths.collision_dir):
		_skip("dust2-objectives", "extracted Dust2 collision/nav is absent")
		return
	await process_frame
	seed(20261004)
	var scene := (load("res://maps/de_dust2/de_dust2.tscn") as PackedScene).instantiate() as PlayScene
	scene.game_mode = "Competitive"
	scene.spawn_team = "CT"
	scene.warmup_seconds = 120.0
	root.add_child(scene)
	var mode := scene.mode as Competitive
	var world := scene.world
	world.set_physics_process(false)
	for bot in mode.bots:
		bot.holds_fire = true
	await physics_frame
	mode.match_state.rules.freeze_seconds = 0.0
	mode.match_state.end_warmup_on_next_tick()
	var planted := false
	var defused := false
	var long_t := false
	var long_ct := false
	var gave_kits := false
	var use_ticks := 0
	var plant_at := Vector3.ZERO
	var planted_tick := -1
	var defused_tick := -1
	var lane: PackedVector3Array = mode.bots[0].round_plan.data["lanes"]["T"][0]
	var long_point := lane[-2]
	for tick in 64 * 75:
		world.step()
		if not gave_kits and mode.match_state.phase == MatchState.Phase.LIVE:
			for bot in mode.bots:
				if bot.team == "CT":
					bot.inventory.has_defuser = true
			gave_kits = true
		var bomb := mode.bomb_system.bomb
		if bomb.state == C4.State.PLANTED and not planted:
			planted = true
			plant_at = bomb.position
			planted_tick = tick
		defused = defused or bomb.state == C4.State.DEFUSED
		for bot in mode.bots:
			if bot.team == "CT" and bot.last_command.held(UserCmd.USE):
				use_ticks += 1
			if bot.position.distance_to(long_point) < 256.0:
				long_t = long_t or bot.team == "T"
				long_ct = long_ct or bot.team == "CT"
		if defused:
			defused_tick = tick
			break
	_check(long_t and long_ct, "both teams physically travel Long, not just receive a lane goal")
	_check(planted and mode.bomb_system.sites.any(func(site: BombSite) -> bool: return site.contains(plant_at)),
		"a bot plants inside the actual Dust2 bomb-target volume")
	_check(defused and use_ticks >= 64 * 5, "a CT retakes and holds a complete kit defuse through BombSystem")
	_check(mode.match_state.phase == MatchState.Phase.ROUND_END and mode.match_state.last_winner == "CT",
		"the defuse ends the round for CT through MatchState")
	print("Dust2 objectives: plant at %.2f s, defuse at %.2f s, %d use ticks" % [planted_tick / 64.0, defused_tick / 64.0, use_ticks])
	scene.free()
	await process_frame
	_finish("dust2-objectives")
