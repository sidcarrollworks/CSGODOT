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
## How far past its motion a sweep looks, so a motion ending inside the
## contact band short of touching is reported (shape_cast_prepared).
const CAST_REACH := 0.75
## The most a hit backs off along its motion for its clearance; the rest
## of the clearance is a push along the plane (shape_cast_prepared).
const CAST_BACK_OFF := 0.5
## A sweep is made with a shape this much smaller all round than the one
## asked about, and kept as much further from what it meets, so it stops
## where it did. Box3D counts a start within 0.246 of anything as an
## overlap: a hull at rest 0.257 over a floor had a hundredth of a unit to
## spare, a floor a fiftieth higher than the last put it in overlap, and a
## hull with someone standing on its head, 0.257 over it, was held between
## the two and went nowhere (tests/run_box3d_movement_checks.gd). With it a
## hull is in overlap within 0.12 of what it is near, not 0.246.
const CAST_INSET := 0.125

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
## A body's hitboxes are a set (the SkinnedHitboxes they hang under), which
## counts its changes. By the set's id: the set, its hitboxes' ids, and
## what was last put of it into the native world (_put).
var _sets: Dictionary = {}
## The set a hitbox is of, by the hitbox's id.
var _set_of: Dictionary = {}
## The hitboxes of no set (a target's own boxes), looked over by every ray
## that can meet one, as all were.
var _loose: Dictionary = {}
var _putting := false
## Whether what a ray in a tick meets is held to the hitboxes themselves
## (_hold_to_capsules). Off in the game; every check has it on
## (tests/check_suite.gd), and a check file with a fault has failed.
static var check_sets := false
static var set_rays_held: int = 0
static var set_faults: PackedStringArray = PackedStringArray()
var _hull_layers: int = 2
var _hitbox_layers: int = Hitbox.LAYER
var _dynamic_layers: int = 2 | Hitbox.LAYER
var _pending: Array[WeakRef] = []
var _cast_cache: Dictionary = {}
var _shape_watchers: Dictionary = {}
var _scope_owner := RID()
var _scope_synced: int = 0
var _scope_left_out: Array = []
var _tick_open := false
var _tick_synced: int = 0
## Whether several threads are asking at once (begin_reading).
var reading := false
## How much smaller all round the last native cast's shape was (CAST_INSET,
## less for a shape too small for it, none for a convex one).
var _inset := 0.0


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
		_unwatch_shapes(record)
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
	_sets.clear()
	_set_of.clear()
	_loose.clear()
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
	if _pending.is_empty():
		return
	var pending := _pending
	_pending = []
	for ref: WeakRef in pending:
		var node := ref.get_ref() as CollisionObject3D
		if is_instance_valid(node) and node.is_inside_tree() and (_root == node or _root.is_ancestor_of(node)):
			sync_object(node)


## A scope in which one body moves and nothing else does, and every query
## made excludes that body: a player's tick. The other hulls and hitboxes
## are then synchronized once for the scope rather than for every cast (a
## moving player's tick is five to ten casts, and each compared every
## hull's transform), and the body's own proxies are left out of the native
## world once, rather than by each cast, so its own rays do not start in
## it either. Its own proxy is published when the scope is over.
func begin_scope(owner: RID) -> void:
	if _scope_owner.is_valid():
		end_scope()
	_scope_owner = owner
	_scope_synced = 0
	_leave_out_scope_owner()


func end_scope() -> void:
	for pair: Array in _scope_left_out:
		if is_instance_valid(pair[0]):
			(pair[0] as Node3D).set(&"collision_layer", pair[1])
	_scope_left_out = []
	_scope_owner = RID()
	_scope_synced = 0


## Takes the scope's owner out of the native world, keeping the layer each
## of its proxies is to have back: the one its record says, since a proxy
## already out would otherwise be given nothing back.
func _leave_out_scope_owner() -> void:
	_scope_left_out = []
	var record: Dictionary = _objects.get(int(_by_rid.get(_scope_owner, 0)), {})
	if record.is_empty():
		return
	var disabled: Array = record.get("disabled", [])
	var proxies: Array = record["proxies"]
	for slot in proxies.size():
		var native := proxies[slot] as Node3D
		if not is_instance_valid(native):
			continue
		var layer := 0 if slot < disabled.size() and disabled[slot] else int(record["layer"])
		_scope_left_out.append([native, layer])
		native.set(&"collision_layer", 0)


## A tick begins (GameWorld.begin_tick). Until it ends the hulls are looked
## over once, by the first query that could meet one, rather than by every
## query or every player's scope: in a tick a hull moves by its player's
## own tick, a spawn or a death, each of which publishes it
## (PhysicsQueries.sync_object), and whatever else moves one in a tick has
## to. Outside a tick nothing is taken on trust: a hull moved by hand is
## found by the next query, as the checks move them.
func begin_tick() -> void:
	_tick_open = true
	_tick_synced = 0


