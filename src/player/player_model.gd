class_name PlayerModel
extends RigModel

## A player seen from outside: the agent's body on the third-person rig,
## the weapon in its hand, animated as CS2's own graph animates it.
##
## CS2 moves the body with blend spaces (reference/animgraph2.md): the
## running and walking clips of the eight directions, and the idle among
## them, each placed at the speed it is authored for, forward and to the left
## of the body. The space is cut into triangles, and the body's speed mixes
## the three clips around it. A second space does the same crouched, and how
## far down the body is mixes the two. The places and the triangles here are
## the game's, read from its locomotion graph into
## reference/animgraph/locomotion.json. The air is two more spaces of the same
## kind, with CS2's cross-fades into it and back; a death is blended in over
## the top and held.
##
## CS2 keeps the clips it mixes in step: each clip's sync track is its whole
## cycle, so every clip is at the same point of its stride. Godot's spaces
## play each clip at its own length (the run's 0.73 s, the walk's 1 s), so
## here every moving clip is stretched to one cycle, and a time scale over
## them sets how long a cycle takes: the lengths of the clips being mixed,
## weighted as the mix weighs them, which is how CS2 times its blend.
##
## Over the locomotion go the gun's own clips, through CS2's UpperBody mask
## and in the order its graph stacks them (reference/animgraph/worldmodel.md):
## the gun's hold added, a reload or draw in place of the upper body, and each
## shot added on top (add_weapon_layers()). CS2's additive clips hold bare
## differences, which Godot adds only as differences from the rest pose, so
## they are re-expressed from the rest as they load (rest_relative()).
##
## The rig faces along +Z (Source's +X); the game's forward is -Z, so the
## model is turned round and then given the body's yaw.

const CLIPS_DIR := "res://assets/characters/animation/anims/world/rifle/_default_rifle"
## The deaths every weapon shares. (Its flinches are additive, like the
## guns' shots, and would go in as the shots do; they are not extracted.)
const SHARED_DIR := "res://assets/characters/animation/anims/world/shared"
const AGENTS := ViewModel.AGENTS

## CS2's locomotion blend spaces, from its own graph
## (scripts/animgraph_tables.gd writes it).
const LOCOMOTION := "res://reference/animgraph/locomotion.json"
## Which of the graph's variations the clips are. CS2 picks it by the
## weapon in hand; a body built with one gun moves as a rifle does.
const VARIATION := "rifle"
## The graph's other variations, which a body that holds whatever is in its
## hand moves by as well: each the same spaces with its own clips, from its
## own set, loaded under its name (pistol_run_n). CS2 picks one by what is
## in hand (variation_for(), reference/animgraph/parameters.md), keeps the
## one it has while the draw plays (not while action_deploy) and switches
## after it, its idle poses cross-fading into the new weapon's in 0.2 s, 0.5
## into a pistol's (reference/animgraph/worldmodel.md; the same in 1.41.8.3).
const HELD_VARIATIONS := {"pistol": "pistol/_default_pistol", "knife": "knife/_default_knife"}
const VARIATION_FADE := 0.2
const PISTOL_FADE := 0.5
## The locomotion clips a variation's set is read for.
const LOCOMOTION_CLIPS := ["idle_", "run_", "walk_", "crouch_", "inair_", "jump_stand"]
## How far the spaces reach, beyond CS2's furthest clip (225).
const SPACE_EXTENT := 300.0

## Below this the body is standing still, for state().
const STILL_SPEED := 8.0
## CS2's cross-fades into the air and back to the ground (locomotion.md).
const TO_AIR := 0.1
const TO_GROUND := 0.2
## How long a clip played once takes to fade back out.
const BLEND := 0.15

## Where a gun's own third-person set is (world_clip_set under it).
const WORLD_DIR := "res://assets/characters/animation/anims/world"
## What the gun's own clips are loaded as: weapon_idle, weapon_reload.
const WEAPON := "weapon_"
## CS2's UpperBody bone mask (worldmodel.vnmskel), which its weapon, shooting
## and idle-pose layers go through: these bones and every bone under them,
## all at full weight.
const UPPER_BODY := ["spine_0", "wpn", "wpnHand_L", "wpnHand_R", "wpnTip", "wpnEnd", "wpnPivot"]
## How long a gun's reload or draw takes to fade back into the hold.
const ACTION_FADE := 0.2
## How many models of what it has held a body keeps, shown or hidden, before
## it lets them all go and builds again what it holds next.
const MODELS_KEPT := 4

## The gun clips as the body plays them (prepared_set()), by the clip's path:
## the rig is the same in every model, and so are they.
static var _prepared := {}
## The locomotion table, read once (read_locomotion()), which hands out
## copies of it.
static var _locomotion := {}

