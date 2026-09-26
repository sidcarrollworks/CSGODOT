class_name Box3DQueries
extends RefCounted

## Native collision queries, with Source units and Godot authoring-node
## identities at the boundary. Authoring bodies are detached from Godot's
## simulation while this bridge owns their collision.
## Meshes use front faces only, matching imported map collision. The binding
## cannot enable authored mesh backface collision or honor hit_back_faces.
const SCALE := 0.0254
const QUERY_LAYER := 1 << 30
const ALL_LAYERS := 0x7fffffff
## v0.4.3's sweep stops 0.197 inches out, but its initial-contact test
## reaches about 0.246. Leave enough normal clearance for an outgoing
## sweep (grenade rebound or player sliding) to start outside that band.
const CAST_CLEARANCE := 0.06

var adapter: Node3D
var native_world: Node3D
var space_id: int
var _root: Node
var _original_space: RID
var _objects: Dictionary = {}
var _by_rid: Dictionary = {}
var _dynamic: Dictionary = {}
var _hulls: Dictionary = {}
var _hitboxes: Dictionary = {}
var _hull_layers: int = 2
var _hitbox_layers: int = Hitbox.LAYER
var _dynamic_layers: int = 2 | Hitbox.LAYER
var _pending: Array[WeakRef] = []
var _cast_cache: Dictionary = {}


func initialize(owner: Node3D, geometry_root: Node) -> void:
	adapter = owner
	native_world = owner.native_world
	_root = geometry_root
	var world := geometry_root.get_viewport().find_world_3d()
	_original_space = world.space
	space_id = world.direct_space_state.get_instance_id()
	PhysicsQueries.register(world.direct_space_state, self)
	_scan(geometry_root)
	geometry_root.get_tree().node_added.connect(_on_node_added)
	geometry_root.get_tree().node_removed.connect(_on_node_removed)


func close() -> void:
	PhysicsQueries.unregister(space_id, self)
	if is_instance_valid(_root) and _root.is_inside_tree():
		if _root.get_tree().node_added.is_connected(_on_node_added):
			_root.get_tree().node_added.disconnect(_on_node_added)
		if _root.get_tree().node_removed.is_connected(_on_node_removed):
			_root.get_tree().node_removed.disconnect(_on_node_removed)
	for record: Dictionary in _objects.values():
		var source := (record["source"] as WeakRef).get_ref() as CollisionObject3D
		if is_instance_valid(source) and source.is_inside_tree():
			if source is Area3D:
				PhysicsServer3D.area_set_space(source.get_rid(), _original_space)
			else:
				PhysicsServer3D.body_set_space(source.get_rid(), _original_space)
	_objects.clear()
	_by_rid.clear()
	_dynamic.clear()
	_hulls.clear()
	_hitboxes.clear()
	_pending.clear()


func refresh_statics() -> void:
	for id: int in _objects.keys():
		if not _dynamic.has(id):
			_by_rid.erase(_objects[id]["rid"])
			_objects.erase(id)
	_scan(_root)


func _scan(node: Node) -> void:
	if node == adapter:
		return
	if node is CollisionObject3D:
		sync_object(node)
	for child in node.get_children():
		_scan(child)


func _on_node_added(node: Node) -> void:
	if node is CollisionObject3D:
		_pending.append(weakref(node))
	elif node is CollisionShape3D and node.get_parent() is CollisionObject3D:
		_pending.append(weakref(node.get_parent()))


func _on_node_removed(node: Node) -> void:
	if node is CollisionObject3D and _objects.has(node.get_instance_id()):
		_remove(node.get_instance_id())


func flush_pending() -> void:
	var pending := _pending
	_pending = []
	for ref: WeakRef in pending:
		var node := ref.get_ref() as CollisionObject3D
		if is_instance_valid(node) and node.is_inside_tree() and (_root == node or _root.is_ancestor_of(node)):
			sync_object(node)


