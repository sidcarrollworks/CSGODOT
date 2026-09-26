extends "res://tests/check_suite.gd"

## Checks the ragdoll on the kind of floor dust2 has: a one-sided triangle
## mesh (ConcavePolygonShape3D, built the way MapImporter._build_collision
## builds the map's hull), flat and as a 20 degree ramp. The range's checks
## all land on a solid box, which is what hid issue 4 of the 2026-09-25
## playtest: legs sinking through the road in T spawn, and limbs bent past
## what a body allows.
##
##   godot --headless --path . --script tests/run_ragdoll_checks.gd
##
## The body is a stand-in skeleton the shape of CS2's agents, standing in a
## rest pose of its own (arms hanging out at 45 degrees, legs straight) and
## killed in another (a rifle up, mid-stride), its feet starting 1.5 units
## into the floor as the real ankle hitboxes do. Then CS2's own ragdoll
## shapes read from a model description, and the same checks with the
## hitbox capsules standing in for them. With the extracted agent, one more
## check drops the real model's ragdoll on the ramp.

const SCALE := MapImporter.SOURCE2_VIEWER_SCALE
const RAMP_DEGREES := 20.0
## How far into the floor the feet start, as the real ankle hitboxes do.
const FEET_IN := 1.5
## How far past a limit a joint may be found after the fall, in degrees:
## the solver holds a limit softly while a body lands on it.
const LIMIT_SLACK := 12.0
const AGENT := "res://assets/characters/agents/models/tm_phoenix/tm_phoenix_varianta.gltf"

## How far the body may bend at each joint, as a human body can, in degrees
## (reference/research/ragdoll-joints.md): [child bone, parent bone, the
## child limb's axis in its own bone, its neutral way ("down" to hang, ""
## for its rest), forward most, back most, out most, in most]. Forward is
## the body's front for a leg, an arm or the head.
const RANGES := [
	["leg_upper_l", "pelvis", Vector3.DOWN, "down", 120.0, 20.0, 45.0, 25.0],
	["leg_upper_r", "pelvis", Vector3.DOWN, "down", 120.0, 20.0, 45.0, 25.0],
	["arm_upper_l", "spine_2", Vector3.DOWN, "down", 135.0, 50.0, 135.0, 45.0],
	["arm_upper_r", "spine_2", Vector3.DOWN, "down", 135.0, 50.0, 135.0, 45.0],
	["head_0", "spine_2", Vector3.UP, "", 50.0, 60.0, 40.0, 40.0],
]

var _world: Node3D
var _space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_shape_parser()
	_world = Node3D.new()
	root.add_child(_world)
	await physics_frame
	_space = _world.get_world_3d().direct_space_state

	await _test_the_floor_is_one_sided()
	for shapes in ["cs2", "hitboxes"]:
		await _fall(shapes, "flat", "standing", Vector3.ZERO, -1)
		await _fall(shapes, "ramp", "standing", Vector3.ZERO, -1)
		var down := Vector3(0.0, -sin(deg_to_rad(RAMP_DEGREES)), -cos(deg_to_rad(RAMP_DEGREES))) * 250.0
		await _fall(shapes, "ramp", "running downhill", down, -1)
		await _fall(shapes, "flat", "shot in the legs", Vector3.ZERO, 1)
		await _fall(shapes, "curb", "standing with a foot in the kerb", Vector3.ZERO, -1)
	await _test_the_agent()
	_report()


func _print_passes() -> bool:
	return true


func _report() -> void:
	_finish("ragdoll")


# --- CS2's shapes ---------------------------------------------------------

