class_name MatchState
extends Node

## A match of rounds, as the server keeps it: warmup, then rounds of freeze
## time, play and a pause after, the score, the side swap at half time,
## overtime at 12-12, and the end of the match.
##
## It is simulation, not drawing. The world runs it on every tick, after
## the players have run theirs (GameWorld.end_tick), and it changes
## the game only through the players themselves: where they spawn, whether
## they come back when they die (only in warmup), whether they may move and
## fire (not in freeze time), and which side they are on. What is on screen
## (GameHud) reads it and never changes it, so a server can run it with a
## client drawing what it says.
##
## A round ends when a side that started it with players has none left
## alive, when the round's time runs out, which the counter-terrorists win
## because no bomb went off, or when the bomb goes off or is defused (its
## events). Once the bomb is down the round's clock no longer ends the
## round, and every terrorist dead no longer does either: the
## counter-terrorists still have to defuse it.
##
## It says what the round is doing as the game's events, as CS2's server
## does (reference/systems/contracts.md): round_announce_warmup,
## begin_new_match, round_officially_ended, round_prestart, round_start,
## round_poststart, round_freeze_end, round_end, announce_phase_end and
## cs_win_panel_match, into the events of the world that runs it (events).
## The economy, the bomb, the grenades and what lies on the ground go by
## them.
##
## A player spawns with CS2's knife and their side's pistol and nothing
## else (mp_t_default_secondary, mp_ct_default_secondary, mp_free_armor 0);
## the rest is bought. Someone who lived through the last round keeps what
## they carry.

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

## The game's events, where the match says what the round is doing and
## hears what the bomb does. The GameWorld that runs the match hands it its
## own (GameWorld.match_state); null for a match a check runs by hand, which
## then says nothing.
var events: GameEvents:
	set(value):
		if events != null:
			events.unlisten(&"bomb_planted", _on_bomb_planted)
			events.unlisten(&"bomb_exploded", _on_bomb_exploded)
			events.unlisten(&"bomb_defused", _on_bomb_defused)
		events = value
		if events != null:
			events.listen(&"bomb_planted", _on_bomb_planted)
			events.listen(&"bomb_exploded", _on_bomb_exploded)
			events.listen(&"bomb_defused", _on_bomb_defused)

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
## The bomb is down this round (bomb_planted): the clock and a dead T side no
## longer end it.
var _bomb_planted := false
## Warmup is to end on the next tick (F5, mp_warmup_end), so its spawns and
## events happen inside the tick like everything else.
var _warmup_end_asked := false


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
	_give_spawn_armor(player)


## Someone leaves the match: out of the game altogether (GameWorld).
func remove_player(player: PlayerSim) -> void:
	players.erase(player)


## Starts the match: warmup, where there is one, or the first round.
func start(now_usec: int = SimClock.now_usec()) -> void:
	if rules == null:
		rules = MatchRules.new()
	for player in players:
		player.team_damage_scale = rules.friendly_fire_bullets
		player.freeze_cam_seconds = rules.freeze_cam_seconds
		_give_spawn_armor(player)
	_score = {"T": 0, "CT": 0}
	_swapped = false
	_swap_next = false
	rounds_played = 0
	round_number = 0
	winner = ""
	if rules.warmup_seconds <= 0.0:
		_send(&"begin_new_match", {}, now_usec)
		_start_round(now_usec, true)
		return
	_send(&"round_announce_warmup", {}, now_usec)
	_spawn_everyone(true)
	for player in players:
		player.respawns = true
		player.frozen = false
	_enter(Phase.WARMUP, now_usec + _usec(rules.warmup_seconds))


## Ends warmup now and starts the first round (CS2's mp_warmup_end).
func end_warmup(now_usec: int = SimClock.now_usec()) -> void:
	if phase == Phase.WARMUP:
		_send(&"warmup_end", {}, now_usec)
		_send(&"begin_new_match", {}, now_usec)
		_start_round(now_usec, true)


## Ends warmup at the next tick: what a key (F5) asks for, from outside the
## tick.
func end_warmup_on_next_tick() -> void:
	_warmup_end_asked = true


