extends "res://tests/check_suite.gd"

## Substep-scale contacts, outgoing motion and blocked starts. Test the
## native box and triangle paths at both origin and map-scale coordinates.
var _host: Node3D
var _game: GameSystems
var _adapter: Box3DDrops
var _floor: StaticBody3D


func _initialize() -> void:
	if not Box3DDrops.available():
		_skip("projectile-trace", "Install the patched Box3D addon")
		return
	for kind in ["box", "mesh"]:
		for origin in [Vector3.ZERO, Vector3(4096.0, 2048.0, -4096.0)]:
			await _fixture(kind, origin, true)
	await _fixture("box", Vector3.ZERO, false)
	await _corners_and_launch()
	await _slope()
	await _body_hit()
	_finish("projectile-trace")


func _fixture(kind: String, origin: Vector3, native: bool) -> void:
	_host = Node3D.new()
	root.add_child(_host)
	_floor = StaticBody3D.new()
	_floor.position = origin + Vector3.DOWN * 8.0
	_floor.collision_layer = 1
	_floor.collision_mask = 0
	var dummy := CollisionShape3D.new()
	dummy.position.x = 1024.0
	dummy.shape = BoxShape3D.new()
	_floor.add_child(dummy)
	var shape := CollisionShape3D.new()
	if kind == "mesh":
		var mesh := BoxMesh.new()
		mesh.size = Vector3(512.0, 16.0, 512.0)
		var triangles := ConcavePolygonShape3D.new()
		triangles.set_faces(mesh.get_faces())
		shape.shape = triangles
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(512.0, 16.0, 512.0)
		shape.shape = box
	_floor.add_child(shape)
	_host.add_child(_floor)
	for frame in 3:
		await physics_frame
	_game = GameSystems.new()
	_adapter = Box3DDrops.new()
	if native:
		_host.add_child(_adapter)
		_check(_adapter.initialize(_game, _host, true), "%s fixture uses native physics" % kind)
	var space := _host.get_world_3d().direct_space_state
	var label := "%s/%s at %s" % ["native" if native else "legacy", kind, origin]
	for gap in [1.0, 0.2, 0.01]:
		var start: Vector3 = origin + Vector3.UP * (2.0 + float(gap))
		var hit := _trace(space, start, Vector3.DOWN * 2.0)
		_check(hit.hit and not hit.blocked_start, "%s: gap %.3f returns a contact plane" % [label, gap])
		_check(absf(float(hit.fraction) - gap / 2.0) < 0.002, "%s: gap %.3f preserves geometric flight fraction" % [label, gap])
		_check((hit.normal as Vector3).y > 0.99 and hit.collider == _floor and hit.rid == _floor.get_rid() and hit.shape == 1,
			"%s: preserves floor plane and original second-shape identity" % label)
		_check((hit.end as Vector3).distance_to(start + Vector3.DOWN * 2.0 * float(hit.fraction) + hit.offset) < 0.0005,
			"%s: clearance changes position independently of flight time" % label)
		_check(not _trace(space, hit.end, Vector3.UP * 0.002).hit,
			"%s: a very small rebound leaves contact" % label)
		_check(not _trace(space, hit.end, Vector3.RIGHT * 0.02).hit,
			"%s: a very small tangent sweep clears contact" % label)
	var contact := origin + Vector3.UP * 2.0
	_check(not _trace(space, contact, Vector3.UP * 1.0).hit, "%s: exact contact permits outward motion" % label)
	_check(not _trace(space, contact, Vector3.RIGHT * 16.0).hit, "%s: exact contact permits tangent motion" % label)
	var inward := _trace(space, contact, Vector3.DOWN)
	_check(inward.hit and not inward.blocked_start and inward.fraction < 0.001 and inward.normal.y > 0.99,
		"%s: exact contact retains the incoming plane" % label)
	var embedded := _trace(space, origin + Vector3.UP, Vector3.RIGHT * 16.0)
	_check(embedded.hit and embedded.blocked_start and embedded.fraction == 0.0 and embedded.normal == Vector3.ZERO,
		"%s: embedded start stops without inventing a bounce normal" % label)
	_check(not _trace(space, origin + Vector3.UP * 4.0, Vector3.DOWN * 8.0, 32).hit,
		"%s: grenade-only mask does not collide with world layer" % label)
	var excluded := _trace(space, origin + Vector3.UP * 4.0, Vector3.DOWN * 8.0, 1, [_floor.get_rid()])
	_check(not excluded.hit, "%s: excludes the original body RID" % label)
	_check(_trace(space, origin + Vector3.UP * 4.0, Vector3.DOWN * 8.0).hit,
		"%s: restores excluded native proxies after the query" % label)
	if native:
		var before := PhysicsQueries.native_queries
		var legacy := PhysicsQueries.legacy_queries
		_trace(space, origin + Vector3.UP * 4.0, Vector3.DOWN * 8.0)
		_check(PhysicsQueries.native_queries == before + 1 and PhysicsQueries.legacy_queries == legacy,
			"%s: one native query, no legacy recovery query" % label)
	else:
		_adapter.free()
	_host.free()
	for system in _game.systems():
		if system is ItemDrops:
			system.game = null
	_game = null


