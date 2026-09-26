class_name CharacterEyes
extends RefCounted

## Aims a model's eyes, as CS2's character shader aims them, for
## character.gdshader to paint (CharacterMaterials): where each eyeball is
## and where it looks, from the rig, every time the rig updates, which is
## per frame and only for what is drawn, never in the tick.
##
## CS2 works this out per vertex (Source 2 Viewer's
## features/csgo_character_eyes_vs.slang, GetCharacterEyeInterpolator). Each
## eye looks from its eyeball bone at the eye_target bone, turned outward by
## the material's walleye about the eye's up, and held within 40 degrees of
## two directions, the eye's forward tipped half up and half down. The
## eye's forward and up are the model's forward and up (Source's +X and +Z)
## turned with the eyeball bone from its bind pose. The answer is the same
## for every vertex of an eye, so it is worked out here once a frame, and
## the shader reads it as plain uniforms.
##
## Those are per model, and two eyes need 18 floats where the character
## shader has four of Godot's 16 instance uniform slots left, so each model
## draws its eyes with its own copy of the one material that has them (the
## Phoenix's balaclava; ProbeMaterials makes one per source for every
## model to share).
##
## The model's forward and up are read off the bind pose rather than the
## export's axes, which Source 2 Viewer has changed between versions: up
## is the forward turned toward the model's left, the left from the right
## eyeball to the left, and the forward from between the eyes to the
## target, which sits straight ahead of the head.

const LEFT := "eyeball_l"
const RIGHT := "eyeball_r"
const TARGET := "eye_target"
## How far an eye turns from each of its two held directions.
const CLAMP := deg_to_rad(40.0)

var _rig: Skeleton3D
var _left := -1
var _right := -1
var _target := -1
## The model's forward and up at bind, in the skeleton's space, and each
## eyeball's bind pose.
var _forward := Vector3.FORWARD
var _up := Vector3.UP
var _left_rest := Transform3D.IDENTITY
var _right_rest := Transform3D.IDENTITY
## World units to a Source unit, per skeleton unit: the export's metres.
var _unit := 1.0 / MapImporter.SOURCE2_VIEWER_SCALE
## Each model's own copies of the eye materials, with their walleye.
var _materials: Array[ShaderMaterial] = []
var _walleye: Array[Vector2] = []


## The eyes of a rig, or null for one without its eyeball and target bones.
static func on(rig: Skeleton3D) -> CharacterEyes:
	var left := rig.find_bone(LEFT)
	var right := rig.find_bone(RIGHT)
	var target := rig.find_bone(TARGET)
	if left < 0 or right < 0 or target < 0:
		return null
	var eyes := CharacterEyes.new()
	eyes._rig = rig
	eyes._left = left
	eyes._right = right
	eyes._target = target
	eyes._left_rest = rig.get_bone_global_rest(left)
	eyes._right_rest = rig.get_bone_global_rest(right)
	var across := eyes._left_rest.origin - eyes._right_rest.origin
	var ahead := rig.get_bone_global_rest(target).origin - (eyes._left_rest.origin + eyes._right_rest.origin) * 0.5
	if across.is_zero_approx() or ahead.is_zero_approx():
		return null
	eyes._up = ahead.cross(across).normalized()
	eyes._forward = across.cross(eyes._up).normalized()
	return eyes


## Gives each surface of mesh whose material draws eyes a copy of it of its
## own, to aim. Returns how many.
func take(mesh: MeshInstance3D) -> int:
	if mesh.mesh == null:
		return 0
	var taken := 0
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface) as ShaderMaterial
		if material == null or material.get_shader_parameter("eyes") != true or material in _materials:
			continue
		var own := material.duplicate() as ShaderMaterial
		mesh.set_surface_override_material(surface, own)
		_materials.append(own)
		_walleye.append(material.get_meta(CharacterMaterials.WALLEYE, Vector2.ZERO))
		taken += 1
	if taken > 0:
		update()
	return taken


## Whether any surface has eyes to aim.
func has_any() -> bool:
	return not _materials.is_empty()


## Aims the eyes where the rig has them now.
func update() -> void:
	if _materials.is_empty() or not is_instance_valid(_rig):
		return
	var world := _rig.global_transform if _rig.is_inside_tree() else _rig.transform
	var target := world * _rig.get_bone_global_pose(_target).origin
	var left := _eye(world, _left, _left_rest, target)
	var right := _eye(world, _right, _right_rest, target)
	for i in _materials.size():
		var material := _materials[i]
		var walleye := _walleye[i]
		var left_view := aim(left[0], left[1], left[2], target, walleye.x)
		var right_view := aim(right[0], right[1], right[2], target, -walleye.y)
		material.set_shader_parameter("eye_left_position", left[0])
		material.set_shader_parameter("eye_left_view", left_view)
		material.set_shader_parameter("eye_left_across", (left[2] as Vector3).cross(left_view).normalized())
		material.set_shader_parameter("eye_right_position", right[0])
		material.set_shader_parameter("eye_right_view", right_view)
		material.set_shader_parameter("eye_right_across", (right[2] as Vector3).cross(right_view).normalized())
		material.set_shader_parameter("eye_scale", left[3])


## An eye in the world: its centre, forward and up, and world units to a
## Source unit there.
func _eye(world: Transform3D, bone: int, rest: Transform3D, target: Vector3) -> Array:
	var pose := _rig.get_bone_global_pose(bone)
	var turn := (pose.basis.orthonormalized() * rest.basis.orthonormalized().inverse())
	var placed := world.basis * pose.basis
	var scale := placed.get_scale().x / maxf(rest.basis.get_scale().x, 1e-6)
	return [
		world * pose.origin,
		(world.basis * (turn * _forward)).normalized(),
		(world.basis * (turn * _up)).normalized(),
		scale * _unit,
	]


## Where an eye at centre looks, toward target, as CS2 aims it: turned
## outward by walleye degrees about its up (positive toward the model's
## left), then held within CLAMP of its forward tipped half up and of its
## forward tipped half down.
static func aim(centre: Vector3, forward: Vector3, up: Vector3, target: Vector3, walleye: float) -> Vector3:
	var view := (target - centre).normalized()
	if view.is_zero_approx():
		return forward
	if walleye != 0.0:
		view = view.rotated(up, deg_to_rad(walleye))
	for tip: float in [0.5, -0.5]:
		var held := (forward + up * tip).normalized()
		if held.angle_to(view) > CLAMP:
			var axis := held.cross(view).normalized()
			if not axis.is_zero_approx():
				view = held.rotated(axis, CLAMP)
	return view.normalized()
