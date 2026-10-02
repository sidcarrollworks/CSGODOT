extends "res://tests/check_suite.gd"

## Head/body reactions must add over a continuing pose, restart smoothly,
## expire while not shown, and restore it on death/respawn. The synthetic
## rig checks those contracts without CS2 assets; local clips are checked
## as well when extracted.


func _initialize() -> void:
	_test_selection()
	call_deferred(&"_run")


func _test_selection() -> void:
	for variation: String in ["rifle", "pistol", "knife"]:
		var suffix := "" if variation == "rifle" else "_" + variation
		for zone: StringName in [&"chest", &"head"]:
			for direction: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var end := "" if direction.x > 0 else ("_rear" if direction.x < 0 else ("_left" if direction.y > 0 else "_right"))
				_check_equal(PlayerFlinch.clip_for(zone, &"", direction, variation), StringName("flinch_" + String(zone) + end + suffix), "the authored %s %s reaction faces %s" % [variation, zone, direction])
		for zone: StringName in [&"arm", &"leg"]:
			for side: StringName in [&"left", &"right"]:
				_check_equal(PlayerFlinch.clip_for(zone, side, Vector2(-1, 0), variation), StringName("flinch_" + String(zone) + "_" + String(side) + suffix), "the %s %s reaction uses the capsule's side" % [zone, side])
		_check_equal(PlayerFlinch.clip_for(&"stomach", &"", Vector2(-1, 1), variation), StringName("flinch_stomach_rear" + suffix), "stomach has an authored rear reaction")
		_check_equal(PlayerFlinch.clip_for(&"stomach", &"", Vector2(0, -1), variation), StringName("flinch_stomach" + suffix), "stomach uses front for side hits because the graph has no side clip")
	_check_equal(PlayerFlinch.clip_for(&"head", &"", Vector2.ZERO, "rifle"), &"flinch_head", "a directionless head hit has a valid front reaction")
	_check_equal(PlayerFlinch.clip_for(&"unknown", &"", Vector2.ONE, "rifle"), &"", "an unknown hit zone does not guess a reaction")
	_check(PlayerModel.body_speeds(Vector3.FORWARD, 0.0) == Vector2(1, 0)
		and PlayerModel.body_speeds(Vector3.BACK, 180.0).distance_to(Vector2(1, 0)) < 0.00001,
		"source direction is relative to the victim's facing, including a turned victim")


func _run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var rig := Skeleton3D.new()
	rig.name = "Rig"
	fixture.add_child(rig)
	for bone: String in ["pelvis", "head"]:
		rig.add_bone(bone)
		rig.set_bone_rest(rig.get_bone_count() - 1, Transform3D(Basis.IDENTITY, Vector3(0, 10, 0)))
	var library := AnimationLibrary.new()
	var base := Animation.new()
	base.length = 1.0
	base.loop_mode = Animation.LOOP_LINEAR
	for bone: String in ["pelvis", "head"]:
		var track := base.add_track(Animation.TYPE_POSITION_3D)
		base.track_set_path(track, NodePath("Rig:" + bone))
		base.position_track_insert_key(track, 0.0, Vector3(2, 10, 0))
		base.position_track_insert_key(track, 1.0, Vector3(2, 10, 0))
	library.add_animation(&"base", base)
	library.add_animation(&"front", PlayerModel.rest_relative(_reaction("pelvis", 4.0), rig))
	library.add_animation(&"back", PlayerModel.rest_relative(_reaction("pelvis", -4.0), rig))
	library.add_animation(&"head", PlayerModel.rest_relative(_reaction("head", 6.0), rig))
	var player := AnimationPlayer.new()
	fixture.add_child(player)
	player.add_animation_library(&"", library)
	player.active = false
	var graph := AnimationNodeBlendTree.new()
	var base_node := AnimationNodeAnimation.new()
	base_node.animation = &"base"
	graph.add_node(&"base", base_node)
	var body := PlayerFlinch.new()
	var head := PlayerFlinch.new(true)
	var over := body.attach(graph, &"base", &"front")
	over = head.attach(graph, over, &"head")
	graph.connect_node(&"output", 0, over)
	var tree := AnimationTree.new()
	fixture.add_child(tree)
	tree.add_animation_library(&"", library)
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	body.initialize(tree)
	head.initialize(tree)
	for pass_index in 3:
		tree.advance(0.0)
	var untouched := rig.get_bone_pose_position(0)
	_check(untouched.is_equal_approx(Vector3(2, 10, 0)), "an inactive flinch preserves the base pose with a nonzero rest")
	body.start(&"front", 0.4, 1_000_000)
	body.apply(tree, 1_100_000)
	tree.advance(0.1)
	_check(rig.get_bone_pose_position(0).is_equal_approx(Vector3(2, 10, 4)), "the authored body shift adds at full strength over the base, without adding the rest twice")
	_check(rig.get_bone_pose_position(1).is_equal_approx(Vector3(2, 10, 0)), "a body clip with no head track leaves the head pose alone")
	body.start(&"back", 0.4, 1_150_000)
	body.apply(tree, 1_150_000)
	tree.advance(0.05)
	_check_near(float(tree.get(&"parameters/body_flinch_seek_0/seek_request")), -1.0, "the mixer consumes a seek request")
	_check_near(body.restart_share(1_150_000), 0.0, "a second hit starts with the previous reaction")
	_check_near(body.age(0, 1_150_000), 0.15, "restarting does not rewind the old clip")
	_check_near(body.restart_share(1_200_000), 0.5, "the graph's 0.1-second restart cross-fade is half complete after 0.05 seconds")
	body.apply(tree, 1_200_000)
	head.start(&"head", 0.4, 1_180_000)
	head.apply(tree, 1_200_000)
	tree.advance(0.05)
	_check(absf(rig.get_bone_pose_position(0).z) < 1.0, "a new opposite hit cross-fades into the ongoing reaction instead of doubling both")
	_check(rig.get_bone_pose_position(1).z > 1.0, "a head reaction adds independently while the body flinch is active")
	_check_near(body.age(1, 1_200_000), 0.05, "starting a head reaction leaves the body's start time untouched")
	_check_near(float(tree.get(&"parameters/base/current_position")), 0.2, "the base animation continues while both reaction layers are sampled")
	body.apply(tree, 2_000_000)
	head.apply(tree, 2_000_000)
	tree.advance(0.0)
	_check(rig.get_bone_pose_position(0).is_equal_approx(untouched) and rig.get_bone_pose_position(1).is_equal_approx(untouched), "a deferred unseen body returns to its base pose without playing a stale hit")
	head.start(&"head", 0.4, 3_000_000)
	_check_near(head.weight(3_450_000), 0.5, "HeadFlinch fades to Off over the graph's 0.1 seconds")
	body.start(&"front", 0.4, 3_000_000)
	_check_near(body.weight(3_450_000), 0.0, "BodyFlinch leaves at the authored end instead of holding its last pose")
	body.clear(tree)
	head.clear(tree)
	_check_near(body.weight(3_100_000), 0.0, "death/respawn clears pending body reactions")
	_check_near(head.weight(3_100_000), 0.0, "death/respawn clears pending head reactions")
	fixture.free()
	_test_local_clips()
	_finish("flinch")


