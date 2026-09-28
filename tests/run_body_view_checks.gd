extends "res://tests/check_suite.gd"

## Checks what of your own body the camera can see (PlayerView.FOLDED_BONES)
## without the extracted models: the bones it folds, on a stand-in skeleton
## shaped like the agents', through RigModel.fold_bones as the seen body
## folds them. The same on the agent itself is in run_model_checks.gd
## (needs the assets); what is left in view is Sid's to look at
## (reference/playtest-2026-09-25.md, issue 22).
##
##   godot --headless --path . --script tests/run_body_view_checks.gd


func _initialize() -> void:
	_test_chest_folds()
	_test_look_down()
	await _test_arch_bends_forward()
	await _test_arch_over_the_clips()
	_finish("body-view")


## A rig with the agents' bone names and parents, standing about as tall
## (metres, as Source 2 Viewer exports them), with a jiggle bone on the
## chest as the vests have, and a clip that keys every bone's scale, as
## every clip does.
func _stand_in() -> RigModel:
	var model := RigModel.new()
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	model.add_child(skeleton)
	model.character_rig = skeleton
	var clip := Animation.new()
	clip.length = 1.0
	# name, parent, where from the parent in metres
	for bone: Array in [
		["pelvis", "", Vector3(0, 1.09, 0)],
		["spine_0", "pelvis", Vector3(0, 0.08, 0)],
		["spine_1", "spine_0", Vector3(0, 0.1, 0)],
		["spine_2", "spine_1", Vector3(0, 0.07, 0)],
		["jiggle_primary", "spine_2", Vector3(0, 0.05, 0.12)],
		["spine_3", "spine_2", Vector3(0, 0.12, 0)],
		["neck_0", "spine_3", Vector3(0, 0.12, 0)],
		["head_0", "neck_0", Vector3(0, 0.1, 0)],
		["clavicle_L", "spine_3", Vector3(0.03, 0.08, 0.02)],
		["scapula_L", "clavicle_L", Vector3(0.05, 0, -0.05)],
		["arm_upper_L", "clavicle_L", Vector3(0.17, 0, 0)],
		["arm_lower_L", "arm_upper_L", Vector3(0, -0.28, 0)],
		["hand_L", "arm_lower_L", Vector3(0, -0.26, 0)],
		["clavicle_R", "spine_3", Vector3(-0.03, 0.08, 0.02)],
		["arm_upper_R", "clavicle_R", Vector3(-0.17, 0, 0)],
		["hand_R", "arm_upper_R", Vector3(0, -0.54, 0)],
		["leg_upper_L", "pelvis", Vector3(0.1, -0.05, 0)],
		["leg_lower_L", "leg_upper_L", Vector3(0, -0.43, 0)],
		["ankle_L", "leg_lower_L", Vector3(0, -0.42, 0)],
		["leg_upper_R", "pelvis", Vector3(-0.1, -0.05, 0)],
		["leg_lower_R", "leg_upper_R", Vector3(0, -0.43, 0)],
		["ankle_R", "leg_lower_R", Vector3(0, -0.42, 0)],
	]:
		var index := skeleton.add_bone(bone[0])
		if bone[1] != "":
			skeleton.set_bone_parent(index, skeleton.find_bone(bone[1]))
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, bone[2]))
		var track := clip.add_track(Animation.TYPE_SCALE_3D)
		clip.track_set_path(track, NodePath("Skeleton3D:%s" % bone[0]))
		clip.scale_track_insert_key(track, 0.0, Vector3.ONE)
	skeleton.reset_bone_poses()
	var library := AnimationLibrary.new()
	library.add_animation(&"idle", clip)
	model.animation_player = AnimationPlayer.new()
	model.add_child(model.animation_player)
	model.animation_player.add_animation_library(&"", library)
	return model


func _test_chest_folds() -> void:
	_test_fold(false)
	# A body is folded before it enters the tree, and adopting its meshes
	# can read the rig's global poses first (CharacterEyes aims the eyes at
	# once): the fold must show all the same.
	_test_fold(true)


func _test_fold(read_first: bool) -> void:
	var model := _stand_in()
	var skeleton := model.character_rig
	var shared := model.animation_player.get_animation(&"idle")
	if read_first:
		for bone in skeleton.get_bone_count():
			skeleton.get_bone_global_pose(bone)
	model.fold_bones(PackedStringArray(PlayerView.FOLDED_BONES))
	var when := " (its poses read before the fold)" if read_first else ""

	var folded := func(bone_name: String) -> bool:
		return skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).basis.get_scale().x < 0.01
	var whole := func(bone_name: String) -> bool:
		return skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).basis.get_scale().is_equal_approx(Vector3.ONE)

	var seen_above: Array[String] = []
	var chest_height := skeleton.get_bone_global_rest(skeleton.find_bone("spine_2")).origin.y
	for bone in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone)
		if skeleton.get_bone_global_rest(bone).origin.y > chest_height and not folded.call(bone_name):
			seen_above.append(bone_name)
	_check(
		seen_above.is_empty(),
		"the seen body folds everything resting above the chest" + when
			if seen_above.is_empty() else "the seen body leaves these above the chest%s: %s" % [when, seen_above]
	)
	_check(
		folded.call("spine_3") and folded.call("jiggle_primary") and folded.call("clavicle_L")
			and folded.call("scapula_L") and folded.call("head_0") and folded.call("arm_upper_R") and folded.call("hand_R"),
		"the vest's bones (spine_3, the chest's jiggle bone, the clavicles and scapulas) fold, the head and arms with them" + when
	)
	_check(
		whole.call("pelvis") and whole.call("spine_0") and whole.call("spine_1")
			and whole.call("leg_upper_L") and whole.call("ankle_L") and whole.call("leg_lower_R") and whole.call("ankle_R"),
		"the waist, legs and boots stay whole" + when
	)

	# The clips put every bone's scale back each frame; the folded bone's
	# scale track has to go from this model's copy of the clip, and only
	# from the copy.
	var own := model.animation_player.get_animation(&"idle")
	_check(
		own != shared and own.find_track(NodePath("Skeleton3D:spine_2"), Animation.TYPE_SCALE_3D) == -1
			and own.find_track(NodePath("Skeleton3D:pelvis"), Animation.TYPE_SCALE_3D) >= 0
			and shared.find_track(NodePath("Skeleton3D:spine_2"), Animation.TYPE_SCALE_3D) >= 0,
		"the seen body's clips lose the chest's scale track, and the clips other bodies share keep it" + when
	)
	model.free()


