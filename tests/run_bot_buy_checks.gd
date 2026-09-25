extends "res://tests/check_suite.gd"

## Checks bots buying as CS2's classic bot does (BotBuying): nothing below
## bot_eco_limit, a primary by its template, the first its side may buy and
## it can afford, then armour, a kit for a counter-terrorist, and a third of
## the time one grenade, an HE six times as likely as each other kind. Then
## the plan carried out through the economy as buy commands, and bots in a
## match shopping in freeze time and taking their best gun out, the same way
## every run.
##
##   godot --headless --path . --script tests/run_bot_buy_checks.gd
##
## Needs nothing extracted: bots without their model wear the standard
## boxes. Where the characters are extracted, their bodies are checked to
## hold what is in hand.

const SECOND := 1_000_000
const T_ZONE := AABB(Vector3(-256.0, 0.0, -256.0), Vector3(512.0, 128.0, 512.0))
const CT_ZONE := AABB(Vector3(-256.0, 0.0, -4256.0), Vector3(512.0, 128.0, 512.0))
const T_SPAWNS := [
	{"position": Vector3(0.0, 0.0, 0.0), "yaw": 0.0, "priority": 0},
	{"position": Vector3(128.0, 0.0, 0.0), "yaw": 0.0, "priority": 0},
]
const CT_SPAWNS := [
	{"position": Vector3(0.0, 0.0, -4000.0), "yaw": 180.0, "priority": 0},
	{"position": Vector3(128.0, 0.0, -4000.0), "yaw": 180.0, "priority": 0},
]


## A player as the roster sees one: a node with a side and a life.
class Body extends Node3D:
	var team: String = "T"
	var alive: bool = true


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_test_the_eco_limit()
	_test_what_each_template_buys()
	_test_a_bot_that_has_a_primary()
	_test_the_dice()
	_test_the_templates_are_spread_as_cs2s()
	_test_what_a_bot_may_hold()
	_test_the_plan_through_the_economy()
	await _test_bots_in_a_match()
	_finish("bot-buying")


# --- The plan --------------------------------------------------------------------

func _test_the_eco_limit() -> void:
	for side: String in ["T", "CT"]:
		_check(BotBuying.plan(side, 1999, null, &"Rifle", _dice(1)).is_empty(), "%s: $1,999 buys nothing (bot_eco_limit 2000)" % side)
		_check(not BotBuying.plan(side, 2000, null, &"Rifle", _dice(1)).is_empty(), "%s: $2,000 buys" % side)


func _test_what_each_template_buys() -> void:
	var ct := BotBuying.plan("CT", 4750, null, &"Rifle", _dice(1))
	_check(
		ct.slice(0, 4) == PackedStringArray(["weapon_m4a1_silencer", "item_assaultsuit", "item_kevlar", "item_defuser"]),
		"a CT Rifle bot on $4,750: the M4 its loadout holds (the M4A1-S), the suit, the vest, the kit (%s)" % [ct]
	)
	_check_equal(_primary("T", 4750, &"Rifle"), "weapon_ak47", "a T Rifle bot skips the CTs' M4 for the AK-47")
	_check_equal(_primary("T", 2000, &"RifleT"), "weapon_galilar", "a T RifleT bot on $2,000: the Galil AR, the AK-47 unaffordable")
	_check_equal(_primary("CT", 2000, &"RifleT"), "weapon_famas", "a CT RifleT bot on $2,000: the FAMAS")
	_check_equal(_primary("CT", 3000, &"Sniper"), "weapon_ssg08", "a CT Sniper bot on $3,000: the SSG 08 (the AWP unaffordable, the SCAR-20 not in the loadout)")
	_check_equal(_primary("T", 2500, &"Power"), "weapon_xm1014", "a T Power bot on $2,500: the XM1014 (the M249 not in the loadout)")
	_check_equal(_primary("CT", 2000, &"Spray"), "weapon_mp9", "a CT Spray bot on $2,000: the MP9 (the P90 unaffordable)")
	_check_equal(_primary("T", 2000, &"None"), "weapon_galilar", "one with no preference buys by autobuy's order: the Galil AR on $2,000")
	_check_equal(BotBuying.resolve("T", "mp7"), "weapon_mp5sd", "the MP7 is bought as the MP5-SD the loadout holds in its place")
	_check_equal(BotBuying.resolve("T", "m4a1"), "", "a T cannot buy an M4")
	_check_equal(BotBuying.resolve("CT", "m249"), "", "nobody buys the M249, which the loadout does not hold")
	_check(not "item_defuser" in BotBuying.plan("T", 16000, null, &"Rifle", _dice(1)), "a T plans no kit")


