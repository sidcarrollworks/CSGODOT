class_name Ragdoll
extends Node3D

## A dead body falling as a body: a rigid body per bone that has a shape,
## jointed to the nearest such bone above it, and the skeleton posed from
## them every frame until it is taken away.
##
## CS2 ragdolls its dead from its own physics shapes: fifteen capsules and
## spheres in each agent's model description (RagdollShapes), one body each
## for the pelvis, the chest, the head and each side's upper arm, forearm,
## hand, thigh, shin and foot. Where a model has none (an extraction older
## than that), its hitbox capsules stand in for them: close to the same
## shapes on the same bones.
##
## A knee and an elbow are hinges, bending one way only, from straight to as
## far as they go. Every other joint lets its limb bend a different way
## forward, back, out and in, and twist, as a body allows
## (reference/research/ragdoll-joints.md), measured from the body standing
## with its arms hanging, not from how it died: a hip killed mid-stride
## still goes no further back than a hip can. Every joint has friction, so a
## limb slows as it swings rather than flailing and spinning on.
##
## The bodies are in world units, unscaled, like the hitboxes: the model is
## scaled up from metres and physics bodies do not take a scale. They live
## on their own layer and touch the world and each other, never a round or
## the living. As in CS2 (Sid, 2026-09-26), a body's parts collide with one
## another, except two parts joined at a joint or a joint apart and two
## that start inside each other, but one dead body passes through another. Before the first step the whole body is
## lifted clear of the floor: dust2's floor is one-sided, and a foot that
## starts inside a kerb or under the road is never pushed back out, but
## falls on through and drags its leg after it.
##
## With the hitbox capsules, a spine bone that starts close to the body
## below it gets no body of its own: its capsules join that body and it
## rides it, and so does the neck (CS2's ragdoll has no neck). The spine is
## four bones over the pelvis, a hand's width apart, and a chain of short
## bodies jointed that close together throws the physics solver into a fit
## (the body tangles and flies off), so the torso falls as two or three
## stiff pieces instead. Under Godot Physics the joints also pull their
## bodies back together gently (JOINT_BIAS), for the same reason.

## The physics layer the bodies are on (the fifth), and what they touch:
## the world, and the bodies of the same dead body (another's are made
## exceptions, _pass_through_others).
const LAYER := 16
const MASK := Hitscan.WORLD_LAYER | LAYER
## How near, in units, another dead body has to lie for this one to be
## told to pass through it. Farther, they cannot reach each other.
const OTHERS_NEAR := 200.0
## The group every ragdoll is in, to find the others.
const GROUP := &"ragdolls"
## The world's gravity, in units per second squared (MovementConfig's).
const GRAVITY := 800.0
## The body's weight in all, shared between the parts by their size. Only
## the ratios matter, to the joints.
const TOTAL_MASS := 80.0