## What animates the body: the locomotion's spaces, the air, the gun's hold,
## its reload and draw and its shots over the upper body, a clip played once
## and a death, over the clips animation_player holds.
var animation_tree: AnimationTree
## Whether the gun's layers are in the tree: its own set was loaded, or the
## body holds whatever is put in its hand (holds_items).
var has_weapon_layers := false
## The gun in the hand, pinned to its wpn bone; null holding none.
var held_weapon: Node3D
## Whether the body holds what is put in its hand (hold()), rather than the
## one gun it was built with, for life.
var holds_items := false
## The item in the hand, by class; "" for none (hold()).
var holding: String = ""

## Where in the library the held item's own clips are: WEAPON for the set the
## body was built with, "held_<set>_" for one taken in hand since; "" for none.
var _hold_prefix := ""
## Whether the held item has a hold of its own, and a shot.
var _has_hold := false
var _has_shoot := false
## The held item's model, and the models of what the body has held, by
## class, each pinned to the wpn bone and shown only while in the hand
## (show_held()); the class shown.
var _held_model_path := ""
var _held_models := {}
var _shown := ""

## The locomotion the tree moves by, each by where its parameters are
## ("" for a body with the one, "rifle/", "pistol/", "knife/" for one with
## them all): for each moving space, the length of a cycle at each distance
## from its centre (cycle_rings()).
var _rings := {}
## Which of them the body moves by now, and the one it goes to once the
## draw under way is over (at _switch_at_usec, simulation time), or "".
var _variation := VARIATION
var _pending_variation := ""
var _switch_at_usec := 0
var _speeds := Vector2.ZERO
var _crouch := 0.0
var _on_ground := true
## The death being held, if any.
var _dead: StringName = &""


## Builds the body and weapon. weapon_set is the gun's own third-person set
## under WORLD_DIR (WeaponData.world_clip_set), for its hold, reload, draw and
## shots; without one the body only moves. A body that holds_items is built
## holding nothing, with the gun's layers ready for whatever it is handed
## (hold()), and weapon_model and weapon_set are not used. Returns false,
## with nothing built, when the models or clips have not been extracted.
func setup(team: String, weapon_model: String, weapon_set: String = "", holds: bool = false) -> bool:
	one_shots = PackedStringArray(["jump", "draw", "reload", "death"])
	held = PackedStringArray(["death"])
	var clips := list_clips(CLIPS_DIR, PackedStringArray(LOCOMOTION_CLIPS))
	clips.append_array(list_clips(SHARED_DIR, PackedStringArray(["death_"])))
	if not load_clips(clips, VARIATION):
		return false
	idle = &"idle"
	holds_items = holds
	if holds:
		for variation: String in HELD_VARIATIONS:
			var added := add_clips(list_clips(WORLD_DIR.path_join(HELD_VARIATIONS[variation]), PackedStringArray(LOCOMOTION_CLIPS)), variation, variation + "_")
			for clip_name in added:
				if not clip_name.begins_with(variation + "_jump"):
					animation_player.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
	var weapon_clips := PackedStringArray() if holds else _add_set(weapon_set, WEAPON)

	var agent := instantiate(AGENTS.get(team, AGENTS["T"]))
	if agent != null:
		for mesh in agent.find_children("*thirdperson*", "MeshInstance3D", true, false):
			adopt(mesh, character_rig)
		agent.free()

	if not holds:
		held_weapon = attach_weapon(weapon_model)

	scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
	rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_build_tree(weapon_clips)
	return true


## A weapon's model beside the rig, held by its own skeleton: the locomotion
## clips carry no weapon rig, so its root bone is pinned on the hand's wpn
## bone. Null when the model is not there. The buy menu's agent, which
## CS2's own poses stand (BuyMenuAgent), holds its items with it too.
func attach_weapon(weapon_model: String) -> Node3D:
	var weapon := instantiate(weapon_model) as Node3D
	if weapon == null:
		return null
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
	return weapon


## A gun's own third-person clips, from its set (rifle/rifle_ak), added to
## this body's clips under prefix: its hold, draw, reload and shot, as
## weapon_idle, weapon_draw and so on. Returns the names they are under.
func _add_set(weapon_set: String, prefix: String) -> PackedStringArray:
	var names := PackedStringArray()
	var library := animation_player.get_animation_library(&"")
	var clips := prepared_set(weapon_set)
	for action: String in clips:
		var clip_name := StringName(prefix + action)
		if not library.has_animation(clip_name):
			library.add_animation(clip_name, clips[action])
		names.append(clip_name)
	return names


