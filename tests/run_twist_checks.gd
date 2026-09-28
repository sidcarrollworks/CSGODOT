extends "res://tests/check_suite.gd"

## Checks the twist bones' constraints (TwistConstraints, TwistModifier;
## reference/research/twist-constraints.md).
##
##   godot --headless --path . --script tests/run_twist_checks.gd
##
## The maths and the reading run anywhere, on a model description and a
## skeleton made up here (not Valve's text). Where the agents are extracted,
## the real ones are read too, and the knife's arms are checked in the idle.

## A made-up model description, laid out as Source 2 Viewer writes one: a
## list of constraints, each a tilt-twist with its turned bone and the bone
## it follows as children, and its own axes after them. Names are in the
## file's case, not the skeleton's.
const DESCRIPTION := """
	AnimConstraintList =
	{
		_class = "AnimConstraintList"
		children =
		[
			{
				_class = "AnimConstraintTiltTwist"
				children =
				[
					{
						_class = "AnimConstraintSlave"
						parent_bone = "arm_lower_l_twist"
						weight = 0.5
						relative_origin = [ 0.0, 0.0, 0.0 ]
						relative_angles = [ 0.0, 0.0, 0.0 ]
					},
					{
						_class = "AnimConstraintBoneInput"
						parent_bone = "hand_l"
						weight = 1.0
						relative_origin = [ 0.0, 0.0, 0.0 ]
						relative_angles = [ 0.0, 0.0, 0.0 ]
					},
				]
				input_axis = 0
				slave_axis = 0
			},
			{
				_class = "AnimConstraintTiltTwist"
				children =
				[
					{
						_class = "AnimConstraintSlave"
						parent_bone = "arm_lower_l_twist1"
						weight = 1.0
					},
					{
						_class = "AnimConstraintBoneInput"
						parent_bone = "hand_l"
						weight = 1.0
					},
				]
				input_axis = 0
				slave_axis = 0
			},
			{
				_class = "AnimConstraintDotToMorph"
				m_sName = "eyes"
				m_sDriverBone = "head_0"
			},
			{
				_class = "AnimConstraintTiltTwist"
				children =
				[
					{
						_class = "AnimConstraintSlave"
						parent_bone = "counter_l"
						weight = -0.5
					},
					{
						_class = "AnimConstraintBoneInput"
						parent_bone = "hand_l"
						weight = 1.0
					},
				]
				input_axis = 0
				slave_axis = 0
			},
			{
				_class = "AnimConstraintTiltTwist"
				children =
				[
					{
						_class = "AnimConstraintSlave"
						parent_bone = "side_twist"
						weight = 1.0
					},
					{
						_class = "AnimConstraintBoneInput"
						parent_bone = "side"
						weight = 1.0
						relative_origin = [ 0.0, 0.0, 0.0 ]
						relative_angles = [ 0.0, 90.0, 0.0 ]
					},
				]
				input_axis = 1
				slave_axis = 2
			},
		]
	}
"""

const TOLERANCE_DEGREES := 0.05

var _frames := 0
var _seen_rig: Skeleton3D
var _seen_modifier: TwistModifier
var _hidden_rig: Skeleton3D
var _seen_in_update := Quaternion.IDENTITY
var _view_model: ViewModel


func _init() -> void:
	_test_parsing()
	_test_angles()
	_test_twist_angle()
	_test_modifier()
	_test_cost()
	_start_frame_checks()
	_start_view_model()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_finish_frame_checks()
	_finish_view_model()
	_finish("twist")
	return true


