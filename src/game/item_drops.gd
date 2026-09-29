class_name ItemDrops
extends RefCounted

## Items on the ground: what a death leaves, what the drop command throws,
## walking over one to pick it up, and E on the one looked at. The items
## contract's own system, which GameSystems adds first.
##
## A death drops what Inventory.drops_on_death says (the C4 is the bomb's to
## drop, and is not in it). "drop" throws what is in hand, but never the
## knife and never the C4 (the bomb takes that command when the C4 is in
## hand). Walking over an item takes it if its slot is free, as CS2 does,
## measured from the item's centre of mass (DroppedItem.position).
## Pressing E (UserCmd.USE) takes the item looked at, within reach and in
## clear sight, and a gun whose slot is taken takes the place of the one
## there, which is thrown as a drop throws it (CS2's cone search, player_use_radius
## 80; issue 3 of reference/playtest-2026-09-25.md). An item there is no
## room for is refused with item_pickup_failed, as CS2 refuses a fifth
## grenade. Near the bomb E is the bomb's: the query use_claimed, which
## the bomb answers, is asked first (sv_weapon_swap_difficulty_near_hi_pri).
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
## How far from the eyes E reaches: CS2's player_use_radius, 80.
const USE_REACH := 80.0
## How far off the aim an item may lie for E to take it, in degrees: CS2
## searches a cone, of an angle in no file (measure). The nearest to the
## aim is taken.
const USE_CONE_DEGREES := 30.0
## Whether a gun E takes into a free slot comes into hand: CS2 leaves it to
## the client's "Switch to picked up weapon", whose default is in no file
## (measure). A gun that takes the place of the one in hand always does.
const USE_DRAWS := false
## item_pickup_failed's reason for an item there is no room for. CS2's
## reason numbers are in no file (measure).
const FAILED_NO_ROOM := 0

var game: GameSystems
## Whether a player pressed E this tick:
## func(userid: int, player: Node3D) -> bool. Reads the command the player
## ran this tick (PlayerSim.last_command); a check may put its own.
var use_pressed: Callable = _use_from_command


func attach(p_game: GameSystems) -> void:
	game = p_game
	game.events.listen(&"player_death", _on_death)
	game.events.listen(&"round_prestart", _on_round_prestart)
	game.on_command(&"drop", _on_drop)
	# A purchase thrown out rather than taken (the economy's buy and throw).
	game.provide(&"throw_item", throw_item)


func tick(t: SimTick) -> void:
	for userid in t.roster.ids():
		var node := t.roster.player(userid)
		if node != null and _alive(userid) and bool(use_pressed.call(userid, node)):
			_use(t, userid, node)
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
		var model_basis := ItemPhysics.of(entry.item.item_class).model_held_at(from).basis
		var spin := model_basis.x * rng.randf_range(-DEATH_TUMBLE, DEATH_TUMBLE) + Vector3.UP * rng.randf_range(-DEATH_TUMBLE, DEATH_TUMBLE)
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
	DroppedItem.drop_from(game, userid, entry, from, _throw_velocity(node), _throw_spin(from, entry.item.item_class, rng))
	game.events.send(&"item_remove", {"userid": userid, "item": entry.item.item_class})
	return true


## Throws an item that was never in the player's inventory (a purchase
## bought to throw) as the drop command throws what is in hand: from where
## they would hold it, where they look, at CS2's drop speed. The entity,
## already spawned; it announces nothing, as nothing left an inventory.
func throw_item(userid: int, entry: Inventory.Entry) -> DroppedItem:
	var node := game.roster.player(userid)
	var item_class := entry.item.item_class
	var space := game.last_tick.space if game.last_tick != null else null
	var from := _clear_of_walls(node, _held_transform_of(node, item_class), space, item_class)
	var rng := _seeded(userid, item_class)
	return DroppedItem.drop_from(game, userid, entry, from, _throw_velocity(node), _throw_spin(from, item_class, rng))


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


## E: the item looked at, within reach and in sight, unless the bomb claims
## the press.
func _use(t: SimTick, userid: int, node: Node3D) -> void:
	if bool(t.game.query(&"use_claimed", [userid], false)):
		return
	var item := use_target(t, node, userid)
	if item != null:
		take(t, item, userid)


## The item E would take: the one nearest the aim, inside USE_CONE_DEGREES
## of it and USE_REACH of the eyes, with nothing of the world between, that
## the player may take yet (DroppedItem.can_be_taken_by). Null if none. One
## ray for each item in the cone, and only on a press.
func use_target(t: SimTick, node: Node3D, userid: int) -> DroppedItem:
	var eyes := _eyes(node)
	var aim := _aim(node)
	var least_cos := cos(deg_to_rad(USE_CONE_DEGREES))
	var candidates: Array[Array] = []
	for entity in t.entities.all():
		var item := entity as DroppedItem
		if item == null or item.entry == null or not item.can_be_taken_by(userid, t.now_usec):
			continue
		var to_item := item.position - eyes
		var distance := to_item.length()
		if distance > USE_REACH:
			continue
		var along := 1.0 if distance < 1e-3 else aim.dot(to_item / distance)
		if along < least_cos:
			continue
		candidates.append([along, distance, item])
	# Nearest the aim first, then nearest the eyes.
	candidates.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	for candidate in candidates:
		var item: DroppedItem = candidate[2]
		# Through PhysicsQueries, as every query is: once Box3D owns the map,
		# Godot's own space has no walls in it, and a ray cast straight into
		# it saw every gun through them.
		if PhysicsQueries.intersect_ray(t.space, PhysicsRayQueryParameters3D.create(eyes, item.position, Hitscan.WORLD_LAYER)).is_empty():
			return item
	return null