func _trace(space: PhysicsDirectSpaceState3D, from: Vector3, motion: Vector3, mask: int = 1, exclude: Array[RID] = []) -> Dictionary:
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 4.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.margin = 0.0
	query.transform.origin = from
	query.motion = motion
	query.collision_mask = mask
	query.exclude = exclude
	return PhysicsQueries.projectile_trace(space, query)


func _corners_and_launch() -> void:
	_host = Node3D.new()
	root.add_child(_host)
	var importer := MapImporter.new()
	importer.report = false
	_host.add_child(importer)
	# Floor and wall share ONE concave shape. Leaving a touching triangle
	# must not exclude the whole mesh and tunnel through its other wall.
	var mesh := ArrayMesh.new()
	var floor := BoxMesh.new()
	floor.size = Vector3(512.0, 16.0, 512.0)
	var wall := BoxMesh.new()
	wall.size = Vector3(4.0, 128.0, 128.0)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = Transform3D(Basis.IDENTITY, Vector3.DOWN * 8.0) * floor.get_faces() \
		+ Transform3D(Basis.IDENTITY, Vector3(18.0, 64.0, 0.0)) * wall.get_faces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	importer.add_child(node)
	var ceiling := MeshInstance3D.new()
	var ceiling_mesh := BoxMesh.new()
	ceiling_mesh.size = Vector3(128.0, 4.0, 128.0)
	ceiling.mesh = ceiling_mesh
	ceiling.position = Vector3(-128.0, 66.0, 0.0)
	importer.add_child(ceiling)
	importer._build_collision([node, ceiling])
	for frame in 3:
		await physics_frame
	_game = GameSystems.new()
	_adapter = Box3DDrops.new()
	_host.add_child(_adapter)
	_check(_adapter.initialize(_game, _host, true), "corner fixture binds a native mesh world")
	var space := _host.get_world_3d().direct_space_state
	var corner := _trace(space, Vector3(0.0, 2.0, 0.0), Vector3.RIGHT * 32.0)
	_check(corner.hit and not corner.blocked_start and corner.normal.x < -0.99
		and absf(float(corner.fraction) - 14.0 / 32.0) < 0.001,
		"a tangent departure from the floor still hits a wall in the same mesh")
	var flight := GrenadeFlight.new()
	flight.position = Vector3(0.0, 1.0, 0.0)
	flight.velocity = Vector3.RIGHT * 500.0
	flight.step(space, 1.0 / 64.0)
	_check(flight.at_rest and flight.blocked_start and flight.velocity == Vector3.ZERO and flight.touches.is_empty(),
		"embedded grenade stops without a fabricated rebound or bounce event")
	var launch := GrenadeFlight.throw_from(space, GrenadeRules.HE, Vector3(-128.0, 64.0, 0.0),
		0.0, 0.0, Vector3.ZERO, 1.0, [], Vector3(-128.0, 36.0, 0.0))
	_check(not launch.blocked_start and launch.position.y < 62.0 and launch.position.y > 61.9,
		"pawn-center launch clips the 2.02-inch box against a low ceiling even when the eye starts too close")
	var moving := CharacterBody3D.new()
	moving.collision_layer = PlayerSim.PLAYER_LAYER
	moving.collision_mask = 0
	moving.position = Vector3(-80.0, 16.0, 0.0)
	var moving_shape := CollisionShape3D.new()
	var moving_box := BoxShape3D.new()
	moving_box.size = Vector3.ONE * 16.0
	moving_shape.shape = moving_box
	moving.add_child(moving_shape)
	_host.add_child(moving)
	_check(_trace(space, Vector3(-104.0, 16.0, 0.0), Vector3.RIGHT * 48.0, 2).hit,
		"projectile query captures a newly added moving hull")
	moving.position.z = 64.0
	_check(not _trace(space, Vector3(-104.0, 16.0, 0.0), Vector3.RIGHT * 48.0, 2).hit,
		"another query in the same tick sees the hull's new position")
	_host.free()
	for system in _game.systems():
		if system is ItemDrops:
			system.game = null
	_game = null


