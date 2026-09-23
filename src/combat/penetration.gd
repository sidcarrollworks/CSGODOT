class_name Penetration
extends RefCounted

## What a wall does to a round that goes through it: how much of the
## round's penetration power it uses up, and how much of its damage it
## takes, by what the wall is made of and how thick it is.
##
## The surfaces are CS2's own. Each one's two numbers are copied from the
## game's scripts/surfaceproperties_game.txt, as SteamDatabase's
## GameTracking-CS2 publishes it (game/csgo/pak01_dir/scripts/, checked
## 2026-09-23): bulletPenetrationDistanceModifier, how far a round gets
## through it (wood 0.9 goes a long way, sand 0.3 does not), and
## bulletPenetrationDamageModifier, how much damage it lets a round keep
## (concrete 0.25 keeps little, chain-link 0.99 almost all).
##
## How those numbers turn into a thickness and a damage is this project's
## own, not CS2's, which Valve has not published: a round with power P gets
## through P x REACH_PER_POWER units of a surface whose distance modifier is
## 1, scaled down by the surface's modifier, and loses a fixed share at every
## wall plus a share that grows with the thickness. REACH_PER_POWER,
## FLAT_LOSS, DAMAGE_DEPTH and MOST_WALLS are estimates, to be set from
## CS2 itself: with sv_showimpacts_penetration 1 the game draws each wall a
## round went through and what it did (roadmap item 7a).

## Units of a distance-modifier-1 surface one point of penetration power
## gets through. A rifle (power 2) through concrete (0.5): 12 units; through
## wood (0.9): about 22; an SMG (power 1) half that. ESTIMATE.
const REACH_PER_POWER := 12.0
## The share of its damage a round loses at every wall however thin.
## ESTIMATE.
const FLAT_LOSS := 0.1
## The thickness, in units per point of the weapon's power, over which a
## surface takes its damage modifier's share: a rifle through 8 units of
## concrete keeps 0.25 of what the flat loss leaves it. ESTIMATE.
const DAMAGE_DEPTH := 4.0
## The most walls one round goes through. ESTIMATE.
const MOST_WALLS := 4
## Below this much damage a round is spent.
const SPENT_BELOW := 1.0

## CS2's surfaces by lower-case name: the name as the game spells it, then
## its distance and damage modifiers, null where the game's file leaves one
## out (it inherits it; see PARENTS).
const SURFACES := {
	"default": ["default", 0.5, 0.5],
	"solidmetal": ["solidmetal", 0.27, 0.3],
	"metal": ["metal", 0.4, null],
	"metaldogtags": ["metaldogtags", 0.4, null],
	"metalgrate": ["metalgrate", 0.95, 0.99],
	"metal_box": ["Metal_Box", 0.5, null],
	"metalvent": ["metalvent", 0.6, 0.45],
	"metalpanel": ["metalpanel", 0.5, 0.45],
	"dirt": ["dirt", 0.6, 0.3],
	"mud": ["mud", null, null],
	"slipperyslime": ["slipperyslime", null, null],
	"grass": ["grass", null, null],
	"slowgrass": ["slowgrass", null, null],
	"sugarcane": ["sugarcane", null, null],
	"tile": ["tile", 0.7, 0.3],
	"wood": ["Wood", 0.9, 0.6],
	"wood_box": ["Wood_Box", 0.9, null],
	"wood_basket": ["Wood_Basket", 0.9, null],
	"wood_crate": ["Wood_Crate", 0.9, null],
	"wood_plank": ["Wood_Plank", 0.85, null],
	"wood_solid": ["Wood_Solid", 0.8, null],
	"wood_dense": ["Wood_Dense", 0.5, 0.3],
	"water": ["water", 0.3, null],
	"wet": ["wet", null, null],
	"puddle": ["puddle", null, null],
	"slime": ["slime", null, null],
	"quicksand": ["quicksand", 0.2, null],
	"wade": ["wade", null, null],
	"ladder": ["ladder", null, null],
	"wood_ladder": ["Wood_Ladder", 0.9, null],
	"glass": ["glass", 0.99, null],
	"glassfloor": ["glassfloor", 0.99, null],
	"computer": ["computer", 0.4, 0.45],
	"weapon_magazine": ["weapon_magazine", null, null],
	"concrete": ["concrete", 0.5, 0.25],
	"asphalt": ["asphalt", 0.55, 0.3],
	"rock": ["rock", null, 0.25],
	"porcelain": ["porcelain", 0.95, null],
	"brick": ["brick", 0.47, 0.3],
	"stucco": ["stucco", null, null],
	"chainlink": ["chainlink", 0.99, 0.99],
	"chain": ["chain", null, null],
	"flesh": ["flesh", 0.9, null],
	"bloodyflesh": ["bloodyflesh", null, null],
	"alienflesh": ["alienflesh", null, null],
	"armorflesh": ["armorflesh", 0.5, 0.3],
	"ice": ["ice", 0.75, null],
	"carpet": ["carpet", 0.75, null],
	"upholstery": ["upholstery", 0.75, null],
	"plaster": ["plaster", 0.7, 0.6],
	"sheetrock": ["sheetrock", 0.85, 0.6],
	"cardboard": ["cardboard", 0.95, 0.99],
	"plastic_barrel": ["plastic_barrel", 0.7, null],
	"plastic_box": ["Plastic_Box", 0.75, null],
	"sand": ["sand", 0.3, 0.25],
	"rubber": ["rubber", 0.85, 0.5],
	"glassbottle": ["glassbottle", 0.99, 0.0],
	"pottery": ["pottery", 0.95, 0.6],
	"clay": ["clay", 0.95, 0.6],
	"metal_barrel": ["metal_barrel", 0.01, 0.01],
	"foliage": ["foliage", 0.95, null],
	"slipperyslide": ["slipperyslide", null, null],
	"watermelon": ["watermelon", 0.95, 0.6],
	"metal_shield": ["metal_shield", null, null],
	"default_silent": ["default_silent", null, null],
	"player_control_clip": ["player_control_clip", null, 1.0],
	"no_decal": ["no_decal", null, null],
	"soccerball": ["soccerball", null, null],
	"gravel": ["gravel", 0.4, null],
	"snow": ["snow", 0.85, null],
	"metalvehicle": ["metalvehicle", 0.5, null],
	"metal_sand_barrel": ["metal_sand_barrel", 0.01, 0.01],
	"blockbullets": ["blockbullets", 0.01, 0.001],
	"potterylarge": ["potterylarge", 0.95, 0.6],
	"fruit": ["fruit", 0.9, null],
	"audioblocker": ["audioblocker", null, null],
	"metalrailing": ["metalrailing", null, null],
	"plastic_solid": ["plastic_solid", 0.0, null],
}

