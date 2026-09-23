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
## Nothing is layered yet, so firing does not show (roadmap item 6; CS2's
## own layers are in reference/animgraph/worldmodel.md).
##
## The rig faces along +Z (Source's +X); the game's forward is -Z, so the
## model is turned round and then given the body's yaw.

const CLIPS_DIR := "res://assets/characters/animation/anims/world/rifle/_default_rifle"
## The deaths every weapon shares. (Its flinches are additive layers, not
## poses; played whole they fold the body to nothing. So are the shoot_
## clips beside the locomotion ones. Both wait for layers over the
## locomotion, roadmap item 6.)
const SHARED_DIR := "res://assets/characters/animation/anims/world/shared"
const AGENTS := ViewModel.AGENTS

## CS2's locomotion blend spaces, from its own graph
## (scripts/animgraph_tables.gd writes it).
const LOCOMOTION := "res://reference/animgraph/locomotion.json"
## Which of the graph's variations the clips are. CS2 picks it by the
## weapon in hand; every gun anyone carries so far is rifle-style.
const VARIATION := "rifle"
## How far the spaces reach, beyond CS2's furthest clip (225).
const SPACE_EXTENT := 300.0

## Below this the body is standing still, for state().
const STILL_SPEED := 8.0
## CS2's cross-fades into the air and back to the ground (locomotion.md).
const TO_AIR := 0.1
const TO_GROUND := 0.2
## How long a clip played once takes to fade back out.
const BLEND := 0.15

## What animates the body: the locomotion's spaces, the air, a clip played
## once and a death, over the clips animation_player holds.
var animation_tree: AnimationTree

## For each moving space, the length of a cycle at each distance from its
## centre (cycle_rings()).
var _rings := {}
var _speeds := Vector2.ZERO
var _crouch := 0.0
var _on_ground := true
## The death being held, if any.
var _dead: StringName = &""


## Builds the body and weapon. Returns false, with nothing built, when the
## models or clips have not been extracted.
func setup(team: String, weapon_model: String) -> bool:
	one_shots = PackedStringArray(["jump", "draw", "reload", "death"])
	held = PackedStringArray(["death"])
	var clips := list_clips(CLIPS_DIR, PackedStringArray([
		"idle_", "run_", "walk_", "crouch_", "inair_", "jump_stand",
	]))
	clips.append_array(list_clips(SHARED_DIR, PackedStringArray(["death_"])))
	if not load_clips(clips, VARIATION):
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
	_build_tree()
	return true


## The tree over the loaded clips, sharing their library, so fold_bones'
## copies are what it plays. Without the table it falls back to the idle.
func _build_tree() -> void:
	var table := read_locomotion()
	var root := build_tree(table, VARIATION)
	if root == null:
		push_warning("no locomotion blend spaces in %s; the body stands in its idle" % LOCOMOTION)
		play(idle)
		return
	var lengths := {}
	for clip in animation_player.get_animation_list():
		lengths[String(clip)] = animation_player.get_animation(clip).length
	for space_name: StringName in [&"stand", &"crouch"]:
		_rings[space_name] = cycle_rings(find_space(table, "/Move/", _centre_of(space_name), VARIATION), VARIATION, lengths)
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


func _apply() -> void:
	for space_name in [&"stand", &"crouch", &"air_stand", &"air_crouch"]:
		animation_tree.set("parameters/%s/blend_position" % space_name, _speeds)
	animation_tree.set("parameters/move/blend_amount", _crouch)
	animation_tree.set("parameters/air/blend_amount", _crouch)
	animation_tree.set("parameters/cycle/scale", 1.0 / cycle_length(_rings, _speeds.length(), _crouch))
	var wanted := "ground" if _on_ground else "air"
	if String(animation_tree.get("parameters/ground/current_state")) != wanted:
		(_node(&"ground") as AnimationNodeTransition).xfade_time = TO_GROUND if _on_ground else TO_AIR
		animation_tree.set("parameters/ground/transition_request", wanted)


