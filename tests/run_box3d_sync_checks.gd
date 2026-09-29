extends "res://tests/check_suite.gd"

## Query-visible proxy state without an intervening world step or frame.
## These use authoring nodes and the public query facade, so changing how
## geometry/transforms are cached must preserve the same gameplay results.

const HULL_LAYER := 2


func _initialize() -> void:
	if not Box3DDrops.available():
		_skip("box3d-sync", "Box3D native addon is not installed; run scripts/install_box3d.ps1")
		return
	await physics_frame
	var frame := Engine.get_physics_frames()
	_check_successive_moves()
	_check_prepared_casts()
	_check_geometry_edits()
	_check_shared_resources()
	_check_bone_poses()
	_check_lifecycle_and_masks()
	_check_scope()
	_check_tick()
	_check(Engine.get_physics_frames() == frame,
		"all proxy edits are observed within the same physics frame")
	_finish("box3d-sync")


func _check_successive_moves() -> void:
	var test := _case()
	var parent := Node3D.new()
	test.host.add_child(parent)
	var hull := _hull(parent, Vector3(0, 32, -64))
	hull.velocity = Vector3(20, 0, 0)
	var hit := _ray(test, hull.global_position)
	_check(_identity(hit, hull, 0) and hit.get("linear_velocity") == hull.velocity,
		"native hull queries preserve original object, RID, shape index and velocity")
	hull.position.x = 64
	_check(_ray(test, Vector3(0, 32, -64)).is_empty()
		and _ray(test, hull.global_position).get("collider") == hull,
		"a first unannounced move reaches queries without begin/end-tick synchronization")
	hull.position.x = -64
	_check(_ray(test, Vector3(64, 32, -64)).is_empty()
		and _ray(test, hull.global_position).get("collider") == hull,
		"a second move in the same tick replaces the first native pose")
	var local := hull.transform
	parent.position = Vector3(256, 0, 0)
	parent.rotation.y = PI * 0.5
	_check(hull.transform == local and _ray(test, Vector3(-64, 32, -64)).is_empty()
		and _ray(test, hull.global_position).get("collider") == hull,
		"ancestor translation and rotation update collision with an unchanged local transform")
	parent.rotation = Vector3.ZERO
	parent.scale = Vector3(2, 1, 1)
	_check(_ray(test, hull.global_position + Vector3.RIGHT * 14).get("collider") == hull
		and _ray(test, hull.global_position + Vector3.RIGHT * 18).is_empty(),
		"inherited scale refreshes native geometry as well as the proxy pose")
	var sweep := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2
	sweep.shape = sphere
	sweep.collision_mask = HULL_LAYER
	sweep.transform.origin = hull.global_position + Vector3.BACK * 64
	sweep.motion = Vector3.FORWARD * 128
	_check(_identity(PhysicsQueries.shape_cast(test.space(), sweep), hull, 0),
		"a movement sweep sees the same moved hull and original identity as a ray")
	sweep.exclude = [hull.get_rid()]
	_check(PhysicsQueries.shape_cast(test.space(), sweep).is_empty()
		and _ray(test, hull.global_position).get("collider") == hull,
		"temporary sweep exclusion restores the cached proxy for the next query")
	_close(test)


func _check_prepared_casts() -> void:
	var test := _case()
	var first := _hull(test.host, Vector3(0, 32, -32))
	var second := _hull(test.host, Vector3(0, 32, -80))
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2
	query.shape = sphere
	query.collision_mask = HULL_LAYER
	query.transform.origin = Vector3(0, 32, 0)
	query.motion = Vector3.FORWARD * 128
	query.exclude = [first.get_rid()]
	var disabled := test.adapter.queries.begin_shape_cast(query)
	var hit := test.adapter.queries.shape_cast_prepared(query)
	test.adapter.queries.end_shape_cast(disabled)
	_check(_identity(hit, second, 0),
		"a prepared sweep excludes only its source and still finds the other character")
	_check(_identity(_ray(test, first.position), first, 0),
		"ending a prepared sweep restores its source for a subsequent ray")
	second.position.x = 64
	disabled = test.adapter.queries.begin_shape_cast(query)
	hit = test.adapter.queries.shape_cast_prepared(query)
	test.adapter.queries.end_shape_cast(disabled)
	_check(hit.is_empty() and _identity(_ray(test, second.position), second, 0),
		"the next prepared sweep synchronizes another character moved in the same tick")
	_check(_identity(_ray(test, first.position), first, 0),
		"a missed prepared sweep also restores the excluded source")
	_close(test)


