class_name Knife
extends RefCounted

## The knife in a player's hand: its two attacks, what each reaches and
## does, and when the next may come. One a player, kept on PlayerSim, run by
## its commands on the tick like the guns (PlayerSim._update_knife).
##
## The left button slashes (a light attack) and the right stabs (a heavy
## one), each again for as long as it is held. A swing is traced the moment
## it is made, from the eye along the aim: a line first, and where the line
## meets nobody, a ring of lines out to the edges of a box round its end, as
## CS's knife falls back to a hull trace (reference/research/combat.md 2).
## Both meet the hitboxes the guns' rounds meet. Enemies are looked for
## first, through teammates; a teammate is hit only when no enemy is in
## reach (Valve's notes of 2 November 2023). From behind a swing is a
## backstab.
##
## What CS2's files give (reference/weapons/vdata.csv, weapon_knife): the
## armour ratio 1.7 (85% through kevlar), the flinch modifier 0.3, the draw
## of 1.0 s, the $1,500 kill award and the 250 speed, which the knife's
## WeaponData and ItemDef read from there. Its damage, reach, swing rates and
## backstab angle are in no file of the game's (the 50 and 4096 its entry
## carries are the class's defaults, equipment.md): every number below that
## says "K1" is the community's figure or a guess, until Sid's local agent
## measures them in CS2 (reference/cs2-systems.md K1; combat.md's table says
## how).

## Damage, before armour, and flat wherever it lands: CS's knife has no
## hit-group multiplier (the fandom Knife page; combat.md 2 lists vdata's
## headshot multiplier 4.0 as the class default, to measure in K1). The
## light attack does LIGHT_FIRST on a swing that starts a run and LIGHT
## after; a backstab does its own. Commonly cited, CS:GO era (fandom Knife
## page by web search, combat.md 2): K1.
const LIGHT_FIRST_DAMAGE := 40.0
const LIGHT_DAMAGE := 25.0
const HEAVY_DAMAGE := 65.0
const LIGHT_BACKSTAB_DAMAGE := 90.0
const HEAVY_BACKSTAB_DAMAGE := 180.0

## How far each attack reaches from the eye, in units, and the half-width of
## the box a swing that meets nothing on its line is widened to. 48 and 32
## are the figures usually given, a line then a box; they are from memory
## and probably trace back to Valve's code (combat.md 2): K1.
const LIGHT_REACH := 48.0
const HEAVY_REACH := 32.0
const WIDEN := 16.0

## Seconds from one swing to the next of the same button held down: about
## 0.4 a slash and 1.0 a stab (a guide's figures by web search, not
## measured; combat.md 2): K1. The stab stops the slash for as long.
const LIGHT_CYCLE := 0.4
const HEAVY_CYCLE := 1.0

## A slash that comes within this long of the last slash's start carries a
## run on, and does LIGHT_DAMAGE; any later, or the first since the knife
## was drawn (Valve, 2 November 2023: "a swing right after drawing always
## does full damage"), starts one. How long CS2 waits is in no source found
## (combat.md 2): a guess, twice the slash's cycle, for K1 to measure.
const RUN_WITHIN := 0.8

## A backstab: the victim's facing, flat, within this cosine of the way
## from the attacker to them, so the attacker is within about 60 degrees of
## straight behind. A guess (combat.md 2: "backstab angle unknown"), for K1
## to measure a turn of 5 degrees at a time.
const BACKSTAB_COS := 0.5

## What a swing met.
enum Outcome { MISS, WALL, PLAYER }

## The class the knife goes by in events and damage: both sides' knives are
## weapon_knife to the game's rules (the T's model is weapon_knife_t, a look
## of it: WeaponLibrary.look).
const ITEM_CLASS := "weapon_knife"