## A model description holding a ragdoll's shapes the way Source 2 Viewer
## writes them (PhysicsShapeList under ModelDoc), beside a hitbox that must
## not be read as one, and a shapeless sphere that keeps a body without a
## shape.
const DESCRIPTION := """
{
	_class = "PhysicsShapeList"
	children =
	[
		{
			_class = "PhysicsShapeCapsule"
			parent_bone = "pelvis"
			surface_prop = "playerflesh"
			collision_tags = "solid"
			radius = 6.5
			point0 = [ -3.0, 0.0, 0.0 ]
			point1 = [ 3.0, 0.0, 0.0 ]
			name = ""
		},
		{
			_class = "PhysicsShapeSphere"
			parent_bone = "head_0"
			surface_prop = "playerflesh"
			collision_tags = "solid"
			radius = 4.75
			center = [ 0.0, 3.5, 0.5 ]
			name = ""
		},
		{
			_class = "PhysicsShapeSphere"
			parent_bone = "hand_l"
			surface_prop = "playerflesh"
			collision_tags = "solid"
			radius = 0.0
			center = [ 0.0, 0.0, 0.0 ]
			name = ""
		},
	]
},
{
	_class = "HitboxCapsule"
	parent_bone = "ankle_l"
	radius = 2.6
	point0 = [ 0.0, 0.0, 0.0 ]
	point1 = [ 0.0, 0.0, 5.0 ]
}
"""


func _test_shape_parser() -> void:
	var shapes := RagdollShapes.parse(DESCRIPTION)
	_check(shapes.size() == 2, "a model's ragdoll shapes are its PhysicsShapeCapsule and PhysicsShapeSphere, not its hitboxes nor a shapeless sphere (%d)" % shapes.size())
	if shapes.size() < 2:
		return
	_check(
		shapes[0]["bone"] == "pelvis" and is_equal_approx(shapes[0]["radius"], 6.5)
			and shapes[0]["point0"] == Vector3(-3, 0, 0) and shapes[0]["point1"] == Vector3(3, 0, 0),
		"a capsule is its bone, radius and two points (%s)" % shapes[0]
	)
	_check(
		shapes[1]["bone"] == "head_0" and shapes[1]["point0"] == Vector3(0, 3.5, 0.5) and shapes[1]["point1"] == shapes[1]["point0"],
		"a sphere is a capsule of no length about its centre (%s)" % shapes[1]
	)
	_check(shapes.all(func(shape: Dictionary) -> bool: return shape.get("physics", false)),
		"and each says it is a ragdoll's shape, not a hitbox, so no body is folded into another")
	shapes[0]["radius"] = 1.0
	_check(is_equal_approx(RagdollShapes.parse(DESCRIPTION)[0]["radius"], 6.5), "what parse hands out is the caller's own")


# --- The floor ------------------------------------------------------------

## A floor made as dust2's hull is: triangles from a mesh, one-sided, on
## the world's layer. flat or a ramp rising toward +Z.
func _floor(kind: String) -> StaticBody3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1200.0, 1200.0)
	var tilt := Transform3D.IDENTITY
	if kind == "ramp":
		tilt = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-RAMP_DEGREES)), Vector3.ZERO)
	var faces := tilt * mesh.get_faces()
	if kind == "curb":
		faces = _around_curb()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.collision_layer = Hitscan.WORLD_LAYER
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	_world.add_child(body)
	return body


## A kerb on the road, as in T spawn: a block CURB high made of one-sided
## triangles facing out, under where the left foot stands, so that foot
## starts inside it, as a foot drawn stepping onto a kerb does.
const CURB := Vector3(18.0, 6.0, 80.0)
const CURB_AT := Vector3(8.0, 3.0, 0.0)


