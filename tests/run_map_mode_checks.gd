extends "res://tests/check_suite.gd"

## Checks maps apart from modes: every path of a map derived from its name,
## as the extraction script writes them (dust2's exactly as they always
## were); the sky found from the map's own sky material; the map chosen by
## --map; competitive set up on a small map built here, with spawn points,
## buy zones and bomb sites given directly; and the bots' way to the bomb
## sites on a map whose callouts are not named BombsiteA and BombsiteB.
##
##   godot --headless --path . --script tests/run_map_mode_checks.gd
##
## Needs nothing extracted.

const T_SPAWNS := [
	{"position": Vector3(0.0, 8.0, 0.0), "yaw": 0.0, "priority": 0},
	{"position": Vector3(128.0, 8.0, 0.0), "yaw": 0.0, "priority": 0},
	{"position": Vector3(256.0, 8.0, 0.0), "yaw": 0.0, "priority": 1},
]
const CT_SPAWNS := [
	{"position": Vector3(0.0, 8.0, -1500.0), "yaw": 180.0, "priority": 0},
	{"position": Vector3(128.0, 8.0, -1500.0), "yaw": 180.0, "priority": 0},
]

## Where the sky check writes its stand-in extraction.
const SKY_DIR := "user://map_mode_checks_sky"


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_paths_from_a_name()
	_test_the_extraction_script_agrees()
	_test_the_map_from_the_command_line()
	_test_the_sky_from_the_maps_own_material()
	_test_site_floors_from_callouts_or_volumes()
	# The tree takes nodes in from its first frame on.
	await physics_frame
	await physics_frame
	await _test_competitive_on_a_small_map()
	await _test_competitive_without_the_maps_buy_zones_or_a_side()
	_finish("map-mode")


# --- Paths -------------------------------------------------------------------

func _test_paths_from_a_name() -> void:
	# dust2's, as the scene and the checks had them written out before.
	var dust2 := MapPaths.of("de_dust2")
	_check_equal(dust2.map_dir, "res://assets/maps/de_dust2", "dust2's map directory is where it always was")
	_check_equal(dust2.collision_dir, "res://assets/maps/de_dust2_physics", "dust2's hull is where it always was")
	_check_equal(dust2.skybox_dir, "res://assets/maps/de_dust2_skybox", "dust2's skybox is where it always was")
	_check_equal(dust2.nav_file, "res://assets/maps/de_dust2/maps/de_dust2.nav", "dust2's nav mesh is where it always was")
	_check_equal(
		dust2.radar_image, "res://assets/maps/de_dust2/panorama/images/overheadmaps/de_dust2_radar_psd.png",
		"dust2's radar image is where it always was"
	)
	_check_equal(
		dust2.overview_file, "res://assets/maps/de_dust2/resource/overviews/de_dust2.txt",
		"dust2's overview text is where it always was"
	)
	_check_equal(
		dust2.baked_bomb_damage, "res://assets/maps/de_dust2/maps/de_dust2/baked_bomb_damage.vdata",
		"dust2's baked bomb damage is where it always was"
	)

	var mirage := MapPaths.of("de_mirage")
	_check(
		mirage.map_dir == "res://assets/maps/de_mirage" and mirage.collision_dir == "res://assets/maps/de_mirage_physics"
			and mirage.skybox_dir == "res://assets/maps/de_mirage_skybox"
			and mirage.nav_file == "res://assets/maps/de_mirage/maps/de_mirage.nav"
			and mirage.entity_models_dir == "res://assets/maps/de_mirage/maps/de_mirage/entities/",
		"another map's paths are dust2's with its name in place of dust2's"
	)
	_check_equal(mirage.extract_command("nav"), "scripts/extract_assets.sh nav de_mirage", "what to run names the map")
	_check(
		MapPaths.is_valid_name("de_dust2") and MapPaths.is_valid_name("cs_office") and MapPaths.is_valid_name("ar_baggage")
			and not MapPaths.is_valid_name("") and not MapPaths.is_valid_name("De_Dust2")
			and not MapPaths.is_valid_name("../de_dust2") and not MapPaths.is_valid_name("de dust2"),
		"a map's name is lower case letters, digits and underscores, and nothing that climbs out of assets/"
	)


