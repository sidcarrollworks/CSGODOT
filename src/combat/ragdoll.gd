class_name Ragdoll
extends Node3D

## A dead body falling as a body: a native Box3D body per bone with a shape,
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
## far as they go. Every other joint uses a circular swing cone inscribed
## inside the anatomical forward/back/out/in limits, plus a twist limit
## (reference/research/ragdoll-joints.md), measured from the body standing
## with its arms hanging, not from how it died: a hip killed mid-stride
## still goes no further back than a hip can. Every joint has friction, so a
## limb slows as it swings rather than flailing and spinning on.
##
## Bone proxies remain in Source inches; native bodies use metres in the
## shared world, stepped by GameWorld, with render interpolation here. They live
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
## stiff pieces instead.

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
var adapter: Box3DDrops
var _filters: Array[Node3D] = []
const METRES := 0.0254

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
	velocity: Vector3, forward: Vector3, hit_direction: Vector3 = Vector3.ZERO, hit_bone: int = -1,
	native_adapter: Box3DDrops = null
) -> int:
	clear()
	adapter = native_adapter if native_adapter != null else PhysicsQueries.adapter_for_node(self)
	if adapter == null and is_instance_valid(GameWorld.current) and GameWorld.configured_drop_physics() == "box3d":
		# A death can be requested by scene setup before the world's deferred
		# READY initializer. Its containing scene already owns the geometry.
		GameWorld.current.initialize_drop_physics()
		adapter = PhysicsQueries.adapter_for_node(self)
	if not is_instance_valid(adapter) or not adapter.initialized:
		push_error("A ragdoll requires the initialized shared Box3D world.")
		return 0
	adapter.pre_step.connect(_before_native_step)
	adapter.post_step.connect(_after_native_step)
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
		var body: Part = bodies[bone]
		died[bone] = body.global_transform
		body.global_transform = _rest_world(bone) * _offsets[bone].affine_inverse()
		body.write_native()
	forward = Vector3(forward.x, 0.0, forward.z)
	forward = forward.normalized() if forward.length_squared() > 1e-6 else Vector3.FORWARD
	for bone: int in bodies:
		var parent := _body_parent(bone)
		if parent >= 0:
			_join(parent, bone, forward)
	for bone: int in bodies:
		(bodies[bone] as Part).global_transform = died[bone]
		(bodies[bone] as Part).write_native()
	_apart_where_inside()
	_pass_through_others()
	_lift_clear()
	for body: Part in bodies.values():
		body.write_native()
	return bodies.size()


## Takes the bodies away and leaves the skeleton where it lies.
func clear() -> void:
	if is_instance_valid(adapter):
		if adapter.pre_step.is_connected(_before_native_step):
			adapter.pre_step.disconnect(_before_native_step)
		if adapter.post_step.is_connected(_after_native_step):
			adapter.post_step.disconnect(_after_native_step)
	for filter in _filters:
		if is_instance_valid(filter):
			filter.free()
	_filters.clear()
	for joint in get_children():
		if joint is Link:
			joint.free()
	for body: Part in bodies.values():
		body.free()
	bodies.clear()
	lifted = 0.0
	_offsets.clear()
	_order.clear()
	_host.clear()
	_before_step.clear()
	_skeleton = null
	adapter = null


## The body is wanted back, at a respawn or a side swap: the bodies go and
## the skeleton is written no more, from now and not from the frame's end,
## when the node is freed. Freed and no more, it posed the skeleton once
## again in that frame, where it lay, after the player had been put at its
## spawn: for a frame the body was drawn where it died and the gun it
## holds, which hangs on a bone the ragdoll does not write, where it
## spawned, in the air with nobody under it (Sid, 2026-09-29).
func let_go() -> void:
	clear()
	queue_free()


func _exit_tree() -> void:
	clear()


func _process(_delta: float) -> void:
	pose_skeleton()


## Parts found under the floor put back on it (_keep_over_floor), and where
## each body is before this tick's step moves it, to draw the skeleton
## between the two (pose_skeleton).
func _before_native_step(_tick: SimTick) -> void:
	_keep_over_floor()
	for body: Part in bodies.values():
		body.write_native()
		_before_step[body] = body.global_transform


