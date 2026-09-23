extends SceneTree

## Checks the test range's dummy: that it stands in its lane wearing drawn
## hitboxes, that a round into it says what it did, that armour and the
## helmet change that the way CS does, and that a killed dummy comes back
## whole where it stood. And the shooter: that it holds its fire until
## told, then shoots you, and what that does to you shows.
##
##   godot --headless --path . --script tests/run_range_checks.gd
##
## Without the extracted character the dummy wears the four standard boxes
## instead of the game's capsules; everything here holds for either.

const RANGE_SCENE := "res://maps/test_range/test_range.tscn"

var _failures: int = 0
var _checks: int = 0
var _range: Node3D
var _clock_usec: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_range = (load(RANGE_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_range)
	for i in 8:
		await physics_frame

	var dummy: Bot = _range.dummy
	_check(dummy != null and dummy.weapon == null and dummy.route.is_empty(), "the dummy is a bot with nothing to shoot with and nowhere to go")
	if dummy == null:
		_report()
		return
	dummy.respawn_seconds = 0.05
	var hitboxes := dummy.hit_target.hitboxes()
	_check(hitboxes.size() == 4 or hitboxes.size() == 19, "it wears hitboxes (%d)" % hitboxes.size())
	_check(
		hitboxes.all(func(hitbox: Hitbox) -> bool: return hitbox.is_drawn()),
		"every one of them is drawn"
	)
	_check(
		dummy.global_position.distance_to(_range.dummy_position()) < 1.0
			and absf(dummy.global_position.z + 512.0) < 1.0,
		"it stands down its lane, 512 units from the firing spot (%s)" % dummy.global_position
	)
	_check(
		dummy.hit_target.armor == 100.0 and dummy.hit_target.helmet,
		"it wears kevlar and a helmet, as in a rifle round"
	)
	var drawn := _find_drawn(hitboxes[0])
	_check(drawn != null and drawn.mesh != null, "a drawn hitbox has a mesh the shape of its collision")

	var data: WeaponData = _range.player.weapon.data
	# A round to the chest: through the kevlar, for the armour's share.
	var chest := _shoot(_zone_point(dummy, &"chest"))
	_check(chest.hitbox != null and chest.zone == &"chest", "a round at the chest hits the chest (%s)" % chest.zone)
	var raw := data.damage_at(chest.distance) * data.hitbox_multiplier(&"chest")
	_check(
		is_equal_approx(chest.damage, raw * data.armor_penetration)
			and is_equal_approx(dummy.hit_target.health, 100.0 - chest.damage),
		"through kevlar it does %.0f of %.0f, and the dummy has %.0f left" % [chest.damage, raw, dummy.hit_target.health]
	)
	var lines: PackedStringArray = _range.log_lines()
	_check(
		lines.size() == 1 and "chest" in lines[0] and ("before armour" in lines[0]),
		"the log says where it landed and what it carried before the armour (%s)" % (lines[0] if lines.size() > 0 else "")
	)
	await process_frame
	_check(
		_range.get_node("DamageNumbers").get_child_count() == 1
			and (_range.get_node("DamageNumbers").get_child(0) as Label3D).text == "%d" % roundi(chest.damage),
		"the damage rises from where the round landed"
	)

	# A round to the head through the helmet kills.
	var head := _shoot(_zone_point(dummy, &"head"))
	_check(
		head.zone == &"head" and head.damage > 100.0 - chest.damage and not dummy.alive,
		"a round to the head through the helmet finishes it (%.0f)" % head.damage
	)
	lines = _range.log_lines()
	_check(
		lines.size() >= 3 and lines[0].begins_with("KILLED  100 damage in 2 hits") and "1 to the head" in lines[0],
		"the kill is summed up: all its health in two hits, one to the head (%s)" % (lines[0] if lines.size() > 0 else "")
	)
	_check(
		hitboxes.all(func(hitbox: Hitbox) -> bool: return hitbox.collision_layer == 0),
		"down, it cannot be shot"
	)

	for i in 30:
		await physics_frame
		if dummy.alive:
			break
	await physics_frame
	_check(
		dummy.alive and is_equal_approx(dummy.hit_target.health, 100.0) and dummy.hit_target.armor == 100.0
			and dummy.global_position.distance_to(_range.dummy_position()) < 1.0
			and hitboxes.all(func(hitbox: Hitbox) -> bool: return hitbox.collision_layer == Hitbox.LAYER),
		"it stands up again where it was, whole, and can be shot"
	)

	# No helmet: the head takes the whole round, the chest still does not.
	_range.next_armour()
	_check(dummy.hit_target.armor == 100.0 and not dummy.hit_target.helmet, "K takes the helmet off")
	var bare_head := _shoot(_zone_point(dummy, &"head"))
	var bare_raw := data.damage_at(bare_head.distance) * data.hitbox_multiplier(&"head")
	_check(is_equal_approx(bare_head.damage, bare_raw), "without a helmet the head takes the whole round (%.0f)" % bare_head.damage)
	await _wait_for_respawn(dummy)

	# No armour at all: the chest takes it all.
	_range.next_armour()
	var bare_chest := _shoot(_zone_point(dummy, &"chest"))
	_check(
		dummy.hit_target.armor == 0.0
			and is_equal_approx(bare_chest.damage, data.damage_at(bare_chest.distance) * data.hitbox_multiplier(&"chest")),
		"with no armour the chest takes the whole round (%.0f)" % bare_chest.damage
	)
	_range.next_armour()
	_check(dummy.hit_target.armor == 100.0 and dummy.hit_target.helmet, "and K round again puts both back on")

	_range.next_distance()
	await physics_frame
	_check(absf(dummy.global_position.z + 1024.0) < 1.0, "N walks it back to 1024 units")

	_range.toggle_hitboxes()
	_check(hitboxes.all(func(hitbox: Hitbox) -> bool: return not hitbox.is_drawn()), "H hides the hitboxes")
	_range.toggle_hitboxes()
	_check(hitboxes.all(func(hitbox: Hitbox) -> bool: return hitbox.is_drawn()), "and H again draws them")

	# Never dies: a whole spray registers, a kill is still counted.
	_range.toggle_immortal()
	var spray_hits := 0
	for i in 8:
		if _shoot(_zone_point(dummy, &"head")).hitbox != null:
			spray_hits += 1
	lines = _range.log_lines()
	_check(
		spray_hits == 8 and dummy.alive and dummy.hit_target.health > 0.0
			and lines.size() >= 2 and lines[0].begins_with("KILLED  100 damage in 1 hit"),
		"G keeps it standing: eight rounds to the head all register, each one counted as a kill (%d, %s)" % [spray_hits, lines[0] if lines.size() > 0 else ""]
	)
	_range.toggle_immortal()
	_check(not dummy.hit_target.immortal, "and G again lets it die")
	_check(
		_range.hitbox_source.contains("19 CS2 capsules") or _range.hitbox_source.contains("stand-in"),
		"the readout says which hitboxes it wears (%s)" % _range.hitbox_source
	)

	await _test_ragdoll()
	await _test_whole_ragdoll()
	await _test_fall_speed()
	_test_path_budget()
	_test_bodies_drawn_between_ticks()
	await _test_being_shot()
	await _test_death_cam()

	# The armour rules themselves, on a target of their own.
	var target := HitTarget.new()
	target.build_own_hitboxes = false
	root.add_child(target)
	_check(target.is_armored(&"head") and target.is_armored(&"arm") and not target.is_armored(&"leg"), "kevlar and helmet cover all but the legs")
	target.wear(100.0, false)
	_check(not target.is_armored(&"head") and target.is_armored(&"chest"), "kevlar alone leaves the head bare")
	target.armor = 30.0
	target.reset()
	_check(target.armor == 100.0, "a reset puts back what it was given to wear, not what is left of it")

	_report()


## A ragdoll on a small skeleton of its own, in metres under a node scaled
## to units the way the character is: a pelvis, a spine, a head and two legs
## of thigh and shin, standing, with a capsule on each. Pushed backward, it
## has to fall, come to rest on the floor, keep its joints together, bend
## its knees the right way, and carry the skeleton with it.
func _test_ragdoll() -> void:
	var scale := MapImporter.SOURCE2_VIEWER_SCALE
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * scale
	holder.position = Vector3(-512.0, 0.0, -256.0)
	_range.add_child(holder)
	var skeleton := Skeleton3D.new()
	holder.add_child(skeleton)
	var bones := [
		["pelvis", -1, Vector3(0, 0.95, 0)],
		["spine_0", 0, Vector3(0, 0.15, 0)],
		["spine_2", 1, Vector3(0, 0.2, 0)],
		["head_0", 2, Vector3(0, 0.3, 0)],
		["leg_upper_l", 0, Vector3(0.1, -0.05, 0)],
		["leg_lower_l", 4, Vector3(0, -0.43, 0)],
		["leg_upper_r", 0, Vector3(-0.1, -0.05, 0)],
		["leg_lower_r", 6, Vector3(0, -0.43, 0)],
	]
	for bone: Array in bones:
		var index := skeleton.add_bone(bone[0])
		if bone[1] >= 0:
			skeleton.set_bone_parent(index, bone[1])
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, bone[2]))
	skeleton.reset_bone_poses()
	var capsules: Array[Dictionary] = []
	for spec: Array in [
		["pelvis", 6.0, Vector3(-3, 0, 0), Vector3(3, 0, 0)],
		["spine_0", 6.0, Vector3(0, 0, 0), Vector3(0, 5, 0)],
		["spine_2", 7.0, Vector3(0, 0, 0), Vector3(0, 9, 0)],
		["head_0", 4.3, Vector3(0, 2, 0), Vector3(0, 6, 0)],
		["leg_upper_l", 4.0, Vector3(0, 0, 0), Vector3(0, -15, 0)],
		["leg_lower_l", 3.5, Vector3(0, 0, 0), Vector3(0, -15, 0)],
		["leg_upper_r", 4.0, Vector3(0, 0, 0), Vector3(0, -15, 0)],
		["leg_lower_r", 3.5, Vector3(0, 0, 0), Vector3(0, -15, 0)],
	]:
		capsules.append({"bone": spec[0], "radius": spec[1], "point0": spec[2], "point1": spec[3]})
	await physics_frame

	var head := skeleton.find_bone("head_0")
	var head_before := (skeleton.global_transform * skeleton.get_bone_global_pose(head)).origin
	var ragdoll := Ragdoll.new()
	_range.add_child(ragdoll)
	var made := ragdoll.build(skeleton, capsules, scale, Vector3.ZERO, Vector3.FORWARD, Vector3.BACK, head)
	var pelvis := skeleton.find_bone("pelvis")
	_check(made == 7 and ragdoll.get_children().filter(func(n: Node) -> bool: return n is Joint3D).size() == 6,
		"a body for every bone with a capsule and a joint to each one's parent (%d bodies)" % made)
	_check(
		ragdoll.body_for(skeleton.find_bone("spine_0")) == ragdoll.body_for(pelvis)
			and ragdoll.body_for(skeleton.find_bone("spine_2")) != ragdoll.body_for(pelvis),
		"a spine bone close over the pelvis rides the pelvis's body; the chest has its own"
	)
	var body_head: RigidBody3D = ragdoll.bodies.get(head)
	_check(
		body_head != null and body_head.collision_layer == Ragdoll.LAYER and body_head.collision_mask == Hitscan.WORLD_LAYER,
		"the bodies touch the world and nothing else, and are nothing a round is traced against"
	)
	# Jolt ignores a joint's bias and warns on every joint of every death
	# when one is set; Godot Physics needs Ragdoll.JOINT_BIAS.
	var biases := []
	for joint in ragdoll.get_children():
		if joint is ConeTwistJoint3D:
			biases.append((joint as ConeTwistJoint3D).get_param(ConeTwistJoint3D.PARAM_BIAS))
		elif joint is HingeJoint3D:
			biases.append((joint as HingeJoint3D).get_param(HingeJoint3D.PARAM_BIAS))
	var wanted := 0.3 if Ragdoll.on_jolt() else Ragdoll.JOINT_BIAS
	_check(
		not biases.is_empty() and biases.all(func(bias: float) -> bool: return is_equal_approx(bias, wanted)),
		"its joints' bias is %s (%s)" % ["left alone on Jolt, which has none" if Ragdoll.on_jolt() else "Ragdoll.JOINT_BIAS on Godot Physics", biases]
	)

	for i in SimClock.ticks_in(4.0):
		await physics_frame
	await process_frame

	var lowest := INF
	var fastest := 0.0
	for body: RigidBody3D in ragdoll.bodies.values():
		lowest = minf(lowest, body.global_position.y)
		fastest = maxf(fastest, body.linear_velocity.length())
	_check(
		body_head.global_position.y < 16.0 and lowest > -2.0,
		"it falls and lies on the floor, not through it (head at %.1f, lowest part at %.1f)" % [body_head.global_position.y, lowest]
	)
	_check(fastest < 20.0, "and comes to rest (%.1f u/s at most)" % fastest)
	_check(
		body_head.global_position.z > head_before.z + 10.0,
		"it fell the way the round was going (head %.0f units back)" % (body_head.global_position.z - head_before.z)
	)
	var head_now := (skeleton.global_transform * skeleton.get_bone_global_pose(head)).origin
	var expected := (body_head.global_transform * (ragdoll.get("_offsets")[head] as Transform3D)).origin
	_check(head_now.distance_to(expected) < 0.5, "the skeleton's head is where the head's body is")
	# Drawn between ticks: with the head's body 10 units higher a tick ago,
	# half way between is 5 up.
	var before_step: Dictionary = ragdoll.get("_before_step")
	var was: Transform3D = before_step.get(body_head, body_head.global_transform)
	before_step[body_head] = body_head.global_transform.translated(Vector3.UP * 10.0)
	ragdoll.pose_skeleton(0.5)
	var halfway := (skeleton.global_transform * skeleton.get_bone_global_pose(head)).origin
	before_step[body_head] = was
	ragdoll.pose_skeleton()
	_check(
		absf(halfway.y - expected.y - 5.0) < 0.01,
		"between two ticks the skeleton is drawn between where they left the bodies (%.2f up of 10)" % (halfway.y - expected.y)
	)

	var worst_gap := 0.0
	var knees_ok := true
	for side in ["l", "r"]:
		var thigh := skeleton.find_bone("leg_upper_" + side)
		var shin := skeleton.find_bone("leg_lower_" + side)
		var hip := (skeleton.global_transform * skeleton.get_bone_global_pose(thigh))
		var knee := (skeleton.global_transform * skeleton.get_bone_global_pose(shin))
		# The knee bone's head is where the thigh's capsule ends.
		var thigh_end: Vector3 = hip * (Vector3(0, -15, 0) / scale)
		worst_gap = maxf(worst_gap, thigh_end.distance_to(knee.origin) - 0.43 * scale + 15.0)
		# Bent the right way: the shin swings behind the thigh, toward the
		# back of the body, which the thigh's own frame still says.
		var thigh_down := (hip.basis * Vector3.DOWN).normalized()
		var shin_down := (knee.basis * Vector3.DOWN).normalized()
		var thigh_back := (hip.basis * Vector3.BACK).normalized()
		var bend := rad_to_deg(thigh_down.angle_to(shin_down))
		if bend > 10.0 and shin_down.dot(thigh_back) < -0.05:
			knees_ok = false
		if bend > 140.0:
			knees_ok = false
	_check(absf(worst_gap) < 3.0, "the joints hold: a knee is where its thigh ends, give or take (%.1f)" % worst_gap)
	_check(knees_ok, "the knees bend backward and no further than they can")

	ragdoll.queue_free()
	holder.queue_free()


