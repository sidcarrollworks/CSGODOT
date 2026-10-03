class_name GrenadeEntity
extends SimEntity

## One grenade in the world, from the hand that threw it until it is gone:
## in flight, then, by what it is, going off at once (the HE, the flash, the
## molotov and incendiary), or lying where it stopped as a smoke's cloud or
## a decoy's gunfire until those run out. Stepped on the tick with the
## game's other entities; what draws it reads its state and listens to its
## events.
##
## What it does to players it does through the shared contracts: a
## DamageInfo per player an HE or a decoy's pop reaches, a player_blind for
## each player a flash blinds, and CS2's events for every bounce and
## detonation (reference/systems/contracts.md).

enum Phase { FLYING, SMOKING, DECOYING, GONE }

## CS2's class for each grenade in flight. The incendiary flies as a
## molotov, as in CS2.
const ENTITY_CLASSES := {
	GrenadeRules.HE: "hegrenade_projectile",
	GrenadeRules.FLASHBANG: "flashbang_projectile",
	GrenadeRules.SMOKE: "smokegrenade_projectile",
	GrenadeRules.MOLOTOV: "molotov_projectile",
	GrenadeRules.INCENDIARY: "molotov_projectile",
	GrenadeRules.DECOY: "decoy_projectile",
}

var system: GrenadeSystem
## What it is, by its item's class name (GrenadeRules.HE and the rest).
var weapon_class: String = "":
	set(value):
		weapon_class = value
		entity_class = entity_class_for(value)
## The thrower's side when it left the hand, for team damage.
var team: String = ""
var flight: GrenadeFlight
var phase: Phase = Phase.FLYING
## Simulation time it left the hand.
var thrown_usec: int = 0
## A seed for its smoke's shape and its decoy's bursts, from its id.
var random_seed: int = 0

## A smoke's cloud once it pops, and when it popped.
var cloud: SmokeVoxels
var popped_usec: int = 0
## A decoy's gunfire, and whose gun it sounds like (a class name; the
## thrower's primary, else their pistol).
var bursts: DecoyBursts
var decoy_weapon: String = ""
var next_think_usec: int = -1
var body_hit: bool = false
var fire_extension_usec: int = 0
var _low_speed_since_usec: int = -1
var _body_query: PhysicsShapeQueryParameters3D


static func entity_class_for(item_class: String) -> String:
	return String(ENTITY_CLASSES.get(item_class, "grenade_projectile"))


func tick(t: SimTick) -> void:
	match phase:
		Phase.FLYING:
			_fly(t)
		Phase.SMOKING:
			_smoke(t)
		Phase.DECOYING:
			_decoy(t)


## How long it has been out of the hand, in seconds.
func age(now_usec: int) -> float:
	return float(now_usec - thrown_usec) / 1_000_000.0


func _fly(t: SimTick) -> void:
	_check_body_hit(t)
	flight.step(t.space, t.dt, system.exclude_for(owner_id))
	previous_position = flight.previous_position
	position = flight.position
	for touch in flight.touches:
		_send(t, &"grenade_bounce", {"userid": owner_id}, touch["position"])
	match weapon_class:
		GrenadeRules.HE, GrenadeRules.FLASHBANG:
			if _think_due(t) and t.now_usec > thrown_usec + int(GrenadeRules.FUSE_SECONDS * 1_000_000.0):
				_detonate(t)
		GrenadeRules.SMOKE:
			if flight.velocity.length() <= GrenadeRules.SMOKE_ACTIVATE_SPEED and age(t.now_usec) >= GrenadeRules.SMOKE_MIN_SECONDS:
				_detonate(t)
		GrenadeRules.DECOY:
			if _think_due(t, GrenadeRules.DECOY_FIRST_THINK_USEC) and flight.velocity.length() <= GrenadeRules.DECOY_ACTIVATE_SPEED:
				_detonate(t)
		GrenadeRules.MOLOTOV, GrenadeRules.INCENDIARY:
			if flight.landed_normal.y >= cos(deg_to_rad(GrenadeRules.MOLOTOV_MAX_SLOPE_DEGREES)):
				_break(t, flight.landed_position)
			elif _think_due(t) and _fire_due(t.now_usec):
				_airburst(t)


## Think timers reschedule from the actual simulation time of each poll.
func _think_due(t: SimTick, initial_delay_usec: int = 0) -> bool:
	if next_think_usec < 0:
		next_think_usec = thrown_usec + initial_delay_usec
	if t.now_usec < next_think_usec:
		return false
	next_think_usec = t.now_usec + GrenadeRules.THINK_USEC
	return true


func _fire_due(now_usec: int) -> bool:
	if now_usec > thrown_usec + int(GrenadeRules.MOLOTOV_AIR_SECONDS * 1_000_000.0) + fire_extension_usec:
		return true
	if flight.velocity.length() > GrenadeRules.FIRE_LOW_SPEED:
		_low_speed_since_usec = -1
	elif _low_speed_since_usec < 0:
		_low_speed_since_usec = now_usec
	return _low_speed_since_usec >= 0 and now_usec - _low_speed_since_usec > GrenadeRules.FIRE_LOW_SPEED_USEC


