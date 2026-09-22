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
		var skybox := MapImporter.new()
		skybox.source_path = skybox_file
		skybox.scale_factor = MapImporter.SOURCE2_VIEWER_SCALE * 16.0
		skybox.collision_source = MapImporter.CollisionSource.NONE
		skybox.report = false
		root.add_child(skybox)
		var sky_bounds: AABB = skybox.stats.get("bounds", AABB())
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