func _node(node_name: StringName) -> AnimationNode:
	return (animation_tree.tree_root as AnimationNodeBlendTree).get_node(node_name)


## Plays a clip by its short name over the locomotion: a death blends in and
## is held; a clip that plays once does, and fades back to the locomotion;
## the idle, or anything the locomotion plays of itself, ends either.
func play(
	short: StringName,
	blend: float = 0.0,
	speed: float = 1.0,
	restart: bool = false
) -> void:
	if animation_tree == null:
		super(short, blend, speed, restart)
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
## tree's first step only builds its caches and poses nothing, so it steps
## twice; on a tree already going the second changes nothing.
func pose_now() -> void:
	if animation_tree != null:
		animation_tree.advance(0.0)
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
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCOMOTION))
	return parsed if parsed is Dictionary else {}


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
	var spaces := {}
	for space_name: StringName in [&"stand", &"crouch", &"air_stand", &"air_crouch"]:
		spaces[space_name] = find_space(table, "/Move/" if space_name in [&"stand", &"crouch"] else "/InAir/", _centre_of(space_name), variation)
		if (spaces[space_name] as Dictionary).is_empty():
			return null
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"stand", blend_space(spaces[&"stand"], variation, true))
	tree.add_node(&"crouch", blend_space(spaces[&"crouch"], variation, true))
	tree.add_node(&"move", _blend2())
	tree.connect_node(&"move", 0, &"stand")
	tree.connect_node(&"move", 1, &"crouch")
	tree.add_node(&"cycle", AnimationNodeTimeScale.new())
	tree.connect_node(&"cycle", 0, &"move")
	tree.add_node(&"air_stand", blend_space(spaces[&"air_stand"], variation, false))
	tree.add_node(&"air_crouch", blend_space(spaces[&"air_crouch"], variation, false))
	tree.add_node(&"air", _blend2())
	tree.connect_node(&"air", 0, &"air_stand")
	tree.connect_node(&"air", 1, &"air_crouch")
	tree.add_node(&"ground", _transition(["ground", "air"]))
	tree.connect_node(&"ground", 0, &"cycle")
	tree.connect_node(&"ground", 1, &"air")
	tree.add_node(&"action", AnimationNodeOneShot.new())
	tree.add_node(&"action_clip", _clip(_centre_of(&"stand")))
	tree.connect_node(&"action", 0, &"ground")
	tree.connect_node(&"action", 1, &"action_clip")
	tree.add_node(&"death", _transition(["alive", "dead"]))
	tree.add_node(&"death_clip", _clip(_centre_of(&"stand")))
	tree.connect_node(&"death", 0, &"action")
	tree.connect_node(&"death", 1, &"death_clip")
	tree.connect_node(&"output", 0, &"death")
	return tree


## One of CS2's blend spaces as Godot's: each point its clip, where CS2
## places it, cut into CS2's own triangles. A moving space's clips are each
## stretched to one cycle, for the cycle's time scale to pace them together.
static func blend_space(space: Dictionary, variation: String, one_cycle: bool) -> AnimationNodeBlendSpace2D:
	var out := AnimationNodeBlendSpace2D.new()
	out.auto_triangles = false
	out.sync = true
	out.min_space = Vector2.ONE * -SPACE_EXTENT
	out.max_space = Vector2.ONE * SPACE_EXTENT
	for point: Dictionary in space.get("points", []):
		var clip := _clip(clip_name(point, variation))
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
static func cycle_rings(space: Dictionary, variation: String, lengths: Dictionary) -> Array:
	var by_radius := {}
	for point: Dictionary in space.get("points", []):
		var radius := snappedf(Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))).length(), 5.0)
		var seconds := float(point.get("lasts", -1.0))
		if seconds <= 0.0:
			seconds = float(lengths.get(String(clip_name(point, variation)), 1.0))
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
