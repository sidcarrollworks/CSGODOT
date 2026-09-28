extends "res://tests/check_suite.gd"

## Checks the drawn body's foot fit (FootPlant, playtest 2026-09-25 issue 5)
## without the extracted models: a stand-in leg skeleton shaped like the
## agents', scaled from metres to units as the models are, standing on a
## 13 degree ramp (T spawn's is 6 to 18) with its hull's uphill edge on it,
## on flat ground, and in the air. Whether it looks right on the agents on
## dust2 is Sid's to see (the issue's Local part).
##
##   godot --headless --path . --script tests/run_foot_plant_checks.gd

const UNIT_SCALE := 39.3701
const SLOPE := 13.0
## Half the hull's width: its uphill edge is this far from the middle.
const HULL_HALF := 16.0


func _initialize() -> void:
	_test_knee_bend()
	_test_tipped()
	await _test_ramp()
	await _test_flat()
	await _test_air()
	_test_body_plants()
	_finish("foot-plant")


## Legs as the agents' stand (metres), the knees a little forward, as the
## idle has them, facing -Z.
func _stand_in() -> Node3D:
	var model := Node3D.new()
	model.scale = Vector3.ONE * UNIT_SCALE
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	model.add_child(skeleton)
	for bone: Array in [
		["pelvis", "", Vector3(0, 1.09, 0)],
		["spine_0", "pelvis", Vector3(0, 0.08, 0)],
		["leg_upper_L", "pelvis", Vector3(0.1, -0.05, 0)],
		["leg_lower_L", "leg_upper_L", Vector3(0, -0.43, -0.04)],
		["ankle_L", "leg_lower_L", Vector3(0, -0.42, 0.04)],
		["ball_L", "ankle_L", Vector3(0, -0.15, -0.12)],
		["leg_upper_R", "pelvis", Vector3(-0.1, -0.05, 0)],
		["leg_lower_R", "leg_upper_R", Vector3(0, -0.43, -0.04)],
		["ankle_R", "leg_lower_R", Vector3(0, -0.42, 0.04)],
		["ball_R", "ankle_R", Vector3(0, -0.15, -0.12)],
	]:
		var index := skeleton.add_bone(bone[0])
		if bone[1] != "":
			skeleton.set_bone_parent(index, skeleton.find_bone(bone[1]))
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, bone[2]))
	skeleton.reset_bone_poses()
	return model


## Ground on the world layer: a slab tilted by degrees about Z, rising
## toward +x, and set so that the hull's +x edge (its uphill one) rests on
## it at y 0, the body's origin.
func _ground(degrees: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Hitscan.WORLD_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 20.0, 400.0)
	shape.shape = box
	# The slab's top face, before turning, at y 0 through its middle.
	shape.position = Vector3(0.0, -10.0, 0.0)
	body.add_child(shape)
	body.rotation.z = deg_to_rad(degrees)
	body.position = Vector3(0.0, -HULL_HALF * tan(deg_to_rad(degrees)), 0.0)
	return body


## The ground's height under x.
func _ground_y(degrees: float, x: float) -> float:
	return (x - HULL_HALF) * tan(deg_to_rad(degrees))