## A body falling for a second under the ragdoll's gravity is going 800 u/s.
## Jolt caps every body's speed at 500 "m/s", which in this project's inches
## is 500 u/s, what a body has after falling 156 units; the project raises
## the cap to Jolt's 500 m/s in inches.
func _test_fall_speed() -> void:
	var body := RigidBody3D.new()
	body.collision_layer = Ragdoll.LAYER
	body.collision_mask = Ragdoll.MASK
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	(shape.shape as SphereShape3D).radius = 4.0
	body.add_child(shape)
	body.position = Vector3(-512.0, 5000.0, -256.0)
	_range.add_child(body)
	body.add_constant_central_force(Vector3.DOWN * Ragdoll.GRAVITY * body.mass)
	for i in SimClock.ticks_in(1.0):
		await physics_frame
	_check(
		absf(-body.linear_velocity.y - Ragdoll.GRAVITY) < 10.0,
		"a body falling for a second goes %.0f u/s, as gravity has it, not held to a speed cap" % -body.linear_velocity.y
	)
	body.queue_free()


## A body is drawn between the last two ticks as far as the frame falls
## between them: where it stood and which way it faced.
func _test_bodies_drawn_between_ticks() -> void:
	var body := PlayerModel.new()
	_range.add_child(body)
	body.show_between(Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, -4.0), 350.0, 30.0, 0.5)
	_check(
		body.global_position.is_equal_approx(Vector3(5.0, 0.0, -2.0))
			and is_equal_approx(wrapf(body.rotation.y, -PI, PI), wrapf(PI + deg_to_rad(10.0), -PI, PI)),
		"a body half way between two ticks stands half way, facing half way round the short way (%s, %.1f degrees)"
			% [body.global_position, rad_to_deg(body.rotation.y)]
	)
	body.free()


