class_name ItemDrops
extends RefCounted

## Items on the ground: what a death leaves, what the drop command throws,
## and walking over one to pick it up. The items contract's own system, which
## GameSystems adds first.
##
## A death drops what Inventory.drops_on_death says (the C4 is the bomb's to
## drop, and is not in it). "drop" throws what is in hand, but never the
## knife and never the C4 (the bomb takes that command when the C4 is in
## hand). Walking over an item takes it if its slot is free, as CS2 does;
## swapping with the one in hand (E) is left for when there is a use key.
## What is on the ground goes at round_prestart, CS2's clean-up of the map.
##
## CS2's values are from its convars (SteamDatabase's DumpSource2
## convars.txt) and game/csgo/cfg/gamemode_competitive.cfg.

## mp_drop_knife_enable and mp_drop_grenade_enable.
const DROP_KNIFE := false
const DROP_GRENADES := true
## How often an item on the ground looks for a player standing on it:
## CS2's pickup_check_period, 0.25 s, so 16 ticks at 64 Hz.
const PICKUP_CHECK_PERIOD_USEC := 250_000
## How near a player's feet an item has to lie to be taken, across and up:
## the hull's half width and its height. In no file (measure).
const REACH_ACROSS := 32.0
const REACH_UP := 72.0
## How hard a drop throws the item forward, in units a second, and up. In
## no file (measure).
const THROW_SPEED := 200.0
const THROW_UP := 100.0

var game: GameSystems


func attach(p_game: GameSystems) -> void:
	game = p_game
	game.events.listen(&"player_death", _on_death)
	game.events.listen(&"round_prestart", _on_round_prestart)
	game.on_command(&"drop", _on_drop)


func tick(t: SimTick) -> void:
	for entity in t.entities.all():
		var item := entity as DroppedItem
		if item == null or item.entry == null or t.now_usec < item.next_pickup_check_usec:
			continue
		item.next_pickup_check_usec = t.now_usec + PICKUP_CHECK_PERIOD_USEC
		for userid in t.roster.ids():
			if _try_pickup(t, item, userid):
				break


func _on_death(event: GameEvent) -> void:
	var userid: int = event.fields.userid
	var inventory := game.inventory(userid)
	if inventory == null:
		return
	var node := game.roster.player(userid)
	var velocity: Vector3 = node.get(&"velocity") if node != null and node.get(&"velocity") is Vector3 else Vector3.ZERO
	for entry in inventory.drops_on_death():
		var dropped := DroppedItem.drop(game, userid, entry, velocity)
		if entry.item.item_class == "item_defuser":
			game.events.send(&"defuser_dropped", {"entityid": dropped.id})


## A new round's map has nothing on the ground; the bomb clears its own C4.
func _on_round_prestart(_event: GameEvent) -> void:
	for entity in game.entities.all():
		if entity is DroppedItem:
			entity.remove()


func _on_drop(userid: int, _args: PackedStringArray, _t: SimTick) -> bool:
	var inventory := game.inventory(userid)
	if inventory == null or not _alive(userid):
		return false
	var held := inventory.in_hand()
	if held == null or not held.item.droppable or held.item.item_class == "weapon_c4":
		return false
	if (held.item.is_grenade() and not DROP_GRENADES) or (held.item.type == "knife" and not DROP_KNIFE):
		return false
	var entry := inventory.remove(held.item.item_class)
	DroppedItem.drop(game, userid, entry, _throw_velocity(userid))
	game.events.send(&"item_remove", {"userid": userid, "item": entry.item.item_class})
	return true


func _try_pickup(t: SimTick, item: DroppedItem, userid: int) -> bool:
	if not item.can_be_taken_by(userid, t.now_usec) or not _alive(userid):
		return false
	var node := t.roster.player(userid)
	var inventory := game.inventory(userid)
	if node == null or inventory == null:
		return false
	var offset := item.position - node.global_position
	if Vector2(offset.x, offset.z).length() > REACH_ACROSS or offset.y < -1.0 or offset.y > REACH_UP:
		return false
	var item_class := item.entry.item.item_class
	# The kit is only any use to a CT.
	if item_class == "item_defuser" and t.roster.team_of(userid) != "CT":
		return false
	if inventory.can_add(item_class) != Inventory.Can.OK:
		return false
	for i in item.entry.count:
		inventory.add(item_class, item.entry.weapon)
	item.remove()
	if item_class == "item_defuser":
		t.events.send(&"defuser_pickup", {"entityid": item.id, "userid": userid})
	else:
		t.events.send(&"item_pickup", {"userid": userid, "item": item_class})
	return true


func _alive(userid: int) -> bool:
	var node := game.roster.player(userid)
	if node == null:
		return false
	var alive = node.get(&"alive")
	return alive if alive is bool else true


## Forward from where they look, and a little up.
func _throw_velocity(userid: int) -> Vector3:
	var node := game.roster.player(userid)
	var yaw = node.get(&"yaw_degrees") if node != null else null
	var radians := deg_to_rad(yaw if yaw is float else 0.0)
	return Vector3(-sin(radians), 0.0, -cos(radians)) * THROW_SPEED + Vector3.UP * THROW_UP
