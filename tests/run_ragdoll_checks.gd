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
## How long a body is left to come to rest. One killed running downhill
## at 250 u/s slides and rolls a while, its parts pressing on each other,
## and lies still at about 4.5 s.
const SETTLE_SECONDS := 6.0
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
var _game := GameSystems.new()
var _adapter: Box3DDrops
var _tick := 0


func _advance() -> void:
	# Only this explicit tick advances native bodies. Yield for rendering
	# and queued frees, without waiting for a matching engine physics tick.
	await process_frame
	if _adapter != null:
		_tick += 1
		_game.step(_tick, _space)


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_shape_parser()
	_world = Node3D.new()
	root.add_child(_world)
	await _advance()
	_space = _world.get_world_3d().direct_space_state
	_adapter = Box3DDrops.new()
	_world.add_child(_adapter)
	if not _adapter.initialize(_game, _world, true):
		_check(false, "native ragdoll fixture initializes")
		_report()
		return

	await _test_the_floor_is_one_sided()
	for shapes in ["cs2", "hitboxes"]:
		await _fall(shapes, "flat", "standing", Vector3.ZERO, -1)
		await _fall(shapes, "ramp", "standing", Vector3.ZERO, -1)
		var down := Vector3(0.0, -sin(deg_to_rad(RAMP_DEGREES)), -cos(deg_to_rad(RAMP_DEGREES))) * 250.0
		await _fall(shapes, "ramp", "running downhill", down, -1)
		await _fall(shapes, "flat", "shot in the legs", Vector3.ZERO, 1)
		await _fall(shapes, "curb", "standing with a foot in the kerb", Vector3.ZERO, -1)
	await _test_pushed()
	await _test_parts_and_others()
	await _test_more_bodies_than_layers()
	await _test_native_lifecycle()
	await _test_made_ahead()
	await _test_left_lying()
	await _test_let_go()
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
	_adapter.capture_world(_world)
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
	_adapter.capture_world(_world)


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
	var down := PhysicsRayQueryParameters3D.create(Vector3.UP * 8.0, Vector3.DOWN * 8.0, Hitscan.WORLD_LAYER)
	var up := PhysicsRayQueryParameters3D.create(down.to, down.from, Hitscan.WORLD_LAYER)
	down.hit_back_faces = false
	up.hit_back_faces = false
	_check(not (ground.get_child(0).shape as ConcavePolygonShape3D).backface_collision
		and not PhysicsQueries.intersect_ray(_space, down).is_empty()
		and PhysicsQueries.intersect_ray(_space, up).is_empty(),
		"map-style triangles and native floor rays see only the front face")
	var balls: Array[Node3D] = []
	for y in [-1.0, 6.0]:
		var ball := ClassDB.instantiate(&"Box3DBody") as Node3D
		ball.set(&"body_type", ClassDB.class_get_integer_constant(&"Box3DBody", &"DYNAMIC"))
		ball.set(&"shape_type", ClassDB.class_get_integer_constant(&"Box3DBody", &"SPHERE"))
		ball.set(&"sphere_radius", 3.0 * Ragdoll.METRES)
		ball.set(&"collision_layer", Ragdoll.LAYER)
		ball.set(&"collision_mask", Hitscan.WORLD_LAYER)
		ball.position = Vector3(0.0, y, 0.0) * Ragdoll.METRES
		_adapter.native_world.add_child(ball)
		balls.append(ball)
	for i in SimClock.ticks_in(1.0):
		await _advance()
	_check(
		balls[0].global_position.y / Ragdoll.METRES < -100.0 and absf(balls[1].global_position.y / Ragdoll.METRES - 3.0) < 1.0,
		"the stand-in floor is one-sided like dust2's: a ball starting with its centre under it falls through (%.0f), one over it lands (%.1f)"
			% [balls[0].global_position.y / Ragdoll.METRES, balls[1].global_position.y / Ragdoll.METRES]
	)
	for ball in balls:
		ball.queue_free()
	ground.queue_free()
	await _advance()


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
	var bones := {}
	for index in skeleton.get_bone_count():
		bones[skeleton.get_bone_name(index).to_lower()] = index
	for shape: Dictionary in shapes:
		var bone: int = bones.get(String(shape["bone"]).to_lower(), -1)
		assert(bone >= 0, "Every fixture capsule must have a bone.")
		var bone_to_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		for point: Vector3 in [shape["point0"], shape["point1"]]:
			var at := bone_to_world * (point / SCALE)
			deepest = maxf(deepest, float(shape["radius"]) - surface.distance_to(at))
	return deepest


