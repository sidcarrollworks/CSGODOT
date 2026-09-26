class_name ItemRegistry
extends RefCounted

## Every item in the game, by CS2's class name.
##
## What the game's own files carry comes from them: each weapon's price,
## kill award, slot, type, weight, draw time and speed from weapons.vdata
## (reference/weapons/vdata.csv, through WeaponVData), and each gun's name,
## model and clips from what the extraction lists (reference/weapons/
## models.md, through WeaponLibrary). What they do not carry is written here,
## from reference/cs2-systems.md: which side may buy what, how many
## grenades of a kind, and kevlar, the suit and the kit, which are not
## weapons.
##
## Read once, before play (nothing reads the disk during a tick), and handed
## out as the same ItemDef each time: an ItemDef is never changed after it
## is read.

## The items only one side may buy (cs2-systems.md, Buying). The C4 is the
## Ts' too, though nobody buys it.
const T_ONLY := [
	"weapon_glock", "weapon_tec9", "weapon_mac10", "weapon_sawedoff", "weapon_galilar",
	"weapon_ak47", "weapon_sg556", "weapon_g3sg1", "weapon_molotov", "weapon_c4",
]
const CT_ONLY := [
	"weapon_hkp2000", "weapon_usp_silencer", "weapon_fiveseven", "weapon_mp9", "weapon_mag7",
	"weapon_famas", "weapon_m4a1", "weapon_m4a1_silencer", "weapon_aug", "weapon_scar20",
	"weapon_incgrenade", "item_defuser",
]

## The rest of the equipment, in the order the buy menu lists it, with CS2's
## English names. Kevlar, the suit and the kit are not in weapons.vdata; their
## prices are CS2's (cs2-systems.md).
const EQUIPMENT_NAMES := {
	"weapon_knife": "Knife",
	"weapon_taser": "Zeus x27",
	"weapon_flashbang": "Flashbang",
	"weapon_smokegrenade": "Smoke Grenade",
	"weapon_hegrenade": "High Explosive Grenade",
	"weapon_molotov": "Molotov",
	"weapon_incgrenade": "Incendiary Grenade",
	"weapon_decoy": "Decoy Grenade",
	"weapon_c4": "C4 Explosive",
}
const WORN := {
	"item_kevlar": {"name": "Kevlar Vest", "price": 650},
	"item_assaultsuit": {"name": "Kevlar & Helmet", "price": 1000},
	"item_defuser": {"name": "Defuse Kit", "price": 400},
}

## How many of a grenade one player carries at most; one of anything not
## listed. Four grenades in all (Inventory.MOST_GRENADES).
const GRENADE_LIMITS := {"weapon_flashbang": 2}
const FIREBOMBS := ["weapon_molotov", "weapon_incgrenade"]

const SLOTS := {
	"GEAR_SLOT_RIFLE": ItemDef.Slot.PRIMARY,
	"GEAR_SLOT_PISTOL": ItemDef.Slot.PISTOL,
	"GEAR_SLOT_KNIFE": ItemDef.Slot.KNIFE,
	"GEAR_SLOT_GRENADES": ItemDef.Slot.GRENADE,
	"GEAR_SLOT_C4": ItemDef.Slot.C4,
}
const TYPES := {
	"WEAPONTYPE_PISTOL": "pistol",
	"WEAPONTYPE_SUBMACHINEGUN": "smg",
	"WEAPONTYPE_RIFLE": "rifle",
	"WEAPONTYPE_SHOTGUN": "shotgun",
	"WEAPONTYPE_SNIPER_RIFLE": "sniper",
	"WEAPONTYPE_MACHINEGUN": "machinegun",
	"WEAPONTYPE_KNIFE": "knife",
	"WEAPONTYPE_TASER": "taser",
	"WEAPONTYPE_GRENADE": "grenade",
	"WEAPONTYPE_C4": "c4",
}

static var _items := {}
static var _order: Array[ItemDef] = []
static var _weapon_data := {}


## The item called item_class, or null.
static func item(item_class: String) -> ItemDef:
	_load_once()
	return _items.get(item_class)


static func has(item_class: String) -> bool:
	_load_once()
	return _items.has(item_class)


