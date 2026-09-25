class_name RigModel
extends Node3D

## What the first- and third-person models have in common: a rig taken from
## one of the game's animation clips, the other clips' animations gathered
## into its player, meshes moved onto its skeletons, and things pinned to
## its bones.
##
## Source 2 Viewer exports every clip as a glTF that carries the skeleton it
## animates, and bone names are the same across the clips, the player models
## and the weapons, so nothing here is retargeted: a mesh is skinned to a rig
## by name, and a rig is animated by the clips made for it.
##
## What a rig can lack is bones a mesh is skinned to (the forearm twist bones
## carry weight; the spine and legs are bound with none), and a mesh skinned
## to a bone the rig has not got is pulled towards the origin. Those are
## added at adoption, following their nearest present ancestor rigidly.

## A folded bone's scale (fold_bones). Not zero: a zero scale is a
## degenerate matrix for the skin to chew on.
const FOLDED := 0.001

## The visual layer the players' models, the bots' and your own arms are
## drawn on, apart from the world's: a bullet hole's projection is deep, and
## would otherwise print itself on someone standing at the wall, or on your
## own gun, whose true place is in the wall when you are pressed against it.
const LAYER := 2

## Lit by the map's light probes rather than Godot's ambient: every mesh
## adopted goes on the probe shader, and light_from hands it a cube.
var probe_lit: bool = true

var animation_player: AnimationPlayer
## The rig the character meshes hang off, and the weapon's, if the clips
## carry one.
var character_rig: Skeleton3D
var weapon_rig: Skeleton3D

## The clip everything else returns to.
var idle: StringName = &""
## Clips that play once; everything else loops.
var one_shots: PackedStringArray = PackedStringArray()
## Prefixes of the one-shot clips that hold their last frame when they end
## rather than going back to idle: a death.
var held: PackedStringArray = PackedStringArray()

var _pins: Array[Dictionary] = []

## How far the point a model is lit from moves before its cube is sampled
## again (light_from), in units: a tick's run at 250 u/s, a sixth of the
## probes' 24-unit cells.
const RELIGHT_DISTANCE := 4.0
var _lit_cube := PackedColorArray()
var _lit_shadow := []
var _lit_at := Vector3.INF
var _lit_by: LightProbes
## Something the light was not put on yet is shown (a gun taken in hand):
## light_from puts it on every mesh again although it did not sample again.
var light_due := true

## What building a body reads, kept for the next one: every scene by its
## path, every clip's animation by the clip's, and every directory's clips.
## A body is built from the same few hundred files each time (its clips, the
## agent, the gun), and a scene nothing holds any more drops out of Godot's
## cache, so each body read them all from the disk again: a quarter of a
## second a body, and at half time everyone's at once. The animations are
## shared, as instances of one scene share them; a model changes copies of
## them (fold_bones, PlayerModel.prepared_set); load_clips sets their loop
## mode, the same for every body.
static var _scenes := {}
static var _animations := {}
static var _listed := {}
## Scenes asked for on worker threads (read_ahead) and not yet taken up.
static var _reading := {}


## Loads clips into this node: the first as the rig, the rest as animations
## of its player, under names with the set's suffix taken off. Returns false,
## with nothing loaded, if there are none.
func load_clips(clips: PackedStringArray, suffix: String) -> bool:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	animation_player = null
	character_rig = null
	weapon_rig = null
	_pins.clear()
	if clips.is_empty():
		return false

	var rig := instantiate(clips[0])
	if rig == null:
		return false
	var players := rig.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		rig.free()
		return false
	animation_player = players[0]
	add_child(rig)
	# Source 2 Viewer gives an animation's skeleton a placeholder mesh to hang
	# the skin on: a few tiny triangles on the bones, which draw as white
	# specks that ride the animation, around your gun and on everyone else.
	for placeholder in rig.find_children("*empty_mesh_reference", "MeshInstance3D", true, false):
		placeholder.get_parent().remove_child(placeholder)
		placeholder.free()
	for skeleton in rig.find_children("*", "Skeleton3D", true, false):
		if skeleton.get_parent().name.begins_with("animation_skeletons_characters"):
			character_rig = skeleton
		else:
			weapon_rig = skeleton
	if character_rig == null:
		return false
	character_rig.skeleton_updated.connect(_update_pins)

	# A copy: instances of a scene share its library, and renaming the clip
	# in one would rename it in every model built from the same clip.
	var library := animation_player.get_animation_library(&"").duplicate() as AnimationLibrary
	animation_player.remove_animation_library(&"")
	animation_player.add_animation_library(&"", library)
	library.rename_animation(animation_player.get_animation_list()[0], short_name(clips[0], suffix))
	add_clips(clips.slice(1), suffix)
	for clip in library.get_animation_list():
		if not _is_one_shot(clip):
			library.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	if not animation_player.animation_finished.is_connected(_on_finished):
		animation_player.animation_finished.connect(_on_finished)
	return true