## How far each joint lets its bone bend, in degrees, by bone name, from
## the body standing with its arms hanging (reference/research/
## ragdoll-joints.md has each number's source). A knee or an elbow is a
## hinge: it bends from straight to the angle given, toward the body's back
## or front, and nothing else. Every other joint is
## [name contains, twist either way, forward, back, out, in, neutral]:
## forward is toward the body's front (for a foot, the toes up), out away
## from the body's middle, and neutral "down" measures the limb from
## hanging straight down rather than from how the model stands at rest.
const JOINTS := [
	["head", 70.0, 50.0, 60.0, 40.0, 40.0, &""],
	["spine", 30.0, 45.0, 25.0, 25.0, 25.0, &""],
	["arm_upper", 60.0, 135.0, 50.0, 135.0, 45.0, &"down"],
	["hand", 40.0, 70.0, 70.0, 25.0, 25.0, &""],
	["leg_upper", 35.0, 120.0, 20.0, 45.0, 25.0, &"down"],
	["ankle", 20.0, 20.0, 45.0, 15.0, 15.0, &""],
]
const DEFAULT_JOINT := ["", 15.0, 30.0, 30.0, 30.0, 30.0, &""]
const HINGES := [
	# [name contains, bends to, bends toward]
	["arm_lower", 120.0, &"front"],
	["leg_lower", 125.0, &"back"],
]
## How much of the way back together a joint pulls its two bodies each step,
## when they drift apart, under Godot Physics. Godot's default is 0.3; at
## that, one fall in twelve of a stand-in body exploded, and from 0.2 down
## none did, the joints still holding within half a unit. Jolt has no such
## setting and warns when one is given: it puts drifting bodies back by
## moving them, not by speeding them up, so it cannot overshoot and fling
## them apart, which is what this was holding down.
const JOINT_BIAS := 0.15
## How hard a joint resists its two bodies turning against each other, per
## unit of the child body's mass, in mass-units by square inches a second
## squared: the stiffness of a dead body's joints. It is a motor in each
## joint driving the turn toward standing still, no stronger than this, the
## way CS2 compiles a joint's friction (Source 2 Viewer's ModelExtract, as
## read 2026-09-25: a friction motor of 360 N per kilogram times the
## friction). Without it a hand or a head, light on the end of a limb, whips
## round at thousands of degrees a second and keeps spinning after the body
## has landed. It is inside the solver, so it only ever takes speed away.
const JOINT_TORQUE := 2000.0

## How close, in units, a spine bone can start to the bone its body stands
## on and still have a body of its own. Closer and it joins that body. Only
## the spine folds: the hips and shoulders also start close to the torso, but
## a leg or an arm has to swing.
const FOLD_DISTANCE := 8.0
const FOLDS := "spine"
## A neck always rides the body below it: CS2's ragdoll has no neck, and a
## short heavy neck between the chest and the head is one more short body.
const ALWAYS_FOLDS := "neck"

## CS2's playerflesh (reference/surfaces/surfaces.csv), what its ragdoll
## shapes are made of: how the body slides on the floor.
const FRICTION := 0.8
## How far above a part the floor is looked for when the body is lifted
## clear of it, in units: more than a step (18) is tall, so a foot inside a
## kerb or a stair is found.
const LIFT_REACH := 24.0
## How far clear of the floor the lowest part is lifted, in units.
const LIFT_MARGIN := 0.25

## What the round that killed does to the body: the part it went into takes
## the most of it, the whole body a little.
const HIT_SPEED := 180.0
const BODY_SPEED := 40.0

## The bodies by the index of the bone each stands on. A bone folded into
## another's body is not a key; body_for finds its body.
var bodies: Dictionary = {}

var _skeleton: Skeleton3D
## Each bone's transform relative to its body, scale included, so the bone
## can be put back from where the body is.
var _offsets: Dictionary = {}
var _order: Array[int] = []
## For every bone with capsules, the bone whose body carries it: itself, or
## the one above it that it was folded into.
var _host: Dictionary = {}
## How far the body was lifted to start clear of the floor, in units.
var lifted := 0.0
## The rays that find the floor a part is in (_under): down onto the tops
## of things, and up into their undersides, both front faces only.
var _down := PhysicsRayQueryParameters3D.new()
var _up := PhysicsRayQueryParameters3D.new()
## Each body's transform before the last tick's step, for pose_skeleton.
var _before_step: Dictionary = {}


func _init() -> void:
	top_level = true
	add_to_group(GROUP)
	for ray in [_down, _up]:
		ray.collision_mask = Hitscan.WORLD_LAYER
		ray.hit_back_faces = false


