extends "res://tests/check_suite.gd"

## Checks money and buying: CS2's numbers, a half of wins and losses walked
## round by round against the loss ladder, kill awards by weapon, the bomb's
## money, the round lost on time, half time and overtime, and every rule a
## purchase is held to (the buy zone, buy time, the side, money, what is
## carried, armour's prices, undoing it), buying to throw, and the buy menu
## buying by keys, greying what cannot be bought and outlining what is
## owned.
##
##   godot --headless --path . --script tests/run_economy_checks.gd
##
## Needs nothing extracted. The economy runs in a GameSystems stepped by
## hand, the round's events sent as MatchState will send them, and the
## players are bare nodes with a side and a life, standing where a check
## puts them.

const SECOND := 1_000_000

const ECONOMY_FILES := [
	"res://src/economy/economy.gd",
	"res://src/economy/money_rules.gd",
	"res://src/economy/buy_zones.gd",
	"res://src/economy/loadout.gd",
]

## The buy zones: a box round each side's spawn.
const T_ZONE := AABB(Vector3(-256.0, 0.0, -256.0), Vector3(512.0, 128.0, 512.0))
const CT_ZONE := AABB(Vector3(-256.0, 0.0, -4256.0), Vector3(512.0, 128.0, 512.0))
const T_SPAWN := Vector3(0.0, 0.0, 0.0)
const CT_SPAWN := Vector3(0.0, 0.0, -4000.0)
const MID := Vector3(0.0, 0.0, -2000.0)


## A player, as the roster sees one: a node with a side and a life.
## Counts the key presses that reach the game behind a menu.
class KeyCatcher extends Node:
	var presses := 0

	func _unhandled_input(event: InputEvent) -> void:
		var key := event as InputEventKey
		if key != null and key.pressed:
			presses += 1


class Body extends Node3D:
	var team: String = "T"
	var alive: bool = true


var _game: GameSystems
var _economy: Economy
var _tick: int = 1000
var _ts: Array[int] = []
var _cts: Array[int] = []
var _bodies := {}
var _sent: Array[GameEvent] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	# The players stand in the tree, which is not there to stand in yet.
	await process_frame
	_test_the_economy_reads_only_the_simulation()
	_test_the_rules_are_cs2s()
	_test_the_menu_is_cs2s_loadout()
	_test_a_half_of_rounds()
	_test_the_pistol_winner_that_loses()
	_test_kill_awards()
	_test_the_bomb()
	_test_a_plant_after_the_round()
	_test_a_round_lost_on_time()
	_test_half_time_and_overtime()
	_test_the_cap()
	_test_buy_zone_and_buy_time()
	_test_what_may_be_bought()
	_test_a_rounds_purchase_limits()
	_test_practice_buying()
	_test_armour_prices()
	_test_a_purchase()
	_test_a_buy_from_before_the_round()
	_test_undoing_a_purchase()
	_test_buy_and_throw()
	_test_the_menu_buys_by_keys()
	_test_the_menu_greys_and_outlines()
	await _test_the_menu_buys_by_clicks()
	_test_the_menu_counts_down_buying()
	for body in _bodies.values():
		body.free()
	_finish("economy")


# --- The rules ----------------------------------------------------------------

func _test_the_economy_reads_only_the_simulation() -> void:
	# Server state keeps time with SimClock and hears of the game through its
	# events: no wall clock, no keys, no signals from the round code.
	for path in ECONOMY_FILES:
		var source := FileAccess.get_file_as_string(path)
		var reads := []
		for banned in ["Time.get_ticks", "Time.get_unix", "Input.", "Engine.get_physics_frames", "MatchState.new", "round_ended.connect"]:
			if source.contains(banned):
				reads.append(banned)
		_check(reads.is_empty(), "%s reads nothing but the simulation (%s)" % [path.get_file(), ", ".join(reads)])


func _test_the_rules_are_cs2s() -> void:
	var rules := MoneyRules.new()
	_check(not rules.unlimited_money and not rules.unlimited_grenade_purchases,
		"competitive defaults retain money and grenade purchase limits")
	_check(rules.start_money == 800 and rules.max_money == 16000 and rules.overtime_start_money == 10000,
		"$800 to start, $16,000 at most, $10,000 an overtime half")
	_check(rules.win_elimination == 3250 and rules.win_time == 3250
		and rules.win_bomb_exploded == 3500 and rules.win_bomb_defused == 3500,
		"a win pays $3,250, or $3,500 by the bomb going off or being defused")
	_check(rules.loss_bonus == 1400 and rules.loss_bonus_step == 500 and rules.loss_steps_max == 4
		and rules.starting_losses == 1 and rules.loss_aversion == 1,
		"the loss bonus is $1,400 and $500 a step, four steps, starting one up, a win stepping it down one")
	_check(rules.planted_but_lost == 600 and rules.bomb_planted == 300 and rules.bomb_defused == 300
		and rules.team_kill == -300 and rules.kill_award_default == 300,
		"$600 to Ts who planted and lost, $300 a plant and a defuse, -$300 a team kill")
	_check(is_equal_approx(rules.buy_seconds, 20.0) and not rules.buy_anywhere and rules.sellback
		and rules.max_armor == 2 and rules.type_purchases == 5 and rules.zeus_purchases == 5,
		"20 s of buying in the buy zone, purchases undone, kevlar and helmet, five of a type")


