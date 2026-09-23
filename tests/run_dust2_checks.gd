extends SceneTree

## Checks the extracted dust2, if there is one.
##
##   godot --headless --path . --script tests/run_dust2_checks.gd
##
## The map is Valve's and is not in the repository, so on a machine where
## scripts/extract_assets.sh has not been run this passes without checking
## anything. Where it has, this is the test that the whole chain lines up: the
## export's scale, the axis conversion, the collision hull and the entity
## coordinates are four separate things, and a player dropped at each of the
## map's own spawn points only lands on floor if all four agree.

const MAP_DIR := "res://assets/maps/de_dust2"
const COLLISION_DIR := "res://assets/maps/de_dust2_physics"
const SKYBOX_DIR := "res://assets/maps/de_dust2_skybox"
const ENTITIES_FILE := "entities/default_ents.vents"
const NAV_FILE := "res://assets/maps/de_dust2/maps/de_dust2.nav"

## Spawn points float above the floor, the highest on dust2 by 61 units.
const MAX_DROP := 80.0

const BOTS := 2
const SETTLE_TICKS := 320

var _failures: int = 0
var _checks: int = 0
var _frames: int = 0
var _spawned_at_tick: int = 0

var _importer: MapImporter
## Player to the spawn it was put at.
var _players: Dictionary = {}
var _bots: Array[Bot] = []
var _bot_starts: Array[Vector3] = []
var _spawns: Dictionary = {}
var _places: Dictionary = {}
var _entities: Array[Dictionary] = []


func _process(_delta: float) -> bool:
	_frames += 1
	# One frame of grace so the tree is ready to parent into.
	if _frames == 1:
		return false

	if _frames == 2:
		if not _import():
			return true
		_spawned_at_tick = Engine.get_physics_frames()
		return false

	if Engine.get_physics_frames() - _spawned_at_tick < SETTLE_TICKS:
		return false

	_test_every_spawn_is_on_floor()
	_test_bots_walk()
	_test_nav_mesh()
	_test_volumes_and_radar()
	_importer.free()
	_report()
	return true


