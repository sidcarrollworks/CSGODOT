class_name Inventory
extends RefCounted

## What one player carries, what is in their hand, their armour and their
## kit: CS2's weapon and item services for one player.
##
## It holds CS2's carrying rules and nothing else. Whether they can afford
## it, are in their buy zone or on the right side is buying's to check
## before calling add; what falls to the ground is whoever drops it's to
## make into a dropped item. Nothing here sends events: the system that
## caused the change does (item_purchase, item_pickup, grenade_thrown,
## bomb_dropped).
##
## Each gun carried is its own Weapon, so its ammo and recoil stay with it
## through a switch, a drop and a pick-up.
##
## Armour and the kit live on the player, as CS2 keeps them on the pawn: the
## armour points and the helmet on the player's HitTarget, which damage
## wears down. This is the one way to read and change them; given no
## HitTarget (a test), it keeps them itself.

## What can_add finds.
enum Can {
	## There is room for it.
	OK,
	## Its slot is taken by another gun, which add hands back, to be
	## dropped.
	REPLACES,
	## No room: the grenade limits, one already carried, armour already
	## full, a kit already worn.
	FULL,
	## No such item.
	UNKNOWN,
}

## Four grenades in all (CS2's ammo_grenade_limit_total).
const MOST_GRENADES := 4
## Which grenade falls when a player dies with none in hand: the best first.
## CS2 drops the one in hand, or else its best; which it counts as best is
## a guess.
const GRENADE_DROP_ORDER := [
	"weapon_molotov", "weapon_incgrenade", "weapon_hegrenade", "weapon_smokegrenade",
	"weapon_flashbang", "weapon_decoy",
]
## Each side's pistol at the start of a half: CS2's default loadout (the
## P2000 is the CTs' other choice, once there is a loadout to choose it in).
const STARTING_PISTOLS := {"T": "weapon_glock", "CT": "weapon_usp_silencer"}
const FULL_ARMOR := 100.0


## One thing carried.
class Entry:
	var item: ItemDef
	## A gun's own Weapon; null for anything else.
	var weapon: Weapon
	## How many: grenades stack, anything else is one.
	var count: int = 1

	func _init(p_item: ItemDef, p_weapon: Weapon = null, p_count: int = 1) -> void:
		item = p_item
		weapon = p_weapon
		count = p_count

	func item_class() -> String:
		return item.item_class


## Whose it is, by userid.
var userid: int = GameEvents.NOBODY
## The player's HitTarget, which holds their armour; null in a test.
var body: HitTarget
var has_defuser: bool = false

## Armour points, 0 to 100.
var armor: float:
	get: return body.armor if body != null else _armor
	set(value):
		if body != null:
			body.armor = value
		else:
			_armor = value

var helmet: bool:
	get: return body.helmet if body != null else _helmet
	set(value):
		if body != null:
			body.helmet = value
		else:
			_helmet = value

var _entries: Array[Entry] = []
var _active: String = ""
var _previous: String = ""
var _armor: float = 0.0
var _helmet: bool = false


func _init(p_userid: int = GameEvents.NOBODY, p_body: HitTarget = null) -> void:
	userid = p_userid
	body = p_body


# --- Reading --------------------------------------------------------------

## Every entry, in slot order: primary, pistol, knife and Zeus, grenades, C4.
## A copy.
func entries() -> Array[Entry]:
	return _entries.duplicate()


## Whether they carry or wear it: kevlar is any armour, the suit armour and
## a helmet.
func has(item_class: String) -> bool:
	match item_class:
		"item_kevlar":
			return armor > 0.0
		"item_assaultsuit":
			return armor > 0.0 and helmet
		"item_defuser":
			return has_defuser
	return _find(item_class) != null


## How many they carry: a grenade's count, 1 or 0 for anything else.
func count(item_class: String) -> int:
	if item_class.begins_with("item_"):
		return 1 if has(item_class) else 0
	var entry := _find(item_class)
	return entry.count if entry != null else 0


## The entry in a slot, or null; position picks the Zeus (1) from the knife
## (0) in theirs. The first grenade for the grenades' slot.
func item_in(slot: ItemDef.Slot, position: int = -1) -> Entry:
	for entry in _entries:
		if entry.item.slot == slot and (position < 0 or entry.item.slot_position == position):
			return entry
	return null


## Every entry in a slot: the grenades, or the knife and the Zeus.
func items_in(slot: ItemDef.Slot) -> Array[Entry]:
	var out: Array[Entry] = []
	for entry in _entries:
		if entry.item.slot == slot:
			out.append(entry)
	return out


