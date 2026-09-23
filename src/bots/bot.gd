class_name Bot
extends PlayerSim

## A player that is not you. The same simulation as the local player
## (PlayerSim: body, hull, movement solver, weapon), run by the same kind of
## command, except that the command comes from what the bot decides rather
## than from keys. It wears the third-person model. It walks its route round
## and round, facing the way it goes, and can be shot: it wears the model's
## own hitboxes on its bones, goes limp and falls the way the last round
## pushed it (a ragdoll), and comes back at the start of its route. It shoots
## back: when a player of the other side is in its sight, in the open and
## within its cone for long enough to react, it stops, turns, and holds the
## trigger in bursts, so its rounds go through the weapon's own rate, spread
## and recoil exactly as yours do, and it reloads when it runs dry. It does
## not flinch, take cover or think.
##
## The point of it being the same simulation is that it moves and shoots
## like a player. A bot that walked on rails and fired by its own rules
## would be a different thing to shoot at than the players it stands in for.
##
## Its model is part of what it is, not just how it looks: the hitboxes ride
## the model's bones, so the model animates whether anyone sees it or not,
## as CS2's server animates everyone for their hitboxes.

## Where the bot goes, in order, in world units. It turns for the first
## point on arriving at the last.
@export var route: PackedVector3Array = PackedVector3Array()

## Close enough to a point to head for the next, in units.
@export var arrive_distance: float = 24.0

## How fast the bot turns to face its way, in degrees per second.
@export var turn_rate: float = 540.0

## What it holds: the model to draw and the numbers to shoot with.
@export var weapon_model: String = ""
@export var weapon_data: WeaponData

## Sight: how far and how wide it sees, in units and degrees either side
## of where it faces, and how long a player has to be in sight before it
## acts. Then it fires in bursts, with a little error on top of the
## weapon's own, and turns at its turn rate.
const SIGHT_RANGE := 3000.0
const SIGHT_HALF_ANGLE := 75.0
const REACTION_SECONDS := 0.5
const BURST_SECONDS := 0.6
const PAUSE_SECONDS := 0.45
const AIM_ERROR_DEGREES := 1.2
const FIRE_WITHIN_DEGREES := 6.0

## Its body falling, while it is dead; null otherwise.
var ragdoll: Ragdoll

## Armed but not shooting: it sees nobody, so it stands or walks its route.
## The test range's shooter waits like this until it is told to fire.
@export var holds_fire: bool = false

## What it hears of its weapon, in the world.
var weapon_sounds: WeaponSounds
## The player it is engaging, or null.
var target: Node3D

signal died(zone: StringName)

var _next: int = 0
var _deaths: int = 0
var _seen_for: float = 0.0
var _burst_clock: float = 0.0
var _aim_error: Vector2 = Vector2.ZERO
## The error in the angles it last sent, so the next command turns from where
## it meant to face rather than from where the error put it.
var _sent_error: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	# A dead bot lies there this long before it is back on its route.
	respawn_seconds = 5.0


func _ready() -> void:
	super._ready()
	killed.connect(_on_killed)
	shot_traced.connect(_on_shot_traced)
	reload_started.connect(_on_reload_started)

	# The body, drawn, and its hitboxes are PlayerSim's (wear_body).
	if model != null:
		var footsteps := Footsteps.new()
		footsteps.name = "Footsteps"
		add_child(footsteps)
	# What it shoots with is the simulation's, model or no model.
	if weapon_data != null:
		weapon = Weapon.new(weapon_data)
		weapon.trigger_held = false
		weapon_sounds = WeaponSounds.new()
		weapon_sounds.name = "WeaponSounds"
		weapon_sounds.spatial = true
		add_child(weapon_sounds)
		weapon_sounds.equip(weapon_data)


## Hands it another weapon's numbers, loaded; it keeps the model it holds.
func arm(data: WeaponData) -> void:
	weapon_data = data
	weapon = Weapon.new(data)
	weapon.trigger_held = false
	if weapon_sounds != null:
		weapon_sounds.equip(data)


