class_name RoundReport
extends RefCounted

## What the server says about a round once it is over: its MVP (round_mvp)
## and one fun fact about it (cs_win_panel_round), which the HUD's win panel
## shows (WinPanel). A system in the world's GameSystems: it keeps count of
## the round from the game's events (kills, headshots, damage, the bomb) and
## says the rest on round_end, in the same hand-out, so the win panel has it
## on the tick the round ends.
##
## How CS2 picks both is server code that is not in its files
## (reference/research/round-hud-bots.md A6, round-economy.md 4.6), so the
## rules here are the community's, written for CS:GO, and marked where they
## are guesses:
## - MVP: the defuser when the bomb is defused (with a kill that round),
##   the planter when it goes off, and otherwise whoever on the winning side
##   killed the most enemies, the first to join taking a tie. Nobody when the
##   winning side killed no one. The reason is CS2's number
##   (hudwinpanel.js _SetMVP): 9 for killing every one of five or more
##   enemies, 16 for four kills, 15 for three, 1 otherwise; 3 and 2 for the
##   bomb. The clutch, fire and blast reasons (13, 14, 10, 11) are not given:
##   their rules are unknown.
## - The fun fact: the first of FUN_FACTS that holds this round. The tokens,
##   and what each counts, are CS2's (csgo_english.txt); their order is a
##   guess.
##
## It reads the roster and nothing else; it never changes the game.

## The fun facts this can tell, in the order they are tried. Each is CS2's
## token (csgo_english.txt, "Round fun facts") without its leading '#'.
const FUN_FACTS: Array[String] = [
	"funfact_t_win_no_casualties", "funfact_ct_win_no_casualties",
	"funfact_kills_headshots", "funfact_killed_enemies",
	"funfact_bomb_planted_before_kill", "funfact_damage_no_kills",
	"funfact_first_blood", "funfact_short_round",
]
## The least a count must be for its fact to be told: two headshot kills
## and three kills are worth a line, one is not; a round with no kills needs
## 100 damage done to be one. Guesses.
const MOST_HEADSHOTS_AT_LEAST := 2
const KILLS_AT_LEAST := 3
const DAMAGE_AT_LEAST := 100
## A round this short, in seconds from the end of freeze time, is one.
const SHORT_ROUND_SECONDS := 30

## CS2's MVP reasons (hudwinpanel.js _SetMVP).
const MVP_KILLS := 1
const MVP_BOMB_PLANT := 2
const MVP_BOMB_DEFUSE := 3
const MVP_ACE := 9
const MVP_KILLS_THREE := 15
const MVP_KILLS_FOUR := 16
## An ace needs a side of at least this many.
const ACE_AT_LEAST := 5

var game: GameSystems

## The last round's report, as the win panel reads it: winner, reason (the
## round_end's name), mvp (a userid, or GameEvents.NOBODY), mvp_reason,
## mvp_value, funfact_token, funfact_player and funfact_data1 to 3. Empty
## until a round has ended, and emptied as the next starts.
var last := {}

## Whether a round is being played: its kills count.
var _counting := false
var _freeze_end_usec := 0
var _kills := {}
var _headshots := {}
## Health taken from enemies, by attacker.
var _damage := {}
## [attacker][victim]: {"damage", "hits"}, health taken from enemies only.
var _pairs := {}
var _deaths := {"T": 0, "CT": 0}
var _first_death_usec := -1
var _first_kill_usec := -1
var _first_killer := GameEvents.NOBODY
var _planter := GameEvents.NOBODY
var _plant_usec := -1
var _defuser := GameEvents.NOBODY


func attach(p_game: GameSystems) -> void:
	game = p_game
	var events := game.events
	events.listen(&"round_start", _on_round_start)
	events.listen(&"round_freeze_end", _on_freeze_end)
	events.listen(&"player_hurt", _on_hurt)
	events.listen(&"player_death", _on_death)
	events.listen(&"bomb_planted", _on_planted)
	events.listen(&"bomb_defused", _on_defused)
	events.listen(&"round_end", _on_round_end)
	events.listen(&"round_announce_warmup", func(_e: GameEvent) -> void: _reset())