## A gun's own third-person clips as the body plays them, by action (idle,
## idle_crouch, draw, reload, shoot): each keeps only the body's tracks (they
## carry the gun's own rig too, its bolt and magazine, which the body's rig
## has not got), and CS2's additive ones, which have a non-additive copy
## beside them, are made ones Godot adds as CS2 does (rest_relative()). Made
## once for every body (_prepared); the first call for a set reads it from
## the disk, so a map calls it for what its players will hold before play
## (prepare_holding()).
func prepared_set(weapon_set: String) -> Dictionary:
	var out := {}
	if weapon_set.is_empty() or character_rig == null:
		return out
	var files := PackedStringArray()
	for path in list_clips(WORLD_DIR.path_join(weapon_set)):
		if not path.get_file().contains(".vnmclip+"):
			files.append(path)
	var suffix := common_suffix(files)
	var body_node := String(animation_player.get_animation(idle).track_get_path(0).get_concatenated_names())
	for path in files:
		var action := String(short_name(path, suffix))
		if not _prepared.has(path):
			var source := clip_animation(path)
			if source == null:
				continue
			var clip := source.duplicate() as Animation
			for track in range(clip.get_track_count() - 1, -1, -1):
				if String(clip.track_get_path(track).get_concatenated_names()) != body_node:
					clip.remove_track(track)
			if ResourceLoader.exists(path.get_basename() + ".vnmclip+non_additive.gltf"):
				clip = rest_relative(clip, character_rig)
			clip.loop_mode = Animation.LOOP_LINEAR if action.begins_with("idle") else Animation.LOOP_NONE
			_prepared[path] = clip
		out[action] = _prepared[path]
	return out


## Reads what holding each of these items needs before play, so that taking
## one in hand reads nothing from the disk: its clips (prepared_set()) and,
## for a body that is seen (models), its model's scene. team picks the knife.
func prepare_holding(item_classes: PackedStringArray, team: String, models: bool = true) -> void:
	for item_class in item_classes:
		var look := WeaponLibrary.look(item_class, team)
		prepared_set(String(look.get("world_clip_set", "")))
		if models:
			preload_scene(String(look.get("model_path", "")))


