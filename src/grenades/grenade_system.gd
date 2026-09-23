class_name GrenadeSystem
extends RefCounted

## CS2's grenades, as one of the game's systems (GameSystems): the throw,
## and what the grenades in the world are asked about. Each grenade in the
## world is an entity of its own (GrenadeEntity, and InfernoEntity for a
## fire), stepped with the rest of the game's entities each tick; this is
## what they share and what the rest of the game may ask.
##
## It meets the other systems only through the shared contracts
## (reference/systems/contracts.md): a throw and every detonation, bounce,
## blinding and burn go out as CS2's game events, damage as one DamageInfo
## per victim, and grenades are named by their class names. The queries
## (how much smoke a line goes through, how blind a player is, whether a
## point burns) are for whatever needs them: bots' sight, the kill feed's
## "through smoke" and "blind" marks, the white-out.
##
## Blinding is kept here, by userid, as CS2 keeps it on the player
## (m_flFlashDuration and m_flFlashMaxAlpha), until the player carries it.

## The share of a grenade's damage that reaches the thrower's own side (the
## thrower always takes all of their own): all of it alone on the range,
## GrenadeRules.TEAM_DAMAGE_IN_MATCH in a match.
var team_damage_scale: float = 1.0

var game: GameSystems
## Each player's blinding, by userid: the latest FlashBlind that runs
## longest.
var _blinds := {}
## The game's numbers for each grenade, read once.
var _data := {}


func attach(p_game: GameSystems) -> void:
	game = p_game
	for weapon_class in GrenadeRules.ALL:
		_data[weapon_class] = GrenadeRules.weapon_data(weapon_class)
	# A round through a smoke cuts a tunnel in it: from the shooter's eyes
	# to where the round landed.
	game.events.listen(&"bullet_impact", _on_bullet_impact)
	# What the rest of the game may ask (reference/systems/contracts.md).
	game.provide(&"smoke_length_between", smoke_length_between)
	game.provide(&"blindness", blindness)
	game.provide(&"blind_share", blind_share)
	game.provide(&"burning_at", burning_at)
	# A throw asked for by name: "throw weapon_hegrenade 1" (the class and
	# the strength), for whatever throws without a hand to throw from yet:
	# the range, a bot's lineup, a console.
	game.on_command(&"throw", _on_throw_command)


func tick(_t: SimTick) -> void:
	pass


## The game's numbers for a grenade, as the damage it does reads them.
func data(weapon_class: String) -> WeaponData:
	return _data.get(weapon_class) as WeaponData


## A player throws a grenade, from where they are looking, moving as they
## are: the throw a command asks for, at a strength from
## GrenadeRules.strength_for. It takes the grenade out of their inventory,
## and is refused (null) when they carry none. Returns the grenade, now in
## the world; its first flight is on the next tick.
func throw(userid: int, weapon_class: String, strength: float, space: PhysicsDirectSpaceState3D) -> GrenadeEntity:
	var player := game.roster.player(userid) as PlayerSim
	var inventory := game.inventory(userid) if userid >= 0 else null
	if player == null or inventory == null or not inventory.take_one(weapon_class):
		return null
	var eye := player.global_position + Vector3.UP * player.eye_height()
	return throw_from(userid, weapon_class, eye, player.yaw_degrees, player.pitch_degrees, player.velocity, strength, space)


## The throw command: a grenade by class name, at a strength (1 if not
## given), from the player's eyes as the tick finds them. Taken only for a
## grenade a living player carries.
func _on_throw_command(userid: int, args: PackedStringArray, t: SimTick) -> bool:
	if args.is_empty() or not GrenadeRules.is_grenade(args[0]):
		return false
	var player := game.roster.player(userid) as PlayerSim
	if player == null or not player.alive:
		return false
	var strength := clampf(args[1].to_float(), 0.0, 1.0) if args.size() > 1 and args[1].is_valid_float() else 1.0
	return throw(userid, args[0], strength, t.space) != null