func _test_a_bot_that_has_a_primary() -> void:
	var carried := Inventory.new()
	carried.give_starting_items("CT")
	carried.add("weapon_famas")
	var plan := BotBuying.plan("CT", 5000, carried, &"Rifle", _dice(1))
	_check(
		plan.slice(0, 3) == PackedStringArray(["item_assaultsuit", "item_kevlar", "item_defuser"]),
		"a bot that kept its FAMAS buys no primary, but armour and the kit (%s)" % [plan]
	)


func _test_the_dice() -> void:
	_check(BotBuying.plan("T", 5000, null, &"Rifle", _dice(42)) == BotBuying.plan("T", 5000, null, &"Rifle", _dice(42)), "the same seed plans the same")
	var plans := 10000
	var grenades := 0
	var he := 0
	var wrong_fire := 0
	for seed in plans:
		for side: String in ["T", "CT"]:
			var plan := BotBuying.plan(side, 16000, null, &"Rifle", _dice(seed))
			if "weapon_molotov" in plan and side == "CT" or "weapon_incgrenade" in plan and side == "T":
				wrong_fire += 1
			if side == "T":
				var grenade := _grenade_in(plan)
				if not grenade.is_empty():
					grenades += 1
					if grenade == "weapon_hegrenade":
						he += 1
	var share := float(grenades) / plans
	_check(absf(share - 0.33) < 0.015, "a grenade in a third of plans (sv_bot_buy_grenade_chance 33: %.3f)" % share)
	var he_share := float(he) / maxi(grenades, 1)
	_check(absf(he_share - 0.6) < 0.02, "an HE in six of ten of them (%.3f)" % he_share)
	_check_equal(wrong_fire, 0, "a CT's fire grenade is the incendiary, a T's the molotov")
	_check(BotBuying.plan("T", 1000, null, &"Rifle", _dice(7)).is_empty(), "and the dice buy nothing below the limit")


func _test_the_templates_are_spread_as_cs2s() -> void:
	_check_equal(BotBuying.template_for("Bot3"), BotBuying.template_for("Bot3"), "a bot keeps its template")
	var names := 14700
	var rifle := 0
	for i in names:
		if BotBuying.template_for("Bot%d" % i) == &"Rifle":
			rifle += 1
	var share := float(rifle) / names
	_check(absf(share - 25.0 / 147.0) < 0.01, "Rifle comes as often as botprofile.db's 25 profiles of 147 use it (%.3f)" % share)


## What a bot may take in hand is on its side's menu: the match reads every
## model and clip on the menus before play (Competitive._prepare_holding),
## so nothing a bot buys is read during it.
func _test_what_a_bot_may_hold() -> void:
	var off_menu := PackedStringArray()
	var bought := {}
	for side: String in ["T", "CT"]:
		var menu := Loadout.items(side)
		var buys := PackedStringArray()
		for template: StringName in BotBuying.TEMPLATES:
			for short: String in BotBuying.TEMPLATES[template]:
				var item_class := BotBuying.resolve(side, short)
				if item_class.is_empty():
					continue
				buys.append(item_class)
				if not item_class in menu:
					off_menu.append("%s %s" % [side, item_class])
		bought[side] = buys
		if not Inventory.STARTING_PISTOLS[side] in menu:
			off_menu.append("%s %s" % [side, Inventory.STARTING_PISTOLS[side]])
	_check(
		off_menu.is_empty() and "weapon_ak47" in bought["T"] and "weapon_awp" in bought["T"] and not "weapon_famas" in bought["T"]
			and "weapon_m4a1_silencer" in bought["CT"] and not "weapon_ak47" in bought["CT"],
		"every gun a bot's templates buy, and its starting pistol, is on its side's menu, which is read before play (off it: %s)" % [off_menu]
	)


# --- Through the economy --------------------------------------------------------

