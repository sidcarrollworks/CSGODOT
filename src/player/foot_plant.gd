class_name FootPlant
extends SkeletonModifier3D

## Plants a standing body's feet on the ground under them (playtest
## 2026-09-25 issue 5): CS2's FootIK on ankle_L and ankle_R
## (reference/animgraph/worldmodel.md), done here without its targets.
##
## The hull stands on the first thing its bottom meets, which on a ramp is
## its uphill edge, so a body drawn at the hull's origin hangs over the
## floor by up to 7 units at T spawn. Each frame this casts one ray under
## each ankle (GroundProbe, the world only), lowers the pelvis by the larger
## of the two gaps, and bends each leg with two-bone IK so that each foot
## comes down by its own gap, keeping whatever lift the clip gives it; the
## foot is then tipped toward the slope. It eases in over EASE on the
## ground and out in the air, and follows a changing floor over the same.
##
## It runs in the skeleton's own update after the clips, so it moves only
## what the skeleton shows: whatever reads the pose there (SkinnedHitboxes,
## on skeleton_updated) sees it too; see reference/research/foot-ik.md for
## what CS2's hitboxes do. It casts only when the owner says so (planting)
## and again only once a foot has moved RECAST from where it last cast.

## Each leg's bones, from the hip down.
const LEGS := [
	["leg_upper_L", "leg_lower_L", "ankle_L"],
	["leg_upper_R", "leg_lower_R", "ankle_R"],
]
const PELVIS := "pelvis"
## The gun's bones, which go down with the pelvis (lower_gun()), in no
## order. Every body's rig is the rifle locomotion clips' (RigModel), on
## which wpnPivot hangs under root_motion, wpn under it, and the rest
## under wpn.
const GUN_BONES: Array[String] = ["wpn", "wpnHand_L", "wpnHand_R", "wpnTip", "wpnEnd", "wpnPivot"]
## The furthest the pelvis is lowered, in units: a foot over a deeper gap
## than this is left where the clip has it, as over a ledge.
const MOST_DROP := 12.0
## How far a foot moves before its ray is cast again, in units.
const RECAST := 1.0
## Seconds to ease the fit in and out, and to follow a changing floor.
const EASE := 0.1
## The most a foot is tipped toward the slope, in degrees.
const MOST_TILT := 30.0

## Whether to plant the feet: on the ground and worth drawing. Set by the
## owner each frame; off, the fit eases away.
var planting := false
## Rays cast so far, for the checks and the profiler.
var rays := 0

var _weight := 0.0
var _drop := 0.0
var _at_once := false
var _gaps := PackedFloat32Array([0.0, 0.0])
var _cast_at: Array[Vector3] = [Vector3.INF, Vector3.INF]
var _cast_gap := PackedFloat32Array([0.0, 0.0])
var _cast_normal: Array[Vector3] = [Vector3.UP, Vector3.UP]
var _normals: Array[Vector3] = [Vector3.UP, Vector3.UP]


## How far the pelvis is lowered now, in units.
func drop() -> float:
	return _drop * _weight


## Takes the floor as it finds it at the next update, not eased from where
## the body last stood: for a body put somewhere else at once, a spawn or
## a respawn. The fit is switched off while a body lies dead and keeps what
## it had, so one that died on the flat and came back on T ramp hung over
## it, and one the other way round stood in the floor, easing to where it
## should be over a third of a second.
func snap() -> void:
	_cast_at = [Vector3.INF, Vector3.INF]
	_at_once = true


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not skeleton.is_inside_tree():
		return
	var at_once := _at_once or delta <= 0.0
	_at_once = false
	var follow := 1.0 if at_once else 1.0 - exp(-delta / EASE)
	_weight = move_toward(_weight, 1.0 if planting else 0.0, 1.0 if at_once else delta / EASE)
	if planting:
		var space := skeleton.get_world_3d().direct_space_state
		var floor_y := skeleton.global_position.y
		for leg in LEGS.size():
			var ankle := skeleton.find_bone(LEGS[leg][2])
			if ankle < 0:
				return
			var at := skeleton.global_transform * skeleton.get_bone_global_pose(ankle).origin
			at.y = floor_y
			_cast(space, leg, at)
			_gaps[leg] = lerpf(_gaps[leg], _cast_gap[leg], follow)
			_normals[leg] = eased_normal(_normals[leg], _cast_normal[leg], follow)
		_drop = lerpf(_drop, maxf(_cast_gap[0], _cast_gap[1]), follow)
	# Flat ground, or eased away: the clip's pose stands.
	if _weight <= 0.0 or maxf(_drop, maxf(_gaps[0], _gaps[1])) * _weight < 0.01:
		return
	fit(skeleton, _drop * _weight, [_gaps[0] * _weight, _gaps[1] * _weight], _normals, _weight)