func sync_dynamic(mask: int = ALL_LAYERS) -> void:
	flush_pending()
	if mask & _dynamic_layers == 0:
		return
	# Movement never needs to revisit every bone capsule. Keep separate
	# registries so a hull sweep only synchronizes the character hulls.
	if mask & _hull_layers != 0:
		_sync_group(_hulls, mask)
	if mask & _hitbox_layers != 0:
		_sync_group(_hitboxes, mask)


func _sync_group(group: Dictionary, mask: int) -> void:
	for id: int in group.keys():
		var node := (group[id] as WeakRef).get_ref() as CollisionObject3D
		if not is_instance_valid(node) or not node.is_inside_tree():
			_remove(id)
		elif node.collision_layer & mask != 0 or int(_objects[id].get("layer", 0)) & mask != 0:
			sync_object(node, false)


func _remove(id: int) -> void:
	var record: Dictionary = _objects.get(id, {})
	for proxy: Node3D in record.get("proxies", []):
		if is_instance_valid(proxy):
			proxy.free()
	_objects.erase(id)
	_by_rid.erase(record.get("rid", RID()))
	_dynamic.erase(id)
	_hulls.erase(id)
	_hitboxes.erase(id)
	_cast_cache.clear()


func sync_object(source: CollisionObject3D, refresh_shapes: bool = true) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree():
		return
	if not (source is StaticBody3D or source is CharacterBody3D or source is Hitbox):
		return
	var id := source.get_instance_id()
	if source is StaticBody3D:
		if not _objects.has(id):
			var proxies: Array[Node3D] = []
			for native: Node in native_world.get_children():
				if int(native.get_meta(&"source_id", 0)) == id:
					proxies.append(native as Node3D)
			if proxies.is_empty() and source.collision_layer != 0:
				adapter.capture_static_body(source)
				for native: Node in native_world.get_children():
					if int(native.get_meta(&"source_id", 0)) == id:
						proxies.append(native as Node3D)
			_objects[id] = {"source": weakref(source), "rid": source.get_rid(), "proxies": proxies, "layer": source.collision_layer}
			_by_rid[source.get_rid()] = id
			PhysicsServer3D.body_set_space(source.get_rid(), RID())
		return
	if not _objects.has(id):
		_objects[id] = {"source": weakref(source), "rid": source.get_rid(), "proxies": [], "shapes": [], "layer": source.collision_layer}
		_by_rid[source.get_rid()] = id
		_dynamic[id] = weakref(source)
		if source is Hitbox:
			_hitboxes[id] = _dynamic[id]
		else:
			_hulls[id] = _dynamic[id]
	_dynamic_layers |= source.collision_layer
	if source is Hitbox:
		_hitbox_layers |= source.collision_layer
	else:
		_hull_layers |= source.collision_layer
	if not _objects[id].has("detached"):
		_objects[id]["detached"] = true
		if source is Area3D:
			PhysicsServer3D.area_set_space(source.get_rid(), RID())
		else:
			PhysicsServer3D.body_set_space(source.get_rid(), RID())
	var record: Dictionary = _objects[id]
	# Repeated queries see the same poses. Explicit syncs (movement/duck,
	# shape additions and tools) still refresh geometry at an unchanged pose.
	if not refresh_shapes and record.get("at") == source.global_transform and int(record["layer"]) == source.collision_layer:
		return
	var slot := 0
	for owner_id: int in source.get_shape_owners():
		for index in source.shape_owner_get_shape_count(owner_id):
			var shape := source.shape_owner_get_shape(owner_id, index)
			var at := source.global_transform * source.shape_owner_get_transform(owner_id)
			var proxy: Node3D
			if slot >= record["proxies"].size():
				proxy = ClassDB.instantiate(&"Box3DBody") as Node3D
				proxy.set(&"body_type", ClassDB.class_get_integer_constant(&"Box3DBody", &"KINEMATIC"))
				proxy.set(&"is_sensor", true)
				proxy.set(&"collision_mask", QUERY_LAYER)
				proxy.set(&"sync_node_transform", false)
				proxy.set_meta(&"source_id", id)
				proxy.set_meta(&"source_rid", source.get_rid())
				proxy.set_meta(&"source_shape", source.shape_owner_get_shape_index(owner_id, index))
				proxy.set_meta(&"source_area", source is Area3D)
				proxy.set_meta(&"source_solid", true)
				_configure_shape(proxy, shape, at.basis.get_scale())
				proxy.transform = Transform3D(at.basis.orthonormalized(), at.origin * SCALE)
				native_world.add_child(proxy)
				record["proxies"].append(proxy)
				record["shapes"].append(_shape_key(shape, at.basis.get_scale()))
			else:
				proxy = record["proxies"][slot]
				var key := _shape_key(shape, at.basis.get_scale())
				if record["shapes"][slot] != key:
					_configure_shape(proxy, shape, at.basis.get_scale())
					record["shapes"][slot] = key
			var layer := 0 if source.is_shape_owner_disabled(owner_id) else source.collision_layer
			if int(proxy.get(&"collision_layer")) != layer:
				proxy.set(&"collision_layer", layer)
			var native_at := Transform3D(at.basis.orthonormalized(), at.origin * SCALE)
			if not proxy.transform.is_equal_approx(native_at):
				proxy.call(&"teleport", native_at)
				proxy.transform = native_at
			slot += 1
	while record["proxies"].size() > slot:
		(record["proxies"].pop_back() as Node3D).free()
		record["shapes"].pop_back()
	record["layer"] = source.collision_layer
	record["at"] = source.global_transform


