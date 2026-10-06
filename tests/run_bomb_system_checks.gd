extends "res://tests/check_suite.gd"

## Checks the bomb as one of the game's systems (BombSystem on GameSystems):
## handed to a terrorist at a round's start, planted only once the round is
## live, its events on the game's queue with the schema's names and keys,
## the carrier's inventory and the bomb on the ground kept in step with it,
## and the blast dealt as DamageInfo, armour and all, credited to the
## planter.
##
##   godot --headless --path . --script tests/run_bomb_system_checks.gd
##
## Needs nothing extracted. The players stand still on a floor; what each
## asks of the bomb is set by the checks, and the ticks are theirs.

const SITE_BOX := AABB(Vector3(0.0, -8.0, 0.0), Vector3(256.0, 136.0, 256.0))
const ON_SITE := Vector3(128.0, 0.0, 128.0)
const OFF_SITE := Vector3(-512.0, 0.0, 128.0)

var _world: Node3D
var _game: GameSystems
var _system: BombSystem
var _tick: int = 10_000
var _heard: Array[GameEvent] = []
## What each userid asks of the bomb: {plant, use, drop}.
var _asks := {}


func _initialize() -> void:
	_run()


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	await physics_frame

	_game = GameSystems.new()
	_system = BombSystem.new([BombSite.of_box("A", SITE_BOX)])
	_check(_system.input_of.is_valid(), "by default the bomb reads each player's command")
	_system.input_of = func(userid: int, _player_node: Node3D, _inventory: Inventory) -> Dictionary:
		return _asks.get(userid, {})
	_game.add_system(_system)
	_game.events.listen_all(func(event: GameEvent) -> void: _heard.append(event))

	var planter := _player(ON_SITE, "T")
	var t_id := _game.add_player(planter, planter.hit_target)
	var ct := _player(ON_SITE + Vector3(300.0, 0.0, 0.0), "CT")
	var ct_id := _game.add_player(ct, ct.hit_target)
	await physics_frame

	_test_handed_out_at_the_round_start(t_id)
	_test_no_plant_before_the_round_is_live(t_id)
	_test_a_plant_after_the_round_has_ended(t_id)
	_test_a_plant_through_the_game(t_id)
	_test_the_blast_through_the_damage_path(t_id, ct_id, ct)
	_test_dropped_and_picked_up(t_id, planter)
	_test_who_the_round_hands_it_to()
	_test_taken_from_a_bot()
	_finish("bomb-system")


func _player(at: Vector3, team: String) -> PlayerSim:
	var player := PlayerSim.new()
	player.team = team
	player.respawns = false
	_world.add_child(player)
	player.place(at, 0.0)
	player.on_ground = true
	return player


## Steps the game. Nothing runs the players here, so each is crouched as
## their own tick would crouch them: when the game says so (the crouches
## query, the planter).
func _step(seconds: float) -> void:
	for i in SimClock.ticks_in(seconds):
		for userid in _game.roster.ids():
			var player := _game.roster.player(userid) as PlayerSim
			if player != null:
				player.wants_duck = bool(_game.query(&"crouches", [userid], false))
		_tick += 1
		_game.step(_tick)


## Sends a round's events as the match will, and hands them out.
func _round_event(event_name: StringName) -> void:
	_game.events.send(event_name)
	_game.events.flush()


func _names_heard() -> PackedStringArray:
	var names := PackedStringArray()
	for event in _heard:
		names.append(String(event.name))
	return names


func _heard_one(event_name: StringName) -> GameEvent:
	for event in _heard:
		if event.name == event_name:
			return event
	return null


func _test_handed_out_at_the_round_start(t_id: int) -> void:
	_heard.clear()
	_round_event(&"round_prestart")
	_round_event(&"round_start")
	_check_equal(_system.bomb.carrier, t_id, "at the round's start the only terrorist carries the bomb")
	_check(_game.inventory(t_id).has("weapon_c4"), "it is in their inventory")
	var given := _heard_one(&"player_given_c4")
	_check(given != null and given.fields["userid"] == t_id, "and player_given_c4 says so")
	_check(not _system.live, "no plant until freeze time is over")


