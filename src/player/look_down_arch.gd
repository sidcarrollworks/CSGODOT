class_name LookDownArch
extends SkeletonModifier3D

## Bends the lower back of the body you look down at forward as you look
## down, so looking down reads as the back arching over the legs rather than
## only the neck tipping (Sid, 2026-09-26, playtest 2026-09-25 issue 22).
## PlayerView sets how far and about which axis each frame; this runs in the
## skeleton's own update after the clips, on the drawn body only. Nothing
## the simulation reads (the hitboxes ride another body) sees it.

## The bones that share the bend, from the pelvis up. What is above them is
## folded away (PlayerView.FOLDED_BONES) and goes with them.
const BONES: Array[String] = ["spine_0", "spine_1"]

## How far the back is bent, in degrees, forward positive.
var degrees := 0.0
## The axis it bends about, in the world: the view's right hand.
var axis_world := Vector3.RIGHT


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or is_zero_approx(degrees):
		return
	var basis := skeleton.global_basis if skeleton.is_inside_tree() else skeleton.basis
	# A turn keeps its way round through a space that is not mirrored.
	bend(skeleton, basis.inverse() * axis_world, degrees if basis.determinant() > 0.0 else -degrees)


## Bends skeleton's BONES forward by degrees in all, shared evenly, about
## axis in the skeleton's space, the view's right hand: forward is a
## negative turn about it, which tips up toward the view's forward.
static func bend(skeleton: Skeleton3D, axis: Vector3, degrees: float) -> void:
	if axis.is_zero_approx():
		return
	var turn := -deg_to_rad(degrees) / BONES.size()
	var local_axis := axis.normalized()
	for bone_name in BONES:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var parent := skeleton.get_bone_parent(bone)
		var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
		var in_parent := (parent_rotation.inverse() * Quaternion(local_axis, turn) * parent_rotation).normalized()
		skeleton.set_bone_pose_rotation(bone, (in_parent * skeleton.get_bone_pose_rotation(bone)).normalized())
