class_name SourceEntities
extends RefCounted

## Reads a map's entity lump as Source 2 Viewer decompiles it (a .vents file):
## spawn points, bomb sites, buy zones, the sun. The glTF export carries none
## of that, so this is where "where does a player start" comes from.
##
## The format is one block per entity:
##
##   ====22====
##   enabled                        true
##   classname                      "info_player_terrorist"
##   origin                         [ -822.365173, -795.64209, 150.709 ]
##   angles                         [ 0.0, 106.999992, 0.0 ]
##
## Keys are padded with spaces and never contain one. Values are kept as the
## strings they are, with the quotes taken off; vector() reads the bracketed
## ones. Two value forms run over several lines, a """ heredoc and a [ list,
## and both are skipped: they are rope paths and visibility clusters.


## Every entity in the file, as key to value dictionaries. Empty if the file
## is not there.
static func parse(path: String) -> Array[Dictionary]:
	var entities: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return entities

	var current := {}
	# When inside a multi-line value, the line that ends it.
	var closing := ""
	for raw in file.get_as_text().split("\n"):
		var line := raw.strip_edges(false, true)
		if not closing.is_empty():
			if line == closing:
				closing = ""
			continue
		if line.begins_with("===="):
			if not current.is_empty():
				entities.append(current)
			current = {}
			continue
		# "@" lines are entity I/O connections.
		if line.is_empty() or line.begins_with("@"):
			continue

		var split := line.find(" ")
		if split < 0:
			continue
		var value := line.substr(split).strip_edges()
		if value == '"""':
			closing = '"""'
			continue
		if value == "[":
			closing = "]"
			continue
		if value.length() >= 2 and value.begins_with('"') and value.ends_with('"'):
			value = value.substr(1, value.length() - 2)
		current[line.substr(0, split)] = value

	if not current.is_empty():
		entities.append(current)
	return entities


## Reads "[ x, y, z ]", and "x y z", which is how a prefab's lump writes it.
static func vector(value: String) -> Vector3:
	var parts := value.trim_prefix("[").trim_suffix("]").replace(",", " ").split(" ", false)
	if parts.size() != 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


## A Source position (inches, Z-up) in game space. Source 2 Viewer's glTF puts
## Source X on +Z, Y on +X and Z on +Y, so once the map is scaled back up to
## inches (MapImporter.SOURCE2_VIEWER_SCALE) the two line up exactly.
## tests/run_dust2_checks.gd holds it to that: a player dropped at each of
## dust2's 30 spawn points has to land on the hull just below.
static func to_game(source: Vector3) -> Vector3:
	return Vector3(source.y, source.z, source.x)


## A Source yaw as PlayerInput.yaw_degrees. The half turn is because yaw 0
## looks down Source +X, which is game +Z, and the player's yaw 0 looks down -Z.
static func to_game_yaw(source_yaw: float) -> float:
	return wrapf(source_yaw + 180.0, -180.0, 180.0)


## Player spawn points by team: {"T": [...], "CT": [...]}, each entry a
## {"position": Vector3, "yaw": float, "priority": int} in game space, lowest
## priority number first. The game fills those first: dust2 has five priority 0
## CT spawns, which are the real ones, and ten priority 1 for overflow.
static func player_spawns(entities: Array[Dictionary]) -> Dictionary:
	var spawns := {"T": [], "CT": []}
	for entity in entities:
		var team := ""
		match entity.get("classname", ""):
			"info_player_terrorist":
				team = "T"
			"info_player_counterterrorist":
				team = "CT"
			_:
				continue
		if entity.get("enabled", "true") == "false" or not entity.has("origin"):
			continue
		spawns[team].append({
			"position": to_game(vector(entity["origin"])),
			"yaw": to_game_yaw(vector(entity.get("angles", "[ 0, 0, 0 ]")).y),
			"priority": int(entity.get("priority", "0")),
		})

	for team: String in spawns:
		spawns[team].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["priority"] < b["priority"])
	return spawns


## How far the bomb's blast reaches as the map sets it (info_map_parameters'
## bombradius: 700 on dust2), or -1 where it sets none.
static func bomb_radius(entities: Array[Dictionary]) -> float:
	for entity in entities:
		if entity.get("classname", "") == "info_map_parameters" and entity.has("bombradius"):
			return float(entity["bombradius"])
	return -1.0


## The map's named places, the callouts the radar shows ("BombsiteA",
## "LongDoors"): each name to the game-space origins of the brushes that carry
## it (env_cs_place, 43 on dust2 over 24 names). A brush's origin is its
## middle, which can stand a little off the floor.
static func places(entities: Array[Dictionary]) -> Dictionary:
	var out := {}
	for entity in entities:
		if entity.get("classname", "") != "env_cs_place" or not entity.has("place_name") or not entity.has("origin"):
			continue
		var place: String = entity["place_name"]
		if not out.has(place):
			out[place] = []
		(out[place] as Array).append(to_game(vector(entity["origin"])))
	return out
