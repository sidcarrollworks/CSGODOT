extends "res://tests/check_suite.gd"

## Checks the hands going back on the gun (HandGrip) without the extracted
## models: a stand-in upper body shaped like the agents', scaled from metres
## to units as the models are, its gun bone wpn off the hips and not under
## the arms, and each hand's target (wpnHand_L, wpnHand_R) under it where
## the hand is. Lowering the pelvis, as FootPlant does on a slope, takes the
## hands off the gun; the fit puts them back. Whether it looks right on the
## agents is Sid's to see.
##
##   godot --headless --path . --script tests/run_hand_grip_checks.gd

const UNIT_SCALE := 39.3701
## How far the pelvis is lowered, in units: FootPlant's most is 12.
const DROP := 4.0


func _initialize() -> void:
	_test_share()
	await _test_back_on_gun()
	await _test_let_go()
	await _test_far_hand()
	_test_body_grips()
	_finish("hand-grip")


## An upper body as the agents' stand (metres), facing -Z, the gun held
## across the chest: its wpn bone under root_motion, as CS2's UpperBody
## mask names it apart from the spine, and the hands' targets on the hands.
func _stand_in() -> Node3D:
	var model := Node3D.new()
	model.scale = Vector3.ONE * UNIT_SCALE
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	model.add_child(skeleton)
	# Every bone turns nothing, so where one stands is its offsets summed.
	var at := {}
	for bone: Array in [
		["root_motion", "", Vector3.ZERO],
		["pelvis", "root_motion", Vector3(0, 1.0, 0)],
		["spine_0", "pelvis", Vector3(0, 0.3, 0)],
		["clavicle_R", "spine_0", Vector3(-0.05, 0.15, 0)],
		["arm_upper_R", "clavicle_R", Vector3(-0.15, 0, 0)],
		["arm_lower_R", "arm_upper_R", Vector3(0, -0.28, 0.02)],
		["hand_R", "arm_lower_R", Vector3(0.1, 0.05, -0.2)],
		["clavicle_L", "spine_0", Vector3(0.05, 0.15, 0)],
		["arm_upper_L", "clavicle_L", Vector3(0.15, 0, 0)],
		["arm_lower_L", "arm_upper_L", Vector3(0, -0.25, -0.1)],
		["hand_L", "arm_lower_L", Vector3(-0.1, 0.1, -0.2)],
	]:
		var index := skeleton.add_bone(bone[0])
		if bone[1] != "":
			skeleton.set_bone_parent(index, skeleton.find_bone(bone[1]))
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, bone[2]))
		at[bone[0]] = (at.get(bone[1], Vector3.ZERO) as Vector3) + (bone[2] as Vector3)
	# The gun and its grips, off the root, where the hands are at rest.
	var wpn := skeleton.add_bone("wpn")
	skeleton.set_bone_parent(wpn, skeleton.find_bone("root_motion"))
	var wpn_at: Vector3 = at["hand_R"]
	skeleton.set_bone_rest(wpn, Transform3D(Basis.IDENTITY, wpn_at))
	for side in ["L", "R"]:
		var target := skeleton.add_bone("wpnHand_" + side)
		skeleton.set_bone_parent(target, wpn)
		skeleton.set_bone_rest(target, Transform3D(Basis.IDENTITY, (at["hand_" + side] as Vector3) - wpn_at))
	skeleton.reset_bone_poses()
	return model


## The stand-in with the fit under its skeleton and the pelvis lowered by
## drop units: returns the model, the fit and what each skeleton update
## showed (bone -> world point).
func _stand(holding: bool, drop: float = DROP) -> Dictionary:
	var model := _stand_in()
	var skeleton := model.get_node("Skeleton3D") as Skeleton3D
	var grip := HandGrip.new()
	grip.holding = holding
	skeleton.add_child(grip)
	var seen := {}
	skeleton.skeleton_updated.connect(func() -> void:
		for bone_name in ["hand_L", "hand_R", "arm_lower_L", "arm_upper_L", "wpnHand_L", "wpnHand_R"]:
			seen[bone_name] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin
		seen["hand_R_turn"] = skeleton.get_bone_global_pose(skeleton.find_bone("hand_R")).basis.get_rotation_quaternion()
	)
	root.add_child(model)
	var pelvis := skeleton.find_bone("pelvis")
	skeleton.set_bone_pose_position(pelvis, skeleton.get_bone_pose_position(pelvis) + Vector3.DOWN * drop / UNIT_SCALE)
	return {"model": model, "skeleton": skeleton, "grip": grip, "seen": seen}


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _test_share() -> void:
	_check(
		is_equal_approx(HandGrip.share(0.0), 1.0) and is_equal_approx(HandGrip.share(HandGrip.FULL_GAP), 1.0)
			and is_equal_approx(HandGrip.share(HandGrip.MOST_GAP), 0.0) and is_equal_approx(HandGrip.share(100.0), 0.0)
			and HandGrip.share((HandGrip.FULL_GAP + HandGrip.MOST_GAP) / 2.0) > 0.4 and HandGrip.share((HandGrip.FULL_GAP + HandGrip.MOST_GAP) / 2.0) < 0.6,
		"a hand near its target goes all the way, one far off stays, and between it fades"
	)


