class_name MatchState
extends Node

## A match of rounds, as the server keeps it: warmup, then rounds of freeze
## time, play and a pause after, the score, the side swap at half time,
## overtime at 12-12, and the end of the match.
##
## It is simulation, not drawing. It advances on the simulation's clock
## (SimClock), one tick after the players have run theirs, and it changes
## the game only through the players themselves: where they spawn, whether
## they come back when they die (only in warmup), whether they may move and
## fire (not in freeze time), and which side they are on. What is on screen
## (GameHud) reads it and never changes it, so a server can run it with a
## client drawing what it says.
##
## A round ends when a side that started it with players has none left
## alive, or when the round's time runs out, which the counter-terrorists
## win because no bomb went off. The bomb is not in yet (roadmap item 16):
## when it is, it ends rounds through end_round with its own reasons, and a
## planted bomb stops the round's clock from ending the round.
##
## Until there is an inventory and buying (roadmap items 12 and 14), a
## player who starts a round fresh is handed their side's rifle, the AK-47
## or the M4A1-S, in place of a pistol and the money to buy one.

enum Phase {
	## Everyone plays, dies and comes back; nothing counts.
	WARMUP,
	## A round's first seconds: everyone at their spawn, free to look round,
	## not to move or fire.
	FREEZE,
	## The round is being played.
	LIVE,
	## The round is won; play goes on until the next one starts, but it no
	## longer counts, and the dead stay dead.
	ROUND_END,
	## Someone has won the match, or it is drawn. Everyone stands still.
	OVER,
}

## Why a round ended. Which side it names is the side that lost it or the
## thing that happened, as CS2's round-end reasons are named.
enum Reason {
	NONE,
	## Every terrorist is dead: the counter-terrorists win.
	T_ELIMINATED,
	## Every counter-terrorist is dead: the terrorists win.
	CT_ELIMINATED,
	## The round's time ran out with no bomb down: the counter-terrorists win.
	TIME_RAN_OUT,
	## For the bomb (roadmap item 16): it went off, and the terrorists win;
	## it was defused, and the counter-terrorists do.
	BOMB_EXPLODED,
	BOMB_DEFUSED,
}

const SIDES: Array[String] = ["T", "CT"]

## A phase began; round_started comes with FREEZE, with the round's number.
signal phase_changed(phase: Phase)
signal round_started(number: int)
## The side that won the round and why.
signal round_ended(winner: String, reason: Reason)
## Everyone has changed sides, before they spawn for the round: whoever
## hands out routes and loadouts by side does it now.
signal sides_swapped
## The side that won the match, or "" for a draw.
signal match_over(winner: String)

@export var rules: MatchRules

## Everyone in the match.
var players: Array[PlayerSim] = []
## Where each side spawns, as SourceEntities.player_spawns gives them:
## {"T": [{position, yaw, priority}, ...], "CT": [...]}, in priority order.
var spawns: Dictionary = {"T": [], "CT": []}

var phase: Phase = Phase.WARMUP
## When the current phase runs out, in microseconds of simulation time.
var phase_ends_usec: int = 0
## The round being played, from 1; 0 in warmup.
var round_number: int = 0
## Rounds won by either side so far.
var rounds_played: int = 0
## How the last round went.
var last_winner: String = ""
var last_reason: Reason = Reason.NONE
## Who won the match once it is over: a side, or "" for a draw.
var winner: String = ""

## Rounds won, by the side each team started the match on, since the score
## stays with the team and not with the side.
var _score := {"T": 0, "CT": 0}
## Whether the teams are on the other side from where they started.
var _swapped := false
## Whether the next round starts with everyone on the other side.
var _swap_next := false
## Which sides started the round with anyone on them: a side nobody plays
## cannot be eliminated.
var _fielded := {"T": false, "CT": false}


func _init() -> void:
	# After the players: a round is judged on the tick they have just run.
	process_physics_priority = 100


func _ready() -> void:
	if rules == null:
		rules = MatchRules.new()


## Someone joins the match, on the side they are on.
func add_player(player: PlayerSim) -> void:
	if players.has(player):
		return
	players.append(player)
	player.team_damage_scale = rules.friendly_fire_bullets if rules != null else 1.0
	player.freeze_cam_seconds = rules.freeze_cam_seconds if rules != null else 2.0


## Starts the match: warmup, where there is one, or the first round.
func start(now_usec: int = SimClock.now_usec()) -> void:
	if rules == null:
		rules = MatchRules.new()
	for player in players:
		player.team_damage_scale = rules.friendly_fire_bullets
		player.freeze_cam_seconds = rules.freeze_cam_seconds
	_score = {"T": 0, "CT": 0}
	_swapped = false
	_swap_next = false
	rounds_played = 0
	round_number = 0
	winner = ""
	if rules.warmup_seconds <= 0.0:
		_start_round(now_usec, true)
		return
	_spawn_everyone(true)
	for player in players:
		player.respawns = true
		player.frozen = false
	_enter(Phase.WARMUP, now_usec + _usec(rules.warmup_seconds))


