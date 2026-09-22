class_name ViewModel
extends Node3D

## The first-person arms and weapon, animated by the game's own clips.
##
## CS2 has no separate arms model: what you see in first person is the
## player model's own arm meshes, skinned to a smaller rig that the
## first-person clips animate, with the weapon on a rig of its own that the
## same clips animate too. Source 2 Viewer exports every clip as a glTF that
## carries both rigs, so this takes one clip's scene as the rig, adds every
## other clip's animation to its player, and hangs the arm meshes off the arm
## rig and the weapon's meshes off the weapon rig. Bone names are the same
## across all of them, which is what makes that work without retargeting.
##
## What is not the same: the arm rig leaves out bones the arms are skinned to
## (the twist bones matter; the spine and legs are bound but weightless), and
## a mesh skinned to a bone the rig has not got is pulled towards the origin.
## Those are added to the rig at setup, following their nearest ancestor
## rigidly. The forearm does not twist, but it stays on the arm.
##
## The weapon rig is a sibling of the arm rig in the export, and nothing in
## the clip places it: in the game it hangs off the arm rig's "wpn" bone. So
## it is pinned to that bone here, every time the arm rig updates.
##
## Clip space is the camera: origin at the eye, forward along +Z (Source's
## +X), in metres. This node turns that round to look down Godot's -Z and
## scales it up to inches, so it goes under the camera and nowhere else.

const CLIPS_ROOT := "res://assets/characters/animation/anims/viewmodel/rifle"
const AGENTS := {
	"T": "res://assets/characters/agents/models/tm_phoenix/tm_phoenix_varianta.gltf",
	"CT": "res://assets/characters/agents/models/ctm_sas/ctm_sas.gltf",
}

## A nudge, in inches, from where the clips put the arms. CS2's own default
## is none.
@export var offset := Vector3.ZERO

var _player: AnimationPlayer
var _arm_rig: Skeleton3D
var _weapon_rig: Skeleton3D
var _idle: StringName = &""
## Where the weapon rig hangs, and the weapon root's own rest, which the
## bone's pose replaces.
var _wpn_bone: int = -1
var _weapon_root_rest_inverse := Transform3D.IDENTITY


## Builds the arms and weapon. Returns false, with nothing built, when the
## models or clips have not been extracted; the game plays on without them.
func setup(team: String, weapon_model: String, clip_set: String) -> bool:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_player = null

	var clips := _list_clips(CLIPS_ROOT.path_join(clip_set))
	if clips.is_empty():
		return false
	var suffix := clip_set.get_slice("_", clip_set.get_slice_count("_") - 1)

	# The rig is whichever clip comes first; the rest lend it their animations.
	var rig := _instantiate(clips[0])
	if rig == null:
		return false
	var players := rig.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		rig.free()
		return false
	_player = players[0]
	add_child(rig)
	for skeleton in rig.find_children("*", "Skeleton3D", true, false):
		if skeleton.get_parent().name.begins_with("animation_skeletons_characters"):
			_arm_rig = skeleton
		else:
			_weapon_rig = skeleton
	if _arm_rig != null and _weapon_rig != null and _weapon_rig.get_bone_count() > 0:
		_wpn_bone = _arm_rig.find_bone("wpn")
		_weapon_root_rest_inverse = _weapon_rig.get_bone_rest(0).affine_inverse()
		if _wpn_bone >= 0 and not _arm_rig.skeleton_updated.is_connected(_hang_weapon):
			_arm_rig.skeleton_updated.connect(_hang_weapon)

	# A copy: instances of a scene share its library, and renaming the clip
	# in one would rename it in every view model built from the same clip.
	var library := _player.get_animation_library(&"").duplicate() as AnimationLibrary
	_player.remove_animation_library(&"")
	_player.add_animation_library(&"", library)
	for clip in clips:
		var short := _short_name(clip, suffix)
		if clip == clips[0]:
			var only := _player.get_animation_list()[0]
			library.rename_animation(only, short)
		else:
			var scene := _instantiate(clip)
			if scene == null:
				continue
			var donor := scene.find_children("*", "AnimationPlayer", true, false)
			if not donor.is_empty():
				var animation: Animation = (donor[0] as AnimationPlayer).get_animation(
					(donor[0] as AnimationPlayer).get_animation_list()[0]
				)
				library.add_animation(short, animation)
			scene.free()
		if short.begins_with("idle"):
			_idle = short
			library.get_animation(short).loop_mode = Animation.LOOP_LINEAR

	var agent := _instantiate(AGENTS.get(team, AGENTS["T"]))
	if agent != null and _arm_rig != null:
		for mesh in agent.find_children("*firstperson*", "MeshInstance3D", true, false):
			_adopt(mesh, _arm_rig)
		agent.free()

	var weapon := _instantiate(weapon_model)
	if weapon != null and _weapon_rig != null:
		for mesh in weapon.find_children("*", "MeshInstance3D", true, false):
			# The export carries two bodies; the other is for old hardware.
			if not mesh.name.ends_with("body_legacy"):
				_adopt(mesh, _weapon_rig)
		weapon.free()

	scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
	rotation_degrees = Vector3(0.0, 180.0, 0.0)
	position = offset
	if not _player.animation_finished.is_connected(_on_finished):
		_player.animation_finished.connect(_on_finished)
	play(&"draw")
	return true