## Adds more clips to the loaded ones, each under its short name with prefix
## in front (a gun's own set beside the locomotion: weapon_reload). Returns the
## names given, in order.
func add_clips(clips: PackedStringArray, suffix: String, prefix: String = "") -> PackedStringArray:
	var added := PackedStringArray()
	if animation_player == null:
		return added
	var library := animation_player.get_animation_library(&"")
	for clip in clips:
		var animation := clip_animation(clip)
		if animation == null:
			continue
		var clip_name := prefix + String(short_name(clip, suffix))
		library.add_animation(clip_name, animation)
		added.append(clip_name)
	return added


## A clip's animation, the first its scene's player holds, or null: taken
## from the scene once, and from _animations after that.
static func clip_animation(path: String) -> Animation:
	if _animations.has(path):
		return _animations[path]
	var animation: Animation = null
	var scene := instantiate(path)
	if scene != null:
		var donor := scene.find_children("*", "AnimationPlayer", true, false)
		if not donor.is_empty():
			var names := (donor[0] as AnimationPlayer).get_animation_list()
			if not names.is_empty():
				animation = (donor[0] as AnimationPlayer).get_animation(names[0])
		scene.free()
	_animations[path] = animation
	return animation


## Folds bones away to nothing, for the parts of a body the camera must
## not see: the head the camera sits inside, the arms a view model stands in
## for. Everything skinned to them, and to their children, gathers at the
## joint, inside the body and out of sight.
##
## Every clip carries a scale track for every bone and would put the scale
## back each frame, so this model gets copies of the clips without those
## tracks; the clips themselves are shared with every other model.
func fold_bones(bone_names: PackedStringArray) -> void:
	if animation_player == null or character_rig == null:
		return
	var library := animation_player.get_animation_library(&"")
	for clip_name in library.get_animation_list():
		var copy := library.get_animation(clip_name).duplicate() as Animation
		for track in range(copy.get_track_count() - 1, -1, -1):
			if copy.track_get_type(track) == Animation.TYPE_SCALE_3D \
					and String(copy.track_get_path(track).get_subname(0)) in bone_names:
				copy.remove_track(track)
		library.remove_animation(clip_name)
		library.add_animation(clip_name, copy)
	for bone_name in bone_names:
		var index := character_rig.find_bone(bone_name)
		if index >= 0:
			character_rig.set_bone_pose_scale(index, Vector3.ONE * FOLDED)
	# Swapping the clips under a playing animation stops it.
	if idle != &"":
		play(idle)


## Plays a clip by its short name. Unknown names go to idle, and so does
## anything that plays once, when it ends.
##
## restart rewinds a clip that is already running back to its start. Firing
## needs it: a round fired while the last one's animation is still going has
## to kick the gun again.
func play(
	short: StringName,
	blend: float = 0.0,
	speed: float = 1.0,
	restart: bool = false
) -> void:
	if animation_player == null:
		return
	if not animation_player.has_animation(short):
		short = idle
		if short == &"" or not animation_player.has_animation(short):
			return
	var already := (
		animation_player.current_animation == short
		and animation_player.is_playing()
	)
	if already:
		animation_player.speed_scale = speed
		if restart:
			# Rewound rather than played again. AnimationPlayer.play() on the
			# clip it is already playing carries on from where it was, so
			# asking it to fire again did nothing and the gun only animated
			# once per clip length: about once a second on the AK, against a
			# round every tenth of one.
			animation_player.seek(0.0, true)
		return
	if blend <= 0.0:
		animation_player.stop()
	animation_player.speed_scale = speed
	animation_player.play(short, blend)


## Every clip loaded whose name starts with the given prefix, in order.
func clips_named(prefix: String) -> PackedStringArray:
	var found := PackedStringArray()
	if animation_player == null:
		return found
	var names := animation_player.get_animation_list()
	names.sort()
	for clip in names:
		if String(clip).begins_with(prefix):
			found.append(clip)
	return found