func end_tick() -> void:
	_tick_open = false
	_tick_synced = 0


## Several threads ask at once from here on (the bots thinking together),
## until end_reading: what is new is taken in and the hulls looked over
## first, and nothing is synchronized or written while they ask. Box3D's
## queries read the world and write their own locals, so they may run
## beside each other while nothing moves; the bridge's sweeps keep their
## last hit and are not for then. Hitboxes are as the last query that
## asked for them left them.
func begin_reading() -> void:
	sync_dynamic(_hull_layers)
	reading = true


func end_reading() -> void:
	reading = false


func sync_dynamic(mask: int = ALL_LAYERS, exclude: Array[RID] = []) -> void:
	if reading:
		return
	flush_pending()
	if mask & _dynamic_layers == 0:
		return
	if _tick_open:
		mask &= ~_tick_synced
		if mask & _dynamic_layers == 0:
			return
	if _scope_owner.is_valid():
		# Only the owner moves in the scope: a layer synchronized once in it
		# stays synchronized.
		mask &= ~_scope_synced
		if mask & _dynamic_layers == 0:
			return
		_scope_synced |= mask
	# Movement never needs to revisit every bone capsule. Keep separate
	# registries so a hull sweep only synchronizes the character hulls.
	if mask & _hull_layers != 0:
		if _tick_open:
			# Every hull, whatever this query leaves out: nobody looks again
			# this tick. A layer hitboxes share is looked over as before.
			_sync_group(_hulls, mask, [])
			_tick_synced |= mask & _hull_layers & ~_hitbox_layers
		else:
			_sync_group(_hulls, mask, exclude)
	if mask & _hitbox_layers != 0:
		if _tick_open:
			# No line to go by (a ray has one, intersect_ray): every set that
			# has changed.
			_sync_group(_loose, mask, exclude)
			_sync_sets(false, Vector3.ZERO, Vector3.ZERO)
		else:
			# Outside a tick nothing is taken on trust, a set's count of its
			# changes neither: every hitbox is looked over, as the checks
			# move them by hand, and what was put of the sets is not known.
			_putting = true
			_sync_group(_hitboxes, mask, exclude)
			_putting = false
			for of_set: Dictionary in _sets.values():
				of_set["known"] = false


## How far round a set's capsules its box is drawn: a proxy stands within
## the comparison's tolerance of its hitbox (a twentieth of a unit a
## hundred metres from the map's middle), and the native ray is single
## precision.
const SET_MARGIN := 0.5


## Brings the sets of hitboxes up to date, in an open tick: by_line, those
## the line from one point to the other could meet, and no others.
##
## A set is as it was put if its count of changes and its node's place are
## what they were then. One that is not is wanted by a ray if the line
## passes the box its capsules are in now, or the box its proxies were put
## in: nothing else of it could be on the line. A set put off its layer,
## and off it still, has nothing to meet. (The research is
## reference/research/hitboxes-for-shots-2026-09-28.md.)
func _sync_sets(by_line: bool, from: Vector3, to: Vector3) -> void:
	for of_set: Dictionary in _sets.values():
		var hung := (of_set["set"] as WeakRef).get_ref() as SkinnedHitboxes
		if not is_instance_valid(hung) or not hung.is_inside_tree():
			continue
		var at := hung.global_transform
		var live := hung.on_layer > 0
		if of_set["known"]:
			if of_set["changes"] == hung.changes and of_set["at"] == at:
				continue
			if not live and not of_set["put_on"]:
				continue
			if by_line:
				var passed := bool(of_set["put_on"]) and _line_passes(of_set["put"], from, to)
				if not passed and live:
					_measure(of_set, hung, at)
					passed = _line_passes(_held_at(of_set, at), from, to)
				if not passed:
					continue
		_put(of_set, hung, at, live)


## Every hitbox of a set brought up to date, as each was by being looked
## over, and what was put kept.
func _put(of_set: Dictionary, hung: SkinnedHitboxes, at: Transform3D, live: bool) -> void:
	_putting = true
	for id: int in of_set["members"]:
		var node := (_dynamic[id] as WeakRef).get_ref() as CollisionObject3D
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var record: Dictionary = _objects[id]
		if record.get("at") != node.global_transform or int(record["layer"]) != node.collision_layer or record.get("geometry_dirty", false):
			sync_object(node, false)
	_putting = false
	if live:
		_measure(of_set, hung, at)
		of_set["put"] = _held_at(of_set, at)
	of_set["put_on"] = live
	of_set["changes"] = hung.changes
	of_set["at"] = at
	of_set["known"] = true