## Builds the bodies over a skeleton's current pose, from its ragdoll shapes
## (RagdollShapes) or, where it has none, its hitbox capsules (HitboxSet),
## with the skeleton's bones in metres at unit_scale units each.
## velocity is how the body was moving; forward is the way it faced, flat;
## hit_direction and hit_bone, the killing round's way and the bone it went
## into, or zero and -1. Returns how many bodies it made: none and the
## skeleton is left to its animation.
func build(
	skeleton: Skeleton3D, capsules: Array[Dictionary], unit_scale: float,
	velocity: Vector3, forward: Vector3, hit_direction: Vector3 = Vector3.ZERO, hit_bone: int = -1
) -> int:
	clear()
	_skeleton = skeleton
	var by_lower := {}
	for index in skeleton.get_bone_count():
		by_lower[skeleton.get_bone_name(index).to_lower()] = index

	# The capsules in the world, by bone.
	var parts := {}
	for capsule in capsules:
		var bone: int = by_lower.get(String(capsule["bone"]).to_lower(), -1)
		if bone < 0:
			continue
		var bone_to_world := _bone_world(bone)
		var a: Vector3 = bone_to_world * (capsule["point0"] / unit_scale)
		var b: Vector3 = bone_to_world * (capsule["point1"] / unit_scale)
		if not parts.has(bone):
			parts[bone] = []
		parts[bone].append({"a": a, "b": b, "radius": float(capsule["radius"])})
	if parts.is_empty():
		return 0

	# Bones in index order, so every bone's parents come before it: with
	# hitboxes, a spine bone too close to the body below it, or a neck,
	# gives that body its capsules. CS2's own shapes are a body each.
	var own_shapes: bool = capsules[0].get("physics", false)
	_order.assign(parts.keys())
	_order.sort()
	var held := {}
	for bone in _order:
		var above := _parent_with(bone, parts)
		var host: int = _host[above] if above >= 0 else bone
		var lower := skeleton.get_bone_name(bone).to_lower()
		if above >= 0 and not own_shapes and (
			lower.contains(ALWAYS_FOLDS)
			or lower.contains(FOLDS) and _bone_world(bone).origin.distance_to(_bone_world(host).origin) < FOLD_DISTANCE
		):
			_host[bone] = host
			held[host].append_array(parts[bone])
		else:
			_host[bone] = bone
			held[bone] = parts[bone].duplicate()

	var volumes := {}
	var total_volume := 0.0
	for bone: int in held:
		var volume := 0.0
		for part: Dictionary in held[bone]:
			var r: float = part["radius"]
			volume += PI * r * r * ((part["a"] as Vector3).distance_to(part["b"]) + 4.0 / 3.0 * r)
		volumes[bone] = volume
		total_volume += volume

	var hit_host: int = _host.get(hit_bone, -1)
	for bone in _order:
		if _host[bone] != bone:
			continue
		var body := _make_body(bone, held[bone], TOTAL_MASS * volumes[bone] / total_volume)
		body.linear_velocity = velocity + hit_direction * BODY_SPEED
		if bone == hit_host:
			body.linear_velocity += hit_direction * HIT_SPEED
		bodies[bone] = body
	for bone in _order:
		_offsets[bone] = bodies[_host[bone]].global_transform.affine_inverse() * _bone_world(bone)

	# The joints are made with the bodies laid out as the skeleton stands at
	# rest, which is where their limits are measured from, then the bodies
	# go back to how it died.
	var died := {}
	for bone: int in bodies:
		var body: RigidBody3D = bodies[bone]
		died[bone] = body.global_transform
		body.global_transform = _rest_world(bone) * _offsets[bone].affine_inverse()
	forward = Vector3(forward.x, 0.0, forward.z)
	forward = forward.normalized() if forward.length_squared() > 1e-6 else Vector3.FORWARD
	for bone: int in bodies:
		var parent := _body_parent(bone)
		if parent >= 0:
			_join(parent, bone, forward)
	for bone: int in bodies:
		(bodies[bone] as RigidBody3D).global_transform = died[bone]
	_apart_where_inside()
	_pass_through_others()
	_lift_clear()
	return bodies.size()


## Takes the bodies away and leaves the skeleton where it lies.
func clear() -> void:
	for body: RigidBody3D in bodies.values():
		body.queue_free()
	for joint in get_children():
		if joint is Joint3D:
			joint.queue_free()
	bodies.clear()
	lifted = 0.0
	_offsets.clear()
	_order.clear()
	_host.clear()
	_before_step.clear()
	_skeleton = null