func _curb(ground: StaticBody3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = CURB
	var box := Transform3D(Basis.IDENTITY, CURB_AT) * mesh.get_faces()
	# A map has no face under a kerb, where nothing is seen.
	var faces := PackedVector3Array()
	for i in range(0, box.size(), 3):
		if not (is_equal_approx(box[i].y, 0.0) and is_equal_approx(box[i + 1].y, 0.0) and is_equal_approx(box[i + 2].y, 0.0)):
			faces.append_array([box[i], box[i + 1], box[i + 2]])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	ground.add_child(collision)


## The road around the kerb and not under it: four pieces of floor.
func _around_curb() -> PackedVector3Array:
	var faces := PackedVector3Array()
	var x0 := CURB_AT.x - CURB.x / 2.0
	var x1 := CURB_AT.x + CURB.x / 2.0
	var z0 := CURB_AT.z - CURB.z / 2.0
	var z1 := CURB_AT.z + CURB.z / 2.0
	for piece: Array in [[-600.0, x0, -600.0, 600.0], [x1, 600.0, -600.0, 600.0], [x0, x1, -600.0, z0], [x0, x1, z1, 600.0]]:
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(piece[1] - piece[0], piece[3] - piece[2])
		var middle := Vector3((piece[0] + piece[1]) / 2.0, 0.0, (piece[2] + piece[3]) / 2.0)
		faces.append_array(Transform3D(Basis.IDENTITY, middle) * mesh.get_faces())
	return faces


## How far a point is over the floor, the kerb included: negative inside it.
func _over(kind: String, surface: Plane, at: Vector3) -> float:
	var over := surface.distance_to(at)
	if kind == "curb":
		var local := at - CURB_AT
		if absf(local.x) < CURB.x / 2.0 and absf(local.z) < CURB.z / 2.0:
			over = local.y - CURB.y / 2.0
	return over


## The floor's surface: its normal and a point on it.
func _surface(kind: String) -> Plane:
	var normal := Vector3.UP
	if kind == "ramp":
		normal = Basis(Vector3.RIGHT, deg_to_rad(-RAMP_DEGREES)) * Vector3.UP
	return Plane(normal, 0.0)


## That the stand-in floor is one-sided, as dust2's is: a ball whose centre
## starts under it falls on through, and one above it lands.
func _test_the_floor_is_one_sided() -> void:
	var ground := _floor("flat")
	var balls: Array[RigidBody3D] = []
	for y in [-1.0, 6.0]:
		var ball := RigidBody3D.new()
		ball.collision_layer = Ragdoll.LAYER
		ball.collision_mask = Ragdoll.MASK
		var collision := CollisionShape3D.new()
		collision.shape = SphereShape3D.new()
		(collision.shape as SphereShape3D).radius = 3.0
		ball.add_child(collision)
		_world.add_child(ball)
		ball.global_position = Vector3(0.0, y, 0.0)
		ball.add_constant_central_force(Vector3.DOWN * Ragdoll.GRAVITY * ball.mass)
		balls.append(ball)
	for i in SimClock.ticks_in(1.0):
		await physics_frame
	_check(
		balls[0].global_position.y < -100.0 and absf(balls[1].global_position.y - 3.0) < 1.0,
		"the stand-in floor is one-sided like dust2's: a ball starting with its centre under it falls through (%.0f), one over it lands (%.1f)"
			% [balls[0].global_position.y, balls[1].global_position.y]
	)
	for ball in balls:
		ball.queue_free()
	ground.queue_free()
	await physics_frame


# --- The stand-in body ------------------------------------------------------

## name, parent, where from the parent in metres, rest turn (degrees), and
## the turn it dies in, when that differs.
const BONES := [
	["pelvis", "", Vector3(0, 0.95, 0), Vector3.ZERO, null],
	["spine_0", "pelvis", Vector3(0, 0.08, 0), Vector3.ZERO, null],
	["spine_1", "spine_0", Vector3(0, 0.1, 0), Vector3.ZERO, null],
	["spine_2", "spine_1", Vector3(0, 0.12, 0), Vector3.ZERO, null],
	["spine_3", "spine_2", Vector3(0, 0.12, 0), Vector3.ZERO, null],
	["neck_0", "spine_3", Vector3(0, 0.12, 0), Vector3.ZERO, null],
	["head_0", "neck_0", Vector3(0, 0.1, 0), Vector3.ZERO, null],
	["clavicle_l", "spine_3", Vector3(0.03, 0.08, 0.02), Vector3.ZERO, null],
	["arm_upper_l", "clavicle_l", Vector3(0.17, 0, 0), Vector3(0, 0, 45), Vector3(60, 0, -25)],
	["arm_lower_l", "arm_upper_l", Vector3(0, -0.28, 0), Vector3.ZERO, Vector3(-100, 0, 0)],
	["hand_l", "arm_lower_l", Vector3(0, -0.26, 0), Vector3.ZERO, null],
	["clavicle_r", "spine_3", Vector3(-0.03, 0.08, 0.02), Vector3.ZERO, null],
	["arm_upper_r", "clavicle_r", Vector3(-0.17, 0, 0), Vector3(0, 0, -45), Vector3(60, 0, 25)],
	["arm_lower_r", "arm_upper_r", Vector3(0, -0.28, 0), Vector3.ZERO, Vector3(-100, 0, 0)],
	["hand_r", "arm_lower_r", Vector3(0, -0.26, 0), Vector3.ZERO, null],
	["leg_upper_l", "pelvis", Vector3(0.1, -0.05, 0), Vector3.ZERO, Vector3(25, 0, 0)],
	["leg_lower_l", "leg_upper_l", Vector3(0, -0.43, 0), Vector3.ZERO, Vector3(-30, 0, 0)],
	["ankle_l", "leg_lower_l", Vector3(0, -0.42, 0), Vector3.ZERO, Vector3(5, 0, 0)],
	["leg_upper_r", "pelvis", Vector3(-0.1, -0.05, 0), Vector3.ZERO, Vector3(-30, 0, 0)],
	["leg_lower_r", "leg_upper_r", Vector3(0, -0.43, 0), Vector3.ZERO, Vector3(-20, 0, 0)],
	["ankle_r", "leg_lower_r", Vector3(0, -0.42, 0), Vector3.ZERO, Vector3.ZERO],
]

## The nineteen hitbox capsules, as CS2's cover the body: [bone, radius,
## point0, point1], in units in the bone's space. The ankles reach down to
## the sole, as the real ones do.
const HITBOXES := [
	["head_0", 4.5, Vector3(0, 1, 0), Vector3(0, 6, 0)],
	["neck_0", 3.5, Vector3(0, 0, 0), Vector3(0, 1.4, 0)],
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
	["ankle_l", 2.6, Vector3(0, -1, 1), Vector3(0, -1, 6)],
	["leg_upper_r", 3.5, Vector3(0, 0, 0), Vector3(0, -15, 0)],
	["leg_lower_r", 3.0, Vector3(0, 0, 0), Vector3(0, -15, 0)],
	["ankle_r", 2.6, Vector3(0, -1, 1), Vector3(0, -1, 6)],
]

## CS2's ragdoll's fifteen bodies, as the agents' models list them: a
## capsule or a sphere on each, none on the neck or the spine between.
const RAGDOLL_SHAPES := [
	["pelvis", 6.5, Vector3(-3, 1, 0), Vector3(3, 1, 0)],
	["spine_2", 7.0, Vector3(0, 0, 0), Vector3(0, 8, 0)],
	["head_0", 4.75, Vector3(0, 3.5, 0.5), Vector3(0, 3.5, 0.5)],
	["arm_upper_l", 2.4, Vector3(0, -1, 0), Vector3(0, -9, 0)],
	["arm_lower_l", 2.0, Vector3(0, -1, 0), Vector3(0, -8.5, 0)],
	["hand_l", 1.9, Vector3(0, -2, 0), Vector3(0, -2, 0)],
	["arm_upper_r", 2.4, Vector3(0, -1, 0), Vector3(0, -9, 0)],
	["arm_lower_r", 2.0, Vector3(0, -1, 0), Vector3(0, -8.5, 0)],
	["hand_r", 1.9, Vector3(0, -2, 0), Vector3(0, -2, 0)],
	["leg_upper_l", 3.6, Vector3(0, -1, 0), Vector3(0, -14, 0)],
	["leg_lower_l", 3.0, Vector3(0, -1, 0), Vector3(0, -14, 0)],
	["ankle_l", 2.0, Vector3(0, -0.5, 1), Vector3(0, -0.5, 5.5)],
	["leg_upper_r", 3.6, Vector3(0, -1, 0), Vector3(0, -14, 0)],
	["leg_lower_r", 3.0, Vector3(0, -1, 0), Vector3(0, -14, 0)],
	["ankle_r", 2.0, Vector3(0, -0.5, 1), Vector3(0, -0.5, 5.5)],
]


func _skeleton(holder: Node3D) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	holder.add_child(skeleton)
	for bone: Array in BONES:
		var index := skeleton.add_bone(bone[0])
		if bone[1] != "":
			skeleton.set_bone_parent(index, skeleton.find_bone(bone[1]))
		skeleton.set_bone_rest(index, Transform3D(Basis.from_euler(bone[3] * PI / 180.0), bone[2]))
	skeleton.reset_bone_poses()
	for bone: Array in BONES:
		if bone[4] != null:
			skeleton.set_bone_pose_rotation(skeleton.find_bone(bone[0]), Basis.from_euler(bone[4] * PI / 180.0).get_rotation_quaternion())
	return skeleton


func _shapes(which: String) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	for spec: Array in (RAGDOLL_SHAPES if which == "cs2" else HITBOXES):
		var shape := {"bone": spec[0], "radius": spec[1], "point0": spec[2], "point1": spec[3]}
		if which == "cs2":
			shape["physics"] = true
		shapes.append(shape)
	return shapes


## How far the lowest point of a set of shapes is under a floor.
func _deepest(skeleton: Skeleton3D, shapes: Array[Dictionary], surface: Plane) -> float:
	var deepest := -INF
	for shape: Dictionary in shapes:
		var bone_to_world := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(shape["bone"]))
		for point: Vector3 in [shape["point0"], shape["point1"]]:
			var at := bone_to_world * (point / SCALE)
			deepest = maxf(deepest, float(shape["radius"]) - surface.distance_to(at))
	return deepest