## A body killed on a floor, left SETTLE_SECONDS, then checked: every part's
## centre over the floor, the whole of it at rest, and each joint within
## what a body allows.
func _fall(which: String, kind: String, how: String, velocity: Vector3, legs_hit: int) -> void:
	var ground := _floor(kind)
	var surface := _surface(kind)
	if kind == "curb":
		_curb(ground)
		await _advance()
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
	await _advance()
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
	for i in SimClock.ticks_in(SETTLE_SECONDS):
		await _advance()
		for body: Ragdoll.Part in ragdoll.bodies.values():
			# How far the part is over the floor, less its thickness:
			# negative once all of it is under.
			worst_under = minf(worst_under, _over(kind, surface, body.global_position) + _thinnest(body))
	await process_frame

	var names := []
	var fastest := 0.0
	var ends_under := INF
	for body: Ragdoll.Part in ragdoll.bodies.values():
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
	await _advance()


## The radius of a body's thinnest part.
func _thinnest(body: Ragdoll.Part) -> float:
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


# --- What CS2 does that Sid checked (2026-09-26) --------------------------

## A stand-in body over a flat floor, its feet just in it, and a ragdoll
## built from it: [ragdoll, holder, pelvis body].
func _killed(at: Vector3, velocity: Vector3, hit_direction: Vector3) -> Array:
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * SCALE
	_world.add_child(holder)
	var skeleton := _skeleton(holder)
	var shapes := _shapes("cs2")
	await process_frame
	var into := _deepest(skeleton, shapes, _surface("flat")) - FEET_IN
	holder.position = at + Vector3(0.0, into, 0.0)
	await _advance()
	var ragdoll := Ragdoll.new()
	_world.add_child(ragdoll)
	ragdoll.build(skeleton, shapes, SCALE, velocity, Vector3.FORWARD, hit_direction, skeleton.find_bone("spine_2"))
	return [ragdoll, holder, ragdoll.bodies[skeleton.find_bone("pelvis")]]


## The killing round pushes the body away from the shooter, and a body that
## was running keeps going too, so it falls along the two together.
func _test_pushed() -> void:
	var ground := _floor("flat")
	var away := Vector3.RIGHT
	for case: Array in [["standing", Vector3.ZERO], ["running forward", Vector3.FORWARD * 250.0]]:
		var made: Array = await _killed(Vector3.ZERO, case[1], away)
		var pelvis: Ragdoll.Part = made[2]
		var start := pelvis.global_position
		for i in SimClock.ticks_in(1.0):
			await _advance()
		var moved := pelvis.global_position - start
		var ok := moved.x > 4.0
		if case[1] != Vector3.ZERO:
			ok = ok and moved.z < -20.0
		else:
			ok = ok and absf(moved.z) < moved.x
		_check(ok, "killed %s by a round from its left, it falls away from the shooter%s (moved %.0f right, %.0f forward)"
			% [case[0], ", and on forward with the run it had" if case[1] != Vector3.ZERO else "", moved.x, -moved.z])
		(made[0] as Node).queue_free()
		(made[1] as Node).queue_free()
		await _advance()
	ground.queue_free()
	await _advance()


