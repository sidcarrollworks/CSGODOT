class_name C4
extends RefCounted

## The bomb, as the server keeps it: who carries it, where it lies, the
## plant, the countdown, the defuse and the explosion.
##
## It is simulation, run once a tick after the players (tick), and it knows
## the players only as ids and what each did that tick (Actor), never as
## nodes: whoever runs the tick (the GameWorld, the test range until then)
## builds an Actor per player from the player and their command. What it
## decides it keeps as plain state, with every timer a deadline in
## simulation microseconds, so save_state and load_state copy it whole.
## What happened goes out as CS2's game events (take_events), with the
## names and keys of the shared schema (reference/systems/contracts.md), and
## the explosion's damage as one record per player it reaches (take_blast):
## both plain data, which a bomb system on the shared contracts sends as
## events and deals as DamageInfo (reference/systems/bomb.md).
##
## What is drawn and heard (C4View) reads it and never changes it. The
## round (who wins when it goes off or is defused, the round's clock giving
## way to the bomb's) is MatchState's, from these events and planted();
## reference/systems/bomb.md has the rules for wiring it in.

enum State {
	## Not in play: before a round hands it out, and on a map without sites.
	NONE,
	## On a terrorist, in their inventory.
	CARRIED,
	## On the ground where a carrier dropped it or died.
	DROPPED,
	## Down on a site and counting.
	PLANTED,
	## The round's bomb is spent.
	DEFUSED,
	EXPLODED,
}

## No player.
const NOBODY := -1
## No deadline.
const NEVER := -1
## Where a standing player's middle is, above their feet.
const BODY_MIDDLE := 36.0
## The dropped bomb's box for E (UseSearch), about where it lies: its hull
## in reference/weapons/physics.csv is 9.3 x 2.8 x 6.9, and which way it
## lies is not kept, so the long side goes both ways.
const DROPPED_BOX := AABB(Vector3(-4.65, 0.0, -4.65), Vector3(9.3, 2.8, 9.3))
## A player's hull across, for E on a bot carrying the bomb.
const HULL_HALF := 16.0
const SECOND_USEC := 1_000_000


## One player as the bomb sees them in a tick: built by whoever runs the
## tick, from the player's state after they have run their command.
class Actor:
	## The player's id, as the game events carry it (CS2's userid).
	var id: int = NOBODY
	var team: String = ""
	var alive: bool = true
	## Run by a bot, which leaves the bomb to a human teammate
	## (C4Rules.bot_defer_to_human_items).
	var is_bot: bool = false
	## Where they stand, their eyes, and the way they look.
	var feet: Vector3 = Vector3.ZERO
	var eyes: Vector3 = Vector3.ZERO
	## Their hull's height, standing or ducked.
	var height: float = 72.0
	var aim: Vector3 = Vector3.FORWARD
	var on_ground: bool = true
	## Holding the attack button with the bomb in hand: the plant.
	var plant_held: bool = false
	## Holding the use key: the defuse.
	var use_held: bool = false
	## Pressing the use key this tick: a terrorist takes the bomb off the
	## ground with it from further than a touch (C4Rules.use_reach), or from
	## a bot teammate carrying it (take_from_bot).
	var use_pressed: bool = false
	## Asking to drop the bomb this tick (CS2's drop key with it in hand).
	var drop: bool = false
	## Carrying a defuse kit.
	var has_kit: bool = false

	## An actor from a player in the simulation: where they are after the
	## tick and what they hold. What their command asks of the bomb is the
	## caller's to say, since only the caller knows which item is in hand.
	static func of_player(player: PlayerSim, player_id: int) -> Actor:
		var actor := Actor.new()
		actor.id = player_id
		actor.team = player.team
		actor.alive = player.alive
		actor.is_bot = player.is_bot
		actor.feet = player.global_position
		actor.eyes = player.global_position + Vector3.UP * player.eye_height()
		actor.height = player.config.duck_height if player.is_ducked else player.config.stand_height
		actor.aim = PlayerInput.aim_direction(player.yaw_degrees, player.pitch_degrees)
		actor.on_ground = player.on_ground
		return actor


var rules: C4Rules

var state: State = State.NONE
## Whoever has it, planted it or is defusing it; NOBODY when nobody does.
var carrier: int = NOBODY
var planter: int = NOBODY
var defuser: int = NOBODY
## Where it is: on its carrier's feet, on the ground, or where it was planted.
var position: Vector3 = Vector3.ZERO
## The site it was planted on (or is being planted on), "" when none.
var site: String = ""