## The one-time nearby enemy body path is separate from hull restitution.
## We query our player hulls; Source2's complete entity filters remain a
## local comparison item in the audit. No query after a successful hit.
func _check_body_hit(t: SimTick) -> void:
	if body_hit or flight.at_rest or flight.velocity.is_zero_approx() or t.space == null \
		or owner_id < 0 or not t.roster.player(owner_id) is PlayerSim:
		return
	if _body_query == null:
		_body_query = PhysicsShapeQueryParameters3D.new()
		var shape := SphereShape3D.new()
		shape.radius = GrenadeRules.BODY_HIT_RADIUS
		_body_query.shape = shape
		_body_query.margin = 0.0
		_body_query.collision_mask = PlayerSim.PLAYER_LAYER
	_body_query.transform.origin = flight.position
	for hit in PhysicsQueries.intersect_shape(t.space, _body_query):
		var player := hit.get("collider") as PlayerSim
		if player == null or not player.alive or player.userid == owner_id or player.team == team:
			continue
		body_hit = true
		var normal := (flight.position - player.grenade_center()).normalized()
		if not normal.is_zero_approx():
			flight.velocity = (flight.velocity - normal * 2.0 * flight.velocity.dot(normal)).normalized() * flight.velocity.length() * GrenadeRules.BODY_SPEED_SHARE
		_hurt(t, player.userid, GrenadeRules.BODY_HIT_DAMAGE, DamageInfo.DMG_GENERIC, entity_class, flight.position, 1.0)
		if GrenadeRules.is_fire(weapon_class):
			fire_extension_usec += GrenadeRules.FIRE_BODY_EXTENSION_USEC
		break


func _detonate(t: SimTick) -> void:
	match weapon_class:
		GrenadeRules.HE:
			_explode(t)
		GrenadeRules.FLASHBANG:
			_flash(t)
		GrenadeRules.SMOKE:
			_pop_smoke(t)
		GrenadeRules.DECOY:
			_start_decoy(t)


# --- HE -------------------------------------------------------------------

func _explode(t: SimTick) -> void:
	_send(t, &"hegrenade_detonate", {"userid": owner_id, "entityid": id}, position)
	var data := system.data(weapon_class)
	for userid in t.game.roster.ids():
		var player := t.game.roster.player(userid) as PlayerSim
		if player == null or not player.alive:
			continue
		var centre := player.global_position + Vector3.UP * 36.0
		var amount := GrenadeRules.he_damage_at(position.distance_to(centre))
		if amount <= 0.0 or not _reaches(t.space, player):
			continue
		_hurt(t, userid, amount * _team_share(t, userid), DamageInfo.DMG_BLAST, "hegrenade_projectile", centre, data.armor_penetration)
	system._clear_smoke_near(position, t.now_usec)
	_gone()


## Whether a blast here reaches a player: a clear line to their middle,
## their eyes or their feet.
func _reaches(space: PhysicsDirectSpaceState3D, player: PlayerSim) -> bool:
	var from := position + Vector3.UP * 1.0
	for height in [36.0, player.eye_height(), 4.0]:
		var to: Vector3 = player.global_position + Vector3.UP * height
		var query := PhysicsRayQueryParameters3D.create(from, to, Hitscan.WORLD_LAYER)
		if PhysicsQueries.intersect_ray(space, query).is_empty():
			return true
	return false


# --- Flashbang ------------------------------------------------------------

func _flash(t: SimTick) -> void:
	_send(t, &"flashbang_detonate", {"userid": owner_id, "entityid": id}, position)
	for userid in t.game.roster.ids():
		var player := t.game.roster.player(userid) as PlayerSim
		if player == null or not player.alive:
			continue
		var eyes := player.global_position + Vector3.UP * player.eye_height()
		var forward := PlayerInput.aim_direction(player.yaw_degrees, player.pitch_degrees)
		var blind := FlashBlind.from(t.space, position, eyes, forward, t.now_usec, [player.get_rid()])
		if blind == null:
			continue
		blind.attacker = owner_id
		blind.entityid = id
		if system._blind(userid, blind):
			t.game.events.send(&"player_blind", {
				"userid": userid, "attacker": owner_id, "entityid": id, "blind_duration": blind.duration,
			})
	_gone()


# --- Smoke ----------------------------------------------------------------

func _pop_smoke(t: SimTick) -> void:
	phase = Phase.SMOKING
	popped_usec = t.now_usec
	cloud = SmokeVoxels.new(position, random_seed)
	system._smoke_popped(position)
	_send(t, &"smokegrenade_detonate", {"userid": owner_id, "entityid": id}, position)
	_smoke(t)