## Bots find their way over the nav mesh a few a tick, and the rest on the
## next, rather than every bot on the tick a round starts.
func _test_path_budget() -> void:
	var tick := 1 << 40
	var granted := []
	for i in Bot.PATH_SEARCHES_PER_TICK + 1:
		granted.append(Bot._may_search(tick))
	var expected := []
	for i in Bot.PATH_SEARCHES_PER_TICK:
		expected.append(true)
	expected.append(false)
	_check(
		granted == expected and Bot._may_search(tick + 1),
		"%d bots a tick may search the nav mesh, and the next waits for the next tick (%s)" % [Bot.PATH_SEARCHES_PER_TICK, granted]
	)


## The whole body the way CS2's hitboxes cover it, nineteen capsules on a
## spine of four short bones, arms up holding a rifle: killed standing, and
## killed running with a longer spine. With a body on every spine bone and
## Godot's own joint strength, this one tangled and flew off into the sky.
func _test_whole_ragdoll() -> void:
	for case: Array in [[1.0, Vector3.ZERO], [1.3, Vector3.ZERO], [1.5, Vector3(0.0, 0.0, 250.0)]]:
		var scale := MapImporter.SOURCE2_VIEWER_SCALE
		var holder := Node3D.new()
		holder.scale = Vector3.ONE * scale
		holder.position = Vector3(-512.0, 0.0, -256.0)
		_range.add_child(holder)
		var skeleton := Skeleton3D.new()
		holder.add_child(skeleton)
		var spine: float = case[0]
		# name, parent, where from the parent in metres, turned by (degrees)
		for bone: Array in [
			["pelvis", "", Vector3(0, 0.95, 0), Vector3.ZERO],
			["spine_0", "pelvis", Vector3(0, 0.08, 0) * spine, Vector3.ZERO],
			["spine_1", "spine_0", Vector3(0, 0.1, 0) * spine, Vector3.ZERO],
			["spine_2", "spine_1", Vector3(0, 0.12, 0) * spine, Vector3.ZERO],
			["spine_3", "spine_2", Vector3(0, 0.12, 0) * spine, Vector3.ZERO],
			["neck_0", "spine_3", Vector3(0, 0.12, 0) * spine, Vector3.ZERO],
			["head_0", "neck_0", Vector3(0, 0.1, 0), Vector3.ZERO],
			["clavicle_l", "spine_3", Vector3(0.03, 0.08, 0.02), Vector3.ZERO],
			["arm_upper_l", "clavicle_l", Vector3(0.17, 0, 0), Vector3(0, 0, -70)],
			["arm_lower_l", "arm_upper_l", Vector3(0, -0.28, 0), Vector3(-100, 0, 0)],
			["hand_l", "arm_lower_l", Vector3(0, -0.26, 0), Vector3.ZERO],
			["clavicle_r", "spine_3", Vector3(-0.03, 0.08, 0.02), Vector3.ZERO],
			["arm_upper_r", "clavicle_r", Vector3(-0.17, 0, 0), Vector3(0, 0, 70)],
			["arm_lower_r", "arm_upper_r", Vector3(0, -0.28, 0), Vector3(-100, 0, 0)],
			["hand_r", "arm_lower_r", Vector3(0, -0.26, 0), Vector3.ZERO],
			["leg_upper_l", "pelvis", Vector3(0.1, -0.05, 0), Vector3.ZERO],
			["leg_lower_l", "leg_upper_l", Vector3(0, -0.43, 0), Vector3(10, 0, 0)],
			["ankle_l", "leg_lower_l", Vector3(0, -0.42, 0), Vector3(-10, 0, 0)],
			["leg_upper_r", "pelvis", Vector3(-0.1, -0.05, 0), Vector3.ZERO],
			["leg_lower_r", "leg_upper_r", Vector3(0, -0.43, 0), Vector3(10, 0, 0)],
			["ankle_r", "leg_lower_r", Vector3(0, -0.42, 0), Vector3(-10, 0, 0)],
		]:
			var index := skeleton.add_bone(bone[0])
			if bone[1] != "":
				skeleton.set_bone_parent(index, skeleton.find_bone(bone[1]))
			skeleton.set_bone_rest(index, Transform3D(Basis.from_euler(bone[3] * PI / 180.0), bone[2]))
		skeleton.reset_bone_poses()
		var capsules: Array[Dictionary] = []
		for spec: Array in [
			["head_0", 4.5, Vector3(0, 1, 0), Vector3(0, 6, 0)],
			["neck_0", 3.0, Vector3(0, 0, 0), Vector3(0, 3.5, 0)],
			["pelvis", 6.0, Vector3(-3, 0, 0), Vector3(3, 0, 0)],
			["spine_0", 6.0, Vector3(0, 0, 0), Vector3(0, 3, 0)],
			["spine_1", 6.5, Vector3(0, 0, 0), Vector3(0, 4, 0)],
			["spine_2", 7.0, Vector3(0, 0, 0), Vector3(0, 4, 0)],
			["spine_3", 7.0, Vector3(-2, 0, 0), Vector3(2, 3, 0)],
			["arm_upper_l", 2.5, Vector3(0, 0, 0), Vector3(0, -10, 0)],
			["arm_lower_l", 2.2, Vector3(0, 0, 0), Vector3(0, -9, 0)],
			["hand_l", 1.8, Vector3(0, 0, 0), Vector3(0, -3, 0)],
			["arm_upper_r", 2.5, Vector3(0, 0, 0), Vector3(0, -10, 0)],
			["arm_lower_r", 2.2, Vector3(0, 0, 0), Vector3(0, -9, 0)],
			["hand_r", 1.8, Vector3(0, 0, 0), Vector3(0, -3, 0)],
			["leg_upper_l", 3.5, Vector3(0, 0, 0), Vector3(0, -15, 0)],
			["leg_lower_l", 3.0, Vector3(0, 0, 0), Vector3(0, -15, 0)],
			["ankle_l", 2.0, Vector3(0, -1, 2), Vector3(0, -2, 6)],
			["leg_upper_r", 3.5, Vector3(0, 0, 0), Vector3(0, -15, 0)],
			["leg_lower_r", 3.0, Vector3(0, 0, 0), Vector3(0, -15, 0)],
			["ankle_r", 2.0, Vector3(0, -1, 2), Vector3(0, -2, 6)],
		]:
			capsules.append({"bone": spec[0], "radius": spec[1], "point0": spec[2], "point1": spec[3]})
		await physics_frame

		var ragdoll := Ragdoll.new()
		_range.add_child(ragdoll)
		var made := ragdoll.build(skeleton, capsules, scale, case[1], Vector3.FORWARD, Vector3.BACK, skeleton.find_bone("head_0"))
		# Each joint's pivot as each of its two bodies holds it.
		var pivots := []
		for joint in ragdoll.get_children():
			if joint is ConeTwistJoint3D:
				var a := joint.get_node(joint.node_a) as RigidBody3D
				var b := joint.get_node(joint.node_b) as RigidBody3D
				pivots.append([a, b, a.to_local(joint.global_position), b.to_local(joint.global_position)])
		for i in SimClock.ticks_in(4.0):
			await physics_frame

		var highest := -INF
		var lowest := INF
		var fastest := 0.0
		for body: RigidBody3D in ragdoll.bodies.values():
			highest = maxf(highest, body.global_position.y)
			lowest = minf(lowest, body.global_position.y)
			fastest = maxf(fastest, body.linear_velocity.length())
		var widest := 0.0
		var spinning := 0.0
		for pivot: Array in pivots:
			widest = maxf(widest, (pivot[0] as RigidBody3D).to_global(pivot[2]).distance_to((pivot[1] as RigidBody3D).to_global(pivot[3])))
			spinning = maxf(spinning, rad_to_deg(((pivot[1] as RigidBody3D).angular_velocity - (pivot[0] as RigidBody3D).angular_velocity).length()))
		var hinges := ragdoll.get_children().filter(func(n: Node) -> bool: return n is HingeJoint3D).map(func(n: Node) -> String: return String(n.name))
		_check(
			hinges.size() == 4 and spinning < 60.0,
			"its knees and elbows are hinges (%s), and once it lies no joint is still turning (%.0f deg/s at most)" % [", ".join(hinges), spinning]
		)
		_check(
			highest < 16.0 and lowest > -2.0 and fastest < 20.0 and widest < 2.0,
			"a whole body killed %s, spine x%.1f, lies still on the floor in one piece (%d bodies; parts between %.1f and %.1f, %.1f u/s at most, joints apart by %.1f at most)"
				% ["running" if case[1] != Vector3.ZERO else "standing", spine, made, lowest, highest, fastest, widest]
		)
		ragdoll.queue_free()
		holder.queue_free()


