class_name Ragdoll
extends Node3D

## A dead body falling as a body: a rigid body per bone that has hitboxes,
## shaped by those capsules, jointed to the nearest such bone above it, and
## the skeleton posed from them every frame until it is taken away.
##
## CS2 ragdolls its dead the same way, from a physics description of its
## own. That one is not extracted yet; the hitbox capsules are the game's
## own shapes for the same bones, and close to the ragdoll's, so they stand
## in for it. The joints are cones, limbs swinging within them: a knee and
## an elbow bend one way, so their cones are set around a half-bent limb
## rather than a straight one.
##
## The bodies are in world units, unscaled, like the hitboxes: the model is
## scaled up from metres and physics bodies do not take a scale. They live
## on their own layer and touch only the world, so a corpse is not in the
## way of rounds or of the living.
##
## A spine bone that starts close to the body below it gets no body of its
## own: its capsules join that body and it rides it. The spine is four bones
## over the pelvis, a hand's width apart, and a chain of short bodies jointed
## that close together throws the physics solver into a fit (the body tangles
## and flies off), so the torso falls as two or three stiff pieces instead.
## The joints also pull their bodies back together gently (JOINT_BIAS), for
## the same reason.

## The physics layer the bodies are on (the fifth), and what they touch.
const LAYER := 16
const MASK := Hitscan.WORLD_LAYER
## The world's gravity, in units per second squared (MovementConfig's).
const GRAVITY := 800.0
## The body's weight in all, shared between the parts by their size. Only
## the ratios matter, to the joints.
const TOTAL_MASS := 80.0

## How far each joint lets its bone swing and twist, in degrees, by bone
## name; and for a knee or elbow, how far the middle of its cone is bent
## from straight, and which way.
const JOINTS := [
	# [name contains, swing, twist, bend, bends toward]
	["head", 30.0, 25.0, 0.0, &""],
	["neck", 25.0, 20.0, 0.0, &""],
	["spine", 20.0, 15.0, 0.0, &""],
	["arm_upper", 70.0, 30.0, 0.0, &""],
	["arm_lower", 65.0, 10.0, 65.0, &"front"],
	["hand", 35.0, 15.0, 0.0, &""],
	["leg_upper", 50.0, 15.0, 0.0, &""],
	["leg_lower", 60.0, 5.0, 60.0, &"back"],
	["ankle", 25.0, 10.0, 0.0, &""],
]
const DEFAULT_JOINT := ["", 30.0, 15.0, 0.0, &""]
## How much of the way back together a joint pulls its two bodies each step,
## when they drift apart. Godot's default is 0.3; at that, one fall in twelve
## of a stand-in body exploded, and from 0.2 down none did, the joints still
## holding within half a unit.
const JOINT_BIAS := 0.15

## How close, in units, a spine bone can start to the bone its body stands
## on and still have a body of its own. Closer and it joins that body. Only
## the spine folds: the hips and shoulders also start close to the torso, but
## a leg or an arm has to swing.
const FOLD_DISTANCE := 8.0
const FOLDS := "spine"

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


func _init() -> void:
	top_level = true