## When the carrier's plant began, and the site they began it on.
var plant_started_usec: int = NEVER
## When it was planted and when it goes off.
var planted_usec: int = NEVER
var explodes_usec: int = NEVER
## When the defuse began and when it will be done, and whether with a kit.
var defuse_started_usec: int = NEVER
var defuse_ends_usec: int = NEVER
var defuse_with_kit: bool = false
## The player who dropped it, and when they may pick it up again.
var dropped_by: int = NOBODY
var redrop_usec: int = NEVER

## The site each player stood on last tick, by id, for enter_bombzone and
## exit_bombzone.
var _in_zone: Dictionary = {}

var _events: Array[Dictionary] = []
var _blast: Array[Dictionary] = []


func _init(p_rules: C4Rules = null) -> void:
	rules = p_rules if p_rules != null else C4Rules.new()


## The round hands the bomb to a terrorist (CS2 picks one at random; the
## caller does, from its own seeded numbers).
func give_to(player_id: int, feet: Vector3 = Vector3.ZERO) -> void:
	_clear()
	state = State.CARRIED
	carrier = player_id
	position = feet
	_event("player_given_c4", {"userid": carrier})


## Out of play, as at the end of a round before the next hands it out.
func reset() -> void:
	_clear()
	state = State.NONE


## Runs the bomb one tick, after the players have run theirs. now_usec is
## the end of the tick (SimClock.tick_end_usec). sites are the places it
## can be planted.
func tick(now_usec: int, actors: Array[Actor], sites: Array[BombSite]) -> void:
	_track_zones(actors, sites)
	match state:
		State.CARRIED:
			_tick_carried(now_usec, _find(actors, carrier), sites, actors)
		State.DROPPED:
			_tick_dropped(now_usec, actors)
		State.PLANTED:
			_tick_planted(now_usec, actors)


## Whether a player is planting or defusing, which holds them still as CS2
## does: whoever runs the tick stops their movement (as freeze time does)
## until it ends. A planter can look round; so can a defuser.
func holds_still(player_id: int) -> bool:
	if player_id == NOBODY:
		return false
	return (planting() and carrier == player_id) or (defusing() and defuser == player_id)


func planting() -> bool:
	return state == State.CARRIED and plant_started_usec != NEVER


func planted() -> bool:
	return state == State.PLANTED


func defusing() -> bool:
	return state == State.PLANTED and defuser != NOBODY


## How far through the plant the carrier is, 0 to 1; 0 when not planting.
func plant_progress(now_usec: int) -> float:
	if not planting():
		return 0.0
	return clampf(float(now_usec - plant_started_usec) / (rules.plant_seconds * SECOND_USEC), 0.0, 1.0)


## How far through the defuse the defuser is, 0 to 1; 0 when nobody is.
func defuse_progress(now_usec: int) -> float:
	if not defusing():
		return 0.0
	return clampf(
		float(now_usec - defuse_started_usec) / float(defuse_ends_usec - defuse_started_usec), 0.0, 1.0
	)


## Seconds left on the bomb's timer; 0 when it is not counting.
func seconds_left(now_usec: int) -> float:
	if state != State.PLANTED:
		return 0.0
	return maxf(float(explodes_usec - now_usec) / SECOND_USEC, 0.0)


## Seconds since it was planted; 0 when it is not counting.
func seconds_planted(now_usec: int) -> float:
	if state != State.PLANTED:
		return 0.0
	return maxf(float(now_usec - planted_usec) / SECOND_USEC, 0.0)


## The game events since the last call, oldest first, each a Dictionary
## with its CS2 name under "name" and CS2's keys beside it.
func take_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


## The explosion's damage since the last call: one record per player it
## reached, {victim, attacker, weapon, amount, origin}, the amount before
## armour. Empty until it goes off.
func take_blast() -> Array[Dictionary]:
	var out := _blast
	_blast = []
	return out


## The damage the blast does at a distance from the bomb, before armour.
## The rule before CS2's July 2026 shockwave: bomb_damage at the bomb,
## falling off as a bell curve whose standard deviation is a third of the
## reach, bomb_damage times radius_scale, and nothing past the reach. Walls
## do not shield anyone from it.
static func blast_damage(distance: float, bomb_damage: float, radius_scale: float = 3.5) -> float:
	var reach := bomb_damage * radius_scale
	if distance > reach or reach <= 0.0:
		return 0.0
	var sigma := reach / 3.0
	return bomb_damage * exp(-(distance * distance) / (2.0 * sigma * sigma))


