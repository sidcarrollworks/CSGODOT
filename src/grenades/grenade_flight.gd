class_name GrenadeFlight
extends RefCounted

## A grenade's flight, from the hand to where it lies still: where it is and
## how fast it is going, run forward one tick at a time. The grenade entity
## (GrenadeEntity) holds one and decides what happens when; whatever draws
## it reads previous_position and position and draws a frame between the
## two.
##
## It flies on its own fixed-step physics, as a Source projectile does
## (MOVETYPE_FLYGRAVITY): a fraction of sv_gravity, a small sphere swept
## through the world each tick, and off whatever it meets at a share of its
## speed, until a floor leaves it too slow to bounce and it lies still. It
## meets the world, players' hulls and the map's grenade clips, never the
## player clips or its thrower (GrenadeRules.COLLIDE_MASK and the exclude
## list).

var position := Vector3.ZERO
var velocity := Vector3.ZERO
## Where it was at the end of the tick before, for drawing between the two.
var previous_position := Vector3.ZERO
## Lying still: no longer moving, and nothing moves it.
var at_rest: bool = false
## How many times it has bounced, and the last floor it met in the last
## tick (zero if none), for a molotov to go off on.
var bounces: int = 0
var landed_normal := Vector3.ZERO
## Every surface met in the last tick, as {position, normal, surface,
## player}, for a grenade_bounce each.
var touches: Array[Dictionary] = []

## How many sweeps a tick may take: one, and one more for each bounce in it.
const MOST_SWEEPS := 4


## A grenade thrown from eye, looking yaw and pitch (degrees, pitch up
## positive, as UserCmd has them), by someone moving at thrower_velocity,
## at a strength from GrenadeRules.strength_for: CS:GO's throw (G1). It
## leaves the hand a little ahead of the eyes, and lower for a lob, or
## wherever short of that the world lets it.
static func throw_from(
	space: PhysicsDirectSpaceState3D, weapon_class: String, eye: Vector3, yaw: float, pitch: float,
	thrower_velocity: Vector3, strength: float, exclude: Array[RID] = []
) -> GrenadeFlight:
	var grenade := GrenadeFlight.new()
	var lifted := pitch + (90.0 - absf(pitch)) * GrenadeRules.THROW_LIFT_DEGREES / 90.0
	var forward := PlayerInput.aim_direction(yaw, lifted)
	grenade.velocity = forward * throw_speed(weapon_class, strength) \
		+ thrower_velocity * GrenadeRules.THROWER_VELOCITY_SHARE
	var hand := eye + Vector3.UP * (strength * GrenadeRules.RELEASE_DROP - GrenadeRules.RELEASE_DROP) \
		+ forward * GrenadeRules.RELEASE_AHEAD
	var free := _sweep(space, eye, hand - eye, exclude)
	grenade.position = eye + (hand - eye) * float(free["safe"])
	grenade.previous_position = grenade.position
	return grenade


## How fast a grenade leaves the hand at a strength, before the thrower's
## own speed is added.
static func throw_speed(weapon_class: String, strength: float) -> float:
	var speed := clampf(GrenadeRules.throw_speed(weapon_class) * GrenadeRules.THROW_SPEED_SCALE, 15.0, 750.0)
	return speed * (strength * (1.0 - GrenadeRules.THROW_POWER_MIN) + GrenadeRules.THROW_POWER_MIN)


## One tick of flight: moved, bounced off whatever it met, and put down if
## a floor left it too slow to go on.
func step(space: PhysicsDirectSpaceState3D, dt: float, exclude: Array[RID] = []) -> void:
	previous_position = position
	touches.clear()
	landed_normal = Vector3.ZERO
	if at_rest:
		return
	# Half the tick's gravity before the move and half after, as Source
	# splits it, so the arc does not depend on the tick rate.
	var gravity := GrenadeRules.SV_GRAVITY * GrenadeRules.GRAVITY_SCALE
	var start_velocity := velocity
	velocity.y -= gravity * dt
	var motion := (start_velocity + velocity) * 0.5 * dt
	for sweep in MOST_SWEEPS:
		if motion.length_squared() < 1e-8:
			break
		var hit := _sweep(space, position, motion, exclude)
		var safe: float = hit["safe"]
		position += motion * safe
		if not hit.has("normal"):
			break
		var normal: Vector3 = hit["normal"]
		_bounce(normal, bool(hit["player"]))
		touches.append({
			"position": position, "normal": normal,
			"surface": String(hit.get("surface", "")), "player": hit["player"],
		})
		if normal.y > GrenadeRules.FLOOR_NORMAL_Y:
			landed_normal = normal
			if velocity.length() < GrenadeRules.REST_SPEED:
				velocity = Vector3.ZERO
				at_rest = true
				break
		# What is left of the tick goes on at the new velocity, a little off
		# the surface so the next sweep does not start in it.
		position += normal * 0.01
		motion = velocity * dt * (1.0 - safe)
		if safe <= 0.0 and sweep > 0:
			# Wedged: nowhere to go this tick.
			break


## Off a surface the way Source bounces a grenade: the velocity reflected in
## the surface (ClipVelocity with an overbounce of 2), and a share of it
## kept, less off a player.
func _bounce(normal: Vector3, off_player: bool) -> void:
	bounces += 1
	var into := velocity.dot(normal)
	if into < 0.0:
		velocity -= normal * into * 2.0
	velocity *= GrenadeRules.ELASTICITY * (GrenadeRules.PLAYER_ELASTICITY if off_player else 1.0)


## Sweeps the grenade's sphere from a point along a motion: how far it got
## (safe, 0 to 1), and what it met there if anything (normal, surface, and
## whether it was a player).
static func _sweep(
	space: PhysicsDirectSpaceState3D, from: Vector3, motion: Vector3, exclude: Array[RID]
) -> Dictionary:
	var shape := SphereShape3D.new()
	shape.radius = GrenadeRules.RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = motion
	query.collision_mask = GrenadeRules.COLLIDE_MASK
	query.exclude = exclude
	var fractions := space.cast_motion(query)
	if fractions.is_empty() or fractions[1] >= 1.0:
		return {"safe": 1.0}
	var safe: float = fractions[0]
	# What it met: the contact just past where it could go.
	query.transform = Transform3D(Basis.IDENTITY, from + motion * fractions[1])
	query.motion = Vector3.ZERO
	var rest := space.get_rest_info(query)
	if rest.is_empty():
		return {"safe": safe}
	var collider := instance_from_id(int(rest.get("collider_id", 0)))
	var surface := ""
	if collider is CollisionObject3D and rest.has("shape"):
		var owner_id: int = (collider as CollisionObject3D).shape_find_owner(int(rest["shape"]))
		var shape_node := (collider as CollisionObject3D).shape_owner_get_owner(owner_id)
		if shape_node != null:
			surface = shape_node.name
	var normal: Vector3 = rest["normal"]
	if normal.length_squared() < 1e-6:
		normal = -motion.normalized()
	return {
		"safe": safe, "normal": normal.normalized(), "surface": surface,
		"player": collider is PlayerSim,
	}
