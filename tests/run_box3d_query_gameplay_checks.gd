extends "res://tests/check_suite.gd"

## Gameplay callers over the full Box3D query adapter, without extracted
## assets: damage zones, box/mesh penetration, flash/smoke visibility and
## live grenade sweeps. Counters prove these do not pass on a Jolt fallback.
## godot --headless --path . --script tests/run_box3d_query_gameplay_checks.gd


func _initialize() -> void:
	if not Box3DDrops.available():
		_skip("box3d-query-gameplay", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	await physics_frame
	await _check_clear_hit()
	for kind in ["box", "mesh"]:
		await _check_penetration(kind)
	await _check_visibility()
	for kind in ["box", "mesh"]:
		await _check_projectile_contact_band(kind)
	await _check_grenade_flight()
	await _check_grenade_time_budget()
	await _check_grenade_masks()
	await _check_drop_near_wall()
	_finish("box3d-query-gameplay")


func _print_passes() -> bool:
	return true


func _check_clear_hit() -> void:
	var test := _case()
	var target := _target(test)
	if not await _start(test):
		_close(test)
		return
	var data := WeaponLibrary.ak47()
	var result := Hitscan.fire_at(test.space(), _shot(), data)
	_check(result.hitbox != null and result.hitbox.target == target and result.zone == &"head",
		"a native hitscan returns the original target's head hitbox")
	_check(result.damage > 0.0 and absf(target.health - (target.max_health - result.damage)) < 0.01,
		"the ordinary damage path applies the native head hit to its target")
	var query := PhysicsRayQueryParameters3D.create(_shot().origin, Vector3(0.0, 66.5, -256.0), Hitbox.LAYER)
	_check(PhysicsQueries.intersect_ray(test.space(), query).is_empty(),
		"a ray that does not opt into areas ignores native hitboxes")
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := PhysicsQueries.intersect_ray(test.space(), query)
	_check(hit.get("collider") == result.hitbox and hit.get("rid") == result.hitbox.get_rid() if result.hitbox != null else false,
		"an area-only ray preserves the original hitbox object and RID")
	if result.hitbox != null:
		query.exclude = [result.hitbox.get_rid()]
		_check(PhysicsQueries.intersect_ray(test.space(), query).is_empty(),
			"excluding an original hitbox RID excludes its native representation")
	_close(test)


func _check_penetration(kind: String) -> void:
	var test := _case()
	var target := _target(test)
	_wall(test.geometry, kind, Vector3(96.0, 128.0, 4.0), Vector3(0.0, 64.0, -64.0), "wood_plank")
	if not await _start(test):
		_close(test)
		return
	var data := WeaponLibrary.ak47()
	var result := Hitscan.fire_at(test.space(), _shot(), data)
	_check(result.hitbox != null and result.hitbox.target == target and result.walls.size() == 1,
		"%s: the native trace penetrates a thin wood wall and hits the target (walls=%d, at=%s, hitbox=%s)"
		% [kind, result.walls.size(), result.position, result.hitbox])
	if result.walls.size() == 1:
		var wall := result.walls[0]
		_check(absf(wall.thickness - 4.0) < 0.15 and wall.material == "wood_plank",
			"%s: original shape ownership supplies wood material and four-inch thickness" % kind)
		_check(wall.entry_normal.z > 0.9 and wall.exit_normal.z < -0.9,
			"%s: penetration receives correctly oriented entry and exit faces" % kind)
		var clean := data.damage_at(result.distance) * data.head_multiplier
		var expected := clean * Penetration.kept(wall.thickness, 0.6, data.penetration_power)
		_check(absf(result.damage - expected) < 0.1 and result.damage < clean,
			"%s: native penetration retains the existing damage loss" % kind)
	_close(test)


func _check_visibility() -> void:
	var test := _case()
	var target := _target(test)
	_wall(test.geometry, "box", Vector3(96.0, 128.0, 32.0), Vector3(0.0, 64.0, -64.0), "concrete")
	if not await _start(test):
		_close(test)
		return
	var blocked := Hitscan.fire_at(test.space(), _shot(), WeaponLibrary.ak47())
	_check(blocked.hit and blocked.hitbox == null and blocked.walls.is_empty() and target.health == target.max_health,
		"a thick native wall stops the round before the target")
	var eyes := Vector3(0.0, 64.0, -128.0)
	_check(FlashBlind.from(test.space(), Vector3(0.0, 64.0, 0.0), eyes, Vector3.BACK, 0) == null,
		"native world collision blocks a flash behind the concrete wall")
	_check(FlashBlind.from(test.space(), Vector3(160.0, 64.0, 0.0), eyes + Vector3.RIGHT * 160.0, Vector3.BACK, 0) != null,
		"a flash with a clear native sight line still blinds")
	var smoke := SmokeVoxels.new()
	_check(not smoke._open(test.space(), Vector3(0.0, 64.0, -40.0), Vector3(0.0, 64.0, -88.0)),
		"smoke expansion cannot cross the native concrete wall")
	_check(not smoke._open(test.space(), Vector3(0.0, 64.0, -64.0), Vector3(0.0, 64.0, -88.0)),
		"smoke's hit-from-inside query detects the wall containing its start")
	_check(smoke._open(test.space(), Vector3(160.0, 64.0, -40.0), Vector3(160.0, 64.0, -88.0)),
		"smoke expansion passes a clear native sight line")
	_close(test)


func _check_grenade_flight() -> void:
	var test := _case()
	_box(test.geometry, Vector3(1024.0, 16.0, 1024.0), Vector3(0.0, -8.0, 0.0), "concrete")
	_box(test.geometry, Vector3(128.0, 128.0, 8.0), Vector3(0.0, 64.0, -64.0), "wood_plank")
	if not await _start(test):
		_close(test)
		return
	var fall := GrenadeFlight.new()
	fall.position = Vector3(200.0, 16.0, 0.0)
	fall.velocity = Vector3(0.0, -200.0, 0.0)
	fall.step(test.space(), 0.1)
	_check(fall.bounces > 0 and fall.position.y >= GrenadeRules.RADIUS - 0.25 and fall.velocity.y > 0.0,
		"a live grenade sweeps against the native floor and bounces without tunnelling")
	_check(not fall.touches.is_empty() and fall.touches[0]["normal"].y > 0.9
		and fall.touches[0]["surface"] == "physics_group_concrete",
		"grenade contact readback preserves floor normal and original material name")
	var flight := GrenadeFlight.new()
	flight.position = Vector3(0.0, 64.0, 0.0)
	flight.velocity = Vector3(0.0, 0.0, -800.0)
	flight.step(test.space(), 0.2)
	_check(flight.bounces > 0 and flight.position.z > -60.0 and flight.velocity.z > 0.0,
		"a fast live grenade bounces back from the native wall")
	_check(flight.bounces == 1 and flight.touches.size() == 1,
		"the outgoing sweep does not add false bounces against its previous wall contact")
	var from := Vector3(0.0, 64.0, 0.0)
	var motion := Vector3(0.0, 0.0, -128.0)
	var before := PhysicsQueries.native_queries
	var contact := GrenadeFlight._sweep(test.space(), from, motion, [])
	_check(PhysicsQueries.native_queries - before == 1,
		"a grenade sweep obtains its fraction, normal and collider in one adapter query")
	if contact.has("normal"):
		var normal: Vector3 = contact["normal"]
		var departing := from + motion * float(contact["safe"]) + normal * 0.01
		var outgoing := GrenadeFlight._sweep(test.space(), departing, normal * 16.0, [])
		_check(float(outgoing["safe"]) == 1.0 and not outgoing.has("normal"),
			"a grenade leaving its impact with the gameplay's 0.01-inch offset is unobstructed")
	var fire := FireSpread.new(GrenadeRules.MOLOTOV, Vector3(200.0, 0.0, 0.0), 0, 1024)
	fire.spread(test.space(), 1_000_000)
	var on_floor := fire.flames.size() > 1
	for flame in fire.flames:
		on_floor = on_floor and absf(flame.y) < 0.25
	_check(on_floor, "fire spread finds native ground and places its flames on that surface")
	_close(test)


## Characterize the pinned backend's small-hull contract before porting
## CS2's box projectile. These are backend tolerances, not CS2 targets.
## Player sweeps use a separate clearance/recovery contract.
func _check_projectile_contact_band(kind: String) -> void:
	var test := _case()
	_wall(test.geometry, kind, Vector3(512.0, 16.0, 512.0), Vector3(0.0, -8.0, 0.0), "concrete")
	if not await _start(test):
		_close(test)
		return
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 4.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.margin = 0.0
	query.collision_mask = Hitscan.WORLD_LAYER
	query.transform.origin = Vector3(0.0, 3.0, 0.0)
	query.motion = Vector3(16.0, -2.0, 0.0)
	var hit := PhysicsQueries.shape_cast(test.space(), query)
	_check(not hit.is_empty() and absf(3.0 - 2.0 * float(hit.get("fraction", 1.0)) - 2.25685) < 0.005
		and (hit.get("normal", Vector3.ZERO) as Vector3).y > 0.99,
		"%s: a shallow four-inch box sweep retains the general query's contact clearance" % kind)
	query.transform.origin.y = 2.2
	query.motion = Vector3.DOWN * 2.0
	hit = PhysicsQueries.shape_cast(test.space(), query)
	_check(not hit.is_empty() and float(hit.get("fraction", 1.0)) == 0.0
		and (hit.get("normal", Vector3.UP) as Vector3).is_zero_approx(),
		"%s: the backend's small-box contact band reports a zero-normal hit at a physically clear start" % kind)
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	query.shape = sphere
	query.transform.origin.y = 3.0
	hit = PhysicsQueries.shape_cast(test.space(), query)
	_check(not hit.is_empty() and absf(3.0 - 2.0 * float(hit.get("fraction", 1.0)) - 1.86315) < 0.005,
		"%s: the existing sphere query has a different contact band; it is not a box substitute" % kind)
	if not hit.is_empty():
		var collider: CollisionObject3D = hit.get("collider")
		_check(collider != null and hit.get("rid") == collider.get_rid() and hit.get("shape") == 1,
			"%s: the full sweep keeps the original collider, RID and material shape index" % kind)
		query.exclude = [collider.get_rid()]
		_check(PhysicsQueries.shape_cast(test.space(), query).is_empty(),
			"%s: excluding the original RID removes the projectile's floor" % kind)
		query.exclude = []
		_check(not PhysicsQueries.shape_cast(test.space(), query).is_empty(),
			"%s: a projectile exclusion is restored for the following query" % kind)
	_close(test)


func _check_grenade_time_budget() -> void:
	var test := _case()
	# Faces at x=10 and x=-4: a radius-two grenade first travels eight
	# units right, then ten left, then has only 0.00978 seconds left.
	_box(test.geometry, Vector3(4.0, 256.0, 256.0), Vector3(12.0, 64.0, 0.0), "concrete")
	_box(test.geometry, Vector3(4.0, 256.0, 256.0), Vector3(-6.0, 64.0, 0.0), "concrete")
	if not await _start(test):
		_close(test)
		return
	var flight := GrenadeFlight.new()
	flight.position = Vector3(0.0, 64.0, 0.0)
	flight.velocity = Vector3.RIGHT * 1000.0
	flight.step(test.space(), 0.04)
	_check(flight.bounces == 2 and flight.touches.size() == 2 and flight.velocity.x > 0.0,
		"a short corridor produces exactly two wall bounces within one flight step")
	# Distance / speed independently measures the time already travelled.
	# Use the observed impact locations so backend contact tolerances do
	# not mask a time-budget error. Account for the outgoing wall pushes.
	if flight.touches.size() == 2:
		var first: Vector3 = flight.touches[0]["position"]
		var second: Vector3 = flight.touches[1]["position"]
		var first_speed := (1000.0 + 0.03125) * 0.45
		var second_speed := (first_speed + 0.03125) * 0.45
		var spent := first.x / 1000.0 + (first.x - 0.01 - second.x) / first_speed
		var expected := second.x + 0.01 + second_speed * (0.04 - spent)
		_check(absf(flight.position.x - expected) < 0.01,
			"two bounces share the original 40 ms travel budget (x=%.5f, expected %.5f)" % [flight.position.x, expected])
	_check(absf(flight.velocity.x - 202.520390625) < 0.01,
		"each bounce uses the recovered 0.03125 clip push and 0.45 elasticity")
	_close(test)


func _check_grenade_masks() -> void:
	var test := _case()
	_box(test.geometry, Vector3(64.0, 128.0, 8.0), Vector3(0.0, 64.0, -64.0), "grenade_clip", GrenadeRules.GRENADE_CLIP_LAYER)
	_box(test.geometry, Vector3(64.0, 128.0, 8.0), Vector3(128.0, 64.0, -64.0), "player_clip", MapImporter.PLAYER_CLIP_LAYER)
	if not await _start(test):
		_close(test)
		return
	var clip := GrenadeFlight._sweep(test.space(), Vector3(0.0, 64.0, 0.0), Vector3(0.0, 0.0, -128.0), [])
	_check(float(clip["safe"]) < 0.5 and clip.has("normal"),
		"the full native mirror includes grenade clips for live grenade sweeps")
	var pass_player_clip := GrenadeFlight._sweep(test.space(), Vector3(128.0, 64.0, 0.0), Vector3(0.0, 0.0, -128.0), [])
	_check(float(pass_player_clip["safe"]) == 1.0,
		"live grenade collision masks still pass through player-only clips")
	_close(test)


func _check_drop_near_wall() -> void:
	var test := _case()
	ItemPhysics.use_table("res://tests/fixtures/item_physics.csv")
	_box(test.geometry, Vector3(128.0, 128.0, 2.0), Vector3(0.0, 64.0, -10.0), "concrete")
	var player := Node3D.new()
	test.geometry.add_child(player)
	if not await _start(test):
		ItemPhysics.use_table(ItemPhysics.PATH)
		_close(test)
		return
	var hull := ItemPhysics.of("weapon_ak47")
	var held := Transform3D(Basis.IDENTITY, Vector3(0.0, 60.0, -28.0)) * hull.held_bone
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull.shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 64.0, 0.0))
	query.collision_mask = Hitscan.WORLD_LAYER
	_check(not PhysicsQueries.intersect_shape(test.space(), query, 1).is_empty(),
		"a long dropped-gun hull detects the wall it already overlaps at the player's eyes")
	var cleared := ItemDrops._clear_of_walls(player, held, test.space(), "weapon_ak47")
	var centre := hull.body_of(hull.model_held_at(cleared)).origin
	_check(centre.z > -9.0 and cleared.origin.distance_to(held.origin) > 1.0 and cleared.basis.is_equal_approx(held.basis),
		"the drop's overlap fallback keeps its centre on the near side of the wall without turning the gun")
	ItemPhysics.use_table(ItemPhysics.PATH)
	_close(test)