## Ends warmup now and starts the first round (CS2's mp_warmup_end).
func end_warmup(now_usec: int = SimClock.now_usec()) -> void:
	if phase == Phase.WARMUP:
		_start_round(now_usec, true)


func _physics_process(_delta: float) -> void:
	tick(SimClock.now_usec())


## Moves the match on to where it stands at this moment of simulation time.
func tick(now_usec: int) -> void:
	match phase:
		Phase.WARMUP:
			if now_usec >= phase_ends_usec:
				end_warmup(now_usec)
		Phase.FREEZE:
			if now_usec >= phase_ends_usec:
				_go_live(now_usec)
		Phase.LIVE:
			var eliminated := _eliminated()
			if eliminated != Reason.NONE:
				end_round(winner_of(eliminated), eliminated, now_usec)
			elif now_usec >= phase_ends_usec:
				end_round("CT", Reason.TIME_RAN_OUT, now_usec)
		Phase.ROUND_END:
			if now_usec >= phase_ends_usec:
				_start_round(now_usec, _swap_next)


## The round is won: the score, and whether the match is over or the sides
## swap before the next. Only a round being played can end.
func end_round(side: String, reason: Reason, now_usec: int = SimClock.now_usec()) -> void:
	if phase != Phase.LIVE:
		return
	_score[_started_as(side)] += 1
	rounds_played += 1
	last_winner = side
	last_reason = reason
	round_ended.emit(side, reason)

	var next := _after_round()
	if next["over"]:
		winner = next["winner"]
		for player in players:
			player.frozen = true
			player.respawns = false
		_enter(Phase.OVER, now_usec)
		match_over.emit(winner)
		return
	_swap_next = next["swap"]
	var pause := rules.halftime_seconds if _swap_next else rules.round_restart_seconds
	_enter(Phase.ROUND_END, now_usec + _usec(pause))


## The side a round-end reason gives the round to.
static func winner_of(reason: Reason) -> String:
	match reason:
		Reason.CT_ELIMINATED, Reason.BOMB_EXPLODED:
			return "T"
	return "CT"


## Rounds won by the team on this side now.
func score(side: String) -> int:
	return _score[_started_as(side)]


## Players on a side still alive.
func alive_on(side: String) -> int:
	var count := 0
	for player in players:
		if player.team == side and player.alive:
			count += 1
	return count


## Seconds left on the current phase's clock; none in the phases that have
## no end of their own.
func seconds_left(now_usec: int = SimClock.now_usec()) -> float:
	if phase == Phase.OVER:
		return 0.0
	return maxf(0.0, float(phase_ends_usec - now_usec) / 1_000_000.0)


## Whether the round just finished is the last before the sides swap.
func swapping_next() -> bool:
	return phase == Phase.ROUND_END and _swap_next


## In overtime: more rounds played than regulation has.
func in_overtime() -> bool:
	return round_number > rules.max_rounds


static func other(side: String) -> String:
	return "CT" if side == "T" else "T"


## What the weapon a player on this side starts with is, until they can buy.
static func starting_weapon(side: String) -> WeaponData:
	return WeaponLibrary.m4a1s() if side == "CT" else WeaponLibrary.ak47()


func _enter(next: Phase, ends_usec: int) -> void:
	phase = next
	phase_ends_usec = ends_usec
	phase_changed.emit(next)


func _go_live(now_usec: int) -> void:
	for player in players:
		player.frozen = false
	_enter(Phase.LIVE, now_usec + _usec(rules.round_seconds))


## A round starts: sides swapped if it is time, everyone at a spawn, still
## until freeze time is over, and nobody coming back who dies.
func _start_round(now_usec: int, fresh: bool) -> void:
	if phase == Phase.WARMUP:
		# Warmup counted for nothing.
		_score = {"T": 0, "CT": 0}
		rounds_played = 0
	if _swap_next:
		_swap_sides()
		_swap_next = false
	round_number = rounds_played + 1
	_spawn_everyone(fresh)
	for side in SIDES:
		_fielded[side] = alive_on(side) > 0
	for player in players:
		player.respawns = false
		player.frozen = rules.freeze_seconds > 0.0
	round_started.emit(round_number)
	if rules.freeze_seconds > 0.0:
		_enter(Phase.FREEZE, now_usec + _usec(rules.freeze_seconds))
	else:
		_go_live(now_usec)


