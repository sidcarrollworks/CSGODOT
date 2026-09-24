class_name MapContents
extends RefCounted

## What a map gives the game played on it: where each side starts, the buy
## zones, the bomb sites and the bomb's damage, the callouts, the nav mesh,
## and where to drop a player when there are no spawn points. A mode
## (Competitive) sets its game up from this alone, so it runs on whatever map
## is loaded. MapLoader fills it from the extracted files; the checks fill it
## by hand.

## The map's name (de_dust2), or "" for one built by hand.
var name: String = ""
## Spawn points by side, as SourceEntities.player_spawns gives them.
var spawns: Dictionary = {"T": [], "CT": []}
## The callouts by name, as SourceEntities.places gives them.
var places: Dictionary = {}
## The floor the bots walk; null where the map has none.
var nav_mesh: SourceNavMesh
## Each side's func_buyzone; null where they were not extracted.
var buy_zones: BuyZones
## The map's bomb sites, A then B; empty where there are none.
var bomb_sites: Array[BombSite] = []
## The map's bombradius (info_map_parameters), or -1 where it sets none.
var bomb_radius: float = -1.0
## Where a player goes in without spawn points.
var drop_position: Vector3 = Vector3.ZERO
## What is missing but leaves the map playable, one line each, saying how
## to extract it.
var missing: PackedStringArray = []


## Whether both sides have somewhere to start, which a match needs.
func has_both_sides() -> bool:
	return not (spawns["T"] as Array).is_empty() and not (spawns["CT"] as Array).is_empty()