func _test_the_menu_is_cs2s_loadout() -> void:
	for side in ["T", "CT"]:
		var bad := []
		for item in Loadout.items(side):
			var def := ItemRegistry.item(item)
			if def == null or not def.buyable or not (def.team.is_empty() or def.team == side):
				bad.append(item)
		_check(bad.is_empty(), "every item on the %s menu is sold to %s (%s)" % [side, side, bad])
	_check_equal(Loadout.items("T").size(), 23, "the T menu: 15 guns, kevlar, the suit, the Zeus, 5 grenades")
	_check_equal(Loadout.items("CT").size(), 24, "the CT menu has the kit as well")
	_check(Loadout.item_at("T", 2, 1) == "weapon_ak47" and Loadout.item_at("CT", 2, 1) == "weapon_m4a1_silencer",
		"3 then 2 is the AK-47 or the M4A1-S")
	_check_equal(Loadout.index_of("CT", "item_defuser"), 18, "the kit's place, as item_purchase's loadout names it")


# --- Money ----------------------------------------------------------------------

func _test_a_half_of_rounds() -> void:
	_new_game(5)
	_send(&"begin_new_match")
	_check(_all_have(_ts, 800) and _all_have(_cts, 800), "everyone starts the match with $800")

	# The Ts lose five in a row: $1,900 (one step up), 2,400, 2,900 and
	# 3,400 twice; the CTs are paid $3,250 a win. Accounts are emptied
	# before each round, so the cap is never met.
	var t_paid := []
	var ct_paid := []
	for round in 5:
		t_paid.append(_paid(_ts[0], "CT", "CTsWin"))
		ct_paid.append(_last_paid(_cts[0]))
	_check_equal(t_paid, [1900, 2400, 2900, 3400, 3400], "the Ts' loss bonus climbs the ladder to $3,400")
	_check_equal(ct_paid, [3250, 3250, 3250, 3250, 3250], "the CTs are paid $3,250 a round")

	_check_equal(_paid(_ts[0], "T", "TerroristsWin"), 3250, "the Ts' win pays $3,250")
	# The CTs' ladder went to the bottom with their first win.
	_check_equal(_last_paid(_cts[0]), 1400, "the CTs' first loss, after five wins, pays $1,400")
	# The Ts' was at the top: a win steps it down one, not to the bottom.
	_check_equal(_paid(_ts[0], "CT", "CTsWin"), 2900, "a loss after a win pays one step less than before it ($2,900)")


func _test_the_pistol_winner_that_loses() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_check_equal(_paid(_ts[0], "T", "TerroristsWin"), 3250, "the pistol round won")
	_check_equal(_last_paid(_cts[0]), 1900, "the pistol round's losers get $1,900")
	_check_equal(_paid(_ts[0], "CT", "CTsWin"), 1400, "the pistol round's winners, losing the next, get $1,400")
	_check_equal(_paid(_cts[0], "T", "TerroristsWin"), 1900,
		"the pistol round's losers, having won one since, get $1,900 again")


func _test_kill_awards() -> void:
	_new_game(2)
	_send(&"begin_new_match")
	var awards := {
		"weapon_ak47": 300, "weapon_knife": 1500, "weapon_awp": 100, "weapon_taser": 100,
		"weapon_mp9": 600, "weapon_p90": 300, "weapon_nova": 900, "weapon_xm1014": 600,
		"weapon_hegrenade": 300, "weapon_glock": 300,
	}
	var wrong := []
	for weapon: String in awards:
		var had := _economy.money(_ts[0])
		_send(&"player_death", {"userid": _cts[0], "attacker": _ts[0], "weapon": weapon})
		if _economy.money(_ts[0]) - had != awards[weapon]:
			wrong.append("%s %d" % [weapon, _economy.money(_ts[0]) - had])
	_check(wrong.is_empty(), "a kill pays the weapon's own kill award (%s)" % [wrong])

	var before := _economy.money(_ts[0])
	_send(&"player_death", {"userid": _ts[1], "attacker": _ts[0], "weapon": "weapon_ak47"})
	_check_equal(_economy.money(_ts[0]) - before, -300, "a team kill costs $300")
	before = _economy.money(_cts[1])
	_send(&"player_death", {"userid": _cts[1], "attacker": GameEvents.NOBODY, "weapon": ""})
	_check_equal(_economy.money(_cts[1]) - before, 0, "a death credited to no one costs the victim nothing")
	before = _economy.money(_cts[1])
	_send(&"player_death", {"userid": _cts[1], "attacker": _cts[1], "weapon": "weapon_hegrenade"})
	_check_equal(_economy.money(_cts[1]) - before, 0, "a suicide costs nothing (CS2 has no cash rule for one)")
	var accounts := [_economy.money(_ts[0]), _economy.money(_ts[1]), _economy.money(_cts[0])]
	for victim in [_ts[0], _ts[1], _cts[0]]:
		_send(&"player_death", {"userid": victim, "attacker": GameEvents.NOBODY, "weapon": "weapon_c4"})
	_check(accounts == [_economy.money(_ts[0]), _economy.money(_ts[1]), _economy.money(_cts[0])],
		"the bomb's blast, credited to no one, moves nobody's money")
	_economy.set_money(_ts[0], 0)
	_send(&"player_death", {"userid": _ts[1], "attacker": _ts[0], "weapon": "weapon_ak47"})
	_check_equal(_economy.money(_ts[0]), 0, "no account goes below nothing")