## Seconds from one beep to the next, with this many seconds left on a
## timer of this length: the beeps a second, 1.04865 * e^(0.244018 x +
## 1.763798 x^2) with x the share of the timer gone, from 1.05 at the plant
## to 7.8 at the end (0.95 s apart to 0.13 s). That is Wouter Gritter's fit
## to CS:GO's beeps (reference/research/round-bomb-grenades.md 1.3); that CS2
## kept it is inferred from its client scheduling beeps by the share gone,
## and the bomb's Local check C1 times a few in CS2. Only what is heard uses
## it (C4View); the simulation does not beep.
static func beep_interval(seconds_left_now: float, timer: float) -> float:
	var gone := 1.0 - clampf(seconds_left_now / maxf(timer, 0.001), 0.0, 1.0)
	return 1.0 / (1.04865 * exp(0.244018 * gone + 1.763798 * gone * gone))


## Everything the bomb is, as plain data, to put back with load_state.
func save_state() -> Dictionary:
	return {
		"state": state,
		"carrier": carrier,
		"planter": planter,
		"defuser": defuser,
		"position": position,
		"site": site,
		"plant_started_usec": plant_started_usec,
		"planted_usec": planted_usec,
		"explodes_usec": explodes_usec,
		"defuse_started_usec": defuse_started_usec,
		"defuse_ends_usec": defuse_ends_usec,
		"defuse_with_kit": defuse_with_kit,
		"dropped_by": dropped_by,
		"redrop_usec": redrop_usec,
		"in_zone": _in_zone.duplicate(),
	}


func load_state(saved: Dictionary) -> void:
	state = saved["state"]
	carrier = saved["carrier"]
	planter = saved["planter"]
	defuser = saved["defuser"]
	position = saved["position"]
	site = saved["site"]
	plant_started_usec = saved["plant_started_usec"]
	planted_usec = saved["planted_usec"]
	explodes_usec = saved["explodes_usec"]
	defuse_started_usec = saved["defuse_started_usec"]
	defuse_ends_usec = saved["defuse_ends_usec"]
	defuse_with_kit = saved["defuse_with_kit"]
	dropped_by = saved["dropped_by"]
	redrop_usec = saved["redrop_usec"]
	_in_zone = (saved["in_zone"] as Dictionary).duplicate()


func _tick_carried(now_usec: int, actor: Actor, sites: Array[BombSite], actors: Array[Actor] = []) -> void:
	if actor == null or not actor.alive:
		# Dropped where its carrier fell (CS2's mp_death_drop_c4).
		_drop(now_usec, actor.feet if actor != null else position, false)
		return
	position = actor.feet
	if actor.drop and not planting():
		_drop(now_usec, actor.feet, true)
		return
	if not planting():
		var taker := _taker_from(actor, actors)
		if taker != null:
			carrier = taker.id
			position = taker.feet
			_event("bomb_pickup", {"userid": carrier})
			return

	var on_site := _site_at(actor.feet, sites)
	var can_plant := actor.plant_held and actor.on_ground and actor.team == "T" and on_site != ""
	if planting():
		if not can_plant or on_site != site:
			_event("bomb_abortplant", {"userid": carrier, "site": site})
			plant_started_usec = NEVER
			site = ""
		elif now_usec - plant_started_usec >= roundi(rules.plant_seconds * SECOND_USEC):
			_plant(now_usec)
		return
	if can_plant:
		plant_started_usec = now_usec
		site = on_site
		_event("bomb_beginplant", {"userid": carrier, "site": site})


func _plant(now_usec: int) -> void:
	state = State.PLANTED
	planter = carrier
	carrier = NOBODY
	plant_started_usec = NEVER
	planted_usec = now_usec
	explodes_usec = now_usec + roundi(rules.timer_seconds * SECOND_USEC)
	_event("bomb_planted", {"userid": planter, "site": site})


func _drop(now_usec: int, at: Vector3, by_choice: bool) -> void:
	var was := carrier
	plant_started_usec = NEVER
	site = ""
	state = State.DROPPED
	carrier = NOBODY
	position = at
	dropped_by = was if by_choice else NOBODY
	redrop_usec = now_usec + roundi(rules.redrop_seconds * SECOND_USEC) if by_choice else NEVER
	# entindex is the dropped bomb's entity id, which whoever keeps the
	# world's entities gives it (the contract's SimEntities); none here.
	_event("bomb_dropped", {"userid": was, "entindex": NOBODY})


