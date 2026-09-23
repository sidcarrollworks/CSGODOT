class_name DroppedItem
extends SimEntity

## An item lying in the world, or falling to it: a gun with its ammo (its
## own Weapon, from the Inventory.Entry that was carried), a grenade, the
## Zeus, the kit. Its entity class is the item's (weapon_ak47, item_defuser).
## The C4 on the ground is the bomb's own entity, not one of these.
##
## It falls under gravity until it meets the world, then lies there until a
## player picks it up (ItemDrops) or a round's start clears the map. A fall
## is one trace a tick while it moves, none once it lies still.

## sv_gravity, as MovementConfig has it.
const GRAVITY := 800.0
## Who dropped it cannot take it straight back: a gun thrown forward would
## otherwise be picked up again as it leaves the hand. How long is a guess.
const OWNER_PICKUP_DELAY_USEC := 1_000_000

var entry: Inventory.Entry
var velocity := Vector3.ZERO
var resting: bool = false
## Simulation time it was dropped at.
var dropped_usec: int = 0


func _init(p_entry: Inventory.Entry = null, p_owner_id: int = GameEvents.NOBODY, p_position := Vector3.ZERO, p_velocity := Vector3.ZERO) -> void:
	super(p_entry.item.item_class if p_entry != null else "", p_owner_id, p_position)
	entry = p_entry
	velocity = p_velocity


## Puts entry on the ground from where the player userid is: thrown along
## velocity from their middle, as a drop or a death leaves it. The entity,
## already spawned into game.entities.
static func drop(game: GameSystems, userid: int, p_entry: Inventory.Entry, p_velocity := Vector3.ZERO) -> DroppedItem:
	var node := game.roster.player(userid)
	var from := node.global_position + Vector3.UP * 36.0 if node != null else Vector3.ZERO
	var item := DroppedItem.new(p_entry, userid, from, p_velocity)
	item.dropped_usec = game.now_usec()
	game.entities.spawn(item)
	return item


## Whether userid may pick it up at now_usec.
func can_be_taken_by(userid: int, now_usec: int) -> bool:
	return userid != owner_id or now_usec >= dropped_usec + OWNER_PICKUP_DELAY_USEC


func tick(t: SimTick) -> void:
	if resting:
		return
	velocity.y -= GRAVITY * t.dt
	var to := position + velocity * t.dt
	if t.space == null:
		# No world to fall onto: it stays where it was dropped.
		resting = true
		velocity = Vector3.ZERO
		return
	var query := PhysicsRayQueryParameters3D.create(position, to, Hitscan.WORLD_LAYER)
	var hit := t.space.intersect_ray(query)
	if hit.is_empty():
		position = to
		return
	position = hit["position"]
	velocity = Vector3.ZERO
	resting = true


func save_state() -> Dictionary:
	var state := super()
	state["item"] = entry.item.item_class if entry != null else ""
	state["ammo"] = entry.weapon.ammo if entry != null and entry.weapon != null else 0
	state["reserve"] = entry.weapon.reserve if entry != null and entry.weapon != null else 0
	state["count"] = entry.count if entry != null else 0
	state["velocity"] = velocity
	state["resting"] = resting
	state["dropped_usec"] = dropped_usec
	return state


func load_state(state: Dictionary) -> void:
	super(state)
	velocity = state.get("velocity", velocity)
	resting = state.get("resting", resting)
	dropped_usec = state.get("dropped_usec", dropped_usec)
	var def := ItemRegistry.item(state.get("item", ""))
	if def == null:
		return
	var weapon: Weapon = null
	if def.is_gun:
		weapon = Weapon.new(ItemRegistry.weapon_data(def.item_class))
		weapon.ammo = state.get("ammo", weapon.ammo)
		weapon.reserve = state.get("reserve", weapon.reserve)
	entry = Inventory.Entry.new(def, weapon, state.get("count", 1))
