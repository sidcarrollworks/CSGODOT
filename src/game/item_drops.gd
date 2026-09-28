class_name ItemDrops
extends RefCounted

## Items on the ground: what a death leaves, what the drop command throws,
## and walking over one to pick it up. The items contract's own system, which
## GameSystems adds first.
##
## A death drops what Inventory.drops_on_death says (the C4 is the bomb's to
## drop, and is not in it). "drop" throws what is in hand, but never the
## knife and never the C4 (the bomb takes that command when the C4 is in
## hand). Walking over an item takes it if its slot is free, as CS2 does,
## measured from the item's centre of mass (DroppedItem.position);
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
## How near a player's feet an item's centre of mass has to be to be
## taken, across, up and down: the hull's width, from the middle of its
## feet (the item's own size standing in for the half the hull leaves), its
## standing height, and below the feet as far as the ground under the
## middle of the hull can be on the steepest floor a player stands on (the
## box stands on its uphill edge, 16 x tan(45.6) = 16.3 units above the
## ground under its middle at sv_standable_normal 0.7), with a little over
## for a gun's thickness. CS2's touch box is in no file (measure).
const REACH_ACROSS := 32.0
const REACH_UP := 72.0
const REACH_DOWN := 18.0
## How hard a drop throws the item: CS2's m_flDropSpeed, 300 for every
## weapon (GT's CCSWeaponBaseVData.h, no override in weapons.vdata;
## reference/research/round-bomb-grenades.md 3.2). Its direction is where
## the player looks, lifted a little so a drop straight ahead arcs rather
## than skims: how much is in no file (measure). The dropper's own motion
## goes with it.
const THROW_SPEED := 300.0
const THROW_LIFT := 0.25
## How a thrown item turns, radians a second: end over end away from the
## thrower, and a little about the up axis, each a share of the most, from
## the drop's seed. A death lets the gun go with a little of each. By eye.
const THROW_TUMBLE := 2.5
const THROW_TWIST := 1.5
const DEATH_TUMBLE := 2.0

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


## A death lets go of what it drops where the body has it: the gun from the
## hand, as it was held, the rest from the body's middle, all moving as the
## body was.
func _on_death(event: GameEvent) -> void:
	var userid: int = event.fields.userid
	var inventory := game.inventory(userid)
	if inventory == null:
		return
	var node := game.roster.player(userid)
	var velocity := _death_velocity(node)
	var held := inventory.in_hand_class()
	# Held out past the hull, a gun can be through the wall its holder died
	# against, as for a drop.
	var hand := _clear_of_walls(node, _held_transform(node), game.last_tick.space if game.last_tick != null else null, held)
	for entry in inventory.drops_on_death():
		var from := hand if entry.item.item_class == held else _middle(node)
		var rng := _seeded(userid, entry.item.item_class)
		var spin := from.basis.x * rng.randf_range(-DEATH_TUMBLE, DEATH_TUMBLE) + Vector3.UP * rng.randf_range(-DEATH_TUMBLE, DEATH_TUMBLE)
		var dropped := DroppedItem.drop_from(game, userid, entry, from, velocity, spin)
		if entry.item.item_class == "item_defuser":
			game.events.send(&"defuser_dropped", {"entityid": dropped.id})


## A new round's map has nothing on the ground; the bomb clears its own C4.
func _on_round_prestart(_event: GameEvent) -> void:
	for entity in game.entities.all():
		if entity is DroppedItem:
			entity.remove()


