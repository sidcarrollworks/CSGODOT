class_name BotRoundMap
extends RefCounted

## Floors/lane goals prepared once from the map's own callouts. Arrays are
## shared read-only; a bot receives a copy when it starts a route. Dust2's
## lane sequences are choices, with a generic site route on other maps.
static func prepare(map: MapContents, sites: PackedVector3Array) -> Dictionary:
	var floors := {}
	var search := PackedVector3Array()
	var names := map.places.keys()
	names.sort()
	for place: String in names:
		var points := PackedVector3Array()
		for origin: Vector3 in map.places[place]:
			var floor_at: Variant = Competitive._floor_under(map.nav_mesh, origin, 300.0)
			if floor_at != null:
				points.append(floor_at)
		if not points.is_empty():
			floors[place] = points
			search.append(points[0])
	if search.is_empty():
		search = sites.duplicate()
	var lanes := {"T": [], "CT": []}
	if map.name == "de_dust2" and sites.size() == 2:
		lanes["T"] = [
			_lane(floors, ["OutsideLong", "LongDoors", "LongA"], sites[0]),
			_lane(floors, ["TopofMid", "Catwalk", "ShortStairs"], sites[0]),
			_lane(floors, ["OutsideTunnel", "UpperTunnel"], sites[1]),
		]
		lanes["CT"] = [
			_lane(floors, ["ARamp"], floors.get("LongA", PackedVector3Array([sites[0]]))[0]),
			_lane(floors, ["ShortStairs", "ExtendedA"], sites[0]),
			_lane(floors, ["BDoors"], sites[1]),
		]
	else:
		for side in ["T", "CT"]:
			for site in sites:
				(lanes[side] as Array).append(PackedVector3Array([site]))
	var enemy_spawn := {}
	for side in ["T", "CT"]:
		var enemies: Array = map.spawns["CT" if side == "T" else "T"]
		enemy_spawn[side] = enemies[0]["position"] if not enemies.is_empty() else sites[0]
	var plant_sites := PackedVector3Array()
	for site in map.bomb_sites:
		var spot: Variant = plant_spot(map.nav_mesh, site)
		if spot != null:
			plant_sites.append(spot)
		else:
			# Keep indices aligned with A/B. No guessed plant location.
			plant_sites.clear()
			break
	return {"sites": sites.duplicate(), "plant_sites": plant_sites, "lanes": lanes, "search": search, "enemy_spawn": enemy_spawn}

## A callout is a broad named area, not a plant zone. Choose a nav floor
## inside the actual func_bomb_target. Prefer its middle; sample its box
## when the middle is on a prop or outside a non-box brush.
static func plant_spot(nav: SourceNavMesh, site: BombSite) -> Variant:
	var box := site.bounds()
	var centre := box.get_center()
	var candidates := PackedVector3Array([centre])
	for x in range(1, 8):
		for z in range(1, 8):
			candidates.append(Vector3(box.position.x + box.size.x * x / 8.0, centre.y, box.position.z + box.size.z * z / 8.0))
	for candidate in candidates:
		var floor_at: Variant = Competitive._floor_under(nav, candidate, box.size.y * 0.5 + 64.0)
		if floor_at != null and site.contains(floor_at):
			return floor_at
	return null

static func _lane(floors: Dictionary, names: Array, goal: Vector3) -> PackedVector3Array:
	var lane := PackedVector3Array()
	for name: String in names:
		if floors.has(name):
			lane.append(floors[name][0])
	lane.append(goal)
	return lane
