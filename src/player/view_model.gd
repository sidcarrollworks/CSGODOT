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

const CLIPS_ROOT := "res://assets/characters/animation/anims/viewmodel"
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


## Where a first-person set's clips are. A set is named by its folder under
## viewmodel/ ("pistol/pistol_glock18"; reference/weapons/models.md lists
## every gun's); a bare name ("rifle_ak") is a rifle set, as the first two
## guns' were named.
static func clips_dir(clip_set: String) -> String:
	return CLIPS_ROOT.path_join(clip_set if clip_set.contains("/") else "rifle".path_join(clip_set))


## Builds the arms and what they hold: a gun, the knife, a grenade, the
## bomb. Returns false, with nothing built, when the models or clips have
## not been extracted; the game plays on without them.
func setup(team: String, weapon_model: String, clip_set: String) -> bool:
	# Besides a gun's: a grenade's pin and throws, the bomb's plant, the
	# knife's swings. The pin pulled and a throw's end are held, not left
	# for the idle, until the throw and what is drawn next take over.
	one_shots = PackedStringArray([
		"draw", "shoot", "reload", "lookat", "silencer",
		"pullpin", "throw_", "plant", "light_", "heavy_",
	])
	held = PackedStringArray(["pullpin", "throw_"])
	var clips := list_clips(clips_dir(clip_set))
	if not load_clips(clips, common_suffix(clips)):
		return false
	# The idle is "idle" on all but the M249 and G3SG1, whose sets name it
	# "idle1".
	var idles := clips_named("idle")
	idle = &"idle" if idles.has("idle") or idles.is_empty() else StringName(idles[0])
	# Not a pistol's last round, which leaves its slide back (shoot_empty).
	shoot_clips = PackedStringArray(Array(clips_named("shoot")).filter(
		func(clip: String) -> bool: return not clip.contains("empty")))
	_next_shoot = 0

	var agent := instantiate(AGENTS.get(team, AGENTS["T"]))
	if agent != null:
		for mesh in agent.find_children("*firstperson*", "MeshInstance3D", true, false):
			adopt(mesh, character_rig)
		# The forearms' twist bones, which the clips do not key.
		TwistModifier.attach(character_rig, AGENTS.get(team, AGENTS["T"]), TwistModifier.skeleton_of(agent))
		agent.free()

	var weapon := instantiate(weapon_model)
	if weapon != null and weapon_rig != null:
		var meshes := weapon.find_children("*", "MeshInstance3D", true, false)
		for mesh in meshes:
			# The export carries two bodies, the other for legacy skins (the
			# default knives carry only that one, and keep it). And the Dual
			# Berettas carry their thigh holster, which is for the
			# third-person body: no first-person clip poses it, and it floats
			# in the middle of the view.
			if not is_spare_body(mesh, meshes) and not mesh.name.ends_with("_eholster"):
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