func _on_finished(finished: StringName) -> void:
	if _is_held(finished):
		return
	if _is_one_shot(finished) and idle != &"" and animation_player.has_animation(idle):
		animation_player.play(idle)


## Whether a one-shot clip is running now and should be left to finish.
func playing_one_shot() -> bool:
	return animation_player != null and animation_player.is_playing() \
		and _is_one_shot(animation_player.current_animation)


func _is_held(clip: StringName) -> bool:
	for prefix in held:
		if String(clip).begins_with(prefix):
			return true
	return false


func _is_one_shot(clip: StringName) -> bool:
	for prefix in one_shots:
		if String(clip).begins_with(prefix):
			return true
	return false


## Moves a skinned mesh onto a rig, adding every bone its skin binds that
## the rig has not got.
func adopt(mesh: MeshInstance3D, rig: Skeleton3D) -> void:
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
	mesh.layers = LAYER
	if probe_lit:
		_probe_light(mesh)


## Puts a mesh's standard materials on the probe shader.
func _probe_light(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null:
		return
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface)
		if material is BaseMaterial3D:
			mesh.set_surface_override_material(surface, ProbeMaterials.build(material as BaseMaterial3D))


## Puts the model on the probe shader after all, when it was built without
## (probe_lit false): a body nobody saw that is now to be seen.
func use_probe_lighting() -> void:
	if probe_lit:
		return
	probe_lit = true
	light_due = true
	for mesh in find_children("*", "MeshInstance3D", true, false):
		_probe_light(mesh as MeshInstance3D)


## Lights every mesh of the model from a point in the world, through the
## scene's light probes, if it has any. Called by whoever moves the model,
## every frame.
##
## The cube is sampled again only once the point has moved RELIGHT_DISTANCE,
## and put on the meshes only when it was, or when something new is shown
## (light_due): sampling it was 19 us of script and putting it on a body's
## meshes 11 more, every frame for every body (dust2, 2026-09-25), and the
## probes are tens of units apart, so a few units' difference does not show.
func light_from(at: Vector3) -> void:
	var probes := LightProbeField.find(get_tree()) if is_inside_tree() else null
	if probes == null:
		return
	if probes != _lit_by or at.distance_squared_to(_lit_at) >= RELIGHT_DISTANCE * RELIGHT_DISTANCE:
		_lit_cube = probes.cube_at(at)
		_lit_shadow = probes.shadow_placement(at)
		_lit_at = at
		_lit_by = probes
		light_due = true
	if not light_due:
		return
	light_due = false
	for mesh in find_children("*", "MeshInstance3D", true, false):
		ProbeMaterials.light_instance(mesh as MeshInstance3D, _lit_cube, _lit_shadow)


## Keeps a node on a bone of the character rig, every time the rig updates.
## The node's transform becomes the bone's pose, times the inverse given:
## for a weapon rig that is its root bone's rest, which the pose stands in
## for, so the two coincide.
func pin(node: Node3D, bone_name: String, inverse: Transform3D = Transform3D.IDENTITY) -> bool:
	var bone := character_rig.find_bone(bone_name) if character_rig != null else -1
	if bone < 0:
		return false
	_pins.append({"node": node, "bone": bone, "inverse": inverse})
	_update_pins()
	return true


## Lets go of a node pin() kept on a bone.
func unpin(node: Node3D) -> void:
	for i in range(_pins.size() - 1, -1, -1):
		if _pins[i]["node"] == node:
			_pins.remove_at(i)


## A hidden node is not moved: it is put on its bone when it is shown.
func _update_pins() -> void:
	for entry in _pins:
		var node := entry["node"] as Node3D
		if node != null and node.visible and node.is_inside_tree():
			node.global_transform = (
				character_rig.global_transform
				* character_rig.get_bone_global_pose(entry["bone"])
				* entry["inverse"]
			)


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


## A scene by its path, read once (_scenes), or null when it is not there.
static func instantiate(path: String) -> Node:
	var packed := preload_scene(path)
	return packed.instantiate() if packed != null else null