## Builds the bodies over a skeleton's current pose, from its hitbox capsules
## (HitboxSet), with the skeleton's bones in metres at unit_scale units each.
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

	# Bones in index order, so every bone's parents come before it: a spine
	# bone too close to the body below it gives that body its capsules.
	_order.assign(parts.keys())
	_order.sort()
	var held := {}
	for bone in _order:
		var above := _parent_with(bone, parts)
		var host: int = _host[above] if above >= 0 else bone
		if (
			above >= 0 and skeleton.get_bone_name(bone).to_lower().contains(FOLDS)
			and _bone_world(bone).origin.distance_to(_bone_world(host).origin) < FOLD_DISTANCE
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

	for bone: int in bodies:
		var parent := _body_parent(bone)
		if parent >= 0:
			_join(parent, bone, forward)
	return bodies.size()


## Takes the bodies away and leaves the skeleton where it lies.
func clear() -> void:
	for body: RigidBody3D in bodies.values():
		body.queue_free()
	for joint in get_children():
		if joint is Joint3D:
			joint.queue_free()
	bodies.clear()
	_offsets.clear()
	_order.clear()
	_host.clear()
	_skeleton = null


func _process(_delta: float) -> void:
	pose_skeleton()


## Puts every bone that has a body where its body is. Parents first, so a
## bone between two bodies (a clavicle) rides the one above it.
func pose_skeleton() -> void:
	if _skeleton == null or not is_instance_valid(_skeleton):
		return
	var world_to_skeleton := _skeleton.global_transform.affine_inverse()
	for bone in _order:
		var body: RigidBody3D = bodies[_host[bone]]
		_skeleton.set_bone_global_pose(bone, world_to_skeleton * body.global_transform * _offsets[bone])


func _bone_world(bone: int) -> Transform3D:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone)


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
	material.friction = 0.9
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


static func joint_for(bone_name: String) -> Array:
	var lower := bone_name.to_lower()
	for joint: Array in JOINTS:
		if lower.contains(joint[0]):
			return joint
	return DEFAULT_JOINT


## A cone joint at the child bone's head: its twist axis along the child
## limb, the cone around it. A cone is centred on the pose the bodies are in
## when it is made, so for a knee or an elbow the child is turned to the
## middle of its bend first, and turned back once the joint holds.
func _join(parent_bone: int, child_bone: int, forward: Vector3) -> void:
	var parent: RigidBody3D = bodies[parent_bone]
	var child: RigidBody3D = bodies[child_bone]
	var spec := joint_for(_skeleton.get_bone_name(child_bone))
	var pivot := _bone_world(child_bone).origin
	var limb := child.global_position - pivot
	if limb.length_squared() < 1e-6:
		limb = child.global_transform.basis.y
	limb = limb.normalized()

	var actual := child.global_transform
	var bend: float = spec[3]
	if bend > 0.0:
		var axis := bend_axis(pivot - parent.global_position, limb, forward, spec[4])
		if axis != Vector3.ZERO:
			var upper := (pivot - parent.global_position).normalized()
			var already := rad_to_deg(upper.angle_to(limb))
			var turn := deg_to_rad(bend - already)
			var about_pivot := Transform3D(Basis(axis, turn), Vector3.ZERO)
			var centred := Transform3D(Basis.IDENTITY, pivot) * about_pivot * Transform3D(Basis.IDENTITY, -pivot)
			child.global_transform = centred * actual
			limb = Basis(axis, turn) * limb

	var joint := ConeTwistJoint3D.new()
	joint.name = "Joint_%s" % _skeleton.get_bone_name(child_bone)
	# The twist axis is the joint's X.
	var x := limb
	var y := x.cross(Vector3.UP)
	if y.length_squared() < 1e-6:
		y = x.cross(Vector3.FORWARD)
	y = y.normalized()
	joint.transform = Transform3D(Basis(x, y, x.cross(y)), pivot)
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(spec[1]))
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(spec[2]))
	joint.set_param(ConeTwistJoint3D.PARAM_BIAS, JOINT_BIAS)
	joint.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.8)
	joint.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)
	add_child(joint)
	joint.node_a = joint.get_path_to(parent)
	joint.node_b = joint.get_path_to(child)
	child.global_transform = actual


## The axis a knee or an elbow bends about: rotating the lower limb about it
## bends the joint further. A limb already bent says so itself; a straight
## one bends toward the way given, the body's back for a knee and its front
## for an elbow. Zero when there is nothing to go by.
static func bend_axis(upper: Vector3, lower: Vector3, forward: Vector3, toward: StringName) -> Vector3:
	upper = upper.normalized()
	lower = lower.normalized()
	var axis := upper.cross(lower)
	if axis.length() > 0.17:
		return axis.normalized()
	var way := forward if toward == &"front" else -forward
	axis = lower.cross(way)
	if axis.length_squared() < 1e-6:
		return Vector3.ZERO
	return axis.normalized()