func _process(_delta: float) -> void:
	pose_skeleton()


## Parts found under the floor put back on it (_keep_over_floor), and where
## each body is before this tick's step moves it, to draw the skeleton
## between the two (pose_skeleton).
func _physics_process(_delta: float) -> void:
	_keep_over_floor()
	for body: RigidBody3D in bodies.values():
		_before_step[body] = body.global_transform


## Puts every bone that has a body where its body is. Parents first, so a
## bone between two bodies (a clavicle) rides the one above it. Each body is
## taken alpha of the way between its last two ticks (by default as far as
## the frame falls between them), as bodies alive are drawn, or it would
## move in steps of a 64 Hz tick.
func pose_skeleton(alpha: float = -1.0) -> void:
	if _skeleton == null or not is_instance_valid(_skeleton):
		return
	if alpha < 0.0:
		alpha = DrawClock.fraction()
	var world_to_skeleton := _skeleton.global_transform.affine_inverse()
	for bone in _order:
		var body: RigidBody3D = bodies[_host[bone]]
		var at := body.global_transform
		if _before_step.has(body):
			at = (_before_step[body] as Transform3D).interpolate_with(at, alpha)
		_skeleton.set_bone_global_pose(bone, world_to_skeleton * at * _offsets[bone])


func _bone_world(bone: int) -> Transform3D:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone)


## Where a bone would be with the skeleton standing at rest where it is.
func _rest_world(bone: int) -> Transform3D:
	return _skeleton.global_transform * _skeleton.get_bone_global_rest(bone)


## Two parts that start inside each other (a hand held against the chest)
## never collide: pushed apart from inside in one step, they would fling the
## body. Nor do two a joint apart with one between (_one_apart). Two parts
## joined at a joint are already kept from colliding by the joint
## (exclude_nodes_from_collision).
func _apart_where_inside() -> void:
	var bones: Array = bodies.keys()
	var shapes := bones.map(func(bone: int) -> Array: return _segments(bodies[bone]))
	for i in bones.size():
		for j in range(i + 1, bones.size()):
			if _one_apart(bones[i], bones[j]) or _touch(shapes[i], shapes[j]):
				(bodies[bones[i]] as RigidBody3D).add_collision_exception_with(bodies[bones[j]])


## Whether two bodies are a joint apart with one between (a forearm and the
## chest, a shin and the pelvis, the two thighs), which press on each other
## wherever the joint between them bends far, and would fight it.
func _one_apart(a: int, b: int) -> bool:
	var above_a := _body_parent(a)
	var above_b := _body_parent(b)
	return (above_a >= 0 and (above_a == above_b or _body_parent(above_a) == b)) \
		or (above_b >= 0 and _body_parent(above_b) == a)


## One dead body passes through another, as in CS2: every part of this one is
## made an exception for every part of each other body lying near it.
func _pass_through_others() -> void:
	if not is_inside_tree() or bodies.is_empty():
		return
	var here: Vector3 = (bodies.values()[0] as RigidBody3D).global_position
	for other: Node in get_tree().get_nodes_in_group(GROUP):
		if other == self or not other is Ragdoll or (other as Ragdoll).bodies.is_empty():
			continue
		var theirs: Array = (other as Ragdoll).bodies.values()
		if (theirs[0] as RigidBody3D).global_position.distance_to(here) > OTHERS_NEAR:
			continue
		for mine: RigidBody3D in bodies.values():
			for their: RigidBody3D in theirs:
				mine.add_collision_exception_with(their)


## A body's capsules in the world, each [one end, the other, radius].
static func _segments(body: RigidBody3D) -> Array:
	var found := []
	for collision in body.get_children():
		if collision is CollisionShape3D:
			var capsule := (collision as CollisionShape3D).shape as CapsuleShape3D
			var half := (collision as CollisionShape3D).global_basis.y.normalized() * (capsule.height / 2.0 - capsule.radius)
			var centre := (collision as CollisionShape3D).global_position
			found.append([centre - half, centre + half, capsule.radius])
	return found


