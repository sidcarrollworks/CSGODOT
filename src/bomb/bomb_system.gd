class_name BombSystem
extends RefCounted

## The bomb as one of the game's systems (GameSystems): it joins the C4 to
## the shared contracts (reference/systems/contracts.md). Each tick it
## builds the C4's view of every player from the Roster, their inventory and
## their command, runs the C4, sends what happened as game events, deals the
## blast as DamageInfo, keeps the carrier's inventory and the bomb on the
## ground (a SimEntity) in step with it, and hands it out each round.
##
## The rules themselves are C4's; this only carries them to and from the
## rest of the game, so C4 stays plain state that is checked on its own.

var bomb: C4
var sites: Array[BombSite] = []
## Whether a plant may be made: between round_freeze_end and round_end in a
## match. With no match (the range) always.
var live: bool = true
## What each player asks of the bomb this tick, as {plant, use}:
## func(userid: int, player: Node3D, inventory: Inventory) -> Dictionary.
## Reads the player's command by default. The range reads its own keys, and
## may add "team" to plant as a T and defuse as a CT with one player.
var input_of: Callable

var _game: GameSystems
## The bomb on the ground, when it is: a dropped "weapon_c4" or the
## "planted_c4".
var _entity: SimEntity
## Seeded from the round, so a server and a replay pick the same carrier.
var _rng := RandomNumberGenerator.new()
## Who asked to drop the bomb this tick (the drop command, with it in hand).
var _drop_asked := {}


func _init(p_sites: Array[BombSite] = [], rules: C4Rules = null) -> void:
	sites = p_sites
	bomb = C4.new(rules)
	input_of = _input_from_command


func attach(game: GameSystems) -> void:
	_game = game
	game.events.listen(&"round_prestart", _on_round_prestart)
	game.events.listen(&"round_start", _on_round_start)
	game.events.listen(&"round_freeze_end", func(_e: GameEvent) -> void: live = true)
	game.events.listen(&"round_end", func(_e: GameEvent) -> void: live = false)
	game.on_command(&"drop", _on_drop)


## Hands the bomb to a player now: a round's start does it to a random
## terrorist; the range to you.
func give_to(userid: int) -> void:
	_forget_entity()
	var inventory := _game.inventory(userid) if _game != null else null
	if inventory != null and not inventory.has("weapon_c4"):
		inventory.add("weapon_c4")
	var player := _game.roster.player(userid) if _game != null else null
	bomb.give_to(userid, player.global_position if player != null else Vector3.ZERO)
	_send_events()


func tick(t: SimTick) -> void:
	_game = t.game
	var actors: Array[C4.Actor] = []
	for userid in t.roster.ids():
		var player := t.roster.player(userid) as PlayerSim
		if player == null:
			continue
		var actor := C4.Actor.of_player(player, userid)
		var inventory := t.game.inventory(userid)
		var asked: Dictionary = input_of.call(userid, player, inventory)
		actor.plant_held = live and bool(asked.get("plant", false))
		actor.use_held = bool(asked.get("use", false))
		actor.drop = _drop_asked.has(userid)
		actor.has_kit = inventory != null and inventory.has_defuser
		if asked.has("team"):
			actor.team = asked["team"]
		actors.append(actor)
	_drop_asked.clear()
	var was := bomb.state
	var carrier := bomb.carrier
	bomb.tick(t.now_usec, actors, sites)
	_follow(was, carrier)
	_send_events()
	for record in bomb.take_blast():
		_deal(record, t)


## Whether a player is planting or defusing, which holds them still.
func holds_still(userid: int) -> bool:
	return bomb.holds_still(userid)


func save_state() -> Dictionary:
	return {"bomb": bomb.save_state(), "live": live, "entity": _entity.id if _entity != null else 0}


func load_state(saved: Dictionary) -> void:
	bomb.load_state(saved["bomb"])
	live = saved["live"]
	var id: int = saved["entity"]
	_entity = _game.entities.find(id) if _game != null and id != 0 else null