## Takes an item in the hand, by class, as look has it (WeaponLibrary.look):
## its own third-person clips for the hold, the draw, the reload and the
## shots, from its set, and its draw played. "" holds nothing. A body built
## with one gun (not holds_items) holds that one whenever anything is in
## hand. Its model is shown from the next frame drawn (show_held()): the pose
## is what the hitboxes ride, and the gun is only seen.
func hold(item_class: String, look: Dictionary = {}) -> void:
	if not holds_items:
		if held_weapon != null:
			held_weapon.visible = not item_class.is_empty()
		return
	if item_class == holding:
		return
	holding = item_class
	_held_model_path = String(look.get("model_path", ""))
	var weapon_set := String(look.get("world_clip_set", ""))
	_hold_prefix = ""
	if not item_class.is_empty() and not weapon_set.is_empty():
		_hold_prefix = "held_%s_" % weapon_set.get_file()
		_add_set(weapon_set, _hold_prefix)
	var stand := _held_clip(&"idle")
	var shot := _held_clip(&"shoot")
	_has_hold = stand != &""
	_has_shoot = shot != &""
	if animation_tree == null or not has_weapon_layers:
		return
	var moves_by := variation_for(item_class) if not item_class.is_empty() else _variation
	_pending_variation = ""
	if moves_by != _variation and _rings.has(moves_by + "/"):
		var draw := _held_clip(&"draw")
		if draw == &"":
			_switch_variation(moves_by)
		else:
			# The legs and body keep what they had while the draw plays.
			_pending_variation = moves_by
			_switch_at_usec = SimClock.now_usec() + int(animation_player.get_animation(draw).length * 1_000_000.0)
	var crouched := _held_clip(&"idle_crouch")
	(_node(&"hold_stand") as AnimationNodeAnimation).animation = stand if _has_hold else idle
	(_node(&"hold_crouch") as AnimationNodeAnimation).animation = crouched if crouched != &"" else (stand if _has_hold else idle)
	(_node(&"shoot_clip") as AnimationNodeAnimation).animation = shot if _has_shoot else idle
	animation_tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	animation_tree.set("parameters/gun_action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_apply(true)
	if _held_clip(&"draw") != &"":
		play(&"draw")


## Nothing in the hand: a death's, whose gun falls as an item of its own.
func let_go() -> void:
	hold("")


## The held item's own clip for an action, standing; empty if it has none.
func _held_clip(action: StringName) -> StringName:
	if _hold_prefix.is_empty():
		return &""
	var clip := StringName(_hold_prefix + String(action))
	return clip if animation_player.has_animation(clip) else &""


## Shows the model of the item in hand on the wpn bone and hides the rest,
## built the first time it is wanted. Per frame, from whoever draws the body.
## A body keeps the models of the last few things it held (MODELS_KEPT).
func show_held() -> void:
	if not holds_items or holding == _shown:
		return
	_shown = holding
	if held_weapon != null:
		held_weapon.visible = false
	held_weapon = null
	if holding.is_empty():
		return
	held_weapon = _held_models.get(holding)
	if held_weapon == null:
		if _held_models.size() >= MODELS_KEPT:
			for item_class: String in _held_models.keys():
				unpin(_held_models[item_class])
				(_held_models[item_class] as Node).queue_free()
			_held_models.clear()
		held_weapon = attach_weapon(_held_model_path)
		if held_weapon == null:
			return
		_held_models[holding] = held_weapon
	held_weapon.visible = true
	_update_pins()


## One of CS2's additive clips made one Godot's additive nodes add as CS2
## does. CS2's hold the difference itself, applied in the bone's own space
## (Esoterica's AdditiveBlendFunction: base * delta, and base + delta for the
## translation); Godot adds a clip's difference from the bone's rest (base *
## rest^-1 * key, base + key - rest). So each key becomes rest * delta and
## rest + delta. Scale goes: CS2 keeps it as an offset near nothing, which is
## no change.
static func rest_relative(clip: Animation, rig: Skeleton3D) -> Animation:
	var out := clip.duplicate() as Animation
	for track in range(out.get_track_count() - 1, -1, -1):
		var type := out.track_get_type(track)
		if type == Animation.TYPE_SCALE_3D:
			out.remove_track(track)
			continue
		var bone := rig.find_bone(String(out.track_get_path(track).get_subname(0)))
		if bone < 0:
			continue
		var rest := rig.get_bone_rest(bone)
		for key in out.track_get_key_count(track):
			if type == Animation.TYPE_POSITION_3D:
				out.track_set_key_value(track, key, rest.origin + (out.track_get_key_value(track, key) as Vector3))
			elif type == Animation.TYPE_ROTATION_3D:
				out.track_set_key_value(track, key, rest.basis.get_rotation_quaternion() * (out.track_get_key_value(track, key) as Quaternion))
	return out


## The tracks of the upper body, as CS2's mask draws it: every bone at or
## under UPPER_BODY's, as the clips name their tracks.
func upper_body_tracks() -> Array[NodePath]:
	var bones := {}
	for bone in character_rig.get_bone_count():
		var at := bone
		while at >= 0:
			if character_rig.get_bone_name(at) in UPPER_BODY:
				bones[character_rig.get_bone_name(bone)] = true
				break
			at = character_rig.get_bone_parent(at)
	var out: Array[NodePath] = []
	var clip := animation_player.get_animation(idle)
	for track in clip.get_track_count():
		if bones.has(String(clip.track_get_path(track).get_subname(0))):
			out.append(clip.track_get_path(track))
	return out


## The tree over the loaded clips, sharing their library, so fold_bones'
## copies are what it plays. Without the table it falls back to the idle.
func _build_tree(weapon_clips: PackedStringArray) -> void:
	var table := read_locomotion()
	var variations := [VARIATION] + HELD_VARIATIONS.keys() if holds_items else []
	var root := build_varied_tree(table, variations) if holds_items else build_tree(table, VARIATION)
	if root == null:
		push_warning("no locomotion blend spaces in %s; the body stands in its idle" % LOCOMOTION)
		play(idle)
		return
	if holds_items:
		# Nothing in hand yet: the layers stand on the locomotion's idle, and
		# hold() points them at the clips of whatever is handed over.
		add_weapon_layers(root, upper_body_tracks(), idle, idle, idle, &"variation")
		has_weapon_layers = true
	elif (WEAPON + "idle") in weapon_clips and (WEAPON + "shoot") in weapon_clips:
		var crouched := StringName(WEAPON + "idle_crouch") if (WEAPON + "idle_crouch") in weapon_clips else StringName(WEAPON + "idle")
		add_weapon_layers(root, upper_body_tracks(), StringName(WEAPON + "idle"), crouched, StringName(WEAPON + "shoot"))
		has_weapon_layers = true
		_hold_prefix = WEAPON
		_has_hold = true
		_has_shoot = true
	var lengths := {}
	for clip in animation_player.get_animation_list():
		lengths[String(clip)] = animation_player.get_animation(clip).length
	for variation: String in (variations if holds_items else [VARIATION]):
		var rings := {}
		var clip_prefix := "" if variation == VARIATION else variation + "_"
		for space_name: StringName in [&"stand", &"crouch"]:
			rings[space_name] = cycle_rings(find_space(table, "/Move/", _centre_of(space_name), variation), variation, lengths, clip_prefix)
		_rings[variation + "/" if holds_items else ""] = rings
	animation_tree = AnimationTree.new()
	animation_tree.name = "Animation"
	animation_player.get_parent().add_child(animation_tree)
	animation_tree.root_node = animation_player.root_node
	animation_tree.add_animation_library(&"", animation_player.get_animation_library(&""))
	animation_tree.tree_root = root
	animation_player.active = false
	animation_tree.active = true
	_apply()


static func _centre_of(space_name: StringName) -> StringName:
	return {&"stand": &"idle", &"crouch": &"idle_crouch", &"air_stand": &"inair_stand", &"air_crouch": &"inair_crouch_stand"}[space_name]


## Draws the body alpha of the way from where its player stood and faced a
## tick before the last to where the last tick left them, as a frame falling
## between the two should show it: at 64 ticks a second a body drawn where
## the last tick put it moves in steps on a faster screen. The hitboxes ride
## its bones, so a round meets it where the shooter saw it.
func show_between(from: Vector3, to: Vector3, from_yaw_degrees: float, to_yaw_degrees: float, alpha: float) -> void:
	global_position = from.lerp(to, alpha)
	rotation.y = PI + lerp_angle(deg_to_rad(from_yaw_degrees), deg_to_rad(to_yaw_degrees), alpha)


## Moves the animation with the body. velocity is in world space, yaw is
## where the body faces in the game's degrees (PlayerInput's), crouch how far
## down it is, 0 to 1 (PlayerBody.duck_progress).
func update_motion(velocity: Vector3, yaw_degrees: float, crouch: float, on_ground: bool) -> void:
	rotation_degrees.y = 180.0 + yaw_degrees
	if animation_tree == null or _dead != &"":
		# A death is held where it fell.
		return
	_speeds = body_speeds(velocity, yaw_degrees)
	_crouch = clampf(crouch, 0.0, 1.0)
	_on_ground = on_ground
	_apply()


## Sets the tree's parameters from the motion: the locomotion moving now,
## or every one of them (all), for one about to be switched to. A switch
## waiting on a draw is made once the draw is over, on the tick.
func _apply(all: bool = false) -> void:
	if not _pending_variation.is_empty() and SimClock.now_usec() >= _switch_at_usec:
		var moves_by := _pending_variation
		_pending_variation = ""
		_switch_variation(moves_by)
	for at: String in _rings:
		if all or at.is_empty() or at == _variation + "/":
			_apply_locomotion(at)
	if has_weapon_layers:
		animation_tree.set("parameters/hold/add_amount", 1.0 if _has_hold else 0.0)
		animation_tree.set("parameters/hold_pose/blend_amount", _crouch)


func _apply_locomotion(at: String) -> void:
	var path := "parameters/" + at
	for space_name in [&"stand", &"crouch", &"air_stand", &"air_crouch"]:
		animation_tree.set(path + String(space_name) + "/blend_position", _speeds)
	animation_tree.set(path + "move/blend_amount", _crouch)
	animation_tree.set(path + "air/blend_amount", _crouch)
	animation_tree.set(path + "cycle/scale", 1.0 / cycle_length(_rings[at], _speeds.length(), _crouch))
	var wanted := "ground" if _on_ground else "air"
	if String(animation_tree.get(path + "ground/current_state")) != wanted:
		var ground := _node(&"ground") if at.is_empty() else (_node(StringName(at.trim_suffix("/"))) as AnimationNodeBlendTree).get_node(&"ground")
		(ground as AnimationNodeTransition).xfade_time = TO_GROUND if _on_ground else TO_AIR
		animation_tree.set(path + "ground/transition_request", wanted)


## Moves the body by another variation's locomotion, its parameters set
## first, cross-faded as CS2 fades its idle poses.
func _switch_variation(moves_by: String) -> void:
	_variation = moves_by
	_apply_locomotion(moves_by + "/")
	(_node(&"variation") as AnimationNodeTransition).xfade_time = PISTOL_FADE if moves_by == "pistol" else VARIATION_FADE
	animation_tree.set("parameters/variation/transition_request", moves_by)


## The locomotion CS2 moves a body by with an item in hand: the pistol's
## for pistols, the Zeus and the bomb; the knife's for knives and grenades;
## the rifle's for every other gun (reference/animgraph/parameters.md).
static func variation_for(item_class: String) -> String:
	var item := ItemRegistry.item(item_class) if not item_class.is_empty() else null
	if item == null:
		return VARIATION
	if item.slot == ItemDef.Slot.PISTOL or item.slot == ItemDef.Slot.C4 or item.type == "taser":
		return "pistol"
	if item.slot == ItemDef.Slot.KNIFE or item.is_grenade():
		return "knife"
	return VARIATION


func _node(node_name: StringName) -> AnimationNode:
	return (animation_tree.tree_root as AnimationNodeBlendTree).get_node(node_name)


## A round fired: the gun's shot added over the upper body, from its start,
## as CS2's Weapon Shoot layer restarts it on every round.
func fire() -> void:
	if has_weapon_layers and _has_shoot:
		animation_tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## The held gun's own clip for an action (reload, draw), crouched if the body
## is down and the gun has one; empty if the gun has none.
func weapon_clip(action: StringName) -> StringName:
	if not has_weapon_layers or _hold_prefix.is_empty():
		return &""
	var crouched := StringName(_hold_prefix + String(action) + "_crouch")
	if _crouch >= 0.5 and animation_player.has_animation(crouched):
		return crouched
	var standing := StringName(_hold_prefix + String(action))
	return standing if animation_player.has_animation(standing) else &""


## Plays a clip by its short name over the locomotion: a death blends in and
## is held; one of the gun's actions (reload, draw) plays over the upper body
## and fades back into the hold; a clip that plays once over the whole body
## does, and fades back to the locomotion; the idle, or anything the
## locomotion plays of itself, ends a death or a whole-body clip.
func play(
	short: StringName,
	blend: float = 0.0,
	speed: float = 1.0,
	restart: bool = false
) -> void:
	if animation_tree == null:
		super(short, blend, speed, restart)
		return
	var gun_clip := weapon_clip(short)
	if gun_clip != &"" and short != idle:
		(_node(&"gun_action_clip") as AnimationNodeAnimation).animation = gun_clip
		var gun_action := _node(&"gun_action") as AnimationNodeOneShot
		gun_action.fadein_time = blend
		gun_action.fadeout_time = ACTION_FADE
		animation_tree.set("parameters/gun_action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		return
	if _is_held(short) and animation_player.has_animation(short):
		(_node(&"death_clip") as AnimationNodeAnimation).animation = short
		(_node(&"death") as AnimationNodeTransition).xfade_time = blend
		animation_tree.set("parameters/death/transition_request", "dead")
		_dead = short
		return
	if _is_one_shot(short) and animation_player.has_animation(short):
		(_node(&"action_clip") as AnimationNodeAnimation).animation = short
		var action := _node(&"action") as AnimationNodeOneShot
		action.fadein_time = blend
		action.fadeout_time = BLEND
		animation_tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		return
	_dead = &""
	(_node(&"death") as AnimationNodeTransition).xfade_time = blend
	animation_tree.set("parameters/death/transition_request", "alive")
	animation_tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	if has_weapon_layers:
		animation_tree.set("parameters/gun_action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		animation_tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


func playing_one_shot() -> bool:
	if animation_tree == null:
		return super()
	return _dead != &"" or bool(animation_tree.get("parameters/action/active"))


## What the body is doing, in a word: idle, move, air, or the death it is
## holding; empty before it is built.
func state() -> StringName:
	if animation_tree == null:
		return StringName(animation_player.current_animation) if animation_player != null else &""
	if _dead != &"":
		return _dead
	if not _on_ground:
		return &"air"
	return &"idle" if _speeds.length() < STILL_SPEED else &"move"


## Poses the skeleton now rather than at the next animation step. A fresh
## tree's first step only builds its caches and poses nothing, and one with
## the variations' locomotion (holds_items) takes another to settle into its
## first, so it steps three times; on a tree already going the rest change
## nothing.
func pose_now() -> void:
	if animation_tree != null:
		for step in 3:
			animation_tree.advance(0.0)
	elif animation_player != null:
		animation_player.advance(0.0)


## Stops the animation, for a ragdoll to have the bones, or starts it again.
func set_animating(on: bool) -> void:
	if animation_tree != null:
		animation_tree.active = on
	elif animation_player != null:
		animation_player.active = on


func is_animating() -> bool:
	if animation_tree != null:
		return animation_tree.active
	return animation_player != null and animation_player.active


## A velocity as CS2's locomotion takes it: units a second along where the
## body faces, and to its left (move_speed_x, move_speed_y).
static func body_speeds(velocity: Vector3, yaw_degrees: float) -> Vector2:
	var yaw := deg_to_rad(yaw_degrees)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return Vector2(velocity.dot(forward), -velocity.dot(right))


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


## CS2's locomotion blend spaces, as scripts/animgraph_tables.gd wrote them.
static func read_locomotion() -> Dictionary:
	if _locomotion.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCOMOTION))
		_locomotion = parsed if parsed is Dictionary else {}
	return _locomotion.duplicate(true)


## The blend space in the table from a part of CS2's locomotion graph (its
## path containing part) with the clip given at its centre: ("/Move/",
## "idle") is the standing one. Empty when there is none.
static func find_space(table: Dictionary, part: String, centre: StringName, variation: String) -> Dictionary:
	for space: Dictionary in table.get("blend_spaces", []):
		if not String(space.get("path", "")).contains(part):
			continue
		for point: Dictionary in space.get("points", []):
			if is_zero_approx(float(point.get("x", 1.0))) and is_zero_approx(float(point.get("y", 1.0))) \
					and clip_name(point, variation) == centre:
				return space
	return {}


## A point's clip, by the short name the model loads it under: run_n for
## animation/anims/world/rifle/_default_rifle/run_n_rifle.
static func clip_name(point: Dictionary, variation: String) -> StringName:
	var clips: Dictionary = point.get("clips", {})
	return StringName(String(clips.get(variation, "")).get_file().trim_suffix("_" + variation))


## The tree: CS2's standing and crouched spaces mixed by the crouch, under
## the cycle's time scale; its two air spaces mixed the same way; the ground
## and the air cross-faded; a clip played once over that; a death over it
## all. Null when the table lacks a space.
static func build_tree(table: Dictionary, variation: String) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	if not _add_locomotion(tree, table, variation, ""):
		return null
	_add_action_and_death(tree, &"ground")
	return tree


## The same over each of several variations' locomotion, each its own tree
## (named by the variation, its clips under its name but for the first's),
## one of them moving the body at a time (variation).
static func build_varied_tree(table: Dictionary, variations: Array) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"variation", _transition(variations))
	for i in variations.size():
		var variation: String = variations[i]
		var locomotion := AnimationNodeBlendTree.new()
		if not _add_locomotion(locomotion, table, variation, "" if i == 0 else variation + "_"):
			return null
		locomotion.connect_node(&"output", 0, &"ground")
		tree.add_node(StringName(variation), locomotion)
		tree.connect_node(&"variation", i, StringName(variation))
	_add_action_and_death(tree, &"variation")
	return tree