## Grenades carried, of every kind.
func grenade_count() -> int:
	var total := 0
	for entry in items_in(ItemDef.Slot.GRENADE):
		total += entry.count
	return total


## The entry in hand, or null with nothing in it.
func in_hand() -> Entry:
	return _find(_active)


func in_hand_class() -> String:
	return _active


## The gun a death drops and a player is handed back to: the primary, or
## else the pistol. Null without either.
func best_gun() -> Entry:
	var primary := item_in(ItemDef.Slot.PRIMARY)
	return primary if primary != null else item_in(ItemDef.Slot.PISTOL)


# --- Changing -------------------------------------------------------------

## Whether add would take it, and whether it would hand something back.
func can_add(item_class: String) -> Can:
	var def := ItemRegistry.item(item_class)
	if def == null:
		return Can.UNKNOWN
	match item_class:
		"item_kevlar":
			return Can.FULL if armor >= FULL_ARMOR else Can.OK
		"item_assaultsuit":
			return Can.FULL if armor >= FULL_ARMOR and helmet else Can.OK
		"item_defuser":
			return Can.FULL if has_defuser else Can.OK
	if def.is_grenade():
		if count(item_class) >= def.max_carried or grenade_count() >= MOST_GRENADES:
			return Can.FULL
		if not def.grenade_group.is_empty():
			for entry in items_in(ItemDef.Slot.GRENADE):
				if entry.item.grenade_group == def.grenade_group and entry.item != def:
					return Can.FULL
		return Can.OK
	var there := item_in(def.slot, def.slot_position)
	if there == null:
		return Can.OK
	if there.item == def:
		# One of each: CS2 will not sell a gun its buyer already carries.
		return Can.FULL
	if def.slot == ItemDef.Slot.PRIMARY or def.slot == ItemDef.Slot.PISTOL:
		return Can.REPLACES
	return Can.FULL


## Adds it, if can_add allows, and hands back what it replaced (a primary
## or pistol already carried) for the caller to drop; empty when nothing
## was replaced, and when it was refused (check can_add first). A picked-up
## gun comes with its own Weapon, keeping its ammo; a new one comes loaded.
## Kevlar fills the armour to 100, the suit does and adds the helmet, and
## the kit is worn. With nothing in hand, it goes in hand; replacing what
## is in hand, it takes its place.
func add(item_class: String, weapon: Weapon = null) -> Array[Entry]:
	var replaced: Array[Entry] = []
	var can := can_add(item_class)
	if can == Can.FULL or can == Can.UNKNOWN:
		return replaced
	var def := ItemRegistry.item(item_class)
	match item_class:
		"item_kevlar":
			armor = FULL_ARMOR
			return replaced
		"item_assaultsuit":
			armor = FULL_ARMOR
			helmet = true
			return replaced
		"item_defuser":
			has_defuser = true
			return replaced

	var took_hand := false
	if can == Can.REPLACES:
		var there := item_in(def.slot, def.slot_position)
		took_hand = there.item.item_class == _active
		_entries.erase(there)
		replaced.append(there)

	var existing := _find(item_class)
	if existing != null:
		existing.count += 1
	else:
		if weapon == null and def.is_gun:
			weapon = Weapon.new(ItemRegistry.weapon_data(item_class))
		_insert(Entry.new(def, weapon))
	if _active.is_empty() or took_hand:
		_active = item_class
	return replaced


## Takes one of it out and hands it back: the gun with its Weapon, one
## grenade, the C4. The kit and armour come off (undoing a purchase: whoever
## undoes it puts back what was there before). Null if they have none.
## If it was in hand, the hand goes to what was held before it, or else to
## the best there is.
func remove(item_class: String) -> Entry:
	var def := ItemRegistry.item(item_class)
	match item_class:
		"item_defuser":
			if not has_defuser:
				return null
			has_defuser = false
			return Entry.new(def)
		"item_kevlar", "item_assaultsuit":
			if not has(item_class):
				return null
			armor = 0.0
			if item_class == "item_assaultsuit":
				helmet = false
			return Entry.new(def)
	var entry := _find(item_class)
	if entry == null:
		return null
	if entry.count > 1:
		entry.count -= 1
		return Entry.new(entry.item, null, 1)
	_entries.erase(entry)
	if _active == item_class:
		_hand_emptied()
	if _previous == item_class:
		_previous = ""
	return entry


## One grenade thrown: one fewer, gone at none. False if they had none.
func take_one(item_class: String) -> bool:
	return remove(item_class) != null