## A throw from anywhere: what throw does once it knows where the player
## stands and has taken the grenade. It takes nothing from anyone's
## inventory; the checks set grenades off with it.
func throw_from(
	userid: int, weapon_class: String, eye: Vector3, yaw: float, pitch: float,
	velocity: Vector3, strength: float, space: PhysicsDirectSpaceState3D
) -> GrenadeEntity:
	assert(GrenadeRules.is_grenade(weapon_class), "%s is not a grenade" % weapon_class)
	var grenade := GrenadeEntity.new()
	grenade.system = self
	grenade.weapon_class = weapon_class
	grenade.owner_id = userid
	grenade.team = game.roster.team_of(userid) if userid >= 0 else ""
	grenade.thrown_usec = game.now_usec()
	grenade.flight = GrenadeFlight.throw_from(space, weapon_class, eye, yaw, pitch, velocity, strength, exclude_for(userid))
	grenade.position = grenade.flight.position
	grenade.previous_position = grenade.position
	grenade.decoy_weapon = _primary_of(userid)
	game.entities.spawn(grenade)
	grenade.seed = hash([grenade.id, weapon_class, grenade.thrown_usec])
	game.events.send(&"grenade_thrown", {"userid": userid, "weapon": weapon_class})
	return grenade


## What a grenade does not bounce off: its thrower.
func exclude_for(userid: int) -> Array[RID]:
	var out: Array[RID] = []
	var player := game.roster.player(userid) if userid >= 0 else null
	if player is CollisionObject3D:
		out.append((player as CollisionObject3D).get_rid())
	return out


# --- Smoke ----------------------------------------------------------------

## Every smoke in the world that has popped.
func clouds() -> Array[SmokeVoxels]:
	var out: Array[SmokeVoxels] = []
	for entity in game.entities.of_class(GrenadeEntity.entity_class_for(GrenadeRules.SMOKE)):
		var grenade := entity as GrenadeEntity
		if grenade != null and grenade.cloud != null:
			out.append(grenade.cloud)
	return out


## How much of a line is in smoke, in units, at a simulation time (now if
## not given): what sight asks.
func smoke_length_between(from: Vector3, to: Vector3, at_usec: int = -1) -> float:
	var now := SimClock.now_usec() if at_usec < 0 else at_usec
	var through := 0.0
	for cloud in clouds():
		through += cloud.length_through(from, to, now)
	return through


## Whether smoke hides one point from another for someone who sees through
## at most that much of it: a bot, by default (bot_max_visible_smoke_length).
func blocks_sight(from: Vector3, to: Vector3, most: float = GrenadeRules.BOT_MAX_VISIBLE_SMOKE_LENGTH) -> bool:
	return smoke_length_between(from, to) > most


func in_smoke(point: Vector3, at_usec: int = -1) -> bool:
	var now := SimClock.now_usec() if at_usec < 0 else at_usec
	for cloud in clouds():
		if cloud.contains(point, now):
			return true
	return false


func _clear_smoke_near(point: Vector3, now_usec: int) -> void:
	var until := now_usec + int(GrenadeRules.SMOKE_HOLE_SECONDS * 1_000_000.0)
	for cloud in clouds():
		cloud.clear_sphere(point, GrenadeRules.HE_SMOKE_CLEAR_RADIUS, until)


func _on_bullet_impact(event: GameEvent) -> void:
	var clouds_now := clouds()
	if clouds_now.is_empty():
		return
	var shooter := game.roster.player(int(event.fields["userid"])) as PlayerBody
	if shooter == null:
		return
	var eyes := shooter.global_position + Vector3.UP * shooter.eye_height()
	var landed := position_of(event.fields)
	var until := event.at_usec + int(GrenadeRules.SMOKE_TUNNEL_SECONDS * 1_000_000.0)
	for cloud in clouds_now:
		cloud.clear_line(eyes, landed, until)


# --- Fire -----------------------------------------------------------------

## Every fire burning.
func fires() -> Array[FireSpread]:
	var out: Array[FireSpread] = []
	for entity in game.entities.of_class(InfernoEntity.ENTITY_CLASS):
		out.append((entity as InfernoEntity).fire)
	return out