func _case() -> _Case:
	var test := _Case.new()
	test.host = Node3D.new()
	root.add_child(test.host)
	test.geometry = Node3D.new()
	test.host.add_child(test.geometry)
	test.game = GameSystems.new()
	test.adapter = Box3DDrops.new()
	test.host.add_child(test.adapter)
	return test


func _start(test: _Case) -> bool:
	for frame in 3:
		await physics_frame
	var initialized := test.adapter.initialize(test.game, test.geometry, true)
	_check(initialized and PhysicsQueries.for_space(test.space()) != null,
		"the gameplay fixture binds a full native query adapter")
	test.native_before = PhysicsQueries.native_queries
	test.legacy_before = PhysicsQueries.legacy_queries
	return initialized


func _target(test: _Case) -> HitTarget:
	var target := HitTarget.new()
	target.build_visual = false
	target.max_health = 1000.0
	target.armor = 0.0
	target.helmet = false
	target.position = Vector3(0.0, 0.0, -128.0)
	test.geometry.add_child(target)
	test.game.add_player(target, target)
	return target


func _shot() -> Weapon.Shot:
	var shot := Weapon.Shot.new()
	shot.origin = Vector3(0.0, 66.5, 0.0)
	shot.direction = Vector3.FORWARD
	return shot


func _wall(parent: Node3D, kind: String, size: Vector3, at: Vector3, surface: String) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Hitscan.WORLD_LAYER
	body.collision_mask = 0
	body.position = at
	# The hit wall is deliberately the second shape: material lookup must
	# preserve the source body's shape index rather than native index zero.
	var away := CollisionShape3D.new()
	away.name = "physics_group_sky"
	away.position.x = 512.0
	away.shape = BoxShape3D.new()
	body.add_child(away)
	var collision := CollisionShape3D.new()
	collision.name = "physics_group_" + surface
	if kind == "mesh":
		var mesh := BoxMesh.new()
		mesh.size = size
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(mesh.get_faces())
		collision.shape = shape
	else:
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _box(parent: Node3D, size: Vector3, at: Vector3, surface: String, layer: int = Hitscan.WORLD_LAYER) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = at
	var collision := CollisionShape3D.new()
	collision.name = "physics_group_" + surface
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _close(test: _Case) -> void:
	if test.adapter.initialized:
		_check(PhysicsQueries.native_queries > test.native_before and PhysicsQueries.legacy_queries == test.legacy_before,
			"the gameplay checks used native queries without falling back to the Godot space")
	test.host.free()
	# GameSystems owns ItemDrops, which holds its game. Break that test-fixture
	# reference cycle once its native adapter and scene have been freed.
	for system in test.game.systems():
		if system is ItemDrops:
			system.game = null


class _Case:
	extends RefCounted
	var host: Node3D
	var geometry: Node3D
	var game: GameSystems
	var adapter: Box3DDrops
	var native_before: int = 0
	var legacy_before: int = 0

	func space() -> PhysicsDirectSpaceState3D:
		return host.get_world_3d().direct_space_state