func tick(_t: SimTick) -> void:
	pass


## The damage a player did to an enemy this round and in how many hits, and
## what they took back: {"given", "hits", "taken", "taken_hits"}, each given
## up to 100 as CS2's post-round report shows it (prdr_health_removed). For
## the team counter's report under a dead enemy's card.
func damage_between(you: int, enemy: int) -> Dictionary:
	var given: Dictionary = _pairs.get(you, {}).get(enemy, {})
	var taken: Dictionary = _pairs.get(enemy, {}).get(you, {})
	return {
		"given": mini(int(given.get("damage", 0)), 100), "hits": int(given.get("hits", 0)),
		"taken": mini(int(taken.get("damage", 0)), 100), "taken_hits": int(taken.get("hits", 0)),
	}


## Kills of enemies this round.
func kills_of(userid: int) -> int:
	return int(_kills.get(userid, 0))


func _reset() -> void:
	_counting = false
	_kills.clear()
	_headshots.clear()
	_damage.clear()
	_pairs.clear()
	_deaths = {"T": 0, "CT": 0}
	_first_death_usec = -1
	_first_kill_usec = -1
	_first_killer = GameEvents.NOBODY
	_planter = GameEvents.NOBODY
	_plant_usec = -1
	_defuser = GameEvents.NOBODY
	last = {}


func _on_round_start(event: GameEvent) -> void:
	_reset()
	_counting = true
	_freeze_end_usec = event.at_usec


func _on_freeze_end(event: GameEvent) -> void:
	_freeze_end_usec = event.at_usec


## Whether a hit or kill was on an enemy: not on yourself, a teammate, or
## by the world.
func _on_enemy(attacker: int, victim: int) -> bool:
	if attacker < 0 or attacker == victim:
		return false
	var side := game.roster.team_of(attacker)
	return not side.is_empty() and side != game.roster.team_of(victim)


func _on_hurt(event: GameEvent) -> void:
	var attacker: int = event.fields["attacker"]
	var victim: int = event.fields["userid"]
	if not _counting or not _on_enemy(attacker, victim):
		return
	var taken := int(event.fields["dmg_health"])
	_damage[attacker] = int(_damage.get(attacker, 0)) + taken
	if not _pairs.has(attacker):
		_pairs[attacker] = {}
	var pair: Dictionary = _pairs[attacker].get(victim, {"damage": 0, "hits": 0})
	pair["damage"] += taken
	pair["hits"] += 1
	_pairs[attacker][victim] = pair


func _on_death(event: GameEvent) -> void:
	if not _counting:
		return
	var victim: int = event.fields["userid"]
	var attacker: int = event.fields["attacker"]
	var side := game.roster.team_of(victim)
	if _deaths.has(side):
		_deaths[side] += 1
	if _first_death_usec < 0:
		_first_death_usec = event.at_usec
	if not _on_enemy(attacker, victim):
		return
	if _first_kill_usec < 0:
		_first_kill_usec = event.at_usec
		_first_killer = attacker
	_kills[attacker] = kills_of(attacker) + 1
	if event.fields["headshot"]:
		_headshots[attacker] = int(_headshots.get(attacker, 0)) + 1


func _on_planted(event: GameEvent) -> void:
	if _counting:
		_planter = event.fields["userid"]
		_plant_usec = event.at_usec


func _on_defused(event: GameEvent) -> void:
	if _counting:
		_defuser = event.fields["userid"]


func _on_round_end(event: GameEvent) -> void:
	if not _counting:
		return
	_counting = false
	var winner := String(event.fields["winner"])
	var reason := String(event.fields["reason"])
	var mvp := pick_mvp(winner, reason)
	var fact := pick_fun_fact(winner, reason, event.at_usec)
	last = {
		"winner": winner, "reason": reason,
		"mvp": mvp[0], "mvp_reason": mvp[1], "mvp_value": mvp[2],
		"funfact_token": fact[0], "funfact_player": fact[1],
		"funfact_data1": fact[2], "funfact_data2": 0, "funfact_data3": 0,
	}
	if mvp[0] != GameEvents.NOBODY:
		game.events.send(&"round_mvp", {"userid": mvp[0], "reason": mvp[1], "value": mvp[2]}, event.at_usec)
	game.events.send(&"cs_win_panel_round", {
		"funfact_token": ("#" + fact[0]) if not String(fact[0]).is_empty() else "",
		"funfact_player": fact[1], "funfact_data1": fact[2],
	}, event.at_usec)