## Puts it in hand. False if they do not carry it.
func select(item_class: String) -> bool:
	if _find(item_class) == null:
		return false
	if item_class != _active:
		_previous = _active
		_active = item_class
	return true


## The number keys: the first thing in that slot, or, pressed again on the
## grenades or the knife's slot, the next thing in it (CS2 cycles 4 through
## the grenades). False with nothing there.
func select_slot(slot: ItemDef.Slot) -> bool:
	var there := items_in(slot)
	if there.is_empty():
		return false
	var at := -1
	for i in there.size():
		if there[i].item.item_class == _active:
			at = i
	return select(there[(at + 1) % there.size()].item.item_class)


## Q: back to what was in hand before. False if that is gone.
func select_last() -> bool:
	if _previous.is_empty():
		return false
	return select(_previous)


## Takes out and hands back what a death leaves on the ground, as CS2 does
## (mp_death_drop_gun, _grenade, _taser, _defuser): the best gun, the grenade
## in hand or else the best one, the Zeus and the kit. Not the C4, which the
## bomb takes and drops itself when its carrier dies (mp_death_drop_c4). The
## rest goes with strip(), when the player next spawns.
func drops_on_death() -> Array[Entry]:
	var out: Array[Entry] = []
	var gun := best_gun()
	if gun != null:
		out.append(remove(gun.item.item_class))
	var grenade := ""
	var held := in_hand()
	if held != null and held.item.is_grenade():
		grenade = held.item.item_class
	else:
		for item_class in GRENADE_DROP_ORDER:
			if has(item_class):
				grenade = item_class
				break
	if not grenade.is_empty():
		out.append(remove(grenade))
	for item_class in ["weapon_taser", "item_defuser"]:
		if has(item_class):
			out.append(remove(item_class))
	return out


## Everything gone, armour and kit too: a death, or a new match.
func strip() -> void:
	_entries.clear()
	_active = ""
	_previous = ""
	has_defuser = false
	armor = 0.0
	helmet = false


## What a player on side team starts a half with: the knife and the side's
## pistol, with the pistol in hand. Adds only what is missing.
func give_starting_items(team: String) -> void:
	add("weapon_knife")
	if item_in(ItemDef.Slot.PISTOL) == null and STARTING_PISTOLS.has(team):
		add(STARTING_PISTOLS[team])
	var best := best_gun()
	if best != null:
		select(best.item.item_class)


## What it holds, as plain data: each entry's class, count and ammo, what is
## in hand and was before, armour, helmet and kit. A gun's recoil and timers
## are not kept.
func save_state() -> Dictionary:
	var carried := []
	for entry in _entries:
		carried.append({
			"class": entry.item.item_class,
			"count": entry.count,
			"ammo": entry.weapon.ammo if entry.weapon != null else 0,
			"reserve": entry.weapon.reserve if entry.weapon != null else 0,
		})
	return {
		"entries": carried, "active": _active, "previous": _previous,
		"defuser": has_defuser, "armor": armor, "helmet": helmet,
	}


func load_state(state: Dictionary) -> void:
	_entries.clear()
	for saved in state.get("entries", []):
		var def := ItemRegistry.item(saved["class"])
		if def == null:
			continue
		var weapon: Weapon = null
		if def.is_gun:
			weapon = Weapon.new(ItemRegistry.weapon_data(def.item_class))
			weapon.ammo = saved["ammo"]
			weapon.reserve = saved["reserve"]
		_insert(Entry.new(def, weapon, saved["count"]))
	_active = state.get("active", "")
	_previous = state.get("previous", "")
	has_defuser = state.get("defuser", false)
	armor = state.get("armor", 0.0)
	helmet = state.get("helmet", false)


func _find(item_class: String) -> Entry:
	if item_class.is_empty():
		return null
	for entry in _entries:
		if entry.item.item_class == item_class:
			return entry
	return null


## Keeps the entries in slot order, and within a slot in the order CS2
## places them, so what is saved and what a slot key picks never depend on
## the order things were bought in.
func _insert(entry: Entry) -> void:
	var rank := func(e: Entry) -> Array:
		return [e.item.slot, e.item.slot_position, e.item.order]
	var key: Array = rank.call(entry)
	for i in _entries.size():
		var other: Array = rank.call(_entries[i])
		if key < other:
			_entries.insert(i, entry)
			return
	_entries.append(entry)


func _hand_emptied() -> void:
	_active = ""
	if not _previous.is_empty() and _find(_previous) != null:
		_active = _previous
		_previous = ""
		return
	var gun := best_gun()
	if gun != null:
		_active = gun.item.item_class
	elif not _entries.is_empty():
		_active = _entries[0].item.item_class