static func _shape_key(shape: Shape3D, scale: Vector3) -> Array:
	if shape is BoxShape3D:
		return [shape.get_instance_id(), (shape as BoxShape3D).size, scale]
	if shape is CapsuleShape3D:
		return [shape.get_instance_id(), (shape as CapsuleShape3D).radius, (shape as CapsuleShape3D).height, scale]
	if shape is SphereShape3D:
		return [shape.get_instance_id(), (shape as SphereShape3D).radius, scale]
	return [shape.get_instance_id(), scale]


static func _configure_shape(body: Node3D, shape: Shape3D, scale: Vector3) -> void:
	scale = scale.abs()
	if shape is BoxShape3D:
		body.set(&"shape_type", ClassDB.class_get_integer_constant(&"Box3DBody", &"BOX"))
		body.set(&"box_size", (shape as BoxShape3D).size * scale * SCALE)
	elif shape is CapsuleShape3D:
		body.set(&"shape_type", ClassDB.class_get_integer_constant(&"Box3DBody", &"CAPSULE"))
		body.set(&"capsule_radius", (shape as CapsuleShape3D).radius * maxf(scale.x, scale.z) * SCALE)
		body.set(&"capsule_height", (shape as CapsuleShape3D).height * scale.y * SCALE)
	elif shape is SphereShape3D:
		body.set(&"shape_type", ClassDB.class_get_integer_constant(&"Box3DBody", &"SPHERE"))
		body.set(&"sphere_radius", (shape as SphereShape3D).radius * maxf(scale.x, maxf(scale.y, scale.z)) * SCALE)
	else:
		push_error("Unsupported dynamic Box3D query shape: %s" % shape.get_class())


func _mapped(hit: Dictionary) -> Dictionary:
	var native := hit.get("collider") as Node3D
	if not is_instance_valid(native):
		return {}
	var id := int(native.get_meta(&"source_id", 0))
	var source := instance_from_id(id) as CollisionObject3D if id != 0 else null
	if source == null:
		return {}
	var result := hit.duplicate()
	result["collider"] = source
	result["collider_id"] = id
	result["rid"] = source.get_rid()
	result["shape"] = int(native.get_meta(&"source_shape", 0))
	if hit.has("position"):
		result["position"] = (hit["position"] as Vector3) / SCALE
		result["point"] = result["position"]
	result["linear_velocity"] = source.velocity if source is CharacterBody3D else Vector3.ZERO
	return result


