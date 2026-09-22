class_name Bot
extends PlayerBody

## A player that is not you. The same body, hull and movement solver as the
## local player, pushed by a route rather than by keys, and wearing the
## third-person model. It walks its route round and round, facing the way it
## goes, and can be shot: it wears the model's own hitboxes on its bones,
## dies where the last round lands, and comes back at the start of its
## route. It shoots back: when a player is in its sight, in the open and
## within its cone for long enough to react, it stops, turns, and fires its
## weapon at them in bursts with the weapon's own spread and recoil, and
## reloads when it runs dry. It does not flinch, take cover or think.
##
## The point of it being the same body is that it moves like a player. A bot
## that walked on rails would be a different thing to shoot at than the
## players it stands in for.

## Where the bot goes, in order, in world units. It turns for the first
## point on arriving at the last.
@export var route: PackedVector3Array = PackedVector3Array()

## Close enough to a point to head for the next, in units.
@export var arrive_distance: float = 24.0

## How fast the bot turns to face its way, in degrees per second.
@export var turn_rate: float = 540.0

## The bot's side, for its model, and what it holds: the model to draw and
## the numbers to shoot with.
@export_enum("T", "CT") var team: String = "T"
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

## How long a dead bot lies there before it is back on its route.
@export var respawn_seconds: float = 5.0

## The way it faces, in the game's degrees (PlayerInput's).
var yaw_degrees: float = 0.0

var model: PlayerModel
## Its health and armour; what a hit is applied to.
var hit_target: HitTarget
## The model's hitboxes, on its bones.
var hitboxes: SkinnedHitboxes
var alive: bool = true

## What it shoots with, and what it hears of it, in the world.
var weapon: Weapon
var weapon_sounds: WeaponSounds
## The player it is engaging, or null; and how it is going.
var target: Node3D
var pitch_degrees: float = 0.0
var rounds_fired: int = 0

signal died(zone: StringName)
signal respawned
signal fired(shot: Weapon.Shot, result: Hitscan.Result)

var _next: int = 0
var _deaths: int = 0
var _respawn_at_usec: int = 0
var _seen_for: float = 0.0
var _burst_clock: float = 0.0
var _aim_error: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	hit_target = HitTarget.new()
	hit_target.name = "HitTarget"
	hit_target.build_own_hitboxes = false
	add_child(hit_target)
	hit_target.died.connect(_on_died)

	model = PlayerModel.new()
	model.name = "Model"
	add_child(model)
	if not model.setup(team, weapon_model):
		model.queue_free()
		model = null
		return
	var footsteps := Footsteps.new()
	footsteps.name = "Footsteps"
	add_child(footsteps)
	if weapon_data != null:
		weapon = Weapon.new(weapon_data)
		weapon.trigger_held = false
		weapon_sounds = WeaponSounds.new()
		weapon_sounds.name = "WeaponSounds"
		weapon_sounds.spatial = true
		add_child(weapon_sounds)
		weapon_sounds.equip(weapon_data)
	hitboxes = SkinnedHitboxes.new()
	hitboxes.name = "Hitboxes"
	add_child(hitboxes)
	hitboxes.build(
		model.character_rig, HitboxSet.load_for(PlayerModel.AGENTS.get(team, PlayerModel.AGENTS["T"])),
		hit_target, MapImporter.SOURCE2_VIEWER_SCALE
	)


func _physics_process(delta: float) -> void:
	wants_jump = false
	wants_duck = false
	wish_dir = Vector3.ZERO
	wish_speed = 0.0

	if not alive:
		if Time.get_ticks_usec() >= _respawn_at_usec:
			respawn()
		return

	# Nothing to shoot with, nothing to stop for: an unarmed bot just walks.
	target = _look_for_target() if weapon != null else null
	if target != null:
		_seen_for += delta
	else:
		_seen_for = 0.0
		_burst_clock = 0.0
	if target != null and _seen_for >= REACTION_SECONDS:
		_engage(target, delta)
	elif not route.is_empty():
		var waypoint := route[_next]
		var to_waypoint := waypoint - global_position
		to_waypoint.y = 0.0
		if to_waypoint.length() < arrive_distance:
			_next = (_next + 1) % route.size()
		elif to_waypoint.length_squared() > 0.0:
			wish_dir = to_waypoint.normalized()
			wish_speed = config.max_speed
			# The game's yaw 0 looks down -Z, and yaw grows towards -X.
			var wanted := rad_to_deg(atan2(-wish_dir.x, -wish_dir.z))
			yaw_degrees = rad_to_deg(rotate_toward(
				deg_to_rad(yaw_degrees), deg_to_rad(wanted), deg_to_rad(turn_rate) * delta
			))

	simulate(delta)
	if model != null:
		model.update_motion(velocity, yaw_degrees, is_ducked, on_ground)
		model.light_from(global_position + Vector3.UP * 40.0)


