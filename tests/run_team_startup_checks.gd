extends "res://tests/check_suite.gd"

## The map and both possible players precede team select. Joining retains
## ready objects, starts the clock once, and keeps only the final roster.
## Needs no extracted map; models are checked too when locally available.

class AskingScene:
	extends PlayScene

	func _can_ask() -> bool:
		return true


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await _test_scene_prepares_before_select()
	for practice_mode in [false, true]:
		for side in ["T", "CT"]:
			await _test_prepared_join(side, practice_mode)
	await _test_auto_select()
	await _test_five_player_colours()
	await _test_team_camera_view()
	await _test_direct_start()
	await _test_headless_bypass()
	_finish("team-startup")


func _small_map() -> MapContents:
	var contents := MapContents.new()
	contents.name = "de_team_startup_fixture"
	contents.spawns = {
		"T": [{"position": Vector3(0.0, 8.0, 0.0), "yaw": 0.0, "priority": 0}],
		"CT": [{"position": Vector3(0.0, 8.0, -1024.0), "yaw": 180.0, "priority": 0}],
	}
	contents.buy_zones = Competitive.stand_in_buy_zones(contents.spawns)
	contents.bomb_sites = [BombSite.of_box("A", AABB(Vector3(128.0, 0.0, -512.0), Vector3(128.0, 100.0, 128.0)))]
	return contents


func _prepared_fixture(practice_mode: bool = false, team_count: int = 2, map_name: String = "de_team_startup_fixture") -> Array:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4096.0, 32.0, 4096.0)
	collision.shape = shape
	collision.position.y = -16.0
	floor_body.add_child(collision)
	fixture.add_child(floor_body)
	var world := GameWorld.new()
	world.set_physics_process(false)
	fixture.add_child(world)
	var mode := Competitive.new()
	mode.team_size = team_count
	mode.warmup_seconds = 1.0
	if practice_mode:
		mode.practice()
	fixture.add_child(mode)
	var contents := _small_map()
	contents.name = map_name
	mode.prepare_for_team_select(world, contents)
	world.initialize_drop_physics(fixture)
	world.make_bodies_now()
	return [fixture, world, mode]


func _test_scene_prepares_before_select() -> void:
	var scene := AskingScene.new()
	scene.map_name = "de_never_extracted"
	scene.game_mode = "Competitive"
	scene.spawn_team = "Ask"
	root.add_child(scene)
	await process_frame
	_check(scene.team_picker != null, "the selector appears after preparation")
	_check(scene.map != null and scene.map.contents.name == scene.map_name and scene.map.has_node(^"Floor"),
		"the map is loaded before team selection, including missing-map fallback")
	_check(scene.world != null and not scene.world.drop_physics_backend.is_empty(), "map collision physics is initialized before selection")
	_check(scene.mode != null and scene.mode.waiting_for_team, "both team choices are prepared before selection")
	_check(scene.get_viewport().get_camera_3d() == scene.mode.team_camera
		and scene.mode.team_camera != (scene.mode.player as PlayerController).camera,
		"a dedicated camera draws the loaded world behind the chooser")
	var loaded_map := scene.map
	var loaded_world := scene.world
	var candidates := scene.mode._team_choices.duplicate()
	for i in 4:
		await physics_frame
	_check_equal(scene.world.tick, 0, "selecting a team consumes no simulation ticks")
	scene.team_picker.choose("CT")
	_check(scene.map == loaded_map and scene.world == loaded_world, "clicking a side retains the loaded map and world")
	_check(scene.mode.player == candidates["CT"]["player"] and scene.mode.spawn_team == "CT",
		"clicking CT joins its already prepared player immediately")
	_check(scene.team_picker == null and not scene.mode.waiting_for_team, "the selector closes and joins in the same action")
	scene.queue_free()
	await process_frame


