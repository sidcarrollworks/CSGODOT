extends SceneTree

## Checks the extracted weapons and player models, if there are any.
##
##   godot --headless --path . --script tests/run_model_checks.gd
##
## Like the dust2 checks, this passes without checking anything on a machine
## where scripts/extract_assets.sh has not been run. Where it has, it is the
## test that what Godot made of the exports is what the game will need: a
## skeleton to animate, the first-person arm meshes to draw, the weapon's own
## animations, and the first-person clips as animations of their own; and
## that the view model puts them together, with the weapon in the hands.

const WEAPONS_DIR := "res://assets/weapons"
const CHARACTERS_DIR := "res://assets/characters"

var _failures: int = 0
var _checks: int = 0
var _frames: int = 0
var _view_model: ViewModel
var _player_model: PlayerModel


func _init() -> void:
	# CS2's field of view numbers are horizontal at 4:3; Godot's are vertical.
	_check(
		absf(ViewModelOverlay.vertical_fov(90.0) - 73.74) < 0.05
			and absf(ViewModelOverlay.vertical_fov(68.0) - 53.64) < 0.05,
		"CS2's fov 90 and viewmodel_fov 68 convert to 73.7 and 53.6 vertical"
	)

	# Which locomotion clip a movement gets, from the body's speed along its
	# facing and to its right. No assets needed.
	_check(
		PlayerModel.clip_for(250.0, 0.0, false, true) == &"run_n"
			and PlayerModel.clip_for(0.0, 250.0, false, true) == &"run_e"
			and PlayerModel.clip_for(-180.0, -180.0, false, true) == &"run_sw"
			and PlayerModel.clip_for(0.0, -250.0, false, true) == &"run_w",
		"running picks the compass clip for the way the body moves relative to its facing"
	)
	_check(
		PlayerModel.clip_for(130.0, 0.0, false, true) == &"walk_n"
			and PlayerModel.clip_for(60.0, 60.0, true, true) == &"crouch_ne"
			and PlayerModel.clip_for(0.0, 0.0, false, true) == &"idle"
			and PlayerModel.clip_for(2.0, 0.0, true, true) == &"idle_crouch"
			and PlayerModel.clip_for(250.0, 0.0, false, false) == &"inair_stand",
		"walking, crouching, standing and being in the air each have their own"
	)

	var weapons := _find(WEAPONS_DIR, "weapon_rif_")
	var agents := _find(CHARACTERS_DIR.path_join("agents"), "")
	var clips := _find(CHARACTERS_DIR.path_join("animation/anims"), "")
	if weapons.is_empty() and agents.is_empty():
		print("no weapons or characters have been extracted; only the arithmetic was checked.")
		_report()
		return

	_check(weapons.size() >= 2, "both weapons are there (%d found; scripts/extract_assets.sh weapons)" % weapons.size())
	for path in weapons:
		if path.get_file().ends_with("_mag.gltf"):
			continue
		var scene := _instantiate(path)
		if scene == null:
			continue
		var player := scene.find_children("*", "AnimationPlayer", true, false)
		var animations: PackedStringArray = (player[0] as AnimationPlayer).get_animation_list() if not player.is_empty() else PackedStringArray()
		_check(
			not scene.find_children("*", "Skeleton3D", true, false).is_empty(),
			"%s has a skeleton" % path.get_file()
		)
		_check(
			_has(animations, "shoot") and _has(animations, "reload"),
			"%s has its shoot and reload animations (%s)" % [path.get_file(), ", ".join(animations)]
		)
		scene.free()

	_check(agents.size() >= 2, "both player models are there (%d found; scripts/extract_assets.sh characters)" % agents.size())
	for path in agents:
		var scene := _instantiate(path)
		if scene == null:
			continue
		var skeletons := scene.find_children("*", "Skeleton3D", true, false)
		_check(
			not skeletons.is_empty() and (skeletons[0] as Skeleton3D).get_bone_count() >= 80,
			"%s has a full skeleton (%d bones)" % [path.get_file(), (skeletons[0] as Skeleton3D).get_bone_count() if not skeletons.is_empty() else 0]
		)
		for part in ["firstperson_default_gloves_arms", "firstperson_sleeves", "thirdperson_body"]:
			var found := scene.find_children("*%s*" % part, "MeshInstance3D", true, false)
			_check(
				not found.is_empty() and (found[0] as MeshInstance3D).mesh != null,
				"%s has its %s mesh" % [path.get_file(), part]
			)
		scene.free()

	_check(clips.size() >= 20, "the first-person rifle animations are there (%d found)" % clips.size())
	var checked := 0
	for path in clips:
		if not ("shoot" in path.get_file() or "draw" in path.get_file() or "reload" in path.get_file()):
			continue
		var scene := _instantiate(path)
		if scene == null:
			continue
		var players := scene.find_children("*", "AnimationPlayer", true, false)
		var ok := false
		if not players.is_empty():
			var list := (players[0] as AnimationPlayer).get_animation_list()
			if list.size() == 1:
				var animation := (players[0] as AnimationPlayer).get_animation(list[0])
				# One track per bone of the 69-bone view-model skeleton.
				ok = animation.get_track_count() >= 50 and animation.length > 0.1
		_check(ok, "%s is one animation over the view-model skeleton" % path.get_file())
		scene.free()
		checked += 1
		if checked >= 4:
			break

	# The rest needs frames: the rigs only pose once the tree has processed.
	_view_model = ViewModel.new()
	root.add_child(_view_model)
	var data := WeaponLibrary.ak47()
	_check(_view_model.setup("T", data.model_path, data.clip_set), "the view model builds for the AK-47 and a T")
	ViewModelOverlay.claim(_view_model)

	_player_model = PlayerModel.new()
	root.add_child(_player_model)
	_check(_player_model.setup("CT", WeaponLibrary.m4a1s().model_path), "the third-person model builds for the M4A1-S and a CT")