## Killed, your camera leaves your head and watches your body from outside,
## back and above it, turning with the mouse; back alive, it is in your eyes
## again. Without the extracted model there is no ragdoll to watch, and the
## camera watches where you fell.
func _test_death_cam() -> void:
	var player: PlayerController = _range.player
	var view := player.view
	var was := player.respawn_seconds
	player.respawn_seconds = 1.0
	player.hit_target.immortal = false
	player.hit_target.apply_damage(1000.0, &"head", 1.0)
	_check(not player.alive, "a round to the head kills you")
	for i in 60:
		await process_frame
	var centre := player.body_centre()
	var camera := player.camera
	var looking := -camera.global_basis.z
	var to_body := (centre - camera.global_position).normalized()
	_check(
		camera.global_position.distance_to(centre) > 40.0 and camera.global_position.y > centre.y + 20.0
			and looking.dot(to_body) > 0.99,
		"dead, the camera stands back from your body and looks down at it (%.0f units off, %.0f above)"
			% [camera.global_position.distance_to(centre), camera.global_position.y - centre.y]
	)
	var turned := view.death_cam_position(centre, player.input.yaw_degrees + 90.0, player.input.pitch_degrees)
	var now := view.death_cam_position(centre, player.input.yaw_degrees, player.input.pitch_degrees)
	_check(turned.distance_to(now) > 40.0, "and the mouse turns it round the body")
	_check(
		player.model == null or player.ragdoll != null,
		"your own body falls as a ragdoll, where the model is there to fall"
	)
	for i in 160:
		await physics_frame
	await process_frame
	var eyes := player.global_position + Vector3.UP * player.eye_height()
	_check(
		player.alive and camera.global_position.distance_to(eyes) < 8.0 and player.ragdoll == null,
		"back alive, the camera is in your eyes again (%.1f units off)" % camera.global_position.distance_to(eyes)
	)
	player.respawn_seconds = was


