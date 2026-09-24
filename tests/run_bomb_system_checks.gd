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
	_test_a_plant_through_the_game(t_id)
	_test_the_blast_through_the_damage_path(t_id, ct_id, ct)
	_test_dropped_and_picked_up(t_id, planter)
	_finish("bomb-system")


func _player(at: Vector3, team: String) -> PlayerSim:
	var player := PlayerSim.new()
	player.team = team
	player.respawns = false
	_world.add_child(player)
	player.place(at, 0.0)
	player.on_ground = true
	return player


func _step(seconds: float) -> void:
	for i in SimClock.ticks_in(seconds):
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


func _test_no_plant_before_the_round_is_live(t_id: int) -> void:
	_asks[t_id] = {"plant": true}
	_step(4.0)
	_check(not _system.bomb.planting() and _system.bomb.state == C4.State.CARRIED,
		"holding the plant in freeze time plants nothing")


func _test_a_plant_through_the_game(t_id: int) -> void:
	_heard.clear()
	_round_event(&"round_freeze_end")
	_check(_system.live, "the round is live at round_freeze_end")
	_step(0.5)
	_check(_game.query(&"holds_still", [t_id], false) == true, "the game's holds_still says the planter is held still")
	_check(_game.query(&"holds_still", [t_id + 1], false) == false, "and nobody else")
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