static func _touch(a: Array, b: Array) -> bool:
	for one: Array in a:
		for two: Array in b:
			var closest := Geometry3D.get_closest_points_between_segments(one[0], one[1], two[0], two[1])
			if closest[0].distance_to(closest[1]) < one[2] + two[2]:
				return true
	return false


## Lifts the whole body straight up by as much as its deepest part is into
## the floor, or inside something standing on it, so that it starts clear.
## dust2's floor is one-sided: the solver pushes a part back out only while
## its centre is over a face, and a part inside a kerb touches none. So each
## part looks down from LIFT_REACH over it for the top of what it is in, and
## up for anything over it that it is only under (a ledge, a table), which it
## is not in and is left alone for.
func _lift_clear() -> void:
	if not is_inside_tree():
		return
	var most := 0.0
	for body: RigidBody3D in bodies.values():
		for collision in body.get_children():
			if collision is CollisionShape3D:
				most = maxf(most, _under(collision, LIFT_REACH, true))
	if most <= 0.0:
		return
	lifted = most + LIFT_MARGIN
	for body: RigidBody3D in bodies.values():
		body.global_position += Vector3.UP * lifted


## Puts back on top any part whose centre the last step left under the
## floor, before the one-sided floor lets it fall on through: a foot held at
## the end of its ankle's bend, pressed into a slope by the leg's weight,
## creeps down through it otherwise. Bodies at rest are left alone.
func _keep_over_floor() -> void:
	for body: RigidBody3D in bodies.values():
		if body.sleeping:
			continue
		var most := 0.0
		for collision in body.get_children():
			if collision is CollisionShape3D:
				most = maxf(most, _under(collision, (collision.shape as CapsuleShape3D).radius, false))
		if most > 0.0:
			body.global_position += Vector3.UP * (most + LIFT_MARGIN)
			body.linear_velocity.y = maxf(body.linear_velocity.y, 0.0)


## How far a part has to go up to be clear of the floor it is in, looking
## down from `reach` over its centre: for its lowest point (whole), or its
## centre. Zero when it is clear, or only under something (a ledge, a
## table), the underside of which is met first on the way up.
func _under(collision: CollisionShape3D, reach: float, whole: bool) -> float:
	var space := get_world_3d().direct_space_state
	var capsule := collision.shape as CapsuleShape3D
	var centre := collision.global_position
	var below := 0.0
	if whole:
		below = capsule.radius + (capsule.height / 2.0 - capsule.radius) * absf(collision.global_basis.y.normalized().y)
	_down.from = centre + Vector3.UP * reach
	_down.to = centre + Vector3.DOWN * below * 2.0
	var floor := space.intersect_ray(_down)
	if floor.is_empty():
		return 0.0
	var normal: Vector3 = floor["normal"]
	var top: Vector3 = floor["position"]
	if normal.y < 0.1:
		return 0.0
	if top.y > centre.y:
		_up.from = centre
		_up.to = top
		if not space.intersect_ray(_up).is_empty():
			return 0.0
	return maxf(top.y + below / normal.y - centre.y, 0.0)


