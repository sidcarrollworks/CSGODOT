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
const ENTITIES_FILE := "entities/default_ents.vents"

## Spawn points float above the floor, the highest on dust2 by 61 units.
const MAX_DROP := 80.0
const SETTLE_TICKS := 320

var _failures: int = 0
var _checks: int = 0
var _frames: int = 0
var _spawned_at_tick: int = 0

var _importer: MapImporter
## Player to the spawn it was put at.
var _players: Dictionary = {}


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

	var entities_path := ProjectSettings.globalize_path(
		map_file.get_base_dir().path_join(ENTITIES_FILE)
	)
	var spawns := SourceEntities.player_spawns(SourceEntities.parse(entities_path))
	_check(
		spawns["T"].size() >= 5 and spawns["CT"].size() >= 5,
		"both teams have spawn points (%d T, %d CT; scripts/extract_assets.sh entities)"
			% [spawns["T"].size(), spawns["CT"].size()]
	)

	var scene: PackedScene = load("res://src/player/player.tscn")
	for team: String in spawns:
		for spawn: Dictionary in spawns[team]:
			var player := scene.instantiate() as PlayerBody
			_importer.add_child(player)
			player.global_position = spawn["position"]
			_players[player] = spawn
	return true


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
