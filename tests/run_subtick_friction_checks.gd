extends "res://tests/run_crouch_movement_checks.gd"

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
	_check(_world.initialize_drop_physics(_host, "box3d"), "subtick fixture initializes Box3D")
	for i in 80:
		_command(_player, 0, false)
	_test_cache_lifetime()
	_test_input_events()
	_test_split_friction()
	_test_segmented_commands()
	if PlayerBody.native_installed():
		_check(PlayerBody.native_built(), "subtick checks use the current native build")
		_check(PlayerBody.steps_checked > 80, "cache states are compared in real native/script steps")
	_world.remove_player(_player)
	_player.free()
	_world.game.entities.clear()
	_world.game.last_tick = null
	for system in _world.game.systems():
		if system is ItemDrops or system is KillCredit:
			system.game = null
	_host.free()
	await process_frame
	_finish("subtick-friction")


func _test_cache_lifetime() -> void:
	_player._friction_cached = false
	_player._friction_refreshed = false
	_player._interval_start = 0.25
	_player.velocity = Vector3.RIGHT * 200.0
	_player.movement_impulse = Vector3.RIGHT * 250.0
	_player._last_movement_impulse = Vector3.ZERO
	_player._update_friction_cache()
	_check(_player._friction_cached and _player._friction_refreshed and _player._friction_until == 0.25,
		"input change saves speed and its phase")
	var saved := _player._friction_speed
	_player.velocity = Vector3.RIGHT * 180.0
	_player._last_movement_impulse = _player.movement_impulse
	_player.movement_impulse = Vector3.LEFT * 250.0
	_player._interval_start = 0.5
	_player._update_friction_cache()
	_check(_player._friction_speed == saved and _player._friction_until == 0.25,
		"later input changes retain the current cache until its phase")
	_player._interval_start = 0.0
	_player._friction_refreshed = false
	_player._update_friction_cache()
	_check(_player._friction_speed == saved and not _player._friction_refreshed,
		"next command keeps the old control before the saved phase")
	_player._interval_start = 0.25
	_player._update_friction_cache()
	_check(_player._friction_cached and _player._friction_refreshed and _player._friction_speed < saved,
		"changed speed refreshes the cache at the saved phase")
	_player._last_movement_impulse = _player.movement_impulse
	_player._friction_refreshed = false
	_player._update_friction_cache()
	_check(not _player._friction_cached and not _player._friction_refreshed,
		"stable speed and input retire the cache at its phase")


func _test_input_events() -> void:
	for sample: Array in [[0.001, 0.0], [0.1, 0.09375], [0.999, 1.0], [0.0078125, 0.0], [0.0234375, 0.03125]]:
		_check(UserCmd.movement_phase(sample[0]) == sample[1], "live command phase rounds %.8f to %.8f" % sample)
	var cmd := UserCmd.new()
	cmd.move = Vector2(1.0, 0.0)
	cmd.buttons = UserCmd.RIGHT
	cmd.steps = [UserCmd.SubtickStep.new(UserCmd.RIGHT, true, 0.25, 90.0, 0.0)]
	_check(cmd.movement_at(0.0, 0.25).move == Vector2.ZERO, "new movement press does not act before its event")
	_check(cmd.movement_at(0.25, 1.0).move == Vector2.RIGHT, "movement press acts at its event")
	_check(cmd.movement_at(0.0, 0.125).yaw_degrees == 90.0, "forced boundary retains the next event look")
	cmd.move = Vector2.ZERO
	cmd.buttons = 0
	cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.RIGHT, false, 0.75, 0.0, 0.0))
	_check(cmd.movement_at(0.5, 0.75).move == Vector2.RIGHT, "short movement tap survives final released state")
	_check(cmd.movement_at(0.75, 1.0).move == Vector2.ZERO, "release ends the movement tap")
	cmd.steps = [UserCmd.SubtickStep.new(UserCmd.FORWARD, true, 0.5, 0.0, 0.0),
		UserCmd.SubtickStep.new(UserCmd.RIGHT, true, 0.5, 0.0, 0.0)]
	cmd.move = Vector2.ONE
	cmd.buttons = UserCmd.FORWARD | UserCmd.RIGHT
	_check(cmd.movement_at(0.0, 0.5).move == Vector2.ZERO and cmd.movement_at(0.5, 1.0).move == Vector2.ONE,
		"same-phase events form a single diagonal input")
	_check(cmd.movement_impulse().length() > 1.4, "raw diagonal input survives normalization for the cache")
	for sample: Array in [[0.0, Vector2.RIGHT], [1.0, Vector2.ZERO]]:
		cmd.move = Vector2.RIGHT
		cmd.steps = [UserCmd.SubtickStep.new(UserCmd.RIGHT, true, sample[0], 0.0, 0.0)]
		_check(cmd.movement_at(0.0, 1.0).move == sample[1], "event at %.0f selects the proper interval" % sample[0])
	_check(PlayerInput.BUTTONS[&"move_forward"] == UserCmd.FORWARD and PlayerInput.BUTTONS[&"move_left"] == UserCmd.LEFT,
		"local movement keys use timestamped command events")