func _tick_dropped(now_usec: int, actors: Array[Actor]) -> void:
	var nearest: Actor = null
	var nearest_distance := INF
	var bots_defer := rules.bot_defer_to_human_items and actors.any(
		func(actor: Actor) -> bool: return actor.alive and actor.team == "T" and not actor.is_bot)
	for actor in actors:
		if not actor.alive or actor.team != "T":
			continue
		if bots_defer and actor.is_bot:
			continue
		if actor.id == dropped_by and now_usec < redrop_usec:
			continue
		var across := Vector2(actor.feet.x - position.x, actor.feet.z - position.z).length()
		var up := position.y - actor.feet.y
		if (across > rules.pickup_reach or absf(up) > rules.pickup_height) and not (actor.use_pressed and _use_on_bomb(actor)):
			continue
		if across < nearest_distance:
			nearest = actor
			nearest_distance = across
	if nearest == null:
		return
	state = State.CARRIED
	carrier = nearest.id
	dropped_by = NOBODY
	redrop_usec = NEVER
	position = nearest.feet
	_event("bomb_pickup", {"userid": carrier})


func _tick_planted(now_usec: int, actors: Array[Actor]) -> void:
	# A defuse that ends by the time the bomb would go off wins; one that
	# would end after it loses to it.
	if defusing() and now_usec >= defuse_ends_usec and defuse_ends_usec <= explodes_usec:
		var actor := _find(actors, defuser)
		if actor != null and _can_defuse(actor):
			state = State.DEFUSED
			_event("bomb_defused", {"userid": defuser, "site": site})
			return
	if now_usec >= explodes_usec:
		_explode(actors)
		return

	if defusing():
		var actor := _find(actors, defuser)
		if actor == null or not _can_defuse(actor):
			_event("bomb_abortdefuse", {"userid": defuser})
			defuser = NOBODY
			defuse_started_usec = NEVER
			defuse_ends_usec = NEVER
			defuse_with_kit = false
		return

	var nearest: Actor = null
	var nearest_distance := INF
	for actor in actors:
		if not _can_defuse(actor):
			continue
		var distance := actor.eyes.distance_to(position)
		if distance < nearest_distance:
			nearest = actor
			nearest_distance = distance
	if nearest == null:
		return
	defuser = nearest.id
	defuse_with_kit = nearest.has_kit
	defuse_started_usec = now_usec
	var seconds := rules.kit_defuse_seconds if nearest.has_kit else rules.defuse_seconds
	defuse_ends_usec = now_usec + roundi(seconds * SECOND_USEC)
	_event("bomb_begindefuse", {"userid": defuser, "haskit": defuse_with_kit})


## Whether E is the bomb's for this player now, before anything on the
## ground (CS2's sv_weapon_swap_difficulty_near_hi_pri: no cone search near
## a high-priority item): a living counter-terrorist in reach of the
## planted bomb and looking at it, or its defuser; a living terrorist in
## E's reach of the dropped bomb and looking at it; a human terrorist
## taking it from a bot (take_from_bot, which needs the carrier).
func claims_use(actor: Actor, carrier_actor: Actor = null) -> bool:
	if not actor.alive:
		return false
	match state:
		State.PLANTED:
			return actor.team == "CT" and (actor.id == defuser or _looked_at(actor, rules.defuse_reach, rules.defuse_cone_degrees))
		State.DROPPED:
			return actor.team == "T" and _use_on_bomb(actor)
		State.CARRIED:
			return take_from_bot(actor, carrier_actor)
	return false


## CS2's "[E] Take Bomb" (Panorama_HUD_botid_request_bomb in
## csgo_english.txt): whether this actor, pressing E, takes the bomb from
## its carrier. A living human terrorist, from a living bot terrorist who
## carries it and is not planting, with E on the bot's hull (UseSearch, the
## search E on a gun makes, within C4Rules.use_reach). CS2 has the prompt
## and its string; that the search is the same and that the bot's hull is
## what it finds are inferred, as is the event (bomb_pickup for the one who
## takes it). There is no sight test yet (playtest-2026-09-25.md issue 18).
func take_from_bot(actor: Actor, carrier_actor: Actor) -> bool:
	if actor == null or carrier_actor == null or state != State.CARRIED or planting():
		return false
	if not actor.alive or actor.is_bot or actor.team != "T" or actor.id == carrier_actor.id:
		return false
	if carrier_actor.id != carrier or not carrier_actor.alive or not carrier_actor.is_bot:
		return false
	var hull := AABB(Vector3(-HULL_HALF, 0.0, -HULL_HALF), Vector3(HULL_HALF * 2.0, carrier_actor.height, HULL_HALF * 2.0))
	return _use_on(actor, Transform3D(Basis.IDENTITY, carrier_actor.feet), hull)