## CS2's bot_defer_to_human_items (competitive's 1): the round hands it to a
## living human T when there is one, to a bot only when there is none, and
## to any T with the rule off. The players' is_bot is what says who is a bot.
func _test_who_the_round_hands_it_to() -> void:
	var a_bot := Bot.new()
	var a_person := PlayerSim.new()
	_check(a_bot.is_bot and not a_person.is_bot, "a Bot is a bot, a PlayerSim a person")
	a_bot.free()
	a_person.free()
	var roster := Roster.new()
	var human := _player(OFF_SITE, "T")
	var bots: Array[int] = []
	for i in 4:
		var bot := _player(OFF_SITE, "T")
		bot.is_bot = true
		bots.append(roster.add(bot))
	var ct := _player(OFF_SITE, "CT")
	roster.add(ct)
	var human_id := roster.add(human)
	var rules := C4Rules.new()
	_check_equal(BombSystem.may_be_given(roster, rules), [human_id] as Array[int], "with a human T and four T bots, only the human")
	rules.bot_defer_to_human_items = false
	_check_equal(BombSystem.may_be_given(roster, rules).size(), 5, "with the rule off, any of the five")
	rules.bot_defer_to_human_items = true
	human.alive = false
	_check_equal(BombSystem.may_be_given(roster, rules), bots, "the human dead, one of the bots")
	for player: Node in [human, ct]:
		player.queue_free()
	for id in bots:
		roster.player(id).queue_free()


## "[E] Take Bomb" through the game: E looking at a bot teammate who carries
## it moves the bomb from the bot's inventory to yours, and E is the
## bomb's that tick, so a gun on the ground in the same view stays there.
func _test_taken_from_a_bot() -> void:
	var game := GameSystems.new()
	var system := BombSystem.new([BombSite.of_box("A", SITE_BOX)])
	var asks := {}
	system.input_of = func(userid: int, _player_node: Node3D, _inventory: Inventory) -> Dictionary:
		return asks.get(userid, {})
	game.add_system(system)
	var heard: Array[StringName] = []
	game.events.listen_all(func(event: GameEvent) -> void: heard.append(event.name))
	var you := _player(OFF_SITE, "T")
	var you_id := game.add_player(you, you.hit_target)
	var bot := _player(OFF_SITE + Vector3(0.0, 0.0, -50.0), "T")
	bot.is_bot = true
	var bot_id := game.add_player(bot, bot.hit_target)
	# Facing -Z, down at the bot's middle.
	you.yaw_degrees = 0.0
	you.pitch_degrees = rad_to_deg(atan2(C4.BODY_MIDDLE - you.eye_height(), 50.0))
	system.give_to(bot_id)
	var drops := game.systems()[0] as ItemDrops
	drops.use_pressed = func(userid: int, _node: Node3D) -> bool: return userid == you_id
	var gun := ItemRegistry.item("weapon_ak47")
	var lying := DroppedItem.drop_from(game, bot_id, Inventory.Entry.new(gun), Transform3D(Basis(), bot.global_position + Vector3(0.0, 30.0, 5.0)), Vector3.ZERO, Vector3.ZERO)
	# In view by the bot (no floor here, so it stays in the air), long
	# enough dropped for E to take it, and never walked over.
	lying.dropped_usec = game.now_usec() - 10_000_000
	lying.next_pickup_check_usec = 1 << 60
	_check(system.use_claimed(you_id), "looking at a bot who carries the bomb, E is the bomb's")
	asks[you_id] = {"use_pressed": true}
	_tick += 1
	game.step(_tick)
	_check_equal(system.bomb.carrier, you_id, "E takes the bomb from the bot")
	_check(game.inventory(you_id).has("weapon_c4") and not game.inventory(bot_id).has("weapon_c4"),
		"out of its inventory into yours")
	_check(heard.has(&"bomb_pickup"), "with bomb_pickup")
	_check(not game.inventory(you_id).has("weapon_ak47") and lying.entry != null, "and the gun on the ground in view stays there")
	_check(not system.use_claimed(bot_id), "the bot cannot take it back")
	asks.clear()
	_tick += 1
	game.step(_tick)
	_check(game.inventory(you_id).has("weapon_ak47"), "and with the bomb yours, the next E takes the gun")
	for player: Node in [you, bot]:
		player.queue_free()