## Whether a point stands in fire: for a bot to keep out of it.
func burning_at(point: Vector3) -> bool:
	for fire in fires():
		if fire.burns(point):
			return true
	return false


## A smoke popped at a point: a fire it popped in goes out whole, as a smoke
## thrown into a molotov puts it out in CS:GO.
func _smoke_popped(at: Vector3) -> void:
	for fire in fires():
		if fire.burns(at):
			fire.extinguished = true


## Puts out whatever fire smoke covers, flame by flame as the cloud grows.
func _put_out_fires(cloud: SmokeVoxels, now_usec: int) -> void:
	for fire in fires():
		fire.put_out(func(point: Vector3) -> bool: return cloud.contains(point + Vector3.UP * 8.0, now_usec))


# --- Flashes --------------------------------------------------------------

## A player blinded, unless a blind already on them runs longer.
func _blind(userid: int, blind: FlashBlind) -> bool:
	var current := _blinds.get(userid) as FlashBlind
	if not blind.outlasts(current):
		return false
	_blinds[userid] = blind
	return true


## How white a player's screen is at a simulation time (now if not given),
## 0 to 1. A frame between two ticks asks for the time between them.
func blind_amount(userid: int, at_usec: int = -1) -> float:
	var blind := _blinds.get(userid) as FlashBlind
	if blind == null:
		return 0.0
	return blind.amount(SimClock.now_usec() if at_usec < 0 else at_usec)


## The blinding on a player, or null: who threw it, how long it runs.
func blind_of(userid: int) -> FlashBlind:
	return _blinds.get(userid) as FlashBlind


## The blindness query: how long a player's blinding runs and how white it
## gets, or empty if they are not blinded.
func blindness(userid: int) -> Dictionary:
	var blind := blind_of(userid)
	if blind == null or blind.amount(SimClock.now_usec()) <= 0.0:
		return {}
	return {"duration": blind.duration, "peak": blind.peak}


## The blind_share query: how blind a player is now, 0 to 1, or at a
## simulation time (the white-out asks for the frame's).
func blind_share(userid: int, at_usec: int = -1) -> float:
	return blind_amount(userid, at_usec)


## Whether a kill on this player now is a blind kill (flashed past 70%).
func blind_for_kill(userid: int) -> bool:
	return blind_amount(userid) > GrenadeRules.FLASHED_FOR_BLIND_KILL


# --- Damage ---------------------------------------------------------------

## Deals a grenade's damage to a player through the shared record, and says
## so on the game's events. Until the player reads HitTarget.last_damage,
## the target's last_hit fields are set as a round sets them (Hitscan), so
## being hit by a grenade tags and turns the view as the game's code
## expects: what hit it (weapon, the grenade's own numbers), from where.
func deal(t: SimTick, userid: int, info: DamageInfo, weapon: WeaponData) -> float:
	var target := t.roster.hit_target(userid)
	if target == null:
		return 0.0
	target.last_hit_direction = info.direction
	target.last_hit_from = info.origin
	target.last_hit_weapon = weapon
	return DamageInfo.deal(target, info, t.events)


# --- Positions in events --------------------------------------------------

## A point as an event's x, y and z, as Hitscan's bullet_impact gives them.
static func position_fields(at: Vector3) -> Dictionary:
	return {"x": at.x, "y": at.y, "z": at.z}


static func position_of(fields: Dictionary) -> Vector3:
	return Vector3(float(fields.get("x", 0.0)), float(fields.get("y", 0.0)), float(fields.get("z", 0.0)))


## Everything ended: a new round.
func clear() -> void:
	_blinds.clear()


func _primary_of(userid: int) -> String:
	var inventory := game.inventory(userid) if userid >= 0 else null
	if inventory == null:
		return ""
	var entry := inventory.item_in(ItemDef.Slot.PRIMARY)
	if entry == null:
		entry = inventory.item_in(ItemDef.Slot.PISTOL)
	return entry.item.item_class if entry != null else ""