func _after_native_step(_tick: SimTick) -> void:
	for body: Part in bodies.values():
		body.read_native()


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
		var body: Part = bodies[_host[bone]]
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
				(bodies[bones[i]] as Part).add_collision_exception_with(bodies[bones[j]])


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
	var here: Vector3 = (bodies.values()[0] as Part).global_position
	for other: Node in get_tree().get_nodes_in_group(GROUP):
		if other == self or not other is Ragdoll or (other as Ragdoll).bodies.is_empty():
			continue
		var theirs: Array = (other as Ragdoll).bodies.values()
		if (other as Ragdoll).adapter != adapter or (theirs[0] as Part).global_position.distance_to(here) > OTHERS_NEAR:
			continue
		for mine: Part in bodies.values():
			for their: Part in theirs:
				mine.add_collision_exception_with(their)


## A body's capsules in the world, each [one end, the other, radius].
static func _segments(body: Part) -> Array:
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
	for body: Part in bodies.values():
		for collision in body.get_children():
			if collision is CollisionShape3D:
				most = maxf(most, _under(collision, LIFT_REACH, true))
	if most <= 0.0:
		return
	lifted = most + LIFT_MARGIN
	for body: Part in bodies.values():
		body.global_position += Vector3.UP * lifted


## Puts back on top any part whose centre the last step left under the
## floor, before the one-sided floor lets it fall on through: a foot held at
## the end of its ankle's bend, pressed into a slope by the leg's weight,
## creeps down through it otherwise. Bodies at rest are left alone.
func _keep_over_floor() -> void:
	for body: Part in bodies.values():
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
	var ground := PhysicsQueries.intersect_ray(space, _down)
	if ground.is_empty():
		return 0.0
	var normal: Vector3 = ground["normal"]
	var top: Vector3 = ground["position"]
	if normal.y < 0.1:
		return 0.0
	if top.y > centre.y:
		_up.from = centre
		_up.to = top
		if not PhysicsQueries.intersect_ray(space, _up).is_empty():
			return 0.0
	return maxf(top.y + below / normal.y - centre.y, 0.0)


func _make_body(bone: int, parts: Array, mass: float) -> Part:
	# The body stands on its largest capsule, so its centre of mass is the
	# middle of the part rather than the joint.
	var largest: Dictionary = parts[0]
	for part: Dictionary in parts:
		if part["radius"] > largest["radius"]:
			largest = part
	var body := Part.new()
	body.ragdoll = self
	body.name = "Ragdoll_%s" % _skeleton.get_bone_name(bone)
	body.collision_layer = LAYER
	body.collision_mask = MASK
	body.mass = maxf(mass, 0.5)
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
	body.create_native()
	return body


## The body a bone rides, its own or the one it was folded into, or null.
func body_for(bone: int) -> Part:
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
	var parent: Part = bodies[parent_bone]
	var child: Part = bodies[child_bone]
	var spec := joint_for(_skeleton.get_bone_name(child_bone))
	var pivot := _rest_world(child_bone).origin
	var limb := child.global_position - pivot
	if limb.length_squared() < 1e-6:
		limb = child.global_transform.basis.y
	limb = limb.normalized()

	var upper := pivot - parent.global_position
	var joint: Link
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
		child.write_native()
		joint = _limits(pivot, hanging, forward, upper, spec)
	_resist(joint, child.mass * JOINT_TORQUE)
	joint.name = "Joint_%s" % _skeleton.get_bone_name(child_bone)
	add_child(joint)
	joint.node_a = joint.get_path_to(parent)
	joint.node_b = joint.get_path_to(child)
	_install_joint(joint, parent, child)
	child.global_transform = rest
	child.write_native()


## The joint's friction: a motor on each axis it turns about, driving the
## turn toward standing still with no more than `torque`.
static func _resist(joint: Link, torque: float) -> void:
	joint.torque = torque * METRES * METRES