func _reset() -> void:
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.on_ground = true
	_player.is_ducked = false
	_player.duck_progress = 0.0
	_player._friction_cached = false
	_player._friction_refreshed = false
	_player._last_movement_impulse = Vector3.ZERO
	_player.movement_impulse = Vector3.INF
	_player.wish_dir = Vector3.ZERO
	_player.wish_speed = 0.0
	_player.acceleration_speed = 0.0
	_player.movement_speed_limit = INF
	_player.walk_acceleration_limit = 0.0
	_player.wants_jump = false
	_player.wants_duck = false
	_player._jump_held_last_tick = false
	_player._movement_jump_pending = false
	_player._movement_jump_held = false
	_player.jump_fraction = -1.0
	_player.movement_fraction = -1.0
	_player.movement_boundaries.clear()
	_player._floor_at = Vector3.INF
	_player._looked_from = Vector3.INF
	_player.config.friction = 5.2


func _test_split_friction() -> void:
	var unsplit := 0.0
	for pieces in [1, 4, 16]:
		_reset()
		_player.velocity = Vector3.RIGHT * 200.0
		_player._last_movement_impulse = Vector3.RIGHT * 250.0
		for i in range(1, pieces):
			_player.movement_boundaries.append(float(i) / pieces)
		_player.simulate(DT)
		# Quantizer code 530687 decodes to 199.98455810546875.
		# Constant drag: 200 - decoded_speed * 5.2 / 64.
		_check(absf(_player.velocity.x - 183.751254653931) < 0.0005,
			"%d segments use a single saved drag speed" % pieces)
		if pieces == 1:
			unsplit = _player.velocity.x
		else:
			_check(absf(_player.velocity.x - unsplit) < 0.0005, "extra boundaries do not weaken friction")
		_check(_player._friction_cached, "command publishes its cache refresh")
	_reset()
	_player._friction_cached = true
	_player._friction_until = 0.25
	_player._friction_speed = 200.0
	_player.velocity = Vector3.RIGHT * 200.0
	_player.simulate(DT)
	_check(_player._friction_until == 0.25 and _player._friction_speed < 196.0,
		"saved phase forces an interval and refreshes in a command with no input events")
	_reset()
	_player._friction_cached = true
	_player._friction_until = 0.5
	_player._friction_speed = 200.0
	_player.velocity = Vector3.RIGHT
	_player.simulate(DT)
	_check(_player.velocity.is_zero_approx(), "cached drag clamps at zero without reversing")
	_reset()
	_player._friction_cached = true
	_player._friction_until = 0.75
	_player._friction_speed = 200.0
	_player.wish_dir = Vector3.RIGHT
	_player.wish_speed = 100.0
	_player.acceleration_speed = 100.0
	_player._interval_start = 0.0
	_player._simulate_step(DT)
	_check(_player.velocity.is_zero_approx() and absf(_player._friction_overshoot - 16.25) < 0.00001,
		"cached drag at rest consumes acceleration through overshoot instead of an extra burst")
	_reset()
	_player._friction_cached = true
	_player.noclip = true
	_player.simulate(DT)
	_check(not _player._friction_cached, "noclip clears ground friction state")
	_player.noclip = false