## The shooter holds its fire until B; then its rounds find you from where
## it stands, tag you and throw your aim, an arc says where from and the
## readout says what each did. The switches change its weapon, your armour
## and whether you can die; T shows your hitboxes in a window of their own.
func _test_being_shot() -> void:
	var shooter: Bot = _range.shooter
	var player: PlayerController = _range.player
	_check(
		shooter != null and shooter.holds_fire and shooter.weapon != null and shooter.team != player.team
			and shooter.weapon_data.display_name == "AK-47",
		"the shooter stands armed with an AK-47, on the other side, holding its fire"
	)
	if shooter == null:
		return
	var gunfire := shooter.weapon_sounds.get_child(0) as AudioStreamPlayer3D
	_check(
		gunfire != null and gunfire.global_position.distance_to(shooter.global_position) < 1.0,
		"its gunfire sounds from where it stands, not from the middle of the map"
	)
	var hurt: Array[float] = []
	var lowest_tag := [1.0]
	# The most arcs up at once while the rounds land: they fade in a second
	# or so, and the wait below can run on for seconds after the last hit.
	var most_arcs := [0]
	player.hurt.connect(func(amount: float, _zone: StringName, _from: Vector3) -> void: hurt.append(amount))
	for i in SimClock.ticks_in(1.0):
		await physics_frame
	_check(hurt.is_empty() and shooter.target == null, "held, it leaves you alone for a second")

	_range.toggle_player_immortal()
	_range.toggle_shooter()
	for i in 640:
		await physics_frame
		lowest_tag[0] = minf(lowest_tag[0], player.velocity_modifier)
		most_arcs[0] = maxi(most_arcs[0], _range.damage_indicator.showing())
		if hurt.size() >= 3 and i > 256:
			break
	await process_frame
	_check(
		not shooter.holds_fire and shooter.target == player and hurt.size() >= 1,
		"B and it turns on you and its rounds land (%d hits)" % hurt.size()
	)
	_check(is_equal_approx(lowest_tag[0], 0.4), "an AK-47 hit tags you to 40%% of your speed (%.2f)" % lowest_tag[0])
	_check(player.alive and player.hit_target.health > 0.0, "J keeps you alive through it (health %.0f)" % player.hit_target.health)
	_check(most_arcs[0] >= 1, "arcs round the crosshair say where the hits came from (%d at most)" % most_arcs[0])
	var readout: String = _range.you_readout()
	_check(
		"tagged to 40%" in readout and "AK-47" in readout,
		"the readout lists each hit and what it tagged you to"
	)
	_range.toggle_shooter()
	await physics_frame
	_check(shooter.holds_fire and shooter.target == null, "B again and it holds its fire")

	_range.next_shooter_weapon()
	_range.next_shooter_weapon()
	_check(
		shooter.weapon_data.display_name == "MP9" and is_equal_approx(shooter.weapon.data.tagging_power, 1.0)
			and is_equal_approx(shooter.weapon.data.base_damage, WeaponVData.number("weapon_mp9", "m_nDamage"))
			and is_equal_approx(shooter.weapon.data.reload_time, WeaponVData.number("weapon_mp9", "m_flDisallowAttackAfterReloadStartDuration")),
		"U round to the MP9, with the game's damage, its own reload and 100%% tagging (%.0f, %.3f s)"
			% [shooter.weapon.data.base_damage, shooter.weapon.data.reload_time]
	)
	_range.next_shooter_weapon()
	_check(shooter.weapon_data.display_name == "AK-47", "and round again to the AK-47")

	_range.next_player_armour()
	_check(player.hit_target.armor == 100.0 and not player.hit_target.helmet, "Y takes your helmet off")
	_range.next_player_armour()
	_check(player.hit_target.armor == 0.0, "and Y again your kevlar")
	_range.next_player_armour()
	_range.toggle_player_immortal()
	_check(player.hit_target.helmet and not player.hit_target.immortal, "and both back on, and J lets you die again")

	var main_camera := player.camera
	var drawn := player.hit_target.hitboxes().all(func(hitbox: Hitbox) -> bool:
		var mesh := _find_drawn(hitbox)
		return mesh != null and mesh.layers == PlayerSim.UNSEEN_LAYER)
	_check(
		drawn and (main_camera.cull_mask & PlayerSim.UNSEEN_LAYER) == 0,
		"your hitboxes are drawn where your own camera does not see them"
	)
	_range.next_hitbox_view()
	await process_frame
	var camera: Camera3D = _range.hitbox_camera
	var ahead := Vector3(-sin(deg_to_rad(player.yaw_degrees)), 0.0, -cos(deg_to_rad(player.yaw_degrees)))
	var offset := camera.global_position - player.global_position
	_check(
		_range.hitbox_view() == "front" and _range.get("_hitbox_window").visible
			and (camera.cull_mask & PlayerSim.UNSEEN_LAYER) != 0 and (camera.cull_mask & RigModel.LAYER) == 0
			and absf(Vector2(offset.x, offset.z).length() - 110.0) < 1.0 and Vector2(offset.x, offset.z).normalized().dot(Vector2(ahead.x, ahead.z)) > 0.99,
		"T opens a window on them from 110 units in front of you, seeing your body and not the bots' or the view's"
	)
	_range.next_hitbox_view()
	await process_frame
	offset = camera.global_position - player.global_position
	_check(
		_range.hitbox_view() == "side" and absf(Vector2(offset.x, offset.z).normalized().dot(Vector2(ahead.x, ahead.z))) < 0.01,
		"T again from your side"
	)
	_range.next_hitbox_view()
	_check(not _range.get("_hitbox_window").visible, "and T again shuts it")