## A body killed on a floor, left four seconds, then checked: every part's
## centre over the floor, the whole of it at rest, and each joint within
## what a body allows.
func _fall(which: String, kind: String, how: String, velocity: Vector3, legs_hit: int) -> void:
	var ground := _floor(kind)
	var surface := _surface(kind)
	if kind == "curb":
		_curb(ground)
		await physics_frame
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * SCALE
	_world.add_child(holder)
	var skeleton := _skeleton(holder)
	var shapes := _shapes(which)
	# The skeleton poses itself on a frame of its own.
	await process_frame
	# Feet FEET_IN into the floor, as the real ankles start.
	var into := _deepest(skeleton, shapes, surface) - FEET_IN
	holder.position = Vector3(0.0, into / surface.normal.y, 0.0)
	await physics_frame
	var feet_in := _deepest(skeleton, shapes, surface)

	var hit_bone := -1
	var hit_direction := Vector3.BACK
	if legs_hit > 0:
		hit_bone = skeleton.find_bone("leg_lower_l")
		hit_direction = Vector3(0.0, -0.2, 1.0).normalized()
	var ragdoll := Ragdoll.new()
	_world.add_child(ragdoll)
	var started := Time.get_ticks_usec()
	var made := ragdoll.build(skeleton, shapes, SCALE, velocity, Vector3.FORWARD, hit_direction, hit_bone)
	var build_ms := (Time.get_ticks_usec() - started) / 1000.0
	var label := "%s, killed on a %s one-sided floor (%s shapes)" % [how, "road by a kerb" if kind == "curb" else kind, which]

	var worst_under := INF
	for i in SimClock.ticks_in(4.0):
		await physics_frame
		for body: RigidBody3D in ragdoll.bodies.values():
			# How far the part is over the floor, less its thickness:
			# negative once all of it is under.
			worst_under = minf(worst_under, _over(kind, surface, body.global_position) + _thinnest(body))
	await process_frame

	var names := []
	var fastest := 0.0
	var ends_under := INF
	for body: RigidBody3D in ragdoll.bodies.values():
		fastest = maxf(fastest, body.linear_velocity.length())
		var over := _over(kind, surface, body.global_position)
		if over < ends_under:
			ends_under = over
		if over < 0.0:
			names.append(String(body.name).trim_prefix("Ragdoll_"))
	_check(
		made >= (15 if which == "cs2" else 13),
		"%s: a body for each of %s (%d, built in %.2f ms), feet starting %.1f units into the floor" % [label, "CS2's fifteen" if which == "cs2" else "the hitbox bones", made, build_ms, feet_in]
	)
	_check(
		names.is_empty() and worst_under > 0.0,
		"%s: no part's centre ends under the floor, nor any part goes wholly under it on the way (%s; the lowest centre %.1f over it; at worst a part's top %.1f over it)"
			% [label, ", ".join(names) if not names.is_empty() else "none under", ends_under, worst_under]
	)
	_check(fastest < 20.0, "%s: and lies still (%.1f u/s at most)" % [label, fastest])
	var bent := _outside_ranges(skeleton)
	_check(bent.is_empty(), "%s: every joint within what a body allows (%s)" % [label, "; ".join(bent) if not bent.is_empty() else "all within"])
	var knees := _knees(skeleton)
	_check(knees.is_empty(), "%s: knees bend backward, and elbows forward, no further than they can (%s)" % [label, "; ".join(knees) if not knees.is_empty() else "all right"])

	ragdoll.queue_free()
	holder.queue_free()
	ground.queue_free()
	await physics_frame


