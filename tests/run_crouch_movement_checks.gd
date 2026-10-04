extends "res://tests/check_suite.gd"

## Real crouched commands on flat/uphill/downhill Box3D floors. The first
## acceleration interval is bounded by the recovered 250 * 0.34 scale,
## while long holds must still reach each item's crouched speed.
var _tick := 200000
var DT := SimClock.tick_seconds()

class Pawn extends PlayerSim:
	func _init() -> void:
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		add_child(shape)
	func wear_body(_weapon_model: String, _drawn: bool) -> void:
		pass

func _initialize() -> void:
	if not Box3DDrops.available():
		_skip("crouch-movement", "Requires the patched Box3D addon")
		return
	_run()

func _run() -> void:
	await physics_frame
	for angle in [0.0, 5.0, -5.0, 20.0, -20.0]:
		for item in ["weapon_knife", "weapon_ak47", "weapon_awp"]:
			for walking in [false, true]:
				await _check_start(angle, item, walking)
	_finish("crouch-movement")

func _check_start(angle: float, item: String, walking: bool) -> void:
	var host := Node3D.new()
	root.add_child(host)
	var floor_body := StaticBody3D.new()
	var rotation := Basis(Vector3.BACK, deg_to_rad(angle))
	floor_body.position = Vector3.UP * 200.0 - rotation.y * 8.0
	floor_body.basis = rotation
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2048.0, 16.0, 512.0)
	shape.shape = box
	floor_body.add_child(shape)
	host.add_child(floor_body)
	var world := GameWorld.new()
	host.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	var player := Pawn.new()
	player.position = Vector3(0.0, 220.0, 0.0)
	host.add_child(player)
	player.inventory.add(item)
	player.inventory.select(item)
	world.add_player(player)
	await physics_frame
	if not world.initialize_drop_physics(host, "box3d"):
		_check(false, "crouch fixture initializes Box3D")
		host.free()
		return
	var buttons := UserCmd.DUCK | (UserCmd.WALK if walking else 0)
	for i in 80:
		_command(player, buttons, false)
	var label := "%s, slope %.0f, Walk %s" % [item, angle, walking]
	_check(player.on_ground and player.is_ducked and player.velocity.length() < 0.01,
		"fully crouched start stays planted: " + label)
	var start := player.global_position
	var speeds: Array[float] = []
	var grounded := true
	for i in SimClock.ticks_in(2.0):
		_command(player, buttons, true)
		speeds.append(Vector2(player.velocity.x, player.velocity.z).length())
		grounded = grounded and player.on_ground
	print("CROUCH ", JSON.stringify({"item": item, "slope": angle, "walk": walking,
		"first_speed": speeds[0], "fourth_speed": speeds[3], "final_speed": speeds[-1],
		"distance": player.global_position.x - start.x, "grounded": grounded}))
	_check(speeds[0] <= 5.5 * 85.0 * DT + 0.05,
		"first crouch acceleration uses the recovered duck scale: " + label)
	_check(speeds[3] < 11.0,
		"crouch starts build speed gradually instead of a standing-speed burst: " + label)
	_check(grounded and speeds.max() <= player.config.max_speed * 0.34 + 0.1,
		"crouch slope travel remains grounded and within the held item's speed: " + label)
	if angle == 0.0:
		_check(absf(speeds[-1] - player.config.max_speed * 0.34) < 0.05,
			"crouch acceleration still overcomes stop friction and reaches its target: " + label)
		for i in 64:
			_command(player, UserCmd.WALK if walking else 0, false)
		_command(player, buttons, true)
		_check(player.duck_progress > 0.0 and player.duck_progress < 1.0
			and Vector2(player.velocity.x, player.velocity.z).length() <= 5.5 * 85.0 * DT + 0.05,
			"pressing crouch and move together reduces acceleration before the duck finishes: " + label)
		_command(player, UserCmd.WALK if walking else 0, true)
		_check(Vector2(player.velocity.x, player.velocity.z).length() < 9.0,
			"releasing a partial crouch keeps the transition's acceleration scale for its last interval: " + label)
	world.remove_player(player)
	player.free()
	world.game.entities.clear()
	world.game.last_tick = null
	for system in world.game.systems():
		if system is ItemDrops or system is KillCredit:
			system.game = null
	host.free()
	await process_frame

func _command(player: PlayerSim, buttons: int, moving: bool) -> void:
	var cmd := UserCmd.new()
	cmd.tick = _tick
	_tick += 1
	cmd.yaw_degrees = 270.0
	cmd.buttons = buttons
	cmd.move = Vector2(0.0, 1.0) if moving else Vector2.ZERO
	player.run_command(cmd, DT)