## Plays a clip by its short name: draw, idle, shoot1, reload, lookat01...
## Anything but idle goes back to idle when it ends.
func play(short: StringName) -> void:
	if _player == null:
		return
	if not _player.has_animation(short):
		if short != _idle and _idle != &"":
			_player.play(_idle)
		return
	_player.stop()
	_player.play(short)


## Puts the weapon rig's root where the arm rig's wpn bone is. Both rigs sit
## under the same parent, so one bone's pose is the other's node transform,
## less the root bone's own rest, which the pose stands in for.
func _hang_weapon() -> void:
	(_weapon_rig.get_parent() as Node3D).transform = (
		_arm_rig.get_bone_global_pose(_wpn_bone) * _weapon_root_rest_inverse
	)


func _on_finished(finished: StringName) -> void:
	if finished != _idle and _idle != &"":
		_player.play(_idle)


## Moves a skinned mesh onto a rig, adding every bone its skin binds that
## the rig has not got. Most carry no weight and cost nothing; the twist
## bones do, and are the point.
func _adopt(mesh: MeshInstance3D, rig: Skeleton3D) -> void:
	var source := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	var skin := mesh.skin
	if source != null and skin != null:
		for bind in skin.get_bind_count():
			var bone_name := skin.get_bind_name(bind)
			if not bone_name.is_empty() and rig.find_bone(bone_name) < 0:
				_add_bone_from(source, bone_name, rig)
	mesh.owner = null
	mesh.get_parent().remove_child(mesh)
	rig.add_child(mesh)
	mesh.skeleton = NodePath("..")
	mesh.transform = Transform3D.IDENTITY


## Adds a bone the rig lacks, under its nearest ancestor the rig has, with
## the rest pose composed along the skipped part of the chain.
func _add_bone_from(source: Skeleton3D, bone_name: String, rig: Skeleton3D) -> void:
	var index := source.find_bone(bone_name)
	if index < 0:
		return
	var rest := source.get_bone_rest(index)
	var parent := source.get_bone_parent(index)
	while parent >= 0 and rig.find_bone(source.get_bone_name(parent)) < 0:
		rest = source.get_bone_rest(parent) * rest
		parent = source.get_bone_parent(parent)
	var added := rig.get_bone_count()
	rig.add_bone(bone_name)
	rig.set_bone_parent(added, rig.find_bone(source.get_bone_name(parent)) if parent >= 0 else -1)
	rig.set_bone_rest(added, rest)
	rig.reset_bone_pose(added)


func _instantiate(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	return packed.instantiate() if packed != null else null


func _list_clips(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for file in files:
		if file.ends_with(".gltf") and ResourceLoader.exists(dir_path.path_join(file)):
			out.append(dir_path.path_join(file))
	return out


## "draw_ak.gltf" with suffix "ak" is "draw".
static func _short_name(path: String, suffix: String) -> StringName:
	return StringName(path.get_file().get_basename().trim_suffix("_" + suffix))