## Where a surface takes a number the game's file leaves out. The file only
## gives what differs from a surface's parent, and the parents are set in
## CS2's surfaceproperties.vsurf, which is not in the public dump, so these
## are inferred from the names and the game's material letters until that
## file is extracted (roadmap item 7b). Anything not here takes default's.
const PARENTS := {
	"metal": "solidmetal", "metaldogtags": "solidmetal", "metal_box": "solidmetal",
	"metalvehicle": "solidmetal", "metal_shield": "solidmetal", "metalrailing": "solidmetal",
	"weapon_magazine": "solidmetal", "chain": "solidmetal", "ladder": "solidmetal",
	"wood_box": "wood", "wood_basket": "wood", "wood_crate": "wood", "wood_plank": "wood",
	"wood_solid": "wood", "wood_ladder": "wood",
	"mud": "dirt", "grass": "dirt", "slowgrass": "dirt", "sugarcane": "dirt", "gravel": "dirt",
	"wet": "water", "puddle": "water", "slime": "water", "wade": "water", "quicksand": "water",
	"glassfloor": "glass", "stucco": "plaster", "rock": "concrete",
	"bloodyflesh": "flesh", "alienflesh": "flesh",
	"plastic_box": "plastic_barrel", "plastic_solid": "plastic_barrel",
}


## The CS2 surface (a key of SURFACES) for a part of the collision hull, by
## its name: the hull names its parts by surface (physics_group_wood_plank).
## A name the game has no surface for takes the nearest one it does, by
## dropping words off the end (metal_dumpster is metal) or by what it begins
## with (rubbertire is rubber), and anything else is default, as a surface
## with no properties is in the game.
static func surface_for(hull_name: String) -> String:
	var name := hull_name.to_lower().trim_prefix("physics_group").trim_prefix("physics").trim_prefix("_")
	if name.is_empty():
		return "default"
	var words := name.split("_")
	while not words.is_empty():
		var candidate := "_".join(words)
		if SURFACES.has(candidate):
			return candidate
		words.resize(words.size() - 1)
	var best := ""
	for key: String in SURFACES:
		if name.begins_with(key) and key.length() > best.length():
			best = key
	return best if not best.is_empty() else "default"


## A surface's distance modifier (x) and damage modifier (y), each from the
## game's file or, where it gives none, from the surface's parent.
static func modifiers(surface: String) -> Vector2:
	return Vector2(_modifier(surface, 1), _modifier(surface, 2))


static func _modifier(surface: String, column: int) -> float:
	var at := surface
	for i in 4:
		var row: Array = SURFACES.get(at, SURFACES["default"])
		if row[column] != null:
			return row[column]
		at = PARENTS.get(at, "default")
	return SURFACES["default"][column]


## The game's own spelling of a surface, for anything that shows it.
static func display_name(surface: String) -> String:
	return SURFACES.get(surface, SURFACES["default"])[0]


## The power a wall of this thickness uses up, going through a surface with
## this distance modifier. More than the round has left and it stops inside.
static func cost(thickness: float, distance_modifier: float) -> float:
	if distance_modifier <= 0.0:
		return INF
	return thickness / (distance_modifier * REACH_PER_POWER)


## The share of its damage a round keeps through a wall of this thickness,
## by the surface's damage modifier and the weapon's penetration power: a
## stronger round loses less to the same wall.
static func kept(thickness: float, damage_modifier: float, weapon_power: float) -> float:
	if weapon_power <= 0.0:
		return 0.0
	var depth := thickness / (DAMAGE_DEPTH * weapon_power)
	return (1.0 - FLAT_LOSS) * pow(clampf(damage_modifier, 0.0, 1.0), depth)


## The thickest wall a round with this much power left could get through,
## whatever it is made of: how far to look for the other side of one.
static func deepest(power: float) -> float:
	return power * REACH_PER_POWER
