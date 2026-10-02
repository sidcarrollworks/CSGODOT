class_name SkinnedHitboxes
extends Node3D

## A model's hitboxes (HitboxSet) on its skeleton, following the bones.
##
## Each capsule is a Hitbox of its own, so a trace says which part of the
## body it hit. They are not children of the bones: the model is scaled
## from the export's metres to units, and physics shapes do not take a
## scale, so the hitboxes stand unscaled under this node and are moved
## every time the skeleton updates, to where their bone's points now are.

var hitboxes: Array[Hitbox] = []

## Counts every change to where the capsules are, which are on their layer
## and which there are: the bones followed, a death, a revival, the set
## built or cleared. Between two of them the capsules move only as this
## node does. What keeps a copy of the capsules (Box3DQueries, for a
## round's ray) goes by it, so a capsule moved or taken off its layer any
## other way is not seen: Hitbox.set_on_layer for its layer, follow() for
## its place.
var changes: int = 0
## How many of the capsules are on their layer, where a round can meet
## them: none of a dead body's.
var on_layer: int = 0

var _skeleton: Skeleton3D
var _entries: Array[Dictionary] = []


## Builds the capsules on a skeleton whose bones are in metres, unit_scale
## units each, and registers them with the target that takes the damage.
## Returns how many landed on a bone the skeleton has.
func build(skeleton: Skeleton3D, capsules: Array[Dictionary], target: HitTarget, unit_scale: float) -> int:
	clear()
	_skeleton = skeleton
	var by_lower := {}
	for index in skeleton.get_bone_count():
		by_lower[skeleton.get_bone_name(index).to_lower()] = index
	for capsule in capsules:
		var bone: int = by_lower.get(String(capsule["bone"]).to_lower(), -1)
		if bone < 0:
			continue
		var hitbox := Hitbox.new()
		hitbox.name = "Hitbox_%s" % capsule["name"]
		hitbox.zone = capsule["zone"]
		hitbox.side = capsule["side"]
		hitbox.bone_name = skeleton.get_bone_name(bone)
		var collision := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = capsule["radius"]
		shape.height = (capsule["point1"] - capsule["point0"]).length() + 2.0 * capsule["radius"]
		collision.shape = shape
		hitbox.add_child(collision)
		add_child(hitbox)
		if target != null:
			target.adopt(hitbox)
		hitboxes.append(hitbox)
		_entries.append({
			"hitbox": hitbox,
			"bone": bone,
			"point0": capsule["point0"] / unit_scale,
			"point1": capsule["point1"] / unit_scale,
		})
	if not skeleton.skeleton_updated.is_connected(follow):
		skeleton.skeleton_updated.connect(follow)
	layers_changed()
	follow()
	return hitboxes.size()


func clear() -> void:
	if _skeleton != null and _skeleton.skeleton_updated.is_connected(follow):
		_skeleton.skeleton_updated.disconnect(follow)
	_skeleton = null
	for hitbox in hitboxes:
		hitbox.queue_free()
	hitboxes.clear()
	_entries.clear()
	on_layer = 0
	changes += 1


## The skeleton's bone a hitbox rides, or -1 for one that is not here.
func bone_of(hitbox: Hitbox) -> int:
	for entry in _entries:
		if entry["hitbox"] == hitbox:
			return entry["bone"]
	return -1


## Turns the hitboxes on or off together: off, a body cannot be shot.
func set_active(active: bool) -> void:
	for hitbox in hitboxes:
		hitbox.set_on_layer(active)


## A capsule has gone on its layer or off it (Hitbox.set_on_layer).
func layers_changed() -> void:
	on_layer = 0
	for hitbox in hitboxes:
		if hitbox.collision_layer != 0:
			on_layer += 1
	changes += 1


## Moves every capsule to its bone.
func follow() -> void:
	if _skeleton == null or not is_inside_tree():
		return
	for entry in _entries:
		var bone_to_world: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(entry["bone"])
		var a: Vector3 = bone_to_world * entry["point0"]
		var b: Vector3 = bone_to_world * entry["point1"]
		(entry["hitbox"] as Hitbox).global_transform = capsule_transform(a, b)
	changes += 1


## Where a capsule between two world points stands: Godot's capsules run
## along their own Y axis.
static func capsule_transform(a: Vector3, b: Vector3) -> Transform3D:
	var axis := b - a
	if axis.length_squared() < 1e-12:
		return Transform3D(Basis.IDENTITY, a)
	var y := axis.normalized()
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