## The radius of a body's thinnest part.
func _thinnest(body: RigidBody3D) -> float:
	var thinnest := INF
	for collision in body.get_children():
		if collision is CollisionShape3D:
			thinnest = minf(thinnest, ((collision as CollisionShape3D).shape as CapsuleShape3D).radius)
	return thinnest


## Where a bone is in the world, posed and at rest.
func _posed(skeleton: Skeleton3D, bone: String) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))


func _rest(skeleton: Skeleton3D, bone: String) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(bone))


## Each joint of RANGES bent further than it can, as "name: how far". The
## child limb's way is taken in its parent bone's frame and compared with
## its neutral way there (hanging, or as at rest), and the turn from one to
## the other split into its turn toward the body's front and its turn
## outward, both as they are at rest in that same frame.
func _outside_ranges(skeleton: Skeleton3D) -> Array:
	var found := []
	var model_up := (skeleton.global_basis * Vector3.UP).normalized()
	var model_forward := (skeleton.global_basis * Vector3.FORWARD).normalized()
	for range: Array in RANGES:
		var parent_rest := _rest(skeleton, range[1])
		var child_rest := _rest(skeleton, range[0])
		var neutral: Vector3 = -model_up if range[3] == "down" else (child_rest.basis * range[2]).normalized()
		var outward := child_rest.origin - parent_rest.origin
		outward -= outward.dot(model_up) * model_up + outward.dot(model_forward) * model_forward
		# In the parent bone's own frame, so they turn with it.
		var to_parent := parent_rest.basis.orthonormalized().inverse()
		var n := (to_parent * neutral).normalized()
		var f := to_parent * model_forward
		f = (f - f.dot(n) * n).normalized()
		var o := to_parent * outward
		o = (o - o.dot(n) * n - o.dot(f) * f)
		o = o.normalized() if o.length() > 1e-4 else n.cross(f).normalized()
		var parent_now := _posed(skeleton, range[1]).basis.orthonormalized()
		var child_now := _posed(skeleton, range[0]).basis.orthonormalized()
		var axis: Vector3 = range[2]
		var limb := parent_now.inverse() * (child_now * axis).normalized()
		# The shortest turn from neutral to where the limb is, split into its
		# turn toward the front and its turn outward.
		var swing := Vector3.ZERO
		if n.cross(limb).length() > 1e-5:
			swing = n.cross(limb).normalized() * n.angle_to(limb)
		var forward := rad_to_deg(swing.dot(n.cross(f)))
		var out := rad_to_deg(swing.dot(n.cross(o)))
		var within: bool = (
			forward <= range[4] + LIMIT_SLACK and forward >= -range[5] - LIMIT_SLACK
			and out <= range[6] + LIMIT_SLACK and out >= -range[7] - LIMIT_SLACK
		)
		if not within:
			found.append("%s %.0f forward, %.0f out" % [range[0], forward, out])
	return found


