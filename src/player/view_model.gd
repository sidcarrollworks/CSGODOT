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

## The AUG's and SG 553's clips at the eye, when the set has them: the pose
## held there and the round fired from it (reference/research/scopes.md).
const IRON_SIGHT_POSE := &"ironsight_fidget"
const IRON_SIGHT_SHOOT := &"ironsight_shoot"
## The idle away from the eye, which the pose stands in for while up.
var _hip_idle: StringName = &""
## How far the gun was up at the eye last frame (raise_to_eye).
var _raised: float = 0.0
## Whether it is going up (or up), rather than coming down (or down).
var _raising := false
## The scope's glass, which the game draws clear: its surfaces are given
## LENS_SHADER when the model is built, and counted here.
var lens_surfaces: int = 0

## The clear opening fills 46% of the screen height in Sid's CS2 reference
## (2026-10-01). The sight clip centres the gun, but needs its own framing,
## beyond the world zoom. Arms FOVs are calibrated against rendered views
## of these extracted models; see reference/research/scopes.md.
const IRON_SIGHT_LENS_HEIGHT := 0.46
var iron_sight_arms_fov := 45.0
const IRON_SIGHT_ARMS_FOV := {"rifle/rifle_sg556": 9.0, "rifle/rifle_aug": 10.0}

const LENS_SHADER := preload("res://src/player/scope_lens.gdshader")


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
		"pullpin", "throw_", "plant", "light_", "heavy_", String(IRON_SIGHT_SHOOT),
	])
	held = PackedStringArray(["pullpin", "throw_"])
	var clips := list_clips(clips_dir(clip_set))
	if not load_clips(clips, common_suffix(clips)):
		return false
	# The idle is "idle" on all but the M249 and G3SG1, whose sets name it
	# "idle1".
	var idles := clips_named("idle")
	idle = &"idle" if idles.has("idle") or idles.is_empty() else StringName(idles[0])
	_hip_idle = idle
	_raised = 0.0
	_raising = false
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
	lens_surfaces = clear_lenses(self)

	scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
	rotation_degrees = Vector3(0.0, 180.0, 0.0)
	position = offset
	iron_sight_arms_fov = IRON_SIGHT_ARMS_FOV.get(clip_set, 45.0)
	play(&"draw")
	return true


## Taken in hand: shown if the player is alive, running again, and drawing
## from the start. CS2's first-person graph goes to Deploying from any state
## on every deploy and swaps Deploy0 and Deploy2 on action_reset, so the draw
## restarts each time (reference/animgraph/viewmodel.md), as the simulation
## restarts the deploy time (PlayerSim._draw). Without the rewind a model
## taken up again part way through its draw carried on from there, or was
## already at idle, while the gun still could not fire.
func deploy(shown: bool) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = shown
	_lower()
	play(&"draw", 0.0, 1.0, true)


## Put away: hidden, stilled, and its clip stopped, so a model put away half
## way through its draw holds none of it for the next time it is taken up.
func put_away() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	if animation_player != null:
		animation_player.stop()


## Kicks the gun for one round, cycling through whatever firing clips the set
## carries and replaying from the top every time.
##
## Every round, not every clip length. The clip is longer than the gap between
## rounds, so leaving a running one alone meant the gun animated about once a
## second on the AK while it was firing ten times a second.
func shoot() -> void:
	if _raising and has_clip(IRON_SIGHT_SHOOT):
		play(IRON_SIGHT_SHOOT, SHOOT_BLEND, 1.0, true)
		return
	if shoot_clips.is_empty():
		return
	play(shoot_clips[_next_shoot], SHOOT_BLEND, 1.0, true)
	_next_shoot = (_next_shoot + 1) % shoot_clips.size()


## Raises the gun to the eye as far as amount (0 at the hip, 1 up;
## Weapon.iron_sight_amount), for the AUG and SG 553 as they scope. CS2's
## first-person graph blends its idle into the pose at the eye by that
## amount (weapon_ironsight_amount; reference/animgraph/viewmodel.md,
## Idle). Here the set's pose clip is faded in over the time the rest of
## the way takes at the gun's pull-up speed, and out again at its put-down
## speed; a clip already running, a shot or a reload, is left to finish
## and goes to the pose or the idle after it. Nothing for a gun without
## the pose.
func raise_to_eye(amount: float, data: WeaponData) -> void:
	if data == null or not data.has_iron_sight() or not has_clip(IRON_SIGHT_POSE):
		if _raising:
			_lower()
		return
	var raising := amount > _raised or amount >= 1.0
	if amount <= 0.0:
		raising = false
	_raised = amount
	if raising == _raising:
		return
	_raising = raising
	if raising:
		idle = IRON_SIGHT_POSE
		_to_idle((1.0 - amount) / data.iron_sight_pull_up_speed)
	else:
		idle = _hip_idle
		_to_idle(amount / maxf(data.iron_sight_put_down_speed, 0.001))


## Back at the hip at once, as a draw starts.
func _lower() -> void:
	_raised = 0.0
	_raising = false
	if _hip_idle != &"":
		idle = _hip_idle


## Fades to the idle over blend seconds, unless a one-shot clip is running.
func _to_idle(blend: float) -> void:
	if animation_player == null or playing_one_shot():
		return
	play(idle, maxf(blend, 0.0))


func has_clip(clip: StringName) -> bool:
	return animation_player != null and animation_player.has_animation(clip)


## Gives the surfaces of a scope's glass under node the clear lens: CS2's
## AUG and SG 553 name the material rif_aug_scope_glass and
## rif_sg556_scope_glass, and the lens's dirt scope_lens_dirt
## (reference/research/scopes.md). How many it found.
static func clear_lenses(node: Node) -> int:
	var found := 0
	var lens: ShaderMaterial = null
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material == null or not is_lens(material.resource_name):
				continue
			if lens == null:
				lens = ShaderMaterial.new()
				lens.shader = LENS_SHADER
				lens.resource_name = "scope_lens"
			mesh.set_surface_override_material(surface, lens)
			found += 1
	return found


## Whether a material, by name, is a scope's glass.
static func is_lens(material_name: String) -> bool:
	var lower := material_name.to_lower()
	return lower.contains("scope_glass") or lower.contains("scope_lens")