## One variation's locomotion in a tree: the standing and crouched spaces
## mixed by the crouch under the cycle's time scale, the air's the same way,
## the ground and the air cross-faded (ground). False when the table lacks a
## space.
static func _add_locomotion(tree: AnimationNodeBlendTree, table: Dictionary, variation: String, clip_prefix: String) -> bool:
	var spaces := {}
	for space_name: StringName in [&"stand", &"crouch", &"air_stand", &"air_crouch"]:
		spaces[space_name] = find_space(table, "/Move/" if space_name in [&"stand", &"crouch"] else "/InAir/", _centre_of(space_name), variation)
		if (spaces[space_name] as Dictionary).is_empty():
			return false
	tree.add_node(&"stand", blend_space(spaces[&"stand"], variation, true, clip_prefix))
	tree.add_node(&"crouch", blend_space(spaces[&"crouch"], variation, true, clip_prefix))
	tree.add_node(&"move", _blend2())
	tree.connect_node(&"move", 0, &"stand")
	tree.connect_node(&"move", 1, &"crouch")
	tree.add_node(&"cycle", AnimationNodeTimeScale.new())
	tree.connect_node(&"cycle", 0, &"move")
	tree.add_node(&"air_stand", blend_space(spaces[&"air_stand"], variation, false, clip_prefix))
	tree.add_node(&"air_crouch", blend_space(spaces[&"air_crouch"], variation, false, clip_prefix))
	tree.add_node(&"air", _blend2())
	tree.connect_node(&"air", 0, &"air_stand")
	tree.connect_node(&"air", 1, &"air_crouch")
	tree.add_node(&"ground", _transition(["ground", "air"]))
	tree.connect_node(&"ground", 0, &"cycle")
	tree.connect_node(&"ground", 1, &"air")
	return true