## A bot's body is seen, holding its weapon. Without the model's capsules
## (not extracted, or a broken extraction) it wears the four standard boxes,
## with a grey body to see them by when there is no model either: a bot has
## to be something that can be shot.
func _body_weapon_model() -> String:
	return weapon_model


func _body_drawn() -> bool:
	return true


func _physics_process(delta: float) -> void:
	run_command(_think(delta), delta)
	if alive and model != null:
		model.light_from(global_position + Vector3.UP * 40.0)


## What it does this tick, as a command: the way it faces, the way it walks,
## and whether the trigger is down.
func _think(delta: float) -> UserCmd:
	var cmd := UserCmd.new()
	cmd.tick = SimClock.current_tick()
	# Where it meant to face last tick, the aim error taken back out.
	var yaw := yaw_degrees - _sent_error.x
	var pitch := pitch_degrees - _sent_error.y
	var error := Vector2.ZERO

	if not alive:
		cmd.yaw_degrees = yaw
		cmd.pitch_degrees = pitch
		_sent_error = Vector2.ZERO
		return cmd

	# Nothing to shoot with, nothing to stop for: an unarmed bot just walks.
	target = _look_for_target() if weapon != null and not holds_fire else null
	if target != null:
		_seen_for += delta
	else:
		_seen_for = 0.0
		_burst_clock = 0.0

	if target != null and _seen_for >= REACTION_SECONDS:
		# Stops, turns to face the target, and fires in bursts once facing it.
		var eyes := global_position + Vector3.UP * eye_height()
		var aim: Vector3 = target.global_position + Vector3.UP * 48.0
		var angles := PlayerInput.angles_from_direction(aim - eyes)
		yaw = rad_to_deg(rotate_toward(deg_to_rad(yaw), deg_to_rad(angles.x), deg_to_rad(turn_rate) * delta))
		pitch = angles.y
		var facing := absf(angle_difference(deg_to_rad(yaw), deg_to_rad(angles.x))) < deg_to_rad(FIRE_WITHIN_DEGREES)
		if facing:
			if weapon.ammo <= 0:
				cmd.steps.append(UserCmd.SubtickStep.new(UserCmd.RELOAD, true, 0.0, yaw, pitch))
				_burst_clock = 0.0
			# A burst, a pause, a burst: the clock runs round both.
			_burst_clock = fmod(_burst_clock + delta, BURST_SECONDS + PAUSE_SECONDS)
			if _burst_clock < delta:
				_aim_error = Vector2(
					_rng.randf_range(-AIM_ERROR_DEGREES, AIM_ERROR_DEGREES),
					_rng.randf_range(-AIM_ERROR_DEGREES, AIM_ERROR_DEGREES)
				)
			error = _aim_error
			if _burst_clock < BURST_SECONDS:
				cmd.buttons |= UserCmd.ATTACK
	elif not route.is_empty():
		var waypoint := route[_next]
		var to_waypoint := waypoint - global_position
		to_waypoint.y = 0.0
		if to_waypoint.length() < arrive_distance:
			_next = (_next + 1) % route.size()
		elif to_waypoint.length_squared() > 0.0:
			var way := to_waypoint.normalized()
			# The game's yaw 0 looks down -Z, and yaw grows towards -X.
			var wanted := rad_to_deg(atan2(-way.x, -way.z))
			yaw = rad_to_deg(rotate_toward(deg_to_rad(yaw), deg_to_rad(wanted), deg_to_rad(turn_rate) * delta))
			cmd.move = UserCmd.move_toward(way, yaw)

	cmd.yaw_degrees = yaw + error.x
	cmd.pitch_degrees = pitch + error.y
	_sent_error = error
	return cmd