## Looking down leans the body from nothing, level or looking up, to all of
## it straight down.
func _test_look_down() -> void:
	_check(
		PlayerView.look_down(0.0) == 0.0 and PlayerView.look_down(45.0) == 0.0
			and is_equal_approx(PlayerView.look_down(-89.0), 1.0)
			and PlayerView.look_down(-30.0) > 0.0 and PlayerView.look_down(-30.0) < PlayerView.look_down(-60.0),
		"the lean grows as the view looks down, none level or looking up, all of it straight down"
	)
	_check(
		PlayerView.LOOK_DOWN_ARCH > 0.0 and PlayerView.LOOK_DOWN_LEAN > 0.0,
		"looking down both tips the body back and bends its back forward"
	)
	# A view at yaw 0 looks down -Z; at yaw 90 degrees, down -X.
	var ok := true
	for yaw_degrees: float in [0.0, 90.0, 217.0]:
		var yaw := deg_to_rad(yaw_degrees)
		var ahead := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Vector3.FORWARD
		var top := PlayerView.lean(yaw, -89.0) * Vector3.UP
		ok = ok and top.dot(ahead) < -0.3 and top.y > 0.9 and PlayerView.lean(yaw, 10.0).is_equal_approx(Basis.IDENTITY)
		ok = ok and is_equal_approx(PlayerView.view_right(yaw).dot(ahead), 0.0) and PlayerView.view_right(yaw).cross(ahead).y > 0.9
	_check(ok, "looking straight down tips the body's top back, away from where the view faces, whichever way it faces")


## The stand-in faces -Z with +X its right, as a view at yaw 0 does. In the
## tree, where the arch runs: out of it a pose set is not seen in the
## global poses (RigModel.fold_bones).
func _test_arch_bends_forward() -> void:
	var model := _stand_in()
	var skeleton := model.character_rig
	root.add_child(model)
	await process_frame
	var chest := skeleton.find_bone("spine_2")
	var pelvis := skeleton.get_bone_global_pose(skeleton.find_bone("pelvis"))
	var ankle := skeleton.get_bone_global_pose(skeleton.find_bone("ankle_L")).origin
	var chest_before := skeleton.get_bone_global_pose(chest).origin
	LookDownArch.bend(skeleton, Vector3.RIGHT, 60.0)
	var chest_after := skeleton.get_bone_global_pose(chest).origin
	_check(
		chest_after.z < chest_before.z - 0.05 and chest_after.y < chest_before.y,
		"the back bends forward and down over the legs (chest from %s to %s)" % [chest_before, chest_after]
	)
	_check(
		skeleton.get_bone_global_pose(skeleton.find_bone("pelvis")).is_equal_approx(pelvis)
			and skeleton.get_bone_global_pose(skeleton.find_bone("ankle_L")).origin.is_equal_approx(ankle),
		"the pelvis and legs stay where the clip has them"
	)
	var lower := skeleton.get_bone_global_pose(skeleton.find_bone("spine_1")).basis.get_rotation_quaternion()
	_check_near(
		rad_to_deg(Quaternion.IDENTITY.angle_to(lower)), 60.0,
		"the bend is shared by spine_0 and spine_1, all of it by spine_1"
	)
	model.free()


## In the tree, the bend lands after the clips, which key every bone's
## rotation each frame: the modifier runs in the skeleton's update after
## them, and its result is read where it is, in modification_processed.
func _test_arch_over_the_clips() -> void:
	var model := _stand_in()
	var skeleton := model.character_rig
	var clip := model.animation_player.get_animation(&"idle")
	for bone_name in LookDownArch.BONES:
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath("Skeleton3D:%s" % bone_name))
		clip.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
	clip.loop_mode = Animation.LOOP_LINEAR
	var arch := LookDownArch.new()
	skeleton.add_child(arch)
	arch.axis_world = Vector3.RIGHT
	arch.degrees = 60.0
	var seen := []
	arch.modification_processed.connect(func() -> void:
		seen.append(skeleton.get_bone_global_pose(skeleton.find_bone("spine_2")).origin)
	)
	root.add_child(model)
	model.animation_player.play(&"idle")
	for frame in 4:
		await process_frame
	var upright := Vector3(0, 1.09 + 0.08 + 0.1 + 0.07, 0)
	_check(
		not seen.is_empty() and (seen.back() as Vector3).z < -0.05 and (seen.back() as Vector3).y < upright.y,
		"in the tree the bend lands over the playing clip (chest at %s)" % [seen.back() if not seen.is_empty() else "never updated"]
	)
	model.free()
