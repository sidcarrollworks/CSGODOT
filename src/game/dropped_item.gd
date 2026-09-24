class_name DroppedItem
extends SimEntity

## An item lying in the world, or thrown to it: a gun with its ammo (its own
## Weapon, from the Inventory.Entry that was carried), a grenade, the Zeus,
## the kit. Its entity class is the item's (weapon_ak47, item_defuser). The
## C4 on the ground is the bomb's own entity, not one of these.
##
## It leaves the hand where the gun was held and pointing the way it was
## held (drop_from), flies under gravity turning as it was thrown, skips
## off what it meets and comes to rest, then lies there until a player
## picks it up (ItemDrops) or a round's start clears the map. The flight is
## one trace a tick while it moves, none once it lies still. Which side it
## lies on is the drawing's (DroppedItemView): the simulation knows where it
## is and where it points, not the model's shape.
##
## Nothing cleans it up sooner: CS2's weapon_auto_cleanup_time and
## weapon_max_before_cleanup are both 0. Bullets pass through it, as
## mp_shoot_dropped_grenades is false; what blasts and bullets do to a gun
## on the ground, its mass and how it bounces are in no file (measure), so
## the skip below is a choice to be checked against CS2.

## sv_gravity, as MovementConfig has it.
const GRAVITY := 800.0
## Who dropped it cannot take it straight back, so a gun thrown forward is
## not picked up again as it leaves the hand: CS2's
## mp_weapon_prev_owner_touch_time, 1.5 s.
const PREV_OWNER_TOUCH_USEC := 1_500_000
## Anyone else waits too: CS2's mp_weapon_next_owner_touch_time, 1.3 s. The
## convar has no description; that it is anyone else's wait, for every
## drop and a death's too, is read from its name (measure).
const NEXT_OWNER_TOUCH_USEC := 1_300_000
## How it meets the world, in no file (measure): the share of its speed
## into a surface it bounces back with, the share of its speed along the
## surface it keeps, and how much of its spin; under REST_SPEED on a floor
## it stops.
const BOUNCE := 0.25
const SLIDE := 0.5
const SPIN_KEPT := 0.4
const REST_SPEED := 40.0
## A gun that lands on an end falls flat rather than hopping on it: each
## time it meets the world it is turned this share of the way to level,
## the way it was heading. By eye.
const LEVEL_ON_BOUNCE := 0.7
## How steep a surface still counts as a floor to rest on.
const FLOOR_NORMAL_Y := 0.7
## How far off a surface it is kept, so the next trace does not start in it.
const SKIN := 0.1

var entry: Inventory.Entry
var velocity := Vector3.ZERO
## Which way it points: the model's +Z is its muzzle, +Y its top, as a gun
## is held (PlayerSim.held_transform). And the tick before's, for drawing
## between the two.
var basis := Basis.IDENTITY
var previous_basis := Basis.IDENTITY
## How it turns, in radians a second about the world's axes.
var angular_velocity := Vector3.ZERO
var resting: bool = false
## Simulation time it came to rest at, for the drawing to lay it down from
## then; -1 while it moves.
var rested_usec: int = -1
## Simulation time it was dropped at.
var dropped_usec: int = 0
## When ItemDrops next looks for someone standing on it: first when anyone
## may take it, then every pickup check period.
var next_pickup_check_usec: int = 0


func _init(p_entry: Inventory.Entry = null, p_owner_id: int = GameEvents.NOBODY, p_position := Vector3.ZERO, p_velocity := Vector3.ZERO) -> void:
	super(p_entry.item.item_class if p_entry != null else "", p_owner_id, p_position)
	entry = p_entry
	velocity = p_velocity


## Puts entry on the ground from the player userid's middle, let fall with
## velocity: what a gun a purchase replaced does. The entity, already
## spawned into game.entities. It announces nothing: whoever took the item
## out of the inventory sends item_remove, once.
static func drop(game: GameSystems, userid: int, p_entry: Inventory.Entry, p_velocity := Vector3.ZERO) -> DroppedItem:
	var node := game.roster.player(userid)
	var from := node.global_position + Vector3.UP * 36.0 if node != null else Vector3.ZERO
	return drop_from(game, userid, p_entry, Transform3D(Basis.IDENTITY, from), p_velocity)


