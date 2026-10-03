class_name GrenadeFlight
extends RefCounted

## Source-unit flight from the September 2026 CS2 audit. Default collision
## is an axis-aligned four-inch box; the 64 Hz wrapper runs two 1/128 s
## steps. PhysicsQueries keeps geometric flight time separate from clearance.
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var previous_position := Vector3.ZERO
var at_rest := false
var blocked_start := false
var bounces := 0
var landed_normal := Vector3.ZERO
var landed_position := Vector3.ZERO
var detonate_floor_y := INF
var touches: Array[Dictionary] = []
var _query := PhysicsShapeQueryParameters3D.new()
var _zero_updates := 0

## A bounded corner fallback. Source's callback performs additional traces;
## this guard prevents an unresolved corner from looping inside one tick.
const MOST_SWEEPS := 4
const PHYSICS_STEP := 1.0 / 128.0


func _init() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * GrenadeRules.RADIUS * 2.0
	_query.shape = box
	_query.margin = 0.0
	_query.collision_mask = GrenadeRules.COLLIDE_MASK


## Center is the pawn's collision center. Synthetic throws without a pawn
## default to eye as their trace origin; ordinary player throws pass it.
static func throw_from(
	space: PhysicsDirectSpaceState3D, weapon_class: String, eye: Vector3, yaw: float, pitch: float,
	thrower_velocity: Vector3, strength: float, exclude: Array[RID] = [], center := Vector3.INF
) -> GrenadeFlight:
	var grenade := GrenadeFlight.new()
	if GrenadeRules.is_fire(weapon_class):
		grenade.detonate_floor_y = cos(deg_to_rad(GrenadeRules.MOLOTOV_MAX_SLOPE_DEGREES))
	strength = GrenadeRules.launch_strength(strength)
	# Convert Source's positive-down pitch before its wrap and lift.
	var source_pitch := -pitch
	if source_pitch > 90.0:
		source_pitch -= 360.0
	if source_pitch < -90.0:
		source_pitch += 360.0
	source_pitch -= (90.0 - absf(source_pitch)) * GrenadeRules.THROW_LIFT_DEGREES / 90.0
	var forward := PlayerInput.aim_direction(yaw, -source_pitch)
	grenade.velocity = forward * throw_speed(weapon_class, strength) \
		+ thrower_velocity * GrenadeRules.THROWER_VELOCITY_SHARE
	var hand := eye + Vector3.UP * (strength * GrenadeRules.RELEASE_DROP - GrenadeRules.RELEASE_DROP) \
		+ forward * GrenadeRules.RELEASE_AHEAD
	var start := center if center.is_finite() else eye
	var free := _sweep(space, start, hand - start, exclude, 2.02)
	grenade.position = free["end"]
	grenade.blocked_start = free["blocked_start"]
	if grenade.blocked_start:
		grenade.stop()
	grenade.previous_position = grenade.position
	return grenade


static func throw_speed(weapon_class: String, strength: float) -> float:
	var speed := clampf(GrenadeRules.throw_speed(weapon_class) * GrenadeRules.THROW_SPEED_SCALE, 15.0, 750.0)
	return speed * (clampf(strength, 0.0, 1.0) * 0.7 + GrenadeRules.THROW_POWER_MIN)


static func physics_steps(dt: float) -> int:
	var ratio := dt * 128.0
	var count := int(ratio)
	# Recovered wrapper fallback for non-integral frame intervals.
	if count > 0 and ratio - float(count) > 0.0001:
		return 1
	return maxi(count, 1)


func step(space: PhysicsDirectSpaceState3D, dt: float, exclude: Array[RID] = []) -> void:
	previous_position = position
	touches.clear()
	landed_normal = Vector3.ZERO
	if at_rest or dt <= 0.0:
		return
	_query.exclude = exclude
	var count := physics_steps(dt)
	var step_dt := dt if count == 1 else PHYSICS_STEP
	for substep in count:
		_step(space, step_dt)
		if at_rest:
			break
	_zero_updates = _zero_updates + 1 if velocity.is_zero_approx() else 0
	if _zero_updates >= 9:
		stop()


