class_name Penetration
extends RefCounted

## What a wall does to a round that goes through it: how much of the
## round's penetration power it uses up, and how much of its damage it
## takes, by what the wall is made of and how thick it is.
##
## The surfaces are CS2's own, read from the game's files through
## SurfaceProperties: each one's bulletPenetrationDistanceModifier, how far a
## round gets through it (wood 0.9 goes a long way, sand 0.3 does not), and
## bulletPenetrationDamageModifier, how much damage it lets a round keep
## (concrete 0.25 keeps little, chain-link 0.99 almost all), taken from its
## parent where it gives none, as surfaceproperties.vsurf sets the parents.
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

## Hull part names Source 2 Viewer writes for a surface it has no string
## for, by the surface they are. Its table lacks metalrailing, so dust2's
## railings (12 shapes) come out as physics_group_vrf_unknown_key; the hull's
## physics names its 31 surfaces by hash, and 2838185980 is the vsurf's
## metalrailing, the one of them the export could not name (gravel, the
## other it does not name, no shape uses). On another map it could be
## another surface.
const UNNAMED_IN_EXPORT := {"vrf_unknown_key": "metalrailing"}


## The CS2 surface (lower-case, as SurfaceProperties keys them) for a part
## of the collision hull, by its name: the hull names its parts by surface
## (physics_group_wood_plank, physics_group_metal_dumpster). A name the game
## has no surface for takes the nearest one it does, by dropping words off
## the end or by what it begins with, and anything else is default, as a
## surface with no properties is in the game.
static func surface_for(hull_name: String) -> String:
	var name := hull_name.to_lower().trim_prefix("physics_group").trim_prefix("physics").trim_prefix("_")
	if name.is_empty():
		return "default"
	if UNNAMED_IN_EXPORT.has(name):
		return UNNAMED_IN_EXPORT[name]
	var words := name.split("_")
	while not words.is_empty():
		var candidate := "_".join(words)
		if SurfaceProperties.has(candidate):
			return candidate
		words.resize(words.size() - 1)
	var best := ""
	for key: String in SurfaceProperties.names():
		if name.begins_with(key) and key.length() > best.length():
			best = key
	return best if not best.is_empty() else "default"


## A surface's distance modifier (x) and damage modifier (y), each its own
## or, where the game's file gives none, its parent's.
static func modifiers(surface: String) -> Vector2:
	return Vector2(
		SurfaceProperties.value(surface, "penetration_distance"),
		SurfaceProperties.value(surface, "penetration_damage")
	)


## The game's own spelling of a surface, for anything that shows it.
static func display_name(surface: String) -> String:
	return SurfaceProperties.spelling(surface)


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