func _test_prepared_join(side: String, practice_mode: bool) -> void:
	var prepared := _prepared_fixture(practice_mode)
	var fixture := prepared[0] as Node3D
	var world := prepared[1] as GameWorld
	var mode := prepared[2] as Competitive
	var choice: Dictionary = mode._team_choices[side]
	var controller := choice["player"] as PlayerController
	var ready_hud := choice["hud"] as GameHud
	var ready_views := choice["views"] as Node3D
	var ready_model := controller.model
	var ready_body := controller.body_model
	var ready_shadow := controller.body_shadow
	var ready_arms := controller.view._view_models.duplicate()
	var ready_agent := ready_hud.buy_menu.agent
	var ready_camera := controller.camera.global_transform
	var preview_camera := mode.team_camera
	var other_controller := mode._team_choices[MatchState.other(side)]["player"] as PlayerController
	var other_id := other_controller.userid
	var scenes_before := RigModel._scenes.keys()
	_check(mode.match_state != null and mode.economy != null and mode.bomb_system != null,
		"%s %s: match and systems are ready before selection" % [side, practice_mode])
	for i in 4:
		await physics_frame
		await process_frame
		for bot in mode.bots:
			_check(bot.alive and bot.previous_position.is_equal_approx(bot.global_position),
				"%s %s: held bot %s has no respawn or origin-to-spawn interpolation" % [side, practice_mode, bot.name])
			if bot.model != null:
				_check(bot.model.global_position.is_equal_approx(bot.global_position),
					"%s %s: held bot %s and its shadow stay at the spawn" % [side, practice_mode, bot.name])
	_check_equal(world.tick, 0, "%s %s: world waits for the chooser" % [side, practice_mode])
	_check_equal(mode.match_state.phase_ends_usec, 0, "%s %s: no match countdown starts behind the chooser" % [side, practice_mode])
	_check_equal(_warmup_announcements(world), 0, "%s %s: preparation sends no warmup announcement" % [side, practice_mode])
	mode.join_team(side)
	_check_equal(_warmup_announcements(world), 1, "%s %s: joining announces warmup exactly once" % [side, practice_mode])
	_check(mode.team_camera == null and not preview_camera.is_inside_tree()
		and controller.get_viewport().get_camera_3d() == controller.camera,
		"%s %s: joining removes the preview camera and selects the ready player camera" % [side, practice_mode])
	_check(controller.camera.global_transform.is_equal_approx(ready_camera),
		"%s %s: preview framing never changes the player's spawn view" % [side, practice_mode])
	_check(mode.player == controller and mode.hud == ready_hud, "%s %s: retains the prepared controller and HUD" % [side, practice_mode])
	_check(controller.model == ready_model and controller.body_model == ready_body and controller.body_shadow == ready_shadow,
		"%s %s: joining rebuilds no player body or shadow" % [side, practice_mode])
	_check_equal(controller.view._view_models, ready_arms, "%s %s: joining retains the ready first-person models" % [side, practice_mode])
	_check_equal(RigModel._scenes.keys(), scenes_before, "%s %s: joining loads no model or animation resources" % [side, practice_mode])
	_check(ready_hud.buy_menu.agent == ready_agent and ready_hud._agent_team == side,
		"%s %s: the chosen buy-menu agent is already built" % [side, practice_mode])
	_check(world.players[0] == controller and mode.match_state.players[0] == controller,
		"%s %s: the local player runs first in world and match" % [side, practice_mode])
	_check(world.game.roster.player(other_id) == null and not other_controller.is_inside_tree(),
		"%s %s: the unused local player leaves the active roster immediately" % [side, practice_mode])
	var expected_players := 1 if practice_mode else 4
	_check_equal(world.players.size(), expected_players, "%s %s: final world roster has the intended size" % [side, practice_mode])
	_check_equal(world.game.roster.ids().size(), expected_players, "%s %s: economy/game roster has the same size" % [side, practice_mode])
	_check_equal(mode.match_state.players.size(), expected_players, "%s %s: match roster has the same size" % [side, practice_mode])
	_check_equal(mode.bots.size(), 0 if practice_mode else 3, "%s %s: only the required bots remain" % [side, practice_mode])
	if not practice_mode:
		for team in MatchState.SIDES:
			_check_equal(world.game.roster.on_team(team).size(), 2, "%s: %s has two players after joining" % [side, team])
	_check(ready_hud.player == controller and ready_hud.userid == controller.userid
		and ready_hud.damage_indicator.player == controller and ready_hud._damage_pawn == controller,
		"%s %s: HUD and damage callbacks retain the selected controller identity" % [side, practice_mode])
	var shots := ready_views.get_node(^"ShotEffects") as ShotEffects
	var rounds := ready_views.get_node(^"RoundSounds") as RoundSounds
	var hits := ready_views.get_node(^"HitSounds") as HitSounds
	var grenades := ready_views.get_node(^"GrenadeSounds") as GrenadeSounds
	_check(shots.you == controller and shots.listener_id == controller.userid and rounds.listener_id == controller.userid
		and hits.listener_id == controller.userid and grenades.listener_id == controller.userid,
		"%s %s: effects and audio follow the selected controller" % [side, practice_mode])
	_check(rounds.settings == controller.preferences.audio, "%s %s: selected audio uses the selected preferences" % [side, practice_mode])
	controller.global_position += Vector3(64.0, 0.0, 32.0)
	_check(ready_views.global_transform == Transform3D.IDENTITY,
		"%s %s: world effect positions stay fixed when the selected controller moves" % [side, practice_mode])
	_check_equal(mode.find_children("*", "GrenadeView", true, false).size(), 1,
		"%s %s: both choices share one world grenade presenter" % [side, practice_mode])
	_check_equal((world.game.events._listeners[&"fire_bullets"] as Array).size(), 1,
		"%s %s: unused shot presenter unlistens during teardown" % [side, practice_mode])
	_check_equal(mode.match_state.phase_ends_usec, 1000000, "%s %s: full warmup starts at the join" % [side, practice_mode])
	mode.join_team(MatchState.other(side))
	_check(mode.player == controller, "%s %s: repeated selections do not join twice" % [side, practice_mode])
	_check_equal(_warmup_announcements(world), 1, "%s %s: repeated selections do not restart warmup" % [side, practice_mode])
	for i in 4:
		await physics_frame
	_check(world.tick > 0, "%s %s: simulation runs after joining" % [side, practice_mode])
	_check(ready_hud.buy_menu.agent == ready_agent, "%s %s: the first active frame does not rebuild the buy agent" % [side, practice_mode])
	_check_equal(mode.economy.money(controller.userid), mode.economy.rules.warmup_money,
		"%s %s: the chosen player receives warmup money" % [side, practice_mode])
	fixture.queue_free()
	await process_frame