## A joint about `limb` (its X, the twist) that lets the limb bend forward,
## back, out and in as far as `spec` says (a JOINTS entry). Its Z is the
## body's front, or up for a limb that already points forward (a foot, whose
## "forward" is its toes up); out is away from the parent body's middle.
func _limits(pivot: Vector3, limb: Vector3, forward: Vector3, upper: Vector3, spec: Array) -> Link:
	var front := forward if absf(limb.dot(forward)) < 0.7 else Vector3.UP
	var z := (front - limb * front.dot(limb)).normalized()
	var y := z.cross(limb)
	var joint := Link.new()
	# Native ball joints swing and twist about Z. Their single circular cone
	# cannot reproduce the legacy six-axis angular box. Use a conservative
	# cone offset toward the permitted bend, retaining the neutral pose.
	joint.transform = Transform3D(Basis(z, limb.cross(z), limb), pivot)
	var outward := y if upper.dot(y) >= 0.0 else -y
	var radius := 0.85 * minf((float(spec[2]) + float(spec[3])) * 0.5, (float(spec[4]) + float(spec[5])) * 0.5)
	var centre := Vector2((float(spec[2]) - float(spec[3])) * 0.5, (float(spec[4]) - float(spec[5])) * 0.5)
	if centre.length() > radius:
		centre = centre.limit_length(radius)
	var swing := limb.cross(z) * deg_to_rad(centre.x) + limb.cross(outward) * deg_to_rad(centre.y)
	joint.cone_offset = Basis(swing.normalized(), swing.length()) if swing.length_squared() > 1e-8 else Basis.IDENTITY
	joint.cone_angle = deg_to_rad(radius)
	joint.twist = deg_to_rad(float(spec[1]))
	return joint


## A hinge about `axis` (turning the lower limb about it bends the joint
## further), from straight to `most` degrees bent. Its limits are angles
## from the pose it is made in, in the native axis's positive sense.
func _hinge(pivot: Vector3, upper: Vector3, lower: Vector3, axis: Vector3, most: float) -> Link:
	var joint := Link.new()
	joint.is_hinge = true
	var z := (axis - lower * axis.dot(lower)).normalized()
	# The hinge turns about its Z.
	joint.transform = Transform3D(Basis(lower, z.cross(lower), z), pivot)
	# Negative for a joint bent the wrong way (a knee locked back), which may
	# straighten from there but not go further back.
	var bent := upper.signed_angle_to(lower, axis)
	# Native angles are body B relative to A, in the axis's positive sense.
	joint.lower = -maxf(bent, 0.0)
	joint.upper = deg_to_rad(most) - bent
	return joint


func _install_joint(link: Link, parent: Part, child: Part) -> void:
	var native := ClassDB.instantiate(&"Box3DHingeJoint" if link.is_hinge else &"Box3DBallJoint") as Node3D
	link.native = native
	native.transform = _to_native(link.global_transform)
	native.set(&"body_a", parent.native.get_path())
	native.set(&"body_b", child.native.get_path())
	native.set(&"collide_connected", false)
	if link.is_hinge:
		native.set(&"limit_enabled", true)
		native.set(&"lower_limit", link.lower)
		native.set(&"upper_limit", link.upper)
		native.set(&"motor_enabled", true)
		native.set(&"motor_speed", 0.0)
		native.set(&"max_motor_torque", link.torque)
	else:
		native.set(&"cone_limit_enabled", true)
		native.set(&"cone_angle", link.cone_angle)
		native.set(&"twist_limit_enabled", true)
		native.set(&"twist_lower", -link.twist)
		native.set(&"twist_upper", link.twist)
		native.set(&"friction_torque", link.torque)
	adapter.native_world.add_child(native)
	# The referenced bodies are already ready, so native READY creates the
	# joint immediately at anatomical rest, before restoring the death pose.
	assert(native.call(&"is_joint_valid"), "Ragdoll joint must exist before the first simulation tick.")
	if not link.is_hinge:
		var centred := Transform3D(link.cone_offset * link.global_basis, link.global_position)
		native.call(&"set_local_frame_a", _to_native(parent.global_transform.affine_inverse() * centred))
	parent.exceptions.append(child)
	child.exceptions.append(parent)


func _exclude(a: Part, b: Part) -> void:
	if a.exceptions.has(b) or not is_instance_valid(a.native) or not is_instance_valid(b.native):
		return
	var native := ClassDB.instantiate(&"Box3DFilterJoint") as Node3D
	native.set(&"body_a", a.native.get_path())
	native.set(&"body_b", b.native.get_path())
	adapter.native_world.add_child(native)
	assert(native.call(&"is_joint_valid"), "Ragdoll collision exclusion must exist before stepping.")
	_filters.append(native)
	a.exceptions.append(b)
	b.exceptions.append(a)


