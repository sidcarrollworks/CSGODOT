class_name Muzzles
extends RefCounted

## Where each gun's muzzle is, which is where its flash and its tracer
## start: the attachment its CS2 model names muzzle_flash, and on three
## models muzzle_flash2 (the M4A1-S's and USP-S's silencer tip, the Dual
## Berettas' left pistol). Read from every gun's model
## (weapons/models/<dir>/weapon_*.vmdl, decompiled with Source 2 Viewer,
## 2026-09-24, CS2 1.41.8.3): each is an offset in inches in its bone's own
## axes (+X down the barrel, +Y left, +Z up), on weapon_offset, or on the
## Berettas' weapon_r and weapon_l. vdata's m_vecMuzzlePos0 and 1 are the
## same points seen from the eye in the first-person idle pose, which the
## checks hold these to.
##
## One rule serves both views, since the extracted glTF's bones keep
## Source's axes in metres under a root that turns them: the offset,
## scaled to metres, on the bone as it is posed now. First person that is
## the view model's weapon rig, third person the gun in a body's hand. It is
## read per frame, where the gun is drawn, never in the tick.

## [bone, muzzle_flash, bone, muzzle_flash2] by class.
const POINTS := {
	"weapon_glock": [&"weapon_offset", Vector3(4.583174, -0.001193, 0.339271)],
	"weapon_hkp2000": [&"weapon_offset", Vector3(4.25555, 0.003498, 0.479813)],
	"weapon_usp_silencer": [&"weapon_offset", Vector3(5.080554, 0.003535, 0.908709), &"weapon_offset", Vector3(12.862753, 0.003705, 0.834599)],
	"weapon_elite": [&"weapon_r", Vector3(6.6875, -0.001157, 1.141602), &"weapon_l", Vector3(6.692858, -0.00124, 1.121026)],
	"weapon_p250": [&"weapon_offset", Vector3(4.662828, 0.003498, 0.497315)],
	"weapon_tec9": [&"weapon_offset", Vector3(9.752368, -0.001087, 1.245578)],
	"weapon_fiveseven": [&"weapon_offset", Vector3(4.618845, -0.001087, 0.186727)],
	"weapon_cz75a": [&"weapon_offset", Vector3(6.394149, 0.004109, 0.369205)],
	"weapon_deagle": [&"weapon_offset", Vector3(7.243939, 0.0115, 0.991591)],
	"weapon_revolver": [&"weapon_offset", Vector3(7.215837, 0.012271, 1.574948)],
	"weapon_nova": [&"weapon_offset", Vector3(25.030956, 0.208954, -0.829785)],
	"weapon_xm1014": [&"weapon_offset", Vector3(21.552691, 0.208958, -0.953119)],
	"weapon_sawedoff": [&"weapon_offset", Vector3(19.356697, 0.200608, -0.64939)],
	"weapon_mag7": [&"weapon_offset", Vector3(15.384541, 0.200374, 0.230918)],
	"weapon_mac10": [&"weapon_offset", Vector3(5.088435, 0.161771, -1.009941)],
	"weapon_mp9": [&"weapon_offset", Vector3(5.232351, 0.17018, -1.312389)],
	"weapon_mp7": [&"weapon_offset", Vector3(9.010708, -0.031592, -0.006317)],
	"weapon_mp5sd": [&"weapon_offset", Vector3(19.340055, 0.231671, 0.100748)],
	"weapon_ump45": [&"weapon_offset", Vector3(12.879474, 0.160653, -0.251548)],
	"weapon_p90": [&"weapon_offset", Vector3(6.11328, 0.178223, -1.356445)],
	"weapon_bizon": [&"weapon_offset", Vector3(16.049217, 0.16147, -0.760738)],
	"weapon_galilar": [&"weapon_offset", Vector3(18.698488, 0.200659, -0.85997)],
	"weapon_famas": [&"weapon_offset", Vector3(16.396826, 0.200675, -0.401298)],
	"weapon_ak47": [&"weapon_offset", Vector3(22.671568, 0.210674, -0.649208)],
	"weapon_m4a1": [&"weapon_offset", Vector3(18.455202, 0.193322, -0.078313)],
	"weapon_m4a1_silencer": [&"weapon_offset", Vector3(22.416992, 0.311977, 0.064523), &"weapon_offset", Vector3(29.296875, 0.294922, 0.077332)],
	"weapon_sg556": [&"weapon_offset", Vector3(23.119652, 0.200598, -0.358922)],
	"weapon_aug": [&"weapon_offset", Vector3(13.889058, 0.20838, -0.963864)],
	"weapon_m249": [&"weapon_offset", Vector3(28.699007, 0.201364, -0.682603)],
	"weapon_negev": [&"weapon_offset", Vector3(21.146736, 0.200743, -0.038621)],
	"weapon_ssg08": [&"weapon_offset", Vector3(32.867302, 0.442052, 0.14854)],
	"weapon_awp": [&"weapon_offset", Vector3(37.3923, 0.193341, 0.087366)],
	"weapon_g3sg1": [&"weapon_offset", Vector3(25.634689, -0.170404, -0.198042)],
	"weapon_scar20": [&"weapon_offset", Vector3(26.253332, 0.019943, -0.423546)],
	"weapon_taser": [&"weapon_offset", Vector3(4.817113, -0.001182, -0.719068)],
}