## Where to aim for a zone: the middle of that zone's first hitbox.
func _zone_point(dummy: Bot, zone: StringName) -> Vector3:
	for hitbox in dummy.hit_target.hitboxes():
		if hitbox.zone == zone:
			return hitbox.global_position
	return dummy.global_position + Vector3.UP * 40.0


## Fires one round with no spread from the lane's firing spot at a point, as
## the player's weapon does, and tells the range about it as the player would.
func _shoot(at: Vector3) -> Hitscan.Result:
	var player: PlayerController = _range.player
	var data: WeaponData = player.weapon.data.duplicate()
	data.inaccuracy_standing = 0.0
	data.inaccuracy_per_shot = 0.0
	var weapon := Weapon.new(data)
	var origin := Vector3(_range.dummy_position().x, 64.0, 0.0)
	var angles := PlayerInput.angles_from_direction(at - origin)
	_clock_usec += 1_000_000
	var shot := weapon.fire(_clock_usec, 0.0, origin, angles.x, angles.y, Weapon.ShooterState.new(0.0, true, false))
	var result := Hitscan.fire_at(_range.get_world_3d().direct_space_state, shot, data, player.hit_target.rids())
	player.shot_traced.emit(shot, result)
	return result


func _wait_for_respawn(dummy: Bot) -> void:
	for i in 30:
		await physics_frame
		if dummy.alive:
			break
	await physics_frame


func _find_drawn(hitbox: Hitbox) -> MeshInstance3D:
	for child in hitbox.get_children():
		if child is MeshInstance3D:
			return child
	return null


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % description)
	else:
		_failures += 1
		print("  FAIL %s" % description)


func _report() -> void:
	if _failures == 0:
		print("%d range checks passed." % _checks)
		quit(0)
	else:
		print("%d of %d range checks failed." % [_failures, _checks])
		quit(1)