## The box a set's capsules are in, kept from its node's place: measured
## once for a count of the set's changes, from each hitbox's place and how
## far its shapes reach from it, and carried with the node after that,
## which only moves.
func _measure(of_set: Dictionary, hung: SkinnedHitboxes, at: Transform3D) -> void:
	if of_set["measured"] == hung.changes and of_set["held_basis"] == at.basis:
		return
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for id: int in of_set["members"]:
		var node := (_dynamic[id] as WeakRef).get_ref() as CollisionObject3D
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var record: Dictionary = _objects[id]
		if not record.has("reach") or record.get("geometry_dirty", false):
			record["reach"] = _reach(node)
		var round_it := Vector3.ONE * (float(record["reach"]) + SET_MARGIN)
		var middle := node.global_position
		low = low.min(middle - round_it)
		high = high.max(middle + round_it)
	of_set["held"] = AABB(low - at.origin, high - low) if low.x <= high.x else AABB()
	of_set["held_basis"] = at.basis
	of_set["measured"] = hung.changes


static func _held_at(of_set: Dictionary, at: Transform3D) -> AABB:
	var held: AABB = of_set["held"]
	return AABB(held.position + at.origin, held.size)


## How far from a hitbox's own place any of its shapes reaches.
static func _reach(node: CollisionObject3D) -> float:
	var reach := 0.0
	var scale := node.global_transform.basis.get_scale().abs()
	var largest := maxf(scale.x, maxf(scale.y, scale.z))
	for owner_id: int in node.get_shape_owners():
		var local := node.shape_owner_get_transform(owner_id)
		var local_scale := local.basis.get_scale().abs()
		var by := largest * maxf(local_scale.x, maxf(local_scale.y, local_scale.z))
		for index in node.shape_owner_get_shape_count(owner_id):
			var shape := node.shape_owner_get_shape(owner_id, index)
			var round_shape := 0.0
			if shape is CapsuleShape3D:
				round_shape = maxf((shape as CapsuleShape3D).height * 0.5, (shape as CapsuleShape3D).radius)
			elif shape is SphereShape3D:
				round_shape = (shape as SphereShape3D).radius
			elif shape is BoxShape3D:
				round_shape = (shape as BoxShape3D).size.length() * 0.5
			elif shape is ConvexPolygonShape3D:
				for point in (shape as ConvexPolygonShape3D).points:
					round_shape = maxf(round_shape, point.length())
			else:
				# A shape whose size is not read: the set is always wanted.
				return INF
			reach = maxf(reach, local.origin.length() * largest + round_shape * by)
	return reach


## Whether a line, from one point to the other, passes a box: its ends in
## it count.
static func _line_passes(box: AABB, from: Vector3, to: Vector3) -> bool:
	if not box.size.is_finite() or not box.position.is_finite():
		return true
	return box.has_point(from) or box.has_point(to) or box.intersects_segment(from, to) != null


func _join_set(hitbox: Hitbox, id: int) -> void:
	var hung := hitbox.get_parent() as SkinnedHitboxes
	if hung == null:
		_loose[id] = _dynamic[id]
		return
	var set_id := hung.get_instance_id()
	if not _sets.has(set_id):
		_sets[set_id] = {
			"set": weakref(hung), "members": {}, "known": false, "changes": -1, "at": Transform3D(),
			"put": AABB(), "put_on": true, "measured": -1, "held": AABB(), "held_basis": Basis(),
		}
	# One more to put: what was put of the set does not hold it.
	_sets[set_id]["members"][id] = true
	_sets[set_id]["known"] = false
	_sets[set_id]["measured"] = -1
	_set_of[id] = set_id


func _leave_set(id: int) -> void:
	_loose.erase(id)
	if not _set_of.has(id):
		return
	var set_id: int = _set_of[id]
	_set_of.erase(id)
	if _sets.has(set_id):
		var of_set: Dictionary = _sets[set_id]
		of_set["members"].erase(id)
		of_set["measured"] = -1
		if of_set["members"].is_empty():
			_sets.erase(set_id)


func _sync_group(group: Dictionary, mask: int, exclude: Array[RID]) -> void:
	# Node removal signals maintain the registries. Defer the rare stale-entry
	# cleanup so ordinary casts don't allocate a keys() snapshot.
	var removed: Array[int] = []
	for id: int in group:
		var node := (group[id] as WeakRef).get_ref() as CollisionObject3D
		if not is_instance_valid(node) or not node.is_inside_tree():
			removed.append(id)
			continue
		var record: Dictionary = _objects[id]
		# Its native shapes are excluded by the query below. Moving this
		# mirror now cannot affect the result; a later query that can hit it
		# will pull its current pose before casting.
		if exclude.has(record["rid"]):
			continue
		var layer := node.collision_layer
		if (layer | int(record["layer"])) & mask == 0:
			continue
		# Most hull sweeps revisit nine unmoved players. Check here, before
		# registration, geometry and native-property work in sync_object.
		if record.get("at") != node.global_transform or int(record["layer"]) != layer or record.get("geometry_dirty", false):
			sync_object(node, false)
	for id in removed:
		_remove(id)


