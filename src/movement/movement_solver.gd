class_name MovementSolver
extends RefCounted

## The Quake/Source acceleration model, as pure functions.
##
## Nothing in here touches the scene tree or the physics server, so all of it
## is directly testable headless (see tests/test_movement_solver.gd). The
## collision half of movement lives in player_body.gd, which is the part that
## needs a physics world.
##
## These are ports of Source's CGameMovement. The odd-looking details are
## deliberate and load-bearing:
##
##   - air_accelerate clamps addspeed by the CLAMPED wish speed but scales
##     accelspeed by the UNCLAMPED one. That asymmetry is air strafing.
##   - friction uses stop_speed as a floor on the control value, which is what
##     makes stopping crisp rather than sliding.
##   - clip_velocity does a second pass when the result still points into the
##     plane, which is what keeps you from sinking into creases.

## Applies ground friction. No-op in the air: Source only drops speed on the
## ground, air drag does not exist.
static func apply_friction(
	velocity: Vector3,
	on_ground: bool,
	surface_friction: float,
	cfg: MovementConfig,
	dt: float
) -> Vector3:
	var speed := velocity.length()
	if speed < 0.1:
		return velocity
	var drop := 0.0
	if on_ground:
		var f := cfg.friction * surface_friction
		var control: float = cfg.stop_speed if speed < cfg.stop_speed else speed
		drop = control * f * dt
	var new_speed: float = maxf(speed - drop, 0.0)
	return velocity * (new_speed / speed)


## Ground acceleration toward wish_dir.
static func accelerate(
	velocity: Vector3,
	wish_dir: Vector3,
	wish_speed: float,
	accel: float,
	surface_friction: float,
	dt: float
) -> Vector3:
	var current_speed := velocity.dot(wish_dir)
	var add_speed := wish_speed - current_speed
	if add_speed <= 0.0:
		return velocity
	var accel_speed := accel * dt * wish_speed * surface_friction
	if accel_speed > add_speed:
		accel_speed = add_speed
	return velocity + wish_dir * accel_speed


## Air acceleration toward wish_dir.
##
## The clamp is the whole trick. You can only ever add speed up to
## air_max_wishspeed ALONG the wish direction, so holding W in the air does
## nothing once you are moving forward faster than 30 u/s. But if you point the
## wish direction sideways relative to your velocity, current_speed along it is
## near zero, so you get the full addition and your speed vector rotates while
## growing. That is an air strafe, and it is also a surf.
static func air_accelerate(
	velocity: Vector3,
	wish_dir: Vector3,
	wish_speed: float,
	accel: float,
	surface_friction: float,
	cfg: MovementConfig,
	dt: float
) -> Vector3:
	var wish_spd: float = minf(wish_speed, cfg.air_max_wishspeed)
	var current_speed := velocity.dot(wish_dir)
	var add_speed := wish_spd - current_speed
	if add_speed <= 0.0:
		return velocity
	# Deliberately the UNCLAMPED wish_speed here. This matches Source.
	var accel_speed := accel * wish_speed * dt * surface_friction
	if accel_speed > add_speed:
		accel_speed = add_speed
	return velocity + wish_dir * accel_speed


## Source's ClipVelocity: remove the component of velocity heading into a
## plane, then correct again if floating point left it still heading in.
static func clip_velocity(
	velocity: Vector3,
	normal: Vector3,
	overbounce: float = 1.0
) -> Vector3:
	var backoff := velocity.dot(normal) * overbounce
	var out := velocity - normal * backoff
	var adjust := out.dot(normal)
	if adjust < 0.0:
		out -= normal * adjust
	return out


## The CS2 dead-strafe quirk. Returns the surface friction multiplier to use
## for this tick given the player's vertical velocity.
##
## See MovementConfig.cs2_deadstrafe for what this is and why it is optional.
static func surface_friction_for(
	vertical_velocity: float,
	on_ground: bool,
	cfg: MovementConfig
) -> float:
	if on_ground or not cfg.cs2_deadstrafe:
		return 1.0
	if vertical_velocity > 0.0 and vertical_velocity < cfg.deadstrafe_max_vertical_speed:
		return cfg.deadstrafe_friction
	return 1.0


## Is this surface walkable, or do you slide off it?
static func is_walkable(normal: Vector3, cfg: MovementConfig) -> bool:
	return normal.y >= cos(deg_to_rad(cfg.max_ground_angle_deg))


## Clamps the speed of a jump taken while already moving fast, which is what
## stops uncapped bunny hopping. CS2 has this on by default.
static func clamp_bunnyhop(velocity: Vector3, cfg: MovementConfig) -> Vector3:
	if cfg.enable_bunnyhopping:
		return velocity
	var cap := cfg.max_speed * cfg.bunnyhop_speed_cap
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	if speed <= cap:
		return velocity
	horizontal *= cap / speed
	return Vector3(horizontal.x, velocity.y, horizontal.z)