func _test_parsing() -> void:
	var constraints := TwistConstraints.parse(DESCRIPTION)
	_check_equal(constraints.size(), 4, "every tilt-twist in the list is read, and the morph constraint is not")
	if constraints.size() != 4:
		return
	_check(
		constraints[0]["bone"] == "arm_lower_l_twist" and constraints[0]["target"] == "hand_l"
			and is_equal_approx(constraints[0]["weight"], 0.5)
			and constraints[1]["bone"] == "arm_lower_l_twist1" and is_equal_approx(constraints[1]["weight"], 1.0),
		"each takes its turned bone, the bone it follows and its weight, in the file's order"
	)
	_check(is_equal_approx(constraints[2]["weight"], -0.5), "a negative weight is read as one")
	_check(
		constraints[0]["input_axis"] == 0 and constraints[0]["slave_axis"] == 0
			and constraints[3]["input_axis"] == 1 and constraints[3]["slave_axis"] == 2,
		"the axes written after the children are the constraint's own"
	)
	_check(
		(constraints[3]["offset"] as Quaternion).is_equal_approx(Quaternion(Vector3(0, 0, 1), PI / 2.0))
			and (constraints[1]["offset"] as Quaternion).is_equal_approx(Quaternion.IDENTITY),
		"the followed bone's relative_angles become its offset, and none is no offset"
	)
	_check(TwistConstraints.parse("_class = \"HitboxCapsule\"").is_empty(), "a description with no constraints gives none")
	_check(TwistConstraints.load_for("res://no/such/model.gltf").is_empty(), "a model with no description gives none")


## Source's angles: pitch about Y (positive down), yaw about Z, roll about X,
## applied yaw first.
func _test_angles() -> void:
	var yaw := TwistConstraints.qangle_quaternion(Vector3(0, 90, 0))
	var pitch := TwistConstraints.qangle_quaternion(Vector3(90, 0, 0))
	var roll := TwistConstraints.qangle_quaternion(Vector3(0, 0, 90))
	var both := TwistConstraints.qangle_quaternion(Vector3(30, 90, 0))
	_check(
		(yaw * Vector3(1, 0, 0)).is_equal_approx(Vector3(0, 1, 0))
			and (pitch * Vector3(1, 0, 0)).is_equal_approx(Vector3(0, 0, -1))
			and (roll * Vector3(0, 1, 0)).is_equal_approx(Vector3(0, 0, 1)),
		"a Source angle turns forward left by its yaw, down by its pitch, and rolls left into up"
	)
	_check(
		(both * Vector3(1, 0, 0)).is_equal_approx(Vector3(0, cos(PI / 6.0), -sin(PI / 6.0))),
		"yaw then pitch: pitched 30 down and yawed 90 looks left and down"
	)


func _test_twist_angle() -> void:
	var twist := Quaternion(Vector3(1, 0, 0), deg_to_rad(80.0))
	var bend := Quaternion(Vector3(0, 1, 0), deg_to_rad(40.0))
	var aslant := Quaternion(Vector3(0, 1, -1).normalized(), deg_to_rad(55.0))
	_check_degrees(rad_to_deg(TwistConstraints.twist_angle(twist, 0)), 80.0, "a turn of 80 about X measures 80 of twist about X")
	_check_degrees(rad_to_deg(TwistConstraints.twist_angle(twist.inverse(), 0)), -80.0, "and the other way, -80")
	_check_degrees(rad_to_deg(TwistConstraints.twist_angle(bend, 0)), 0.0, "a bend about Y measures no twist about X")
	_check_degrees(rad_to_deg(TwistConstraints.twist_angle(aslant, 0)), 0.0, "nor does a bend about an axis between Y and Z")
	_check_degrees(rad_to_deg(TwistConstraints.twist_angle(bend * twist, 0)), 80.0, "a twist then a bend measures the twist")
	_check_degrees(rad_to_deg(TwistConstraints.twist_angle(twist, 1)), 0.0, "a turn about X is no twist about Y")
	_check_degrees(
		rad_to_deg(TwistConstraints.twist_angle(Quaternion(Vector3(0, 0, 1), deg_to_rad(35.0)), 2)), 35.0,
		"about Z, a turn about Z is its twist"
	)
	# Against the textbook split, the twist being the rotation's part along
	# the axis: Source 2 Viewer's tilt is the shortest arc, so the two agree,
	# but for an axis tilted less than 0.81 degrees, which it takes for
	# untilted and reads the twist off the next axis, a few tenths out.
	var worst := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	for i in 200:
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var rotation := Quaternion(axis, rng.randf_range(-2.5, 2.5))
		var along := Quaternion(rotation.x, 0.0, 0.0, rotation.w).normalized()
		var textbook := along.get_angle() * signf(along.x) if absf(along.x) > 1e-6 else 0.0
		worst = maxf(worst, absf(wrapf(TwistConstraints.twist_angle(rotation, 0) - textbook, -PI, PI)))
	_check(rad_to_deg(worst) < 0.3, "over 200 turns it agrees with the swing-twist split (worst %.3f degrees)" % rad_to_deg(worst))