## Every item: the guns in the order the game lists them, then the knife,
## the Zeus, the grenades, the C4, and what is worn. A copy.
static func all() -> Array[ItemDef]:
	_load_once()
	return _order.duplicate()


## The 34 guns.
static func guns() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for def in all():
		if def.is_gun:
			out.append(def)
	return out


## What a side may buy: everything buyable that is for both sides or that one.
static func buyable(team: String) -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for def in all():
		if def.buyable and (def.team.is_empty() or def.team == team):
			out.append(def)
	return out


## A gun's WeaponData (WeaponLibrary.build), a copy of its own, its scoped
## numbers and arrays included, or null for anything else. Every gun's is
## built by load_all(), so none is read from disk in a tick, and its recoil
## solved then: a copy carries the answers, where working them out took
## about 20 ms on the first tick each new gun was held.
static func weapon_data(item_class: String) -> WeaponData:
	var def := item(item_class)
	if def == null or not def.is_gun:
		return null
	if not _weapon_data.has(item_class):
		var built := WeaponLibrary.build(item_class)
		if built != null:
			built.model_hold_time()
			built.view_kick_up()
		_weapon_data[item_class] = built
	var cached := _weapon_data[item_class] as WeaponData
	return cached.duplicate(true) as WeaponData if cached != null else null


## Reads everything the registry hands out, each gun's WeaponData included:
## once, before play, by whatever sets the game up (GameSystems does).
static func load_all() -> void:
	_load_once()
	for def in _order:
		if def.is_gun:
			weapon_data(def.item_class)


static func _load_once() -> void:
	if not _order.is_empty():
		return
	for weapon_class in WeaponLibrary.classes():
		_add(_from_vdata(weapon_class, WeaponLibrary.display_name(weapon_class), true))
	for weapon_class in EQUIPMENT_NAMES:
		_add(_from_vdata(weapon_class, EQUIPMENT_NAMES[weapon_class], false))
	for item_class in WORN:
		var def := ItemDef.new()
		def.item_class = item_class
		def.name = WORN[item_class]["name"]
		def.price = WORN[item_class]["price"]
		def.type = "equipment"
		def.slot = ItemDef.Slot.EQUIPMENT
		def.team = _team_of(item_class)
		def.droppable = item_class == "item_defuser"
		_add(def)


static func _add(def: ItemDef) -> void:
	if def == null:
		return
	def.order = _order.size()
	_items[def.item_class] = def
	_order.append(def)


static func _from_vdata(weapon_class: String, display: String, gun: bool) -> ItemDef:
	if not WeaponVData.has(weapon_class):
		push_error("No %s in weapons.vdata (%s)" % [weapon_class, WeaponVData.PATH])
		return null
	var fields: Dictionary = WeaponVData.classes()[weapon_class]
	var def := ItemDef.new()
	def.item_class = weapon_class
	def.name = display
	def.slot = SLOTS.get(fields.get("m_GearSlot", ""), ItemDef.Slot.EQUIPMENT)
	def.type = TYPES.get(fields.get("m_WeaponType", ""), "")
	def.is_gun = gun
	var number := func(field: String, fallback: float) -> float:
		var value := WeaponVData.number(weapon_class, field)
		return fallback if is_nan(value) else value
	def.slot_position = int(number.call("m_GearSlotPosition", 0.0))
	def.price = int(number.call("m_nPrice", 0.0))
	def.kill_award = int(number.call("m_nKillAward", 0.0))
	def.weight = int(number.call("m_iWeight", 0.0))
	def.deploy_seconds = number.call("m_flDeployDuration", 0.0)
	def.max_speed = number.call("m_flMaxSpeed", 250.0)
	def.team = _team_of(weapon_class)
	def.max_carried = GRENADE_LIMITS.get(weapon_class, 1)
	def.grenade_group = "firebomb" if weapon_class in FIREBOMBS else ""
	def.silenced_by_default = weapon_class in ["weapon_m4a1_silencer", "weapon_usp_silencer"]
	def.buyable = def.slot != ItemDef.Slot.KNIFE or def.type == "taser"
	def.buyable = def.buyable and def.slot != ItemDef.Slot.C4
	def.droppable = def.type != "knife"
	return def


static func _team_of(item_class: String) -> String:
	if item_class in T_ONLY:
		return "T"
	if item_class in CT_ONLY:
		return "CT"
	return ""