## Moves the match on to where it stands at this moment of simulation time:
## the end of the tick the players have just run, when the world runs it.
func tick(now_usec: int) -> void:
	match phase:
		Phase.WARMUP:
			if now_usec >= phase_ends_usec or _warmup_end_asked:
				_warmup_end_asked = false
				end_warmup(now_usec)
		Phase.FREEZE:
			if now_usec >= phase_ends_usec:
				_go_live(now_usec)
		Phase.LIVE:
			var eliminated := _eliminated()
			if eliminated != Reason.NONE:
				end_round(winner_of(eliminated), eliminated, now_usec)
			elif now_usec >= phase_ends_usec and not _bomb_planted:
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
	_send(&"round_end", {
		"winner": side, "reason": GameEvents.round_end_reason(reason),
		"message": GameEvents.round_end_message(reason),
		"player_count": alive_on("T") + alive_on("CT"),
	}, now_usec)

	var next := _after_round()
	if next["over"]:
		winner = next["winner"]
		for player in players:
			player.frozen = true
			player.respawns = false
		_enter(Phase.OVER, now_usec)
		_send(&"cs_win_panel_match", {}, now_usec)
		match_over.emit(winner)
		return
	_swap_next = next["swap"]
	# The end of a half: half time, regulation into overtime (no swap), each
	# overtime half. CS2 announces it as the half's last round ends; the swap
	# and the money come at the next round's start.
	if _swap_next or rounds_played == rules.max_rounds:
		_send(&"announce_phase_end", {}, now_usec)
	# Half time (and each overtime half's): CS2's start_halftime, with the
	# swap.
	if _swap_next:
		_send(&"start_halftime", {}, now_usec)
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


func _enter(next: Phase, ends_usec: int) -> void:
	phase = next
	phase_ends_usec = ends_usec
	phase_changed.emit(next)


func _go_live(now_usec: int) -> void:
	for player in players:
		player.frozen = false
	_enter(Phase.LIVE, now_usec + _usec(rules.round_seconds))
	_send(&"round_freeze_end", {}, now_usec)


## A round starts: sides swapped if it is time, everyone at a spawn, still
## until freeze time is over, and nobody coming back who dies.
##
## CS2's order: round_prestart before anything else is done (handed out at
## once, so the ground is cleared and the bomb taken back before anyone
## spawns onto them), then the swap and the spawns, then round_start and
## round_poststart.
func _start_round(now_usec: int, fresh: bool) -> void:
	if phase == Phase.ROUND_END:
		_send(&"round_officially_ended", {}, now_usec)
	_send(&"round_prestart", {}, now_usec)
	if events != null:
		events.flush()
	if phase == Phase.WARMUP:
		# Warmup counted for nothing.
		_score = {"T": 0, "CT": 0}
		rounds_played = 0
	if _swap_next:
		_swap_sides()
		_swap_next = false
	_bomb_planted = false
	round_number = rounds_played + 1
	_spawn_everyone(fresh)
	for side in SIDES:
		_fielded[side] = alive_on(side) > 0
	for player in players:
		player.respawns = false
		player.frozen = rules.freeze_seconds > 0.0
	round_started.emit(round_number)
	_send(&"round_start", {"timelimit": roundi(rules.round_seconds)}, now_usec)
	var announced := announce_round()
	if not announced.is_empty():
		_send(announced, {}, now_usec)
	_send(&"round_poststart", {}, now_usec)
	if rules.freeze_seconds > 0.0:
		_enter(Phase.FREEZE, now_usec + _usec(rules.freeze_seconds))
	else:
		_go_live(now_usec)


## Everyone to the other side: the other side's model and hitboxes. They
## start the round fresh, as CS2 hands a team that has swapped nothing but
## the pistol and the money it starts with.
func _swap_sides() -> void:
	_swapped = not _swapped
	for player in players:
		player.change_team(other(player.team))
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


## What a player spawning this round is handed: CS2's knife and their
## side's pistol and nothing else, whatever gun they were given outside a
## match (the range's AK-47, a bot's own); the rest is bought. A spawn hands
## it out (PlayerSim.respawn); a survivor keeps what they carry.
func _arm(player: PlayerSim) -> void:
	player.starting_gun = null