func _test_auto_select() -> void:
	var prepared := _prepared_fixture()
	var fixture := prepared[0] as Node3D
	var mode := prepared[2] as Competitive
	var picker := TeamPicker.new()
	fixture.add_child(picker)
	picker.chosen.connect(mode.join_team)
	picker.tick_down(TeamPicker.PICK_SECONDS)
	_check(mode.spawn_team in MatchState.SIDES and not mode.waiting_for_team,
		"countdown Auto Select joins one prepared team")
	_check((prepared[1] as GameWorld).players.size() == 4, "Auto Select keeps the intended final roster")
	fixture.queue_free()
	await process_frame


func _warmup_announcements(world: GameWorld) -> int:
	var count := 0
	for event in world.game.events.pending():
		if event.name == &"round_announce_warmup":
			count += 1
	return count


func _test_direct_start() -> void:
	for practice_mode in [false, true]:
		for side in MatchState.SIDES:
			var fixture := Node3D.new()
			root.add_child(fixture)
			var world := GameWorld.new()
			world.set_physics_process(false)
			fixture.add_child(world)
			var mode := Competitive.new()
			mode.spawn_team = side
			mode.team_size = 2
			if practice_mode:
				mode.practice()
			fixture.add_child(mode)
			mode.start(world, _small_map())
			_check_equal(_warmup_announcements(world), 1, "%s %s: direct startup announces warmup exactly once" % [side, practice_mode])
			fixture.queue_free()
			await process_frame


func _test_headless_bypass() -> void:
	for side in ["Ask", "T", "CT", "Auto"]:
		var scene := PlayScene.new()
		scene.map_name = "de_never_extracted"
		scene.game_mode = "Competitive"
		scene.spawn_team = side
		root.add_child(scene)
		_check(scene.team_picker == null and not scene.mode.waiting_for_team, "%s: headless startup bypasses team selection" % side)
		_check(scene.mode._team_choices.is_empty() and scene.world.players.size() == 1,
			"%s: direct startup builds only its chosen local player" % side)
		_check(scene.mode.team_camera == null, "%s: direct startup creates no preview camera" % side)
		_check(scene.mode.spawn_team == ("T" if side == "Ask" else side) if side != "Auto" else scene.mode.spawn_team in MatchState.SIDES,
			"%s: direct startup preserves side resolution" % side)
		scene.queue_free()
		await process_frame


func _test_team_camera_view() -> void:
	for map_name in ["de_dust2", "de_mirage"]:
		var prepared := _prepared_fixture(true, 2, map_name)
		var mode := prepared[2] as Competitive
		var controller := mode.player as PlayerController
		var camera := mode.team_camera
		if map_name == "de_dust2":
			_check(camera.global_position.is_equal_approx(Vector3(-573.7, 193.2, -1302.8)),
				"Dust2 chooser matches the supplied feet position plus the standing eye height")
			_check(camera.global_basis.is_equal_approx(Basis.from_euler(Vector3(deg_to_rad(3.3), deg_to_rad(220.4), 0.0))),
				"Dust2 chooser matches the supplied yaw and pitch")
		else:
			_check(camera.global_transform.is_equal_approx(controller.camera.global_transform),
				"maps without an authored chooser view use the prepared spawn view")
		_check(camera.cull_mask == controller.camera.cull_mask and camera.fov == controller.camera.fov
			and camera.near == controller.camera.near and camera.far == controller.camera.far,
			"%s: preview keeps the world projection and hidden-body cull mask" % map_name)
		(prepared[0] as Node3D).queue_free()
		await process_frame


func _test_five_player_colours() -> void:
	for selected in MatchState.SIDES:
		var prepared := _prepared_fixture(false, 5)
		var mode := prepared[2] as Competitive
		mode.join_team(selected)
		for side in MatchState.SIDES:
			var colours := {}
			for participant in mode.match_state.players:
				if participant.team == side:
					colours[mode.match_state.colour_of(participant)] = true
			_check_equal(colours.size(), 5, "joining %s: all five %s teammate colours remain unique" % [selected, side])
		(prepared[0] as Node3D).queue_free()
		await process_frame