func intersect_ray(query: PhysicsRayQueryParameters3D) -> Dictionary:
	sync_dynamic(query.collision_mask)
	var mask := _mask(query.collision_mask, query.collide_with_bodies, query.collide_with_areas)
	# Unlike Godot's ray contract, Box3D convex casts can report a hit at
	# fraction zero when the start is inside. Penetration's exit search
	# depends on ignoring that solid; smoke explicitly requests the hit.
	var containing := {}
	var overlaps: Array = native_world.call(&"overlap_sphere", query.from * SCALE, 0.000001, mask, QUERY_LAYER)
	for native: Node3D in overlaps:
		if _excluded(native, query.exclude) or not bool(native.get_meta(&"source_solid", false)):
			continue
		if query.hit_from_inside:
			return _mapped({"hit": true, "collider": native, "position": query.from * SCALE, "normal": Vector3.ZERO, "fraction": 0.0})
		containing[native.get_instance_id()] = true
	# Sight/ground rays usually accept the nearest surface. Collecting every
	# triangle hit across a map is only needed if that nearest hit is ignored.
	var nearest: Dictionary = native_world.call(&"raycast", query.from * SCALE, query.to * SCALE, mask, QUERY_LAYER)
	if not bool(nearest.get("hit", false)):
		return {}
	var first := nearest.get("collider") as Node3D
	if is_instance_valid(first) and not _excluded(first, query.exclude) and not containing.has(first.get_instance_id()):
		var mapped := _mapped(nearest)
		if not mapped.is_empty():
			return mapped
	var hits: Array = native_world.call(&"raycast_all", query.from * SCALE, query.to * SCALE, mask, QUERY_LAYER)
	for hit: Dictionary in hits:
		var native := hit.get("collider") as Node3D
		if not is_instance_valid(native) or _excluded(native, query.exclude) or containing.has(native.get_instance_id()):
			continue
		var mapped := _mapped(hit)
		if not mapped.is_empty():
			return mapped
	return {}


static func _mask(mask: int, bodies: bool, areas: bool) -> int:
	if not areas:
		mask &= ~Hitbox.LAYER
	if not bodies:
		mask &= Hitbox.LAYER
	return mask


static func _excluded(native: Node3D, exclude: Array[RID]) -> bool:
	return exclude.has(native.get_meta(&"source_rid", RID()))


func _disable_excluded(exclude: Array[RID]) -> Array:
	var disabled: Array = []
	if exclude.is_empty():
		return disabled
	for rid: RID in exclude:
		var record: Dictionary = _objects.get(int(_by_rid.get(rid, 0)), {})
		if record.is_empty():
			continue
		for native: Node3D in record["proxies"]:
			if is_instance_valid(native):
				disabled.append([native, int(native.get(&"collision_layer"))])
				native.set(&"collision_layer", 0)
	return disabled


static func _restore_excluded(disabled: Array) -> void:
	for pair: Array in disabled:
		(pair[0] as Node3D).set(&"collision_layer", pair[1])


func shape_cast(query: PhysicsShapeQueryParameters3D) -> Dictionary:
	sync_dynamic(query.collision_mask)
	var disabled := _disable_excluded(query.exclude)
	var hit := _native_cast(query, query.motion)
	_restore_excluded(disabled)
	if not bool(hit.get("hit", false)):
		return {}
	var result := _mapped(hit)
	if result.is_empty():
		return {}
	var unsafe := float(hit["fraction"])
	result["unsafe_fraction"] = unsafe
	var normal: Vector3 = result.get("normal", Vector3.ZERO)
	var approach := absf(query.motion.dot(normal)) if normal.length_squared() > 0.5 else query.motion.length()
	result["fraction"] = maxf(0.0, unsafe - maxf(query.margin, CAST_CLEARANCE) / maxf(approach, 0.000001))
	_cast_cache = {query.get_instance_id(): {"result": result, "at": query.transform.origin + query.motion * unsafe}}
	return result


