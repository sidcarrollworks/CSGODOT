class_name Box3DDrops
extends Node3D

## Experimental dropped-item rigid bodies. GameSystems advances this world
## after entity ticks and before pickups. Jolt still owns players,
## hits and live grenades. Native bodies use metres; entities keep inches.
const METRES_PER_UNIT := 0.0254
const ITEM_LAYER := 2
const COLLISION_STEPS := 4
## Experimental bullet response requested during the Box3D playtest.
## kg*inches/second per point of remaining base damage, before armour or
## hitbox multipliers. This is tuning, not an extracted CS2 force value.
const BULLET_IMPULSE_PER_DAMAGE := 6.0

var game: GameSystems
var native_world: Node3D
var steps: int = 0
var native_steps: int = 0
var bullet_queries: int = 0
var captured_shapes: int = 0
var captured_triangles: int = 0
var initialized: bool = false

var _bodies: Dictionary = {}
var _items: Dictionary = {}
var _revisions: Dictionary = {}
var _hull_meshes: Dictionary = {}
var _statics: Array[Node3D] = []
var _materials: Dictionary = {}
var _contact_rules: RefCounted
var _last_tick: int = -1


static func available() -> bool:
	return ClassDB.class_exists(&"Box3DWorld") and ClassDB.class_exists(&"Box3DBody") \
		and ClassDB.class_exists(&"Box3DContactRules")


## Explicit setup for scenes and headless checks, after static collision
## has been built. All meshes and material rules are prepared before play.
func initialize(p_game: GameSystems, geometry_root: Node) -> bool:
	if initialized:
		return game == p_game
	if not is_inside_tree() or geometry_root == null or not available():
		push_error("Box3D drops require the installed v0.4.3 addon and an initialized scene. Use --drop-physics legacy to compare.")
		return false
	if not is_equal_approx(float(ProjectSettings.get_setting("physics/box3d/length_units_per_meter", 1.0)), 1.0):
		push_error("Box3D drops use a metre bridge; physics/box3d/length_units_per_meter must be 1.")
		return false
	game = p_game
	# A failed capture can be retried on this adapter with a fresh world.
	# Its new contact-rule object needs the material pairs populated again.
	_materials.clear()
	_hull_meshes.clear()
	_contact_rules = ClassDB.instantiate(&"Box3DContactRules") as RefCounted
	native_world = ClassDB.instantiate(&"Box3DWorld") as Node3D
	native_world.name = "NativeWorld"
	native_world.set(&"auto_step", false)
	native_world.set(&"async_step", false)
	native_world.set(&"gravity", Vector3.DOWN * DroppedItem.GRAVITY * METRES_PER_UNIT)
	native_world.set(&"substep_count", 4)
	native_world.set(&"contact_recycle_distance", 0.005)
	native_world.set(&"enable_sleep", true)
	native_world.set(&"enable_warm_starting", true)
	native_world.set(&"continuous_collision", true)
	native_world.set(&"contact_rules", _contact_rules)
	native_world.set(&"restitution_threshold", DroppedItem.BOUNCE_SPEED * METRES_PER_UNIT)
	native_world.top_level = true
	native_world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(native_world)
	native_world.global_transform = Transform3D.IDENTITY
	# ENTER_TREE enables callbacks; turn them off after adding it. Only our
	# tick may solve it, and views interpolate the entity snapshots.
	native_world.set_process(false)
	native_world.set_physics_process(false)
	SurfaceProperties.rows()
	for item_class in ItemPhysics.classes():
		_cache_hull(item_class)
	for definition in ItemRegistry.all():
		_cache_hull(definition.item_class)
	if not capture_world(geometry_root):
		native_world.free()
		native_world = null
		_statics.clear()
		return false
	initialized = true
	game.drop_physics = self
	game.entities.spawned.connect(_on_spawned)
	game.entities.removed.connect(_on_removed)
	for entity in game.entities.all():
		_on_spawned(entity)
	return true