## A forearm made up here: arm_lower_L with the hand at its end, the two
## twist bones and a counter-turned one beside it, and a bone off the side
## whose rest is turned, to see the offset taken out.
func _arm() -> Skeleton3D:
	var rig := Skeleton3D.new()
	for bone_name in ["root", "arm_lower_L", "hand_L", "arm_lower_L_TWIST", "arm_lower_L_TWIST1", "counter_L", "side", "side_TWIST", "finger_L"]:
		rig.add_bone(bone_name)
	rig.set_bone_parent(1, 0)
	for bone in [2, 3, 4, 5, 6]:
		rig.set_bone_parent(bone, 1)
	rig.set_bone_parent(7, 6)
	rig.set_bone_parent(8, 2)
	rig.set_bone_rest(1, Transform3D(Basis(), Vector3(0, 10, 0)))
	rig.set_bone_rest(2, Transform3D(Basis(), Vector3(11.8, 0, 0)))
	rig.set_bone_rest(3, Transform3D(Basis(), Vector3(4, 0, 0)))
	rig.set_bone_rest(4, Transform3D(Basis(), Vector3(8, 0, 0)))
	rig.set_bone_rest(5, Transform3D(Basis(), Vector3(6, 0, 0)))
	rig.set_bone_rest(6, Transform3D(Basis(Quaternion(Vector3(0, 0, 1), PI / 2.0)), Vector3(0, 2, 0)))
	rig.set_bone_rest(7, Transform3D(Basis(), Vector3(3, 0, 0)))
	rig.set_bone_rest(8, Transform3D(Basis(), Vector3(3, 0, 0)))
	rig.reset_bone_poses()
	return rig