## The script's own paths (extract_assets.sh paths), which need no CS2, are
## the ones MapPaths derives.
func _test_the_extraction_script_agrees() -> void:
	for map_name: String in ["de_dust2", "de_mirage"]:
		var output: Array = []
		var code := OS.execute("bash", [ProjectSettings.globalize_path("res://scripts/extract_assets.sh"), "paths", map_name], output, true)
		if code == -1:
			print("  (no bash here, so the extraction script's paths were not compared)")
			return
		var script_paths := {}
		for line in String(output[0]).split("\n", false):
			var parts := line.split(" ", false, 1)
			if parts.size() == 2:
				script_paths[parts[0]] = "res://" + parts[1]
		var paths := MapPaths.of(map_name)
		_check(
			code == 0 and script_paths.get("map") == paths.map_dir and script_paths.get("physics") == paths.collision_dir
				and script_paths.get("skybox") == paths.skybox_dir and script_paths.get("nav") == paths.nav_file
				and script_paths.get("entity-models") == paths.entity_models_dir
				and script_paths.get("radar") == paths.radar_image and script_paths.get("overview") == paths.overview_file,
			"the extraction script puts %s where the game looks for it (%s)" % [map_name, script_paths]
		)


func _test_the_map_from_the_command_line() -> void:
	_check_equal(PlayScene.map_from_args(PackedStringArray(["--map", "de_mirage"]), "de_dust2"), "de_mirage", "--map de_mirage chooses mirage")
	_check_equal(PlayScene.map_from_args(PackedStringArray(["--x", "--map=de_inferno"]), "de_dust2"), "de_inferno", "--map=de_inferno chooses inferno")
	_check_equal(PlayScene.map_from_args(PackedStringArray(["--map"]), "de_dust2"), "de_dust2", "--map with no name leaves the scene's map")
	_check_equal(PlayScene.map_from_args(PackedStringArray(), "de_overpass"), "de_overpass", "without --map the scene's own map plays")
	var scene := load("res://maps/de_dust2/de_dust2.tscn") as PackedScene
	var dust2 := scene.instantiate()
	_check(dust2 is PlayScene and dust2.get("map_name") == "de_dust2", "maps/de_dust2/de_dust2.tscn is the play scene set to de_dust2")
	_check(dust2.get("team_size") == 5, "and still takes a team size, as scripts/profile_dust2.gd sets it")
	dust2.free()


# --- The sky -------------------------------------------------------------------

## The sky's file comes from the env_sky's material: the texture the
## decompiled material names, or the file named as the material is.
func _test_the_sky_from_the_maps_own_material() -> void:
	_check_equal(
		MapLoader.resource_path('resource_name:"materials/skybox/sky_de_dust2.vmat"'), "materials/skybox/sky_de_dust2.vmat",
		"the lump's resource reference, bare"
	)
	var vmat := "\n".join([
		'\t"g_tNormal" "materials/default/default_normal.vtex"',
		'\t"g_tSkyTexture" "materials/skybox/sky_mirage_hdr.vtex"',
	])
	_check_equal(
		MapLoader.sky_textures(vmat), PackedStringArray(["materials/skybox/sky_mirage_hdr.vtex", "materials/default/default_normal.vtex"]),
		"the material's sky texture comes first"
	)

	DirAccess.make_dir_recursive_absolute(SKY_DIR.path_join("materials/skybox"))
	var entities: Array[Dictionary] = [
		{"classname": "env_sky", "skyname": 'resource_name:"materials/skybox/sky_de_mirage.vmat"'},
	]
	_check_equal(MapLoader.sky_file(entities, SKY_DIR), "", "no sky where the panorama was not extracted")
	_write(SKY_DIR.path_join("materials/skybox/sky_de_mirage.exr"), "stand-in")
	_check_equal(
		MapLoader.sky_file(entities, SKY_DIR), SKY_DIR.path_join("materials/skybox/sky_de_mirage.exr"),
		"a panorama named as its material, as dust2's is"
	)
	_write(SKY_DIR.path_join("materials/skybox/sky_de_mirage.vmat"), vmat)
	_write(SKY_DIR.path_join("materials/skybox/sky_mirage_hdr.exr"), "stand-in")
	_check_equal(
		MapLoader.sky_file(entities, SKY_DIR), SKY_DIR.path_join("materials/skybox/sky_mirage_hdr.exr"),
		"the texture the material names wins over the name's guess"
	)
	_check_equal(MapLoader.sky_file([], SKY_DIR), "", "no env_sky, no sky")
	for file in ["sky_de_mirage.exr", "sky_de_mirage.vmat", "sky_mirage_hdr.exr"]:
		DirAccess.remove_absolute(SKY_DIR.path_join("materials/skybox").path_join(file))


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# --- Bot routes -------------------------------------------------------------------