const METRE := 0.0254


## Whether a class has its muzzle_flash2 (second) as well.
static func has_second(weapon_class: String) -> bool:
	return (POINTS.get(weapon_class, []) as Array).size() >= 4


## The muzzle on a gun's skeleton as it is posed now, in the world: the
## origin where the flash and the tracer start, basis.x down the barrel.
## second picks muzzle_flash2 where the model has it. Null when the class
## has no muzzle here or the skeleton lacks its bone.
static func on_skeleton(skeleton: Skeleton3D, weapon_class: String, second: bool = false) -> Variant:
	var point: Array = POINTS.get(weapon_class, [])
	if point.is_empty() or skeleton == null:
		return null
	var at := 2 if second and point.size() >= 4 else 0
	var bone := skeleton.find_bone(String(point[at]))
	if bone < 0:
		return null
	var offset: Vector3 = point[at + 1]
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone) * Transform3D(Basis.IDENTITY, offset * METRE)


## The muzzle of the gun in a view model's hands (its weapon rig).
static func in_view(view_model: ViewModel, weapon_class: String, second: bool = false) -> Variant:
	if view_model == null or not is_instance_valid(view_model):
		return null
	return on_skeleton(view_model.weapon_rig, weapon_class, second)


## The muzzle of the gun a body holds (PlayerModel.held_weapon's skeleton).
static func in_hand(model: PlayerModel, weapon_class: String, second: bool = false) -> Variant:
	return on_skeleton(skeleton_of(model), weapon_class, second)


## The skeleton a drawn gun's muzzle is on: a view model's weapon rig, or the
## gun a body holds; null when nothing is drawn.
static func skeleton_of(gun: Node3D) -> Skeleton3D:
	if gun == null or not is_instance_valid(gun):
		return null
	if gun is ViewModel:
		return (gun as ViewModel).weapon_rig
	if gun is PlayerModel and (gun as PlayerModel).held_weapon != null:
		var skeletons := (gun as PlayerModel).held_weapon.find_children("*", "Skeleton3D", true, false)
		return skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	return null


## Where a point on the first-person gun appears to be, in the world: the
## view model is drawn at a narrower field of view (ViewModelProjection), so
## a world effect meant to start on the drawn muzzle (your tracer) starts
## where the world's projection puts the same place on screen. The camera
## space x and y are widened by the narrowing; the depth is kept. Source
## does the same for every view model attachment (FormatViewModelAttachment,
## Source SDK 2013); that CS2's tracer starts there is inferred. narrowing
## is the arms' as drawn now (ViewModelProjection.narrowing_under): a scope
## changes it.
static func as_drawn(eye: Transform3D, point: Vector3, narrowing: float = ViewModelProjection.fov_narrowing()) -> Vector3:
	var local := eye.affine_inverse() * point
	return eye * Vector3(local.x * narrowing, local.y * narrowing, local.z)
