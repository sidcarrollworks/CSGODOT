class_name MatchStats
extends RefCounted

## Each player's numbers for the match, as CS2's scoreboard (Tab) shows them:
## kills, deaths, assists, headshot kills (for its HS%), the health they took
## from enemies (its DMG) and the rounds they were MVP. A system in the
## world's GameSystems, counting from the game's events (player_hurt,
## player_death, round_mvp); the scoreboard only reads it (Scoreboard).
##
## CS2's own counting is server code that is not in its files; what its
## scoreboard shows is (scoreboard.js, reference/research/round-hud-bots.md
## A4). The rules here, and which are guesses:
## - A kill of an enemy counts one. Killing a teammate or yourself takes one
##   away, as CS:GO's scoreboard did (a guess for CS2). A death counts
##   whoever killed you, the world included.
## - An assist is player_death's assister (KillCredit's rule).
## - DMG is the health taken from enemies (player_hurt's dmg_health), never
##   more than they had; a teammate's is not counted.
## - HS% is the headshot kills over the kills, rounded down.
## - Warmup counts, and everything starts again as the match does
##   (begin_new_match), as CS2's scoreboard goes back to nothing then.
## - Once the match is decided (cs_win_panel_match) no damage or death
##   counts: whatever still burns or goes off on the end screen does not
##   change the final scoreboard. The last round's MVP, sent after, still
##   does. What CS2 does is not known; this is the least surprising.
##
## It reads the roster and nothing else; it never changes the game.

var game: GameSystems

## By userid: {"kills", "deaths", "assists", "headshots", "damage", "mvps"}.
var _stats := {}
## The match is decided: damage and deaths no longer count.
var _over := false

const ZERO := {"kills": 0, "deaths": 0, "assists": 0, "headshots": 0, "damage": 0, "mvps": 0}


func attach(p_game: GameSystems) -> void:
	game = p_game
	var events := game.events
	events.listen(&"player_hurt", _on_hurt)
	events.listen(&"player_death", _on_death)
	events.listen(&"round_mvp", _on_mvp)
	events.listen(&"begin_new_match", _start_again)
	events.listen(&"round_announce_warmup", _start_again)
	events.listen(&"cs_win_panel_match", func(_e: GameEvent) -> void: _over = true)


func tick(_t: SimTick) -> void:
	pass


## A player's numbers, a copy: ZERO's keys, each 0 until they count.
func of(userid: int) -> Dictionary:
	return _stats.get(userid, ZERO).duplicate()


## CS2's HS%: the headshot kills over the kills, as a whole percentage
## rounded down; 0 without a kill.
static func headshot_percent(stats: Dictionary) -> int:
	var kills := int(stats["kills"])
	if kills <= 0:
		return 0
	@warning_ignore("integer_division")
	return int(stats["headshots"]) * 100 / kills


func _add(userid: int, stat: String, amount: int) -> void:
	if userid < 0:
		return
	if not _stats.has(userid):
		_stats[userid] = ZERO.duplicate()
	_stats[userid][stat] += amount


func _start_again(_event: GameEvent) -> void:
	_stats.clear()
	_over = false


func _enemies(attacker: int, victim: int) -> bool:
	if attacker < 0 or attacker == victim:
		return false
	var side := game.roster.team_of(attacker)
	return not side.is_empty() and side != game.roster.team_of(victim)


func _on_hurt(event: GameEvent) -> void:
	if _over:
		return
	var attacker: int = event.fields["attacker"]
	if _enemies(attacker, event.fields["userid"]):
		_add(attacker, "damage", int(event.fields["dmg_health"]))


func _on_death(event: GameEvent) -> void:
	if _over:
		return
	var victim: int = event.fields["userid"]
	var attacker: int = event.fields["attacker"]
	_add(victim, "deaths", 1)
	if _enemies(attacker, victim):
		_add(attacker, "kills", 1)
		if event.fields["headshot"]:
			_add(attacker, "headshots", 1)
	elif attacker >= 0 and (attacker == victim or game.roster.team_of(attacker) == game.roster.team_of(victim)):
		_add(attacker, "kills", -1)
	_add(int(event.fields["assister"]), "assists", 1)


func _on_mvp(event: GameEvent) -> void:
	_add(int(event.fields["userid"]), "mvps", 1)