## Over the locomotion (moving, the node it comes out of): a clip played
## once over it, and a death over it all.
static func _add_action_and_death(tree: AnimationNodeBlendTree, moving: StringName) -> void:
	tree.add_node(&"action", AnimationNodeOneShot.new())
	tree.add_node(&"action_clip", _clip(_centre_of(&"stand")))
	tree.connect_node(&"action", 0, moving)
	tree.connect_node(&"action", 1, &"action_clip")
	tree.add_node(&"death", _transition(["alive", "dead"]))
	tree.add_node(&"death_clip", _clip(_centre_of(&"stand")))
	tree.connect_node(&"death", 0, &"action")
	tree.connect_node(&"death", 1, &"death_clip")
	tree.connect_node(&"output", 0, &"death")


## The gun's layers, between the locomotion and the clip played once, in the
## order CS2's third-person graph stacks them (reference/animgraph/
## worldmodel.md), each through its UpperBody mask (upper_body, the tracks):
## the gun's idle pose added over the locomotion, as its Idle Poses layer
## does (hold, standing or crouched); a reload or a draw over the upper body
## in place of the rest, as its Weapons layer does (gun_action); and each
## shot added on top, as its Weapon Shoot layer does (shoot). CS2 blends the
## Weapons layer in model space; Godot blends in each bone's own, so here the
## upper body keeps its pose relative to the hips, not to the world.
static func add_weapon_layers(tree: AnimationNodeBlendTree, upper_body: Array[NodePath], hold_stand: StringName, hold_crouch: StringName, shot: StringName, moving: StringName = &"ground") -> void:
	# A node's output feeds one input: the locomotion leaves the whole-body
	# clip's input for the hold's.
	tree.disconnect_node(&"action", 0)
	tree.add_node(&"hold_stand", _clip(hold_stand))
	tree.add_node(&"hold_crouch", _clip(hold_crouch))
	tree.add_node(&"hold_pose", _blend2())
	tree.connect_node(&"hold_pose", 0, &"hold_stand")
	tree.connect_node(&"hold_pose", 1, &"hold_crouch")
	var hold := AnimationNodeAdd2.new()
	_mask(hold, upper_body)
	tree.add_node(&"hold", hold)
	tree.connect_node(&"hold", 0, moving)
	tree.connect_node(&"hold", 1, &"hold_pose")
	var gun_action := AnimationNodeOneShot.new()
	_mask(gun_action, upper_body)
	tree.add_node(&"gun_action", gun_action)
	tree.add_node(&"gun_action_clip", _clip(hold_stand))
	tree.connect_node(&"gun_action", 0, &"hold")
	tree.connect_node(&"gun_action", 1, &"gun_action_clip")
	var shoot := AnimationNodeOneShot.new()
	shoot.mix_mode = AnimationNodeOneShot.MIX_MODE_ADD
	_mask(shoot, upper_body)
	tree.add_node(&"shoot", shoot)
	tree.add_node(&"shoot_clip", _clip(shot))
	tree.connect_node(&"shoot", 0, &"gun_action")
	tree.connect_node(&"shoot", 1, &"shoot_clip")
	tree.connect_node(&"action", 0, &"shoot")