## The nearest living player in sight: within range, within the cone, and
## in the open between its eyes and theirs.
func _look_for_target() -> Node3D:
	var best: Node3D = null
	var best_distance := SIGHT_RANGE
	for node in get_tree().get_nodes_in_group(&"players"):
		var candidate := node as Node3D
		if candidate == null or candidate == self or not bool(candidate.get("alive")):
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


## Stops, turns to face the target, and fires in bursts once facing it.
func _engage(enemy: Node3D, delta: float) -> void:
	var eyes := global_position + Vector3.UP * eye_height()
	var aim: Vector3 = enemy.global_position + Vector3.UP * 48.0
	var angles := PlayerInput.angles_from_direction(aim - eyes)
	yaw_degrees = rad_to_deg(rotate_toward(
		deg_to_rad(yaw_degrees), deg_to_rad(angles.x), deg_to_rad(turn_rate) * delta
	))
	pitch_degrees = angles.y
	var facing := absf(angle_difference(deg_to_rad(yaw_degrees), deg_to_rad(angles.x))) < deg_to_rad(FIRE_WITHIN_DEGREES)
	if weapon == null or not facing:
		return
	var now := Time.get_ticks_usec()
	weapon.finish_reload_if_due(now)
	if weapon.ammo <= 0:
		if weapon.start_reload(now) and model != null:
			model.play(&"reload", 0.1)
		_burst_clock = 0.0
	# A burst, a pause, a burst: the clock runs round both.
	_burst_clock = fmod(_burst_clock + delta, BURST_SECONDS + PAUSE_SECONDS)
	var bursting := _burst_clock < BURST_SECONDS
	if _burst_clock < delta:
		_aim_error = Vector2(_rng.randf_range(-AIM_ERROR_DEGREES, AIM_ERROR_DEGREES), _rng.randf_range(-AIM_ERROR_DEGREES, AIM_ERROR_DEGREES))
	weapon.trigger_held = bursting
	weapon.update(delta, now)
	if not bursting or not weapon.can_fire(now):
		return
	var state := Weapon.ShooterState.new(Vector2(velocity.x, velocity.z).length(), on_ground, is_ducked)
	var shot := weapon.fire(now, 0.0, eyes, yaw_degrees + _aim_error.x, pitch_degrees + _aim_error.y, state)
	if shot == null:
		return
	rounds_fired += 1
	var exclude: Array[RID] = [get_rid()]
	if hit_target != null:
		exclude.append_array(hit_target.rids())
	var result := Hitscan.fire_at(get_world_3d().direct_space_state, shot, weapon.data, exclude)
	BulletImpacts.mark_in(get_tree(), result)
	if weapon_sounds != null:
		weapon_sounds.shot()
	if model != null:
		model.play(&"shoot", 0.03, 1.0, true)
	fired.emit(shot, result)


## Dies where the last round landed: the model plays that death and stays
## down, the hull and the hitboxes go, and the route waits.
func _on_died() -> void:
	alive = false
	_deaths += 1
	velocity = Vector3.ZERO
	var zone: StringName = hit_target.last_hitbox.zone if hit_target.last_hitbox != null else &"chest"
	if model != null:
		model.play(PlayerModel.death_for(zone, _deaths), 0.05)
	if hitboxes != null:
		hitboxes.set_active(false)
	collision_layer = 0
	_respawn_at_usec = Time.get_ticks_usec() + int(respawn_seconds * 1_000_000.0)
	died.emit(zone)


## Back at the start of the route, whole.
func respawn() -> void:
	alive = true
	hit_target.reset()
	if weapon_data != null:
		weapon = Weapon.new(weapon_data)
		weapon.trigger_held = false
	_seen_for = 0.0
	target = null
	collision_layer = 2
	if hitboxes != null:
		hitboxes.set_active(true)
	if not route.is_empty():
		global_position = route[0]
		_next = 1 % route.size()
	velocity = Vector3.ZERO
	if model != null:
		model.play(model.idle)
	respawned.emit()