## A floor's normal eased toward another's, follow of the way: eased
## straight and made a unit again. Both are floors' normals, a few degrees
## apart at most, and Vector3.slerp between two that near finds its axis
## from a cross product too small to make a unit of, which printed an
## error a frame for every such foot.
static func eased_normal(from: Vector3, to: Vector3, follow: float) -> Vector3:
	var eased := from.lerp(to, follow)
	return eased.normalized() if eased.length_squared() > 0.000001 else to


## The gap under a foot at point, cast again only once it has moved RECAST.
func _cast(space: PhysicsDirectSpaceState3D, leg: int, point: Vector3) -> void:
	var moved := Vector2(point.x - _cast_at[leg].x, point.z - _cast_at[leg].z)
	if _cast_at[leg].is_finite() and moved.length_squared() < RECAST * RECAST and absf(point.y - _cast_at[leg].y) < RECAST:
		return
	_cast_at[leg] = point
	rays += 1
	var ground := GroundProbe.ground_below(space, point, MOST_DROP + GroundProbe.LIFT)
	if ground.is_empty() or float(ground["height"]) > MOST_DROP:
		_cast_gap[leg] = 0.0
		_cast_normal[leg] = Vector3.UP
	else:
		_cast_gap[leg] = ground["height"]
		_cast_normal[leg] = ground["normal"]


## Lowers skeleton's pelvis by drop_units and brings each foot down by its
## own gap from where the clip has it, bending the legs to reach, then tips
## each foot toward its ground's normal by tilt of the way (up to
## MOST_TILT). World units and directions; the skeleton may be scaled.
static func fit(skeleton: Skeleton3D, drop_units: float, gaps: Array, normals: Array, tilt: float = 1.0) -> void:
	var pelvis := skeleton.find_bone(PELVIS)
	if pelvis < 0:
		return
	var to_skeleton := skeleton.global_basis.inverse() if skeleton.is_inside_tree() else skeleton.basis.inverse()
	var down := to_skeleton * Vector3.DOWN
	# Where the clip put each ankle, and how it faced, before the pelvis moves.
	var targets: Array[Vector3] = []
	var facing: Array[Quaternion] = []
	for leg in LEGS.size():
		var ankle := skeleton.find_bone(LEGS[leg][2])
		if ankle < 0:
			return
		var pose := skeleton.get_bone_global_pose(ankle)
		targets.append(pose.origin + down * float(gaps[leg]))
		var up_here := (to_skeleton * Vector3.UP).normalized()
		var normal_here := (to_skeleton * (normals[leg] as Vector3)).normalized()
		facing.append(tipped(up_here, normal_here, tilt) * pose.basis.get_rotation_quaternion())
	if drop_units > 0.0:
		var parent := skeleton.get_bone_parent(pelvis)
		var into_parent := skeleton.get_bone_global_pose(parent).basis.inverse() if parent >= 0 else Basis.IDENTITY
		skeleton.set_bone_pose_position(pelvis, skeleton.get_bone_pose_position(pelvis) + into_parent * (down * drop_units))
		lower_gun(skeleton, pelvis, down * drop_units)
	for leg in LEGS.size():
		reach(skeleton, LEGS[leg], targets[leg], facing[leg])


## Lowers the gun's bones by by (the skeleton's space) with the pelvis. The
## gun hangs off wpn, which is not under the pelvis (CS2's UpperBody mask
## names it apart from the spine: PlayerModel.UPPER_BODY), so lowering only
## the pelvis took the body down a slope and left the gun in the air above
## its hands (Sid, 2026-09-29). Of GUN_BONES those move that hang under
## neither the pelvis nor another of them, and the rest come along under
## them: whichever they are on the rig, in whatever order they are named.
## (Taken in the list's order, with only those already moved counted, wpn
## moved and then wpnPivot, which it hangs under on the agents' rigs,
## moved it again: the gun went down twice as far as the body, 24 units
## for 12, and was under the hands where it had been over them.)
static func lower_gun(skeleton: Skeleton3D, pelvis: int, by: Vector3) -> void:
	var moved_with: Array[int] = [pelvis]
	for bone_name: String in GUN_BONES:
		var found := skeleton.find_bone(bone_name)
		if found >= 0:
			moved_with.append(found)
	for bone: int in moved_with:
		if bone == pelvis or _under_any(skeleton, bone, moved_with):
			continue
		var parent := skeleton.get_bone_parent(bone)
		var into_parent := skeleton.get_bone_global_pose(parent).basis.inverse() if parent >= 0 else Basis.IDENTITY
		skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone) + into_parent * by)