func _test_the_bomb() -> void:
	_new_game(2)
	_send(&"begin_new_match")
	_send(&"round_start")
	_send(&"bomb_planted", {"userid": _ts[0], "site": "A"})
	_check_equal(_economy.money(_ts[0]), 800 + 300, "planting pays $300")
	_send(&"player_death", {"userid": _ts[1], "attacker": _cts[0], "weapon": "weapon_m4a1_silencer"})
	_send(&"bomb_defused", {"userid": _cts[1], "site": "A"})
	_send(&"round_end", {"winner": "CT", "reason": "BombDefused"})
	_check_equal(_economy.money(_cts[1]), 800 + 300 + 3500, "the defuser: $300, and $3,500 for the round")
	_check_equal(_economy.money(_cts[0]), 800 + 300 + 3500, "the CTs are paid $3,500 for a defuse")
	_check_equal(_economy.money(_ts[1]), 800 + 1900 + 600, "the Ts who planted and lost get $600 on the loss bonus")

	_send(&"round_start")
	_send(&"bomb_planted", {"userid": _ts[1], "site": "B"})
	var ct_before := _economy.money(_cts[0])
	_send(&"round_end", {"winner": "T", "reason": "TargetBombed"})
	_check_equal(_economy.money(_ts[0]), 800 + 300 + 1900 + 600 + 3500, "the bomb going off pays the Ts $3,500")
	_check_equal(_economy.money(_cts[0]) - ct_before, 1400, "the CTs, their ladder stepped down by the win, get $1,400")



## CS2 pays the planter $300 for a bomb planted after the round is over (its
## plant asks nothing of the round, server.dll 180a18640), and nothing else
## changes: the round's team money was settled as it ended. A plant in
## warmup pays nothing.
func _test_a_plant_after_the_round() -> void:
	_new_game(2)
	_send(&"begin_new_match")
	_send(&"round_start")
	_send(&"round_end", {"winner": "CT", "reason": "TargetSaved"})
	var before := {}
	for userid in _ts + _cts:
		before[userid] = _economy.money(userid)
	var losses := _economy.losses("T")
	_send(&"bomb_planted", {"userid": _ts[0], "site": "A"})
	_check_equal(_economy.money(_ts[0]) - before[_ts[0]], 300, "a bomb planted after the round has ended pays the planter $300")
	var others_unpaid := true
	for userid in [_ts[1], _cts[0], _cts[1]]:
		others_unpaid = others_unpaid and _economy.money(userid) == before[userid]
	_check(others_unpaid and _economy.losses("T") == losses,
		"and nobody else anything: no team money, the loss ladder as the round left it")
	_send(&"round_announce_warmup")
	var warm := _economy.money(_ts[0])
	_send(&"bomb_planted", {"userid": _ts[0], "site": "A"})
	_check_equal(_economy.money(_ts[0]), warm, "a plant in warmup pays nothing")


func _test_a_round_lost_on_time() -> void:
	_new_game(2)
	_send(&"begin_new_match")
	_send(&"round_start")
	_send(&"player_death", {"userid": _ts[1], "attacker": _cts[0], "weapon": "weapon_m4a1_silencer"})
	_send(&"round_end", {"winner": "CT", "reason": "TargetSaved"})
	_check_equal(_economy.money(_cts[1]), 800 + 3250, "the CTs win $3,250 when time runs out")
	_check_equal(_economy.money(_ts[0]), 800, "a T alive when time runs out gets nothing")
	_check_equal(_economy.money(_ts[1]), 800 + 1900, "a T who died gets the loss bonus")
	_check_equal(_economy.losses("T"), 2, "and the Ts' ladder climbs all the same")


func _test_half_time_and_overtime() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	for round in 12:
		_round("CT", "CTsWin")
	_send(&"announce_phase_end")
	_check(not _all_have(_cts, 800), "the half's end is announced as its last round ends; the money stays until the next round")
	_send(&"round_prestart")
	_check(_all_have(_ts, 800) and _all_have(_cts, 800), "half time: everyone back to $800 as the next round starts")
	_check(_economy.losses("T") == 1 and _economy.losses("CT") == 1, "and both ladders back to one step up")
	for round in 12:
		_round("T" if round % 2 == 0 else "CT", "TerroristsWin" if round % 2 == 0 else "CTsWin")
	_send(&"announce_phase_end")
	_send(&"round_prestart")
	_check(_all_have(_ts, 10000) and _all_have(_cts, 10000), "overtime: everyone to $10,000")
	for round in 3:
		_round("CT", "CTsWin")
	_send(&"announce_phase_end")
	_send(&"round_prestart")
	_check(_all_have(_ts, 10000) and _all_have(_cts, 10000), "and again for overtime's second half")
	_send(&"begin_new_match")
	_check(_all_have(_ts, 800), "a new match starts everyone at $800")
	_send(&"round_announce_warmup")
	_check(_all_have(_ts, 16000) and _all_have(_cts, 16000), "warmup: everyone on $16,000")
	_send(&"begin_new_match")
	_check(_all_have(_ts, 800), "and the match itself starts from $800")


func _test_the_cap() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_economy.set_money(_cts[0], 15000)
	_round("CT", "CTsWin")
	_check_equal(_economy.money(_cts[0]), 16000, "no account holds more than $16,000")
	_economy.set_money(_cts[0], 99999)
	_check_equal(_economy.money(_cts[0]), 16000, "not even one set by hand")


# --- Buying ------------------------------------------------------------------------