## A knee bent the wrong way or past 125 degrees, an elbow past 120.
func _knees(skeleton: Skeleton3D) -> Array:
	var found := []
	for pair: Array in [["leg_upper_l", "leg_lower_l", 125.0, -1.0], ["leg_upper_r", "leg_lower_r", 125.0, -1.0],
			["arm_upper_l", "arm_lower_l", 120.0, 0.0], ["arm_upper_r", "arm_lower_r", 120.0, 0.0]]:
		var upper := _posed(skeleton, pair[0]).basis.orthonormalized()
		var lower := _posed(skeleton, pair[1]).basis.orthonormalized()
		var bend := rad_to_deg((upper * Vector3.DOWN).angle_to(lower * Vector3.DOWN))
		if bend > pair[2] + LIMIT_SLACK:
			found.append("%s bent %.0f" % [pair[1], bend])
		# A knee's shin swings behind its thigh, toward the thigh's back.
		if pair[3] < 0.0 and bend > 15.0 and (lower * Vector3.DOWN).dot(upper * Vector3.BACK) < -0.1:
			found.append("%s bent forward %.0f" % [pair[1], bend])
	return found


# --- The real agent -------------------------------------------------------

## The extracted agent killed standing on the ramp, with CS2's own shapes
## from its model description: only where the assets are.
func _test_the_agent() -> void:
	if not ResourceLoader.exists(AGENT):
		print("  (no extracted agent: its ragdoll on the ramp is checked on Sid's machine)")
		return
	var shapes := RagdollShapes.load_for(AGENT)
	_check(shapes.size() == 15, "the agent's model description gives CS2's fifteen ragdoll shapes (%d)" % shapes.size())
	var ground := _floor("ramp")
	var surface := _surface("ramp")
	var model := (load(AGENT) as PackedScene).instantiate() as Node3D
	# As PlayerModel stands it: scaled to units, turned to face -Z.
	model.scale = Vector3.ONE * SCALE
	model.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_world.add_child(model)
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var into := _deepest(skeleton, shapes, surface) - FEET_IN
	model.position = Vector3(0.0, into / surface.normal.y, 0.0)
	await physics_frame
	var ragdoll := Ragdoll.new()
	_world.add_child(ragdoll)
	var made := ragdoll.build(skeleton, shapes, SCALE, Vector3.ZERO, Vector3.FORWARD, Vector3.BACK, -1)
	for i in SimClock.ticks_in(4.0):
		await physics_frame
	var under := []
	for body: RigidBody3D in ragdoll.bodies.values():
		if surface.distance_to(body.global_position) < 0.0:
			under.append(String(body.name))
	_check(made == 15 and under.is_empty(), "the agent's ragdoll, %d bodies, lies on the ramp with no part under it (%s)" % [made, under])
	ragdoll.queue_free()
	model.queue_free()
	ground.queue_free()