func _reaction(bone: String, amount: float) -> Animation:
	var animation := Animation.new()
	animation.length = 0.4
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath("Rig:" + bone))
	animation.position_track_insert_key(track, 0.0, Vector3.ZERO)
	animation.position_track_insert_key(track, 0.1, Vector3(0, 0, amount))
	animation.position_track_insert_key(track, 0.4, Vector3.ZERO)
	return animation


func _test_local_clips() -> void:
	if not ResourceLoader.exists(PlayerModel.SHARED_DIR.path_join("flinch_chest.gltf")):
		print("flinch: local authored clips not extracted; synthetic pose checks passed")
		return
	var model := PlayerModel.new()
	root.add_child(model)
	if not model.setup("T", "", "", true):
		_check(false, "the extracted player rig loads for local flinch checks")
		model.free()
		return
	model.step_off_tick_frames()
	model.pose_now()
	var first := model.animation_player.get_animation(&"flinch_chest")
	_check(first != null and first.length > 0.3 and first.length < 0.7 and first.loop_mode == Animation.LOOP_NONE, "current CS2's chest flinch has its authored duration and never loops")
	var count := 0
	for clip: StringName in model.animation_player.get_animation_list():
		if String(clip).begins_with("flinch_"):
			count += 1
	_check_equal(count, 42, "all fourteen directional/side reactions load for rifle, pistol and knife")
	# Check an actual authored pose, not just the additive parameter. The
	# floor/hand modifiers are off here so the comparison is to the mixer.
	model.foot_plant.active = false
	model.hand_grip.active = false
	model.animation_tree.advance(0.0)
	var plain := PackedVector3Array()
	for bone in model.character_rig.get_bone_count():
		plain.append(model.character_rig.get_bone_pose_position(bone))
	model.flinch(&"chest", &"", Vector3.BACK, 0)
	model._apply_flinches(100_000)
	model.animation_tree.advance(0.0)
	var shifted := 0.0
	for track in first.get_track_count():
		if first.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var bone := model.character_rig.find_bone(String(first.track_get_path(track).get_subname(0)))
		if bone < 0:
			continue
		var delta := first.position_track_interpolate(track, 0.1) - model.character_rig.get_bone_rest(bone).origin
		var actual := model.character_rig.get_bone_pose_position(bone) - plain[bone]
		if delta.length() > shifted:
			shifted = delta.length()
		_check(actual.distance_to(delta) < 0.00001, "authored %s translation adds its difference, including constant tracks (%s expected, %s actual)" % [model.character_rig.get_bone_name(bone), delta, actual])
	_check(shifted > 0.001 and shifted < 0.2, "the current CS2 flinch shifts the body by its authored displacement instead of moving the player node")
	model.play(model.idle)
	model.update_motion(Vector3(0, 0, -100), 0, 0.0, true)
	model.play(&"reload")
	model.flinch(&"chest", &"", Vector3.BACK)
	_check_equal(model.state(), &"move", "flinching leaves locomotion running")
	_check(model.animation_tree.get(&"parameters/body_flinch/add_amount") == 1.0, "the event-facing API starts the authored body reaction")
	model.flinch(&"head", &"", Vector3.BACK)
	_check(model.animation_tree.get(&"parameters/head_flinch/add_amount") == 1.0
		and model.animation_tree.get(&"parameters/body_flinch/add_amount") == 1.0, "the event-facing API can run body and head reactions together")
	model.play(&"death_chest_a", 0.15)
	_check(model.animation_tree.get(&"parameters/body_flinch/add_amount") == 0.0
		and model.animation_tree.get(&"parameters/head_flinch/add_amount") == 0.0, "a death aborts both flinches before the ragdoll takes the pose")
	model.flinch(&"head", &"", Vector3.BACK)
	_check(model.animation_tree.get(&"parameters/head_flinch/add_amount") == 0.0, "a dead model ignores late hit reactions")
	model.play(model.idle)
	model.flinch(&"chest", &"", Vector3.BACK)
	model.set_animating(false)
	_check(model.animation_tree.get(&"parameters/body_flinch/add_amount") == 0.0, "handing a model to ragdoll physics clears a pending flinch")
	model.free()