func _remove(id: int) -> void:
	var record: Dictionary = _objects.get(id, {})
	_unwatch_shapes(record)
	for proxy: Node3D in record.get("proxies", []):
		if is_instance_valid(proxy):
			proxy.free()
	_objects.erase(id)
	_by_rid.erase(record.get("rid", RID()))
	_dynamic.erase(id)
	_hulls.erase(id)
	_hitboxes.erase(id)
	_leave_set(id)
	_cast_cache.clear()


func _invalidate_shape_resource(shape_id: int) -> void:
	for id: int in _shape_watchers[shape_id]["sources"]:
		if _objects.has(id):
			_objects[id]["geometry_dirty"] = true


func _unwatch_shapes(record: Dictionary) -> void:
	for shape: Shape3D in record.get("resources", []):
		var shape_id := shape.get_instance_id()
		var watcher: Dictionary = _shape_watchers[shape_id]
		watcher["sources"].erase(record["shape_source_id"])
		if watcher["sources"].is_empty():
			shape.changed.disconnect(watcher["changed"])
			_shape_watchers.erase(shape_id)


func _watch_shapes(record: Dictionary, resources: Array[Shape3D], id: int) -> void:
	_unwatch_shapes(record)
	for shape in resources:
		var shape_id := shape.get_instance_id()
		if not _shape_watchers.has(shape_id):
			var changed := _invalidate_shape_resource.bind(shape_id)
			_shape_watchers[shape_id] = {"sources": {}, "changed": changed}
			shape.changed.connect(changed)
		_shape_watchers[shape_id]["sources"][id] = true
	record["resources"] = resources
	record["shape_source_id"] = id


func sync_object(source: CollisionObject3D, refresh_shapes: bool = true) -> void:
	_sync_object(source, refresh_shapes)
	# A hitbox put by itself (published, found by a scan): what was put of
	# its set as a whole no longer says where its proxies are.
	if not _putting and is_instance_valid(source) and _set_of.has(source.get_instance_id()):
		var of_set: Dictionary = _sets.get(_set_of[source.get_instance_id()], {})
		if not of_set.is_empty():
			of_set["known"] = false
	# Synchronized inside its own scope (a duck resizes the hull), its
	# proxies have their layer again: out they go again.
	if _scope_owner.is_valid() and is_instance_valid(source) and source.get_rid() == _scope_owner:
		_leave_out_scope_owner()


func _sync_object(source: CollisionObject3D, refresh_shapes: bool) -> void:
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
			_join_set(source as Hitbox, id)
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
	var source_at := source.global_transform
	var source_layer := source.collision_layer
	refresh_shapes = refresh_shapes or bool(record.get("geometry_dirty", false))
	# Repeated queries see the same poses. Explicit syncs (movement/duck,
	# shape additions and tools) still refresh geometry at an unchanged pose.
	if not refresh_shapes and record.get("at") == source_at and int(record["layer"]) == source_layer:
		return
	# A motion-only update reuses authored geometry. Crouching, shape edits,
	# owner changes and explicit callers still take the full refresh path.
	# Check each combined scale: rotated owners beneath nonuniform scale can
	# change shape dimensions even when the source's own scale is unchanged.
	if not refresh_shapes and record.has("locals"):
		var scale_changed := false
		for slot: int in record["proxies"].size():
			var at: Transform3D = source_at * record["locals"][slot]
			if not at.basis.get_scale().is_equal_approx(record["scales"][slot]):
				scale_changed = true
				break
		if not scale_changed:
			for slot: int in record["proxies"].size():
				var at: Transform3D = source_at * record["locals"][slot]
				var proxy: Node3D = record["proxies"][slot]
				if int(record["layer"]) != source_layer and not record["disabled"][slot]:
					proxy.set(&"collision_layer", source_layer)
				var native_at := Transform3D(at.basis.orthonormalized(), at.origin * SCALE)
				if not proxy.transform.is_equal_approx(native_at):
					proxy.call(&"teleport", native_at)
			record["at"] = source_at
			record["layer"] = source_layer
			return
	var locals: Array[Transform3D] = []
	var disabled: Array[bool] = []
	var scales: Array[Vector3] = []
	var resources: Array[Shape3D] = []
	var slot := 0
	for owner_id: int in source.get_shape_owners():
		for index in source.shape_owner_get_shape_count(owner_id):
			var shape := source.shape_owner_get_shape(owner_id, index)
			if not resources.has(shape):
				resources.append(shape)
			var local := source.shape_owner_get_transform(owner_id)
			var at := source_at * local
			locals.append(local)
			disabled.append(source.is_shape_owner_disabled(owner_id))
			scales.append(at.basis.get_scale())
			var proxy: Node3D
			if slot >= record["proxies"].size():
				proxy = ClassDB.instantiate(&"Box3DBody") as Node3D
				# Only casts use these mirrors. Explicit teleport updates the
				# broadphase immediately; a static sensor avoids four unnecessary
				# kinematic target/velocity updates on every native world tick.
				proxy.set(&"body_type", ClassDB.class_get_integer_constant(&"Box3DBody", &"STATIC"))
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
			slot += 1
	while record["proxies"].size() > slot:
		(record["proxies"].pop_back() as Node3D).free()
		record["shapes"].pop_back()
	record["layer"] = source_layer
	record["at"] = source_at
	record["locals"] = locals
	record["disabled"] = disabled
	record["scales"] = scales
	_watch_shapes(record, resources, id)
	record["geometry_dirty"] = false


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
	# The native normal is single precision and can be a few parts in ten
	# thousand off unit length, which Vector3.slerp refuses (the foot plant's
	# ease between floor normals printed an error a frame for every foot
	# beside a wall). Godot's own queries hand out unit normals; so does this.
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if not normal.is_zero_approx():
		result["normal"] = normal.normalized()
	if hit.has("position"):
		result["position"] = (hit["position"] as Vector3) / SCALE
		result["point"] = result["position"]
	result["linear_velocity"] = source.velocity if source is CharacterBody3D else Vector3.ZERO
	return result


