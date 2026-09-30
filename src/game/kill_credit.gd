class_name KillCredit
extends RefCounted

## What a death's source cannot know about the kill, filled into its
## player_death as it is sent (GameEvents.complete), so the kill feed, the
## money and the round's report hear it whole: who assisted, whether with a
## flash, whether the killer was blind or in the air, and whether the round
## went through smoke. The damage contract's own system, which GameSystems
## adds after ItemDrops. It works each death out once, as it happens; its
## only per-tick cost is none (tick does nothing).
##
## CS2's rules, from its files (GameTracking-CS2 at 3fc98e7, 2026-09-25:
## DumpSource2/convars.txt, resource/mod.gameevents):
## - An assist takes cs_AssistDamageThreshold 25 damage done to the victim
##   in this life by an enemy of theirs other than the killer
##   (mp_display_kill_assists, on by default, shows and scores it). That 25
##   is enough, not more than it, is read from the convar's words ("the
##   amount of damage needed"); CS:GO's community figure was 41.
## - A flash assist (assistedflash): without a damage assist, the enemy
##   whose flash the victim was still under when killed. Whether CS2 asks
##   more of the flash, or prefers it to a damage assist, is not in its
##   files: a guess.
## - attackerblind: the killer flashed to at least
##   sv_flashed_amount_for_blind_kill 0.7 ("minimum flashed alpha value for
##   a player to be awarded a blind kill on the kill feed").
## - attackerinair: the killer off the ground ("attacker was in midair").
## - thrusmoke: a gun's kill whose line from the killer's eyes to the
##   victim's chest crosses smoke ("hitscan weapon went through smoke
##   grenade"). The chest, not where the round landed: the event does not
##   carry the hit's position, and a smoke is far wider than the difference.
## - dominated and revenge stay 0: CS2's sv_nonemesis is true by default,
##   "Disable nemesis and revenge".
## A teammate's kill and a suicide get no assist (a guess).
##
## It reads the roster, the grenades' blind_share and smoke_length_between
## queries, and the events; it never changes the game. No physics queries.

## cs_AssistDamageThreshold.
const ASSIST_DAMAGE := 25
## sv_flashed_amount_for_blind_kill.
const BLIND_KILL := 0.7
## How high the victim's chest is, as a share of their eyes' height.
const CHEST_SHARE := 0.8

var game: GameSystems
## [victim][attacker]: health taken from the victim by that enemy this life.
var _damage := {}
## [victim]: who last flashed them.
var _flashed_by := {}


func attach(p_game: GameSystems) -> void:
	game = p_game
	var events := game.events
	events.complete(&"player_hurt", _on_hurt)
	events.complete(&"player_death", _on_death)
	events.listen(&"player_blind", _on_blind)
	events.listen(&"player_spawn", func(e: GameEvent) -> void: _forget(int(e.fields.userid)))
	events.listen(&"round_prestart", func(_e: GameEvent) -> void: _reset())
	events.listen(&"round_announce_warmup", func(_e: GameEvent) -> void: _reset())


func tick(_t: SimTick) -> void:
	pass


func _reset() -> void:
	_damage.clear()
	_flashed_by.clear()


func _forget(victim: int) -> void:
	_damage.erase(victim)
	_flashed_by.erase(victim)


## Every hit as it is sent (so a hit in the killing tick counts): the
## health an enemy took.
func _on_hurt(fields: Dictionary) -> Dictionary:
	var victim: int = fields.userid
	var attacker: int = fields.attacker
	if attacker == GameEvents.NOBODY or attacker == victim or not _enemies(attacker, victim):
		return {}
	if not _damage.has(victim):
		_damage[victim] = {}
	var by: Dictionary = _damage[victim]
	by[attacker] = int(by.get(attacker, 0)) + int(fields.dmg_health)
	return {}


func _on_blind(event: GameEvent) -> void:
	_flashed_by[int(event.fields.userid)] = int(event.fields.attacker)


func _on_death(fields: Dictionary) -> Dictionary:
	var victim: int = fields.userid
	var attacker: int = fields.attacker
	var out := {}
	if attacker != GameEvents.NOBODY and attacker != victim:
		var killer := game.roster.player(attacker)
		if killer != null:
			if killer.get(&"on_ground") == false:
				out["attackerinair"] = true
			if float(game.query(&"blind_share", [attacker], 0.0)) >= BLIND_KILL:
				out["attackerblind"] = true
			if _through_smoke(killer, game.roster.player(victim), String(fields.weapon)):
				out["thrusmoke"] = true
		if _enemies(attacker, victim):
			out.merge(assist_for(victim, attacker))
	_forget(victim)
	return out


## The assist for a kill: {"assister", "assistedflash"}, or {} for none.
func assist_for(victim: int, attacker: int) -> Dictionary:
	var best := GameEvents.NOBODY
	var most := 0
	var by: Dictionary = _damage.get(victim, {})
	for who: int in by:
		if who == attacker or by[who] < ASSIST_DAMAGE or not _enemies(who, victim):
			continue
		if by[who] > most:
			best = who
			most = by[who]
	if best != GameEvents.NOBODY:
		return {"assister": best}
	var flasher: int = _flashed_by.get(victim, GameEvents.NOBODY)
	if flasher != GameEvents.NOBODY and flasher != attacker and _enemies(flasher, victim) \
			and float(game.query(&"blind_share", [victim], 0.0)) > 0.0:
		return {"assister": flasher, "assistedflash": true}
	return {}


func _enemies(a: int, b: int) -> bool:
	var side_a := game.roster.team_of(a)
	var side_b := game.roster.team_of(b)
	return not side_a.is_empty() and not side_b.is_empty() and side_a != side_b


## Whether a gun's round from the killer's eyes to the victim's chest went
## through smoke.
func _through_smoke(killer: Node3D, victim: Node3D, weapon: String) -> bool:
	if victim == null or not ItemRegistry.has(weapon):
		return false
	var slot := ItemRegistry.item(weapon).slot
	if slot != ItemDef.Slot.PRIMARY and slot != ItemDef.Slot.PISTOL:
		return false
	var eyes := killer.global_position + Vector3.UP * _eye_height(killer)
	var chest := victim.global_position + Vector3.UP * _eye_height(victim) * CHEST_SHARE
	return float(game.query(&"smoke_length_between", [eyes, chest], 0.0)) > 0.0


static func _eye_height(body: Node3D) -> float:
	return body.call(&"eye_height") if body.has_method(&"eye_height") else 64.0