func _test_buy_zone_and_buy_time() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_send(&"round_start")
	var t := _ts[0]
	_check_equal(_economy.shop_refusal(t), Economy.OK, "in freeze time, at the spawn, a T may buy")
	_check(_sent_named(&"enter_buyzone").size() == 2, "both players are told they are in their buy zones")
	_place(t, CT_SPAWN)
	_check_equal(_economy.shop_refusal(t), Economy.NOT_IN_BUY_ZONE, "not in the CTs' buy zone")
	_place(t, MID)
	_step()
	_check_equal(_economy.shop_refusal(t), Economy.NOT_IN_BUY_ZONE, "nor out in the map")
	_check(_sent_named(&"exit_buyzone").size() == 1, "leaving the zone says so")
	_place(t, T_SPAWN + Vector3(262.0, 0.0, 0.0))
	_check_equal(_economy.shop_refusal(t), Economy.OK, "the hull's edge touching the zone is in it")

	var freeze_end := SimClock.tick_end_usec(_tick)
	_send(&"round_freeze_end", {}, freeze_end)
	_check(absf(_economy.buy_seconds_left(freeze_end) - 20.0) < 0.001, "freeze time over: 20 s of buying left")
	_tick += SimClock.ticks_in(19.9)
	_step()
	_check_equal(_economy.shop_refusal(t), Economy.OK, "still buying after 19.9 s")
	_tick += SimClock.ticks_in(0.2) + 1
	_sent.clear()
	_step()
	_check_equal(_economy.shop_refusal(t), Economy.BUY_TIME_OVER, "not after 20 s")
	_check_equal(_sent_named(&"buytime_ended").size(), 1, "buytime_ended is sent once")

	_send(&"round_start")
	_body(t).alive = false
	_check_equal(_economy.shop_refusal(t), Economy.DEAD, "the dead do not buy")
	_body(t).alive = true
	_send(&"player_death", {"userid": t, "attacker": GameEvents.NOBODY, "weapon": ""})
	_check_equal(_economy.shop_refusal(t), Economy.DEAD, "killed, and nobody to credit: dead all the same")
	_send(&"player_spawn", {"userid": t})
	_check_equal(_economy.shop_refusal(t), Economy.OK, "back with player_spawn, and buying again")
	_send(&"round_end", {"winner": "CT", "reason": "CTsWin"})
	_check_equal(_economy.shop_refusal(t), Economy.BUY_TIME_OVER, "nor does anyone once the round is over")


func _test_what_may_be_bought() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_send(&"round_start")
	var t := _ts[0]
	var ct := _cts[0]
	_check_equal(_economy.refusal(t, "weapon_m4a1_silencer"), Economy.WRONG_TEAM, "a T cannot buy the M4A1-S")
	_check_equal(_economy.refusal(ct, "weapon_ak47"), Economy.WRONG_TEAM, "a CT cannot buy the AK-47")
	_check_equal(_economy.refusal(t, "item_defuser"), Economy.WRONG_TEAM, "nor a T the kit")
	_check_equal(_economy.refusal(t, "weapon_knife"), Economy.NOT_SOLD, "the knife is not sold")
	_check_equal(_economy.refusal(t, "weapon_c4"), Economy.NOT_SOLD, "nor the bomb")
	_check_equal(_economy.refusal(t, "weapon_ak47"), Economy.NO_MONEY, "$800 does not buy an AK-47")
	_check_equal(_economy.refusal(t, "weapon_p250"), Economy.OK, "it buys a P250")

	_economy.set_money(t, 16000)
	var inv := _game.inventory(t)
	inv.give_starting_items("T")
	_check_equal(_economy.refusal(t, "weapon_glock"), Economy.ALREADY_HAVE, "nor a Glock-18 while carrying one")
	for grenade in ["weapon_flashbang", "weapon_flashbang", "weapon_smokegrenade", "weapon_hegrenade"]:
		_buy(t, grenade)
	_check_equal(inv.grenade_count(), 4, "four grenades bought")
	_check_equal(_economy.refusal(t, "weapon_molotov"), Economy.CANNOT_CARRY, "a fifth cannot be carried")
	_check_equal(_economy.refusal(t, "weapon_flashbang"), Economy.CANNOT_CARRY, "nor a third flashbang")

	_economy.set_money(ct, 16000)
	for round in 5:
		_buy(ct, "weapon_taser")
		_game.inventory(ct).remove("weapon_taser")
	_check_equal(_economy.refusal(ct, "weapon_taser"), Economy.TYPE_LIMIT, "five Zeus a round, and no sixth")



## CS2 holds a round's purchases to its own limits (CanAcquire, server.dll
## 180ab2a20): a grenade no more than one carries of it, four grenades in
## all, and any one item five times, counted by item rather than by weapon
## type; none of them in warmup.
func _test_a_rounds_purchase_limits() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_send(&"round_start")
	var t := _ts[0]
	var inv := _game.inventory(t)
	_economy.set_money(t, 16000)
	_buy(t, "weapon_hegrenade")
	inv.take_one("weapon_hegrenade")
	_check_equal(_economy.refusal(t, "weapon_hegrenade"), Economy.TYPE_LIMIT, "one HE a round: thrown, it cannot be bought again")
	for i in 2:
		_buy(t, "weapon_flashbang")
		inv.take_one("weapon_flashbang")
	_check_equal(_economy.refusal(t, "weapon_flashbang"), Economy.TYPE_LIMIT, "two flashbangs a round, and no third")
	_buy(t, "weapon_smokegrenade")
	inv.take_one("weapon_smokegrenade")
	_check_equal(inv.grenade_count(), 0, "none carried")
	_check_equal(_economy.refusal(t, "weapon_molotov"), Economy.GRENADE_LIMIT,
		"four grenades a round in all: no molotov after an HE, two flashbangs and a smoke, though none is carried")
	_check_equal(_economy.throw_refusal(t, "weapon_decoy"), Economy.GRENADE_LIMIT, "nor a decoy bought to throw")

	_send(&"round_start")
	_economy.set_money(t, 16000)
	for grenade in ["weapon_flashbang", "weapon_smokegrenade", "weapon_hegrenade", "weapon_decoy"]:
		_buy(t, grenade)
	_check_equal(_economy.refusal(t, "weapon_molotov"), Economy.CANNOT_CARRY, "carrying four, a fifth cannot be carried")
	_undo(t, "weapon_decoy")
	_check_equal(_economy.refusal(t, "weapon_molotov"), Economy.OK, "a decoy sold back frees its place among the four bought")

	_send(&"round_start")
	_economy.set_money(t, 16000)
	for i in 5:
		_buy(t, "weapon_ak47")
		inv.remove("weapon_ak47")
	_check_equal(_economy.refusal(t, "weapon_ak47"), Economy.TYPE_LIMIT, "five AK-47s a round, and no sixth")
	_check_equal(_economy.refusal(t, "weapon_galilar"), Economy.OK,
		"but a Galil AR: CS2 counts purchases by item, not by weapon type")

	_send(&"round_announce_warmup")
	_economy.set_money(t, 16000)
	for i in 3:
		_buy(t, "weapon_hegrenade")
		inv.take_one("weapon_hegrenade")
	for i in 6:
		_economy.set_money(t, 16000)
		_buy(t, "weapon_ak47")
		inv.remove("weapon_ak47")
	_check(_economy.refusal(t, "weapon_hegrenade") == Economy.OK and _economy.refusal(t, "weapon_ak47") == Economy.OK,
		"in warmup no round's limit holds: a fourth HE, a seventh AK-47")
	_send(&"begin_new_match")
	_send(&"round_start")
	_economy.set_money(t, 16000)
	_buy(t, "weapon_hegrenade")
	inv.take_one("weapon_hegrenade")
	_check_equal(_economy.refusal(t, "weapon_hegrenade"), Economy.TYPE_LIMIT, "once warmup is over they hold again")


