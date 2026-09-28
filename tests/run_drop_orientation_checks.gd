extends "res://tests/check_suite.gd"

## The hand's attachment bone has different axes from the weapon model.
## A released barrel must still follow aim, for every extracted gun and
## without depending on an animated player model or the physics backend.

const ANGLES := [Vector2.ZERO, Vector2(93.0, 35.0), Vector2(-137.0, -55.0), Vector2(269.0, 80.0)]

var _host: Node3D
var _player: _Player


func _initialize() -> void:
	_host = Node3D.new()
	root.add_child(_host)
	_player = _Player.new()
	_host.add_child(_player)
	_player.position = Vector3(100.0, 20.0, -50.0)
	await physics_frame
	ItemPhysics.use_table(ItemPhysics.PATH)
	_check_all_guns()
	_check_drop_command()
	_check_drawn_models()
	_host.free()
	_finish("drop-orientation")


func _check_all_guns() -> void:
	var game := GameSystems.new()
	for definition in ItemRegistry.all():
		if not definition.is_gun:
			continue
		var failures := PackedStringArray()
		for angles: Vector2 in ANGLES:
			_player.yaw_degrees = angles.x
			_player.pitch_degrees = angles.y
			for crouch: float in [0.0, 0.55, 1.0]:
				_player.duck_progress = crouch
				var aim := PlayerInput.aim_direction(angles.x, angles.y)
				var right := Vector3(cos(deg_to_rad(angles.x)), 0.0, -sin(deg_to_rad(angles.x)))
				var up := right.cross(aim)
				var held := HeldPose.of(_player, definition.item_class)
				var item := DroppedItem.drop_from(game, 1, _entry(definition.item_class), held)
				var model := item.model_transform()
				var offsets := HeldPose.offsets_for(definition.item_class)
				var off: Vector3 = (offsets[0] as Vector3).lerp(offsets[1], MovementSolver.simple_spline(crouch))
				var hand := _player.global_position + Vector3.UP * _player.eye_height() + aim * off.x + right * off.y + up * off.z
				if model.basis.z.dot(aim) < 0.9999 or model.basis.y.dot(up) < 0.9999 \
						or (model * item.physics().held_bone.origin).distance_to(hand) > 0.001:
					failures.append("yaw %.0f pitch %.0f duck %.2f" % [angles.x, angles.y, crouch])
				game.entities.clear()
		_check(failures.is_empty(), "%s releases barrel-first along aim, top upright and root bone at the hand (%s)" % [definition.item_class, "; ".join(failures)])


func _check_drop_command() -> void:
	var game := GameSystems.new()
	var userid := game.add_player(_player)
	_player.item_class = "weapon_ak47"
	_player.yaw_degrees = 32.0
	_player.pitch_degrees = 47.0
	_player.duck_progress = 0.0
	_player.velocity = Vector3(25.0, 0.0, -10.0)
	game.inventory(userid).add(_player.item_class)
	var released: Array[Dictionary] = []
	game.entities.spawned.connect(func(entity: SimEntity) -> void:
		var item := entity as DroppedItem
		if item != null:
			released.append({"model": item.model_transform(), "velocity": item.velocity, "spin": item.angular_velocity})
	)
	game.command(userid, "drop")
	game.step(1)
	_check(released.size() == 1, "the drop command releases exactly one gun")
	if released.is_empty():
		return
	var aim := PlayerInput.aim_direction(_player.yaw_degrees, _player.pitch_degrees)
	var model: Transform3D = released[0]["model"]
	var spin: Vector3 = released[0]["spin"]
	var velocity: Vector3 = released[0]["velocity"]
	var level_forward := PlayerInput.aim_direction(_player.yaw_degrees, 0.0)
	_check(model.basis.z.dot(aim) > 0.9999,
		"the actual drop command releases the barrel along the pitched line of sight")
	_check(spin.dot(model.basis.x) >= ItemDrops.THROW_TUMBLE * 0.5 - 0.001
		and absf(spin.dot(level_forward)) < 0.001,
		"the release tumbles around the gun's lateral axis, not its rotated attachment-bone axis")
	_check(velocity.distance_to((aim + Vector3.UP * ItemDrops.THROW_LIFT).normalized() * ItemDrops.THROW_SPEED + _player.velocity) < 0.001,
		"correcting the release frame preserves throw direction, speed and player momentum")
	game.entities.clear()


func _check_drawn_models() -> void:
	var game := GameSystems.new()
	var view := DroppedItemView.new()
	_host.add_child(view)
	view.set_process(false)
	view.watch(game)
	for gun in ["weapon_glock", "weapon_ak47", "weapon_awp"]:
		_player.yaw_degrees = -65.0
		_player.pitch_degrees = 29.0
		var item := DroppedItem.drop_from(game, 1, _entry(gun), HeldPose.of(_player, gun))
		view._process(0.0)
		var drawn := view.model_of(item.id)
		var frame := DroppedItemView.drawn_frame(drawn, item.physics().bone) if drawn != null else Transform3D.IDENTITY
		var aim := PlayerInput.aim_direction(_player.yaw_degrees, _player.pitch_degrees)
		_check(drawn != null and frame.basis.z.normalized().dot(aim) > 0.9999
			and (frame * item.physics().centre_of_mass).distance_to(item.position) < 0.001,
			"%s's drawn dropped pose preserves the release barrel direction and centre of mass" % gun)
	game.entities.clear()
	view.free()


func _entry(item_class: String) -> Inventory.Entry:
	return Inventory.Entry.new(ItemRegistry.item(item_class), Weapon.new(ItemRegistry.weapon_data(item_class)), 1)


class _Player:
	extends Node3D
	var yaw_degrees: float = 0.0
	var pitch_degrees: float = 0.0
	var duck_progress: float = 0.0
	var velocity := Vector3.ZERO
	var team := "T"
	var alive := true
	var item_class := "weapon_ak47"

	func eye_height() -> float:
		return lerpf(64.0, 46.0, MovementSolver.simple_spline(duck_progress))

	func held_transform() -> Transform3D:
		return HeldPose.of(self, item_class)