static func _mask(node: AnimationNode, tracks: Array[NodePath]) -> void:
	node.filter_enabled = true
	for track in tracks:
		node.set_filter_path(track, true)


## One of CS2's blend spaces as Godot's: each point its clip, where CS2
## places it, cut into CS2's own triangles. A moving space's clips are each
## stretched to one cycle, for the cycle's time scale to pace them together.
static func blend_space(space: Dictionary, variation: String, one_cycle: bool, clip_prefix: String = "") -> AnimationNodeBlendSpace2D:
	var out := AnimationNodeBlendSpace2D.new()
	out.auto_triangles = false
	out.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_INDEPENDENT
	out.min_space = Vector2.ONE * -SPACE_EXTENT
	out.max_space = Vector2.ONE * SPACE_EXTENT
	for point: Dictionary in space.get("points", []):
		var clip := _clip(StringName(clip_prefix + clip_name(point, variation)))
		if one_cycle:
			clip.use_custom_timeline = true
			clip.timeline_length = 1.0
			clip.stretch_time_scale = true
			clip.loop_mode = Animation.LOOP_LINEAR
		out.add_blend_point(clip, Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))), -1, StringName(point.get("name", "")))
	for triangle: Array in space.get("triangles", []):
		out.add_triangle(int(triangle[0]), int(triangle[1]), int(triangle[2]))
	return out


