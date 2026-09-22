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
	var spawns := SourceEntities.player_spawns(SourceEntities.parse(entities_path))
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