func _test_modifier() -> void:
	var rig := _arm()
	var modifier := TwistModifier.new()
	var taken := modifier.setup(rig, TwistConstraints.parse(DESCRIPTION))
	_check_equal(taken, 4, "the constraints find their bones in any case (hand_l is hand_L)")
	modifier.free()
	var missing := TwistConstraints.parse(DESCRIPTION)
	missing[1]["bone"] = "arm_lower_R_TWIST1"
	modifier = TwistModifier.new()
	_check_equal(modifier.setup(rig, missing), 3, "one whose bone is not on the rig is left out")
	modifier.free()
	# The agent's own skeleton hangs the hand under the forearm; a rig that
	# hangs it elsewhere cannot take the hand's constraints.
	var source := _arm()
	var elsewhere := _arm()
	elsewhere.set_bone_parent(elsewhere.find_bone("hand_L"), 0)
	modifier = TwistModifier.new()
	_check_equal(modifier.setup(elsewhere, TwistConstraints.parse(DESCRIPTION), source), 1,
		"with the model's own skeleton given, constraints on a bone the rig parents otherwise are left out")
	modifier.free()
	modifier = TwistModifier.new()
	_check_equal(modifier.setup(rig, TwistConstraints.parse(DESCRIPTION), source), 4, "and where it parents them alike, all are taken")
	modifier.free()
	source.free()
	elsewhere.free()
	modifier = TwistModifier.new()
	modifier.setup(rig, TwistConstraints.parse(DESCRIPTION))

	var hand := rig.find_bone("hand_L")
	var twist := rig.find_bone("arm_lower_L_TWIST")
	var twist1 := rig.find_bone("arm_lower_L_TWIST1")
	var counter := rig.find_bone("counter_L")

	modifier.apply(rig)
	var moved := false
	for bone in rig.get_bone_count():
		moved = moved or not rig.get_bone_pose(bone).is_equal_approx(rig.get_bone_rest(bone))
	_check(not moved, "at rest nothing turns, the bone whose rest is turned included")

	var before := _globals(rig)
	rig.set_bone_pose_rotation(hand, Quaternion(Vector3(1, 0, 0), deg_to_rad(80.0)))
	before[hand] = rig.get_bone_global_pose(hand)
	before[rig.find_bone("finger_L")] = rig.get_bone_global_pose(rig.find_bone("finger_L"))
	modifier.apply(rig)
	_check_degrees(_turn(rig, twist1), 80.0, "the hand turned 80 about the forearm turns TWIST1 80")
	_check_degrees(_turn(rig, twist), 40.0, "and TWIST 40")
	_check_degrees(_turn(rig, counter), -40.0, "and a bone weighted -0.5 turns 40 the other way")
	_check(
		rig.get_bone_pose_position(twist).is_equal_approx(Vector3(4, 0, 0))
			and rig.get_bone_pose_position(twist1).is_equal_approx(Vector3(8, 0, 0)),
		"a twist bone turns where it is, without moving"
	)
	var others_still := true
	var after := _globals(rig)
	for bone in rig.get_bone_count():
		if bone in [twist, twist1, counter]:
			continue
		others_still = others_still and (after[bone] as Transform3D).is_equal_approx(before[bone])
	_check(others_still, "no bone but the twist bones moves: not the hand, the forearm or the fingers")

	rig.set_bone_pose_rotation(hand, Quaternion(Vector3(0, 0, 1), deg_to_rad(50.0)))
	modifier.apply(rig)
	_check(
		absf(_turn(rig, twist)) < 0.01 and absf(_turn(rig, twist1)) < 0.01 and absf(_turn(rig, counter)) < 0.01,
		"a wrist bent 50 without turning turns none of them"
	)
	rig.set_bone_pose_rotation(hand, Quaternion(Vector3(0, 0, 1), deg_to_rad(50.0)) * Quaternion(Vector3(1, 0, 0), deg_to_rad(-60.0)))
	modifier.apply(rig)
	_check_degrees(_turn(rig, twist1), -60.0, "a wrist bent 50 and turned -60 turns TWIST1 -60")

	# Past half a turn the twist carries on, rather than flipping to the
	# other side of the arm.
	var carried := true
	for step in range(-60, -241, -20):
		rig.set_bone_pose_rotation(hand, Quaternion(Vector3(1, 0, 0), deg_to_rad(step)))
		modifier.apply(rig)
		carried = carried and absf(_turn(rig, twist) - step * 0.5) < TOLERANCE_DEGREES
	_check(carried, "turned on to -240 in steps, TWIST follows to -120 without flipping")

	var side := rig.find_bone("side")
	var side_twist := rig.find_bone("side_TWIST")
	rig.set_bone_pose_rotation(hand, Quaternion.IDENTITY)
	rig.set_bone_pose_rotation(side, rig.get_bone_rest(side).basis.get_rotation_quaternion() * Quaternion(Vector3(0, 1, 0), deg_to_rad(25.0)))
	modifier.apply(rig)
	_check_degrees(
		_turn(rig, side_twist, 2), 25.0,
		"with its offset taken out, a bone turned 25 about its own Y turns its twist bone 25 about Z"
	)
	rig.free()
	modifier.free()


## What the modifier costs: the 13 constraints of an agent on one body,
## measured here for a record, not checked (the machine sets it).
func _test_cost() -> void:
	var rig := _arm()
	var constraints: Array[Dictionary] = []
	var parsed := TwistConstraints.parse(DESCRIPTION)
	for i in 13:
		constraints.append(parsed[i % 3])
	var modifier := TwistModifier.new()
	modifier.setup(rig, constraints)
	rig.set_bone_pose_rotation(rig.find_bone("hand_L"), Quaternion(Vector3(1, 0.2, 0).normalized(), 1.2))
	var runs := 2000
	var started := Time.get_ticks_usec()
	for i in runs:
		modifier.apply(rig)
	print("13 constraints on one body: %.1f us a frame" % (float(Time.get_ticks_usec() - started) / runs))
	rig.free()
	modifier.free()


