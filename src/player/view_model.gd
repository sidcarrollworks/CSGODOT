class_name ViewModel
extends RigModel

## The first-person arms and weapon, animated by the game's own clips.
##
## CS2 has no separate arms model: what you see in first person is the
## player model's own arm meshes, skinned to a smaller rig that the
## first-person clips animate, with the weapon on a rig of its own that the
## same clips animate too. Every clip's glTF carries both rigs, so this takes
## one clip's scene as the rig, adds every other clip's animation to its
## player, and hangs the arm meshes off the arm rig and the weapon's meshes
## off the weapon rig.
##
## The weapon rig is a sibling of the arm rig in the export, and nothing in
## the clip places it: in the game it hangs off the arm rig's "wpn" bone. So
## it is pinned to that bone here.
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

## Cross-fade into a firing clip, in seconds. Long enough not to snap, short
## enough that the kick still reads as immediate at 600 rounds a minute.
const SHOOT_BLEND := 0.03

## The firing clips this weapon's set actually carries, found at setup rather
## than assumed. CS2 ships several so a spray does not repeat one animation.
var shoot_clips := PackedStringArray()

var _next_shoot: int = 0


## Builds the arms and weapon. Returns false, with nothing built, when the
## models or clips have not been extracted; the game plays on without them.
func setup(team: String, weapon_model: String, clip_set: String) -> bool:
	one_shots = PackedStringArray(["draw", "shoot", "reload", "lookat", "silencer"])
	var suffix := clip_set.get_slice("_", clip_set.get_slice_count("_") - 1)
	if not load_clips(list_clips(CLIPS_ROOT.path_join(clip_set)), suffix):
		return false
	idle = &"idle"
	shoot_clips = clips_named("shoot")
	_next_shoot = 0

	var agent := instantiate(AGENTS.get(team, AGENTS["T"]))
	if agent != null:
		for mesh in agent.find_children("*firstperson*", "MeshInstance3D", true, false):
			adopt(mesh, character_rig)
		agent.free()

	var weapon := instantiate(weapon_model)
	if weapon != null and weapon_rig != null:
		for mesh in weapon.find_children("*", "MeshInstance3D", true, false):
			# The export carries two bodies; the other is for old hardware.
			if not mesh.name.ends_with("body_legacy"):
				adopt(mesh, weapon_rig)
		weapon.free()
	if weapon_rig != null and weapon_rig.get_bone_count() > 0:
		pin(weapon_rig.get_parent(), "wpn", weapon_rig.get_bone_rest(0).affine_inverse())

	scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
	rotation_degrees = Vector3(0.0, 180.0, 0.0)
	position = offset
	play(&"draw")
	return true


## Kicks the gun for one round, cycling through whatever firing clips the set
## carries and replaying from the top every time.
##
## Every round, not every clip length. The clip is longer than the gap between
## rounds, so leaving a running one alone meant the gun animated about once a
## second on the AK while it was firing ten times a second.
func shoot() -> void:
	if shoot_clips.is_empty():
		return
	play(shoot_clips[_next_shoot], SHOOT_BLEND, 1.0, true)
	_next_shoot = (_next_shoot + 1) % shoot_clips.size()