## Snapshot the world's static shapes. Explicitly repeat after changing a
## test fixture; normal maps capture once. No physics-space query is used.
func capture_world(geometry_root: Node) -> bool:
	if not is_instance_valid(native_world) or geometry_root == null:
		return false
	for body in _statics:
		body.free()
	_statics.clear()
	captured_shapes = 0
	captured_triangles = 0
	return _capture_node(geometry_root)


func _capture_node(node: Node) -> bool:
	if node == self:
		return true
	if node is StaticBody3D:
		var body := node as StaticBody3D
		if body.collision_layer & Hitscan.WORLD_LAYER != 0:
			for owner_id: int in body.get_shape_owners():
				if body.is_shape_owner_disabled(owner_id):
					continue
				var owner_node := body.shape_owner_get_owner(owner_id)
				var surface := Penetration.surface_for(owner_node.name if owner_node is Node else "")
				var at := body.global_transform * body.shape_owner_get_transform(owner_id)
				for index in body.shape_owner_get_shape_count(owner_id):
					if not _capture_shape(body.shape_owner_get_shape(owner_id, index), at, surface):
						return false
	for child in node.get_children():
		if not _capture_node(child):
			return false
	return true


func _capture_shape(shape: Shape3D, at: Transform3D, surface: String) -> bool:
	var faces := PackedVector3Array()
	var convex := false
	if shape is ConcavePolygonShape3D:
		faces = (shape as ConcavePolygonShape3D).get_faces()
	elif shape is ConvexPolygonShape3D:
		faces = _hull_faces((shape as ConvexPolygonShape3D).points)
		convex = true
	elif shape is BoxShape3D:
		var mesh := BoxMesh.new()
		mesh.size = (shape as BoxShape3D).size
		faces = mesh.get_faces()
		convex = true
	elif shape is SphereShape3D:
		var mesh := SphereMesh.new()
		mesh.radius = (shape as SphereShape3D).radius
		mesh.height = mesh.radius * 2.0
		faces = mesh.get_faces()
	elif shape is CapsuleShape3D:
		var mesh := CapsuleMesh.new()
		mesh.radius = (shape as CapsuleShape3D).radius
		mesh.height = (shape as CapsuleShape3D).height
		faces = mesh.get_faces()
	elif shape is CylinderShape3D:
		var mesh := CylinderMesh.new()
		mesh.top_radius = (shape as CylinderShape3D).radius
		mesh.bottom_radius = mesh.top_radius
		mesh.height = (shape as CylinderShape3D).height
		faces = mesh.get_faces()
	else:
		push_error("Box3D cannot copy this static shape yet: %s" % shape.get_class())
		return false
	if faces.is_empty():
		return true
	for i in faces.size():
		faces[i] = (at * faces[i]) * METRES_PER_UNIT
	var body := ClassDB.instantiate(&"Box3DBody") as Node3D
	body.set(&"body_type", ClassDB.class_get_integer_constant(&"Box3DBody", &"STATIC"))
	body.set(&"shape_type", ClassDB.class_get_integer_constant(&"Box3DBody", &"HULL" if convex else &"MESH"))
	# collision_mesh handles Godot's triangle winding in the binding.
	body.set(&"collision_mesh", _mesh_from_faces(faces))
	body.set(&"collision_layer", Hitscan.WORLD_LAYER)
	body.set(&"collision_mask", ITEM_LAYER)
	_material(body, surface)
	native_world.add_child(body)
	_statics.append(body)
	captured_shapes += 1
	@warning_ignore("integer_division")
	captured_triangles += faces.size() / 3
	return true


func _cache_hull(item_class: String) -> void:
	if _hull_meshes.has(item_class):
		return
	var hull := ItemPhysics.of(item_class)
	var points := PackedVector3Array()
	for point in hull.points:
		points.append((point - hull.centre_of_mass) * METRES_PER_UNIT)
	_hull_meshes[item_class] = _mesh_from_faces(_hull_faces(points))
	_material_id(hull.surface)