## Returns false if there is nothing to check, having already reported.
func _import() -> bool:
	var map_file := MapImporter.find_map_file(MAP_DIR)
	if map_file.is_empty():
		print("dust2 has not been extracted; nothing to check.")
		quit(0)
		return false

	_importer = MapImporter.new()
	_importer.source_path = map_file
	_importer.collision_path = MapImporter.find_collision_file(COLLISION_DIR)
	_importer.scale_factor = MapImporter.SOURCE2_VIEWER_SCALE
	_importer.layer_textures_dir = MAP_DIR
	_importer.lightmaps_dir = "."
	_importer.report = false
	root.add_child(_importer)
	var stats := _importer.stats

	_check(not stats.has("error"), "dust2 loads (%s)" % stats.get("error", ""))
	var bounds: AABB = stats.get("bounds", AABB())
	_check(
		bounds.size.x > 6000.0 and bounds.size.x < 8000.0,
		"dust2 is about 7000 units across (%.0f)" % bounds.size.x
	)
	_check_equal(
		stats.get("collision_from", ""), "the collision hull",
		"collision comes from the hull (scripts/extract_assets.sh physics)"
	)
	_check_penetration_surfaces()
	_check(stats.has("sun"), "the map's sun came through")
	var blend: Dictionary = stats.get("blend", {})
	_check(
		int(blend.get("materials", 0)) >= 50 and (blend.get("missing", PackedStringArray()) as PackedStringArray).is_empty(),
		"walls and ground have their second layer (%d blend materials, %d without their textures; scripts/extract_assets.sh layers)"
			% [blend.get("materials", 0), (blend.get("missing", PackedStringArray()) as PackedStringArray).size()]
	)
	var lightmaps: Dictionary = stats.get("lightmaps", {})
	_check(
		lightmaps.get("found", false) and int(lightmaps.get("surfaces", 0)) >= 2000
			and int(lightmaps.get("props", 0)) >= 1000,
		"the world and its lightmapped props have their baked bounce light (%d surfaces, %d props; scripts/extract_assets.sh lightmaps)"
			% [lightmaps.get("surfaces", 0), lightmaps.get("props", 0)]
	)
	_check(
		lightmaps.get("ambient") is Color,
		"the lightmap's average is measured, for the ambient of the rest (scripts/extract_assets.sh lightmaps runs the prepare step)"
	)
	# A crate whose decal coordinates happen to sit at lightmap density
	# must still not read the lightmap through them: its material says so.
	var crate_shader := ""
	for node in _importer.get_child(0).find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			if (mesh_instance.mesh as ArrayMesh).surface_get_name(surface) == "dust_shipping_crate_01_painted_color":
				var material := mesh_instance.get_active_material(surface)
				crate_shader = (material as ShaderMaterial).shader.resource_path.get_file() if material is ShaderMaterial else "standard"
	_check(
		crate_shader == "probe_lit.gdshader",
		"the painted crates, whose second UV set is their stickers', are lit by the probes and not the lightmap (%s)" % crate_shader
	)
	var probes: Dictionary = stats.get("probes", {})
	_check(
		int(probes.get("volumes", 0)) == 43 and int(probes.get("surfaces", 0)) >= 1000,
		"the map's 43 light-probe volumes are read and light the props the lightmaps did not (%d volumes, %d surfaces; scripts/extract_assets.sh lightmaps)"
			% [probes.get("volumes", 0), probes.get("surfaces", 0)]
	)
	var field := LightProbeField.find(self)
	var under_awning := field.cube_at(Vector3(2380, -50, 300)) if field != null else PackedColorArray()
	var open_ground := field.cube_at(Vector3(2600, 20, -1560)) if field != null else PackedColorArray()
	_check(
		field != null and under_awning.size() == 6 and open_ground[2].b > open_ground[2].r
			and under_awning[3].r > under_awning[3].b,
		"the field is in the scene: the sky is blue from above at B, the awning's floor warm from below at CT spawn"
	)

	var entities_path := ProjectSettings.globalize_path(
		map_file.get_base_dir().path_join(ENTITIES_FILE)
	)
	var entities := SourceEntities.parse(entities_path)
	var spawns := SourceEntities.player_spawns(entities)
	_spawns = spawns
	_places = SourceEntities.places(entities)
	_entities = entities
	_check(
		spawns["T"].size() >= 5 and spawns["CT"].size() >= 5,
		"both teams have spawn points (%d T, %d CT; scripts/extract_assets.sh entities)"
			% [spawns["T"].size(), spawns["CT"].size()]
	)

	var skybox_file := MapImporter.find_map_file(SKYBOX_DIR)
	_check(not skybox_file.is_empty(), "the 3D skybox is there (scripts/extract_assets.sh skybox)")
	if not skybox_file.is_empty():
		# The skybox the game builds, placed as it places it.
		var skybox: MapImporter = load("res://maps/de_dust2/de_dust2.gd").make_skybox(SKYBOX_DIR)
		root.add_child(skybox)
		# Where the sky camera is, read here on its own: scaled up about the
		# map's origin by its own scale, it must land there.
		var sky_camera := {}
		for entity in SourceEntities.parse(ProjectSettings.globalize_path(skybox_file.get_base_dir().path_join("entities/default_ents.vents"))):
			if entity.get("classname", "") == "sky_camera":
				sky_camera = entity
		var camera := SourceEntities.to_game(SourceEntities.vector(sky_camera.get("origin", "[ 0 0 0 ]")))
		var sky_scale := float(sky_camera.get("scale", "16"))
		_check(
			not sky_camera.is_empty() and camera.length() > 1.0
				and is_equal_approx(skybox.scale_factor, MapImporter.SOURCE2_VIEWER_SCALE * sky_scale)
				and (skybox.position + camera * sky_scale).length() < 0.01,
			"the skybox is scaled by the sky camera's %.0f about the camera's point, which lands on the map's origin (off by %.1f)"
				% [sky_scale, (skybox.position + camera * sky_scale).length()]
		)
		var sky_bounds: AABB = skybox.stats.get("bounds", AABB())
		var sky_casting := 0
		for node in skybox.find_children("*", "MeshInstance3D", true, false):
			if (node as MeshInstance3D).visible and (node as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				sky_casting += 1
		_check(sky_casting == 0, "the skybox casts no shadows onto the map")
		_check(
			int(skybox.stats.get("behind", 0)) >= 100,
			"and its surfaces are drawn behind the map (%d of them)" % skybox.stats.get("behind", 0)
		)
		_check(
			int(skybox.stats.get("meshes", 0)) > 100 and int(skybox.stats.get("skipped", 0)) < 40
				and sky_bounds.size.x > bounds.size.x * 3.0,
			"the skybox is %d meshes (%d hidden), far larger than the map (%.0f across)"
				% [skybox.stats.get("meshes", 0), skybox.stats.get("skipped", 0), sky_bounds.size.x]
		)
		skybox.free()

	# Bots walking the CT spawn points, the way the map places them.
	var bot_scene: PackedScene = load("res://src/bots/bot.tscn")
	var route := PackedVector3Array()
	for spawn: Dictionary in spawns["CT"]:
		route.append(spawn["position"])
	for i in BOTS:
		var bot := bot_scene.instantiate() as Bot
		bot.team = "CT"
		bot.weapon_model = WeaponLibrary.m4a1s().model_path
		bot.route = route
		_importer.add_child(bot)
		bot.global_position = route[i]
		bot.set("_next", i + 1)
		_bots.append(bot)
		_bot_starts.append(route[i])

	var scene: PackedScene = load("res://src/player/player.tscn")
	for team: String in spawns:
		for spawn: Dictionary in spawns[team]:
			var player := scene.instantiate() as PlayerBody
			_importer.add_child(player)
			player.global_position = spawn["position"]
			_players[player] = spawn
	return true


## Which of CS2's surfaces each part of the hull is taken as for wall
## penetration (Penetration.surface_for), listed so a part taken as
## default by mistake shows, and checked to be more than one or two.
func _check_penetration_surfaces() -> void:
	var hull := _importer.find_child("Collision", true, false)
	var surfaces := {}
	var not_own := PackedStringArray()
	print("Wall penetration takes the hull's parts as:")
	var seen := {}
	for shape in (hull.get_children() if hull != null else []):
		var hull_name := String(shape.name).rstrip("0123456789").rstrip("_")
		if seen.has(hull_name):
			continue
		seen[hull_name] = true
		var surface := Penetration.surface_for(hull_name)
		surfaces[surface] = true
		var own := hull_name.to_lower().trim_prefix("physics_group").trim_prefix("_")
		if surface != own and not own.is_empty() and hull_name != "physics_sky" and not Penetration.UNNAMED_IN_EXPORT.has(own):
			not_own.append("%s as %s" % [hull_name, surface])
		var modifiers := Penetration.modifiers(surface)
		print("  %-40s %-14s reach %.2f  damage %.2f%s" % [
			hull_name, Penetration.display_name(surface), modifiers.x, modifiers.y,
			"  (no CS2 surface by that name: default)" if surface == "default" and hull_name != "physics_group" else "",
		])
	_check(
		surfaces.size() >= 3,
		"the hull's parts are %d of CS2's surfaces for wall penetration (%s)" % [surfaces.size(), ", ".join(surfaces.keys())]
	)
	_check(
		not_own.is_empty() and surfaces.has("metalrailing"),
		"every part of the hull is the CS2 surface of its own name, the railings the export cannot name being metalrailing (not so: %s)"
			% ", ".join(not_own)
	)


func _test_bots_walk() -> void:
	for i in _bots.size():
		var bot := _bots[i]
		var moved := Vector2(bot.global_position.x - _bot_starts[i].x, bot.global_position.z - _bot_starts[i].z).length()
		_check(
			bot.on_ground and moved > 100.0,
			"bot %d has walked its route on the ground (%.0f units so far)" % [i + 1, moved]
		)
		_check(
			bot.model != null and bot.model.animation_player.current_animation != &"",
			"and is animated (%s)" % (bot.model.animation_player.current_animation if bot.model != null else "no model")
		)
		var head_height: float = bot.hitboxes.hitboxes[0].global_position.y - bot.global_position.y \
			if bot.hitboxes != null and not bot.hitboxes.hitboxes.is_empty() else 0.0
		_check(
			bot.hitboxes != null and bot.hitboxes.hitboxes.size() == 19 and head_height > 50.0 and head_height < 72.0
				and bot.hit_target != null and bot.alive,
			"and wears the game's hitboxes on its bones as it walks, the head %.0f up" % head_height
		)
		var footsteps := bot.get_node_or_null("Footsteps") as Footsteps
		_check(
			footsteps != null and (not SoundBank.available() or (footsteps.steps > 0 and footsteps.surface != "")),
			"and its steps have sounded on the map's own surfaces (%d steps, last on %s)"
				% [footsteps.steps if footsteps else 0, footsteps.surface if footsteps else "-"]
		)



## dust2's nav mesh, the one the game's bots walk (scripts/extract_assets.sh
## nav): read to its last byte, lying on the floor the player walks on, under
## every spawn and by every callout, and leading from both spawns to both bomb
## sites by ways a player could walk.
func _test_nav_mesh() -> void:
	var mesh := SourceNavMesh.load_file(NAV_FILE)
	_check(
		mesh.error.is_empty() and mesh.version == 36 and mesh.unread_bytes == 0 and mesh.areas.size() > 2000
			and mesh.hulls.size() == 1 and is_equal_approx(mesh.hulls[0].get("radius", 0.0), 16.0),
		"dust2's nav mesh reads to its last byte, built for CS2's player: %s" % mesh.summary()
	)
	if not mesh.error.is_empty():
		return

	var broken := 0
	for area: SourceNavMesh.Area in mesh.areas.values():
		for link in area.links():
			var other: SourceNavMesh.Area = mesh.areas.get(link.area)
			if other == null or link.edge >= other.corners.size():
				broken += 1
	var t_spawn: Vector3 = _spawns["T"][0]["position"]
	var start := mesh.area_at(t_spawn)
	var reached := {}
	if start != null:
		reached[start.id] = true
		var queue: Array[int] = [start.id]
		while not queue.is_empty():
			for link in (mesh.areas[queue.pop_back()] as SourceNavMesh.Area).links():
				if not reached.has(link.area):
					reached[link.area] = true
					queue.append(link.area)
	_check(
		broken == 0 and reached.size() >= mesh.areas.size() * 0.97,
		"every link leads to an edge of an area there is, and following them from T spawn reaches %d of the %d areas"
			% [reached.size(), mesh.areas.size()]
	)

	# The mesh floats a little over the floor, as a mesh built from voxels
	# does: each corner should have the hull just under it. Taken 2 units in
	# towards the area's middle, because on a ledge the mesh reaches a unit or
	# so past the lip, and straight down from there is the floor below.
	var space := _importer.get_world_3d().direct_space_state
	var mask := Hitscan.WORLD_LAYER | MapImporter.PLAYER_CLIP_LAYER
	var corners := 0
	var heights := PackedFloat32Array()
	for area: SourceNavMesh.Area in mesh.areas.values():
		for corner in area.corners:
			corners += 1
			var inward := Vector3(area.centre.x - corner.x, 0.0, area.centre.z - corner.z).limit_length(2.0)
			var point := corner + inward
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 4.0, point + Vector3.DOWN * 24.0, mask))
			if not hit.is_empty():
				heights.append(corner.y - (hit["position"] as Vector3).y)
	heights.sort()
	var median := heights[heights.size() >> 1] if not heights.is_empty() else INF
	_check(
		heights.size() >= corners * 0.97 and median >= 0.0 and median < 8.0,
		"the mesh lies on the floor the player walks on: %d of its %d corners have the hull within 24 units under them, %.1f under the middle one"
			% [heights.size(), corners, median]
	)

	var off_mesh := PackedStringArray()
	for player: PlayerBody in _players:
		var feet := player.global_position
		var under := mesh.area_at(feet)
		if under == null or absf(under.floor_at(feet) - feet.y) > 8.0:
			off_mesh.append("%s" % feet)
	_check(
		off_mesh.is_empty(),
		"a player dropped at each of the %d spawns stands on the mesh, within 8 units of its floor (off it: %s)"
			% [_players.size(), ", ".join(off_mesh)]
	)

	# A callout's origin is its brush's middle, up to 270 units over the
	# floor on the tunnel stairs, and a few brushes reach past the mesh.
	var far_callouts := PackedStringArray()
	for place: String in _places:
		var nearest := INF
		for origin: Vector3 in _places[place]:
			for area: SourceNavMesh.Area in mesh.areas.values():
				if area.centre.y < origin.y + 24.0 and area.centre.y > origin.y - 300.0:
					nearest = minf(nearest, area.distance_in_plan(origin))
		if nearest > 64.0:
			far_callouts.append("%s %.0f" % [place, nearest])
	_check(
		_places.size() >= 20 and _places.has("BombsiteA") and _places.has("BombsiteB") and far_callouts.is_empty(),
		"each of dust2's %d callouts stands over the mesh or within 64 units of it (further: %s)"
			% [_places.size(), ", ".join(far_callouts)]
	)

	# Routes between the spawns and the sites, whose legs should clear the
	# walls at a player's waist: a path through a wall is a misread mesh.
	var ct_spawn: Vector3 = _spawns["CT"][0]["position"]
	for route: Array in [
		["T spawn", t_spawn, "A", _places["BombsiteA"][0]], ["T spawn", t_spawn, "B", _places["BombsiteB"][0]],
		["CT spawn", ct_spawn, "A", _places["BombsiteA"][0]], ["CT spawn", ct_spawn, "B", _places["BombsiteB"][0]],
		["T spawn", t_spawn, "CT spawn", ct_spawn],
	]:
		var from: Vector3 = route[1]
		var to: Vector3 = route[3]
		var path := mesh.find_path(from, to)
		var length := 0.0
		var blocked := 0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
			var waist := Vector3.UP * 36.0
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(path[i - 1] + waist, path[i] + waist, mask)).is_empty():
				blocked += 1
		var straight := from.distance_to(to)
		_check(
			path.size() > 2 and length > straight and length < straight * 2.0 and blocked == 0,
			"the mesh leads from %s to %s: %.0f units against %.0f in a straight line, %d legs, %d of them through something at waist height (none should be)"
				% [route[0], route[2], length, straight, path.size() - 1, blocked]
		)