## Takes the item for the player by E: into a free slot, or in place of
## the gun in its slot, which is thrown from the hand as a drop throws it.
## An item there is no room for (a grenade past the limits, a kit already
## worn) is refused with item_pickup_failed; a kit is only a CT's to take.
## Whether it was taken.
func take(t: SimTick, item: DroppedItem, userid: int) -> bool:
	var inventory := game.inventory(userid)
	if inventory == null or item.entry == null:
		return false
	var item_class := item.entry.item.item_class
	if item_class == "item_defuser" and t.roster.team_of(userid) != "CT":
		return false
	var def := item.entry.item
	var there := inventory.item_in(def.slot, def.slot_position) if def.is_gun else null
	var can := inventory.can_add(item_class)
	var swap := there != null and (def.slot == ItemDef.Slot.PRIMARY or def.slot == ItemDef.Slot.PISTOL)
	if not swap and can != Inventory.Can.OK:
		t.events.send(&"item_pickup_failed", {"userid": userid, "item": item_class, "reason": FAILED_NO_ROOM,
			"limit": def.max_carried if def.is_grenade() else 1})
		return false
	var in_hand := there != null and inventory.in_hand_class() == there.item.item_class
	if swap:
		# The one there goes as a drop throws it, whatever is in hand, and
		# the one taken has its place; the same gun as the one there
		# (another AK-47) as well, which add alone would refuse.
		var node := t.roster.player(userid)
		var from := _clear_of_walls(node, _held_transform_of(node, there.item.item_class), t.space, there.item.item_class)
		var old := inventory.remove(there.item.item_class)
		var rng := _seeded(userid, old.item.item_class)
		DroppedItem.drop_from(game, userid, old, from, _throw_velocity(node), _throw_spin(from, old.item.item_class, rng))
		t.events.send(&"item_remove", {"userid": userid, "item": old.item.item_class})
	for i in item.entry.count:
		inventory.add(item_class, item.entry.weapon)
	if def.is_gun and (in_hand or USE_DRAWS):
		inventory.select(item_class)
	item.remove()
	if item_class == "item_defuser":
		t.events.send(&"defuser_pickup", {"entityid": item.id, "userid": userid})
	else:
		t.events.send(&"item_pickup", {"userid": userid, "item": item_class})
	return true


## Whether the player pressed E in the command they ran this tick.
static func _use_from_command(_userid: int, player: Node3D) -> bool:
	var sim := player as PlayerSim
	return sim != null and sim.last_command != null and sim.last_command.first_press(UserCmd.USE) != null


static func _eyes(node: Node3D) -> Vector3:
	return node.global_position + Vector3.UP * (float(node.call(&"eye_height")) if node.has_method(&"eye_height") else 64.0)


static func _aim(node: Node3D) -> Vector3:
	var yaw = node.get(&"yaw_degrees")
	var pitch = node.get(&"pitch_degrees")
	return PlayerInput.aim_direction(yaw if yaw is float else 0.0, pitch if pitch is float else 0.0)


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
	var aim := _aim(node)
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


## Where item_class would be in the player's hand, whatever is in it: the
## gun E swaps out is thrown from its own hold, not the one in hand's.
func _held_transform_of(node: Node3D, item_class: String) -> Transform3D:
	if node != null and node.has_method(&"held_transform"):
		return HeldPose.of(node, item_class)
	return _middle(node)


## How a thrown gun turns: end over end, the muzzle dipping away from the
## thrower, and a little twist. from is the attachment bone, whose local X
## is not the gun's lateral axis, so the tumble is about the model's.
func _throw_spin(from: Transform3D, item_class: String, rng: RandomNumberGenerator) -> Vector3:
	var model_basis := ItemPhysics.of(item_class).model_held_at(from).basis
	return model_basis.x * rng.randf_range(0.5, 1.0) * THROW_TUMBLE \
		+ Vector3.UP * rng.randf_range(-1.0, 1.0) * THROW_TWIST


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
	var eye := _eyes(node)
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
	if PhysicsQueries.intersect_shape(space, query, 1).is_empty():
		query.motion = way
		var fractions := PhysicsQueries.cast_motion(space, query)
		if not fractions.is_empty():
			free = fractions[0]
	else:
		var hit := PhysicsQueries.intersect_ray(space, PhysicsRayQueryParameters3D.create(eye, body.origin, Hitscan.WORLD_LAYER))
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
