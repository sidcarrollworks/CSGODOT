extends SceneTree

## Checks the test range's dummy: that it stands in its lane wearing drawn
## hitboxes, that a round into it says what it did, that armour and the
## helmet change that the way CS does, and that a killed dummy comes back
## whole where it stood.
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
	_check(made == 8 and ragdoll.get_children().filter(func(n: Node) -> bool: return n is Joint3D).size() == 7,
		"a body for every bone with a capsule and a joint to each one's parent (%d bodies)" % made)
	var body_head: RigidBody3D = ragdoll.bodies.get(head)
	_check(
		body_head != null and body_head.collision_layer == Ragdoll.LAYER and body_head.collision_mask == Hitscan.WORLD_LAYER,
		"the bodies touch the world and nothing else, and are nothing a round is traced against"
	)

	for i in 128 * 4:
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