func intersect_ray(query: PhysicsRayQueryParameters3D) -> Dictionary:
	if not check_sets:
		return _ray(query)
	var met := _ray(query)
	if _tick_open and not reading and query.collision_mask & _hitbox_layers != 0:
		_hold_to_capsules(query, met)
	return met


func _ray(query: PhysicsRayQueryParameters3D) -> Dictionary:
	if _tick_open and not reading and not _scope_owner.is_valid() and query.collision_mask & _hitbox_layers != 0:
		# A round's ray: what else it can meet as ever, and of the bodies'
		# hitboxes those its line could meet.
		sync_dynamic(query.collision_mask & ~_hitbox_layers)
		_sync_group(_loose, query.collision_mask, [])
		_sync_sets(true, query.from, query.to)
	else:
		sync_dynamic(query.collision_mask)
	var mask := _mask(query.collision_mask, query.collide_with_bodies, query.collide_with_areas)
	var from := query.from * SCALE
	var to := query.to * SCALE
	# Unlike Godot's ray contract, Box3D convex casts can report a hit at
	# fraction zero when the start is inside. Penetration's exit search
	# depends on ignoring that solid; smoke explicitly requests the hit.
	var held: Variant = null
	if query.hit_from_inside:
		held = _holding(from, mask, query.exclude)
		for native: Node3D in held:
			return _mapped({"hit": true, "collider": native, "position": from, "normal": Vector3.ZERO, "fraction": 0.0})
	# Sight/ground rays usually accept the nearest surface. Collecting every
	# triangle hit across a map is only needed if that nearest hit is ignored.
	var nearest: Dictionary = native_world.call(&"raycast", from, to, mask, QUERY_LAYER)
	if not bool(nearest.get("hit", false)):
		return {}
	var first := nearest.get("collider") as Node3D
	var usable := is_instance_valid(first) and not _excluded(first, query.exclude)
	# A nearest hit some way along is the answer: what holds a ray's start
	# is met at its start. Only a hit at the start, or on something left
	# out, needs what holds the start asked for, a query more.
	if usable and float(nearest.get("fraction", 0.0)) > 0.000001:
		var mapped := _mapped(nearest)
		if not mapped.is_empty():
			return mapped
	if held == null:
		held = _holding(from, mask, query.exclude)
	var containing := {}
	for native: Node3D in held:
		containing[native.get_instance_id()] = true
	if usable and not containing.has(first.get_instance_id()):
		var mapped := _mapped(nearest)
		if not mapped.is_empty():
			return mapped
	var hits: Array = native_world.call(&"raycast_all", from, to, mask, QUERY_LAYER)
	for hit: Dictionary in hits:
		var native := hit.get("collider") as Node3D
		if not is_instance_valid(native) or _excluded(native, query.exclude) or containing.has(native.get_instance_id()):
			continue
		var mapped := _mapped(hit)
		if not mapped.is_empty():
			return mapped
	return {}


## How near a hitbox's skin a ray may pass, or begin, and the native ray
## and the one worked out here be allowed to differ about it.
const HELD_WITHIN := 0.05