## The brush entities that are volumes (scripts/extract_assets.sh volumes):
## the buy zones hold their side's spawns, the bomb sites are the boxes the
## game baked its bomb damage for, and every callout has its volume. And the
## radar (scripts/extract_assets.sh radar), which puts the spawns and sites
## where the overview's own markers do.
func _test_volumes_and_radar() -> void:
	var zones := BrushVolume.buy_zones(_entities, MAP_DIR)
	var misplaced := PackedStringArray()
	for team: String in ["T", "CT"]:
		for spawn: Dictionary in _spawns[team]:
			var in_own: bool = zones[team].any(func(zone: BrushVolume) -> bool: return zone.contains(spawn["position"]))
			var in_other: bool = zones["CT" if team == "T" else "T"].any(func(zone: BrushVolume) -> bool: return zone.contains(spawn["position"]))
			if not in_own or in_other:
				misplaced.append("%s %s" % [team, spawn["position"]])
	_check(
		zones["T"].size() == 1 and zones["CT"].size() == 1 and misplaced.is_empty(),
		"one buy zone a side, and each of the %d spawns stands in its own side's and not the other's (misplaced: %s)"
			% [_spawns["T"].size() + _spawns["CT"].size(), ", ".join(misplaced)]
	)

	var sites := BrushVolume.bomb_sites(_entities, MAP_DIR)
	var baked := _baked_bomb_damage(MAP_DIR.path_join("maps/de_dust2/baked_bomb_damage.vdata"))
	var boxes: PackedFloat32Array = baked.get("sites", PackedFloat32Array())
	var matches := boxes.size() == 14
	for i in 2:
		var site: BrushVolume = sites.get("AB"[i])
		if site == null or boxes.size() != 14:
			matches = false
			continue
		# The file keeps each site as Source mins, maxs and its damage power.
		var low := SourceEntities.to_game(Vector3(boxes[i * 7], boxes[i * 7 + 1], boxes[i * 7 + 2]))
		var high := SourceEntities.to_game(Vector3(boxes[i * 7 + 3], boxes[i * 7 + 4], boxes[i * 7 + 5]))
		matches = matches and site.bounds.is_equal_approx(AABB(low, high - low))
		matches = matches and is_equal_approx(float(site.entity.get("bomb_damage_power", "0")), boxes[i * 7 + 6])
	_check(
		sites.size() == 2 and matches,
		"bomb sites A and B span the boxes the game baked its bomb damage for (A's is its L's bounds), with the same damage power (%s; %s)"
			% [", ".join(sites.keys()), boxes]
	)
	_check(
		int(baked.get("positions", 0)) > 50000 and baked.get("on_grid", false) and int(baked.get("damage_bytes", 0)) == int(baked.get("positions", 0)) * 8,
		"the baked bomb damage samples %d points on a 10-unit grid, 8 bytes of damage each"
			% baked.get("positions", 0)
	)
	_check(
		is_equal_approx(SourceEntities.bomb_radius(_entities), 700.0),
		"dust2's bombradius is %.0f (info_map_parameters): the old bomb's damage, reaching 3.5 times that" % SourceEntities.bomb_radius(_entities)
	)

	var callouts := BrushVolume.of_class(_entities, "env_cs_place", MAP_DIR)
	var holding := {}
	var not_convex := 0
	for volume in callouts + zones["T"] + zones["CT"] + sites.values():
		for piece in volume.pieces:
			for corner in piece:
				if not volume.contains(corner, 0.1):
					not_convex += 1
	for letter: String in sites:
		for callout in callouts:
			if callout.contains((sites[letter] as BrushVolume).bounds.get_center()):
				holding[letter] = callout.entity.get("place_name", "")
	var off_callout := PackedStringArray()
	for team: String in ["T", "CT"]:
		for spawn: Dictionary in _spawns[team]:
			var places := PackedStringArray()
			for callout in callouts:
				if callout.contains(spawn["position"]):
					places.append(callout.entity.get("place_name", ""))
			var wrong := places.is_empty()
			for place in places:
				wrong = wrong or place != team + "Spawn"
			if wrong:
				off_callout.append("%s %s in %s" % [team, spawn["position"], places])
	_check(
		callouts.size() == 43 and holding.get("A") == "BombsiteA" and holding.get("B") == "BombsiteB" and not_convex == 0,
		"every one of the 43 callouts has its volume, each site's middle is in BombsiteA's or BombsiteB's (%s), and every solid is convex with its faces out (%d corners outside)"
			% [holding, not_convex]
	)
	_check(
		_spawns["T"].size() + _spawns["CT"].size() == 30 and off_callout.is_empty(),
		"each of the %d spawns stands in its own side's spawn callout (TSpawn or CTSpawn) and in no other (off: %s)"
			% [_spawns["T"].size() + _spawns["CT"].size(), ", ".join(off_callout)]
	)

	var overview := MapOverview.load_file(MAP_DIR.path_join("resource/overviews/de_dust2.txt"))
	var radar := load(MAP_DIR.path_join("panorama/images/overheadmaps/de_dust2_radar_psd.png")) as Texture2D
	var off := PackedStringArray()
	# A side's spawns spread up to a fifth of the image; the marker is their
	# middle.
	var points := {
		"TSpawn": _middle_of(_spawns["T"]), "CTSpawn": _middle_of(_spawns["CT"]),
		"bombA": (sites["A"] as BrushVolume).bounds.get_center() if sites.has("A") else Vector3.ZERO,
		"bombB": (sites["B"] as BrushVolume).bounds.get_center() if sites.has("B") else Vector3.ZERO,
	}
	for marker: String in points:
		var on_image := overview.to_image(points[marker])
		if not overview.markers.has(marker) or on_image.distance_to(overview.markers[marker]) > 0.03:
			off.append("%s at %s, marked %s" % [marker, on_image, overview.markers.get(marker)])
	_check(
		overview.error.is_empty() and radar != null and radar.get_size() == Vector2(1024, 1024) and off.is_empty(),
		"the radar is a 1024 square, and the middle of each side's spawns and each site fall on it within 3%% of where the overview marks them (%s)"
			% (", ".join(off) if not off.is_empty() else overview.error)
	)