static func _to_native(at: Transform3D) -> Transform3D:
	return Transform3D(at.basis.orthonormalized(), at.origin * METRES)


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


## Presentation/inspection proxy in Source inches. The only simulated body
## is native, beneath the shared Box3DWorld. Shape children here are metadata
## for bone placement and floor recovery, not Godot collision bodies.
class Part:
	extends Node3D
	var ragdoll: Ragdoll
	var native: Node3D
	var mass := 1.0
	var collision_layer := LAYER
	var collision_mask := MASK
	var exceptions: Array[Part] = []
	var _last_pose := Transform3D.IDENTITY
	var linear_velocity: Vector3:
		get:
			return (native.call(&"get_linear_velocity") as Vector3) / METRES if is_instance_valid(native) else Vector3.ZERO
		set(value):
			if is_instance_valid(native):
				native.call(&"set_linear_velocity", value * METRES)
	var angular_velocity: Vector3:
		get:
			return native.call(&"get_angular_velocity") as Vector3 if is_instance_valid(native) else Vector3.ZERO
		set(value):
			if is_instance_valid(native):
				native.call(&"set_angular_velocity", value)
	var sleeping: bool:
		get:
			return not bool(native.call(&"is_awake")) if is_instance_valid(native) else true
		set(value):
			if is_instance_valid(native):
				native.call(&"set_awake", not value)
	func create_native() -> void:
		native = ClassDB.instantiate(&"Box3DBody") as Node3D
		native.name = name
		native.transform = Ragdoll._to_native(global_transform)
		native.set(&"body_type", ClassDB.class_get_integer_constant(&"Box3DBody", &"DYNAMIC"))
		native.set(&"collision_layer", collision_layer)
		native.set(&"collision_mask", collision_mask)
		native.set(&"linear_damping", 0.1)
		native.set(&"angular_damping", 1.0)
		native.set(&"continuous", true)
		native.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		for collision: Node in get_children():
			if not collision is CollisionShape3D:
				continue
			var shape := (collision as CollisionShape3D).shape as CapsuleShape3D
			var capsule := ClassDB.instantiate(&"Box3DCollisionShape") as Node3D
			capsule.set(&"shape_type", ClassDB.class_get_integer_constant(&"Box3DCollisionShape", &"CAPSULE"))
			capsule.set(&"capsule_radius", shape.radius * METRES)
			capsule.set(&"capsule_height", shape.height * METRES)
			capsule.set(&"friction", FRICTION)
			capsule.set(&"restitution", 0.0)
			capsule.set(&"collision_layer", collision_layer)
			capsule.set(&"collision_mask", collision_mask)
			capsule.transform = Ragdoll._to_native((collision as Node3D).transform)
			native.add_child(capsule)
		ragdoll.adapter.native_world.add_child(native)
		var data: Dictionary = native.call(&"get_mass_data")
		var ratio := mass / maxf(float(data["mass"]), 1e-8)
		native.call(&"set_mass_data", mass, data["center"], (data["inertia"] as Basis) * ratio)
		_last_pose = global_transform

	func write_native() -> void:
		if not is_instance_valid(native) or global_transform.is_equal_approx(_last_pose):
			return
		var velocity := linear_velocity
		var spin := angular_velocity
		native.call(&"teleport", Ragdoll._to_native(global_transform))
		linear_velocity = velocity
		angular_velocity = spin
		_last_pose = global_transform

	func read_native() -> void:
		if not is_instance_valid(native):
			return
		var solved := native.global_transform
		global_transform = Transform3D(solved.basis, solved.origin / METRES)
		_last_pose = global_transform

	func add_collision_exception_with(other: Part) -> void:
		ragdoll._exclude(self, other)

	func get_collision_exceptions() -> Array[Part]:
		return exceptions.duplicate()

	func _exit_tree() -> void:
		if is_instance_valid(native):
			native.free()
		native = null


## The anatomical frame in inches; native holds the actual solver joint.
class Link:
	extends Node3D
	var native: Node3D
	var node_a: NodePath
	var node_b: NodePath
	var is_hinge := false
	var lower := 0.0
	var upper := 0.0
	var twist := 0.0
	var cone_angle := 0.0
	var cone_offset := Basis.IDENTITY
	var torque := 0.0

	func _exit_tree() -> void:
		if is_instance_valid(native):
			native.free()
		native = null