## Holds what a ray met to the hitboxes themselves: the nearest capsule, box
## or ball on its line, worked out here from every hitbox's own node, the
## proxies not asked. A hitbox met where none is, or one passed that was
## on the line before what was met, is a fault, kept for a check to read.
## What the ray meets of the world is the native world's to say.
func _hold_to_capsules(query: PhysicsRayQueryParameters3D, met: Dictionary) -> void:
	var from := query.from
	var along := query.to - from
	var length := along.length()
	if length < 0.001 or not query.collide_with_areas:
		return
	var way := along / length
	var met_box := met.get("collider") as Hitbox
	var met_at := from.distance_to(met["position"]) if not met.is_empty() else INF
	var nearest := INF
	var nearest_box: Hitbox = null
	var there := false
	for id: int in _hitboxes:
		var node := (_hitboxes[id] as WeakRef).get_ref() as Hitbox
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		if node.collision_layer & query.collision_mask == 0 or query.exclude.has(node.get_rid()):
			continue
		for owner_id: int in node.get_shape_owners():
			if node.is_shape_owner_disabled(owner_id):
				continue
			var at := node.global_transform * node.shape_owner_get_transform(owner_id)
			for index in node.shape_owner_get_shape_count(owner_id):
				var shape := node.shape_owner_get_shape(owner_id, index)
				var holds := _holds(shape, at, from)
				if holds == 0:
					# It begins on a skin: either may say either.
					return
				if holds > 0:
					# What holds a ray's start is not met.
					continue
				var inner := _line_meets(shape, at, from, way, length, -HELD_WITHIN)
				if inner >= 0.0 and inner < nearest:
					nearest = inner
					nearest_box = node
				if node == met_box and not there:
					var outer := _line_meets(shape, at, from, way, length, HELD_WITHIN)
					there = outer >= 0.0 and outer - HELD_WITHIN <= met_at and (inner < 0.0 or met_at <= inner + HELD_WITHIN)
	set_rays_held += 1
	var fault := ""
	if met_box != null and not there:
		fault = "met %s of %s at %.3f, where it is not" % [met_box.name, _whose(met_box), met_at]
	elif nearest + HELD_WITHIN < met_at:
		fault = "passed %s of %s at %.3f, and met %s at %.3f" % [
			nearest_box.name, _whose(nearest_box), nearest,
			"nothing" if met.is_empty() else String((met["collider"] as Node).name), met_at]
	if fault != "":
		set_faults.append("a ray from %s to %s %s" % [from, query.to, fault])
		push_error("Box3DQueries: a ray from %s to %s %s" % [from, query.to, fault])


static func _whose(hitbox: Hitbox) -> String:
	var node: Node = hitbox
	while node != null and not node is CharacterBody3D:
		node = node.get_parent()
	return String(node.name) if node != null else String(hitbox.get_parent().name)


## Whether a shape holds a point: 1 inside, -1 outside, 0 within
## HELD_WITHIN of its skin.
static func _holds(shape: Shape3D, at: Transform3D, point: Vector3) -> int:
	var scale := at.basis.get_scale().abs()
	var out := INF
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var half := maxf(0.0, capsule.height * 0.5 - capsule.radius) * scale.y
		var a := at.origin + at.basis.y.normalized() * half
		var b := at.origin - at.basis.y.normalized() * half
		out = Geometry3D.get_closest_point_to_segment(point, a, b).distance_to(point) - capsule.radius * scale.x
	elif shape is SphereShape3D:
		out = at.origin.distance_to(point) - (shape as SphereShape3D).radius * scale.x
	elif shape is BoxShape3D:
		var local := Transform3D(at.basis.orthonormalized(), at.origin).affine_inverse() * point
		var half_size := (shape as BoxShape3D).size * 0.5 * scale
		var past := local.abs() - half_size
		out = maxf(past.x, maxf(past.y, past.z))
	else:
		return 0
	if out > HELD_WITHIN:
		return -1
	return 1 if out < -HELD_WITHIN else 0


## How far along a line it meets a shape grown by `grow` all round, or -1:
## a capsule, a ball or a box, as the hitboxes are.
static func _line_meets(shape: Shape3D, at: Transform3D, from: Vector3, way: Vector3, length: float, grow: float) -> float:
	var scale := at.basis.get_scale().abs()
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var radius := capsule.radius * scale.x + grow
		if radius <= 0.0:
			return -1.0
		var half := maxf(0.0, capsule.height * 0.5 - capsule.radius) * scale.y
		var axis := at.basis.y.normalized()
		return _meets_capsule(at.origin - axis * half, at.origin + axis * half, radius, from, way, length)
	if shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius * scale.x + grow
		return _meets_ball(at.origin, radius, from, way, length) if radius > 0.0 else -1.0
	if shape is BoxShape3D:
		var half_size := (shape as BoxShape3D).size * 0.5 * scale + Vector3.ONE * grow
		if half_size.x <= 0.0 or half_size.y <= 0.0 or half_size.z <= 0.0:
			return -1.0
		var to_local := Transform3D(at.basis.orthonormalized(), at.origin).affine_inverse()
		return _meets_box(half_size, to_local * from, to_local.basis * way, length)
	return -1.0