## Whoever takes the bomb from its bot carrier this tick: the first actor
## pressing E who may (take_from_bot); null if none.
func _taker_from(carrier_actor: Actor, actors: Array[Actor]) -> Actor:
	for actor in actors:
		if actor.use_pressed and take_from_bot(actor, carrier_actor):
			return actor
	return null


## Whether the actor's E is on the dropped bomb (UseSearch, within
## C4Rules.use_reach), with no sight test.
func _use_on_bomb(actor: Actor) -> bool:
	return _use_on(actor, Transform3D(Basis.IDENTITY, position), DROPPED_BOX)


## Whether the actor's E is on a box: UseSearch with the box alone, so
## nothing else on the ground is weighed against it (near the bomb E is
## the bomb's, claims_use).
func _use_on(actor: Actor, body: Transform3D, box: AABB) -> bool:
	return UseSearch.find(actor.eyes, actor.aim, actor.feet, actor.height, [UseSearch.Target.new(body, box)], Callable(), rules.use_reach) == 0


## Whether the bomb is within reach of the actor's eyes and within
## cone_degrees of their aim.
func _looked_at(actor: Actor, reach: float, cone_degrees: float) -> bool:
	return _looks_at(actor, position, reach, cone_degrees)


## Whether a point is within reach of the actor's eyes and within
## cone_degrees of their aim.
func _looks_at(actor: Actor, point: Vector3, reach: float, cone_degrees: float) -> bool:
	var to_bomb := point - actor.eyes
	var distance := to_bomb.length()
	if distance > reach:
		return false
	if distance < 1.0:
		return true
	return actor.aim.normalized().dot(to_bomb / distance) >= cos(deg_to_rad(cone_degrees))


## Whether a player holding use now can defuse: a living
## counter-terrorist on the ground, close to the bomb and looking at it.
func _can_defuse(actor: Actor) -> bool:
	if not actor.alive or actor.team != "CT" or not actor.use_held or not actor.on_ground:
		return false
	return _looked_at(actor, rules.defuse_reach, rules.defuse_cone_degrees)


func _explode(actors: Array[Actor]) -> void:
	state = State.EXPLODED
	if defuser != NOBODY:
		defuser = NOBODY
	_event("bomb_exploded", {"userid": planter, "site": site})
	for actor in actors:
		if not actor.alive:
			continue
		# Measured to the middle of the body, as a blast is.
		var middle := actor.feet + Vector3.UP * 36.0
		var amount := blast_damage(middle.distance_to(position), rules.bomb_damage, rules.radius_scale)
		if amount <= 0.0:
			continue
		_blast.append({
			"victim": actor.id,
			"attacker": planter,
			"weapon": "weapon_c4",
			"amount": amount,
			"origin": position,
		})


## CS2's enter_bombzone and exit_bombzone, as each living player steps on
## and off a site: the HUD's "you are in a bomb zone" and bots read them.
func _track_zones(actors: Array[Actor], sites: Array[BombSite]) -> void:
	for actor in actors:
		var now_on := _site_at(actor.feet, sites) if actor.alive else ""
		var was_on: String = _in_zone.get(actor.id, "")
		if now_on == was_on:
			continue
		var keys := {"userid": actor.id, "hasbomb": carrier == actor.id, "isplanted": state == State.PLANTED}
		if was_on != "":
			_event("exit_bombzone", keys)
		if now_on != "":
			_event("enter_bombzone", keys)
		if now_on == "":
			_in_zone.erase(actor.id)
		else:
			_in_zone[actor.id] = now_on


static func _site_at(feet: Vector3, sites: Array[BombSite]) -> String:
	for candidate in sites:
		if candidate.contains(feet):
			return candidate.letter
	return ""


static func _find(actors: Array[Actor], player_id: int) -> Actor:
	if player_id == NOBODY:
		return null
	for actor in actors:
		if actor.id == player_id:
			return actor
	return null


func _event(event_name: String, keys: Dictionary) -> void:
	var event := {"name": event_name}
	event.merge(keys)
	_events.append(event)


func _clear() -> void:
	carrier = NOBODY
	planter = NOBODY
	defuser = NOBODY
	site = ""
	plant_started_usec = NEVER
	planted_usec = NEVER
	explodes_usec = NEVER
	defuse_started_usec = NEVER
	defuse_ends_usec = NEVER
	defuse_with_kit = false
	dropped_by = NOBODY
	redrop_usec = NEVER
