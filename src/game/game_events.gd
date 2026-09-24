class_name GameEvents
extends RefCounted

## The game's events, as CS2 has them: what the simulation says happened,
## queued during the tick and handed out once at its end.
##
## Systems never call each other (reference/systems/contracts.md). A death
## is sent here once, and the kill feed, the money, the scoreboard, the
## sounds and, later, the network each hear it from here. Sending during a
## tick only queues; whoever owns the tick calls flush() at its end, which
## hands every event to its listeners in the order sent. An event a listener
## sends while being handed one is handed out in the same flush, after the
## ones already queued, so a death and the money paid for it settle within
## the tick they happened in.
##
## One flush comes earlier: a round's start (MatchState._start_round)
## hands out round_prestart at once, so the ground is cleared and the bomb
## taken back before anyone spawns. It runs in the world's end of the tick,
## after the players' commands and before the game's step, so everything
## queued so far that tick goes out with it, while GameSystems.now_usec() is
## still the last tick's; a listener wanting the time takes event.at_usec.
##
## The names and keys are CS2's (SCHEMA), so what a system listens for is
## what CS2's own game sends. An event or key not in SCHEMA is refused, which
## keeps SCHEMA and the contract the one list of what can happen.

## A player's userid (Roster) when there is nobody: the world, or no one.
const NOBODY := -1