## A body standing on ground, with the fit under its skeleton: returns the
## model, the fit and what each skeleton update showed (bone -> world point).
func _stand(ground_degrees: float, planting: bool) -> Dictionary:
	var ground := _ground(ground_degrees)
	root.add_child(ground)
	var model := _stand_in()
	var skeleton := model.get_node("Skeleton3D") as Skeleton3D
	var plant := FootPlant.new()
	plant.planting = planting
	skeleton.add_child(plant)
	var seen := {}
	skeleton.skeleton_updated.connect(func() -> void:
		for bone_name in ["pelvis", "ankle_L", "ankle_R", "ball_L", "leg_lower_L", "leg_upper_L", "leg_upper_R"]:
			seen[bone_name] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin
	)
	# A capsule on the left shin and foot, as the agents' leg hitboxes ride
	# them, beside the model as a player's stand.
	var hitboxes := SkinnedHitboxes.new()
	model.add_child(hitboxes)
	root.add_child(model)
	var ankle_at := skeleton.get_bone_global_rest(skeleton.find_bone("ankle_L")).origin * UNIT_SCALE
	hitboxes.build(skeleton, [{
		"name": "foot_L", "bone": "ankle_L", "zone": &"leg", "side": &"left", "radius": 2.0,
		"point0": Vector3.ZERO, "point1": Vector3(0.0, -2.0, -4.0),
	}] as Array[Dictionary], null, UNIT_SCALE)
	return {"ground": ground, "model": model, "skeleton": skeleton, "plant": plant, "seen": seen, "hitboxes": hitboxes, "ankle_at": ankle_at}


## Where the clip (here the rest pose) has a bone, in the world: the model
## stands at the origin, scaled to units.
func _rest_point(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone_name)).origin * UNIT_SCALE


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _free(stood: Dictionary) -> void:
	(stood["model"] as Node).free()
	(stood["ground"] as Node).free()


## The knee lands where both bones keep their lengths and the ankle meets
## the target, bent the way it was.
func _test_knee_bend() -> void:
	var hip := Vector3(0, 40, 0)
	var knee := Vector3(0, 23, -1.5)
	var ankle := Vector3(0, 6.5, 0)
	var upper := hip.distance_to(knee)
	var lower := knee.distance_to(ankle)
	var target := Vector3(0, 12, 0)
	var bent := FootPlant.knee_bend(hip, knee, ankle, target)
	_check(
		absf(bent.distance_to(hip) - upper) < 0.01 and absf(bent.distance_to(target) - lower) < 0.01 and bent.z < knee.z,
		"the knee bends further forward to lift the foot, both bones keeping their lengths (%s)" % [bent]
	)
	var far := FootPlant.knee_bend(hip, knee, ankle, Vector3(0, -20, 0))
	_check(
		absf(far.distance_to(hip) - upper) < 0.01 and far.y < hip.y and absf(far.z) < 0.5,
		"a target out of reach straightens the leg toward it (%s)" % [far]
	)


func _test_tipped() -> void:
	var slope := Vector3(-sin(deg_to_rad(SLOPE)), cos(deg_to_rad(SLOPE)), 0.0)
	_check_near(
		rad_to_deg(Quaternion.IDENTITY.angle_to(FootPlant.tipped(Vector3.UP, slope, 1.0))), SLOPE,
		"a foot on a 13 degree ramp tips by 13 degrees"
	)
	var steep := Vector3(-sin(deg_to_rad(60.0)), cos(deg_to_rad(60.0)), 0.0)
	_check_near(
		rad_to_deg(Quaternion.IDENTITY.angle_to(FootPlant.tipped(Vector3.UP, steep, 1.0))), FootPlant.MOST_TILT,
		"and no more than MOST_TILT on a steeper one"
	)
	_check(
		(FootPlant.tipped(Vector3.UP, slope, 1.0) * Vector3.UP).is_equal_approx(slope),
		"tipped all the way, the foot's up is the ground's normal"
	)