func _native_cast(query: PhysicsShapeQueryParameters3D, motion: Vector3) -> Dictionary:
	var mask := _mask(query.collision_mask, query.collide_with_bodies, query.collide_with_areas)
	var at := query.transform
	var from := at.origin * SCALE
	var to := (at.origin + motion) * SCALE
	var scale := at.basis.get_scale().abs()
	if query.shape is SphereShape3D:
		return native_world.call(&"shape_cast_sphere", from, to, (query.shape as SphereShape3D).radius * scale.x * SCALE, mask, QUERY_LAYER)
	if query.shape is CapsuleShape3D:
		var capsule := query.shape as CapsuleShape3D
		var half_axis := maxf(0.0, capsule.height * 0.5 - capsule.radius)
		return native_world.call(&"shape_cast_capsule", (at * (Vector3.UP * half_axis)) * SCALE, (at * (Vector3.DOWN * half_axis)) * SCALE, capsule.radius * scale.x * SCALE, motion * SCALE, mask, QUERY_LAYER)
	if query.shape is BoxShape3D and at.basis.orthonormalized().is_equal_approx(Basis.IDENTITY):
		return native_world.call(&"shape_cast_box", from, to, (query.shape as BoxShape3D).size * scale * SCALE, mask, QUERY_LAYER)
	return native_world.call(&"shape_cast_convex", _points(query), motion * SCALE, mask, QUERY_LAYER)


static func _points(query: PhysicsShapeQueryParameters3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	if query.shape is ConvexPolygonShape3D:
		points = (query.shape as ConvexPolygonShape3D).points
	elif query.shape is BoxShape3D:
		var half := (query.shape as BoxShape3D).size * 0.5
		for corner in 8:
			points.append(Vector3(half.x if corner & 1 else -half.x, half.y if corner & 2 else -half.y, half.z if corner & 4 else -half.z))
	for index in points.size():
		points[index] = (query.transform * points[index]) * SCALE
	return points


func intersect_shape(query: PhysicsShapeQueryParameters3D, max_results: int = 32) -> Array[Dictionary]:
	sync_dynamic(query.collision_mask)
	var mask := _mask(query.collision_mask, query.collide_with_bodies, query.collide_with_areas)
	var hits: Array
	var at := query.transform
	if query.shape is SphereShape3D:
		hits = native_world.call(&"overlap_sphere", at.origin * SCALE, ((query.shape as SphereShape3D).radius + query.margin) * SCALE, mask, QUERY_LAYER)
	elif query.shape is CapsuleShape3D:
		var shape := query.shape as CapsuleShape3D
		var half := maxf(0.0, shape.height * 0.5 - shape.radius)
		hits = native_world.call(&"overlap_capsule", (at * (Vector3.UP * half)) * SCALE, (at * (Vector3.DOWN * half)) * SCALE, (shape.radius + query.margin) * SCALE, mask, QUERY_LAYER)
	else:
		hits = native_world.call(&"overlap_convex", _points(query), mask, QUERY_LAYER)
	var results: Array[Dictionary] = []
	for native: Node3D in hits:
		if not _excluded(native, query.exclude):
			var mapped := _mapped({"collider": native})
			if not mapped.is_empty():
				results.append(mapped)
		if results.size() >= max_results:
			break
	return results


func get_rest_info(query: PhysicsShapeQueryParameters3D) -> Dictionary:
	sync_dynamic(query.collision_mask)
	var cached: Dictionary = _cast_cache.get(query.get_instance_id(), {})
	if not cached.is_empty() and query.transform.origin.distance_to(cached["at"]) < 0.5:
		return (cached["result"] as Dictionary).duplicate()
	var disabled := _disable_excluded(query.exclude)
	var old := query.transform
	var found := {}
	# Rest lookups without a preceding sweep probe the immediate surface.
	for axis in [Vector3.DOWN, Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		query.transform.origin = old.origin - axis * (query.margin + 0.5)
		var hit := _native_cast(query, axis * (query.margin + 0.5) * 2.0)
		if bool(hit.get("hit", false)) and (hit.get("normal", Vector3.ZERO) as Vector3).length_squared() > 0.5:
			found = _mapped(hit)
			break
	query.transform = old
	_restore_excluded(disabled)
	return found