## HULL reads the mesh vertices, not its topology. A fan presents all the
## actual convex points through get_faces(), without a substitute box.
static func _hull_faces(points: PackedVector3Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for i in range(1, points.size() - 1):
		faces.append_array(PackedVector3Array([points[0], points[i], points[i + 1]]))
	return faces


static func _mesh_from_faces(faces: PackedVector3Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _material(body: Node3D, surface: String) -> void:
	body.set(&"friction", _surface_value(surface, "friction", 0.8))
	body.set(&"restitution", _surface_value(surface, "elasticity", 0.2))
	body.set(&"user_material_id", _material_id(surface))


func _material_id(surface: String) -> int:
	if _materials.has(surface):
		return int(_materials[surface])
	var id := _materials.size() + 1
	_materials[surface] = id
	for other: String in _materials:
		var other_id := int(_materials[other])
		_contact_rules.call(&"set_friction_rule", id, other_id, DroppedItem.combined_friction(surface, other))
		_contact_rules.call(&"set_restitution_rule", id, other_id, DroppedItem.combined_restitution(surface, other))
	return id


static func _surface_value(surface: String, column: String, fallback: float) -> float:
	var value := SurfaceProperties.value(surface, column)
	return fallback if is_nan(value) else value


func _on_spawned(entity: SimEntity) -> void:
	var item := entity as DroppedItem
	if item == null or item.removed or _bodies.has(item.id):
		return
	if not _hull_meshes.has(item.entity_class):
		push_error("Box3D item hull was not prepared before play: %s" % item.entity_class)
		return
	var hull := item.physics()
	var body := ClassDB.instantiate(&"Box3DBody") as Node3D
	body.name = "Drop%d" % item.id
	body.set_meta(&"dropped_entity", item.id)
	body.set(&"body_type", ClassDB.class_get_integer_constant(&"Box3DBody", &"DYNAMIC"))
	body.set(&"shape_type", ClassDB.class_get_integer_constant(&"Box3DBody", &"HULL"))
	body.set(&"collision_mesh", _hull_meshes[item.entity_class])
	body.set(&"collision_layer", ITEM_LAYER)
	# Match the existing drops: guns pass through players and other guns.
	body.set(&"collision_mask", Hitscan.WORLD_LAYER)
	body.set(&"linear_damping", hull.linear_damping)
	body.set(&"angular_damping", hull.angular_damping)
	body.set(&"continuous", true)
	body.set(&"sync_node_transform", true)
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	body.transform = Transform3D(item.basis, item.position * METRES_PER_UNIT)
	_material(body, hull.surface)
	native_world.add_child(body)
	# Table inertia is per unit mass in inches squared, about the COM.
	body.call(&"set_mass_data", hull.mass, Vector3.ZERO, hull.inertia * (hull.mass * METRES_PER_UNIT * METRES_PER_UNIT))
	_bodies[item.id] = body
	_items[item.id] = item
	_write_state(item, body)


func _write_state(item: DroppedItem, body: Node3D) -> void:
	body.call(&"teleport", Transform3D(item.basis, item.position * METRES_PER_UNIT))
	body.call(&"set_linear_velocity", item.velocity * METRES_PER_UNIT)
	body.call(&"set_angular_velocity", item.angular_velocity)
	body.call(&"set_awake", not item.resting)
	_revisions[item.id] = item.physics_revision


func _on_removed(entity: SimEntity) -> void:
	if _bodies.has(entity.id):
		(_bodies[entity.id] as Node3D).free()
	_bodies.erase(entity.id)
	_items.erase(entity.id)
	_revisions.erase(entity.id)


## React to an unobstructed part of a bullet's path. Hitscan supplies only
## the space before the next wall/person, and the surviving damage share
## after a penetrated wall. Bullets retain their existing pass-through
## behavior on drops; only guns receive impulses, once per hull per segment.
func push_bullet_segment(from: Vector3, to: Vector3, kept: float, data: WeaponData, shot_origin: Vector3) -> void:
	if not initialized or _bodies.is_empty() or kept <= 0.0 or from.is_equal_approx(to):
		return
	bullet_queries += 1
	# Box3D filters both directions. Drops are on ITEM_LAYER and accept the
	# world layer, so the query must carry WORLD_LAYER as its own category.
	var hits: Array = native_world.call(&"raycast_all", from * METRES_PER_UNIT, to * METRES_PER_UNIT, ITEM_LAYER, Hitscan.WORLD_LAYER)
	var touched := {}
	var direction := (to - from).normalized()
	for hit: Dictionary in hits:
		var body := hit.get("collider") as Node3D
		if not is_instance_valid(body):
			continue
		var id := int(body.get_meta(&"dropped_entity", 0))
		var item := _items.get(id) as DroppedItem
		if item == null or item.removed or touched.has(id) or _bodies.get(id) != body:
			continue
		if item.entry == null or not item.entry.item.is_gun:
			continue
		touched[id] = true
		var at: Vector3 = hit["position"]
		var distance := shot_origin.distance_to(at / METRES_PER_UNIT)
		var damage := data.damage_at(distance) * kept
		if damage <= 0.0:
			continue
		# Impulse (not force) is independent of tick duration. The native API
		# takes kg*m/s and an absolute world-space point in metres; applying it
		# off-centre adds torque and wakes the body. Each pellet adds to the
		# body's current velocity, never overwriting an earlier pellet's kick.
		body.call(&"apply_impulse_at_point", direction * (damage * BULLET_IMPULSE_PER_DAMAGE * METRES_PER_UNIT), at)
		item.velocity = (body.call(&"get_linear_velocity") as Vector3) / METRES_PER_UNIT
		item.angular_velocity = body.call(&"get_angular_velocity") as Vector3
		if item.resting:
			item.resting = false
			item.rested_usec = -1
			item.motion_started.emit()


## Advance one simulation interval, even without a view. Refresh contacts
## four times within it: long, thin weapon hulls otherwise penetrate deeply
## with v0.4.3's recycled contacts. Each call also uses four solver substeps.
func tick(t: SimTick) -> void:
	if not initialized or t.tick == _last_tick:
		return
	_last_tick = t.tick
	for id: int in _bodies.keys():
		var item: DroppedItem = _items[id]
		if item.removed:
			_on_removed(item)
		elif item.physics_revision != int(_revisions[id]):
			_write_state(item, _bodies[id])
	for collision_step in COLLISION_STEPS:
		native_world.call(&"step", t.dt / COLLISION_STEPS)
		native_steps += 1
	steps += 1
	for id: int in _bodies:
		var body: Node3D = _bodies[id]
		var item: DroppedItem = _items[id]
		var solved := body.global_transform
		item.position = solved.origin / METRES_PER_UNIT
		item.basis = solved.basis.orthonormalized()
		item.velocity = (body.call(&"get_linear_velocity") as Vector3) / METRES_PER_UNIT
		item.angular_velocity = body.call(&"get_angular_velocity") as Vector3
		var was_resting := item.resting
		item.resting = not bool(body.call(&"is_awake"))
		if item.resting and not was_resting:
			item.rested_usec = t.now_usec
		elif was_resting and not item.resting:
			item.rested_usec = -1
			item.motion_started.emit()


func body_count() -> int:
	return _bodies.size()


func body_for(entity_id: int) -> Node3D:
	return _bodies.get(entity_id) as Node3D


func _exit_tree() -> void:
	if game != null:
		if game.entities.spawned.is_connected(_on_spawned):
			game.entities.spawned.disconnect(_on_spawned)
		if game.entities.removed.is_connected(_on_removed):
			game.entities.removed.disconnect(_on_removed)
		if game.drop_physics == self:
			game.drop_physics = null
	initialized = false
