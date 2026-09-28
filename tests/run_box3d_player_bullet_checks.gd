extends "res://tests/check_suite.gd"

## The real player drops a gun, waits for native sleep, and shoots it from
## standing eye height through UserCmd -> PlayerSim -> Hitscan -> Box3D.
## Initial velocity alone missed the bug: downward shots woke guns, then
## floor contact absorbed the impulse before a visible movement survived.
## godot --headless --path . --script tests/run_box3d_player_bullet_checks.gd

var _host: Node3D
var _world: GameWorld
var _player: PlayerSim
var _adapter: Box3DDrops


func _initialize() -> void:
	if not Box3DDrops.available():
		_skip("box3d-player-bullets", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	await physics_frame
	ItemPhysics.use_table(ItemPhysics.PATH)
	for item_class in ["weapon_glock", "weapon_ak47"]:
		for elevation in [30.0, 60.0, 85.0]:
			await _check_ground_shot(item_class, elevation)
	_finish("box3d-player-bullets")


func _print_passes() -> bool:
	return true


func _check_ground_shot(item_class: String, elevation: float) -> void:
	var label := "%s shot from %.0f degrees" % [item_class, elevation]
	_setup()
	_player.equip(WeaponLibrary.build(item_class))
	await physics_frame
	await process_frame
	await physics_frame
	for tick in 100:
		_world.step()
	_world.game.command(_player.userid, "drop")
	_world.step()
	var drops := _world.game.entities.of_class(item_class)
	_check(drops.size() == 1, "%s: the player's drop command creates the ground gun" % label)
	if drops.is_empty():
		_host.free()
		return
	var item := drops[0] as DroppedItem
	# Occupy its inventory slot so standing over it for the steep shot does
	# not pick it up. Every comparison uses the same AK bullet damage.
	_player.equip(WeaponLibrary.build(item_class))
	_player.equip(_accurate_ak())
	for tick in 1000:
		_world.step()
		if item.resting:
			break
	_check(item.resting and not item.removed, "%s: the thrown gun sleeps naturally on the floor" % label)
	var view := DroppedItemView.new()
	_host.add_child(view)
	view.set_process(false)
	view.watch(_world.game)
	view._process(0.0)
	var model := view.model_of(item.id)
	var before := item.position
	var eye_height := _player.eye_height()
	var across := (eye_height - before.y) / tan(deg_to_rad(elevation))
	_player.place(Vector3(before.x, 0.0, before.z + across), 0.0)
	await physics_frame
	# Finish drawing and settle the player's movement before the first shot.
	for tick in 160:
		_world.step()
	var eye := _player.global_position + Vector3.UP * _player.eye_height()
	var angles := PlayerInput.angles_from_direction(item.position - eye)
	_player.yaw_degrees = angles.x
	_player.pitch_degrees = angles.y
	var traced: Array[Weapon.Shot] = []
	_player.shot_traced.connect(func(shot: Weapon.Shot, _result: Hitscan.Result) -> void: traced.append(shot))
	var rounds_before := _player.rounds_fired
	var queries_before := _adapter.bullet_queries
	_world.begin_tick()
	var cmd := UserCmd.new()
	cmd.tick = _world.tick
	cmd.yaw_degrees = angles.x
	cmd.pitch_degrees = angles.y
	cmd.buttons = UserCmd.ATTACK
	cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.ATTACK, true, 0.0, angles.x, angles.y))
	_player.run_command(cmd, SimClock.tick_seconds())
	_check(_player.rounds_fired == rounds_before + 1 and traced.size() == 1
		and _adapter.bullet_queries > queries_before,
		"%s: a real attack command fires and reaches the native drop query" % label)
	_check(not item.resting and item.velocity.length() > 1.0,
		"%s: the native hull is hit and wakes with momentum" % label)
	_world.end_tick()
	for tick in 9:
		_world.step()
	var displacement := item.position.distance_to(before)
	_check(displacement > 0.3,
		"%s: movement survives ten ticks of floor contacts (%.4f inches)" % [label, displacement])
	view._process(0.0)
	var frame := DroppedItemView.drawn_frame(model, item.physics().bone) if model != null else Transform3D.IDENTITY
	var drawn_com := frame * item.physics().centre_of_mass
	_check(model != null and drawn_com.distance_to(before) > 0.3
		and drawn_com.distance_to(item.position) < item.position.distance_to(item.previous_position) + 0.02,
		"%s: the sleeping gun's visible model resumes following its moving body" % label)
	_host.free()
	await process_frame


func _setup() -> void:
	_host = Node3D.new()
	root.add_child(_host)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position = Vector3(0.0, -8.0, 0.0)
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(4096.0, 16.0, 4096.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	_host.add_child(floor_body)
	_world = GameWorld.new()
	_host.add_child(_world)
	_world.set_physics_process(false)
	_world.initialize_drop_physics(_host, "box3d")
	_adapter = _world.game.drop_physics
	_player = PlayerSim.new()
	_player.team = "T"
	_player.collision_layer = 2
	var player_shape := CollisionShape3D.new()
	var player_box := BoxShape3D.new()
	player_box.size = Vector3(32.0, 72.0, 32.0)
	player_shape.shape = player_box
	player_shape.position = Vector3(0.0, 36.0, 0.0)
	_player.add_child(player_shape)
	_host.add_child(_player)
	_player.place(Vector3.ZERO, 0.0)
	_world.add_player(_player)


## Only accuracy is controlled: a deterministic ray at the small hull.
## Weapon timing, damage, native mass, player wiring and contacts stay real.
static func _accurate_ak() -> WeaponData:
	var data := WeaponLibrary.ak47()
	data.inaccuracy_standing = 0.0
	data.inaccuracy_crouching = 0.0
	data.inaccuracy_moving = 0.0
	data.inaccuracy_jumping = 0.0
	data.inaccuracy_landing = 0.0
	data.spread = 0.0
	return data