## A scene by its path, read into _scenes now if it is not already, for an
## instance later that reads nothing from the disk; null when it is not there.
static func preload_scene(path: String) -> PackedScene:
	var packed: PackedScene = _scenes.get(path)
	if packed == null:
		if _reading.has(path):
			# Read ahead: waits only if the worker has not finished it.
			_reading.erase(path)
			packed = ResourceLoader.load_threaded_get(path) as PackedScene
			if packed != null:
				_scenes[path] = packed
			return packed
		if path.is_empty() or not ResourceLoader.exists(path):
			return null
		packed = load(path) as PackedScene
		if packed == null:
			return null
		_scenes[path] = packed
	return packed


## Whether a worker thread is still reading this scene (read_ahead), so
## preload_scene would wait for it.
static func reading(path: String) -> bool:
	return _reading.has(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS


## Starts reading these scenes on worker threads, for preload_scene to take
## up later without reading the disk: a gun's first-person clips, read
## there on the tick it was first bought or picked up, took 136 ms on
## average, the R8's 347 (reference/performance.md). Those read or being
## read already are left. Returns how many were started.
static func read_ahead(paths: PackedStringArray) -> int:
	var started := 0
	for path in paths:
		if path.is_empty() or _scenes.has(path) or _reading.has(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_reading[path] = true
			started += 1
	return started


## The clip glTFs in a directory, sorted, or only those whose names start
## with one of the prefixes given. Looked for once (_listed), and handed out
## as a copy: a packed array comes back from a dictionary shared, and a
## caller appending to it would append to the one kept.
static func list_clips(dir_path: String, prefixes: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var key := dir_path + "|" + ",".join(prefixes)
	if _listed.has(key):
		return (_listed[key] as PackedStringArray).duplicate()
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for file in files:
		if not file.ends_with(".gltf") or not ResourceLoader.exists(dir_path.path_join(file)):
			continue
		var wanted := prefixes.is_empty()
		for prefix in prefixes:
			if file.begins_with(prefix):
				wanted = true
		if wanted:
			out.append(dir_path.path_join(file))
	_listed[key] = out.duplicate()
	return out


## The suffix most of a set's clips end in, after their last underscore:
## the set's weapon, which is not always its folder's (pistol_glock18's clips
## end in _glock, and the revolver's also carry _0 to _7). It can run to more
## than one word, the T knife's clips all ending in _default_t: words before
## the last are added while every clip ending in the suffix shares them and
## still has a name of its own before them. A clip's non-additive copy
## (prepare_shoot_revolver.vnmclip+non_additive, new in CS2 1.41.8.2) is not
## counted: it ends in the copy's name, not the set's, and the revolver has as
## many of them as clips.
static func common_suffix(paths: PackedStringArray) -> String:
	var counts := {}
	for path in paths:
		var stem := path.get_file().get_basename()
		if stem.contains(".vnmclip+"):
			continue
		var last := stem.get_slice("_", stem.get_slice_count("_") - 1)
		counts[last] = counts.get(last, 0) + 1
	var best := ""
	for last in counts:
		if best.is_empty() or counts[last] > counts[best]:
			best = last
	var rests := PackedStringArray()
	for path in paths:
		var stem := path.get_file().get_basename()
		if stem.ends_with("_" + best):
			rests.append(stem.trim_suffix("_" + best))
	while not rests.is_empty():
		var word := ""
		for rest in rests:
			var cut := rest.rfind("_")
			var before := rest.substr(cut + 1) if cut >= 0 else ""
			if before.is_empty() or (not word.is_empty() and before != word):
				word = ""
				break
			word = before
		if word.is_empty():
			break
		best = word + "_" + best
		for i in rests.size():
			rests[i] = rests[i].substr(0, rests[i].rfind("_"))
	return best


## Whether one of a weapon's meshes is the second body its export carries
## (...body_legacy), left out where the weapon has another. In CS2 it is the
## body for skins marked use_legacy_model, the old CS:GO finishes; its
## default shows body_hd. The default knives have only the legacy one, and it
## is their knife.
static func is_spare_body(mesh: Node, meshes: Array) -> bool:
	if not mesh.name.ends_with("body_legacy"):
		return false
	for other: Node in meshes:
		# Another body, not another mesh: the Dual Berettas' holster is not one.
		if other != mesh and other.name.contains("_body_") and not other.name.ends_with("body_legacy"):
			return true
	return false


## "draw_ak.gltf" with suffix "ak" is "draw".
static func short_name(path: String, suffix: String) -> StringName:
	return StringName(path.get_file().get_basename().trim_suffix("_" + suffix))