func _check_geometry_edits() -> void:
	var test := _case()
	var hull := _hull(test.host, Vector3(0, 32, -64))
	var collision := hull.get_child(0) as CollisionShape3D
	var box := collision.shape as BoxShape3D
	_check(_ray(test, hull.position + Vector3.RIGHT * 12).is_empty(),
		"a ray outside the initial hull width misses")
	box.size.x = 32
	PhysicsQueries.sync_object(hull)
	_check(_ray(test, hull.position + Vector3.RIGHT * 12).get("collider") == hull,
		"explicit shape refresh observes resource resizing at a fixed body pose")
	collision.position.x = 48
	PhysicsQueries.sync_object(hull)
	_check(_ray(test, hull.position).is_empty()
		and _ray(test, hull.position + Vector3.RIGHT * 48).get("collider") == hull,
		"explicit refresh observes a changed shape-owner transform")
	var owner_id: int = hull.get_shape_owners()[0]
	hull.shape_owner_set_disabled(owner_id, true)
	PhysicsQueries.sync_object(hull)
	_check(_ray(test, hull.position + Vector3.RIGHT * 48).is_empty(),
		"disabling a cached shape removes its collision immediately")
	hull.shape_owner_set_disabled(owner_id, false)
	PhysicsQueries.sync_object(hull)
	hull.collision_layer = 0
	_check(_ray(test, hull.position + Vector3.RIGHT * 48).is_empty(),
		"layer removal suppresses a reenabled shape without a pose change")
	hull.collision_layer = HULL_LAYER
	_check(_ray(test, hull.position + Vector3.RIGHT * 48).get("collider") == hull,
		"restoring the layer restores collision without a world step")
	var sphere := SphereShape3D.new()
	sphere.radius = 4
	collision.shape = sphere
	PhysicsQueries.sync_object(hull)
	_check(_ray(test, hull.position + Vector3.RIGHT * 48).get("collider") == hull
		and _ray(test, hull.position + Vector3.RIGHT * 60).is_empty(),
		"replacing a box resource with a sphere discards the cached box dimensions")
	var extra := _shape(hull, Vector3(8, 8, 8), Vector3(-48, 0, 0))
	_check(_identity(_ray(test, hull.position + Vector3.LEFT * 48), hull, 1),
		"a late-added shape is queryable with its original source shape index")
	collision.free()
	PhysicsQueries.sync_object(hull)
	_check(_ray(test, hull.position + Vector3.RIGHT * 48).is_empty()
		and _identity(_ray(test, hull.position + extra.position), hull, 0),
		"removing a shape removes its proxy and preserves the remaining source index")
	_close(test)


func _check_shared_resources() -> void:
	var test := _case()
	var first := _hull(test.host, Vector3(0, 32, -64))
	var second := _hull(test.host, Vector3(128, 32, -64))
	var shared := (first.get_child(0) as CollisionShape3D).shape as BoxShape3D
	(second.get_child(0) as CollisionShape3D).shape = shared
	_check(_ray(test, first.position + Vector3.RIGHT * 12).is_empty()
		and _ray(test, second.position + Vector3.RIGHT * 12).is_empty(),
		"two separately registered hulls initially share the narrow shape resource")
	shared.size.x = 32
	var world_query := PhysicsRayQueryParameters3D.create(Vector3.UP * 64, Vector3.ZERO, Hitscan.WORLD_LAYER)
	PhysicsQueries.intersect_ray(test.space(), world_query)
	_check(_ray(test, first.position + Vector3.RIGHT * 12).get("collider") == first
		and _ray(test, second.position + Vector3.RIGHT * 12).get("collider") == second,
		"a shared resource edit refreshes both unmoved hulls after a world-only query")
	first.free()
	shared.size.x = 8
	_check(_ray(test, second.position + Vector3.RIGHT * 12).is_empty()
		and _ray(test, second.position).get("collider") == second,
		"removing one resource subscriber leaves the remaining hull's invalidation active")
	_close(test)