## One swing and what it did, for the game's events and for whoever draws
## and sounds it (PlayerSim.knife_swung).
class Swing:
	var heavy: bool = false
	var outcome: Outcome = Outcome.MISS
	var backstab: bool = false
	## Which of the attack's first-person clips it plays: slashes alternate
	## between two (light_hit1 and light_hit2), a stab has one.
	var variation: int = 0
	## A slash that started a run (LIGHT_FIRST_DAMAGE).
	var first: bool = false
	## When, in simulation time, and from where along which way.
	var at_usec: int = 0
	var origin := Vector3.ZERO
	var direction := Vector3.ZERO
	## Where it met the wall or the body; the hitbox it met.
	var position := Vector3.ZERO
	var normal := Vector3.ZERO
	var hitbox: Hitbox
	## The damage before armour, and what it did (DamageInfo.deal), when it
	## met someone.
	var damage: float = 0.0
	var damage_info: DamageInfo

	## The first-person clip it plays, as the knives' sets name them
	## (reference/weapons/equipment.md): light_hit1, light_miss2,
	## heavy_backstab... A wall is a hit to the hand.
	func clip() -> StringName:
		var kind := "heavy" if heavy else "light"
		if backstab:
			return StringName("%s_backstab%s" % [kind, "2" if not heavy and variation == 1 else ""])
		var met := "miss" if outcome == Outcome.MISS else "hit"
		return StringName("%s_%s%d" % [kind, met, 1 if heavy else variation + 1])

	## What it met, as CS2's graph names its attacks (attack_knife_lighthit,
	## heavymiss, lightbackstab...): "backstab", "hit" (a body or a wall)
	## or "miss".
	func met() -> String:
		if backstab:
			return "backstab"
		return "miss" if outcome == Outcome.MISS else "hit"

	## CS2's sound events for it (reference/research/audio-gameplay.md
	## 1.2): the swish of every swing, and the miss's slash, the wall's hit
	## or the body's, light or heavy, from the front or behind.
	func sound_events() -> PackedStringArray:
		var names := PackedStringArray(["Weapon_Knife.Swish.Heavy" if heavy else "Weapon_Knife.Swish.Light"])
		match outcome:
			Outcome.MISS:
				names.append("Weapon_Knife.Slash")
			Outcome.WALL:
				names.append("Weapon_Knife.HitWall")
			Outcome.PLAYER:
				names.append("Weapon_Knife.Hit.%s%s.Flesh" % ["Heavy" if heavy else "Light", ".Backstab" if backstab else ""])
		return names


## Every sound event a swing can start, to be read before play.
static func all_sound_events() -> PackedStringArray:
	var names := PackedStringArray()
	for heavy in [false, true]:
		for outcome in [Outcome.MISS, Outcome.WALL, Outcome.PLAYER]:
			for backstab in [false, true]:
				var swing := Swing.new()
				swing.heavy = heavy
				swing.outcome = outcome
				swing.backstab = backstab and outcome == Outcome.PLAYER
				for event_name in swing.sound_events():
					if not names.has(event_name):
						names.append(event_name)
	return names


## The knife's numbers from the game's file, as a gun's are read: what a
## hit's armour and tagging go by (HitTarget.last_hit_weapon). Read once.
static var _data: WeaponData


static func data() -> WeaponData:
	if _data == null:
		_data = WeaponData.new()
		_data.display_name = "Knife"
		_data.item_class = ITEM_CLASS
		WeaponVData.apply(_data, ITEM_CLASS)
	return _data


## When the next swing may start, in simulation time.
var ready_usec: int = 0
## When the last slash started; negative when none has since the draw.
var _last_light_usec: int = -1
## Slashes since the draw, for the clips to alternate.
var _lights: int = 0


## Taken in hand at now_usec: nothing swings until the draw is over, and the
## next slash starts a run.
func draw(now_usec: int, deploy_seconds: float) -> void:
	ready_usec = now_usec + int(roundf(deploy_seconds * 1_000_000.0))
	_last_light_usec = -1
	_lights = 0


## Whether a swing may start at at_usec.
func is_ready(at_usec: int) -> bool:
	return at_usec >= ready_usec


## A swing starting at at_usec: its damage, the clip it plays and when the
## next may come, before it is traced (swing()).
func begin(heavy: bool, at_usec: int) -> Swing:
	var swing := Swing.new()
	swing.heavy = heavy
	swing.at_usec = at_usec
	if heavy:
		swing.damage = HEAVY_DAMAGE
		ready_usec = at_usec + int(roundf(HEAVY_CYCLE * 1_000_000.0))
	else:
		swing.first = _last_light_usec < 0 or at_usec - _last_light_usec > int(roundf(RUN_WITHIN * 1_000_000.0))
		swing.damage = LIGHT_FIRST_DAMAGE if swing.first else LIGHT_DAMAGE
		swing.variation = _lights % 2
		_lights += 1
		_last_light_usec = at_usec
		ready_usec = at_usec + int(roundf(LIGHT_CYCLE * 1_000_000.0))
	return swing


## Whether an attacker at `from` striking a victim who faces `faces` (the
## way they look, flat or not) is behind them.
static func is_behind(from: Vector3, victim_at: Vector3, faces: Vector3) -> bool:
	var toward := victim_at - from
	toward.y = 0.0
	var facing := Vector3(faces.x, 0.0, faces.z)
	if toward.length_squared() < 1e-6 or facing.length_squared() < 1e-6:
		return false
	return toward.normalized().dot(facing.normalized()) > BACKSTAB_COS


## The damage a swing does to someone, before armour: its own, or a
## backstab's.
static func damage_for(heavy: bool, first: bool, backstab: bool) -> float:
	if backstab:
		return HEAVY_BACKSTAB_DAMAGE if heavy else LIGHT_BACKSTAB_DAMAGE
	if heavy:
		return HEAVY_DAMAGE
	return LIGHT_FIRST_DAMAGE if first else LIGHT_DAMAGE