static func _clip(clip_name_to_play: StringName) -> AnimationNodeAnimation:
	var clip := AnimationNodeAnimation.new()
	clip.animation = clip_name_to_play
	return clip


static func _blend2() -> AnimationNodeBlend2:
	var blend := AnimationNodeBlend2.new()
	blend.sync = true
	return blend


static func _transition(inputs: Array) -> AnimationNodeTransition:
	var transition := AnimationNodeTransition.new()
	transition.input_count = inputs.size()
	for i in inputs.size():
		transition.set_input_name(i, inputs[i])
	return transition


## A moving space's cycle, ring by ring: for each distance of its clips from
## the centre (to five units: the diagonals are a little in), how long their
## cycle is, the mean of their lengths, the idle's the time CS2 makes it
## last. lengths has the clips' lengths by short name. By distance, nearest
## first.
static func cycle_rings(space: Dictionary, variation: String, lengths: Dictionary, clip_prefix: String = "") -> Array:
	var by_radius := {}
	for point: Dictionary in space.get("points", []):
		var radius := snappedf(Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))).length(), 5.0)
		var seconds := float(point.get("lasts", -1.0))
		if seconds <= 0.0:
			seconds = float(lengths.get(clip_prefix + String(clip_name(point, variation)), 1.0))
		var ring: Array = by_radius.get(radius, [])
		ring.append(seconds)
		by_radius[radius] = ring
	var radii := by_radius.keys()
	radii.sort()
	var out := []
	for radius: float in radii:
		var ring: Array = by_radius[radius]
		var total := 0.0
		for seconds: float in ring:
			total += seconds
		out.append([radius, total / ring.size()])
	return out


## How long the blend's cycle lasts at a speed, crouched by crouch: between
## the rings either side of the speed, as the space mixes their clips, and
## the standing and crouched cycles mixed by the crouch.
static func cycle_length(rings: Dictionary, speed: float, crouch: float) -> float:
	return lerpf(_ring_length(rings.get(&"stand", []), speed), _ring_length(rings.get(&"crouch", []), speed), crouch)


static func _ring_length(rings: Array, speed: float) -> float:
	if rings.is_empty():
		return 1.0
	if speed <= float(rings[0][0]):
		return float(rings[0][1])
	for i in range(1, rings.size()):
		if speed <= float(rings[i][0]):
			var along := (speed - float(rings[i - 1][0])) / maxf(float(rings[i][0]) - float(rings[i - 1][0]), 0.001)
			return lerpf(float(rings[i - 1][1]), float(rings[i][1]), along)
	return float(rings[-1][1])