func _check_bone_poses() -> void:
	var test := _case()
	var skeleton := Skeleton3D.new()
	skeleton.position = Vector3(0, 32, -64)
	skeleton.add_bone("test_bone")
	test.host.add_child(skeleton)
	var target := HitTarget.new()
	target.build_own_hitboxes = false
	target.build_visual = false
	test.host.add_child(target)
	var skin := SkinnedHitboxes.new()
	test.host.add_child(skin)
	var capsules: Array[Dictionary] = [{
		"bone": "test_bone", "name": "chest", "zone": &"chest", "side": &"",
		"point0": Vector3(0, -4, 0), "point1": Vector3(0, 4, 0), "radius": 3.0,
	}]
	_check(skin.build(skeleton, capsules, target, 1.0) == 1,
		"the asset-free skeleton builds a real SkinnedHitboxes capsule")
	var part := skin.hitboxes[0]
	_check(_identity(_ray(test, skeleton.position, Hitbox.LAYER), part, 0) and part.target == target,
		"animated hitbox queries preserve their damage-zone and target identity")
	skeleton.set_bone_pose_position(0, Vector3(64, 0, 0))
	skin.follow()
	_check(_ray(test, skeleton.position, Hitbox.LAYER).is_empty()
		and _ray(test, skeleton.position + Vector3.RIGHT * 64, Hitbox.LAYER).get("collider") == part,
		"a freshly evaluated bone pose is queryable before the next skeleton frame")
	skeleton.set_bone_pose_position(0, Vector3(-64, 0, 0))
	skin.follow()
	_check(_ray(test, skeleton.position + Vector3.RIGHT * 64, Hitbox.LAYER).is_empty()
		and _ray(test, skeleton.position + Vector3.LEFT * 64, Hitbox.LAYER).get("collider") == part,
		"two different poses in one tick cannot reuse the first hitbox transform")
	skeleton.position.x = 128
	skin.follow()
	_check(_ray(test, Vector3(-64, 32, -64), Hitbox.LAYER).is_empty()
		and _ray(test, part.global_position, Hitbox.LAYER).get("collider") == part,
		"moving the skeleton node is reflected by the ordinary hitbox-follow path")
	target.set_active(false)
	_check(_ray(test, part.global_position, Hitbox.LAYER).is_empty(),
		"deactivating an animated target removes its cached hitboxes immediately")
	target.set_active(true)
	test.game.step(1, test.space())
	_check(_identity(_ray(test, part.global_position, Hitbox.LAYER), part, 0),
		"restored hitboxes retain the last explicit pose after native world stepping")
	_close(test)