## A body's parts collide with each other, but not two parts joined at a
## joint nor two that start inside each other; and one dead body passes
## through another: one dropped onto another lies on the floor through it.
func _test_parts_and_others() -> void:
	var ground := _floor("flat")
	var first: Array = await _killed(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var ragdoll: Ragdoll = first[0]
	var hands: Array = ragdoll.bodies.values().filter(func(body: Ragdoll.Part) -> bool: return String(body.name).contains("hand"))
	var head: Array = ragdoll.bodies.values().filter(func(body: Ragdoll.Part) -> bool: return String(body.name).contains("head"))
	var shin: Array = ragdoll.bodies.values().filter(func(body: Ragdoll.Part) -> bool: return String(body.name).contains("leg_lower_l"))
	var excepted := (head[0] as Ragdoll.Part).get_collision_exceptions()
	var one := ragdoll.bodies.values()[0] as Ragdoll.Part
	_check(
		one.layer_high != 0 and one.mask_high == one.layer_high
			and int(one.native.get(&"collision_layer_high")) == one.layer_high
			and int(one.native.get(&"collision_mask_high")) == one.mask_high
			and ragdoll.bodies.values().all(func(body: Ragdoll.Part) -> bool: return body.layer_high == one.layer_high)
			and not excepted.has(shin[0]) and hands.size() == 2,
		"a body's parts collide with one another, by an upper layer of the body's own: the head and a shin are no exception to each other"
	)
	_check(
		one.collision_mask & Ragdoll.LAYER == 0 and one.collision_layer == Ragdoll.LAYER,
		"and not by the layer every dead body is on, which would have them meet another's"
	)
	for i in SimClock.ticks_in(2.0):
		await _advance()
	var lying: float = (first[2] as Ragdoll.Part).global_position.y
	var exclusions := _adapter.native_world.get_child_count()
	# A second body killed standing on the first one's spot, 30 units up.
	var second: Array = await _killed(Vector3(0.0, 30.0, 0.0), Vector3.ZERO, Vector3.ZERO)
	var theirs := second[0] as Ragdoll
	var made_for_it := _adapter.native_world.get_child_count() - exclusions
	for i in SimClock.ticks_in(3.0):
		await _advance()
	var fell_to: float = (second[2] as Ragdoll.Part).global_position.y
	_check(
		theirs.slot != ragdoll.slot and not theirs.meets(ragdoll) and not ragdoll.meets(theirs) and fell_to < lying + 4.0,
		"one dead body falls through another onto the floor, not onto it (its pelvis %.1f up, the one under it %.1f), on an upper layer of its own (%d and %d)"
			% [fell_to, lying, theirs.slot, ragdoll.slot]
	)
	_check(
		made_for_it < 225,
		"and nothing is made to say so: %d things in the native world for the second body, where 225 exceptions were made for the pair besides"
			% made_for_it
	)
	for made: Array in [first, second]:
		(made[0] as Node).queue_free()
		(made[1] as Node).queue_free()
	ground.queue_free()
	await _advance()


## More dead bodies than there are upper layers: the one past the last
## shares a layer with another, and is told to pass through it part by part
## where it lies near.
func _test_more_bodies_than_layers() -> void:
	var ground := _floor("flat")
	var made: Array = []
	# Every body the checks before this made has been taken away.
	await process_frame
	var held_before := _layers_held()
	_check(held_before == 0, "every body made and taken away so far has given its upper layer back (%d still held)" % held_before)
	var first: Array = await _killed(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	made.append(first)
	# Far off, only made: they hold a layer each.
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * SCALE
	holder.position = Vector3(400.0, 40.0, 400.0)
	_world.add_child(holder)
	var skeleton := _skeleton(holder)
	await process_frame
	var waiting: Array[Ragdoll] = []
	for i in Ragdoll.SLOTS - 1:
		var ragdoll := Ragdoll.new()
		_world.add_child(ragdoll)
		ragdoll.prepare(skeleton, _shapes("cs2"), SCALE, Vector3.FORWARD)
		waiting.append(ragdoll)
	var slots := {}
	slots[(first[0] as Ragdoll).slot] = true
	for ragdoll in waiting:
		slots[ragdoll.slot] = true
	_check(slots.size() == Ragdoll.SLOTS, "%d bodies have an upper layer each (%d layers held)" % [Ragdoll.SLOTS, slots.size()])
	for i in SimClock.ticks_in(2.0):
		await _advance()
	var lying: float = (first[2] as Ragdoll.Part).global_position.y
	# One more, killed over the first.
	var over: Array = await _killed(Vector3(0.0, 30.0, 0.0), Vector3.ZERO, Vector3.ZERO)
	made.append(over)
	var last := over[0] as Ragdoll
	var shares: Array = ([first[0]] + waiting).filter(func(ragdoll: Ragdoll) -> bool: return ragdoll.slot == last.slot)
	for i in SimClock.ticks_in(3.0):
		await _advance()
	var fell_to: float = (over[2] as Ragdoll.Part).global_position.y
	_check(shares.size() == 1, "the one after shares a layer with one of them (%d)" % shares.size())
	# Whichever it shares with, it lies through the first: by its layer, or
	# by being told to.
	_check(
		not last.meets(first[0]) and fell_to < lying + 4.0,
		"and passes through the body it falls on all the same (its pelvis %.1f up, the one under it %.1f; on the same layer %s)"
			% [fell_to, lying, last.slot == (first[0] as Ragdoll).slot]
	)
	var with_all := _layers_held()
	var theirs := PackedInt32Array()
	for ragdoll in waiting:
		theirs.append(ragdoll.slot)
		ragdoll.free()
	var still := 0
	for slot in theirs:
		if slot != last.slot:
			still += Ragdoll._slot_users[slot]
	_check(
		with_all == Ragdoll.SLOTS + 1 and _layers_held() == 2 and still == 0 and Ragdoll._slot_users[last.slot] == 2,
		"a body taken away gives its layer back: %d held with all of them, %d with the %d waiting gone, none of theirs held still (%d)"
			% [with_all, _layers_held(), waiting.size(), still]
	)
	var freed := Ragdoll.new()
	_world.add_child(freed)
	freed.prepare(skeleton, _shapes("cs2"), SCALE, Vector3.FORWARD)
	_check(freed.slot != last.slot and Ragdoll._slot_users[freed.slot] == 1, "and the next made has one to itself (%d)" % freed.slot)
	# Parked and dropped again it keeps the layer it has; cleared it gives
	# it back once, and once only.
	var kept := freed.slot
	freed.drop(Vector3.ZERO)
	freed.park()
	freed.drop(Vector3.ZERO)
	var while_lying := _layers_held()
	freed.clear()
	freed.clear()
	_check(while_lying == 3 and freed.slot == -1 and _layers_held() == 2 and Ragdoll._slot_users[kept] == 0,
		"dropped, parked and dropped it holds the one layer, and cleared twice it gives it back once (%d held)" % _layers_held())
	freed.free()
	holder.queue_free()
	for one: Array in made:
		(one[0] as Node).queue_free()
		(one[1] as Node).queue_free()
	ground.queue_free()
	await _advance()
	await process_frame
	_check(_layers_held() == 0, "and with every body gone none is held (%d)" % _layers_held())


## How many upper layers are held, by however many bodies.
func _layers_held() -> int:
	var held := 0
	for users in Ragdoll._slot_users:
		held += users
	return held


## A body made ahead of the death waits switched off, falls from how the
## skeleton stands when it is dropped, is parked, and falls again from
## somewhere else: what a player's does at every death and respawn.
func _test_made_ahead() -> void:
	var ground := _floor("flat")
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * SCALE
	_world.add_child(holder)
	var skeleton := _skeleton(holder)
	var shapes := _shapes("hitboxes")
	await process_frame
	var into := _deepest(skeleton, shapes, _surface("flat")) - FEET_IN
	holder.position = Vector3(0.0, into + 60.0, 0.0)
	await _advance()
	var baseline := _adapter.native_world.get_child_count()
	var ragdoll := Ragdoll.new()
	_world.add_child(ragdoll)
	var started := Time.get_ticks_usec()
	var made := ragdoll.prepare(skeleton, shapes, SCALE, Vector3.FORWARD)
	var making := Time.get_ticks_usec() - started
	var pelvis: Ragdoll.Part = ragdoll.bodies[skeleton.find_bone("pelvis")]
	var with_it := _adapter.native_world.get_child_count()
	var posed_before := skeleton.get_bone_global_pose(skeleton.find_bone("pelvis"))
	var waited_at := pelvis.native.global_transform
	var idle := _adapter.idle_ticks
	for i in 32:
		await _advance()
	_check(
		made == 15 and ragdoll.prepared_for(skeleton) and not ragdoll.fallen and not ragdoll.is_processing()
			and ragdoll.bodies.values().all(func(body: Ragdoll.Part) -> bool: return not bool(body.native.get(&"enabled")))
			and pelvis.native.global_transform.is_equal_approx(waited_at)
			and skeleton.get_bone_global_pose(skeleton.find_bone("pelvis")).is_equal_approx(posed_before),
		"a body made ahead (%d parts, in %.2f ms) waits switched off: half a second on it has not moved, and the skeleton is left to its animation"
			% [made, making / 1000.0]
	)
	_check(
		_adapter.idle_ticks - idle == 32 and not _adapter.pre_step.is_connected(ragdoll._before_native_step),
		"and the world is not stepped for it (%d of 32 ticks stepped nothing)" % (_adapter.idle_ticks - idle)
	)
	# It dies 60 units over the floor, moving right, bent at the waist.
	for bent: String in ["spine_0", "spine_1"]:
		skeleton.set_bone_pose_rotation(skeleton.find_bone(bent), Quaternion(Vector3.RIGHT, deg_to_rad(15.0)))
	await process_frame
	var folded := PackedStringArray()
	started = Time.get_ticks_usec()
	var fell := ragdoll.drop(Vector3.RIGHT * 100.0, Vector3.RIGHT, skeleton.find_bone("spine_2"))
	var dropping := Time.get_ticks_usec() - started
	var on_its_bone := pelvis.global_position.distance_to((skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("pelvis"))).origin)
	var spine_kept := 0.0
	for bone: int in ragdoll._order:
		var posed := (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin + Vector3.UP * ragdoll.lifted
		spine_kept = maxf(spine_kept, _bone_by_its_part(ragdoll, bone).origin.distance_to(posed))
		if ragdoll.body_for(bone) != ragdoll.bodies.get(bone):
			folded.append(skeleton.get_bone_name(bone))
	_check(
		fell == 15 and ragdoll.fallen and ragdoll.is_processing() and on_its_bone < 12.0 + ragdoll.lifted
			and ragdoll.bodies.values().all(func(body: Ragdoll.Part) -> bool: return bool(body.native.get(&"enabled")))
			and (pelvis.linear_velocity - Vector3.RIGHT * (100.0 + Ragdoll.BODY_SPEED)).length() < 0.5,
		"dropped (in %.2f ms) its parts are on the bones as the skeleton is posed, switched on and moving as the body was and the round pushed (%s)"
			% [dropping / 1000.0, pelvis.linear_velocity]
	)
	_check(not folded.is_empty() and spine_kept < 0.01,
		"every bone is where the skeleton had it at the death, those folded into another's part too (%s), bent as it was (%.3f units off at most)"
			% [", ".join(folded), spine_kept])
	for i in SimClock.ticks_in(3.0):
		await _advance()
	var lay := pelvis.global_position
	_check(lay.y < 20.0 and lay.x > 20.0, "it falls to the floor and on the way it was going (its pelvis %.1f up, %.0f along)" % [lay.y, lay.x])
	var of_the_death := _adapter.native_world.get_child_count() - with_it
	# Back, as at a respawn: the skeleton elsewhere, at rest.
	ragdoll.park()
	holder.position = Vector3(300.0, into, 0.0)
	skeleton.reset_bone_poses()
	var rest := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("pelvis"))).origin
	await process_frame
	var shown := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("pelvis"))).origin
	_check(
		not ragdoll.fallen and not ragdoll.is_processing() and shown.distance_to(rest) < 0.01
			and _adapter.native_world.get_child_count() == with_it
			and ragdoll.bodies.values().all(func(body: Ragdoll.Part) -> bool: return not bool(body.native.get(&"enabled"))),
		"parked, it writes the skeleton no more from that moment, its parts are switched off, and what was only of that death is gone (%d exceptions)"
			% of_the_death
	)
	var parked_at := pelvis.native.global_transform
	var idle_parked := _adapter.idle_ticks
	for i in 16:
		await _advance()
	_check(
		pelvis.native.global_transform.is_equal_approx(parked_at) and _adapter.idle_ticks - idle_parked == 16
			and pelvis.global_position.distance_to(lay) < 0.01,
		"and its parts lie in the native world where they were parked, unmoved and unstepped (%d of 16 ticks stepped nothing), until it is wanted"
			% (_adapter.idle_ticks - idle_parked)
	)
	# And dies again, there.
	_pose_as_killed(skeleton)
	await process_frame
	fell = ragdoll.drop(Vector3.ZERO)
	var again := pelvis.global_position.distance_to((skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("pelvis"))).origin)
	_check(fell == 15 and again < 12.0 + ragdoll.lifted and pelvis.global_position.distance_to(lay) > 100.0,
		"dropped again it falls from where the skeleton stands now, not from where it lay (%.0f units from there)" % pelvis.global_position.distance_to(lay))
	for i in SimClock.ticks_in(3.0):
		await _advance()
	var under := PackedStringArray()
	for body: Ragdoll.Part in ragdoll.bodies.values():
		if body.global_position.y < 0.0:
			under.append(String(body.name))
	_check(under.is_empty() and pelvis.global_position.y < 20.0 and absf(pelvis.global_position.x - 300.0) < 60.0,
		"and lies on the floor there, no part under it (%s)" % [under])
	ragdoll.clear()
	_check(_adapter.native_world.get_child_count() == baseline, "cleared, nothing of it is left in the native world")
	ragdoll.queue_free()
	holder.queue_free()
	ground.queue_free()
	await _advance()