## With the pelvis lowered the hands drop off the gun; holding, both come
## back onto their targets, each arm keeping its lengths and the hand its turn.
func _test_back_on_gun() -> void:
	var stood := _stand(true)
	var skeleton := stood["skeleton"] as Skeleton3D
	var seen := stood["seen"] as Dictionary
	var upper := skeleton.get_bone_rest(skeleton.find_bone("arm_lower_L")).origin.length() * UNIT_SCALE
	var lower := skeleton.get_bone_rest(skeleton.find_bone("hand_L")).origin.length() * UNIT_SCALE
	var turn_before := skeleton.get_bone_global_pose(skeleton.find_bone("hand_R")).basis.get_rotation_quaternion()
	await _frames(40)
	var grip := stood["grip"] as HandGrip
	var ok := not seen.is_empty()
	var report := []
	for side in ["L", "R"]:
		var off := (seen.get("hand_" + side, Vector3.INF) as Vector3).distance_to(seen.get("wpnHand_" + side, Vector3.ZERO))
		report.append("%s %.3f" % [side, off])
		ok = ok and off < 0.05
	_check(
		ok and absf(grip.gaps[0] - DROP) < 0.05 and absf(grip.gaps[1] - DROP) < 0.05,
		"with the pelvis %.0f units down the hands were %.0f off the gun (%.2f, %.2f) and are back on its grips (%s)" % [DROP, DROP, grip.gaps[0], grip.gaps[1], ", ".join(report)]
	)
	var shoulder := seen.get("arm_upper_L", Vector3.ZERO) as Vector3
	var elbow := seen.get("arm_lower_L", Vector3.ZERO) as Vector3
	var hand := seen.get("hand_L", Vector3.ZERO) as Vector3
	_check(
		absf(shoulder.distance_to(elbow) - upper) < 0.01 and absf(elbow.distance_to(hand) - lower) < 0.01,
		"the left arm keeps its lengths (%.2f of %.2f, %.2f of %.2f)" % [shoulder.distance_to(elbow), upper, elbow.distance_to(hand), lower]
	)
	_check(
		(seen.get("hand_R_turn", Quaternion()) as Quaternion).angle_to(turn_before) < 0.001,
		"and the right hand keeps the turn the clip gave it"
	)
	(stood["model"] as Node).free()


## Not holding (a draw or a reload has the hands, or dead) the hands stay
## where the clip has them.
func _test_let_go() -> void:
	var stood := _stand(false)
	var seen := stood["seen"] as Dictionary
	await _frames(20)
	var off := (seen.get("hand_L", Vector3.INF) as Vector3).distance_to(seen.get("wpnHand_L", Vector3.ZERO))
	_check(not seen.is_empty() and absf(off - DROP) < 0.05, "not holding, the hands stay where the clip has them (%.2f off)" % off)
	(stood["model"] as Node).free()


## A hand further than MOST_GAP from its target is one the clip took off
## the gun, and stays.
func _test_far_hand() -> void:
	var stood := _stand(true, HandGrip.MOST_GAP + 2.0)
	var seen := stood["seen"] as Dictionary
	await _frames(20)
	var off := (seen.get("hand_L", Vector3.INF) as Vector3).distance_to(seen.get("wpnHand_L", Vector3.ZERO))
	_check(not seen.is_empty() and absf(off - HandGrip.MOST_GAP - 2.0) < 0.05, "a hand %.0f units off the gun is left where the clip has it (%.2f)" % [HandGrip.MOST_GAP + 2.0, off])
	(stood["model"] as Node).free()


## A body grips the gun only with one shown in hand and alive.
func _test_body_grips() -> void:
	var model := PlayerModel.new()
	_check(not model.grips_gun(), "a body with nothing in hand grips nothing")
	model.held_weapon = Node3D.new()
	_check(model.grips_gun(), "with a gun shown in hand it grips it")
	model.held_weapon.visible = false
	_check(not model.grips_gun(), "and not once the gun is put away")
	model.held_weapon.free()
	model.free()
