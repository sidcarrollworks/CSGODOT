extends "res://tests/check_suite.gd"

## The kill credit (KillCredit, the damage contract's system): what it fills
## into a player_death as it is sent, by CS2's rules: the assister at 25
## damage, a flash assist, a blind or airborne killer, a gun's kill through
## smoke; and the completers it is built on (GameEvents.complete).
##
##   godot --headless --path . --script tests/run_kill_credit_checks.gd
##
## Needs nothing extracted. The grenades' answers are stood in for here.

## A player as the credit reads one: a side, the ground, eyes.
class Someone extends Node3D:
	var team: String = "T"
	var on_ground: bool = true

	func eye_height() -> float:
		return 64.0


var _game: GameSystems
var _ids := {}
var _blind := {}
var _smoke_across_x := INF
var _deaths: Array[Dictionary] = []


func _initialize() -> void:
	await process_frame
	_test_completers()
	_new_game()
	_test_damage_assist()
	_test_flash_assist()
	_test_marks()
	_test_what_gets_none()
	_test_lives_and_rounds()
	_finish("kill-credit")


func _test_completers() -> void:
	var events := GameEvents.new()
	events.complete(&"player_death", func(_f: Dictionary) -> Dictionary:
		return {"assister": 7, "headshot": true, "nonsense": 1})
	var heard: Array[GameEvent] = []
	events.listen(&"player_death", func(e: GameEvent) -> void: heard.append(e))
	events.send(&"player_death", {"userid": 1, "headshot": false})
	events.flush()
	_check_equal(heard[0].fields.assister, 7, "a completer fills a key the sender left out")
	_check_equal(heard[0].fields.headshot, false, "but never one the sender gave")
	_check(not heard[0].fields.has("nonsense"), "nor a key the event does not have")
	events.muted = true
	var calls := [0]
	events.complete(&"player_hurt", func(_f: Dictionary) -> Dictionary:
		calls[0] += 1
		return {})
	events.send(&"player_hurt", {"userid": 1})
	_check_equal(calls[0], 0, "a muted send (a tick run again) completes nothing")


## Two a side: T1, T2, C1, C2, and a third T for three-way assists.
func _new_game() -> void:
	_game = GameSystems.new()
	_game.provide(&"blind_share", func(userid: int, _at: int = -1) -> float: return _blind.get(userid, 0.0))
	_game.provide(&"smoke_length_between", func(from: Vector3, to: Vector3, _at: int = -1) -> float:
		return 50.0 if minf(from.x, to.x) < _smoke_across_x and maxf(from.x, to.x) > _smoke_across_x else 0.0)
	_game.events.listen(&"player_death", func(e: GameEvent) -> void: _deaths.append(e.fields))
	var x := 0.0
	for spec in [["T1", "T"], ["T2", "T"], ["T3", "T"], ["C1", "CT"], ["C2", "CT"]]:
		var who := Someone.new()
		who.name = spec[0]
		who.team = spec[1]
		who.position = Vector3(x, 0, 0)
		x += 100.0
		root.add_child(who)
		_ids[spec[0]] = _game.add_player(who)


func _id(player_name: String) -> int:
	return _ids.get(player_name, GameEvents.NOBODY)


func _node(player_name: String) -> Someone:
	return _game.roster.player(_id(player_name)) as Someone


func _hurt(attacker: String, victim: String, damage: int) -> void:
	_game.events.send(&"player_hurt", {"userid": _id(victim), "attacker": _id(attacker), "dmg_health": damage})


func _kill(attacker: String, victim: String, weapon: String = "weapon_ak47") -> Dictionary:
	_game.events.send(&"player_death", {"userid": _id(victim),
		"attacker": _id(attacker) if not attacker.is_empty() else GameEvents.NOBODY, "weapon": weapon})
	_game.events.flush()
	return _deaths[-1]


func _spawn(player_name: String) -> void:
	_game.events.send(&"player_spawn", {"userid": _id(player_name)})
	_game.events.flush()


func _test_damage_assist() -> void:
	_hurt("T2", "C1", 30)
	_game.events.flush()
	var death := _kill("T1", "C1")
	_check_equal(death.assister, _id("T2"), "30 damage before the kill is an assist (cs_AssistDamageThreshold 25)")
	_check_equal(death.assistedflash, false, "not a flash assist")
	_spawn("C1")

	_hurt("T2", "C1", 24)
	_game.events.flush()
	_check_equal(_kill("T1", "C1").assister, GameEvents.NOBODY, "24 is not enough")
	_spawn("C1")

	_hurt("T2", "C1", 25)
	_game.events.flush()
	_check_equal(_kill("T1", "C1").assister, _id("T2"), "25 is")
	_spawn("C1")

	# In the killing tick itself, before the hand-out.
	_hurt("T2", "C1", 40)
	_check_equal(_kill("T1", "C1").assister, _id("T2"), "a hit in the same tick as the kill counts")
	_spawn("C1")

	_hurt("T2", "C1", 30)
	_hurt("T3", "C1", 60)
	_hurt("T1", "C1", 90)
	_check_equal(_kill("T1", "C1").assister, _id("T3"), "of several, whoever did the most, never the killer")
	_spawn("C1")

	_hurt("T2", "C1", 12)
	_hurt("T2", "C1", 14)
	_check_equal(_kill("T1", "C1").assister, _id("T2"), "damage adds up over hits")
	_spawn("C1")


