extends "res://tests/check_suite.gd"

## Bullet impulses in the Box3D experiment, through the ordinary hitscan
## path. The real Glock checks a sleeping gun and its view; the committed
## rectangular AK fixture gives controlled centre and off-centre hits.
## No extracted assets are needed. Native binaries are optional in a clone.
## godot --headless --path . --script tests/run_box3d_bullet_checks.gd

const SCALE := 0.0254
const ORIGIN := Vector3(0.0, 64.0, 0.0)
const GUN_AT := Vector3(0.0, 64.0, -128.0)


func _initialize() -> void:
	if not Box3DDrops.available():
		_skip("box3d-bullets", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	await physics_frame
	ItemPhysics.use_table(ItemPhysics.PATH)
	await _check_ground_wake()
	await _check_support_response()
	ItemPhysics.use_table("res://tests/fixtures/item_physics.csv")
	await _check_impulses_and_filters()
	await _check_airborne_downward_hit()
	await _check_range()
	await _check_occlusion()
	ItemPhysics.use_table(ItemPhysics.PATH)
	_finish("box3d-bullets")


func _print_passes() -> bool:
	return true


func _check_ground_wake() -> void:
	var test := _case(true)
	await _settle_queries()
	var item := DroppedItem.drop_from(test.game, 99, _entry("weapon_glock"),
		Transform3D(Basis.IDENTITY, Vector3(0.0, 30.0, 0.0)))
	for tick in 320:
		_step(test)
		if item.resting:
			break
	_check(item.resting, "a real Glock reaches native sleep on the floor before being shot")
	var view := DroppedItemView.new()
	test.host.add_child(view)
	view.set_process(false)
	view.watch(test.game)
	view._process(0.0)
	var model := view.model_of(item.id)
	var from := item.position
	var shot := _shot(from - Vector3.RIGHT * 100.0, Vector3.RIGHT)
	_fire(test, shot, _data())
	var native := test.adapter.body_for(item.id)
	_check(not item.resting and item.rested_usec == -1 and bool(native.call(&"is_awake"))
		and item.velocity.dot(shot.direction) > 1.0,
		"shooting a sleeping gun wakes it and immediately exposes its new momentum")
	for tick in 8:
		_step(test)
	view._process(0.0)
	_check(item.position.distance_to(from) > 0.1, "the hit moves the gun through the next simulation ticks")
	var drawn := DroppedItemView.drawn_frame(model, item.physics().bone) if model != null else Transform3D.IDENTITY
	var drawn_com := drawn * item.physics().centre_of_mass
	_check(model != null and drawn_com.distance_to(from) > 0.1
		and drawn_com.distance_to(item.position) < item.position.distance_to(item.previous_position) + 0.02,
		"the previously settled view resumes drawing the moving gun")
	_close(test)


func _check_impulses_and_filters() -> void:
	var test := _case()
	await _settle_queries()
	var data := _data()
	var shot := _shot()
	var item := _put(test, "weapon_ak47", GUN_AT)
	var plain := Hitscan.trace(test.space(), shot, data)
	_check(item.resting and item.velocity.is_zero_approx() and plain.items.is_empty(), "plain tracing remains read-only with a native gun in its path")
	var missed := _fire(test, _shot(ORIGIN + Vector3.RIGHT * 10.0), data)
	_check(item.resting and item.velocity.is_zero_approx() and missed.items.is_empty(), "a shot that misses the hull does not wake or push it, nor spark")
	var result := _fire(test, shot, data)
	_check(result.items.size() == 1 and (result.items[0]["at"] as Vector3).distance_to(GUN_AT) < 16.0
		and (result.items[0]["normal"] as Vector3).is_normalized(),
		"the round reports where it went through the gun, for its sparks (%s)" % [result.items])
	var single := item.velocity
	var body := test.adapter.body_for(item.id)
	var momentum := (body.call(&"get_linear_velocity") as Vector3).length() * float(body.call(&"get_mass")) / SCALE
	_check(absf(momentum - 248.4) < 0.2,
		"36 damage supplies 248.4 kg-inch/s of native momentum, without a tick-duration factor (%.3f)" % momentum)
	_check(not result.hit and result.walls.is_empty() and item.angular_velocity.length() < 0.01,
		"a centred shot pushes through the gun without changing the Jolt hit result or adding spin")
	test.game.entities.clear()
	item = _put(test, "weapon_ak47", GUN_AT)
	_fire(test, _shot(ORIGIN + Vector3.RIGHT * 0.75), data)
	_check(item.angular_velocity.length() > 0.1 and item.velocity.dot(Vector3.FORWARD) > 1.0,
		"an off-centre bullet applies torque at the hit point as well as forward momentum")
	test.game.entities.clear()
	item = _put(test, "weapon_ak47", GUN_AT)
	shot.pellet_directions = PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD])
	for pellet in shot.pellets():
		_fire(test, shot.pellet_shot(pellet), data)
	_check(item.velocity.distance_to(single * 3.0) < 0.02,
		"three pellets hitting in one interval accumulate three impulses before physics steps")
	test.game.entities.clear()
	var kit := _put(test, "item_defuser", Vector3(0.0, 64.0, -32.0))
	var grenade := _put(test, "weapon_hegrenade", Vector3(0.0, 64.0, -64.0))
	var removed := _put(test, "weapon_ak47", Vector3(0.0, 64.0, -96.0))
	removed.remove()
	item = _put(test, "weapon_ak47", GUN_AT)
	_fire(test, _shot(), data)
	_check(kit.velocity.is_zero_approx() and grenade.velocity.is_zero_approx()
		and kit.resting and grenade.resting and item.velocity.distance_to(single) < 0.02,
		"non-gun drops receive no force and do not hide a gun farther along the ray")
	_check(removed.velocity.is_zero_approx()
		and (test.adapter.body_for(removed.id).call(&"get_linear_velocity") as Vector3).is_zero_approx(),
		"a removed gun is ignored even before its native body is pruned")
	_close(test)


