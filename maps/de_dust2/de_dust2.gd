extends Node3D

## The dust2 scene.
##
## The map itself is not in this repository and never will be: it is Valve's
## geometry, extracted from your own CS2 install into the gitignored assets/
## directory. This scene finds whatever landed there and imports it, or tells
## you how to produce it if nothing has.
##
## The exported filenames depend on Source 2 Viewer's output layout, so
## nothing here hardcodes them; MapImporter searches the directories.

const MAP_DIR := "res://assets/maps/de_dust2"
const COLLISION_DIR := "res://assets/maps/de_dust2_physics"

## The entity lump, relative to the directory the world glTF is in.
const ENTITIES_FILE := "entities/default_ents.vents"

## Which side's spawn points to start at. They come from the map's entity
## lump; the glTF does not carry them.
@export_enum("T", "CT") var spawn_team: String = "T"

## Where to drop the player in if the entity lump was not extracted.
@export var spawn_position := Vector3.ZERO

## Without spawn points: start above the centre of the map's bounding box
## rather than at spawn_position. Noclip (V) from there.
@export var use_bounds_centre_as_spawn: bool = true

var importer: MapImporter
var player: PlayerBody


func _ready() -> void:
	var map_file := MapImporter.find_map_file(MAP_DIR)
	if map_file.is_empty():
		_build_lighting({})
		_build_fallback()
		return

	importer = MapImporter.new()
	importer.source_path = map_file
	importer.collision_path = MapImporter.find_collision_file(COLLISION_DIR)
	importer.scale_factor = MapImporter.SOURCE2_VIEWER_SCALE
	importer.layer_textures_dir = MAP_DIR
	add_child(importer)

	if importer.stats.has("error"):
		# Found but unreadable, which is what an interrupted extraction leaves.
		push_error("dust2 import failed: %s" % importer.stats["error"])
		_build_lighting({})
		_build_fallback(
			"dust2 is there but would not load:\n    %s\n\n" % importer.stats["error"]
			+ "An extraction that was interrupted leaves it like this.\n"
			+ "Run it again:\n"
			+ "    scripts/extract_assets.sh map"
		)
		return

	_build_lighting(importer.stats.get("sun", {}))
	_place_player(map_file)


func _place_player(map_file: String) -> void:
	player = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	add_child(player)

	var entities_path := ProjectSettings.globalize_path(
		map_file.get_base_dir().path_join(ENTITIES_FILE)
	)
	var spawns: Array = SourceEntities.player_spawns(
		SourceEntities.parse(entities_path)
	)[spawn_team]
	if not spawns.is_empty():
		# Any of the spawns the game would fill first. They sit a little above
		# the floor, as they do in the game, and the player drops onto it.
		var first_choice := spawns.filter(func(candidate: Dictionary) -> bool:
			return candidate["priority"] == spawns[0]["priority"])
		var spawn: Dictionary = first_choice.pick_random()
		player.global_position = spawn["position"]
		(player as PlayerController).input.yaw_degrees = spawn["yaw"]
		return

	push_warning(
		"No spawn points: %s is not there. Run scripts/extract_assets.sh entities."
		% entities_path
	)
	var drop_position := spawn_position
	if use_bounds_centre_as_spawn and importer.stats.has("bounds"):
		var bounds: AABB = importer.stats["bounds"]
		# Above the top of the map, so you fall in rather than starting inside
		# a wall. Noclip is bound to V if you land somewhere useless.
		drop_position = Vector3(
			bounds.get_center().x,
			bounds.position.y + bounds.size.y + 64.0,
			bounds.get_center().z
		)
	player.global_position = drop_position


## A floor to stand on and a message saying why there is no map. Without a
## message of its own, it is the one for a map that has not been extracted
## yet, which is the normal state of a fresh clone.
func _build_fallback(message: String = "") -> void:
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1024.0, 32.0, 1024.0)
	collision.shape = shape
	collision.position = Vector3(0.0, -16.0, 0.0)
	floor_body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh_instance.mesh = box
	mesh_instance.position = collision.position
	floor_body.add_child(mesh_instance)
	add_child(floor_body)

	player = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0.0, 8.0, 0.0)

	if not message.is_empty():
		_show_message(message)
		return
	_show_message(
		"dust2 has not been extracted yet.\n\n"
		+ "Run this on a machine with CS2 installed:\n"
		+ "    scripts/extract_assets.sh map\n\n"
		+ "It writes into assets/, which is gitignored on purpose:\n"
		+ "Valve's geometry does not go in the repository.\n\n"
		+ "Then reopen this scene.\n\n"
		+ "To check what the extraction produced, run:\n"
		+ "    scripts/inspect_assets.sh"
	)


func _show_message(text: String) -> void:
	# Three places, because each one fails for someone: the label is easy to
	# miss if you spawn looking at the sky, the console scrolls away, and a
	# double-clicked terminal closes before it can be read.
	print(text)
	var writer := MapImporter.new()
	writer.write_report(text)
	writer.free()

	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = text
	label.position = Vector2(48, 120)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	add_child(layer)


## The sun goes where the map says it is, when the map says: the export
## carries dust2's own, as a direction and a colour.
func _build_lighting(sun: Dictionary) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -120.0, 0.0)
	if not sun.is_empty():
		light.basis = sun["basis"]
		light.light_color = sun["color"]
	light.light_energy = 1.2
	light.shadow_enabled = true
	# The default is 100, which is metres to Godot and eight feet to us.
	light.directional_shadow_max_distance = 4096.0
	add_child(light)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.5

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