func _make_body(bone: int, parts: Array, mass: float) -> RigidBody3D:
	# The body stands on its largest capsule, so its centre of mass is the
	# middle of the part rather than the joint.
	var largest: Dictionary = parts[0]
	for part: Dictionary in parts:
		if part["radius"] > largest["radius"]:
			largest = part
	var body := RigidBody3D.new()
	body.name = "Ragdoll_%s" % _skeleton.get_bone_name(bone)
	body.collision_layer = LAYER
	body.collision_mask = MASK
	body.mass = maxf(mass, 0.5)
	body.continuous_cd = true
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.1
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 1.0
	var material := PhysicsMaterial.new()
	material.friction = FRICTION
	material.bounce = 0.0
	body.physics_material_override = material
	add_child(body)
	body.global_transform = SkinnedHitboxes.capsule_transform(largest["a"], largest["b"])
	for part: Dictionary in parts:
		var collision := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = part["radius"]
		shape.height = (part["a"] as Vector3).distance_to(part["b"]) + 2.0 * shape.radius
		collision.shape = shape
		body.add_child(collision)
		collision.global_transform = SkinnedHitboxes.capsule_transform(part["a"], part["b"])
	body.add_constant_central_force(Vector3.DOWN * GRAVITY * body.mass)
	return body


## The body a bone rides, its own or the one it was folded into, or null.
func body_for(bone: int) -> RigidBody3D:
	return bodies.get(_host.get(bone, -1))


## The nearest bone above this one that has a body, or -1.
func _body_parent(bone: int) -> int:
	return _parent_with(bone, bodies)


## The nearest bone above this one that is a key of `has`, or -1.
func _parent_with(bone: int, has: Dictionary) -> int:
	var parent := _skeleton.get_bone_parent(bone)
	while parent >= 0 and not has.has(parent):
		parent = _skeleton.get_bone_parent(parent)
	return parent


## A joint's limits by its child bone's name: a JOINTS entry, or a HINGES
## one for a knee or an elbow.
static func joint_for(bone_name: String) -> Array:
	var lower := bone_name.to_lower()
	for hinge: Array in HINGES:
		if lower.contains(hinge[0]):
			return hinge
	for joint: Array in JOINTS:
		if lower.contains(joint[0]):
			return joint
	return DEFAULT_JOINT


## A joint at the child bone's head, made with the bodies where the skeleton
## has them at rest: a hinge for a knee or an elbow, and for the rest a
## joint whose twist axis runs along the child limb, from hanging straight
## down for an arm or a leg, and from its rest otherwise.
func _join(parent_bone: int, child_bone: int, forward: Vector3) -> void:
	var parent: RigidBody3D = bodies[parent_bone]
	var child: RigidBody3D = bodies[child_bone]
	var spec := joint_for(_skeleton.get_bone_name(child_bone))
	var pivot := _rest_world(child_bone).origin
	var limb := child.global_position - pivot
	if limb.length_squared() < 1e-6:
		limb = child.global_transform.basis.y
	limb = limb.normalized()

	var upper := pivot - parent.global_position
	var joint: Joint3D
	var rest := child.global_transform
	if spec.size() == 3:
		var axis := bend_axis(upper, limb, forward, spec[2])
		joint = _hinge(pivot, upper.normalized(), limb, axis, spec[1]) if axis != Vector3.ZERO else _limits(pivot, limb, forward, upper, DEFAULT_JOINT)
	else:
		# The joint is made with the limb where its limits are measured from:
		# for an arm or a leg, hanging.
		var hanging := Vector3.DOWN if spec[6] == &"down" else limb
		var turn := Quaternion(limb, hanging) if limb.dot(hanging) > -0.999 else Quaternion(forward, PI)
		child.global_transform = Transform3D(Basis(turn), pivot) * Transform3D(Basis.IDENTITY, -pivot) * rest
		joint = _limits(pivot, hanging, forward, upper, spec)
	_resist(joint, child.mass * JOINT_TORQUE)
	joint.name = "Joint_%s" % _skeleton.get_bone_name(child_bone)
	add_child(joint)
	joint.node_a = joint.get_path_to(parent)
	joint.node_b = joint.get_path_to(child)
	child.global_transform = rest


## The joint's friction: a motor on each axis it turns about, driving the
## turn toward standing still with no more than `torque`.
static func _resist(joint: Joint3D, torque: float) -> void:
	if joint is HingeJoint3D:
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
		joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
		# Given as an impulse a tick; Jolt takes it back to a torque.
		joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, torque / Engine.physics_ticks_per_second)
	elif joint is Generic6DOFJoint3D:
		for axis in ["x", "y", "z"]:
			joint.set("angular_motor_%s/enabled" % axis, true)
			joint.set("angular_motor_%s/target_velocity" % axis, 0.0)
			joint.set("angular_motor_%s/force_limit" % axis, torque)


