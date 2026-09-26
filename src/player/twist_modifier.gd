class_name TwistModifier
extends SkeletonModifier3D

## Poses a rig's twist bones every frame from the bones they follow, by the
## model's own tilt-twist constraints (TwistConstraints,
## reference/research/twist-constraints.md). A child of the rig, it runs
## after the clips have set the pose, in the skeleton's deferred update.
##
## For the drawn body only. It turns nothing but the twist bones, which
## carry no hitbox and nothing pinned; the simulation never reads them. A
## body nobody sees (your own, on PlayerSim.UNSEEN_LAYER, or one hidden) is
## left alone.

## Per constraint: the bone turned, the bone followed, and their numbers,
## resolved against the rig once (_resolve).
var _bones := PackedInt32Array()
var _targets := PackedInt32Array()
var _weights := PackedFloat32Array()
var _inverse_offsets: Array[Quaternion] = []
var _input_axes := PackedInt32Array()
var _slave_axes: Array[Vector3] = []
var _rests: Array[Quaternion] = []
## Each constraint's last twist, unwrapped, so a target turning past half a
## turn carries its bone on rather than flipping it back.
var _last := PackedFloat32Array()
var _has_last := PackedByteArray()
## The meshes on the rig, to tell whether anyone can see it.
var _meshes: Array[MeshInstance3D] = []


## Puts the constraints of the model description beside model_path on a rig
## whose meshes are already adopted (RigModel.adopt), so the twist bones are
## in it. Returns the modifier, or null when the model has none or none of
## its bones are on the rig.
static func attach(rig: Skeleton3D, model_path: String) -> TwistModifier:
	if rig == null:
		return null
	var constraints := TwistConstraints.load_for(model_path)
	if constraints.is_empty():
		return null
	var modifier := TwistModifier.new()
	modifier.name = "Twist"
	if modifier.setup(rig, constraints) == 0:
		modifier.free()
		return null
	rig.add_child(modifier)
	return modifier


## Resolves the constraints against a rig's bones, by name in any case (the
## file writes hand_l for the skeleton's hand_L), and keeps the meshes on
## it. Returns how many constraints found both their bones.
func setup(rig: Skeleton3D, constraints: Array[Dictionary]) -> int:
	var by_name := {}
	for bone in rig.get_bone_count():
		by_name[rig.get_bone_name(bone).to_lower()] = bone
	for constraint in constraints:
		var bone: int = by_name.get(String(constraint["bone"]).to_lower(), -1)
		var target: int = by_name.get(String(constraint["target"]).to_lower(), -1)
		if bone < 0 or target < 0:
			continue
		var axis := Vector3.ZERO
		axis[constraint["slave_axis"]] = 1.0
		_bones.append(bone)
		_targets.append(target)
		_weights.append(constraint["weight"])
		_inverse_offsets.append((constraint["offset"] as Quaternion).inverse())
		_input_axes.append(constraint["input_axis"])
		_slave_axes.append(axis)
		_rests.append(rig.get_bone_rest(bone).basis.get_rotation_quaternion())
	_last.resize(_bones.size())
	_has_last.resize(_bones.size())
	_meshes.clear()
	for child in rig.get_children():
		if child is MeshInstance3D:
			_meshes.append(child as MeshInstance3D)
	return _bones.size()


## How many constraints the rig took.
func count() -> int:
	return _bones.size()


## Whether a camera can draw the rig: a visible mesh on a layer other than
## the one nobody's camera draws.
func is_seen() -> bool:
	if not is_visible_in_tree():
		return false
	if _meshes.is_empty():
		return true
	for mesh in _meshes:
		if is_instance_valid(mesh) and mesh.visible and (mesh.layers & ~PlayerSim.UNSEEN_LAYER) != 0:
			return true
	return false


func _process_modification_with_delta(_delta: float) -> void:
	var rig := get_skeleton()
	if rig == null or not is_seen():
		return
	apply(rig)


## Turns every twist bone by its share of its target's twist, now.
##
## The target's rotation in its parent, taken from its offset, is measured
## for twist about input_axis (TwistConstraints.twist_angle); the bone turns
## that far, times its weight, about slave_axis from its rest in its parent.
## A negative weight turns it the other way.
func apply(rig: Skeleton3D) -> void:
	for i in _bones.size():
		var local := rig.get_bone_pose_rotation(_targets[i])
		var angle := TwistConstraints.twist_angle(_inverse_offsets[i] * local, _input_axes[i])
		if _has_last[i] != 0:
			var delta := wrapf(angle - _last[i], -PI, PI)
			angle = _last[i] + delta
		_last[i] = angle
		_has_last[i] = 1
		rig.set_bone_pose_rotation(_bones[i], _rests[i] * Quaternion(_slave_axes[i], angle * _weights[i]))
