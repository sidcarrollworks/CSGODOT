class_name InfernoEntity
extends SimEntity

## A molotov's or an incendiary's fire on the ground (CS2's inferno): it
## spreads (FireSpread), burns whoever stands in it in steps, goes out when
## its time is up or smoke covers it, and says each of those as CS2's
## events. Stepped on the tick with the game's other entities.
##
## The burn is a DamageInfo each step (DMG_BURN, no zone), credited to the
## thrower for GrenadeRules.FIRE_THROWER_SECONDS and to nobody after, and
## armour does not soften it.

const ENTITY_CLASS := "inferno"

var system: GrenadeSystem
## The thrower's side when it was thrown, for team damage.
var team: String = ""
## GrenadeRules.MOLOTOV or INCENDIARY: the item credited with the burn.
var weapon_class: String = ""
var fire: FireSpread

var _started: bool = false
var _next_burn_usec: int = 0
## When each player, by userid, began standing in it without a step out.
var _burning_since := {}


func _init() -> void:
	super(ENTITY_CLASS)


func tick(t: SimTick) -> void:
	if not _started:
		_started = true
		_next_burn_usec = fire.started_usec + _step_usec()
		_send(t, &"inferno_startburn")
	if fire.extinguished:
		_send(t, &"inferno_extinguish")
		remove()
		return
	fire.spread(t.space, t.now_usec, func(point: Vector3) -> bool:
		return not system.in_smoke(point + Vector3.UP * 8.0, t.now_usec))
	while _next_burn_usec <= t.now_usec and _next_burn_usec <= fire.ends_usec():
		_burn(t, _next_burn_usec)
		_next_burn_usec += _step_usec()
	if fire.out(t.now_usec):
		_send(t, &"inferno_expire")
		remove()


## One step of burning, at a simulation time, for everyone standing in it.
func _burn(t: SimTick, at_usec: int) -> void:
	var per_step := GrenadeRules.damage(weapon_class) * GrenadeRules.FIRE_DAMAGE_STEP
	var credited := at_usec - fire.started_usec < int(GrenadeRules.FIRE_THROWER_SECONDS * 1_000_000.0)
	for userid in t.roster.ids():
		var player := t.roster.player(userid) as PlayerSim
		if player == null or not player.alive or not fire.burns(player.global_position + Vector3.UP * 1.0):
			_burning_since.erase(userid)
			continue
		if not _burning_since.has(userid):
			_burning_since[userid] = at_usec
		var standing := float(at_usec - int(_burning_since[userid])) / 1_000_000.0
		var ramp := lerpf(GrenadeRules.FIRE_RAMP_FROM, 1.0, clampf(standing / GrenadeRules.FIRE_RAMP_SECONDS, 0.0, 1.0))
		var amount := per_step * ramp
		if credited and userid != owner_id and not team.is_empty() and t.roster.team_of(userid) == team:
			amount *= system.team_damage_scale
		var info := DamageInfo.new()
		info.attacker = owner_id if credited else GameEvents.NOBODY
		info.inflictor = ENTITY_CLASS
		info.weapon = weapon_class if credited else ""
		info.damage = amount
		info.damage_type = DamageInfo.DMG_BURN
		info.origin = fire.origin
		info.position = player.global_position
		info.direction = (player.global_position - fire.origin).normalized()
		# Armour does not soften fire, nor wear from it.
		info.armor_penetration = 1.0
		info.armor_wear = 0.0
		info.at_usec = at_usec
		system.deal(t, userid, info, null)


func _step_usec() -> int:
	return int(GrenadeRules.FIRE_DAMAGE_STEP * 1_000_000.0)


func _send(t: SimTick, name: StringName) -> void:
	var fields := {"entityid": id}
	fields.merge(GrenadeSystem.position_fields(fire.origin))
	t.events.send(name, fields)