func _test_segmented_commands() -> void:
	_reset()
	_player.equip(WeaponLibrary.build("weapon_ak47"))
	_player.config.friction = 0.0
	var cmd := UserCmd.new()
	cmd.tick = _tick
	_tick += 1
	cmd.move = Vector2.RIGHT
	cmd.buttons = UserCmd.RIGHT
	cmd.steps = [UserCmd.SubtickStep.new(UserCmd.RIGHT, true, 0.5, 0.0, 0.0)]
	_player.run_command(cmd, DT)
	_check(absf(_player.velocity.x - 9.23828125) < 0.001, "half-tick move press accelerates for half a tick")
	_check(absf(_player.global_position.x - 0.036087) < 0.001, "movement press leaves the first half stationary")
	_reset()
	_player.config.friction = 0.0
	cmd.tick = _tick
	_tick += 1
	cmd.move = Vector2.ZERO
	cmd.buttons = 0
	cmd.steps = [UserCmd.SubtickStep.new(UserCmd.RIGHT, true, 0.25, 0.0, 0.0),
		UserCmd.SubtickStep.new(UserCmd.RIGHT, false, 0.75, 0.0, 0.0)]
	_player.run_command(cmd, DT)
	_check(absf(_player.velocity.x - 9.23828125) < 0.001, "short move tap accelerates only between its press and release")
	_reset()
	cmd.tick = _tick
	_tick += 1
	cmd.steps = [UserCmd.SubtickStep.new(UserCmd.JUMP, true, 0.25, 0.0, 0.0),
		UserCmd.SubtickStep.new(UserCmd.JUMP, false, 0.5, 0.0, 0.0)]
	_player.run_command(cmd, DT)
	_check(not _player.on_ground and _player.velocity.y > 285.0, "short jump tap still jumps at its press")
	_check(not _player._jump_held_last_tick, "jump release survives command completion")
	_reset()
	cmd.tick = _tick
	_tick += 1
	cmd.buttons = UserCmd.JUMP
	cmd.steps = [UserCmd.SubtickStep.new(UserCmd.JUMP, true, 1.0, 0.0, 0.0)]
	_player.run_command(cmd, DT)
	_check(_player.on_ground and not _player._jump_held_last_tick, "tick-end jump waits for an interval without consuming its edge")
	cmd.tick = _tick
	_tick += 1
	cmd.steps.clear()
	_player.run_command(cmd, DT)
	_check(not _player.on_ground and _player.velocity.y > 280.0, "tick-end jump takes off in the following command")
	_reset()
	cmd.tick = _tick
	_tick += 1
	cmd.buttons = 0
	cmd.steps = [UserCmd.SubtickStep.new(UserCmd.JUMP, true, 0.5, 0.0, 0.0),
		UserCmd.SubtickStep.new(UserCmd.JUMP, false, 0.5, 0.0, 0.0)]
	_player.run_command(cmd, DT)
	_check(not _player.on_ground and _player.velocity.y > 290.0, "same-phase wheel press and release still jump")
	_check(not _player._jump_held_last_tick, "wheel jump does not turn its press into a held button")
	_reset()
	cmd.tick = _tick
	_tick += 1
	cmd.steps = [UserCmd.SubtickStep.new(UserCmd.JUMP, true, 1.0, 0.0, 0.0),
		UserCmd.SubtickStep.new(UserCmd.JUMP, false, 1.0, 0.0, 0.0)]
	_player.run_command(cmd, DT)
	_check(_player.on_ground, "tick-end wheel pulse waits for the next command")
	cmd.tick = _tick
	_tick += 1
	cmd.steps.clear()
	_player.run_command(cmd, DT)
	_check(not _player.on_ground and _player.velocity.y > 280.0, "released tick-end wheel pulse is retained for takeoff")
	_reset()
	_player.config.friction = 0.0
	cmd.tick = _tick
	_tick += 1
	cmd.buttons = UserCmd.RIGHT | UserCmd.WALK
	cmd.move = Vector2.RIGHT
	cmd.steps = [UserCmd.SubtickStep.new(UserCmd.RIGHT, true, 0.5, 0.0, 0.0),
		UserCmd.SubtickStep.new(UserCmd.WALK, true, 0.5, 0.0, 0.0)]
	_player.run_command(cmd, DT)
	_check(absf(_player.velocity.x - 5.5859375) < 0.001, "same-phase Walk and move select walking acceleration for the second half")
	_reset()
	cmd.tick = _tick
	_tick += 1
	cmd.buttons = UserCmd.DUCK
	cmd.move = Vector2.ZERO
	cmd.steps = [UserCmd.SubtickStep.new(UserCmd.DUCK, true, 0.5, 0.0, 0.0)]
	_player.run_command(cmd, DT)
	_check(absf(_player.duck_progress - DT * 0.5 / _player.config.duck_time) < 0.00001,
		"crouch transition begins at its input event")
	_reset()
	_player.config.friction = 5.2
