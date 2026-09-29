class_name PhysicsQueries
extends RefCounted

## The game's physics boundary. Source-unit query parameters and original
## collider identities stay the same; an initialized match uses Box3D.
## Bare test spaces and the explicit legacy comparison use Godot's server.
static var _spaces: Dictionary = {}
static var native_queries: int = 0
static var legacy_queries: int = 0


static func register(space: PhysicsDirectSpaceState3D, queries: Box3DQueries) -> void:
	_spaces[space.get_instance_id()] = weakref(queries)


static func unregister(space_id: int, queries: Box3DQueries) -> void:
	var stored: WeakRef = _spaces.get(space_id)
	if stored != null and stored.get_ref() == queries:
		_spaces.erase(space_id)


static func for_space(space: PhysicsDirectSpaceState3D) -> Box3DQueries:
	if space == null:
		return null
	var stored: WeakRef = _spaces.get(space.get_instance_id())
	return stored.get_ref() as Box3DQueries if stored != null else null


static func adapter_for_node(node: Node) -> Box3DDrops:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return null
	var queries := for_space(node.get_viewport().find_world_3d().direct_space_state)
	return queries.adapter as Box3DDrops if queries != null else null


## Pose-only callers may reuse shape geometry. Shape-owner transforms,
## disabling or replacing owners require the default full refresh.
static func sync_object(node: CollisionObject3D, refresh_shapes: bool = true) -> void:
	var adapter := adapter_for_node(node)
	if adapter != null:
		adapter.queries.sync_object(node, refresh_shapes)


static func intersect_ray(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D) -> Dictionary:
	var native := for_space(space)
	if native != null:
		# Several threads asking at once count their own (Bot.thought).
		if not native.reading:
			native_queries += 1
		return native.intersect_ray(query)
	legacy_queries += 1
	return space.intersect_ray(query) if space != null else {}


static func shape_cast(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D) -> Dictionary:
	var native := for_space(space)
	if native != null:
		native_queries += 1
		return native.shape_cast(query)
	legacy_queries += 1
	if space == null:
		return {}
	var fractions := space.cast_motion(query)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return {}
	var at := query.transform
	query.transform.origin += query.motion * fractions[1]
	var hit := space.get_rest_info(query)
	query.transform = at
	hit["hit"] = true
	hit["fraction"] = fractions[0]
	hit["unsafe_fraction"] = fractions[1]
	return hit


static func cast_motion(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D) -> PackedFloat32Array:
	var native := for_space(space)
	if native == null:
		legacy_queries += 1
		return space.cast_motion(query) if space != null else PackedFloat32Array([1.0, 1.0])
	native_queries += 1
	var hit := native.shape_cast(query)
	return PackedFloat32Array([1.0, 1.0]) if hit.is_empty() else PackedFloat32Array([hit["fraction"], hit["unsafe_fraction"]])


static func get_rest_info(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D) -> Dictionary:
	var native := for_space(space)
	if native != null:
		native_queries += 1
		return native.get_rest_info(query)
	legacy_queries += 1
	return space.get_rest_info(query) if space != null else {}


static func collide_shape(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, max_results: int = 32) -> Array[Vector3]:
	var native := for_space(space)
	if native != null:
		# Only the legacy dropped-item solver asks for raw contact pairs.
		# In a native world its bodies are solved by Box3D itself. The binding
		# has overlap queries, but no equivalent contact-pair query to fake.
		push_error("Raw contact-pair queries are legacy-only; use native bodies or intersect_shape for overlap.")
		return []
	legacy_queries += 1
	return space.collide_shape(query, max_results) if space != null else []


static func intersect_shape(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, max_results: int = 32) -> Array[Dictionary]:
	var native := for_space(space)
	if native != null:
		native_queries += 1
		return native.intersect_shape(query, max_results)
	legacy_queries += 1
	return space.intersect_shape(query, max_results) if space != null else []