func _test_practice_buying() -> void:
	_new_game(1)
	_economy.rules.unlimited_money = true
	_economy.rules.unlimited_grenade_purchases = true
	_send(&"begin_new_match")
	_send(&"round_start")
	var userid := _ts[0]
	var inv := _game.inventory(userid)
	_economy.set_money(userid, 0)
	var every_purchase := true
	for i in 100:
		_buy(userid, GrenadeRules.SMOKE)
		every_purchase = every_purchase and inv.has(GrenadeRules.SMOKE)
		inv.remove(GrenadeRules.SMOKE)
	_check(every_purchase, "practice can rebuy 100 smokes, beyond the round cap and a finite $16,000 account")
	_check_equal(_economy.money(userid), 16000, "practice purchases keep the full balance even after setting the account to zero")
	_check_equal(_economy.throw_refusal(userid, GrenadeRules.SMOKE), Economy.OK,
		"practice also allows grenade buy-and-throw past the round purchase cap")
	_buy(userid, GrenadeRules.SMOKE)
	_check_equal(_economy.refusal(userid, GrenadeRules.SMOKE), Economy.CANNOT_CARRY,
		"practice keeps the normal smoke carrying limit")
	_undo(userid, GrenadeRules.SMOKE)
	_check(not inv.has(GrenadeRules.SMOKE) and _economy.money(userid) == 16000,
		"practice sellback removes the grenade and retains the full balance")
	for i in 5:
		_buy(userid, "weapon_taser")
		inv.remove("weapon_taser")
	_check_equal(_economy.refusal(userid, "weapon_taser"), Economy.TYPE_LIMIT,
		"the grenade purchase override does not change the Zeus cap")


func _test_armour_prices() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_send(&"round_start")
	var t := _ts[0]
	var inv := _game.inventory(t)
	_economy.set_money(t, 16000)
	_check_equal(_economy.price_for(t, "item_assaultsuit"), 1000, "kevlar and helmet: $1,000")
	_buy(t, "item_kevlar")
	_check(inv.armor == 100.0 and not inv.helmet and _economy.money(t) == 16000 - 650, "kevlar: $650, 100 armour")
	_check_equal(_economy.refusal(t, "item_kevlar"), Economy.ALREADY_HAVE, "kevlar again is refused while it is whole")
	_check_equal(_economy.price_for(t, "item_assaultsuit"), 350, "the helmet on full kevlar: $350")
	_buy(t, "item_assaultsuit")
	_check(inv.helmet and _economy.money(t) == 16000 - 650 - 350, "and it buys the helmet")
	_check_equal(_economy.refusal(t, "item_assaultsuit"), Economy.ALREADY_HAVE, "with both, nothing more to buy")
	inv.armor = 40.0
	_check_equal(_economy.price_for(t, "item_assaultsuit"), 650, "worn kevlar under a helmet: the vest's $650")
	_check_equal(_economy.refusal(t, "item_kevlar"), Economy.OK, "and kevlar can be bought again")


func _test_a_purchase() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_send(&"round_start")
	var t := _ts[0]
	var inv := _game.inventory(t)
	inv.give_starting_items("T")
	_economy.set_money(t, 5000)
	_buy(t, "weapon_galilar")
	_sent.clear()
	_buy(t, "weapon_ak47")
	_check(inv.has("weapon_ak47") and not inv.has("weapon_galilar"), "the AK-47 takes the Galil AR's place")
	_check_equal(_economy.money(t), 5000 - 1800 - 2700, "and both were paid for")
	_step()
	var dropped := _game.entities.of_class("weapon_galilar")
	_check(dropped.size() == 1 and dropped[0].owner_id == t, "the Galil AR falls at the buyer's feet")
	var removed := _sent_named(&"item_remove")
	_check(removed.size() == 1 and removed[0].fields["userid"] == t and removed[0].fields["item"] == "weapon_galilar",
		"and item_remove says it left the buyer's inventory, once")
	var purchases := _sent_named(&"item_purchase")
	_check(purchases.size() == 1 and purchases[0].fields["weapon"] == "weapon_ak47"
		and purchases[0].fields["team"] == "T" and purchases[0].fields["loadout"] == 11 and purchases[0].fields["userid"] == t,
		"item_purchase says who bought what, for which side, from where in the menu")
	_economy.buy(t, "weapon_awp")
	_step()
	_check_equal(_economy.money(t), 500, "a purchase that cannot be paid for is refused")
	_economy.set_money(t, 5000)
	_game.command(t, "buy vesthelm")
	_game.command(t, "buy deagle")
	_step()
	_check(_game.inventory(t).helmet and _game.inventory(t).has("weapon_deagle") and _economy.money(t) == 5000 - 1000 - 700,
		"CS2's own buy command names work: buy vesthelm, buy deagle")
	_check_equal(inv.in_hand_class(), "weapon_deagle", "a gun bought is taken in hand")
	_buy(t, "weapon_flashbang")
	_check_equal(inv.in_hand_class(), "weapon_deagle", "a grenade bought is only carried")
	_check(
		_game.query(&"money", [t], -1) == _economy.money(t) and _game.query(&"can_buy", [t], false) == true,
		"what a bot asks before it shops: its money and whether it may buy (the money and can_buy queries)"
	)
	_place(t, MID)
	_check(_game.query(&"can_buy", [t], true) == false, "and out of the buy zone it may not")
	_place(t, T_SPAWN)


