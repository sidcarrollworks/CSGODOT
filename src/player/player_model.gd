class_name PlayerModel
extends RigModel

## A player seen from outside: the agent's body on the third-person rig,
## the weapon in its hand, animated by the game's locomotion clips.
##
## CS2 animates a moving player from a set of clips in eight directions
## (run_n, run_ne, run_e...) for running, walking and crouching, blended by
## how the player moves relative to where they face, with idles for standing
## still and in-air clips for the rest. This picks the one clip that fits
## and cross-fades to it, and scales its speed to how fast the body is
## going. Nothing is layered, so firing does not show yet.
##
## The rig faces along +Z (Source's +X); the game's forward is -Z, so the
## model is turned round and then given the body's yaw.

const CLIPS_DIR := "res://assets/characters/animation/anims/world/rifle/_default_rifle"
## The deaths every weapon shares. (Its flinches are additive layers, not
## poses; played whole they fold the body to nothing. So are the shoot_
## clips beside the locomotion ones. Both wait for an animation tree to add
## them over the locomotion, roadmap item 6.)
const SHARED_DIR := "res://assets/characters/animation/anims/world/shared"
const AGENTS := ViewModel.AGENTS

## The clips the game runs, walks and crouches at, in units per second: the
## clip plays at that speed and is scaled from there.
const RUN_SPEED := 250.0
const WALK_SPEED := 130.0
const CROUCH_SPEED := 85.0

## Below this the player is standing still, for the animation's purposes.
const STILL_SPEED := 8.0

const BLEND := 0.15


## Builds the body and weapon. Returns false, with nothing built, when the
## models or clips have not been extracted.
func setup(team: String, weapon_model: String) -> bool:
	one_shots = PackedStringArray(["jump", "draw", "reload", "death"])
	held = PackedStringArray(["death"])
	var clips := list_clips(CLIPS_DIR, PackedStringArray([
		"idle_", "run_", "walk_", "crouch_", "inair_", "jump_stand",
	]))
	clips.append_array(list_clips(SHARED_DIR, PackedStringArray(["death_"])))
	if not load_clips(clips, "rifle"):
		return false
	idle = &"idle"

	var agent := instantiate(AGENTS.get(team, AGENTS["T"]))
	if agent != null:
		for mesh in agent.find_children("*thirdperson*", "MeshInstance3D", true, false):
			adopt(mesh, character_rig)
		agent.free()

	# The locomotion clips carry no weapon rig, so the weapon keeps its own
	# skeleton and is held by it: the root bone on the hand's wpn bone.
	var weapon := instantiate(weapon_model) as Node3D
	if weapon != null:
		var meshes := weapon.find_children("*", "MeshInstance3D", true, false)
		for mesh in meshes:
			(mesh as MeshInstance3D).layers = LAYER
			if is_spare_body(mesh, meshes):
				mesh.visible = false
			elif probe_lit:
				_probe_light(mesh)
		var skeletons := weapon.find_children("*", "Skeleton3D", true, false)
		character_rig.get_parent().add_child(weapon)
		if not skeletons.is_empty() and (skeletons[0] as Skeleton3D).get_bone_count() > 0:
			var root_rest := (skeletons[0] as Skeleton3D).get_bone_rest(0)
			# Between the weapon's root and its skeleton sit the export's own
			# nodes; their transform is folded in so the root lands on the bone.
			var to_skeleton := Transform3D.IDENTITY
			var above := (skeletons[0] as Skeleton3D).get_parent() as Node3D
			if above != null and above != weapon:
				to_skeleton = above.transform
			pin(weapon, "wpn", (to_skeleton * root_rest).affine_inverse())

	scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
	rotation_degrees = Vector3(0.0, 180.0, 0.0)
	play(idle)
	return true


## Picks the clip for how the body is moving. velocity is in world space,
## yaw is where the body faces, in the game's degrees (PlayerInput's).
func update_motion(velocity: Vector3, yaw_degrees: float, ducked: bool, on_ground: bool) -> void:
	rotation_degrees.y = 180.0 + yaw_degrees
	if animation_player == null or playing_one_shot():
		# A jump, a shot, a death: left to finish (a death, to stay).
		return
	var forward := Vector3(-sin(deg_to_rad(yaw_degrees)), 0.0, -cos(deg_to_rad(yaw_degrees)))
	var right := Vector3(cos(deg_to_rad(yaw_degrees)), 0.0, -sin(deg_to_rad(yaw_degrees)))
	var ahead := velocity.dot(forward)
	var aside := velocity.dot(right)
	var speed := Vector2(ahead, aside).length()
	var choice := clip_for(ahead, aside, ducked, on_ground)
	var rate := 1.0
	if choice.begins_with("run_"):
		rate = speed / RUN_SPEED
	elif choice.begins_with("walk_"):
		rate = speed / WALK_SPEED
	elif choice.begins_with("crouch_"):
		rate = speed / CROUCH_SPEED
	play(choice, BLEND, clampf(rate, 0.5, 1.6))


## The death for the shot that killed, by the zone the weapon data prices:
## one of the game's own pair for that part of the body where it has one,
## the chest's otherwise.
static func death_for(zone: StringName, variant: int) -> StringName:
	var pick := "a" if variant % 2 == 0 else "b"
	match zone:
		&"stomach": return StringName("death_gut_" + pick)
		&"leg": return StringName("death_rknee_" + pick)
		&"arm": return &"death_rshoulder"
		_: return StringName("death_chest_" + pick)


## The clip's short name for a movement: ahead and aside are the body's
## speed along where it faces and to its right, in units per second.
static func clip_for(ahead: float, aside: float, ducked: bool, on_ground: bool) -> StringName:
	var speed := Vector2(ahead, aside).length()
	if not on_ground:
		return &"inair_stand"
	if speed < STILL_SPEED:
		return &"idle_crouch" if ducked else &"idle"
	var direction := _compass(ahead, aside)
	if ducked:
		return StringName("crouch_" + direction)
	# CS walks at about half of running; the clip changes at the midpoint.
	if speed < (WALK_SPEED + RUN_SPEED) * 0.5:
		return StringName("walk_" + direction)
	return StringName("run_" + direction)


## n is ahead, e is to the right, as the clips are named.
static func _compass(ahead: float, aside: float) -> String:
	var angle := rad_to_deg(atan2(aside, ahead))
	var sector := wrapi(roundi(angle / 45.0), 0, 8)
	return ["n", "ne", "e", "se", "s", "sw", "w", "nw"][sector]