## The round's MVP, as [userid, reason, value]; [NOBODY, 0, 0] for none.
## reason is round_end's by name ("BombDefused", "TargetBombed", ...).
func pick_mvp(winner: String, reason: String) -> Array:
	if reason == "BombDefused" and _defuser != GameEvents.NOBODY and kills_of(_defuser) > 0:
		return [_defuser, MVP_BOMB_DEFUSE, kills_of(_defuser)]
	if reason == "TargetBombed" and _planter != GameEvents.NOBODY:
		return [_planter, MVP_BOMB_PLANT, kills_of(_planter)]
	var best := GameEvents.NOBODY
	for userid in game.roster.on_team(winner):
		if kills_of(userid) > kills_of(best):
			best = userid
	if best == GameEvents.NOBODY:
		return [GameEvents.NOBODY, 0, 0]
	var kills := kills_of(best)
	var enemies := game.roster.on_team(MatchState.other(winner)).size()
	var why := MVP_KILLS
	if enemies >= ACE_AT_LEAST and kills >= enemies:
		why = MVP_ACE
	elif kills == 4:
		why = MVP_KILLS_FOUR
	elif kills == 3:
		why = MVP_KILLS_THREE
	return [best, why, kills]


## The round's fun fact, as [token without '#', userid, data1]; ["", NOBODY,
## 0] when none holds.
func pick_fun_fact(winner: String, reason: String, end_usec: int) -> Array:
	var loser := MatchState.other(winner)
	for token in FUN_FACTS:
		match token:
			"funfact_t_win_no_casualties", "funfact_ct_win_no_casualties":
				var side := "T" if token.begins_with("funfact_t_") else "CT"
				if side == winner and _deaths[winner] == 0 and _deaths[loser] > 0:
					return [token, GameEvents.NOBODY, 0]
			"funfact_kills_headshots":
				var who := _most(_headshots)
				if int(_headshots.get(who, 0)) >= MOST_HEADSHOTS_AT_LEAST:
					return [token, who, _headshots[who]]
			"funfact_killed_enemies":
				var who := _most(_kills)
				if kills_of(who) >= KILLS_AT_LEAST:
					return [token, who, kills_of(who)]
			"funfact_damage_no_kills":
				var who := GameEvents.NOBODY
				for userid: int in _damage:
					if kills_of(userid) == 0 and int(_damage[userid]) > int(_damage.get(who, 0)):
						who = userid
				if int(_damage.get(who, 0)) >= DAMAGE_AT_LEAST:
					return [token, who, _damage[who]]
			"funfact_first_blood":
				if _first_killer != GameEvents.NOBODY:
					return [token, _first_killer, _seconds_in(_first_kill_usec)]
			"funfact_bomb_planted_before_kill":
				if _plant_usec >= 0 and (_first_death_usec < 0 or _first_death_usec > _plant_usec):
					return [token, GameEvents.NOBODY, 0]
			"funfact_short_round":
				var seconds := _seconds_in(end_usec)
				if reason != "TargetSaved" and seconds <= SHORT_ROUND_SECONDS:
					return [token, GameEvents.NOBODY, seconds]
	return ["", GameEvents.NOBODY, 0]


## Whole seconds from the end of freeze time, at least one.
func _seconds_in(at_usec: int) -> int:
	@warning_ignore("integer_division")
	return maxi(1, int((at_usec - _freeze_end_usec) / 1_000_000))


## Whoever has the most in counts; the first to join takes a tie.
func _most(counts: Dictionary) -> int:
	var best := GameEvents.NOBODY
	for userid in game.roster.ids():
		if int(counts.get(userid, 0)) > int(counts.get(best, 0)):
			best = userid
	return best