## Everyone to the other side: the other side's model, hitboxes and rifle.
## They start the round fresh, as CS2 hands a team that has swapped nothing
## but the pistol and the money it starts with.
func _swap_sides() -> void:
	_swapped = not _swapped
	for player in players:
		var side := other(player.team)
		var bot := player as Bot
		if bot != null:
			var data := starting_weapon(side)
			bot.weapon_model = data.model_path
			bot.arm(data)
		player.change_team(side)
	sides_swapped.emit()


## Every player at one of their side's spawn points, in the order the map
## gives them priority, dealt out in a shuffle seeded by the round so a
## server and a client deal them the same way. A fresh start (the first
## round, after warmup or a side swap) takes everything back to a new
## player's; otherwise the round's survivors keep what they had.
func _spawn_everyone(fresh: bool) -> void:
	for side in SIDES:
		var members: Array[PlayerSim] = []
		for player in players:
			if player.team == side:
				members.append(player)
		if members.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([round_number, side, rounds_played])
		_shuffle(members, rng)
		var points := _spawn_order(spawns.get(side, []), rng)
		for i in members.size():
			var player := members[i]
			if fresh:
				_arm(player)
			if points.is_empty():
				player.spawn_at(player.global_position, player.yaw_degrees, fresh)
			else:
				var point: Dictionary = points[i % points.size()]
				player.spawn_at(point["position"], point["yaw"], fresh)


## The spawn points in the order they are filled: by priority, the lowest
## first, shuffled among those of equal priority.
static func _spawn_order(points: Array, rng: RandomNumberGenerator) -> Array:
	var groups := {}
	for point: Dictionary in points:
		var priority := int(point.get("priority", 0))
		if not groups.has(priority):
			groups[priority] = []
		groups[priority].append(point)
	var keys := groups.keys()
	keys.sort()
	var ordered := []
	for key in keys:
		var group: Array = groups[key]
		_shuffle(group, rng)
		ordered.append_array(group)
	return ordered


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var kept = items[i]
		items[i] = items[j]
		items[j] = kept


## A fresh player's weapon: their side's rifle.
func _arm(player: PlayerSim) -> void:
	var data := starting_weapon(player.team)
	var bot := player as Bot
	if bot != null:
		if bot.weapon_data == null or bot.weapon_data.display_name != data.display_name:
			bot.arm(data)
	elif player.weapon == null or player.weapon.data.display_name != data.display_name:
		player.equip(data)


## A side that started the round with players and has none alive. Both
## sides gone on the same tick is given to the terrorists, the
## counter-terrorists being checked first; how CS2 decides it is not known.
func _eliminated() -> Reason:
	if _fielded["CT"] and alive_on("CT") == 0:
		return Reason.CT_ELIMINATED
	if _fielded["T"] and alive_on("T") == 0:
		return Reason.T_ELIMINATED
	return Reason.NONE


## After a round is scored: whether the match is over and who won it, and
## whether the sides swap before the next round.
##
## Regulation: the sides swap after half the rounds; more than half of them
## wins (a clinch); all of them played and level goes to overtime, or is a
## draw without it. Overtime: the sides stay as they were for its first
## half and swap for its second, and swap again before the next overtime;
## more than half of an overtime's rounds wins it, and level at its end
## goes to another, or is a draw once the limit is reached.
func _after_round() -> Dictionary:
	var result := {"over": false, "winner": "", "swap": false}
	var t := score("T")
	var ct := score("CT")
	var leader := "T" if t > ct else "CT"
	var regulation := rules.max_rounds
	@warning_ignore("integer_division")
	var half := regulation / 2

	if rounds_played <= regulation:
		if rules.can_clinch and maxi(t, ct) > half:
			result["over"] = true
			result["winner"] = leader
		elif rounds_played == regulation:
			if t != ct or not rules.overtime:
				result["over"] = true
				result["winner"] = leader if t != ct else ""
		elif rounds_played == half:
			result["swap"] = true
		return result

	var length := maxi(rules.overtime_rounds, 2)
	@warning_ignore("integer_division")
	var length_half := length / 2
	var into := rounds_played - regulation
	@warning_ignore("integer_division")
	var index := (into - 1) / length
	var played_in_this := into - index * length
	var level_at_start := half + index * length_half
	if maxi(t, ct) - level_at_start > length_half:
		result["over"] = true
		result["winner"] = leader
	elif played_in_this == length:
		if rules.overtime_limit > 0 and index + 1 >= rules.overtime_limit:
			result["over"] = true
			result["winner"] = ""
		else:
			result["swap"] = true
	elif played_in_this == length_half:
		result["swap"] = true
	return result


## The side a team on this side now started the match on.
func _started_as(side: String) -> String:
	return other(side) if _swapped else side


static func _usec(seconds: float) -> int:
	return int(roundf(seconds * 1_000_000.0))