## The match sets a round up after the players' commands and before the
## game's step: a buy run on that tick was asked of the round before (a
## bot's warmup plan), and is dropped rather than paid from the new round's
## money.
func _test_a_buy_from_before_the_round() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_send(&"round_start")
	var t := _ts[0]
	var set_up := SimClock.current_tick()
	_game.command(t, "buy vest")
	_game.events.send(&"round_prestart")
	_game.events.flush()
	_game.step(set_up)
	_check(_game.inventory(t).armor == 0.0 and _economy.money(t) == 800, "a buy asked before the round was set up, run on its tick, buys nothing")
	_game.command(t, "buy vest")
	_step()
	_check(_game.inventory(t).armor == 100.0 and _economy.money(t) == 150, "asked again after it, it buys")


func _test_undoing_a_purchase() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_send(&"round_start")
	var ct := _cts[0]
	var inv := _game.inventory(ct)
	_economy.set_money(ct, 10000)
	_buy(ct, "weapon_famas")
	_buy(ct, "item_assaultsuit")
	_buy(ct, "item_defuser")
	_buy(ct, "weapon_flashbang")
	_buy(ct, "weapon_flashbang")
	_check_equal(_economy.money(ct), 10000 - 1950 - 1000 - 400 - 400, "bought a FAMAS, armour, a kit, two flashbangs")
	_sent.clear()
	_undo(ct, "weapon_famas")
	_check(not inv.has("weapon_famas") and _economy.money(ct) == 10000 - 1800, "undoing the FAMAS gives its $1,950 back")
	_check_equal(_sent_named(&"item_remove").size(), 1, "and says so with item_remove")
	_undo(ct, "weapon_flashbang")
	_check(inv.count("weapon_flashbang") == 1 and _economy.money(ct) == 10000 - 1600, "one flashbang undone, one kept")
	_undo(ct, "item_defuser")
	_check(not inv.has_defuser and _economy.money(ct) == 10000 - 1200, "the kit undone")
	inv.armor = 90.0
	_check(not _economy.can_undo(ct, "item_assaultsuit"), "armour hit since it was bought cannot be undone")
	inv.armor = 100.0
	_undo(ct, "item_assaultsuit")
	_check(inv.armor == 0.0 and not inv.helmet and _economy.money(ct) == 10000 - 200, "armour undone, back to none")
	_check(not _economy.can_undo(ct, "weapon_p250"), "nothing not bought this round can be undone")
	_buy(ct, "weapon_p250")
	_send(&"round_start")
	_check(not _economy.can_undo(ct, "weapon_p250"), "nor last round's purchase")


