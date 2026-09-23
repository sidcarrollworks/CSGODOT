class_name BombSite
extends RefCounted

## A place the bomb can be planted: one of the map's func_bomb_target
## volumes (BrushVolume.bomb_sites), or a box where a map has none of its
## own (the test range, the checks).

## "A" or "B".
var letter: String = ""
## The site's own solids, when it is the map's.
var volume: BrushVolume
## The site as a box, when it has no volume.
var box: AABB
## The site's bomb_damage_power (dust2: A 1929, B 3234), kept for CS2's
## July 2026 shockwave; 0 when the site has none. Nothing reads it yet.
var damage_power: float = 0.0


## Whether a player standing with their feet here is on the site.
func contains(feet: Vector3) -> bool:
	if volume != null:
		# A little above the feet: a site's floor can sit a hair above the
		# ground it is drawn over.
		return volume.contains(feet + Vector3.UP * 2.0, 1.0)
	return box.has_point(feet + Vector3.UP * 2.0)


## Where the site is, for drawing it and for a bot to walk to.
func bounds() -> AABB:
	return volume.bounds if volume != null else box


## The map's sites, A then B, from BrushVolume.bomb_sites.
static func from_volumes(volumes: Dictionary) -> Array[BombSite]:
	var sites: Array[BombSite] = []
	var letters := volumes.keys()
	letters.sort()
	for site_letter: String in letters:
		var site := BombSite.new()
		site.letter = site_letter
		site.volume = volumes[site_letter]
		site.damage_power = float(site.volume.entity.get("bomb_damage_power", "0"))
		sites.append(site)
	return sites


static func of_box(site_letter: String, site_box: AABB) -> BombSite:
	var site := BombSite.new()
	site.letter = site_letter
	site.box = site_box
	return site