## The armour a player spawns with, as a reset puts it back: none in
## competitive (mp_free_armor 0), kevlar, or kevlar and a helmet.
func _give_spawn_armor(player: PlayerSim) -> void:
	if player.hit_target == null or rules == null:
		return
	player.hit_target.wear(Inventory.FULL_ARMOR if rules.free_armor > 0 else 0.0, rules.free_armor >= 2)


## A side that started the round with players and has none alive. Both
## sides gone on the same tick is given to the terrorists, the
## counter-terrorists being checked first; how CS2 decides it is not known.
## With the bomb down, the terrorists all dead is not the end: the
## counter-terrorists still have to defuse it.
func _eliminated() -> Reason:
	if _fielded["CT"] and alive_on("CT") == 0:
		return Reason.CT_ELIMINATED
	if _fielded["T"] and alive_on("T") == 0 and not _bomb_planted:
		return Reason.T_ELIMINATED
	return Reason.NONE


## Says what happened, into the world's events, stamped with the moment of
## the transition (the economy times buying from it).
func _send(event_name: StringName, fields: Dictionary, at_usec: int) -> void:
	if events != null:
		events.send(event_name, fields, at_usec)


func _on_bomb_planted(_event: GameEvent) -> void:
	if phase == Phase.LIVE:
		_bomb_planted = true


func _on_bomb_exploded(event: GameEvent) -> void:
	end_round("T", Reason.BOMB_EXPLODED, event.at_usec)


func _on_bomb_defused(event: GameEvent) -> void:
	end_round("CT", Reason.BOMB_DEFUSED, event.at_usec)


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
	return _outcome(score("T"), score("CT"), rounds_played)


## The same for any score, rounds played: what the match does after a round
## that leaves it so (_after_round, and asking of the round about to be
## played, announce_round()).
func _outcome(t: int, ct: int, played: int) -> Dictionary:
	var result := {"over": false, "winner": "", "swap": false}
	var leader := "T" if t > ct else "CT"
	var regulation := rules.max_rounds
	@warning_ignore("integer_division")
	var half := regulation / 2

	if played <= regulation:
		if rules.can_clinch and maxi(t, ct) > half:
			result["over"] = true
			result["winner"] = leader
		elif played == regulation:
			if t != ct or not rules.overtime:
				result["over"] = true
				result["winner"] = leader if t != ct else ""
		elif played == half:
			result["swap"] = true
		return result

	var length := maxi(rules.overtime_rounds, 2)
	@warning_ignore("integer_division")
	var length_half := length / 2
	var into := played - regulation
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


## What CS2 announces of the round starting now, as its event, or empty:
## the match's first round (round_announce_match_start), the last round of
## regulation or of an overtime (round_announce_final), a round a side
## wins the match by winning (round_announce_match_point), the last round
## before a half ends (round_announce_last_round_half). One a round, the
## first of these that holds. The events are CS2's (game.gameevents); when
## in the round it sends them, and which it sends when two hold, is
## inferred from their names (audio-round.md; a Local check measures it).
func announce_round() -> StringName:
	if rounds_played == 0:
		return &"round_announce_match_start"
	var t := score("T")
	var ct := score("CT")
	var regulation := rules.max_rounds
	@warning_ignore("integer_division")
	var half := regulation / 2
	var next := rounds_played + 1
	var length := maxi(rules.overtime_rounds, 2)
	@warning_ignore("integer_division")
	var length_half := length / 2
	var last_of_regulation := next == regulation
	var into := next - regulation
	var last_of_overtime := into > 0 and into % length == 0
	if last_of_regulation or last_of_overtime:
		return &"round_announce_final"
	for side: String in SIDES:
		var won := _outcome(t + (1 if side == "T" else 0), ct + (1 if side == "CT" else 0), next)
		if won["over"] and won["winner"] == side:
			return &"round_announce_match_point"
	if next == half or (into > 0 and into % length == length_half):
		return &"round_announce_last_round_half"
	return &""


## The side a team on this side now started the match on.
func _started_as(side: String) -> String:
	return other(side) if _swapped else side


static func _usec(seconds: float) -> int:
	return int(roundf(seconds * 1_000_000.0))