func _test_the_plan_through_the_economy() -> void:
	var game := GameSystems.new()
	var zones := BuyZones.new()
	zones.add_box("T", T_ZONE)
	zones.add_box("CT", CT_ZONE)
	var economy := Economy.new(MoneyRules.new(), zones)
	game.add_system(economy)
	var bought := []
	game.events.listen(&"item_purchase", func(event: GameEvent) -> void: bought.append(event.fields["weapon"]))
	var body := Body.new()
	body.team = "CT"
	root.add_child(body)
	body.global_position = CT_SPAWNS[0]["position"]
	var ct := game.add_player(body)
	game.inventory(ct).give_starting_items("CT")
	var tick := 1000
	for event: StringName in [&"begin_new_match", &"round_start"]:
		game.events.send(event)
		tick += 1
		game.step(tick)
	economy.set_money(ct, 4050)
	var plan := BotBuying.plan("CT", int(game.query(&"money", [ct], 0)), game.inventory(ct), &"Rifle", _dice(3))
	for item_class in plan:
		game.command(ct, "buy " + item_class)
	tick += 1
	game.step(tick)
	var inv := game.inventory(ct)
	var spent := 2900 + 1000
	for grenade: String in ["weapon_decoy"]:
		if inv.has(grenade):
			spent += 50
	_check(
		inv.has("weapon_m4a1_silencer") and inv.in_hand_class() == "weapon_m4a1_silencer" and inv.helmet and inv.armor == 100.0
			and not inv.has_defuser and economy.money(ct) == 4050 - spent,
		"a CT on $4,050: the M4A1-S in hand and the suit; the vest refused as the suit covers it, the kit as $150 does not (%s, $%d left)" % [plan, economy.money(ct)]
	)
	_check(bought.slice(0, 2) == ["weapon_m4a1_silencer", "item_assaultsuit"], "item_purchase for each, in the order asked (%s)" % [bought])
	body.free()


# --- In a match -------------------------------------------------------------------

## Bots in a match with an economy: the CT on $4,050 buys its rifle and armour
## in freeze time and has the rifle out before freeze time ends; a CT on
## $16,000 buys exactly what its seed plans, on the tick its seed gives; the
## T on $800 keeps its Glock, and takes out a rifle it picks up; one with no
## template buys nothing on $16,000. The same twice over, tick for tick.
func _test_bots_in_a_match() -> void:
	var first: Dictionary = await _play_freeze_time()
	var rich: Dictionary = first["rich"]
	var carried := Inventory.new()
	carried.give_starting_items("CT")
	var seeded := RandomNumberGenerator.new()
	seeded.seed = hash(["bot_buy", rich["userid"], rich["shop_tick"]])
	var planned := BotBuying.plan("CT", 16000, carried, &"Rifle", seeded)
	# The vest is refused once the suit is on: armour is full.
	var expected := []
	for item_class in planned:
		if item_class != "item_kevlar":
			expected.append(item_class)
	_check(
		rich["shop_tick"] > 0 and rich["bought"] == expected,
		"a CT bot on $16,000 buys what its seed (its userid and the tick it shops on) plans, the vest refused over the suit (%s, planned %s)" % [rich["bought"], planned]
	)
	_check(
		first["purchases"].size() >= 5 and first["purchases"].all(func(p: Array) -> bool: return p[0] >= rich["shop_tick"] - 64),
		"every purchase is logged with its tick (%d)" % first["purchases"].size()
	)
	var ct: Dictionary = first["ct"]
	_check(
		ct["carries"].has("weapon_m4a1_silencer") and ct["in_hand"] == "weapon_m4a1_silencer" and ct["helmet"]
			and ct["money"] <= 4050 - 3900 and ct["frozen"],
		"a CT bot on $4,050 buys the M4A1-S and the suit in freeze time and takes the rifle out before it ends (%s)" % [ct]
	)
	var t: Dictionary = first["t"]
	_check(
		t["carries"] == ["weapon_glock", "weapon_knife"] and t["in_hand"] == "weapon_glock" and t["money"] == 800,
		"a T bot on $800 buys nothing (bot_eco_limit) and keeps the knife and the Glock-18 (%s)" % [t]
	)
	_check_equal(first["t_takes_up"], "weapon_ak47", "handed an AK-47 as a pickup hands it (not in hand), it takes it out itself")
	var idle: Dictionary = first["idle"]
	_check(
		idle["carries"] == ["weapon_glock", "weapon_knife"] and idle["money"] == 16000,
		"a bot with no template never buys, even on $16,000 (%s)" % [idle]
	)
	if first["drawn"]:
		_check(first["body_holds"] == "weapon_m4a1_silencer" and first["body_shows"], "its body holds the rifle, and shows it")
		_check(first["dead_holds"] == "" and not first["dead_shows"], "and dead, holds nothing: the gun falls on its own")
	var second: Dictionary = await _play_freeze_time()
	for who: String in ["ct", "rich", "t", "idle"]:
		_check(first[who] == second[who], "%s: two runs of the same match buy the same (%s, %s)" % [who, first[who], second[who]])
	_check(first["purchases"] == second["purchases"], "and every purchase on the same tick (%s)" % [first["purchases"]])