## The lines a swing is traced along, from the eye: its own first, then the
## ring out to the box round its end (WIDEN each way, across and up).
static func lines(origin: Vector3, direction: Vector3, reach: float) -> PackedVector3Array:
	var end := origin + direction * reach
	var across := direction.cross(Vector3.UP)
	if across.length_squared() < 1e-6:
		across = Vector3.RIGHT
	across = across.normalized()
	var up := across.cross(direction).normalized()
	var ends := PackedVector3Array([end])
	for x in [-1.0, 0.0, 1.0]:
		for y in [-1.0, 0.0, 1.0]:
			if x != 0.0 or y != 0.0:
				ends.append(end + across * (x * WIDEN) + up * (y * WIDEN))
	return ends


## Traces the swing (begun with begin()) from origin along direction, and
## deals its damage to whoever it meets: the nearest enemy hitbox on its
## line or, meeting none, on its ring; a teammate's the same way only when
## no enemy is in reach, at team_damage_scale. exclude is the attacker's own
## hull and hitboxes, teammates the hitboxes of their side's. The damage
## goes through DamageInfo.deal on events (null for none), so a kill is
## credited as a round's is.
static func swing(
	space: PhysicsDirectSpaceState3D, begun: Swing, origin: Vector3, direction: Vector3,
	attacker: int, team: String, team_damage_scale: float,
	exclude: Array[RID], teammates: Array[RID], events: GameEvents
) -> Swing:
	begun.origin = origin
	begun.direction = direction.normalized()
	var reach := HEAVY_REACH if begun.heavy else LIGHT_REACH
	var ends := lines(origin, begun.direction, reach)
	var past_teammates := exclude.duplicate()
	past_teammates.append_array(teammates)
	var met := _nearest_body(space, origin, ends, past_teammates)
	if met.is_empty() and not teammates.is_empty():
		met = _nearest_body(space, origin, ends, exclude)
	if met.is_empty():
		# Nobody: the wall on its own line, if one is in reach.
		var line := PhysicsRayQueryParameters3D.create(origin, ends[0], Hitscan.WORLD_LAYER, exclude)
		var wall := PhysicsQueries.intersect_ray(space, line)
		if not wall.is_empty():
			begun.outcome = Outcome.WALL
			begun.position = wall["position"]
			begun.normal = wall["normal"]
		return begun
	var hitbox := met["collider"] as Hitbox
	begun.outcome = Outcome.PLAYER
	begun.position = met["position"]
	begun.normal = met["normal"]
	begun.hitbox = hitbox
	var target := hitbox.target
	if target == null:
		return begun
	begun.backstab = is_behind(origin, target.global_position, _facing(target))
	begun.damage = damage_for(begun.heavy, begun.first, begun.backstab)
	if not team.is_empty() and target.team == team:
		begun.damage *= team_damage_scale
	target.last_hit_direction = begun.direction
	target.last_hit_from = origin
	target.last_hit_weapon = data()
	var info := DamageInfo.new()
	info.attacker = attacker
	info.inflictor = ITEM_CLASS
	info.weapon = ITEM_CLASS
	info.damage = begun.damage
	info.damage_type = DamageInfo.DMG_SLASH
	info.zone = hitbox.zone
	info.side = hitbox.side
	info.hitbox = hitbox
	info.origin = origin
	info.position = begun.position
	info.direction = begun.direction
	info.at_usec = begun.at_usec
	info.armor_penetration = data().armor_penetration
	DamageInfo.deal(target, info, events)
	begun.damage_info = info
	return begun


## The nearest hitbox on any of the lines, walls in the way: the swing's own
## line alone if it meets one, as the hull trace is only the fallback.
## Empty for none.
static func _nearest_body(
	space: PhysicsDirectSpaceState3D, origin: Vector3, ends: PackedVector3Array, exclude: Array[RID]
) -> Dictionary:
	var nearest := {}
	var nearest_at := INF
	for i in ends.size():
		var query := PhysicsRayQueryParameters3D.create(origin, ends[i], Hitscan.WORLD_LAYER | Hitbox.LAYER, exclude)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		var met := PhysicsQueries.intersect_ray(space, query)
		if met.is_empty() or not met["collider"] is Hitbox:
			continue
		var at := origin.distance_to(met["position"])
		if at < nearest_at:
			nearest = met
			nearest_at = at
		if i == 0:
			break
	return nearest


## The way whoever wears target looks: a player's aim, or the target's own
## facing (-Z) for anything else.
static func _facing(target: HitTarget) -> Vector3:
	var node: Node = target.get_parent()
	if node is PlayerSim:
		var yaw := deg_to_rad((node as PlayerSim).yaw_degrees)
		return Vector3(-sin(yaw), 0.0, -cos(yaw))
	return -target.global_basis.z