func _check_lifecycle_and_masks() -> void:
	var test := _case()
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Hitscan.WORLD_LAYER
	floor_body.collision_mask = 0
	floor_body.position.y = -8
	_shape(floor_body, Vector3(256, 16, 256), Vector3.ZERO)
	test.host.add_child(floor_body)
	var hull := _hull(test.host, Vector3(0, 32, 0))
	var ground := PhysicsRayQueryParameters3D.create(Vector3(0, 64, 0), Vector3(0, -16, 0), Hitscan.WORLD_LAYER)
	# No facade query has run since these nodes spawned. The native solver
	# must receive new static geometry even on a tick with no gameplay casts.
	test.game.step(1, test.space())
	var native_hit: Dictionary = test.adapter.native_world.call(&"raycast",
		ground.from * Box3DQueries.SCALE, ground.to * Box3DQueries.SCALE,
		Hitscan.WORLD_LAYER, Box3DQueries.QUERY_LAYER)
	var native_body := native_hit.get("collider") as Node3D
	_check(bool(native_hit.get("hit", false)) and is_instance_valid(native_body)
		and int(native_body.get_meta(&"source_id", 0)) == floor_body.get_instance_id(),
		"the tick registers a newly spawned floor before any facade query can flush it")
	_check(_identity(PhysicsQueries.intersect_ray(test.space(), ground), floor_body, 0),
		"world-only rays capture late static geometry and ignore character proxies")
	_check(_ray(test, hull.position).get("collider") == hull,
		"a late-spawned character is captured by the first matching query")
	hull.position.x = 64
	_check(PhysicsQueries.intersect_ray(test.space(), ground).get("collider") == floor_body
		and _ray(test, Vector3(0, 32, 0)).is_empty()
		and _ray(test, hull.position).get("collider") == hull,
		"an intervening world-only query cannot consume a pending character move")
	var rid := hull.get_rid()
	test.host.remove_child(hull)
	_check(_ray(test, Vector3(64, 32, 0)).is_empty(),
		"removing a character from the tree removes its native collision immediately")
	test.host.add_child(hull)
	_check(_identity(_ray(test, hull.position), hull, 0) and hull.get_rid() == rid,
		"reentering the tree registers the same source object and RID afresh")
	hull.free()
	_check(_ray(test, Vector3(64, 32, 0)).is_empty(),
		"freeing a registered character leaves no stale query hit")
	floor_body.free()
	_check(PhysicsQueries.intersect_ray(test.space(), ground).is_empty(),
		"freeing a late static body also removes its world-only query hit")
	_close(test)


## A player's tick is a scope (Box3DQueries.begin_scope): its owner is out
## of the native world for it, whether a query leaves it out or not, the
## others are met, and all is as it was when the scope ends.
func _check_scope() -> void:
	var test := _case()
	var mover := _hull(test.host, Vector3(0, 32, -64))
	var other := _hull(test.host, Vector3(128, 32, -64))
	_check(_ray(test, mover.global_position).get("collider") == mover
		and _ray(test, other.global_position).get("collider") == other,
		"two hulls are met before any scope")
	var queries := test.adapter.queries
	queries.begin_scope(mover.get_rid())
	_check(_ray(test, mover.global_position).is_empty() and _ray(test, other.global_position).get("collider") == other,
		"a scope's owner is out of the native world, left out of the query or not, and the others are met")
	var sweep := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16, 16, 16)
	sweep.shape = box
	sweep.collision_mask = HULL_LAYER
	sweep.exclude = [mover.get_rid()]
	sweep.transform.origin = mover.global_position
	sweep.motion = Vector3.RIGHT * 200
	var left_out := queries.begin_shape_cast(sweep)
	var met := queries.shape_cast_prepared(sweep)
	queries.end_shape_cast(left_out)
	_check(left_out.is_empty() and met.get("collider") == other,
		"the owner's own sweep leaves nothing more out, and meets the other hull")
	other.position.x = 96
	_check(_ray(test, other.global_position).is_empty() and _ray(test, Vector3(128, 32, -64)).get("collider") == other,
		"another hull moved by hand inside the scope is not looked for again until it ends")
	queries.end_scope()
	_check(_ray(test, mover.global_position).get("collider") == mover
		and _ray(test, other.global_position).get("collider") == other,
		"the scope over, its owner is back in the world and the other is found where it went")
	queries.begin_scope(mover.get_rid())
	((mover.get_child(0) as CollisionShape3D).shape as BoxShape3D).size = Vector3(16, 8, 16)
	PhysicsQueries.sync_object(mover)
	_check(_ray(test, mover.global_position).is_empty(),
		"a hull resized inside its own scope (a duck) stays out of the world")
	queries.end_scope()
	_check(_ray(test, mover.global_position).get("collider") == mover
		and _ray(test, mover.global_position + Vector3.UP * 6.0).is_empty(),
		"and is back, at its new size, when the scope ends")
	_close(test)