## On the ramp the hull rests on its uphill edge; the feet come down to the
## floor, keeping their height above it, and the pelvis drops by the
## downhill foot's gap.
func _test_ramp() -> void:
	var stood := _stand(SLOPE, true)
	var skeleton := stood["skeleton"] as Skeleton3D
	var seen := stood["seen"] as Dictionary
	var pelvis_rest := _rest_point(skeleton, "pelvis")
	var ankle_lift := _rest_point(skeleton, "ankle_L").y
	await _frames(40)
	var ok := not seen.is_empty()
	var report := []
	var gaps := []
	for side in ["L", "R"]:
		var rest := _rest_point(skeleton, "ankle_" + side)
		var now: Vector3 = seen.get("ankle_" + side, rest)
		var over := now.y - _ground_y(SLOPE, rest.x)
		gaps.append(-_ground_y(SLOPE, rest.x))
		report.append("%s %.2f over the floor" % [side, over])
		ok = ok and absf(over - ankle_lift) < 0.5 and Vector2(now.x - rest.x, now.z - rest.z).length() < 1.5
	_check(ok, "on a 13 degree ramp both ankles end as high over the floor under them as the clip has them over the origin, %.2f (%s)" % [ankle_lift, ", ".join(report)])
	var dropped := pelvis_rest.y - (seen.get("pelvis", pelvis_rest) as Vector3).y
	_check(
		absf(dropped - maxf(gaps[0], gaps[1])) < 0.3,
		"the pelvis drops by the downhill foot's gap, %.2f (dropped %.2f)" % [maxf(gaps[0], gaps[1]), dropped]
	)
	var plant := stood["plant"] as FootPlant
	var ball := seen.get("ball_L", Vector3.ZERO) as Vector3
	var ankle := seen.get("ankle_L", Vector3.ZERO) as Vector3
	var ball_rest := _rest_point(skeleton, "ball_L") - _rest_point(skeleton, "ankle_L")
	# The ramp turns about Z: the foot's turn shows across it, in x and y.
	var tipped := rad_to_deg(Vector2(ball_rest.x, ball_rest.y).angle_to(Vector2(ball.x - ankle.x, ball.y - ankle.y)))
	_check(absf(tipped - SLOPE) < 3.0, "the foot tips with the ramp (%.1f degrees)" % [tipped])
	var foot := (stood["hitboxes"] as SkinnedHitboxes).hitboxes[0]
	var ankle_rest: Vector3 = stood["ankle_at"]
	# The capsule's middle, a unit down and two forward of the ankle.
	var lowered := ankle_rest.y - 1.0 - foot.global_position.y
	_check(
		absf(lowered + _ground_y(SLOPE, ankle_rest.x)) < 1.0,
		"the foot's hitbox rides the planted foot down to the floor, %.2f, as CS2's server poses its hitboxes with the foot IK (%.2f)" % [-_ground_y(SLOPE, ankle_rest.x), lowered]
	)
	var cast := plant.rays
	await _frames(10)
	_check(
		cast <= 4 and plant.rays == cast,
		"standing still it casts one ray a foot and no more (%d, then %d)" % [cast, plant.rays]
	)
	_free(stood)


## On flat ground nothing moves.
func _test_flat() -> void:
	var stood := _stand(0.0, true)
	var skeleton := stood["skeleton"] as Skeleton3D
	var seen := stood["seen"] as Dictionary
	await _frames(20)
	var ok := not seen.is_empty()
	for bone_name: String in seen:
		ok = ok and (seen[bone_name] as Vector3).distance_to(_rest_point(skeleton, bone_name)) < 0.05
	_check(ok, "on flat ground the pelvis and legs stay where the clip has them")
	_free(stood)


## In the air or dead (not planting) it casts nothing and moves nothing.
func _test_air() -> void:
	var stood := _stand(SLOPE, false)
	var skeleton := stood["skeleton"] as Skeleton3D
	var seen := stood["seen"] as Dictionary
	await _frames(20)
	var ok := not seen.is_empty()
	for bone_name: String in seen:
		ok = ok and (seen[bone_name] as Vector3).distance_to(_rest_point(skeleton, bone_name)) < 0.001
	_check(ok and (stood["plant"] as FootPlant).rays == 0, "not planting (in the air, or dead), it casts nothing and moves nothing")
	_free(stood)


## When a body plants its feet: alive and on the ground, seen or not, since
## its hitboxes ride the legs.
func _test_body_plants() -> void:
	_check(
		PlayerModel.plants_feet(true, false) and not PlayerModel.plants_feet(false, false)
			and not PlayerModel.plants_feet(true, true),
		"a body plants its feet alive and on the ground, and not in the air or dead"
	)