## A match of four bots, a CT on $4,050, a CT on $16,000, a T on $800 and a
## T with no template on $16,000, run for 1.5 s of freeze time; what each
## carries then, and every purchase with its tick.
func _play_freeze_time() -> Dictionary:
	var stage := Node3D.new()
	root.add_child(stage)
	var world := GameWorld.new()
	stage.add_child(world)
	world.set_physics_process(false)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16384.0, 32.0, 16384.0)
	shape.shape = box
	shape.position = Vector3(0.0, -16.0, 0.0)
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	var bots := {}
	for who: String in ["ct", "rich", "t", "idle"]:
		var bot := (load("res://src/bots/bot.tscn") as PackedScene).instantiate() as Bot
		bot.name = "Buyer_" + who
		bot.team = "CT" if who in ["ct", "rich"] else "T"
		bot.buy_template = &"" if who == "idle" else (&"Rifle" if bot.team == "CT" else &"RifleT")
		stage.add_child(bot)
		world.add_player(bot)
		bots[who] = bot
	await physics_frame
	var game := MatchState.new()
	game.rules = MatchRules.new()
	game.rules.warmup_seconds = 0.0
	game.spawns = {"T": T_SPAWNS.duplicate(), "CT": CT_SPAWNS.duplicate()}
	stage.add_child(game)
	world.match_state = game
	var zones := BuyZones.new()
	zones.add_box("T", T_ZONE)
	zones.add_box("CT", CT_ZONE)
	var economy := Economy.new(MoneyRules.new(), zones)
	economy.match_rules = game.rules
	world.game.add_system(economy)
	var purchases := []
	world.game.events.listen(&"item_purchase", func(event: GameEvent) -> void:
		purchases.append([event.tick, event.fields["userid"], event.fields["weapon"]]))
	game.start(SimClock.now_usec())
	# The match's start is handed out on the world's first tick.
	world.step()
	economy.set_money(bots["ct"].userid, 4050)
	economy.set_money(bots["rich"].userid, 16000)
	economy.set_money(bots["idle"].userid, 16000)
	for i in SimClock.ticks_in(1.5):
		world.step()
	var out := {"purchases": purchases.duplicate()}
	var rich_bought := []
	var rich_tick := -1
	for purchase: Array in purchases:
		if purchase[1] == bots["rich"].userid:
			rich_bought.append(purchase[2])
			rich_tick = purchase[0] if rich_tick < 0 else rich_tick
	for who: String in bots:
		var bot: Bot = bots[who]
		var carries := []
		for entry in bot.inventory.entries():
			carries.append(entry.item.item_class)
		carries.sort()
		out[who] = {
			"carries": carries, "in_hand": bot.in_hand_class(), "money": economy.money(bot.userid),
			"helmet": bot.hit_target.helmet, "frozen": bot.frozen,
		}
	out["rich"]["userid"] = bots["rich"].userid
	out["rich"]["shop_tick"] = rich_tick
	out["rich"]["bought"] = rich_bought
	# A gun that comes to a bot not in hand (a pickup): it takes it out.
	var t_bot: Bot = bots["t"]
	t_bot.inventory.add("weapon_ak47")
	for i in 3:
		world.step()
	out["t_takes_up"] = t_bot.in_hand_class()
	var ct: Bot = bots["ct"]
	out["drawn"] = ct.model != null
	if ct.model != null:
		ct._process(0.0)
		out["body_holds"] = ct.model.holding
		out["body_shows"] = ct.model.held_weapon != null and ct.model.held_weapon.visible
		ct.hit_target.apply_damage(1000.0, &"chest", 1.0)
		ct._process(0.0)
		out["dead_holds"] = ct.model.holding
		out["dead_shows"] = ct.model.held_weapon != null and ct.model.held_weapon.visible
	stage.queue_free()
	await physics_frame
	return out


# --- Helpers -----------------------------------------------------------------------

func _dice(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


func _primary(side: String, money: int, template: StringName) -> String:
	var plan := BotBuying.plan(side, money, null, template, _dice(1))
	return plan[0] if not plan.is_empty() and ItemRegistry.item(plan[0]).is_gun else ""


func _grenade_in(plan: PackedStringArray) -> String:
	for item_class in plan:
		if ItemRegistry.item(item_class).is_grenade():
			return item_class
	return ""
