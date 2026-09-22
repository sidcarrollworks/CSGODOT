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
const SKYBOX_DIR := "res://assets/maps/de_dust2_skybox"

## The entity lump and the sky panorama, relative to the directory the world
## glTF is in.
const ENTITIES_FILE := "entities/default_ents.vents"
const SKY_FILE := "../../materials/skybox/sky_de_dust2.exr"

## Which side's spawn points to start at. They come from the map's entity
## lump; the glTF does not carry them.
@export_enum("T", "CT") var spawn_team: String = "T"

## Where to drop the player in if the entity lump was not extracted.
@export var spawn_position := Vector3.ZERO

## Without spawn points: start above the centre of the map's bounding box
## rather than at spawn_position. Noclip (V) from there.
@export var use_bounds_centre_as_spawn: bool = true

## How many of the other side to put in. They walk their spawn area, which
## is the one part of the map they can be sure of, and do nothing else yet.
@export var bots: int = 2

var importer: MapImporter
var skybox: MapImporter
var player: PlayerBody

## The map's entity lump, parsed once for whoever needs it.
var entities: Array[Dictionary] = []


func _ready() -> void:
	var map_file := MapImporter.find_map_file(MAP_DIR)
	if map_file.is_empty():
		MapLighting.build(self, {}, entities, "")
		_build_fallback()
		return
	entities = SourceEntities.parse(
		ProjectSettings.globalize_path(map_file.get_base_dir().path_join(ENTITIES_FILE))
	)

	importer = MapImporter.new()
	importer.source_path = map_file
	importer.collision_path = MapImporter.find_collision_file(COLLISION_DIR)
	importer.scale_factor = MapImporter.SOURCE2_VIEWER_SCALE
	importer.layer_textures_dir = MAP_DIR
	importer.lightmaps_dir = "."
	add_child(importer)

	if importer.stats.has("error"):
		# Found but unreadable, which is what an interrupted extraction leaves.
		push_error("dust2 import failed: %s" % importer.stats["error"])
		MapLighting.build(self, {}, entities, "")
		_build_fallback(
			"dust2 is there but would not load:\n    %s\n\n" % importer.stats["error"]
			+ "An extraction that was interrupted leaves it like this.\n"
			+ "Run it again:\n"
			+ "    scripts/extract_assets.sh map"
		)
		return

	var lighting := MapLighting.build(
		self, importer.stats.get("sun", {}), entities,
		map_file.get_base_dir().path_join(SKY_FILE).simplify_path(),
		importer.stats.get("lightmaps", {}).get("ambient")
	)
	print("--- lighting: sun energy %.2f, exposure %.2f, sky from %s, fog %s, ambient from %s" % [
		lighting["sun_energy"], lighting["exposure"], lighting["sky"], "on" if lighting["fog"] else "off",
		lighting["ambient"],
	])
	_build_skybox()
	_place_player(map_file)
	_place_bots()
	var hud := GameHud.new()
	hud.name = "Hud"
	hud.player = player as PlayerController
	add_child(hud)
	var impacts := BulletImpacts.new()
	impacts.name = "BulletImpacts"
	add_child(impacts)


## Bots on the other side, each walking that side's spawn points in a loop,
## starting from a different one.
func _place_bots() -> void:
	var team := "CT" if spawn_team == "T" else "T"
	var spawns: Array = SourceEntities.player_spawns(entities)[team]
	if spawns.is_empty() or bots <= 0:
		return
	var route := PackedVector3Array()
	for spawn: Dictionary in spawns:
		route.append(spawn["position"])
	var scene := load("res://src/bots/bot.tscn") as PackedScene
	for i in mini(bots, spawns.size()):
		var bot := scene.instantiate() as Bot
		bot.name = "Bot%d" % (i + 1)
		bot.team = team
		bot.weapon_data = WeaponLibrary.m4a1s() if team == "CT" else WeaponLibrary.ak47()
		bot.weapon_model = bot.weapon_data.model_path
		# Each starts at a different point and heads for the next.
		var start := (i * spawns.size()) / maxi(bots, 1)
		bot.route = route
		add_child(bot)
		bot.global_position = spawns[start]["position"]
		bot.yaw_degrees = spawns[start]["yaw"]
		bot.set("_next", (start + 1) % route.size())


## The buildings and horizon beyond the playable map. Source builds them as
## a separate small map at a sixteenth of the scale, around a sky_camera, and
## draws that around the player. Scaling it up by sixteen about the camera's
## position puts the same buildings in the same places, a long way off, with
## the haze doing the rest. Nothing in it is solid.
func _build_skybox() -> void:
	var map_file := MapImporter.find_map_file(SKYBOX_DIR)
	if map_file.is_empty():
		return
	var camera := Vector3.ZERO
	var scale := 16.0
	for entity in SourceEntities.parse(
		ProjectSettings.globalize_path(map_file.get_base_dir().path_join(ENTITIES_FILE))
	):
		if entity.get("classname", "") == "sky_camera":
			camera = SourceEntities.to_game(SourceEntities.vector(entity.get("origin", "")))
			scale = float(entity.get("scale", "16"))
			break

	skybox = MapImporter.new()
	skybox.name = "Skybox"
	skybox.source_path = map_file
	skybox.scale_factor = MapImporter.SOURCE2_VIEWER_SCALE * scale
	skybox.collision_source = MapImporter.CollisionSource.NONE
	skybox.layer_textures_dir = SKYBOX_DIR
	# Its terrain sits at its own ground level, which is above some of the
	# map's floors; the map must win wherever they overlap.
	skybox.behind_everything = true
	# Scenery, not a caster: the game's skybox never shadows the map.
	skybox.cast_shadows = false
	skybox.report = false
	skybox.position = -camera * scale
	add_child(skybox)
	print("--- skybox: %d meshes at %.0fx around %s" % [skybox.stats.get("meshes", 0), scale, camera])


func _place_player(map_file: String) -> void:
	player = (load("res://src/player/player.tscn") as PackedScene).instantiate()
	(player as PlayerController).team = spawn_team
	add_child(player)

	var spawns: Array = SourceEntities.player_spawns(entities)[spawn_team]
	if not spawns.is_empty():
		# Any of the spawns the game would fill first. They sit a little above
		# the floor, as they do in the game, and the player drops onto it.
		var first_choice := spawns.filter(func(candidate: Dictionary) -> bool:
			return candidate["priority"] == spawns[0]["priority"])
		var spawn: Dictionary = first_choice.pick_random()
		(player as PlayerController).place(spawn["position"], spawn["yaw"])
		return

	push_warning(
		"No spawn points: %s is not there. Run scripts/extract_assets.sh entities."
		% map_file.get_base_dir().path_join(ENTITIES_FILE)
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