func _slope() -> void:
	_host = Node3D.new()
	root.add_child(_host)
	var body := StaticBody3D.new()
	var basis := Basis(Vector3.FORWARD, deg_to_rad(30.0))
	var normal := basis.y
	body.transform = Transform3D(basis, -normal * 8.0)
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(512.0, 16.0, 512.0)
	collision.shape = shape
	body.add_child(collision)
	_host.add_child(body)
	for frame in 3:
		await physics_frame
	_game = GameSystems.new()
	_adapter = Box3DDrops.new()
	_host.add_child(_adapter)
	_check(_adapter.initialize(_game, _host, true), "slope fixture binds native physics")
	var space := _host.get_world_3d().direct_space_state
	var support := 2.0 * (absf(normal.x) + absf(normal.y))
	var start := normal * (support + 0.1)
	var motion := basis.x * 64.0 - normal * 2.0
	var hit := _trace(space, start, motion)
	_check(hit.hit and not hit.blocked_start and hit.normal.dot(normal) > 0.999,
		"an axis-aligned box meeting an angled floor retains its oblique plane")
	_check(absf(float(hit.fraction) - 0.05) < 0.001,
		"a grazing angled-floor hit keeps the geometric fraction")
	_check(not _trace(space, hit.end, basis.x * 0.02 + normal * 0.002).hit,
		"tiny tangent/outgoing motion leaves the angled floor")
	_host.free()
	for system in _game.systems():
		if system is ItemDrops:
			system.game = null
	_game = null


func _body_hit() -> void:
	_host = Node3D.new()
	root.add_child(_host)
	_game = GameSystems.new()
	var system := GrenadeSystem.new()
	_game.add_system(system)
	var owner := _BarePlayer.new()
	owner.position.x = 128.0
	owner.collision_layer = PlayerSim.PLAYER_LAYER
	owner.team = "T"
	_host.add_child(owner)
	owner.userid = _game.add_player(owner, owner.hit_target, owner.inventory)
	var enemy := _BarePlayer.new()
	enemy.collision_layer = PlayerSim.PLAYER_LAYER
	enemy.team = "CT"
	_host.add_child(enemy)
	enemy.userid = _game.add_player(enemy, enemy.hit_target, enemy.inventory)
	for frame in 3:
		await physics_frame
	_adapter = Box3DDrops.new()
	_host.add_child(_adapter)
	_check(_adapter.initialize(_game, _host, true), "enemy body fixture binds native hulls")
	var grenade := GrenadeEntity.new()
	grenade.system = system
	grenade.weapon_class = GrenadeRules.MOLOTOV
	grenade.owner_id = owner.userid
	grenade.team = owner.team
	grenade.flight = GrenadeFlight.new()
	grenade.flight.position = Vector3(18.5, 36.0, 0.0)
	grenade.flight.velocity = Vector3.LEFT * 100.0
	grenade.position = grenade.flight.position
	var t := SimTick.new(_game, 1, _host.get_world_3d().direct_space_state)
	var health := enemy.hit_target.health
	grenade._check_body_hit(t)
	_check(grenade.body_hit and absf(enemy.hit_target.health - (health - 2.0)) < 0.001,
		"nearby enemy body receives two impact damage once")
	_check(grenade.flight.velocity.distance_to(Vector3.RIGHT * 30.0) < 0.001,
		"separate body hit reflects radially and retains 0.3 of speed")
	_check_equal(grenade.fire_extension_usec, 4_000_000, "fire body hit extends its deadline by four seconds")
	var before := PhysicsQueries.native_queries
	grenade._check_body_hit(t)
	_check(enemy.hit_target.health == health - 2.0 and grenade.fire_extension_usec == 4_000_000
		and PhysicsQueries.native_queries == before,
		"repeat contact neither damages again, extends again nor queries again")
	grenade.body_hit = false
	enemy.team = "T"
	grenade._check_body_hit(t)
	_check(not grenade.body_hit and enemy.hit_target.health == health - 2.0,
		"a teammate does not consume the one-time enemy body hit")
	_host.free()
	for existing in _game.systems():
		if existing is ItemDrops or existing is GrenadeSystem:
			existing.game = null
	_game = null


class _BarePlayer extends PlayerSim:
	func _init() -> void:
		var collision := CollisionShape3D.new()
		collision.shape = BoxShape3D.new()
		add_child(collision)

	func wear_body(_weapon_model: String, _drawn: bool) -> void:
		pass