## Puts entry in the world at from (where it was held and which way it
## pointed), thrown with velocity and turning with spin.
static func drop_from(
	game: GameSystems, userid: int, p_entry: Inventory.Entry, from: Transform3D,
	p_velocity := Vector3.ZERO, spin := Vector3.ZERO
) -> DroppedItem:
	var item := DroppedItem.new(p_entry, userid, from.origin, p_velocity)
	item.basis = from.basis.orthonormalized()
	item.previous_basis = item.basis
	item.angular_velocity = spin
	item.dropped_usec = game.now_usec()
	item.next_pickup_check_usec = item.dropped_usec + mini(PREV_OWNER_TOUCH_USEC, NEXT_OWNER_TOUCH_USEC)
	game.entities.spawn(item)
	return item


## Whether userid may pick it up at now_usec.
func can_be_taken_by(userid: int, now_usec: int) -> bool:
	var wait := PREV_OWNER_TOUCH_USEC if userid == owner_id else NEXT_OWNER_TOUCH_USEC
	return now_usec >= dropped_usec + wait


func tick(t: SimTick) -> void:
	previous_basis = basis
	if resting:
		return
	if angular_velocity != Vector3.ZERO:
		basis = (Basis(angular_velocity.normalized(), angular_velocity.length() * t.dt) * basis).orthonormalized()
	velocity.y -= GRAVITY * t.dt
	if t.space == null:
		# No world to fall onto: it stays where it was dropped.
		_rest(t.now_usec)
		return
	var to := position + velocity * t.dt
	var query := PhysicsRayQueryParameters3D.create(position, to, Hitscan.WORLD_LAYER)
	var hit := t.space.intersect_ray(query)
	if hit.is_empty():
		position = to
		return
	var normal: Vector3 = hit["normal"]
	position = (hit["position"] as Vector3) + normal * SKIN
	var into := velocity.dot(normal)
	var along := velocity - normal * into
	velocity = along * SLIDE - normal * into * BOUNCE
	angular_velocity *= SPIN_KEPT
	basis = basis.slerp(level(basis), LEVEL_ON_BOUNCE).orthonormalized()
	if normal.y >= FLOOR_NORMAL_Y and velocity.length() < REST_SPEED:
		position = hit["position"]
		_rest(t.now_usec)


## The same heading, level with the ground and upright: its muzzle (+Z)
## along the ground the way it pointed, or, pointing straight up or down,
## the way its top did.
static func level(from: Basis) -> Basis:
	var ahead := Vector3(from.z.x, 0.0, from.z.z)
	if ahead.length() < 0.2:
		ahead = Vector3(from.y.x, 0.0, from.y.z)
	if ahead.length() < 0.001:
		return Basis.IDENTITY
	return Basis.looking_at(-ahead.normalized(), Vector3.UP)


func _rest(now_usec: int) -> void:
	resting = true
	rested_usec = now_usec
	velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func save_state() -> Dictionary:
	var state := super()
	state["item"] = entry.item.item_class if entry != null else ""
	state["ammo"] = entry.weapon.ammo if entry != null and entry.weapon != null else 0
	state["reserve"] = entry.weapon.reserve if entry != null and entry.weapon != null else 0
	state["count"] = entry.count if entry != null else 0
	state["velocity"] = velocity
	state["basis"] = basis
	state["previous_basis"] = previous_basis
	state["angular_velocity"] = angular_velocity
	state["resting"] = resting
	state["rested_usec"] = rested_usec
	state["dropped_usec"] = dropped_usec
	state["next_pickup_check_usec"] = next_pickup_check_usec
	return state


func load_state(state: Dictionary) -> void:
	super(state)
	velocity = state.get("velocity", velocity)
	basis = state.get("basis", basis)
	previous_basis = state.get("previous_basis", previous_basis)
	angular_velocity = state.get("angular_velocity", angular_velocity)
	resting = state.get("resting", resting)
	rested_usec = state.get("rested_usec", rested_usec)
	dropped_usec = state.get("dropped_usec", dropped_usec)
	next_pickup_check_usec = state.get("next_pickup_check_usec", next_pickup_check_usec)
	var def := ItemRegistry.item(state.get("item", ""))
	if def == null:
		return
	var weapon: Weapon = null
	if def.is_gun:
		weapon = Weapon.new(ItemRegistry.weapon_data(def.item_class))
		weapon.ammo = state.get("ammo", weapon.ammo)
		weapon.reserve = state.get("reserve", weapon.reserve)
	entry = Inventory.Entry.new(def, weapon, state.get("count", 1))