## CS2's buy and throw (Left Control held in the menu): paid for and
## counted as any purchase, but thrown out in front of the buyer rather than
## taken, so what they carry does not stop it and it is not theirs to undo.
func _test_buy_and_throw() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_send(&"round_start")
	var t := _ts[0]
	var inv := _game.inventory(t)
	inv.give_starting_items("T")
	_economy.set_money(t, 10000)
	_buy(t, "weapon_ak47")
	_check(_economy.refusal(t, "weapon_ak47") == Economy.ALREADY_HAVE and _economy.throw_refusal(t, "weapon_ak47") == Economy.OK,
		"an AK-47 in hand stops buying another for yourself, not buying one to throw")
	_sent.clear()
	_economy.buy_and_throw(t, "weapon_ak47")
	_step()
	_check(inv.has("weapon_ak47") and inv.in_hand_class() == "weapon_ak47", "the buyer keeps their own AK-47, in hand")
	_check_equal(_economy.money(t), 10000 - 2700 - 2700, "and paid for the one thrown")
	var thrown := _game.entities.of_class("weapon_ak47")
	_check(thrown.size() == 1 and thrown[0].owner_id == t and (thrown[0] as DroppedItem).entry.weapon != null,
		"the one bought is on the ground, the buyer's drop, a gun of its own")
	var entry := Inventory.Entry.new(ItemRegistry.item("weapon_deagle"))
	var throw := _game.query(&"throw_item", [t, entry]) as DroppedItem
	_check(throw != null and throw.velocity.length() > 250.0 and throw.owner_id == t,
		"the throw is ItemDrops', as a drop throws: where the buyer looks, at CS2's drop speed")
	throw.remove()
	var purchases := _sent_named(&"item_purchase")
	_check(purchases.size() == 1 and purchases[0].fields["weapon"] == "weapon_ak47", "item_purchase says it was bought")
	_check(_sent_named(&"item_remove").is_empty(), "and nothing left an inventory, so no item_remove")
	_undo(t, "weapon_ak47")
	_check(not inv.has("weapon_ak47") and _game.entities.of_class("weapon_ak47").size() == 1,
		"undoing takes back the one bought for yourself, and leaves the thrown one where it lies")
	_check_equal(_economy.throw_refusal(t, "item_assaultsuit"), Economy.CANNOT_THROW, "armour cannot be thrown")
	# Picked up, not bought: what is carried does not limit a purchase to
	# throw, but the round's purchases of the kind do (two flashbangs).
	inv.add("weapon_flashbang")
	inv.add("weapon_flashbang")
	_check_equal(_economy.throw_refusal(t, "weapon_flashbang"), Economy.OK, "two flashbangs carried, a third can still be bought to throw")
	_economy.buy_and_throw(t, "weapon_flashbang")
	_step()
	_check(inv.count("weapon_flashbang") == 2 and _game.entities.of_class("weapon_flashbang").size() == 1, "and is thrown")
	_economy.buy_and_throw(t, "weapon_flashbang")
	_step()
	_check_equal(_economy.throw_refusal(t, "weapon_flashbang"), Economy.TYPE_LIMIT,
		"two bought to throw, a third is refused: the round's two flashbangs, thrown or not")
	_economy.set_money(t, 100)
	_check_equal(_economy.throw_refusal(t, "weapon_glock"), Economy.NO_MONEY, "one that cannot be paid for is refused")
	_economy.buy_and_throw(t, "weapon_glock")
	_step()
	_check(_economy.money(t) == 100 and _game.entities.of_class("weapon_glock").is_empty(), "and nothing is thrown")
	_economy.set_money(t, 10000)
	_place(t, MID)
	_check_equal(_economy.throw_refusal(t, "weapon_ak47"), Economy.NOT_IN_BUY_ZONE, "out of the buy zone, no buying to throw either")
	_place(t, T_SPAWN)
	_check_equal(_economy.throw_refusal(t, "weapon_m4a1_silencer"), Economy.WRONG_TEAM, "nor the other side's guns")


## Every card the server would refuse is grey, want of money included; what
## is owned is outlined; with Left Control held, the cards are read for a
## buy and throw.
func _test_the_menu_greys_and_outlines() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_send(&"round_start")
	var t := _ts[0]
	var inv := _game.inventory(t)
	inv.give_starting_items("T")
	_economy.set_money(t, 5000)
	_buy(t, "weapon_ak47")
	_buy(t, "item_assaultsuit")
	_buy(t, "weapon_smokegrenade")
	var menu := BuyMenu.new()
	menu.economy = _economy
	menu.userid = t
	root.add_child(menu)
	menu.open()
	var money := _economy.money(t)
	_check_equal(money, 5000 - 2700 - 1000 - 300, "an AK-47, vest and helmet and a smoke bought")
	var cant := func(item: String) -> bool: return menu._items[item][0] != Economy.OK
	var owned := func(item: String) -> bool: return menu._items[item][2]
	_check(cant.call("weapon_galilar") and ItemRegistry.item("weapon_galilar").price > money,
		"a card that cannot be paid for is greyed, as one refused for any other reason")
	_check(cant.call("weapon_ak47") and owned.call("weapon_ak47"), "the AK-47 carried is grey and outlined")
	_check(owned.call("weapon_glock") and owned.call("item_assaultsuit") and not owned.call("item_kevlar"),
		"the stock pistol and the vest and helmet worn are outlined; the vest alone is not")
	_check(owned.call("weapon_smokegrenade") and cant.call("weapon_smokegrenade"),
		"a smoke carried is outlined, and grey at its limit of one")
	_check(not owned.call("weapon_flashbang") and not cant.call("weapon_flashbang"), "a flashbang, neither carried nor refused, is plain")
	menu.close()
	menu.free()



## Every card on both sides buys on a click through Godot's input, with the
## HUD's use prompt over the menu as GameHud stacks them: the HUD is drawn
## over the menu, as CS2's is, so nothing of it may take the clicks (the
## prompt took the fourth row's; playtest 2026-10-05).
func _test_the_menu_buys_by_clicks() -> void:
	var size_was := root.size
	root.size = Vector2i(1920, 1080)
	_new_game(1)
	_send(&"begin_new_match")
	for userid in [_ts[0], _cts[0]]:
		var side := _body(userid).team
		var menu := BuyMenu.new()
		menu.economy = _economy
		menu.userid = userid
		root.add_child(menu)
		var prompt := UsePrompt.new()
		root.add_child(prompt)
		await process_frame
		var inv := _game.inventory(userid)
		var missed := PackedStringArray()
		for item: String in Loadout.items(side):
			_send(&"round_start")
			_economy.set_money(userid, 16000)
			for carried in inv.items_in(ItemDef.Slot.GRENADE):
				inv.remove(carried.item.item_class)
			menu.open()
			var at: Vector2 = (menu._cards[item] as Rect2).get_center()
			var motion := InputEventMouseMotion.new()
			motion.position = at
			root.push_input(motion)
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = at
			root.push_input(press)
			var release := press.duplicate() as InputEventMouseButton
			release.pressed = false
			root.push_input(release)
			_sent.clear()
			_step()
			var bought := false
			for event in _sent:
				bought = bought or (event.name == &"item_purchase" and event.fields.get("weapon") == item)
			if not bought:
				missed.append(item)
			menu.close()
		_check(missed.is_empty(), "every %s card buys on a click, the use prompt over the menu%s" % [
			side, "" if missed.is_empty() else "; these did not: %s" % ", ".join(missed)])
		prompt.free()
		menu.free()
	root.size = size_was


