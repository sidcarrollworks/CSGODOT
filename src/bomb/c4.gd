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
const SECOND_USEC := 1_000_000


## One player as the bomb sees them in a tick: built by whoever runs the
## tick, from the player's state after they have run their command.
class Actor:
	## The player's id, as the game events carry it (CS2's userid).
	var id: int = NOBODY
	var team: String = ""
	var alive: bool = true
	## Where they stand, their eyes, and the way they look.
	var feet: Vector3 = Vector3.ZERO
	var eyes: Vector3 = Vector3.ZERO
	var aim: Vector3 = Vector3.FORWARD
	var on_ground: bool = true
	## Holding the attack button with the bomb in hand: the plant.
	var plant_held: bool = false
	## Holding the use key: the defuse.
	var use_held: bool = false
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
		actor.feet = player.global_position
		actor.eyes = player.global_position + Vector3.UP * player.eye_height()
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
			_tick_carried(now_usec, _find(actors, carrier), sites)
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
## timer of this length. A guess, until C1 measures the cadence: a beep a
## second when it is planted, closing in steadily to ten a second at the
## end, which is how it sounds. Only what is heard uses it (C4View); the
## simulation does not beep.
static func beep_interval(seconds_left_now: float, timer: float) -> float:
	var left := clampf(seconds_left_now / maxf(timer, 0.001), 0.0, 1.0)
	return lerpf(0.1, 1.0, left)


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


func _tick_carried(now_usec: int, actor: Actor, sites: Array[BombSite]) -> void:
	if actor == null or not actor.alive:
		# Dropped where its carrier fell (CS2's mp_death_drop_c4).
		_drop(now_usec, actor.feet if actor != null else position, false)
		return
	position = actor.feet
	if actor.drop and not planting():
		_drop(now_usec, actor.feet, true)
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
	for actor in actors:
		if not actor.alive or actor.team != "T":
			continue
		if actor.id == dropped_by and now_usec < redrop_usec:
			continue
		var across := Vector2(actor.feet.x - position.x, actor.feet.z - position.z).length()
		var up := position.y - actor.feet.y
		if across > rules.pickup_reach or absf(up) > rules.pickup_height:
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


## Whether a player holding use now can defuse: a living
## counter-terrorist on the ground, close to the bomb and looking at it.
func _can_defuse(actor: Actor) -> bool:
	if not actor.alive or actor.team != "CT" or not actor.use_held or not actor.on_ground:
		return false
	var to_bomb := position - actor.eyes
	var distance := to_bomb.length()
	if distance > rules.defuse_reach:
		return false
	if distance < 1.0:
		return true
	return actor.aim.normalized().dot(to_bomb / distance) >= cos(deg_to_rad(rules.defuse_cone_degrees))


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