func _test_flash_assist() -> void:
	_game.events.send(&"player_blind", {"userid": _id("C1"), "attacker": _id("T2")})
	_game.events.flush()
	_blind[_id("C1")] = 0.4
	var death := _kill("T1", "C1")
	_check(death.assister == _id("T2") and death.assistedflash, "the enemy whose flash the victim is under assists")
	_spawn("C1")
	_blind.erase(_id("C1"))

	_game.events.send(&"player_blind", {"userid": _id("C1"), "attacker": _id("T2")})
	_game.events.flush()
	_check_equal(_kill("T1", "C1").assister, GameEvents.NOBODY, "not once the flash has worn off")
	_spawn("C1")

	_game.events.send(&"player_blind", {"userid": _id("C1"), "attacker": _id("T3")})
	_game.events.flush()
	_blind[_id("C1")] = 1.0
	_hurt("T2", "C1", 50)
	death = _kill("T1", "C1")
	_check(death.assister == _id("T2") and not death.assistedflash, "damage's assist before a flash's")
	_spawn("C1")

	_game.events.send(&"player_blind", {"userid": _id("C1"), "attacker": _id("C2")})
	_game.events.flush()
	_check_equal(_kill("T1", "C1").assister, GameEvents.NOBODY, "a teammate's flash on the victim is no assist")
	_blind.erase(_id("C1"))
	_spawn("C1")


func _test_marks() -> void:
	_blind[_id("T1")] = 0.7
	_check(_kill("T1", "C1").attackerblind, "a killer flashed to 0.7 is blind (sv_flashed_amount_for_blind_kill)")
	_spawn("C1")
	_blind[_id("T1")] = 0.69
	_check(not _kill("T1", "C1").attackerblind, "below it is not")
	_blind.erase(_id("T1"))
	_spawn("C1")

	_node("T1").on_ground = false
	_check(_kill("T1", "C1").attackerinair, "a killer off the ground is in the air")
	_node("T1").on_ground = true
	_spawn("C1")
	_check(not _kill("T1", "C1").attackerinair, "on it is not")
	_spawn("C1")

	# T1 at x 0, C1 at x 300.
	_smoke_across_x = 150.0
	_check(_kill("T1", "C1").thrusmoke, "a gun's kill across smoke is through smoke")
	_spawn("C1")
	_check(not _kill("T1", "C1", "weapon_hegrenade").thrusmoke, "a grenade's is not (hitscan only)")
	_spawn("C1")
	_smoke_across_x = 1000.0
	_check(not _kill("T1", "C1").thrusmoke, "and none with no smoke between")
	_spawn("C1")

	var death := _kill("T1", "C1")
	_check(death.dominated == 0 and death.revenge == 0, "no domination or revenge (sv_nonemesis 1)")
	_spawn("C1")


func _test_what_gets_none() -> void:
	_hurt("C2", "T2", 60)
	_check_equal(_kill("T2", "T2", "weapon_hegrenade").assister, GameEvents.NOBODY, "a suicide gets no assist")
	_spawn("T2")
	_hurt("C1", "C2", 60)
	_hurt("T1", "C2", 60)
	_check_equal(_kill("C1", "C2").assister, GameEvents.NOBODY, "a teamkill gets none")
	_spawn("C2")
	_hurt("T1", "C2", 60)
	var bomb := _kill("", "C2", "weapon_c4")
	_check(bomb.assister == GameEvents.NOBODY and not bomb.attackerinair, "the bomb's kill gets nothing")
	_spawn("C2")
	var told := _game.events.send(&"player_death", {"userid": _id("C1"), "attacker": _id("T1"),
		"assister": _id("T3")})
	_game.events.flush()
	_check(told and _deaths[-1].assister == _id("T3"), "an assister the sender names stands")
	_spawn("C1")


func _test_lives_and_rounds() -> void:
	_hurt("T2", "C1", 60)
	_spawn("C1")
	_check_equal(_kill("T1", "C1").assister, GameEvents.NOBODY, "damage before a respawn is forgotten")
	_spawn("C1")
	_hurt("T2", "C1", 60)
	_game.events.send(&"round_prestart")
	_game.events.flush()
	_check_equal(_kill("T1", "C1").assister, GameEvents.NOBODY, "and at a new round")
	_spawn("C1")
	_hurt("T2", "C1", 60)
	_kill("T1", "C1")
	_check_equal(_kill("T1", "C1").assister, GameEvents.NOBODY, "and once the victim has died")
