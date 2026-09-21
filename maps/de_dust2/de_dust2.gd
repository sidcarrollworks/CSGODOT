extends Node3D

## The dust2 scene.
##
## The map itself is not in this repository and never will be: it is Valve's
## geometry, extracted from your own CS2 install into the gitignored assets/
## directory. This scene finds whatever landed there and imports it, or tells
## you how to produce it if nothing has.
##
## The exported filename depends on Source 2 Viewer's output layout, so
## nothing here hardcodes it; MapImporter.find_map_file takes the first glTF
## under the map directory.

const MAP_DIR := "res://assets/maps/de_dust2"

## Where to drop the player in. Dust2's real spawn points live in the map's
## entity data, which the glTF export does not carry, so this starts as the
## centre of the map's bounding box and is meant to be adjusted once you have
## seen the thing. Noclip (V) is the quickest way to find a better number.
@export var spawn_position := Vector3.ZERO

@export var use_bounds_centre_as_spawn: bool = true

var importer: MapImporter
var player: PlayerBody


func _ready() -> void:
	_build_lighting()

	var map_file := MapImporter.find_map_file(MAP_DIR)
	if map_file.is_empty():
		_build_fallback()
		return

	importer = MapImporter.new()
	importer.source_path = map_file
	add_child(importer)

	_place_player()


func _place_player() -> void:
	player = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	add_child(player)

	var position := spawn_position
	if use_bounds_centre_as_spawn and importer.stats.has("bounds"):
		var bounds: AABB = importer.stats["bounds"]
		# Above the top of the map, so you fall in rather than starting inside
		# a wall. Noclip is bound to V if you land somewhere useless.
		position = Vector3(
			bounds.get_center().x,
			bounds.position.y + bounds.size.y + 64.0,
			bounds.get_center().z
		)
	player.global_position = position


## Shown when the map has not been extracted yet, which is the normal state of
## a fresh clone.
func _build_fallback() -> void:
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
	# Console as well as on screen: the label is easy to miss if you spawn
	# looking at the sky.
	print(text)

	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = text
	label.position = Vector2(48, 120)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	add_child(layer)


func _build_lighting() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -120.0, 0.0)
	light.light_energy = 1.2
	light.shadow_enabled = true
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