func _middle_of(spawns: Array) -> Vector3:
	var sum := Vector3.ZERO
	for spawn: Dictionary in spawns:
		sum += spawn["position"]
	return sum / maxf(spawns.size(), 1)


## What can be read of the game's baked bomb damage (KV3 text): the sites'
## boxes and powers as 14 floats, how many points it samples, whether they
## lie on its 10-unit grid, and how many bytes of damage it keeps. The damage
## itself is in a form not worked out yet.
func _baked_bomb_damage(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var blobs := {}
	var hex_space := RegEx.create_from_string("\\s+")
	for found in RegEx.create_from_string("(\\w+) = \\s*#\\[([0-9A-F\\s]*)\\]").search_all(text):
		blobs[found.get_string(1)] = hex_space.sub(found.get_string(2), "", true).hex_decode()
	var positions: PackedByteArray = blobs.get("positions", PackedByteArray())
	var on_grid := positions.size() > 0 and positions.size() % 6 == 0
	for i in range(0, positions.size(), 6):
		for axis in 3:
			if posmod(positions.decode_s16(i + axis * 2), 10) != 5:
				on_grid = false
	var sites: PackedByteArray = blobs.get("bombsites", PackedByteArray())
	return {
		"sites": sites.to_float32_array(),
		"positions": floori(positions.size() / 6.0),
		"on_grid": on_grid,
		"damage_bytes": (blobs.get("damage_values", PackedByteArray()) as PackedByteArray).size(),
	}


func _test_every_spawn_is_on_floor() -> void:
	for player: PlayerBody in _players:
		var spawn: Dictionary = _players[player]
		var drop: float = spawn["position"].y - player.global_position.y
		_check(
			player.on_ground and drop >= 0.0 and drop < MAX_DROP,
			"a player spawned at %s lands on the floor just below (on ground: %s, fell %.1f)"
				% [spawn["position"], player.on_ground, drop]
		)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	printerr("FAIL: %s" % description)


func _check_equal(actual: Variant, expected: Variant, description: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failures += 1
	printerr("FAIL: %s (expected %s, got %s)" % [description, expected, actual])


func _report() -> void:
	if _failures == 0:
		print("%d dust2 checks passed." % _checks)
		quit(0)
	else:
		printerr("%d of %d dust2 checks failed." % [_failures, _checks])
		quit(1)