static func _meets_ball(middle: Vector3, radius: float, from: Vector3, way: Vector3, length: float) -> float:
	var to_it := from - middle
	var b := way.dot(to_it)
	var c := to_it.dot(to_it) - radius * radius
	var h := b * b - c
	if h < 0.0:
		return -1.0
	var t := -b - sqrt(h)
	return t if t >= 0.0 and t <= length else -1.0


static func _meets_capsule(a: Vector3, b: Vector3, radius: float, from: Vector3, way: Vector3, length: float) -> float:
	var ba := b - a
	var oa := from - a
	var baba := ba.dot(ba)
	if baba < 1e-9:
		return _meets_ball(a, radius, from, way, length)
	var bard := ba.dot(way)
	var baoa := ba.dot(oa)
	var rdoa := way.dot(oa)
	var oaoa := oa.dot(oa)
	var k := baba - bard * bard
	if k > 1e-9:
		var m := baba * rdoa - baoa * bard
		var c := baba * oaoa - baoa * baoa - radius * radius * baba
		var h := m * m - k * c
		if h < 0.0:
			return -1.0
		var t := (-m - sqrt(h)) / k
		var y := baoa + t * bard
		if y > 0.0 and y < baba:
			return t if t >= 0.0 and t <= length else -1.0
		return _meets_ball(a if y <= 0.0 else b, radius, from, way, length)
	# Along the capsule's own length: its ends are all it can meet.
	var first := _meets_ball(a, radius, from, way, length)
	var second := _meets_ball(b, radius, from, way, length)
	if first < 0.0:
		return second
	return first if second < 0.0 else minf(first, second)


static func _meets_box(half_size: Vector3, from: Vector3, way: Vector3, length: float) -> float:
	var enters := 0.0
	var leaves := length
	for axis in 3:
		if absf(way[axis]) < 1e-9:
			if absf(from[axis]) > half_size[axis]:
				return -1.0
			continue
		var one := (-half_size[axis] - from[axis]) / way[axis]
		var other := (half_size[axis] - from[axis]) / way[axis]
		enters = maxf(enters, minf(one, other))
		leaves = minf(leaves, maxf(one, other))
		if enters > leaves:
			return -1.0
	return enters


## The solids a point is inside, those left out aside.
func _holding(at: Vector3, mask: int, exclude: Array[RID]) -> Array[Node3D]:
	var holding: Array[Node3D] = []
	var overlaps: Array = native_world.call(&"overlap_sphere", at, 0.000001, mask, QUERY_LAYER)
	for native: Node3D in overlaps:
		if not _excluded(native, exclude) and bool(native.get_meta(&"source_solid", false)):
			holding.append(native)
	return holding


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


## A sweep for anything but a player's hull: a grenade, a dropped item, a
## weapon held out to be thrown. Fraction is how far along the motion the
## shape may go and stay its clearance from what the native cast met,
## backed off along the motion however far that takes, and there is no
## offset: those who ask (PhysicsQueries.cast_motion) are handed two
## fractions and could take no push. It looks no further than the motion.
## The hull's rule is shape_cast_prepared's, asked for by name.
func shape_cast(query: PhysicsShapeQueryParameters3D) -> Dictionary:
	var disabled := begin_shape_cast(query)
	var result := _backed_off(query)
	end_shape_cast(disabled)
	return result


func _backed_off(query: PhysicsShapeQueryParameters3D) -> Dictionary:
	var hit := _native_cast(query, query.motion)
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
	# The cache keeps its own copy, as the hull's does.
	_cast_cache = {query.get_instance_id(): {"result": result.duplicate(), "at": query.transform.origin + query.motion * unsafe}}
	return result


## A movement trace can probe several recovery starts without changing the
## world. Synchronize and exclude once for that synchronous group. Callers
## must end the group before moving anything or emitting gameplay signals.
func begin_shape_cast(query: PhysicsShapeQueryParameters3D) -> Array:
	sync_dynamic(query.collision_mask, query.exclude)
	if _scope_owner.is_valid() and query.exclude.size() == 1 and query.exclude[0] == _scope_owner:
		# Left out for the whole scope already.
		return []
	return _disable_excluded(query.exclude)


func end_shape_cast(disabled: Array) -> void:
	_restore_excluded(disabled)