## Two sites on a nav mesh of three floors in a row: A at x 0 to 400, B at
## x 1200 to 1600, a street between them 32 units lower.
func _test_site_floors_from_callouts_or_volumes() -> void:
	var mesh := _three_floors()
	var a := BombSite.of_box("A", AABB(Vector3(100.0, 0.0, -300.0), Vector3(200.0, 200.0, 200.0)))
	var b := BombSite.of_box("B", AABB(Vector3(1300.0, 0.0, -300.0), Vector3(200.0, 200.0, 200.0)))
	var sites: Array[BombSite] = [a, b]

	var callouts := {"BombsiteA": [Vector3(50.0, 60.0, -100.0)], "BombsiteB": [Vector3(1500.0, 60.0, -100.0)]}
	var floors := Competitive.site_floors(mesh, callouts, sites)
	_check(
		floors.size() == 2 and floors[0].is_equal_approx(Vector3(50.0, 0.0, -100.0))
			and floors[1].is_equal_approx(Vector3(1500.0, 0.0, -100.0)),
		"with BombsiteA and BombsiteB callouts the bots walk to the floor under them (%s)" % floors
	)

	var other_names := {"ASite": [Vector3(50.0, 60.0, -100.0)], "BSite": [Vector3(1500.0, 60.0, -100.0)]}
	floors = Competitive.site_floors(mesh, other_names, sites)
	_check(
		floors.size() == 2 and floors[0].is_equal_approx(Vector3(200.0, 0.0, -200.0))
			and floors[1].is_equal_approx(Vector3(1400.0, 0.0, -200.0)),
		"without them, to the floor under the middle of each bomb site's volume, A then B (%s)" % floors
	)
	floors = Competitive.site_floors(mesh, {"BombsiteA": [Vector3(50.0, 60.0, -100.0)]}, sites)
	_check(floors.size() == 2 and floors[0].is_equal_approx(Vector3(200.0, 0.0, -200.0)), "and with only one of them too")
	var one_site: Array[BombSite] = [a]
	_check(Competitive.site_floors(mesh, other_names, one_site).is_empty(), "with neither, no sites to walk to")
	var off_mesh: Array[BombSite] = [a, BombSite.of_box("B", AABB(Vector3(5000.0, 0.0, 5000.0), Vector3(100.0, 100.0, 100.0)))]
	_check(Competitive.site_floors(mesh, other_names, off_mesh).is_empty(), "nor with a site nowhere near the mesh")

	var spawns := {"T": T_SPAWNS, "CT": CT_SPAWNS}
	floors = Competitive.site_floors(mesh, other_names, sites)
	var first := Competitive.bot_route(spawns, "T", 0, floors)
	var second := Competitive.bot_route(spawns, "T", 1, floors)
	_check(
		first == PackedVector3Array([T_SPAWNS[0]["position"], floors[0]])
			and second == PackedVector3Array([T_SPAWNS[1]["position"], floors[1]]),
		"a side's bots walk from a spawn point to A and B in turn"
	)
	_check_equal(
		Competitive.bot_route(spawns, "CT", 0, PackedVector3Array()),
		PackedVector3Array([CT_SPAWNS[0]["position"], CT_SPAWNS[1]["position"]]),
		"with no sites, round their side's spawn points"
	)


func _three_floors() -> SourceNavMesh:
	var list: Array[SourceNavMesh.Area] = []
	for square: Array in [[0.0, 400.0, 0.0], [400.0, 1200.0, -32.0], [1200.0, 1600.0, 0.0]]:
		var area := SourceNavMesh.Area.new()
		area.id = list.size() + 1
		area.corners = PackedVector3Array([
			Vector3(square[0], square[2], 0.0), Vector3(square[1], square[2], 0.0),
			Vector3(square[1], square[2], -400.0), Vector3(square[0], square[2], -400.0),
		])
		area.edges = [[], [], [], []]
		list.append(area)
	return SourceNavMesh.from_areas(list)


# --- Competitive on a map built here ----------------------------------------------

func _small_map() -> MapContents:
	var map := MapContents.new()
	map.spawns = {"T": T_SPAWNS.duplicate(true), "CT": CT_SPAWNS.duplicate(true)}
	map.buy_zones = BuyZones.new()
	map.buy_zones.add_box("T", AABB(Vector3(-100.0, 0.0, -100.0), Vector3(500.0, 100.0, 200.0)))
	map.buy_zones.add_box("CT", AABB(Vector3(-100.0, 0.0, -1600.0), Vector3(400.0, 100.0, 200.0)))
	map.bomb_sites = [
		BombSite.of_box("A", AABB(Vector3(-600.0, 0.0, -800.0), Vector3(200.0, 100.0, 200.0))),
		BombSite.of_box("B", AABB(Vector3(600.0, 0.0, -800.0), Vector3(200.0, 100.0, 200.0))),
	]
	map.bomb_radius = 500.0
	return map