func _step(space: PhysicsDirectSpaceState3D, dt: float) -> void:
	var gravity := GrenadeRules.SV_GRAVITY * GrenadeRules.GRAVITY_SCALE
	var start_velocity := velocity
	velocity.y -= gravity * dt
	var motion := (start_velocity + velocity) * 0.5 * dt
	var remaining := dt
	for sweep in MOST_SWEEPS:
		if motion.length_squared() < 1e-12:
			break
		var hit := _trace(space, position, motion, _query)
		position = hit["end"]
		if not hit["hit"]:
			break
		if hit["blocked_start"]:
			blocked_start = true
			stop()
			break
		var normal: Vector3 = hit["normal"]
		var player := hit.get("collider") as PlayerSim
		if player != null:
			var radial: Vector3 = (position - hit["offset"] - player.grenade_center()).normalized()
			if not radial.is_zero_approx():
				normal = radial
		# Contact locations exclude the bridge's normal push, for events and
		# trajectory comparisons. That push takes none of the step's time.
		touches.append({"position": position - hit["offset"], "normal": normal,
			"surface": hit.get("surface", ""), "player": player != null})
		if normal.y >= detonate_floor_y and player == null:
			landed_normal = normal
			landed_position = hit.get("point", position - Vector3.UP * GrenadeRules.RADIUS)
			stop()
			break
		_bounce(normal, player != null)
		if at_rest:
			break
		var speed_squared := velocity.length_squared()
		# The repo's static world and player hulls are standable. More Source2
		# entity class/base-velocity branches remain comparison work.
		if normal.y > GrenadeRules.FLOOR_NORMAL_Y or (normal.y > 0.1 and speed_squared < GrenadeRules.REST_SPEED * GrenadeRules.REST_SPEED):
			landed_normal = normal
			landed_position = hit.get("point", position - Vector3.UP * GrenadeRules.RADIUS)
			if speed_squared > 96000.0:
				var outward := velocity.normalized().dot(normal)
				if outward > 0.5:
					velocity *= 1.5 - outward
			if speed_squared < GrenadeRules.REST_SPEED * GrenadeRules.REST_SPEED:
				stop()
				break
		remaining *= 1.0 - float(hit["fraction"])
		motion = velocity * remaining


func stop() -> void:
	velocity = Vector3.ZERO
	at_rest = true


## Surface elasticity and the separate one-time enemy body hit are distinct
## paths. A player surface does not multiply every bounce by 0.3.
func _bounce(normal: Vector3, _off_player: bool) -> void:
	var push := maxf(-velocity.dot(normal) * 2.0, 0.0) + GrenadeRules.CLIP_PUSH
	velocity = (velocity + normal * push) * GrenadeRules.ELASTICITY
	if bounces >= GrenadeRules.MOST_BOUNCES:
		stop()
	else:
		bounces += 1


static func _trace(space: PhysicsDirectSpaceState3D, from: Vector3, motion: Vector3, query: PhysicsShapeQueryParameters3D) -> Dictionary:
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = motion
	var hit := PhysicsQueries.projectile_trace(space, query)
	# Retained for existing trajectory callers; this is now flight fraction,
	# never a motion-direction backoff that consumes collision time.
	hit["safe"] = hit["fraction"]
	var collider := hit.get("collider") as CollisionObject3D
	hit["player"] = collider is PlayerSim
	var surface := ""
	if collider != null and hit.has("shape"):
		var owner_id := collider.shape_find_owner(int(hit["shape"]))
		var shape_node := collider.shape_owner_get_owner(owner_id)
		if shape_node != null:
			surface = shape_node.name
	hit["surface"] = surface
	if not hit["hit"]:
		hit.erase("normal")
	return hit


static func _sweep(space: PhysicsDirectSpaceState3D, from: Vector3, motion: Vector3, exclude: Array[RID], radius: float = GrenadeRules.RADIUS) -> Dictionary:
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * radius * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.margin = 0.0
	query.collision_mask = GrenadeRules.COLLIDE_MASK
	query.exclude = exclude
	return _trace(space, from, motion, query)