## In a tick (Box3DQueries.begin_tick) the hulls are looked over once:
## what moves one in a tick publishes it, and one moved without is where it
## was until the tick ends.
func _check_tick() -> void:
	var test := _case()
	var first := _hull(test.host, Vector3(0, 32, -64))
	var second := _hull(test.host, Vector3(128, 32, -64))
	var queries := test.adapter.queries
	first.position.x = 32
	queries.begin_tick()
	_check(_ray(test, first.global_position).get("collider") == first and _ray(test, Vector3(0, 32, -64)).is_empty(),
		"a hull moved before the tick is found by the tick's first query")
	second.position.x = 96
	_check(_ray(test, second.global_position).is_empty() and _ray(test, Vector3(128, 32, -64)).get("collider") == second,
		"one moved by hand inside the tick is not looked for again")
	PhysicsQueries.sync_object(second, false)
	_check(_ray(test, second.global_position).get("collider") == second and _ray(test, Vector3(128, 32, -64)).is_empty(),
		"and is found where it is once it is published")
	first.collision_layer = 0
	PhysicsQueries.sync_object(first, false)
	_check(_ray(test, first.global_position).is_empty(),
		"a hull taken off its layer in the tick and published, as a death does, is met by nobody after it")
	first.collision_layer = HULL_LAYER
	first.position.x = 64
	queries.end_tick()
	_check(_ray(test, first.global_position).get("collider") == first,
		"the tick over, a hull moved by hand is found by the next query, as before")
	_close(test)


func _case() -> _Case:
	var test := _Case.new()
	test.host = Node3D.new()
	root.add_child(test.host)
	test.game = GameSystems.new()
	test.adapter = Box3DDrops.new()
	test.host.add_child(test.adapter)
	_check(test.adapter.initialize(test.game, test.host, true), "the native synchronization fixture initializes")
	test.native_before = PhysicsQueries.native_queries
	test.legacy_before = PhysicsQueries.legacy_queries
	return test


func _close(test: _Case) -> void:
	_check(PhysicsQueries.native_queries > test.native_before and PhysicsQueries.legacy_queries == test.legacy_before,
		"synchronization checks execute native queries without a legacy fallback")
	test.host.free()
	for system in test.game.systems():
		if system is ItemDrops:
			system.game = null
	# SimTick retains its GameSystems owner; the one stepping case must
	# release that final snapshot as well as ItemDrops' attachment cycle.
	test.game.last_tick = null


func _hull(parent: Node3D, at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.position = at
	body.collision_layer = HULL_LAYER
	body.collision_mask = 0
	_shape(body, Vector3(16, 16, 16), Vector3.ZERO)
	parent.add_child(body)
	return body


func _shape(body: CollisionObject3D, size: Vector3, at: Vector3) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	collision.position = at
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	return collision


func _ray(test: _Case, center: Vector3, mask: int = HULL_LAYER) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(center + Vector3.BACK * 64, center + Vector3.FORWARD * 64, mask)
	query.collide_with_areas = mask & Hitbox.LAYER != 0
	query.collide_with_bodies = mask & Hitbox.LAYER == 0
	return PhysicsQueries.intersect_ray(test.space(), query)


func _identity(hit: Dictionary, body: CollisionObject3D, shape: int) -> bool:
	return hit.get("collider") == body and hit.get("collider_id") == body.get_instance_id() \
		and hit.get("rid") == body.get_rid() and hit.get("shape") == shape


class _Case:
	extends RefCounted
	var host: Node3D
	var game: GameSystems
	var adapter: Box3DDrops
	var native_before: int
	var legacy_before: int

	func space() -> PhysicsDirectSpaceState3D:
		return host.get_world_3d().direct_space_state