## The nearest living player of the other side in sight: within range,
## within the cone, and in the open between its eyes and theirs.
func _look_for_target() -> Node3D:
	var best: Node3D = null
	var best_distance := SIGHT_RANGE
	for node in get_tree().get_nodes_in_group(&"players"):
		var candidate := node as PlayerSim
		if candidate == null or candidate == self or not candidate.alive or candidate.team == team:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance >= best_distance:
			continue
		if not can_see(candidate):
			continue
		best = candidate
		best_distance = distance
	return best


## Whether a body is within the cone the bot faces and nothing of the map
## stands between its eyes and theirs.
func can_see(other: Node3D) -> bool:
	var eyes := global_position + Vector3.UP * eye_height()
	var theirs: Vector3 = other.global_position + Vector3.UP * 60.0
	if other is PlayerBody:
		theirs = other.global_position + Vector3.UP * (other as PlayerBody).eye_height()
	var to_them := theirs - eyes
	if to_them.length() > SIGHT_RANGE:
		return false
	var forward := Vector3(-sin(deg_to_rad(yaw_degrees)), 0.0, -cos(deg_to_rad(yaw_degrees)))
	var flat := Vector3(to_them.x, 0.0, to_them.z)
	if flat.length_squared() > 1e-6 and rad_to_deg(forward.angle_to(flat.normalized())) > SIGHT_HALF_ANGLE:
		return false
	var query := PhysicsRayQueryParameters3D.create(eyes, theirs, Hitscan.WORLD_LAYER, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_shot_traced(_shot: Weapon.Shot, result: Hitscan.Result) -> void:
	BulletImpacts.mark_in(get_tree(), result)
	if weapon_sounds != null:
		weapon_sounds.shot()
	if model != null:
		model.play(&"shoot", 0.03, 1.0, true)


func _on_reload_started() -> void:
	if model != null:
		model.play(&"reload", 0.1)


## Dies where the last round landed: the body goes limp and falls, pushed
## the way the round was going, and stays down; the hull and the hitboxes
## go, and the route waits. Without the hitbox set to build a ragdoll from,
## the model plays the game's death clip for where the round landed instead.
func _on_killed(zone: StringName) -> void:
	_deaths += 1
	if model != null and not _ragdoll():
		model.play(PlayerModel.death_for(zone, _deaths), 0.05)
	collision_layer = 0
	died.emit(zone)


## Hands the skeleton to a ragdoll made from the hitbox capsules. False,
## with nothing done, when there are none to make it from.
func _ragdoll() -> bool:
	if _capsules.is_empty() or model.character_rig == null:
		return false
	ragdoll = Ragdoll.new()
	ragdoll.name = "Ragdoll"
	add_child(ragdoll)
	var forward := Vector3(-sin(deg_to_rad(yaw_degrees)), 0.0, -cos(deg_to_rad(yaw_degrees)))
	var hit_bone := -1
	if hit_target.last_hitbox != null:
		hit_bone = hitboxes.bone_of(hit_target.last_hitbox)
	if ragdoll.build(
		model.character_rig, _capsules, MapImporter.SOURCE2_VIEWER_SCALE,
		velocity, forward, hit_target.last_hit_direction, hit_bone
	) == 0:
		ragdoll.queue_free()
		ragdoll = null
		return false
	# The animation would pose the bones over the bodies' every frame.
	model.animation_player.active = false
	return true


## Back at the start of the route, whole; without a route, where it fell.
func respawn() -> void:
	alive = true
	hit_target.reset()
	if weapon_data != null:
		weapon = Weapon.new(weapon_data)
		weapon.trigger_held = false
	_seen_for = 0.0
	target = null
	collision_layer = 2
	hit_target.set_active(true)
	if not route.is_empty():
		global_position = route[0]
		_next = 1 % route.size()
	velocity = Vector3.ZERO
	_forget_hits()
	if ragdoll != null:
		ragdoll.queue_free()
		ragdoll = null
		if model != null:
			model.character_rig.reset_bone_poses()
			model.animation_player.active = true
	if model != null:
		model.play(model.idle)
	respawned.emit()
