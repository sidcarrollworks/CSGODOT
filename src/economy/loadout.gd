class_name Loadout
extends RefCounted

## What the buy menu offers a side: five columns of five places, as CS2's
## loadout fills them.
##
## CS2 builds the menu from the player's loadout, and the default loadout is
## the game's own: each item's flexible_loadout_slot and
## flexible_loadout_default in items_game.txt (SteamDatabase's
## GameTracking-CS2, checked 2026-09-23; reference/systems/economy.md has the
## table). Choosing another loadout is a settings page for later; until then
## every player has the default. What each item costs, and who may buy it,
## is the item registry's (ItemRegistry).

## The columns, in the menu's order: CS2's loadout slots secondary0-4,
## smg0-4, rifle0-4, equipment0-3 and grenade0-4. A place holds one item per
## side, {"T": class, "CT": class}, "" for nothing.
const COLUMNS: Array[Dictionary] = [
	{"name": "Pistols", "items": [
		{"T": "weapon_glock", "CT": "weapon_hkp2000"},
		{"T": "weapon_elite", "CT": "weapon_elite"},
		{"T": "weapon_p250", "CT": "weapon_p250"},
		{"T": "weapon_tec9", "CT": "weapon_fiveseven"},
		{"T": "weapon_deagle", "CT": "weapon_deagle"},
	]},
	{"name": "Mid-Tier", "items": [
		{"T": "weapon_nova", "CT": "weapon_nova"},
		{"T": "weapon_xm1014", "CT": "weapon_xm1014"},
		{"T": "weapon_mp5sd", "CT": "weapon_mp5sd"},
		{"T": "weapon_p90", "CT": "weapon_p90"},
		{"T": "weapon_mac10", "CT": "weapon_mp9"},
	]},
	{"name": "Rifles", "items": [
		{"T": "weapon_galilar", "CT": "weapon_famas"},
		{"T": "weapon_ak47", "CT": "weapon_m4a1_silencer"},
		{"T": "weapon_ssg08", "CT": "weapon_ssg08"},
		{"T": "weapon_sg556", "CT": "weapon_aug"},
		{"T": "weapon_awp", "CT": "weapon_awp"},
	]},
	{"name": "Equipment", "items": [
		{"T": "item_kevlar", "CT": "item_kevlar"},
		{"T": "item_assaultsuit", "CT": "item_assaultsuit"},
		{"T": "weapon_taser", "CT": "weapon_taser"},
		{"T": "", "CT": "item_defuser"},
		{"T": "", "CT": ""},
	]},
	{"name": "Grenades", "items": [
		{"T": "weapon_flashbang", "CT": "weapon_flashbang"},
		{"T": "weapon_smokegrenade", "CT": "weapon_smokegrenade"},
		{"T": "weapon_hegrenade", "CT": "weapon_hegrenade"},
		{"T": "weapon_molotov", "CT": "weapon_incgrenade"},
		{"T": "weapon_decoy", "CT": "weapon_decoy"},
	]},
]

const PLACES := 5


## The item at a column and place of a side's menu, or "" where there is
## none.
static func item_at(side: String, column: int, place: int) -> String:
	if column < 0 or column >= COLUMNS.size() or place < 0 or place >= PLACES:
		return ""
	return String((COLUMNS[column]["items"][place] as Dictionary).get(side, ""))


## Where an item is in a side's menu, as one number (column * 5 + place), the
## way item_purchase's loadout key names it; -1 when it is not there.
static func index_of(side: String, item_class: String) -> int:
	for column in COLUMNS.size():
		for place in PLACES:
			if item_at(side, column, place) == item_class:
				return column * PLACES + place
	return -1


## Every item a side's menu shows, column by column.
static func items(side: String) -> Array[String]:
	var out: Array[String] = []
	for column in COLUMNS.size():
		for place in PLACES:
			var item := item_at(side, column, place)
			if not item.is_empty():
				out.append(item)
	return out