## Keeps the inventory and the entity on the ground in step with the bomb.
func _follow(was: C4.State, carrier: int) -> void:
	var now := bomb.state
	if now == was:
		if _entity != null:
			_entity.position = bomb.position
		return
	match now:
		C4.State.DROPPED:
			_take_from(carrier)
			_put_down("weapon_c4", carrier)
		C4.State.CARRIED:
			_forget_entity()
			var inventory := _game.inventory(bomb.carrier)
			if inventory != null and not inventory.has("weapon_c4"):
				inventory.add("weapon_c4")
		C4.State.PLANTED:
			_take_from(carrier)
			_put_down("planted_c4", bomb.planter)


func _take_from(userid: int) -> void:
	var inventory := _game.inventory(userid) if _game != null else null
	if inventory != null and inventory.has("weapon_c4"):
		inventory.remove("weapon_c4")


func _put_down(entity_class: String, owner: int) -> void:
	_forget_entity()
	if _game == null:
		return
	_entity = SimEntity.new(entity_class, owner, bomb.position)
	_game.entities.spawn(_entity)


func _forget_entity() -> void:
	if _entity != null:
		_entity.remove()
		_entity = null


## The C4's events onto the game's queue; a dropped bomb's with its entity.
func _send_events() -> void:
	for event in bomb.take_events():
		var fields := event.duplicate()
		var event_name := StringName(fields["name"])
		fields.erase("name")
		if event_name == &"bomb_dropped" and _entity != null:
			fields["entindex"] = _entity.id
		if _game != null:
			_game.events.send(event_name, fields)


## The blast, to one player: armour takes a grenade's share, and no team
## scaling (the contract's damage for the bomb).
func _deal(record: Dictionary, t: SimTick) -> void:
	var target := t.roster.hit_target(record["victim"])
	var player := t.roster.player(record["victim"])
	if target == null or player == null:
		return
	var info := DamageInfo.new()
	info.attacker = record["attacker"]
	info.inflictor = "planted_c4"
	info.weapon = "weapon_c4"
	info.damage = record["amount"]
	info.damage_type = DamageInfo.DMG_BLAST
	info.origin = record["origin"]
	info.position = player.global_position + Vector3.UP * 36.0
	info.direction = (info.position - info.origin).normalized()
	info.at_usec = t.now_usec
	info.armor_penetration = 0.5
	DamageInfo.deal(target, info, t.events)


func _on_round_prestart(_event: GameEvent) -> void:
	_forget_entity()
	bomb.reset()
	live = false


## CS2 gives the bomb to one terrorist at random at each round's start.
func _on_round_start(_event: GameEvent) -> void:
	if _game == null:
		return
	var terrorists: Array[int] = []
	for userid in _game.roster.on_team("T"):
		var player := _game.roster.player(userid) as PlayerSim
		if player != null and player.alive:
			terrorists.append(userid)
	if terrorists.is_empty():
		bomb.reset()
		return
	_rng.seed = hash(["c4", SimClock.current_tick()])
	give_to(terrorists[_rng.randi_range(0, terrorists.size() - 1)])


## The drop command is the bomb's when the bomb is in hand (ItemDrops
## takes it for anything else): it drops on this tick.
func _on_drop(userid: int, _args: PackedStringArray, _t: SimTick) -> bool:
	var inventory := _game.inventory(userid) if _game != null else null
	if inventory == null or inventory.in_hand_class() != "weapon_c4" or bomb.carrier != userid:
		return false
	_drop_asked[userid] = true
	return true


## Plant is the attack button with the bomb in hand, use the use key, from
## the command the player ran this tick.
func _input_from_command(_userid: int, player: Node3D, inventory: Inventory) -> Dictionary:
	var sim := player as PlayerSim
	if sim == null or sim.last_command == null:
		return {}
	var cmd := sim.last_command
	var in_hand := inventory != null and inventory.in_hand_class() == "weapon_c4"
	return {
		"plant": in_hand and cmd.held(UserCmd.ATTACK),
		"use": cmd.held(UserCmd.USE),
	}