func _test_no_plant_before_the_round_is_live(t_id: int) -> void:
	_asks[t_id] = {"plant": true}
	_step(4.0)
	_check(not _system.bomb.planting() and _system.bomb.state == C4.State.CARRIED,
		"holding the plant in freeze time plants nothing")


## CS2's plant asks nothing of the round (the C4's primary attack,
## server.dll 180a18640): a plant that would finish on the tick the round
## ends goes down, and so does one begun after it; the next round's prestart
## takes the bomb off the ground and its start hands it out again.
func _test_a_plant_after_the_round_has_ended(t_id: int) -> void:
	_round_event(&"round_freeze_end")
	_asks[t_id] = {"plant": true}
	_step(_system.bomb.rules.plant_seconds - 0.1)
	var was_planting := _system.bomb.planting()
	_heard.clear()
	# The match ends the round (time out) before the game's step, on the
	# tick the plant would finish.
	_game.events.send(&"round_end", {"winner": "CT", "reason": "TargetSaved"})
	_step(0.2)
	_check(
		was_planting and _names_heard().has("bomb_planted") and _system.bomb.planted()
			and _game.entities.of_class("planted_c4").size() == 1 and _system.live,
		"a plant that finishes on the tick the round ends goes down: bomb_planted, a bomb on the ground"
	)
	_asks.erase(t_id)
	_round_event(&"round_prestart")
	_round_event(&"round_start")
	_check(_game.entities.of_class("planted_c4").is_empty() and _system.bomb.carrier == t_id and not _system.live,
		"the next round's prestart takes it off the ground, and its start hands it out again")
	_round_event(&"round_freeze_end")
	_game.events.send(&"round_end", {"winner": "CT", "reason": "TargetSaved"})
	_game.events.flush()
	_asks[t_id] = {"plant": true}
	_step(_system.bomb.rules.plant_seconds + 0.3)
	_check(_system.bomb.planted(), "a plant begun after the round has ended goes down too")
	_round_event(&"round_prestart")
	_round_event(&"round_start")
	# Still held, for the next round's plant.


func _test_a_plant_through_the_game(t_id: int) -> void:
	_heard.clear()
	_round_event(&"round_freeze_end")
	_check(_system.live, "the round is live at round_freeze_end")
	_step(0.5)
	_check(_game.query(&"holds_still", [t_id], false) == true, "the game's holds_still says the planter is held still")
	_check(_game.query(&"holds_still", [t_id + 1], false) == false, "and nobody else")
	_check(_game.query(&"crouches", [t_id], false) == true and _game.query(&"crouches", [t_id + 1], false) == false,
		"the game's crouches says the planter crouches, and nobody else")
	_step(_system.bomb.rules.plant_seconds - 0.4)
	_check(_system.bomb.planted(), "then holding it on the site plants it")
	_check(_names_heard().has("bomb_beginplant") and _names_heard().has("bomb_planted"),
		"bomb_beginplant and bomb_planted are on the game's events")
	_check_equal(_heard_one(&"bomb_planted").fields.get("site"), "A", "on site A")
	_check(not _game.inventory(t_id).has("weapon_c4"), "the planter no longer carries it")
	var planted := _game.entities.of_class("planted_c4")
	_check(planted.size() == 1 and planted[0].owner_id == t_id, "a planted_c4 is in the world, the planter's")
	_asks[t_id] = {}


