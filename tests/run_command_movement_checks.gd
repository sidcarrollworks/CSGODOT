extends "res://tests/run_crouch_movement_checks.gd"

## Binary-derived command selectors and real, parity-checked ground moves.
## Expected speeds/scales below are worked values, not production helpers.
var _player: Pawn
var _world: GameWorld
var _host: Node3D


func _run() -> void:
	await physics_frame
	_host = Node3D.new()
	root.add_child(_host)
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -8.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4096.0, 16.0, 4096.0)
	shape.shape = box
	floor_body.add_child(shape)
	_host.add_child(floor_body)
	_world = GameWorld.new()
	_host.add_child(_world)
	_world.set_physics_process(false)
	_world.set_process(false)
	_player = Pawn.new()
	_player.position = Vector3(0.0, 8.0, 0.0)
	_host.add_child(_player)
	_world.add_player(_player)
	await physics_frame
	_check(_world.initialize_drop_physics(_host, "box3d"), "command fixture initializes Box3D")
	for i in 80:
		_command(_player, 0, false)
	_test_command_scales()
	_test_walk_gate_and_tag()
	_test_taper_boundaries()
	_test_ground_intervals()
	if PlayerBody.native_installed():
		_check(PlayerBody.native_built(), "command checks use a mover built from these sources")
		_check(PlayerBody.steps_checked > 100, "walking/scoped checks actually compare native and script steps")
	_world.remove_player(_player)
	_player.free()
	_world.game.entities.clear()
	_world.game.last_tick = null
	for system in _world.game.systems():
		if system is ItemDrops or system is KillCredit:
			system.game = null
	_host.free()
	await process_frame
	_finish("command-movement")


func _equip(item: String, zoom: int = 0) -> void:
	_player.equip(WeaponLibrary.build(item))
	_player.weapon.zoom_level = zoom
	_player.velocity = Vector3.ZERO
	_player.on_ground = true
	_player.is_ducked = false
	_player.duck_progress = 0.0
	_player.velocity_modifier = 1.0


func _test_command_scales() -> void:
	# item, zoom, buttons, duck amount, command cap, acceleration scale
	var samples := [
		["weapon_ak47", 0, 0, 0.0, 215.0, 215.0],
		["weapon_ak47", 0, UserCmd.WALK, 0.0, 111.8, 130.0],
		["weapon_ak47", 0, UserCmd.DUCK, 1.0, 73.1, 85.0],
		["weapon_ak47", 0, UserCmd.DUCK | UserCmd.WALK, 1.0, 73.1, 85.0],
		["weapon_ak47", 0, UserCmd.WALK, 0.5, 144.05, 85.0],
		["weapon_awp", 1, 0, 0.0, 100.0, 100.0],
		["weapon_awp", 1, UserCmd.WALK, 0.0, 52.0, 100.0],
		["weapon_awp", 2, UserCmd.WALK, 0.0, 52.0, 100.0],
		["weapon_awp", 1, UserCmd.DUCK, 1.0, 34.0, 85.0],
		["weapon_aug", 1, 0, 0.0, 150.0, 150.0],
		["weapon_aug", 1, UserCmd.WALK, 0.0, 78.0, 130.0],
		["weapon_aug", 1, UserCmd.DUCK, 1.0, 51.0, 85.0],
		["weapon_ssg08", 1, UserCmd.WALK, 0.0, 119.6, 130.0],
		["weapon_scar20", 1, UserCmd.WALK, 0.0, 62.4, 120.0],
	]
	for sample: Array in samples:
		_equip(sample[0], sample[1])
		_player.duck_progress = sample[3]
		var cmd := UserCmd.new()
		cmd.buttons = sample[2]
		_player.wish_speed = _player._max_speed(cmd)
		var label := "%s zoom %d buttons %d duck %.1f" % [sample[0], sample[1], sample[2], sample[3]]
		_check_near(_player.wish_speed, sample[4], label + ": command cap")
		_check_near(_player._ground_acceleration_speed(cmd), sample[5], label + ": acceleration scale")