static func _under_any(skeleton: Skeleton3D, bone: int, ancestors: Array[int]) -> bool:
	var at := skeleton.get_bone_parent(bone)
	while at >= 0:
		if at in ancestors:
			return true
		at = skeleton.get_bone_parent(at)
	return false


## The rotation that tips a foot from up toward normal, share of the way
## and no more than MOST_TILT.
static func tipped(up: Vector3, normal: Vector3, share: float) -> Quaternion:
	if normal.is_zero_approx() or up.is_equal_approx(normal):
		return Quaternion.IDENTITY
	var angle := minf(up.angle_to(normal), deg_to_rad(MOST_TILT)) * share
	var axis := up.cross(normal)
	if axis.is_zero_approx():
		return Quaternion.IDENTITY
	return Quaternion(axis.normalized(), angle)


## Two-bone IK: turns the hip and knee of one leg (bones: hip, knee, ankle)
## so the ankle lands on target, in the skeleton's space, keeping the knee
## bent the way it was; out of reach it points the leg straight at it. Then
## sets the ankle to face as facing, in the skeleton's space.
static func reach(skeleton: Skeleton3D, bones: Array, target: Vector3, facing: Quaternion) -> void:
	var hip := skeleton.find_bone(bones[0])
	var knee := skeleton.find_bone(bones[1])
	var ankle := skeleton.find_bone(bones[2])
	if hip < 0 or knee < 0 or ankle < 0:
		return
	var hip_at := skeleton.get_bone_global_pose(hip).origin
	var knee_at := skeleton.get_bone_global_pose(knee).origin
	var ankle_at := skeleton.get_bone_global_pose(ankle).origin
	var knee_to := knee_bend(hip_at, knee_at, ankle_at, target)
	_turn(skeleton, hip, knee_at - hip_at, knee_to - hip_at)
	var now_knee := skeleton.get_bone_global_pose(knee).origin
	var now_ankle := skeleton.get_bone_global_pose(ankle).origin
	_turn(skeleton, knee, now_ankle - now_knee, target - now_knee)
	var parent := skeleton.get_bone_parent(ankle)
	var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(ankle, (parent_rotation.inverse() * facing).normalized())


## Where the knee goes for the ankle to reach target: the hip and shin keep
## their lengths, and the knee stays on the side it bent to.
static func knee_bend(hip: Vector3, knee: Vector3, ankle: Vector3, target: Vector3) -> Vector3:
	var upper := hip.distance_to(knee)
	var lower := knee.distance_to(ankle)
	var toward := target - hip
	var along := toward.normalized() if not toward.is_zero_approx() else (ankle - hip).normalized()
	var span := clampf(toward.length(), absf(upper - lower) + 0.001, upper + lower - 0.001)
	var bend := (knee - hip) - along * (knee - hip).dot(along)
	if bend.is_zero_approx():
		bend = (knee - ankle) - along * (knee - ankle).dot(along)
	if bend.is_zero_approx():
		return hip + along * upper
	var cos_hip := clampf((upper * upper + span * span - lower * lower) / (2.0 * upper * span), -1.0, 1.0)
	return hip + along * upper * cos_hip + bend.normalized() * upper * sqrt(1.0 - cos_hip * cos_hip)


## Turns bone in the skeleton's space so that from points where to does.
static func _turn(skeleton: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.is_zero_approx() or to.is_zero_approx():
		return
	var a := from.normalized()
	var b := to.normalized()
	if a.is_equal_approx(b):
		return
	var turn := Quaternion(a, b)
	var parent := skeleton.get_bone_parent(bone)
	var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	var in_parent := parent_rotation.inverse() * turn * parent_rotation
	skeleton.set_bone_pose_rotation(bone, (in_parent * skeleton.get_bone_pose_rotation(bone)).normalized())
