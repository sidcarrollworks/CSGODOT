class_name HandGrip
extends SkeletonModifier3D

## Puts a body's hands back on the gun it holds (Sid, 2026-09-29: guns
## floating out of the hands of the bots he spectated): CS2's hand IK, which
## its third-person AimCS node blends in over 0.3 s
## (HandIKBlendInTimeSeconds, reference/animgraph/worldmodel.md), done here
## with the targets the clips already carry.
##
## The gun hangs off the rig's wpn bone, which is not under the arms: CS2's
## UpperBody mask names it apart from spine_0 (PlayerModel.UPPER_BODY). The
## clips key the arms and the gun together, with the hands' targets beside
## the gun as wpnHand_L and wpnHand_R, but whatever turns the spine or the
## hips after them carries the hands away and leaves the gun where it was:
## the rifle locomotion under the gun's additive hold, the shot and jump
## additives. (FootPlant lowering the pelvis on a slope did too, by up to 12
## units, until it took the gun down with it: FootPlant.lower_gun.)
## So each frame, after the foot fit and before the twist bones follow the
## forearms, this bends each arm with two-bone IK (FootPlant.reach) so its
## hand lands on its target, keeping the hand's own turn and the elbow on the
## side it bent to.
##
## A hand far off its target (FULL_GAP to MOST_GAP, fading) is one the clip
## took off the gun on purpose, or a target the item's clips do not use, and
## is left where the clip has it. While a draw or a reload plays the owner
## lets go (holding), and it eases away over EASE, as CS2 blends it by
## the weapon's action.

## Each arm's bones, from the shoulder down, and the target its hand goes to.
const ARMS := [
	["arm_upper_L", "arm_lower_L", "hand_L", "wpnHand_L"],
	["arm_upper_R", "arm_lower_R", "hand_R", "wpnHand_R"],
]
## CS2's HandIKBlendInTimeSeconds.
const EASE := 0.3
## A hand within this many units of its target goes all the way to it.
const FULL_GAP := 6.0
## A hand this far or further from its target is left where the clip has it.
const MOST_GAP := 12.0

## Whether to hold the gun: something in hand, alive, and no draw or reload
## playing. Set by the owner each frame; off, the fit eases away.
var holding := false
## How far each hand was from its target before the fit, in units, for the
## checks (left, right).
var gaps := PackedFloat32Array([0.0, 0.0])

var _weight := 0.0


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_weight = move_toward(_weight, 1.0 if holding else 0.0, 1.0 if delta <= 0.0 else delta / EASE)
	var units := (skeleton.global_basis if skeleton.is_inside_tree() else skeleton.basis).get_scale().x
	for arm in ARMS.size():
		gaps[arm] = fit(skeleton, ARMS[arm], _weight, units)


## Bends one arm (bones: shoulder, elbow, hand, target) so its hand goes
## weight of the way to its target, by how near it is (share()). units is
## the skeleton's scale to units. Returns how far the hand was from the
## target, in units; -1 when the rig lacks a bone.
static func fit(skeleton: Skeleton3D, bones: Array, weight: float, units: float) -> float:
	var hand := skeleton.find_bone(bones[2])
	var target := skeleton.find_bone(bones[3])
	if hand < 0 or target < 0:
		return -1.0
	var hand_pose := skeleton.get_bone_global_pose(hand)
	var target_at := skeleton.get_bone_global_pose(target).origin
	var gap := hand_pose.origin.distance_to(target_at) * units
	var amount := share(gap) * weight
	if amount > 0.0 and gap * amount > 0.001:
		FootPlant.reach(skeleton, [bones[0], bones[1], bones[2]], hand_pose.origin.lerp(target_at, amount), hand_pose.basis.get_rotation_quaternion())
	return gap


## How much of the way a hand gap units from its target is taken to it:
## all of it up to FULL_GAP, none from MOST_GAP.
static func share(gap: float) -> float:
	return clampf((MOST_GAP - gap) / (MOST_GAP - FULL_GAP), 0.0, 1.0)