func _test_walk_gate_and_tag() -> void:
	_equip("weapon_ak47")
	var cmd := UserCmd.new()
	cmd.buttons = UserCmd.WALK
	for sample: Array in [[136.799, 111.8], [136.8, 215.0], [200.0, 215.0]]:
		_player.velocity = Vector3.RIGHT * sample[0]
		_check_near(_player._max_speed(cmd), sample[1], "walk entry gate at %.3f u/s" % sample[0])
	_player.velocity = Vector3(100.0, 100.0, 0.0)
	_check_near(_player._max_speed(cmd), 215.0, "walk gate uses full velocity magnitude")
	_player.velocity = Vector3.ZERO
	_player.velocity_modifier = 0.4
	cmd.buttons = 0
	_player.wish_speed = _player._max_speed(cmd)
	_check_near(_player.wish_speed, 86.0, "ground tag reduces command cap")
	_check_near(_player._ground_acceleration_speed(cmd), 215.0, "ground tag leaves weapon acceleration ratio alone")
	_player.on_ground = false
	_check_near(_player._max_speed(cmd), 215.0, "air command cap does not apply grounded tagging")
	cmd.buttons = UserCmd.DUCK
	_player.duck_progress = 1.0
	_check_near(_player._max_speed(cmd), 215.0, "air crouch leaves wish speed alone")
	_equip("weapon_ak47")


func _test_taper_boundaries() -> void:
	for sample: Array in [[-200.0, 1.0], [0.0, 1.0], [106.8, 1.0], [109.3, 0.5], [111.8, 0.0], [200.0, 0.0]]:
		_check_near(MovementSolver.walk_acceleration_fraction(sample[0], 111.8), sample[1],
			"walk taper at projected %.1f u/s" % sample[0])


func _test_ground_intervals() -> void:
	# No friction: isolate the accelerator from rest, halfway through its
	# taper, at the goal, and while counter-strafing. The cap must also clamp
	# an entire perpendicular vector and coasting velocity with no input.
	_player.config.friction = 0.0
	for sample: Array in [
		["weapon_ak47", 0, 0.0, 11.171875],
		["weapon_ak47", 0, 109.3, 111.8],
		["weapon_ak47", 0, 111.8, 111.8],
		["weapon_ak47", 0, -50.0, -38.828125],
		["weapon_awp", 1, 0.0, 8.59375],
		["weapon_awp", 1, 49.5, 52.0],
		["weapon_aug", 1, 0.0, 11.171875],
	]:
		_equip(sample[0], sample[1])
		_player.velocity = Vector3.RIGHT * sample[2]
		var start := _player.position.x
		_command(_player, UserCmd.WALK, true)
		var label := "%s scoped %d, from %.1f" % [sample[0], sample[1], sample[2]]
		_check_near(_player.velocity.x, sample[3], label + ": end speed")
		_check_near(_player.position.x - start, (sample[2] + sample[3]) * 0.5 * DT,
			label + ": midpoint displacement")
	_equip("weapon_ak47")
	_player.config.accelerate = 1.0
	_player.velocity = Vector3.RIGHT * 109.3
	_command(_player, UserCmd.WALK, true)
	_check_near(_player.velocity.x, 110.315625, "half taper scales actual acceleration below the cap")
	_player.config.accelerate = 5.5
	_equip("weapon_ak47")
	_player.velocity = Vector3.RIGHT * 120.0
	_command(_player, UserCmd.WALK, false)
	_check_near(_player.velocity.length(), 111.8, "command cap also applies while coasting")
	_equip("weapon_awp", 1)
	_player.velocity = Vector3.BACK * 52.0
	_command(_player, UserCmd.WALK, true)
	_check_near(_player.velocity.length(), 52.0, "scoped walk turning clamps total speed")
	_equip("weapon_ak47")
	_player.velocity = Vector3.BACK * 215.0
	_command(_player, 0, true)
	_check_near(_player.velocity.length(), 215.0, "running turn also clamps total speed")
	_equip("weapon_ak47")
	_player.velocity = Vector3.RIGHT * 200.0
	_command(_player, UserCmd.WALK, true)
	_check_near(_player.velocity.x, 200.0, "fast walk entry retains momentum above the walk gate")
	_equip("weapon_ak47")
	_player.config.friction = 5.2
	for i in 128:
		_command(_player, UserCmd.WALK, true)
	_check_near(_player.velocity.length(), 111.8, "walking still overcomes friction and reaches its cap")
	_command(_player, 0, true)
	_check(_player.velocity.length() > 111.8 and _player.walk_acceleration_limit == 0.0,
		"walk release clears taper and accelerates toward running speed")