## Through the engine's own update: the modifier runs in a skeleton's
## deferred update, what the rig's skeleton_updated reads (SkinnedHitboxes,
## the pins) sees its result, and a body only on the layer nobody draws is
## left alone.
func _start_frame_checks() -> void:
	_seen_rig = _arm()
	_seen_rig.set_bone_pose_rotation(_seen_rig.find_bone("hand_L"), Quaternion(Vector3(1, 0, 0), deg_to_rad(70.0)))
	var mesh := MeshInstance3D.new()
	_seen_rig.add_child(mesh)
	root.add_child(_seen_rig)
	_seen_modifier = TwistModifier.new()
	_seen_modifier.setup(_seen_rig, TwistConstraints.parse(DESCRIPTION))
	_seen_rig.add_child(_seen_modifier)
	_seen_rig.skeleton_updated.connect(func() -> void:
		_seen_in_update = _seen_rig.get_bone_pose_rotation(_seen_rig.find_bone("arm_lower_L_TWIST1")))

	_hidden_rig = _arm()
	_hidden_rig.set_bone_pose_rotation(_hidden_rig.find_bone("hand_L"), Quaternion(Vector3(1, 0, 0), deg_to_rad(70.0)))
	var hidden_mesh := MeshInstance3D.new()
	hidden_mesh.layers = PlayerSim.UNSEEN_LAYER
	_hidden_rig.add_child(hidden_mesh)
	root.add_child(_hidden_rig)
	var hidden_modifier := TwistModifier.new()
	hidden_modifier.setup(_hidden_rig, TwistConstraints.parse(DESCRIPTION))
	_hidden_rig.add_child(hidden_modifier)
	_check(not hidden_modifier.is_seen() and _seen_modifier.is_seen(), "a body only on the layer nobody draws is not seen; one on the world's is")


func _finish_frame_checks() -> void:
	_check_degrees(
		rad_to_deg(_seen_in_update.get_angle()), 70.0,
		"in the frame's skeleton update, what skeleton_updated reads has TWIST1 turned with the hand"
	)
	_check(
		_seen_rig.get_bone_pose_rotation(_seen_rig.find_bone("arm_lower_L_TWIST1")).is_equal_approx(Quaternion.IDENTITY),
		"and outside it the pose is the clips' again: a modifier's result is not left for the tick to read"
	)
	_check(
		_hidden_rig.get_bone_pose_rotation(_hidden_rig.find_bone("arm_lower_L_TWIST1")).is_equal_approx(Quaternion.IDENTITY),
		"a body nobody sees is not twisted"
	)
	_seen_rig.queue_free()
	_hidden_rig.queue_free()


## With the agents extracted: the T agent's own constraints, and the T
## knife's arms twisted by them.
func _start_view_model() -> void:
	var agent: String = ViewModel.AGENTS["T"]
	var description := agent.get_basename() + ".vmdl"
	if not FileAccess.file_exists(description):
		print("the agents are not extracted; skipping the real constraints (scripts/extract_assets.sh characters)")
		return
	for team: String in ViewModel.AGENTS:
		var constraints := TwistConstraints.load_for(ViewModel.AGENTS[team])
		var names := PackedStringArray()
		for constraint in constraints:
			names.append("%s %.1f of %s" % [constraint["bone"], constraint["weight"], constraint["target"]])
		print("%s: %s" % [team, ", ".join(names)])
		_check_equal(constraints.size(), 13, "the %s agent's description has CS2's 13 tilt-twist constraints" % team)
		var bones := {}
		for constraint in constraints:
			bones[String(constraint["bone"]).to_lower()] = true
		var on_twist := PackedStringArray()
		for capsule in HitboxSet.load_for(ViewModel.AGENTS[team]):
			if bones.has(String(capsule["bone"]).to_lower()):
				on_twist.append(capsule["bone"])
		_check(on_twist.is_empty(), "no %s hitbox is on a twist bone (%s)" % [team, ", ".join(on_twist)])
	var knife := "res://assets/weapons/weapons/models/knife/knife_default_t/weapon_knife_default_t.gltf"
	if not ResourceLoader.exists(knife):
		print("the knife is not extracted; skipping the knife's arms (scripts/extract_assets.sh equipment)")
		return
	_view_model = ViewModel.new()
	root.add_child(_view_model)
	if not _view_model.setup("T", knife, "knife/knife_default_t"):
		_check(false, "the T knife's view model builds")
		_view_model.queue_free()
		_view_model = null