func _smoke(t: SimTick) -> void:
	previous_position = position
	if not cloud.full():
		cloud.grow(t.space, SmokeVoxels.per_tick())
	system._put_out_fires(cloud, t.now_usec)
	if t.now_usec >= popped_usec + int(GrenadeRules.SMOKE_SECONDS * 1_000_000.0):
		_send(t, &"smokegrenade_expired", {"userid": owner_id, "entityid": id}, position)
		_gone()


# --- Molotov and incendiary -----------------------------------------------

## Gone off in the air: the fire falls on whatever ground is close enough
## below, and comes to nothing if none is.
func _airburst(t: SimTick) -> void:
	var query := PhysicsRayQueryParameters3D.create(
		position + Vector3.UP * 10.0, position + Vector3.DOWN * GrenadeRules.MOLOTOV_AIRBURST_DROP, Hitscan.WORLD_LAYER
	)
	var ground := PhysicsQueries.intersect_ray(t.space, query)
	if ground.is_empty() or (ground["normal"] as Vector3).y < GrenadeRules.FLOOR_NORMAL_Y:
		_send(t, &"molotov_detonate", {"userid": owner_id}, position)
		_gone()
		return
	_break(t, ground["position"])


## Broken on the ground: a fire starts there, unless smoke is there to put
## it out at once.
func _break(t: SimTick, ground: Vector3) -> void:
	_send(t, &"molotov_detonate", {"userid": owner_id}, ground)
	if not system.in_smoke(ground + Vector3.UP * 8.0, t.now_usec):
		var inferno := InfernoEntity.new()
		inferno.system = system
		inferno.owner_id = owner_id
		inferno.team = team
		inferno.weapon_class = weapon_class
		inferno.fire = FireSpread.new(weapon_class, ground, t.now_usec, random_seed)
		inferno.position = ground
		inferno.previous_position = ground
		t.game.entities.spawn(inferno)
	_gone()


# --- Decoy ----------------------------------------------------------------

func _start_decoy(t: SimTick) -> void:
	phase = Phase.DECOYING
	var cycle := 0.1
	if not decoy_weapon.is_empty() and ItemRegistry.has(decoy_weapon):
		var gun := ItemRegistry.weapon_data(decoy_weapon)
		if gun != null and gun.cycle_time > 0.0:
			cycle = gun.cycle_time
	bursts = DecoyBursts.new(t.now_usec, random_seed, cycle)
	_send(t, &"decoy_started", {"userid": owner_id, "entityid": id}, position)
	_decoy(t)


func _decoy(t: SimTick) -> void:
	previous_position = position
	for at_usec in bursts.due(t.now_usec):
		_send(t, &"decoy_firing", {"userid": owner_id, "entityid": id}, position, at_usec)
	if t.now_usec < bursts.ends_usec():
		return
	_send(t, &"decoy_detonate", {"userid": owner_id, "entityid": id}, position)
	for userid in t.game.roster.ids():
		var player := t.game.roster.player(userid) as PlayerSim
		if player == null or not player.alive:
			continue
		# No team damage from the pop (ff_damage_decoy_explosion false), the
		# thrower's own included.
		if userid == owner_id or (not team.is_empty() and t.game.roster.team_of(userid) == team):
			continue
		var centre := player.global_position + Vector3.UP * 36.0
		if position.distance_to(centre) > GrenadeRules.DECOY_POP_RADIUS + 36.0 or not _reaches(t.space, player):
			continue
		_hurt(t, userid, GrenadeRules.DECOY_POP_DAMAGE, DamageInfo.DMG_BLAST, "decoy_projectile", centre, system.data(weapon_class).armor_penetration)
	_gone()


# --- Shared ---------------------------------------------------------------

## The share of its damage a player takes: all of it for the thrower and
## the other side, the system's team share for the thrower's teammates.
func _team_share(t: SimTick, userid: int) -> float:
	if userid == owner_id or team.is_empty() or t.game.roster.team_of(userid) != team:
		return 1.0
	return system.team_damage_scale


func _hurt(
	t: SimTick, userid: int, amount: float, damage_type: int, inflictor: String,
	at: Vector3, armor_penetration: float
) -> void:
	var info := DamageInfo.new()
	info.attacker = owner_id
	info.inflictor = inflictor
	info.weapon = weapon_class
	info.damage = amount
	info.damage_type = damage_type
	info.origin = position
	info.position = at
	info.direction = (at - position).normalized()
	info.armor_penetration = armor_penetration
	info.at_usec = t.now_usec
	system.deal(t, userid, info, system.data(weapon_class))


func _send(t: SimTick, name: StringName, fields: Dictionary, at: Vector3, at_usec: int = -1) -> void:
	fields.merge(GrenadeSystem.position_fields(at))
	t.game.events.send(name, fields, at_usec)


func _gone() -> void:
	phase = Phase.GONE
	remove()