## Every event, with its keys and what a key left out is. Ids default to
## NOBODY; teams are "T" and "CT"; items are CS2 class names in full
## ("weapon_ak47"); positions are x, y and z in Source units; hitgroup is
## CS2's number (DamageInfo). Written from what CS2 and CS:GO send; keys CS2
## has that nothing here can fill (xuids, item ids, pawn handles) are left
## out. Checking the list against CS2's own game.gameevents needs Sid's
## machine.
const SCHEMA := {
	# Players.
	&"player_spawn": {"userid": NOBODY},
	&"player_team": {
		"userid": NOBODY, "team": "", "oldteam": "", "disconnect": false,
		"silent": false, "isbot": false,
	},
	&"player_hurt": {
		"userid": NOBODY, "attacker": NOBODY, "health": 0, "armor": 0, "weapon": "",
		"dmg_health": 0, "dmg_armor": 0, "hitgroup": 0,
	},
	&"player_death": {
		"userid": NOBODY, "attacker": NOBODY, "assister": NOBODY, "assistedflash": false,
		"weapon": "", "headshot": false, "penetrated": 0, "noscope": false,
		"thrusmoke": false, "attackerblind": false, "attackerinair": false,
		"distance": 0.0, "dmg_health": 0, "dmg_armor": 0, "hitgroup": 0,
		"dominated": 0, "revenge": 0, "wipe": 0,
	},
	&"player_blind": {"userid": NOBODY, "attacker": NOBODY, "entityid": NOBODY, "blind_duration": 0.0},
	&"player_jump": {"userid": NOBODY},
	&"player_footstep": {"userid": NOBODY},
	&"player_falldamage": {"userid": NOBODY, "damage": 0.0},

	# Weapons.
	&"weapon_fire": {"userid": NOBODY, "weapon": "", "silenced": false},
	&"weapon_fire_on_empty": {"userid": NOBODY, "weapon": ""},
	&"weapon_reload": {"userid": NOBODY},
	&"weapon_zoom": {"userid": NOBODY},
	&"bullet_impact": {"userid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},

	# Items.
	&"item_purchase": {"userid": NOBODY, "team": "", "loadout": 0, "weapon": ""},
	&"item_pickup": {"userid": NOBODY, "item": "", "silent": false},
	&"item_remove": {"userid": NOBODY, "item": ""},
	&"item_equip": {
		"userid": NOBODY, "item": "", "canzoom": false, "hassilencer": false,
		"issilenced": false, "weptype": "",
	},
	&"ammo_pickup": {"userid": NOBODY, "item": "", "index": NOBODY},
	&"enter_buyzone": {"userid": NOBODY, "canbuy": false},
	&"exit_buyzone": {"userid": NOBODY, "canbuy": false},
	&"buytime_ended": {},

	# Rounds and the match.
	## Warmup has begun (CS2's announcement of it; that it is sent as
	## warmup starts is read from its name).
	&"round_announce_warmup": {},
	&"begin_new_match": {},
	&"round_prestart": {},
	&"round_start": {"timelimit": 0, "fraglimit": 0, "objective": ""},
	&"round_poststart": {},
	&"round_freeze_end": {},
	&"round_end": {"winner": "", "reason": "", "message": "", "player_count": 0},
	&"round_officially_ended": {},
	&"round_mvp": {"userid": NOBODY, "reason": 0, "value": 0},
	## The end of every half: half time, regulation into overtime, and each
	## overtime half.
	&"announce_phase_end": {},
	&"cs_win_panel_match": {},

	# The bomb. Sites are "A" and "B" (CS2 sends the site's entity index).
	&"player_given_c4": {"userid": NOBODY},
	&"bomb_pickup": {"userid": NOBODY},
	&"bomb_dropped": {"userid": NOBODY, "entindex": NOBODY},
	&"bomb_beginplant": {"userid": NOBODY, "site": ""},
	&"bomb_abortplant": {"userid": NOBODY, "site": ""},
	&"bomb_planted": {"userid": NOBODY, "site": ""},
	&"bomb_begindefuse": {"userid": NOBODY, "haskit": false},
	&"bomb_abortdefuse": {"userid": NOBODY},
	&"bomb_defused": {"userid": NOBODY, "site": ""},
	&"bomb_exploded": {"userid": NOBODY, "site": ""},
	&"enter_bombzone": {"userid": NOBODY, "hasbomb": false, "isplanted": false},
	&"exit_bombzone": {"userid": NOBODY, "hasbomb": false, "isplanted": false},
	&"defuser_dropped": {"entityid": NOBODY},
	&"defuser_pickup": {"entityid": NOBODY, "userid": NOBODY},

	# Grenades.
	&"grenade_thrown": {"userid": NOBODY, "weapon": ""},
	&"grenade_bounce": {"userid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},
	&"hegrenade_detonate": {"userid": NOBODY, "entityid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},
	&"flashbang_detonate": {"userid": NOBODY, "entityid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},
	&"smokegrenade_detonate": {"userid": NOBODY, "entityid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},
	&"smokegrenade_expired": {"userid": NOBODY, "entityid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},
	&"decoy_started": {"userid": NOBODY, "entityid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},
	&"decoy_detonate": {"userid": NOBODY, "entityid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},
	&"decoy_firing": {"userid": NOBODY, "entityid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},
	&"molotov_detonate": {"userid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},
	&"inferno_startburn": {"entityid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},
	&"inferno_expire": {"entityid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},
	&"inferno_extinguish": {"entityid": NOBODY, "x": 0.0, "y": 0.0, "z": 0.0},
}

## How many rounds of handing out one flush goes through before it takes a
## chain of events sending events to be endless.
const MOST_PASSES := 64

## While set, sends are dropped: a tick being run again (a client
## predicting) must not report what already happened once.
var muted: bool = false

var _queue: Array[GameEvent] = []
var _listeners := {}
var _everything: Array[Callable] = []
var _flushing: bool = false


## Queues an event for the end of the tick. Keys left out take SCHEMA's
## defaults. False, with an error, for a name or key SCHEMA does not have.
## at_usec is when in the tick it happened; the tick's end if not given.
func send(name: StringName, fields: Dictionary = {}, at_usec: int = -1) -> bool:
	if not SCHEMA.has(name):
		push_error("No game event called %s (GameEvents.SCHEMA)" % name)
		return false
	var keys: Dictionary = SCHEMA[name]
	var full := keys.duplicate()
	for key in fields:
		if not keys.has(key):
			push_error("The game event %s has no key %s (GameEvents.SCHEMA)" % [name, key])
			return false
		full[key] = fields[key]
	if muted:
		return true
	var tick := SimClock.current_tick()
	_queue.append(GameEvent.new(
		name, full, tick, at_usec if at_usec >= 0 else SimClock.tick_end_usec(tick)
	))
	return true


## Calls listener with each event of that name, as a GameEvent.
func listen(name: StringName, listener: Callable) -> void:
	assert(SCHEMA.has(name), "No game event called %s" % name)
	if not _listeners.has(name):
		var list: Array[Callable] = []
		_listeners[name] = list
	(_listeners[name] as Array[Callable]).append(listener)


## Calls listener with every event: a kill feed, a recorder, the network.
func listen_all(listener: Callable) -> void:
	_everything.append(listener)


func unlisten(name: StringName, listener: Callable) -> void:
	if _listeners.has(name):
		(_listeners[name] as Array[Callable]).erase(listener)


func unlisten_all(listener: Callable) -> void:
	_everything.erase(listener)


## Hands every queued event to its listeners, in the order sent, those sent
## meanwhile included. The number handed out.
func flush() -> int:
	if _flushing:
		return 0
	_flushing = true
	var handed := 0
	var passes := 0
	while not _queue.is_empty():
		passes += 1
		if passes > MOST_PASSES:
			push_error("Game events kept sending game events; %d dropped" % _queue.size())
			_queue.clear()
			break
		var batch := _queue
		_queue = []
		for event in batch:
			handed += 1
			# Copies, so a listener that stops listening while being told
			# does not skip the next one.
			if _listeners.has(event.name):
				for listener in (_listeners[event.name] as Array[Callable]).duplicate():
					if listener.is_valid():
						listener.call(event)
			for listener in _everything.duplicate():
				if listener.is_valid():
					listener.call(event)
	_flushing = false
	return handed


## What is queued and not yet handed out, as a copy.
func pending() -> Array[GameEvent]:
	return _queue.duplicate()


## Whether an event of this name is queued and not yet handed out: a round
## ended this tick (round_end), which what runs later in the tick must not
## act past. Copies nothing.
func is_pending(name: StringName) -> bool:
	for event in _queue:
		if event.name == name:
			return true
	return false


## Drops what is queued without handing it out.
func clear() -> void:
	_queue.clear()


## CS2's name for why a round ended (round_end's reason), from MatchState's.
static func round_end_reason(reason: int) -> String:
	match reason:
		MatchState.Reason.T_ELIMINATED:
			return "CTsWin"
		MatchState.Reason.CT_ELIMINATED:
			return "TerroristsWin"
		MatchState.Reason.TIME_RAN_OUT:
			return "TargetSaved"
		MatchState.Reason.BOMB_EXPLODED:
			return "TargetBombed"
		MatchState.Reason.BOMB_DEFUSED:
			return "BombDefused"
	return "RoundDraw"


## round_end's message, the notice CS2 shows for a reason: its localisation
## token (round-hud-bots.md A6; that the server sends the token is from
## memory).
static func round_end_message(reason: int) -> String:
	match reason:
		MatchState.Reason.T_ELIMINATED:
			return "#SFUI_Notice_CTs_Win"
		MatchState.Reason.CT_ELIMINATED:
			return "#SFUI_Notice_Terrorists_Win"
		MatchState.Reason.TIME_RAN_OUT:
			return "#SFUI_Notice_Target_Saved"
		MatchState.Reason.BOMB_EXPLODED:
			return "#SFUI_Notice_Target_Bombed"
		MatchState.Reason.BOMB_DEFUSED:
			return "#SFUI_Notice_Bomb_Defused"
	return "#SFUI_Notice_Round_Draw"