func _check_support_response() -> void:
	for slope_degrees in [0.0, 20.0]:
		var test := _case(true)
		var floor_body := test.geometry.get_child(0) as StaticBody3D
		floor_body.rotation.z = deg_to_rad(slope_degrees)
		test.adapter.capture_world(test.geometry)
		await _settle_queries()
		var item := DroppedItem.drop_from(test.game, 99, _entry("weapon_glock"),
			Transform3D(Basis.IDENTITY, Vector3(0.0, 30.0, 0.0)))
		for tick in 512:
			_step(test)
			if item.resting:
				break
		_check(item.resting, "the gun sleeps on the %.0f-degree support before the downward shot" % slope_degrees)
		var normal := floor_body.basis.y
		var before := item.position
		var origin := before + normal * 64.0 + Vector3.BACK * 12.0
		var shot := _shot(origin, (before - origin).normalized())
		_fire(test, shot, _data())
		var native := test.adapter.body_for(item.id)
		var momentum := item.velocity.length() * float(native.call(&"get_mass"))
		_check(item.velocity.dot(normal) > 10.0 and absf(momentum - 248.4) < 0.2,
			"the %.0f-degree support redirects the kick outward without increasing its magnitude" % slope_degrees)
		var along_surface := shot.direction.slide(normal) * (248.4 / float(native.call(&"get_mass")))
		_check(item.velocity.slide(normal).distance_to(along_surface) < 0.02,
			"the %.0f-degree support preserves momentum along its surface" % slope_degrees)
		var maximum := 0.0
		for tick in 16:
			_step(test)
			maximum = maxf(maximum, item.position.distance_to(before))
		_check(maximum > 0.5, "a downward hit visibly moves the gun on the %.0f-degree support (%.3f inches)" % [slope_degrees, maximum])
		_close(test)


func _check_airborne_downward_hit() -> void:
	var test := _case()
	await _settle_queries()
	var item := _put(test, "weapon_ak47", GUN_AT)
	var origin := GUN_AT + Vector3(0.0, 64.0, 64.0)
	var shot := _shot(origin, (GUN_AT - origin).normalized())
	_fire(test, shot, _data())
	_check(item.velocity.y < -1.0 and item.velocity.normalized().distance_to(shot.direction) < 0.001,
		"a downward shot into an unsupported gun keeps its downward momentum")
	var before := item.position
	for tick in 8:
		_step(test)
	_check(item.position.y < before.y - 1.0, "the airborne gun continues down through simulation ticks")
	_close(test)


func _check_range() -> void:
	var test := _case()
	await _settle_queries()
	var near := _put(test, "weapon_ak47", GUN_AT)
	var far := _put(test, "weapon_ak47", GUN_AT + Vector3.FORWARD * 500.0)
	var data := _data()
	data.max_range = 100.0
	_fire(test, _shot(), data)
	_check(near.resting and far.resting and near.velocity.is_zero_approx() and far.velocity.is_zero_approx(),
		"guns beyond the bullet's maximum range receive no force")
	data.max_range = 1000.0
	data.range_modifier = 0.5
	_fire(test, _shot(), data)
	_check(near.velocity.length() > 1.0 and far.velocity.length() > 0.1
		and far.velocity.length() < near.velocity.length() * 0.75,
		"a bullet continues through guns and loses impulse with range")
	_close(test)