func _test_the_blast_through_the_damage_path(t_id: int, ct_id: int, ct: PlayerSim) -> void:
	ct.hit_target.armor = 100.0
	_heard.clear()
	var planted_at := _system.bomb.position
	_step(40.5)
	_check_equal(_system.bomb.state, C4.State.EXPLODED, "40 s later it goes off")
	var raw := C4.blast_damage(
		(ct.global_position + Vector3.UP * 36.0).distance_to(planted_at), _system.bomb.rules.bomb_damage
	)
	var hurt: GameEvent = null
	var death: GameEvent = null
	for event in _heard:
		if event.name == &"player_hurt" and event.fields["userid"] == ct_id:
			hurt = event
		if event.name == &"player_death" and event.fields["userid"] == ct_id:
			death = event
	_check(hurt != null, "the CT 300 units off is hurt (player_hurt), the blast doing %.0f" % raw)
	if hurt != null:
		_check_equal(hurt.fields["attacker"], GameEvents.NOBODY, "credited to nobody, not the planter, as in CS2")
		_check_equal(hurt.fields["weapon"], "weapon_c4", "with the bomb")
		_check_equal(hurt.fields["hitgroup"], 0, "in no one place")
		_check(hurt.fields["dmg_armor"] > 0, "and armour took a share")
	_check(death != null and death.fields["weapon"] == "weapon_c4", "it kills them (player_death, weapon_c4)")
	_check(_heard_one(&"bomb_exploded") != null, "and bomb_exploded is sent")


func _test_dropped_and_picked_up(t_id: int, planter: PlayerSim) -> void:
	_round_event(&"round_prestart")
	_check(_game.entities.of_class("planted_c4").is_empty(), "a new round clears the planted bomb")
	# The blast killed its planter too; the next round brings them back.
	_check(not planter.alive, "the blast killed its own planter, standing on it")
	planter.respawn()
	planter.place(OFF_SITE, 0.0)
	planter.on_ground = true
	_round_event(&"round_start")
	_round_event(&"round_freeze_end")
	var other := _player(OFF_SITE + Vector3(200.0, 0.0, 0.0), "T")
	var other_id := _game.add_player(other, other.hit_target)
	_step(0.1)
	_check_equal(_system.bomb.carrier, t_id, "the carrier still has it")
	_heard.clear()
	planter.alive = false
	_step(0.1)
	_check_equal(_system.bomb.state, C4.State.DROPPED, "their death drops it")
	var dropped := _game.entities.of_class("weapon_c4")
	_check(dropped.size() == 1, "as a weapon_c4 in the world")
	var event := _heard_one(&"bomb_dropped")
	_check(event != null and dropped.size() == 1 and event.fields["entindex"] == dropped[0].id,
		"bomb_dropped carries its entity id")
	_check(not _game.inventory(t_id).has("weapon_c4"), "and it leaves the dead carrier's inventory")

	_heard.clear()
	other.global_position = OFF_SITE
	_step(0.1)
	_check_equal(_system.bomb.carrier, other_id, "a terrorist walking over it picks it up")
	_check(_game.inventory(other_id).has("weapon_c4"), "into their inventory")
	_check(_game.entities.of_class("weapon_c4").is_empty(), "and it is off the ground")
	_check(_heard_one(&"bomb_pickup") != null, "bomb_pickup is sent")

	_heard.clear()
	_game.inventory(other_id).give_starting_items("T")
	_game.inventory(other_id).select_slot(ItemDef.Slot.KNIFE)
	_game.command(other_id, "drop")
	_step(0.1)
	_check_equal(_system.bomb.state, C4.State.CARRIED, "the drop command with something else in hand leaves the bomb")
	_game.inventory(other_id).select("weapon_c4")
	_game.command(other_id, "drop")
	_step(0.1)
	_check_equal(_system.bomb.state, C4.State.DROPPED, "with the bomb in hand it drops the bomb")
	_check(not _game.inventory(other_id).has("weapon_c4") and _game.entities.of_class("weapon_c4").size() == 1,
		"out of the inventory and onto the ground")