## A scene as maps/play/play.tscn builds one, on the map given, with the
## floor under it; returns [the scene, the world, the mode].
func _play_on(map: MapContents, team_size: int) -> Array:
	var scene := Node3D.new()
	root.add_child(scene)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(4096.0, 32.0, 4096.0)
	shape.position = Vector3(0.0, -16.0, 0.0)
	floor_body.add_child(shape)
	scene.add_child(floor_body)
	var world := GameWorld.new()
	scene.add_child(world)
	var mode := Competitive.new()
	mode.team_size = team_size
	mode.warmup_seconds = 0.0
	scene.add_child(mode)
	mode.start(world, map)
	return [scene, world, mode]


func _test_competitive_on_a_small_map() -> void:
	var map := _small_map()
	var played := _play_on(map, 2)
	var scene: Node3D = played[0]
	var world: GameWorld = played[1]
	var mode: Competitive = played[2]

	_check(world.players.size() == 4 and world.players[0] == mode.player, "you and three bots, two a side, you first")
	_check_equal(mode.bots.filter(func(bot: Bot) -> bool: return bot.team == "CT").size(), 2, "both CT places are bots")
	_check(mode.match_state != null and world.match_state == mode.match_state, "a match, run by the world")
	_check(mode.match_state.players.size() == 4, "with everyone in it")
	_check(mode.economy != null and mode.economy.zones == map.buy_zones, "an economy buying in the map's own zones")
	_check(mode.bomb_system != null and mode.bomb_system.sites == map.bomb_sites, "a bomb on the map's own sites")
	_check(is_equal_approx(mode.bomb_system.bomb.rules.bomb_damage, 500.0), "with the map's bomb damage")
	_check(mode.grenade_system != null, "grenades")
	var systems := world.game.systems()
	_check(
		systems.has(mode.economy) and systems.has(mode.bomb_system) and systems.has(mode.grenade_system),
		"all three in the world's game"
	)
	_check(mode.hud != null and mode.hud.match_state == mode.match_state and mode.hud.economy == mode.economy, "the HUD reads the match and your money")
	_check(mode.hud.scope != null and mode.hud.scope.player == mode.player, "and draws your scope, on any map")
	_check(mode.notes.size() == 1 and mode.notes[0].contains("nav mesh"), "the only thing missing is the nav mesh (%s)" % [mode.notes])
	var at_spawn := false
	for spawn: Dictionary in T_SPAWNS:
		at_spawn = at_spawn or Vector2(spawn["position"].x, spawn["position"].z).distance_to(
			Vector2(mode.player.global_position.x, mode.player.global_position.z)) < 1.0
	_check(at_spawn, "you start at a T spawn point")

	for i in 8:
		await physics_frame
	_check(world.tick >= 4, "the world ticks the game (%d)" % world.tick)
	_check(mode.match_state.round_number >= 1, "and without warmup the first round has begun (round %d)" % mode.match_state.round_number)
	scene.queue_free()
	await process_frame


func _test_competitive_without_the_maps_buy_zones_or_a_side() -> void:
	var map := _small_map()
	map.buy_zones = null
	map.bomb_sites = []
	var played := _play_on(map, 1)
	var mode: Competitive = played[2]
	_check(mode.economy != null and mode.economy.zones.contains("T", T_SPAWNS[2]["position"]), "without the map's buy zones, a stand-in round each side's spawn points")
	_check(mode.notes.has("Buying is round each side's spawn points instead of the map's buy zones."), "which it says")
	_check(mode.bomb_system == null and mode.match_state != null, "without bomb sites, a match with no bomb")
	(played[0] as Node).queue_free()
	await process_frame

	map = _small_map()
	map.spawns = {"T": T_SPAWNS.duplicate(true), "CT": []}
	map.drop_position = Vector3(0.0, 40.0, 0.0)
	played = _play_on(map, 2)
	mode = played[2]
	_check(mode.match_state == null and mode.economy == null, "without a side's spawn points, no match")
	_check(mode.bots.size() == 1 and (played[1] as GameWorld).players.size() == 2, "only the side that has spawn points gets a bot")
	_check(mode.hud != null, "and the HUD all the same")
	(played[0] as Node).queue_free()
	await process_frame