func _check_occlusion() -> void:
	var data := _data()
	var clear_speed := 0.0
	for surface in ["", "physics_group_wood_plank", "physics_group_concrete"]:
		var test := _case()
		if not surface.is_empty():
			_box(test.geometry, Vector3(256.0, 256.0, 4.0 if surface.contains("wood") else 16.0),
				Vector3(0.0, 64.0, -64.0), surface)
			test.adapter.capture_world(test.geometry)
		await _settle_queries()
		var item := _put(test, "weapon_ak47", GUN_AT)
		var result := _fire(test, _shot(), data)
		if surface.is_empty():
			clear_speed = item.velocity.length()
		elif surface.contains("wood"):
			_check(result.walls.size() == 1 and item.velocity.length() > 0.1
				and item.velocity.length() < clear_speed * 0.95,
				"a penetrated wooden wall reduces the impulse delivered to the gun behind it")
		else:
			_check(result.hit and result.walls.is_empty() and item.resting and item.velocity.is_zero_approx(),
				"a concrete wall stops the bullet and protects the gun behind it")
		_close(test)
	var test := _case()
	var target := HitTarget.new()
	target.build_visual = false
	target.armor = 0.0
	target.position = Vector3(0.0, 14.0, -80.0)
	test.host.add_child(target)
	await _settle_queries()
	var before_player := _put(test, "weapon_ak47", Vector3(0.0, 64.0, -32.0))
	var behind_player := _put(test, "weapon_ak47", GUN_AT)
	var plain := Hitscan.trace(test.space(), _shot(), data)
	var result := _fire(test, _shot(), data)
	_check(result.hitbox != null and result.hitbox.target == target and target.health < target.max_health
		and result.hitbox == plain.hitbox and result.position.is_equal_approx(plain.position),
		"pushing a gun in front of a player preserves the ordinary player hit and damage")
	_check(before_player.velocity.length() > 1.0 and behind_player.resting and behind_player.velocity.is_zero_approx(),
		"the player stops the bullet: the nearer gun moves and the gun behind remains untouched")
	_close(test)


func _case(floor: bool = false) -> _Case:
	var test := _Case.new()
	test.host = Node3D.new()
	root.add_child(test.host)
	test.geometry = Node3D.new()
	test.host.add_child(test.geometry)
	if floor:
		_box(test.geometry, Vector3(2048.0, 16.0, 2048.0), Vector3(0.0, -8.0, 0.0), "concrete")
	test.game = GameSystems.new()
	test.game.last_tick = SimTick.new(test.game, 0)
	test.adapter = Box3DDrops.new()
	test.host.add_child(test.adapter)
	_check(test.adapter.initialize(test.game, test.geometry), "the bullet fixture initializes its native world")
	if not floor:
		test.adapter.native_world.set(&"gravity", Vector3.ZERO)
	return test


func _entry(item_class: String) -> Inventory.Entry:
	var definition := ItemRegistry.item(item_class)
	var weapon := Weapon.new(ItemRegistry.weapon_data(item_class)) if definition.is_gun else null
	return Inventory.Entry.new(definition, weapon, 1)


func _put(test: _Case, item_class: String, at: Vector3) -> DroppedItem:
	var item := DroppedItem.new(_entry(item_class), 99, at)
	item.resting = true
	item.rested_usec = 0
	test.game.entities.spawn(item)
	return item


func _data() -> WeaponData:
	var data := WeaponData.new()
	data.base_damage = 36.0
	data.range_modifier = 1.0
	data.max_range = 2048.0
	return data


func _shot(origin: Vector3 = ORIGIN, direction: Vector3 = Vector3.FORWARD) -> Weapon.Shot:
	var shot := Weapon.Shot.new()
	shot.origin = origin
	shot.direction = direction
	return shot


func _fire(test: _Case, shot: Weapon.Shot, data: WeaponData) -> Hitscan.Result:
	var shooter := Hitscan.Shooter.new()
	shooter.on_free_segment = test.adapter.push_bullet_segment.bind(data, shot.origin)
	return Hitscan.fire_as(test.space(), shot, data, shooter)


func _box(parent: Node3D, size: Vector3, at: Vector3, surface: String) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Hitscan.WORLD_LAYER
	body.collision_mask = 0
	body.position = at
	var collision := CollisionShape3D.new()
	collision.name = surface
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _step(test: _Case) -> void:
	test.game.step(test.next_tick, test.space())
	test.next_tick += 1


func _settle_queries() -> void:
	for frame in 3:
		await physics_frame


func _close(test: _Case) -> void:
	test.game.entities.clear()
	test.host.free()


class _Case:
	extends RefCounted
	var host: Node3D
	var geometry: Node3D
	var game: GameSystems
	var adapter: Box3DDrops
	var next_tick: int = 1

	func space() -> PhysicsDirectSpaceState3D:
		return host.get_world_3d().direct_space_state
