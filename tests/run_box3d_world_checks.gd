extends "res://tests/check_suite.gd"

## Native world ownership and collider lifecycle, including late-spawned
## shapes and restoring the engine comparison space when the adapter exits.

func _initialize() -> void:
	if not Box3DDrops.available():
		_skip("box3d-world", "Box3D native addon is not installed")
		return
	await physics_frame
	var host := Node3D.new()
	root.add_child(host)
	var floor_body := _box(host, Vector3(256, 16, 256), Vector3(0, -8, 0))
	var adapter := Box3DDrops.new()
	host.add_child(adapter)
	var game := GameSystems.new()
	_check(adapter.initialize(game, host, true), "the full native world initializes")
	var space := host.get_world_3d().direct_space_state
	_check(PhysicsQueries.adapter_for_node(host) == adapter, "queries resolve the owning native world")
	_check(not PhysicsServer3D.body_get_space(floor_body.get_rid()).is_valid(),
		"authored world collision is detached from Godot's simulation")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 64, 0), Vector3(0, -32, 0), 1)
	await physics_frame
	_check(space.intersect_ray(ray).is_empty(), "the native floor is not a second active Godot floor")
	_check(PhysicsQueries.intersect_ray(space, ray).get("collider") == floor_body,
		"native queries still return the original floor identity")
	var added := _box(host, Vector3(16, 16, 16), Vector3(0, 24, 0))
	_check(PhysicsQueries.intersect_ray(space, ray).get("collider") == added,
		"a shape added after initialization is queryable immediately")
	_check(not PhysicsServer3D.body_get_space(added.get_rid()).is_valid(),
		"late geometry is also removed from the engine space")
	added.free()
	_check(PhysicsQueries.intersect_ray(space, ray).get("collider") == floor_body,
		"removing geometry removes its native collider without a ghost hit")
	_check(adapter.capture_world(host), "static collision can be refreshed after removing a body")
	_check(PhysicsQueries.intersect_ray(space, ray).get("collider") == floor_body,
		"recapture preserves source identity")
	var target := HitTarget.new()
	target.build_visual = false
	target.position = Vector3(0, 0, -64)
	host.add_child(target)
	var people := PhysicsRayQueryParameters3D.create(Vector3(0, 66.5, 0), Vector3(0, 66.5, -128), Hitbox.LAYER)
	people.collide_with_areas = true
	people.collide_with_bodies = false
	var hit := PhysicsQueries.intersect_ray(space, people)
	_check(hit.get("collider") is Hitbox and (hit["collider"] as Hitbox).target == target,
		"late hitbox capsules or boxes join the same world")
	var part := hit.get("collider") as Hitbox
	_check(part != null and not PhysicsServer3D.area_get_space(part.get_rid()).is_valid(),
		"native hitboxes have no duplicate engine area")
	target.position.x = 128
	_check(PhysicsQueries.intersect_ray(space, people).is_empty(),
		"moving a target updates native hitboxes before the next query")
	target.position.x = 0
	target.set_active(false)
	_check(PhysicsQueries.intersect_ray(space, people).is_empty(),
		"disabling a target immediately removes its native hitbox layer")
	target.set_active(true)
	_check(PhysicsQueries.intersect_ray(space, people).get("collider") == part,
		"reenabling a target restores its original hitbox identity")
	var owner_id: int = part.get_shape_owners()[0]
	part.shape_owner_set_disabled(owner_id, true)
	PhysicsQueries.sync_object(part)
	_check(PhysicsQueries.intersect_ray(space, people).is_empty(),
		"explicit synchronization refreshes a disabled shape at an unchanged pose")
	part.shape_owner_set_disabled(owner_id, false)
	PhysicsQueries.sync_object(part)
	_check(PhysicsQueries.intersect_ray(space, people).get("collider") == part,
		"explicit synchronization restores that shape without a pose or layer change")
	adapter.free()
	await physics_frame
	_check(PhysicsQueries.for_space(space) == null, "destroying the adapter unregisters the native space")
	_check(PhysicsServer3D.body_get_space(floor_body.get_rid()) == host.get_world_3d().space,
		"exiting the native adapter restores authored bodies for comparison")
	_check(space.intersect_ray(ray).get("collider") == floor_body,
		"the restored engine space can query its floor again")
	host.free()
	for system in game.systems():
		if system is ItemDrops:
			system.game = null
	_finish("box3d-world")


func _box(parent: Node3D, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.name = "physics_group_concrete"
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body