func _process(_delta: float) -> bool:
	_frames += 1
	if _view_model == null:
		return _frames > 1
	if _frames < 3:
		return false

	var player: AnimationPlayer = _view_model.animation_player
	_check(
		player != null and player.has_animation(&"draw") and player.has_animation(&"idle")
			and player.has_animation(&"shoot1") and player.has_animation(&"reload"),
		"draw, idle, shoot1 and reload are there under their short names"
	)
	_check(
		player != null and player.get_animation(&"idle").loop_mode == Animation.LOOP_LINEAR
			and player.current_animation == &"draw",
		"idle loops, and the draw is what plays first"
	)
	var meshes := _view_model.find_children("*", "MeshInstance3D", true, false)
	var arms := 0
	var weapon := 0
	var on_layer := 0
	for mesh in meshes:
		if mesh.name.contains("firstperson"):
			arms += 1
		if mesh.name.contains("weapon_rif"):
			weapon += 1
		if (mesh as MeshInstance3D).layers == 1 << (ViewModelOverlay.LAYER - 1) \
				and (mesh as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			on_layer += 1
	_check(arms == 2 and weapon >= 1, "the arm meshes and the weapon are on the rigs (%d arms, %d weapon)" % [arms, weapon])
	_check(on_layer == meshes.size(), "and every mesh is on the overlay's layer, casting no shadow")

	var arm_rig: Skeleton3D = _view_model.character_rig
	var weapon_rig: Skeleton3D = _view_model.weapon_rig
	_check(
		arm_rig != null and arm_rig.find_bone("arm_lower_L_TWIST") >= 0
			and arm_rig.get_bone_parent(arm_rig.find_bone("arm_lower_L_TWIST")) == arm_rig.find_bone("arm_lower_L"),
		"a twist bone the rig lacked was added under its parent"
	)
	if arm_rig != null and weapon_rig != null:
		var wpn: Vector3 = (arm_rig.global_transform * arm_rig.get_bone_global_pose(arm_rig.find_bone("wpn"))).origin
		var weapon_root: Vector3 = (weapon_rig.global_transform * weapon_rig.get_bone_global_pose(0)).origin
		_check(
			wpn.distance_to(weapon_root) < 0.01,
			"the weapon's root sits on the wpn bone (%.3f apart)" % wpn.distance_to(weapon_root)
		)
		var muzzle: Vector3 = (weapon_rig.global_transform * weapon_rig.get_bone_global_pose(weapon_rig.find_bone("muzzle"))).origin
		_check(
			muzzle.z < wpn.z - 10.0,
			"and the muzzle is well ahead of it, down the camera's -Z (%.1f)" % (muzzle.z - wpn.z)
		)

	_view_model.play(&"shoot1")
	_check(player.current_animation == &"shoot1", "a shot plays the shoot clip")
	_view_model.play(&"not_a_clip")
	_check(player.current_animation == &"idle", "an unknown clip falls back to idle")
	_view_model.free()
	_view_model = null

	_test_player_model()
	_report()
	return true


func _test_player_model() -> void:
	var model := _player_model
	if model == null:
		return
	var animations := model.animation_player
	_check(
		animations != null and animations.has_animation(&"run_n") and animations.has_animation(&"walk_sw")
			and animations.has_animation(&"crouch_e") and animations.has_animation(&"idle")
			and animations.has_animation(&"inair_stand"),
		"the eight-way run, walk and crouch clips, the idles and the in-air clip are there"
	)
	var body := model.find_children("*thirdperson_body", "MeshInstance3D", true, false)
	var arms := model.find_children("*firstperson*", "MeshInstance3D", true, false)
	_check(not body.is_empty() and arms.is_empty(), "the third-person body is on the rig and the first-person arms are not")
	var rig: Skeleton3D = model.character_rig
	_check(
		rig != null and rig.find_bone("arm_lower_R_TWIST") >= 0,
		"the twist bones the body is skinned to were added to the rig"
	)
	var weapon_root: Node3D = null
	for child in rig.get_parent().get_children():
		if child.name.contains("weapon_rif"):
			weapon_root = child
	var skeleton: Skeleton3D = weapon_root.find_children("*", "Skeleton3D", true, false)[0] if weapon_root != null else null
	if rig != null and skeleton != null:
		var wpn: Vector3 = (rig.global_transform * rig.get_bone_global_pose(rig.find_bone("wpn"))).origin
		var root: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(0)).origin
		_check(wpn.distance_to(root) < 0.01, "the weapon's root bone sits on the hand's wpn bone (%.3f apart)" % wpn.distance_to(root))
	var head: Vector3 = (rig.global_transform * rig.get_bone_global_pose(rig.find_bone("head_0"))).origin
	_check(
		head.y > 60.0 and head.y < 72.0 and (rig.global_transform * rig.get_bone_global_pose(rig.find_bone("root_motion"))).origin.y < 0.5,
		"the model stands on its origin with its head about five and a half feet up (%.1f)" % head.y
	)

	# Facing +Z at yaw 180 (the game's forward is -Z at yaw 0), running forward.
	model.update_motion(Vector3(0, 0, 240), 180.0, false, true)
	_check(
		animations.current_animation == &"run_n" and absf(animations.speed_scale - 0.96) < 0.01,
		"running forward at 240 plays run_n at 0.96 of the clip's speed (%s at %.2f)" % [animations.current_animation, animations.speed_scale]
	)
	model.update_motion(Vector3(-100, 0, 0), 180.0, false, true)
	_check(animations.current_animation == &"walk_e", "sidestepping to the right at walking pace plays walk_e (%s)" % animations.current_animation)
	model.free()
	_player_model = null


func _find(dir_path: String, prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".gltf") and not file.ends_with("_physics.gltf") and file.begins_with(prefix):
			out.append(dir_path.path_join(file))
	for subdirectory in dir.get_directories():
		out.append_array(_find(dir_path.path_join(subdirectory), prefix))
	return out


func _instantiate(path: String) -> Node:
	var packed := load(path) as PackedScene
	_check(packed != null, "%s imports as a scene" % path.get_file())
	if packed == null:
		return null
	return packed.instantiate()


func _has(names: PackedStringArray, fragment: String) -> bool:
	for name in names:
		if name.contains(fragment):
			return true
	return false


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	printerr("FAIL: %s" % description)


func _report() -> void:
	if _failures == 0:
		print("%d model checks passed." % _checks)
		quit(0)
	else:
		printerr("%d of %d model checks failed." % [_failures, _checks])
		quit(1)