## The hull's sweep (PlayerBody._trace, between begin_shape_cast and
## end_shape_cast), with the clearance the movement needs kept at its end:
## fraction
## is how far along the motion the shape may go and stay CAST_CLEARANCE
## clear of what it met, unsafe_fraction where the native cast stopped
## (its smaller shape 0.197 short of touching, 1 at most), and offset a
## push along the plane the shape needs on top of that (Vector3.ZERO but
## for a grazing hit).
##
## The native cast reports nothing when the shape only comes within its
## contact band by the end of the motion without touching, and the next
## cast from there then starts in overlap (a hull stepping down 18 onto a
## floor 0.15 higher than where it stood found no floor, and stayed put; a
## move ending a hair above a rising floor bought a recovery search). So the
## sweep looks CAST_REACH further and reports a hit wherever the motion's
## end would be inside the clearance. And a hit at a few degrees, a floor
## ahead of a walking hull, would need to back off further along the
## motion than it went to gain its clearance: it backs off CAST_BACK_OFF at
## most and takes the rest as offset, so the hull goes on up the slope.
func shape_cast_prepared(query: PhysicsShapeQueryParameters3D) -> Dictionary:
	var motion := query.motion
	var length := motion.length()
	var direction := motion / length if length > 0.0 else Vector3.ZERO
	var hit := _native_cast(query, direction * (length + CAST_REACH) if length > 0.0 else motion, CAST_INSET)
	if not bool(hit.get("hit", false)):
		return {}
	var result := _mapped(hit)
	if result.is_empty():
		return {}
	var normal: Vector3 = result.get("normal", Vector3.ZERO)
	# The smaller shape stops 0.197 short as the whole one would, so the
	# whole one is that much nearer: its clearance makes it up.
	var clearance := maxf(query.margin, CAST_CLEARANCE) + _inset
	# Along the motion, to where the native cast stopped; zero for a start
	# in overlap, which has no plane and goes nowhere.
	var contact := float(hit["fraction"]) * (length + CAST_REACH) if length > 0.0 else 0.0
	var stop := contact
	var offset := Vector3.ZERO
	if normal.length_squared() > 0.5:
		# Backing off along the motion gains approach of clearance a unit.
		var approach := absf(direction.dot(normal))
		var back := minf(minf(clearance / maxf(approach, 0.000001), CAST_BACK_OFF), contact)
		stop = contact - back
		if stop > length:
			# The whole motion fits; what lies past its end is its back-off.
			stop = length
			back = contact - length
		var missing := clearance - back * approach
		if missing > 0.001:
			offset = normal * missing
	else:
		stop = 0.0
	if stop >= length and length > 0.0 and offset == Vector3.ZERO:
		return {}
	result["fraction"] = stop / length if length > 0.0 else 0.0
	result["unsafe_fraction"] = minf(contact / length, 1.0) if length > 0.0 else 0.0
	result["offset"] = offset
	# The cache keeps its own copy: a caller that edits the hit it is handed
	# must not change what get_rest_info reads next.
	_cast_cache = {query.get_instance_id(): {"result": result.duplicate(), "at": query.transform.origin + direction * contact}}
	return result


## The shape swept as it is, or `inset` smaller all round (the hull's
## sweep, shape_cast_prepared): what it came to for this shape is kept in
## _inset, for the clearance to make up.
func _native_cast(query: PhysicsShapeQueryParameters3D, motion: Vector3, inset: float = 0.0) -> Dictionary:
	var mask := _mask(query.collision_mask, query.collide_with_bodies, query.collide_with_areas)
	var at := query.transform
	var from := at.origin * SCALE
	var to := (at.origin + motion) * SCALE
	var scale := at.basis.get_scale().abs()
	_inset = 0.0
	if query.shape is SphereShape3D:
		var radius := (query.shape as SphereShape3D).radius * scale.x
		_inset = minf(inset, radius * 0.5)
		return native_world.call(&"shape_cast_sphere", from, to, (radius - _inset) * SCALE, mask, QUERY_LAYER)
	if query.shape is CapsuleShape3D:
		var capsule := query.shape as CapsuleShape3D
		var half_axis := maxf(0.0, capsule.height * 0.5 - capsule.radius)
		var radius := capsule.radius * scale.x
		_inset = minf(inset, radius * 0.5)
		return native_world.call(&"shape_cast_capsule", (at * (Vector3.UP * half_axis)) * SCALE, (at * (Vector3.DOWN * half_axis)) * SCALE, (radius - _inset) * SCALE, motion * SCALE, mask, QUERY_LAYER)
	if query.shape is BoxShape3D and at.basis.orthonormalized().is_equal_approx(Basis.IDENTITY):
		var size := (query.shape as BoxShape3D).size * scale
		_inset = minf(inset, minf(size.x, minf(size.y, size.z)) * 0.25)
		return native_world.call(&"shape_cast_box", from, to, (size - Vector3.ONE * (2.0 * _inset)) * SCALE, mask, QUERY_LAYER)
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