func _on_drop(userid: int, _args: PackedStringArray, t: SimTick) -> bool:
	var inventory := game.inventory(userid)
	if inventory == null or not _alive(userid):
		return false
	var held := inventory.in_hand()
	if held == null or not held.item.droppable or held.item.item_class == "weapon_c4":
		return false
	if (held.item.is_grenade() and not DROP_GRENADES) or (held.item.type == "knife" and not DROP_KNIFE):
		return false
	var node := game.roster.player(userid)
	var from := _clear_of_walls(node, _held_transform(node), t.space, held.item.item_class)
	var entry := inventory.remove(held.item.item_class)
	var rng := _seeded(userid, entry.item.item_class)
	# End over end, the muzzle dipping away from the thrower, and a little
	# twist.
	var spin := from.basis.x * rng.randf_range(0.5, 1.0) * THROW_TUMBLE \
		+ Vector3.UP * rng.randf_range(-1.0, 1.0) * THROW_TWIST
	DroppedItem.drop_from(game, userid, entry, from, _throw_velocity(node), spin)
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
	if Vector2(offset.x, offset.z).length() > REACH_ACROSS or offset.y < -REACH_DOWN or offset.y > REACH_UP:
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


## Where they look, lifted a little, at CS2's drop speed, with their own
## motion.
func _throw_velocity(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	var yaw = node.get(&"yaw_degrees")
	var pitch = node.get(&"pitch_degrees")
	var aim := PlayerInput.aim_direction(yaw if yaw is float else 0.0, pitch if pitch is float else 0.0)
	var own = node.get(&"velocity")
	return (aim + Vector3.UP * THROW_LIFT).normalized() * THROW_SPEED + (own if own is Vector3 else Vector3.ZERO)


## How a player was moving as they died: PlayerSim keeps it
## (death_velocity), since a death stops the body before the death's event is
## handed out; else their velocity, else still.
static func _death_velocity(node: Node3D) -> Vector3:
	if node == null:
		return Vector3.ZERO
	for property: StringName in [&"death_velocity", &"velocity"]:
		var value = node.get(property)
		if value is Vector3:
			return value
	return Vector3.ZERO


## Where the thing in hand is, and which way it points: the player's own
## (PlayerSim.held_transform), or else their middle.
func _held_transform(node: Node3D) -> Transform3D:
	if node != null and node.has_method(&"held_transform"):
		return node.call(&"held_transform")
	return _middle(node)


func _middle(node: Node3D) -> Transform3D:
	var at := node.global_position + Vector3.UP * 36.0 if node != null else Vector3.ZERO
	var yaw = node.get(&"yaw_degrees") if node != null else null
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw if yaw is float else 0.0)), at)


## Held out in front, a gun can be through a wall the player is up
## against: its hull is swept from the eyes to where it is held, and it is
## brought back to this side of whatever is in the way. Where the hull does
## not even fit at the eyes (a long gun, the back to a wall), its centre of
## mass is brought back along a ray instead, and its first tick steps it out
## of the wall.
static func _clear_of_walls(node: Node3D, from: Transform3D, space: PhysicsDirectSpaceState3D, item_class: String) -> Transform3D:
	if node == null or space == null:
		return from
	var eye := node.global_position + Vector3.UP * (float(node.call(&"eye_height")) if node.has_method(&"eye_height") else 64.0)
	var hull := ItemPhysics.of(item_class)
	var body := hull.body_of(hull.model_held_at(from))
	var way := body.origin - eye
	if way.length_squared() < 1e-6:
		return from
	var free := 1.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull.shape
	query.transform = Transform3D(body.basis, eye)
	query.collision_mask = Hitscan.WORLD_LAYER
	if space.collide_shape(query, 1).is_empty():
		query.motion = way
		var fractions := space.cast_motion(query)
		if not fractions.is_empty():
			free = fractions[0]
	else:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, body.origin, Hitscan.WORLD_LAYER))
		if not hit.is_empty():
			free = maxf(0.0, ((hit["position"] as Vector3) - eye).length() - 4.0) / way.length()
	if free >= 1.0:
		return from
	return Transform3D(from.basis, from.origin - way * (1.0 - free))


## Randomness for one drop that a server and a client agree on: from who
## dropped what, and when.
func _seeded(userid: int, item_class: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([userid, item_class, game.now_usec()])
	return rng