## A joint about `limb` (its X, the twist) that lets the limb bend forward,
## back, out and in as far as `spec` says (a JOINTS entry). Its Z is the
## body's front, or up for a limb that already points forward (a foot, whose
## "forward" is its toes up); out is away from the parent body's middle.
func _limits(pivot: Vector3, limb: Vector3, forward: Vector3, upper: Vector3, spec: Array) -> Generic6DOFJoint3D:
	var front := forward if absf(limb.dot(forward)) < 0.7 else Vector3.UP
	var z := (front - limb * front.dot(limb)).normalized()
	var y := z.cross(limb)
	var joint := Generic6DOFJoint3D.new()
	joint.transform = Transform3D(Basis(limb, y, z), pivot)
	# Turning the limb about Y by +a takes it toward -Z, the back; about Z by
	# +a toward +Y. Godot counts a 6DOF's angles the other way round from the
	# child's turn: an allowed turn from lo to hi is a limit from -hi to -lo.
	var out_is_y := upper.dot(y) >= 0.0
	var turns := {
		"x": [-spec[1], spec[1]],
		"y": [-spec[2], spec[3]],
		"z": [-spec[5], spec[4]] if out_is_y else [-spec[4], spec[5]],
	}
	for axis: String in turns:
		joint.set("angular_limit_%s/enabled" % axis, true)
		joint.set("angular_limit_%s/lower_angle" % axis, deg_to_rad(-turns[axis][1]))
		joint.set("angular_limit_%s/upper_angle" % axis, deg_to_rad(-turns[axis][0]))
	return joint


## A hinge about `axis` (turning the lower limb about it bends the joint
## further), from straight to `most` degrees bent. Its limits are angles
## from the pose it is made in, and Godot counts a hinge's angle the other
## way round from the axis, so bending further is going negative.
func _hinge(pivot: Vector3, upper: Vector3, lower: Vector3, axis: Vector3, most: float) -> HingeJoint3D:
	var joint := HingeJoint3D.new()
	var z := (axis - lower * axis.dot(lower)).normalized()
	# The hinge turns about its Z.
	joint.transform = Transform3D(Basis(lower, z.cross(lower), z), pivot)
	# Negative for a joint bent the wrong way (a knee locked back), which may
	# straighten from there but not go further back.
	var bent := upper.signed_angle_to(lower, axis)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, bent - deg_to_rad(most))
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, maxf(bent, 0.0))
	if not on_jolt():
		joint.set_param(HingeJoint3D.PARAM_BIAS, JOINT_BIAS)
	return joint


## Whether the physics is Jolt's, as the project is set to. DEFAULT is Godot
## Physics in 4.7.
static func on_jolt() -> bool:
	return String(ProjectSettings.get_setting("physics/3d/physics_engine")) == "Jolt Physics"


## The axis a knee or an elbow bends about: rotating the lower limb about it
## bends the joint further. A limb already bent the right way says so
## itself; a straight one, or one bent the wrong way (a knee locked back),
## bends toward the way given, the body's back for a knee and its front for
## an elbow. Zero when there is nothing to go by.
static func bend_axis(upper: Vector3, lower: Vector3, forward: Vector3, toward: StringName) -> Vector3:
	upper = upper.normalized()
	lower = lower.normalized()
	var way := forward if toward == &"front" else -forward
	var anatomical := lower.cross(way)
	var bent := upper.cross(lower)
	if bent.length() > 0.17 and (anatomical.length_squared() < 1e-6 or bent.dot(anatomical) > 0.0):
		return bent.normalized()
	if anatomical.length_squared() < 1e-6:
		return Vector3.ZERO
	return anatomical.normalized()
