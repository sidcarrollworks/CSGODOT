class_name BotBuying
extends RefCounted

## What a bot buys in freeze time, as CS2's classic bot does: nothing below
## bot_eco_limit; otherwise a primary by its profile's weapon preference, the
## first its side may buy and it can afford, then armour, a kit for a
## counter-terrorist, and a third of the time one grenade with what is left,
## an HE six times as likely as each other kind.
##
## Every number is CS2's convars and botprofile.db, as
## reference/research/round-hud-bots.md B gives them; the choices where CS2
## is silent are marked. It is pure: it reads its arguments and the item
## tables and keeps nothing. The bot carries the plan out as buy commands
## through the game (Bot), so the economy refuses and prices each as it
## does a player's: whatever the money no longer covers is refused, which is
## CS2's "with the leftover money".

## bot_eco_limit: a bot with less saves, buying nothing.
const ECO_LIMIT := 2000
## sv_bot_buy_grenade_chance, per cent: a grenade with the leftover money.
const GRENADE_CHANCE := 33
## sv_bot_buy_hegrenade_weight and the flash, smoke, molotov and decoy
## weights; "molotov" is the incendiary for a counter-terrorist (the side's
## fire grenade; that CS2 reads it so is inferred).
const GRENADE_WEIGHTS := [
	["weapon_hegrenade", 6], ["weapon_flashbang", 1], ["weapon_smokegrenade", 1],
	["molotov", 1], ["weapon_decoy", 1],
]
## botprofile.db's weapon templates: the guns each tries to buy, in order,
## in CS2's short names.
const TEMPLATES := {
	&"Rifle": ["m4a1", "ak47", "famas", "galilar", "mp7"],
	&"RifleT": ["ak47", "m4a1", "galilar", "famas", "mp7"],
	&"Punch": ["aug", "sg556", "famas", "galilar", "mp7"],
	&"PunchT": ["aug", "sg556", "famas", "galilar", "mp7"],
	&"Sniper": ["awp", "scar20", "g3sg1", "ssg08", "famas", "galilar", "mp7"],
	&"Power": ["m249", "xm1014", "nova", "famas", "galilar", "mp7"],
	&"Shotgun": ["xm1014", "nova", "famas", "galilar", "mp7"],
	&"Spray": ["p90", "mp9", "mac10", "mp7"],
	## No preference (81 of the 147 profiles): what CS2 buys for them is not
	## known. A stand-in: the guns of CS2's own autobuy.txt, in its order.
	&"None": ["m4a1", "ak47", "famas", "galilar", "mp7", "nova"],
}
## How many of botprofile.db's 147 profiles use each template.
const TEMPLATE_WEIGHTS := [
	[&"Rifle", 25], [&"RifleT", 12], [&"Sniper", 8], [&"PunchT", 6], [&"Spray", 5],
	[&"Punch", 4], [&"Shotgun", 4], [&"Power", 2], [&"None", 81],
]
## Guns that share a place in the loadout: a bot buys the one its side's
## loadout holds, as CS2's autobuy.txt buys "the weapon currently equipped
## in that slot". The pairs are from memory (items_game.txt's
## flexible_loadout_slot settles them).
const SHARES_A_PLACE := {
	"weapon_m4a1": "weapon_m4a1_silencer", "weapon_m4a1_silencer": "weapon_m4a1",
	"weapon_mp7": "weapon_mp5sd", "weapon_mp5sd": "weapon_mp7",
}


## The template a bot buys by, the same for the whole match: a pick
## weighted as botprofile.db's profiles use them, from the bot's name.
static func template_for(key: String) -> StringName:
	var total := 0
	for pair: Array in TEMPLATE_WEIGHTS:
		total += int(pair[1])
	var roll := posmod(hash(["bot_profile", key]), total)
	for pair: Array in TEMPLATE_WEIGHTS:
		roll -= int(pair[1])
		if roll < 0:
			return pair[0]
	return &"None"


## The class a side would buy for a template's entry, or "" to skip it: a
## gun only the other side may buy, or one the side's loadout does not hold
## (neither it nor the gun sharing its place), which a player could not buy
## from the menu either.
static func resolve(side: String, short: String) -> String:
	var item_class := Economy.item_named(short)
	if item_class.is_empty():
		return ""
	var item := ItemRegistry.item(item_class)
	if item == null or not (item.team.is_empty() or item.team == side):
		return ""
	var offered := Loadout.items(side)
	if item_class in offered:
		return item_class
	var sharing: String = SHARES_A_PLACE.get(item_class, "")
	if not sharing.is_empty() and sharing in offered:
		return sharing
	return ""


## What to buy, in the order to ask for it. Both dice are thrown first, so
## the plan's randomness never depends on the money.
static func plan(side: String, money: int, carried: Inventory, template: StringName, rng: RandomNumberGenerator) -> PackedStringArray:
	var out := PackedStringArray()
	var grenade_roll := rng.randi_range(0, 99)
	var grenade_pick := rng.randi_range(0, _grenade_weight_total() - 1)
	if money < ECO_LIMIT:
		return out
	# A primary, unless one is carried: the first on its list the side may
	# buy and it can afford.
	if carried == null or carried.item_in(ItemDef.Slot.PRIMARY) == null:
		for short: String in TEMPLATES.get(template, TEMPLATES[&"None"]):
			var item_class := resolve(side, short)
			if not item_class.is_empty() and ItemRegistry.item(item_class).price <= money:
				out.append(item_class)
				break
	# No pistol: CS2's secondary step exists ("after prim, sec and armor"),
	# but which pistol a bot buys is in no file; it keeps its own.
	# Armour, the best it can afford: the suit, else the vest (a choice; CS2
	# says only "armor"). The economy refuses the vest once the suit is on.
	out.append("item_assaultsuit")
	out.append("item_kevlar")
	# A kit for a counter-terrorist who can still afford it (from memory).
	if side == "CT":
		out.append("item_defuser")
	if grenade_roll < GRENADE_CHANCE:
		out.append(_grenade(side, grenade_pick))
	return out


static func _grenade_weight_total() -> int:
	var total := 0
	for pair: Array in GRENADE_WEIGHTS:
		total += int(pair[1])
	return total


static func _grenade(side: String, pick: int) -> String:
	for pair: Array in GRENADE_WEIGHTS:
		pick -= int(pair[1])
		if pick < 0:
			if pair[0] == "molotov":
				return "weapon_incgrenade" if side == "CT" else "weapon_molotov"
			return pair[0]
	return "weapon_hegrenade"