## Where a ragdoll has a bone, from the part that carries it.
func _bone_by_its_part(ragdoll: Ragdoll, bone: int) -> Transform3D:
	return ragdoll.body_for(bone).global_transform * (ragdoll._offsets[bone] as Transform3D)


## The stand-in skeleton posed as it is killed: a rifle up, mid-stride.
func _pose_as_killed(skeleton: Skeleton3D) -> void:
	skeleton.reset_bone_poses()
	for bone: Array in BONES:
		if bone[4] != null:
			skeleton.set_bone_pose_rotation(skeleton.find_bone(bone[0]), Basis.from_euler(bone[4] * PI / 180.0).get_rotation_quaternion())


## A body come to rest is left lying: the world is stepped for it no more,
## and no frame poses it again.
func _test_left_lying() -> void:
	var ground := _floor("flat")
	var made: Array = await _killed(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var ragdoll: Ragdoll = made[0]
	var ticks := 0
	while not ragdoll.resting and ticks < SimClock.ticks_in(10.0):
		await _advance()
		ticks += 1
	var lay: Vector3 = (made[2] as Ragdoll.Part).global_position
	var idle := _adapter.idle_ticks
	for i in 32:
		await _advance()
	var skeleton := (made[1] as Node).get_child(0) as Skeleton3D
	var pelvis := skeleton.find_bone("pelvis")
	var shown := (skeleton.global_transform * skeleton.get_bone_global_pose(pelvis)).origin
	var posed := [0]
	var count := func() -> void: posed[0] += 1
	skeleton.skeleton_updated.connect(count)
	for i in 8:
		await process_frame
	_check(
		ragdoll.resting and ragdoll.fallen
			and not _adapter.pre_step.is_connected(ragdoll._before_native_step)
			and not _adapter.post_step.is_connected(ragdoll._after_native_step)
			and posed[0] == 0,
		"a body come to rest, every part asleep, is left lying (after %.1f s): it listens to the step no more and no frame poses it (%d poses in 8 frames)"
			% [ticks * SimClock.tick_seconds(), posed[0]]
	)
	# What the skeleton hangs under moved, as a bot's model was every frame
	# between the two ticks it died between: the body stays where it lies.
	var lay_shown := (skeleton.global_transform * skeleton.get_bone_global_pose(pelvis)).origin
	(made[1] as Node3D).position += Vector3(3.0, 0.0, 2.0)
	await process_frame
	var moved_shown := (skeleton.global_transform * skeleton.get_bone_global_pose(pelvis)).origin
	(made[1] as Node3D).position -= Vector3(3.0, 0.0, 2.0)
	await process_frame
	var back_shown := (skeleton.global_transform * skeleton.get_bone_global_pose(pelvis)).origin
	skeleton.skeleton_updated.disconnect(count)
	_check(
		moved_shown.distance_to(lay_shown) < 0.01 and back_shown.distance_to(lay_shown) < 0.01 and posed[0] >= 2,
		"what its skeleton hangs under moved 3.6 units and back, the body at rest is drawn where it lies all the same (%.3f and %.3f from there)"
			% [moved_shown.distance_to(lay_shown), back_shown.distance_to(lay_shown)]
	)
	_check(
		_adapter.idle_ticks - idle == 32 and (made[2] as Ragdoll.Part).global_position.distance_to(lay) < 0.01
			and shown.distance_to(_bone_by_its_part(ragdoll, pelvis).origin) < 0.01,
		"the world is stepped for it no more (%d of 32 ticks stepped nothing), and the skeleton stays as it lay" % (_adapter.idle_ticks - idle)
	)
	# Parked from rest and dropped again, it falls as any.
	ragdoll.park()
	(made[1] as Node3D).position += Vector3(0.0, 50.0, 0.0)
	_pose_as_killed(skeleton)
	await process_frame
	ragdoll.drop(Vector3.ZERO)
	var from: Vector3 = (made[2] as Ragdoll.Part).global_position
	for i in SimClock.ticks_in(1.0):
		await _advance()
	_check(not ragdoll.resting and from.y - (made[2] as Ragdoll.Part).global_position.y > 20.0,
		"dropped again from rest it falls (%.0f units in a second)" % (from.y - (made[2] as Ragdoll.Part).global_position.y))
	(made[0] as Node).queue_free()
	(made[1] as Node).queue_free()
	ground.queue_free()
	await _advance()


# --- The real agent -------------------------------------------------------

## Native lifecycle independently of the engine's automatic physics clock.
func _test_native_lifecycle() -> void:
	var ground := _floor("flat")
	var baseline := _adapter.native_world.get_child_count()
	var made: Array = await _killed(Vector3.UP * 100.0, Vector3.RIGHT * 80.0, Vector3.BACK)
	var ragdoll: Ragdoll = made[0]
	var pelvis: Ragdoll.Part = made[2]
	var before := pelvis.native.global_transform
	var velocity: Vector3 = pelvis.native.call(&"get_linear_velocity")
	for i in 3:
		await physics_frame
		await process_frame
	_check(pelvis.native.global_transform.is_equal_approx(before)
		and (pelvis.native.call(&"get_linear_velocity") as Vector3).is_equal_approx(velocity),
		"engine frames alone do not advance a native ragdoll")
	var mass := 0.0
	var authored_mass := 0.0
	var matches := true
	for part: Ragdoll.Part in ragdoll.bodies.values():
		var actual := float(part.native.call(&"get_mass"))
		mass += actual
		authored_mass += part.mass
		matches = matches and absf(actual - part.mass) < 0.0001
	_check(matches and absf(mass - authored_mass) < 0.001,
		"native parts preserve their authored masses, including the 0.5 kg limb minimum (%.3f kg total)" % mass)
	await _advance()
	_check(not pelvis.native.global_transform.is_equal_approx(before)
		and pelvis.global_position.distance_to(pelvis.native.global_position / Ragdoll.METRES) < 0.001,
		"a game tick advances native physics and updates the Source-unit bone proxy")
	ragdoll.clear()
	_check(_adapter.native_world.get_child_count() == baseline and ragdoll.bodies.is_empty(),
		"clear removes every native part, anatomical joint and collision exclusion")
	ragdoll.queue_free()
	(made[1] as Node).queue_free()
	ground.queue_free()
	await process_frame


## A body wanted back, as a respawn wants it: its skeleton put elsewhere and
## its bones back at rest, and the ragdoll let go of. The frame that follows
## shows the bones at rest. Freed and no more, the ragdoll is there until
## the frame's end and writes them once again, where it lay.
func _test_let_go() -> void:
	var ground := _floor("flat")
	for told: bool in [true, false]:
		var made: Array = await _killed(Vector3.UP * 40.0, Vector3.ZERO, Vector3.BACK)
		var ragdoll: Ragdoll = made[0]
		var holder: Node3D = made[1]
		var skeleton := holder.get_child(0) as Skeleton3D
		var pelvis := skeleton.find_bone("pelvis")
		for i in 40:
			await _advance()
		var lay := (skeleton.global_transform * skeleton.get_bone_global_pose(pelvis)).origin
		# Back, 500 units from where it fell.
		holder.position += Vector3(500.0, 0.0, 0.0)
		skeleton.reset_bone_poses()
		var rest := (skeleton.global_transform * skeleton.get_bone_global_pose(pelvis)).origin
		if told:
			ragdoll.let_go()
		else:
			ragdoll.queue_free()
		await process_frame
		var shown := (skeleton.global_transform * skeleton.get_bone_global_pose(pelvis)).origin
		if told:
			_check(shown.distance_to(rest) < 0.01 and rest.distance_to(lay) > 400.0,
				"a ragdoll let go of writes the skeleton no more: the frame after shows the pelvis where the body was put, %.0f units from where it lay" % rest.distance_to(lay))
		else:
			_check(shown.distance_to(lay) < 1.0,
				"one freed and no more writes it once again that frame, where it lay (%.1f from there, %.0f from where the body was put)" % [shown.distance_to(lay), shown.distance_to(rest)])
		holder.queue_free()
		await process_frame
	ground.queue_free()
	await process_frame


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
	await _advance()
	var ragdoll := Ragdoll.new()
	_world.add_child(ragdoll)
	var made := ragdoll.build(skeleton, shapes, SCALE, Vector3.ZERO, Vector3.FORWARD, Vector3.BACK, -1)
	for i in SimClock.ticks_in(SETTLE_SECONDS):
		await _advance()
	var under := []
	for body: Ragdoll.Part in ragdoll.bodies.values():
		if surface.distance_to(body.global_position) < 0.0:
			under.append(String(body.name))
	_check(made == 15 and under.is_empty(), "the agent's ragdoll, %d bodies, lies on the ramp with no part under it (%s)" % [made, under])
	ragdoll.queue_free()
	model.queue_free()
	ground.queue_free()
