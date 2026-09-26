extends "res://tests/check_suite.gd"

## Checks what of your own body the camera can see (PlayerView.FOLDED_BONES)
## without the extracted models: the bones it folds, on a stand-in skeleton
## shaped like the agents', through RigModel.fold_bones as the seen body
## folds them. The same on the agent itself is in run_model_checks.gd
## (needs the assets); what is left in view is Sid's to look at
## (reference/playtest-2026-09-25.md, issue 22).
##
##   godot --headless --path . --script tests/run_body_view_checks.gd


func _init() -> void:
	_test_chest_folds()
	_finish("body-view")


## A rig with the agents' bone names and parents, standing about as tall
## (metres, as Source 2 Viewer exports them), with a jiggle bone on the
## chest as the vests have, and a clip that keys every bone's scale, as
## every clip does.
func _stand_in() -> RigModel:
	var model := RigModel.new()
	var skeleton := Skeleton3D.new()
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
