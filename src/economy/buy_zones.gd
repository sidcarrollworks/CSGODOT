class_name BuyZones
extends RefCounted

## Where each side may buy: the map's func_buyzone volumes, by side.
##
## CS2 lets a player buy while their hull touches one of their side's buy
## zones. The zones here are BrushVolume's solids (dust2's, from
## BrushVolume.buy_zones) or plain boxes (the test range's). A player counts
## as in one when the middle of their standing hull is within half a hull's
## width of it, which stands in for the hull touching it: 16 units past its
## faces, measured from 36 units above the feet.

## Half the player's hull (32 units across) and its standing middle.
const HULL_MARGIN := 16.0
const HULL_MIDDLE := 36.0

## {"T": [BrushVolume or AABB, ...], "CT": [...]}
var zones := {"T": [], "CT": []}


## A map's zones as BrushVolume.buy_zones gives them.
static func from_volumes(by_side: Dictionary) -> BuyZones:
	var out := BuyZones.new()
	for side in ["T", "CT"]:
		for volume in by_side.get(side, []):
			out.zones[side].append(volume)
	return out


## A box a side may buy in, in game units.
func add_box(side: String, box: AABB) -> void:
	zones[side].append(box)


## Whether a player on a side, standing with their feet here, may buy here.
func contains(side: String, feet: Vector3) -> bool:
	var middle := feet + Vector3(0.0, HULL_MIDDLE, 0.0)
	for zone in zones.get(side, []):
		if zone is AABB:
			if (zone as AABB).grow(HULL_MARGIN).has_point(middle):
				return true
		elif zone is BrushVolume and (zone as BrushVolume).contains(middle, HULL_MARGIN):
			return true
	return false


func is_empty() -> bool:
	return zones["T"].is_empty() and zones["CT"].is_empty()
