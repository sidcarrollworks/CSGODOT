class_name DamageInfo
extends RefCounted

## One lot of damage to one player, and who and what did it: CS's
## CTakeDamageInfo.
##
## Every source of damage fills one (a round, the knife, the Zeus, an HE,
## a fire, the bomb, a fall) and hands it to deal(), so a death always knows
## who killed whom with what, which is what kill awards, the kill feed and
## the scoreboard are made of. The source fills what it knows; the victim's
## HitTarget.take_damage fills in what the damage did.

## Source's damage types, as bits. Falling ignores armour.
const DMG_GENERIC := 0
const DMG_BULLET := 2
const DMG_SLASH := 4
const DMG_BURN := 8
const DMG_FALL := 32
const DMG_BLAST := 64
const DMG_SHOCK := 256

## CS2's hit groups, as its events number them.
const HITGROUP_GENERIC := 0
const HITGROUP_HEAD := 1
const HITGROUP_CHEST := 2
const HITGROUP_STOMACH := 3
const HITGROUP_LEFT_ARM := 4
const HITGROUP_RIGHT_ARM := 5
const HITGROUP_LEFT_LEG := 6
const HITGROUP_RIGHT_LEG := 7

# What the source fills.

## Who did it, by userid (Roster); GameEvents.NOBODY for the world.
var attacker: int = GameEvents.NOBODY
## The entity that did it, by CS2 class: "weapon_ak47" for a round,
## "hegrenade_projectile", "inferno", "planted_c4", "worldspawn" for a fall.
var inflictor: String = ""
## The item credited with it, by CS2 class: what the kill award and the
## kill feed go by. "weapon_hegrenade" for an HE, "weapon_molotov" or
## "weapon_incgrenade" for its fire, "weapon_c4" for the bomb, "" for the
## world.
var weapon: String = ""
## How much, before armour: range, hit group, walls and a teammate's share
## already taken into account.
var damage: float = 0.0
var damage_type: int = DMG_GENERIC
## Where it landed on the body (&"head", &"chest", &"stomach", &"arm",
## &"leg"), or &"" for damage with no one place (a blast, fire, a fall).
var zone: StringName = &""
## &"left", &"right" or &"" for a limb.
var side: StringName = &""
## The hitbox a round came through, for the body to fall from it. Local to
## the simulation: never sent.
var hitbox: Hitbox
## Where it came from (a muzzle, a grenade, the bomb), where it landed, and
## which way it was going.
var origin := Vector3.ZERO
var position := Vector3.ZERO
var direction := Vector3.ZERO
## When, in microseconds of simulation time.
var at_usec: int = 0
## The share of the damage that gets through armour: a gun's
## WeaponData.armor_penetration (the game's armour ratio halved).
var armor_penetration: float = 1.0
## Armour points lost for each point of damage armour takes.
var armor_wear: float = 0.5
## How many walls a round went through first.
var walls: int = 0
## A round from a gun with a scope, fired without it (Weapon.Shot.noscope).
var noscope: bool = false

# What the victim fills (HitTarget.take_damage).

## The victim's userid.
var victim: int = GameEvents.NOBODY
var health_taken: float = 0.0
var armor_taken: float = 0.0
## Whether armour took a share.
var armored: bool = false
var health_left: float = 0.0
var armor_left: float = 0.0
var killed: bool = false


## CS2's hit group for where it landed.
var hitgroup: int:
	get: return hitgroup_of(zone, side)


var headshot: bool:
	get: return zone == &"head"


## Whether armour can soften it: falling goes straight to health.
var armorable: bool:
	get: return damage_type & DMG_FALL == 0


static func hitgroup_of(p_zone: StringName, p_side: StringName = &"") -> int:
	match p_zone:
		&"head":
			return HITGROUP_HEAD
		&"chest":
			return HITGROUP_CHEST
		&"stomach":
			return HITGROUP_STOMACH
		&"arm":
			return HITGROUP_RIGHT_ARM if p_side == &"right" else HITGROUP_LEFT_ARM
		&"leg":
			return HITGROUP_RIGHT_LEG if p_side == &"right" else HITGROUP_LEFT_LEG
	return HITGROUP_GENERIC


## Deals info to target, and says so on events (null for no events):
## player_hurt for any damage that landed, player_death as well when it
## killed. The damage actually taken from health.
static func deal(target: HitTarget, info: DamageInfo, events: GameEvents = null) -> float:
	if target == null or not target.alive:
		return 0.0
	var taken := target.take_damage(info)
	if events == null:
		return taken
	events.send(&"player_hurt", {
		"userid": info.victim,
		"attacker": info.attacker,
		"health": ceili(info.health_left),
		"armor": ceili(info.armor_left),
		"weapon": info.weapon,
		"dmg_health": roundi(info.health_taken),
		"dmg_armor": roundi(info.armor_taken),
		"hitgroup": info.hitgroup,
	}, info.at_usec if info.at_usec > 0 else -1)
	if info.killed:
		events.send(&"player_death", {
			"userid": info.victim,
			"attacker": info.attacker,
			"weapon": info.weapon,
			"headshot": info.headshot,
			"penetrated": info.walls,
			"noscope": info.noscope,
			"distance": info.origin.distance_to(info.position),
			"dmg_health": roundi(info.health_taken),
			"dmg_armor": roundi(info.armor_taken),
			"hitgroup": info.hitgroup,
		}, info.at_usec if info.at_usec > 0 else -1)
	return taken