func _test_the_menu_buys_by_keys() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_send(&"round_start")
	var t := _ts[0]
	_economy.set_money(t, 3000)
	var menu := BuyMenu.new()
	menu.economy = _economy
	menu.userid = t
	root.add_child(menu)
	_place(t, MID)
	var refusals := []
	menu.refused.connect(func(why: StringName) -> void: refusals.append(why))
	menu.open()
	_check(not menu.is_open(), "the menu does not open out of the buy zone")
	_check(refusals == [Economy.NOT_IN_BUY_ZONE], "and says why, for the HUD to show (%s)" % [refusals])
	_place(t, T_SPAWN)
	menu.open()
	_check(menu.is_open(), "it opens in it")
	menu._press_number(3)
	menu._press_number(1)
	_step()
	_check(_game.inventory(t).has("weapon_ak47") and _economy.money(t) == 300,
		"4 then 2 buys the AK-47: CS2's menu has the rifles fourth, after equipment, pistols and mid-tier")
	var behind := KeyCatcher.new()
	root.add_child(behind)
	for keycode in [KEY_Q, KEY_Z, KEY_X, KEY_G]:
		var press := InputEventKey.new()
		press.physical_keycode = keycode
		press.keycode = keycode
		press.pressed = true
		root.push_input(press)
	_check(menu.is_open() and behind.presses == 0, "with the menu open no key press gets past it (%d did)" % behind.presses)
	menu.close()
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.keycode = KEY_Q
	q.pressed = true
	root.push_input(q)
	_check_equal(behind.presses, 1, "closed, it lets them through")
	behind.free()
	menu.open()
	_place(t, MID)
	_step()
	menu._process(0.0)
	_check(not menu.is_open(), "and it closes on leaving the buy zone")
	menu.free()


## The menu's countdown always shows a time, as CS2's does: the economy's
## once its clock runs, and before that what is left all the same, the rest
## of freeze time and the buy time after it, or in warmup its clock.
func _test_the_menu_counts_down_buying() -> void:
	_new_game(1)
	_send(&"begin_new_match")
	_send(&"round_start")
	var menu := BuyMenu.new()
	menu.economy = _economy
	menu.userid = _ts[0]
	_check(is_inf(menu.buy_seconds_shown()), "without a match, a buy time not yet running has no end to show")
	var state := MatchState.new()
	menu.match_state = state
	state.phase = MatchState.Phase.FREEZE
	state.phase_ends_usec = SimClock.now_usec() + 15_000_000
	_check_near(menu.buy_seconds_shown(), 15.0 + _economy.rules.buy_seconds,
		"in freeze time it counts the rest of freeze time and the buy time after it")
	state.phase = MatchState.Phase.WARMUP
	state.phase_ends_usec = SimClock.now_usec() + 90_000_000
	_check_near(menu.buy_seconds_shown(), 90.0, "in warmup, which buying lasts, the warmup's clock")
	state.phase = MatchState.Phase.LIVE
	_send(&"round_freeze_end", {}, SimClock.tick_end_usec(_tick))
	_check_near(menu.buy_seconds_shown(), _economy.buy_seconds_left(SimClock.now_usec()),
		"and once the economy's clock runs, that")
	state.free()
	menu.free()


# --- Helpers -----------------------------------------------------------------------

## A game of one side against the other, each player at their spawn, with
## the economy in it.
func _new_game(per_side: int) -> void:
	for body in _bodies.values():
		body.free()
	_bodies.clear()
	_ts.clear()
	_cts.clear()
	_sent.clear()
	_game = GameSystems.new()
	var zones := BuyZones.new()
	zones.add_box("T", T_ZONE)
	zones.add_box("CT", CT_ZONE)
	_economy = Economy.new(MoneyRules.new(), zones)
	_game.add_system(_economy)
	_game.events.listen_all(func(event: GameEvent) -> void: _sent.append(event))
	for side in ["T", "CT"]:
		for i in per_side:
			var body := Body.new()
			body.team = side
			root.add_child(body)
			body.global_position = T_SPAWN if side == "T" else CT_SPAWN
			var userid := _game.add_player(body)
			_bodies[userid] = body
			(_ts if side == "T" else _cts).append(userid)


func _body(userid: int) -> Body:
	return _bodies[userid]


func _place(userid: int, at: Vector3) -> void:
	_body(userid).global_position = at


func _step() -> void:
	_tick += 1
	_game.step(_tick)


func _send(name: StringName, fields: Dictionary = {}, at_usec: int = -1) -> void:
	_game.events.send(name, fields, at_usec)
	_step()


## A round from its start to its end, won this way.
func _round(winner: String, reason: String) -> void:
	_send(&"round_start")
	_send(&"round_end", {"winner": winner, "reason": reason})


## What a player is paid for a round won this way, from an empty account;
## everyone's is emptied first, for _last_paid.
func _paid(userid: int, winner: String, reason: String) -> int:
	for everyone in _ts + _cts:
		_economy.set_money(everyone, 0)
	_round(winner, reason)
	return _economy.money(userid)


## What a player was paid by the last _paid round.
func _last_paid(userid: int) -> int:
	return _economy.money(userid)


func _buy(userid: int, item: String) -> void:
	_economy.buy(userid, item)
	_step()


func _undo(userid: int, item: String) -> void:
	_economy.undo(userid, item)
	_step()


func _all_have(userids: Array[int], amount: int) -> bool:
	for userid in userids:
		if _economy.money(userid) != amount:
			return false
	return true


func _sent_named(name: StringName) -> Array[GameEvent]:
	var out: Array[GameEvent] = []
	for event in _sent:
		if event.name == name:
			out.append(event)
	return out