func _finish_view_model() -> void:
	if _view_model == null:
		return
	var rig := _view_model.character_rig
	var modifier := rig.get_node_or_null("Twist") as TwistModifier
	_check(modifier != null and modifier.count() >= 4, "the knife's arms take the agent's arm constraints (%d)" % (modifier.count() if modifier != null else 0))
	if modifier != null:
		# At the bind pose each twist bone lands on its own rest: CS2's rests
		# carry the twist the bind pose measures. A constraint on a bone the
		# rig parents otherwise than the agent (the view model's upper arms)
		# was left out, or it would be held about 159 degrees wrung.
		var worst := 0.0
		var worst_bone := ""
		for bone in rig.get_bone_count():
			rig.set_bone_pose_rotation(bone, rig.get_bone_rest(bone).basis.get_rotation_quaternion())
		modifier.apply(rig)
		for i in modifier._bones.size():
			var rest := rig.get_bone_rest(modifier._bones[i]).basis.get_rotation_quaternion()
			var off := rad_to_deg((rest.inverse() * rig.get_bone_pose_rotation(modifier._bones[i])).get_angle())
			if off > worst:
				worst = off
				worst_bone = rig.get_bone_name(modifier._bones[i])
		_check(worst < 1.0, "at the bind pose every twist bone lands on its rest (worst %.2f degrees, %s)" % [worst, worst_bone])
		var upper := false
		for i in modifier._bones.size():
			upper = upper or rig.get_bone_name(modifier._bones[i]).to_lower().begins_with("arm_upper")
		_check(not upper, "the view model's upper arms, parented unlike the agent's, take no constraint")
		_view_model.play(&"idle")
		_view_model.animation_player.advance(0.5)
		var hand := rig.find_bone("hand_R")
		var twist1 := rig.find_bone("arm_lower_R_TWIST1")
		var index := modifier._bones.find(twist1)
		if hand >= 0 and index >= 0:
			var measured := rad_to_deg(TwistConstraints.twist_angle(modifier._inverse_offsets[index] * rig.get_bone_pose_rotation(hand), 0))
			modifier.apply(rig)
			var turn := rad_to_deg(rig.get_bone_pose_rotation(twist1).get_angle())
			_check(
				absf(absf(measured) - turn) < 1.0,
				"in the knife's idle arm_lower_R_TWIST1 turns as far as hand_R twists (%.1f and %.1f degrees)" % [measured, turn]
			)
	_view_model.queue_free()


func _globals(rig: Skeleton3D) -> Dictionary:
	var poses := {}
	for bone in rig.get_bone_count():
		poses[bone] = rig.get_bone_global_pose(bone)
	return poses


## How far a bone is turned from its rest about one of its own axes (0 X,
## 2 Z), in degrees, signed.
func _turn(rig: Skeleton3D, bone: int, axis: int = 0) -> float:
	var from_rest := rig.get_bone_rest(bone).basis.get_rotation_quaternion().inverse() * rig.get_bone_pose_rotation(bone)
	return rad_to_deg(TwistConstraints.twist_angle(from_rest, axis))


func _check_degrees(degrees: float, expected: float, description: String) -> void:
	var close := absf(degrees - expected) <= TOLERANCE_DEGREES
	_check(close, description if close else "%s (expected %.3f, got %.3f)" % [description, expected, degrees])
