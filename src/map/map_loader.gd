class_name MapLoader
extends Node3D

## Loads one extracted CS2 map by name: its geometry and collision hull, its
## lighting and sky, its 3D skybox, its entity lump and its nav mesh, and
## reads from them what a game on it needs (contents). Every path comes from
## the name (MapPaths), so any map scripts/extract_assets.sh has taken loads
## the same way dust2 does.
##
## The map itself is not in this repository and never will be: it is
## Valve's geometry, extracted from your own CS2 install into the gitignored
## assets/ directory. This finds whatever landed there and imports it, or
## says how to produce it if nothing has: a floor to stand on and a message
## when there is no map at all, and a line in contents.missing for each part
## that is missing but leaves the map playable.
##
## The exported filenames depend on Source 2 Viewer's output layout, so
## nothing here hardcodes them; MapImporter searches the directories.

## The map to load, as CS2 names it.
@export var map_name: String = "de_dust2"

## Where to drop the player in if the entity lump was not extracted.
@export var spawn_position := Vector3.ZERO

## Without spawn points: start above the centre of the map's bounding box
## rather than at spawn_position. Noclip (V) from there.
@export var use_bounds_centre_as_spawn: bool = true

var paths: MapPaths
var importer: MapImporter
var skybox: MapImporter
## The map's entity lump, parsed once for whoever needs it.
var entities: Array[Dictionary] = []
## What a game on the map needs from it; filled in _ready.
var contents := MapContents.new()


func _ready() -> void:
	contents.name = map_name
	if not MapPaths.is_valid_name(map_name):
		MapLighting.build(self, {}, entities, "")
		_build_fallback(
			"'%s' is not a map name.\n\n" % map_name
			+ "CS2's are lower case letters, digits and underscores: de_dust2, de_mirage."
		)
		return
	paths = MapPaths.of(map_name)
	var map_file := MapImporter.find_map_file(paths.map_dir)
	if map_file.is_empty():
		MapLighting.build(self, {}, entities, "")
		_build_fallback()
		return
	var entities_path := map_file.get_base_dir().path_join(MapPaths.ENTITIES_FILE)
	entities = SourceEntities.parse(ProjectSettings.globalize_path(entities_path))

	importer = MapImporter.new()
	importer.source_path = map_file
	importer.collision_path = MapImporter.find_collision_file(paths.collision_dir)
	importer.scale_factor = MapImporter.SOURCE2_VIEWER_SCALE
	importer.layer_textures_dir = paths.map_dir
	importer.lightmaps_dir = "."
	add_child(importer)

	if importer.stats.has("error"):
		# Found but unreadable, which is what an interrupted extraction leaves.
		push_error("%s import failed: %s" % [map_name, importer.stats["error"]])
		MapLighting.build(self, {}, entities, "")
		_build_fallback(
			"%s is there but would not load:\n    %s\n\n" % [map_name, importer.stats["error"]]
			+ "An extraction that was interrupted leaves it like this.\n"
			+ "Run it again:\n"
			+ "    %s" % paths.extract_command("map")
		)
		return

	var sky := sky_file(entities, paths.map_dir)
	var lighting := MapLighting.build(
		self, importer.stats.get("sun", {}), entities, sky,
		importer.stats.get("lightmaps", {}).get("ambient")
	)
	print("--- lighting: sun energy %.2f, exposure %.2f, sky from %s, fog %s, ambient from %s, %d lamps lit live" % [
		lighting["sun_energy"], lighting["exposure"], lighting["sky"], "on" if lighting["fog"] else "off",
		lighting["ambient"], lighting["lamps"],
	])
	_build_skybox()
	_read_contents(entities_path)


## What a game needs from the map, read once, and a line for each part that
## was not extracted.
func _read_contents(entities_path: String) -> void:
	contents.spawns = SourceEntities.player_spawns(entities)
	contents.places = SourceEntities.places(entities)
	contents.bomb_radius = SourceEntities.bomb_radius(entities)
	contents.drop_position = spawn_position
	if use_bounds_centre_as_spawn and importer.stats.has("bounds"):
		var bounds: AABB = importer.stats["bounds"]
		# Above the top of the map, so you fall in rather than starting inside
		# a wall. Noclip is bound to V if you land somewhere useless.
		contents.drop_position = Vector3(
			bounds.get_center().x,
			bounds.position.y + bounds.size.y + 64.0,
			bounds.get_center().z
		)
	if not contents.has_both_sides():
		_missing("No spawn points for both sides: %s is not there. Run %s." % [
			entities_path, paths.extract_command("entities")])

	var nav_mesh := SourceNavMesh.load_file(paths.nav_file)
	if nav_mesh.error.is_empty():
		contents.nav_mesh = nav_mesh
		print("--- nav mesh: %s" % nav_mesh.summary())
	else:
		_missing("No nav mesh (%s): %s" % [paths.extract_command("nav"), nav_mesh.error])

	var zones := BuyZones.from_volumes(BrushVolume.buy_zones(entities, paths.map_dir))
	if not zones.zones["T"].is_empty() and not zones.zones["CT"].is_empty():
		contents.buy_zones = zones
	else:
		_missing("No buy zones: run %s." % paths.extract_command("volumes"))
	contents.bomb_sites = BombSite.from_volumes(BrushVolume.bomb_sites(entities, paths.map_dir))
	if contents.bomb_sites.is_empty():
		_missing("No bomb sites: run %s. There is no bomb." % paths.extract_command("volumes"))


func _missing(line: String) -> void:
	push_warning(line)
	contents.missing.append(line)


## The sky panorama the map's own sky material is made of, or "" where it
## has not been extracted (scripts/extract_assets.sh sky). The material is
## the env_sky's skyname; its texture is the one the decompiled material
## names, and failing that the file named as the material is (dust2's
## sky_de_dust2.vmat is drawn from sky_de_dust2.exr). Both are under the
## map's directory, by the path they have in the game.
static func sky_file(map_entities: Array[Dictionary], map_dir: String) -> String:
	var material := ""
	for entity in map_entities:
		if entity.get("classname", "") == "env_sky" and entity.has("skyname"):
			material = resource_path(entity["skyname"])
			break
	if material.is_empty():
		return ""
	var stems := PackedStringArray()
	for texture in sky_textures(FileAccess.get_file_as_string(map_dir.path_join(material))):
		stems.append(texture.get_basename())
	stems.append(material.get_basename())
	for stem in stems:
		for extension: String in ["exr", "hdr", "png"]:
			var path := map_dir.path_join("%s.%s" % [stem, extension])
			if FileAccess.file_exists(path):
				return path
	return ""


## A resource reference as the entity lump writes one
## (resource_name:"materials/skybox/sky_de_dust2.vmat"), bare.
static func resource_path(value: String) -> String:
	return value.trim_prefix("resource_name:").trim_prefix('"').trim_suffix('"')


## The textures a decompiled material names, those on a line that mentions
## the sky first: its source images (dust2's "SkyTexture" names the .exr
## Source 2 Viewer writes) and its compiled textures, whose hashed names
## (sky_de_dust2_exr_908a35ba.vtex) have no file of their own.
static func sky_textures(vmat: String) -> PackedStringArray:
	var sky := PackedStringArray()
	var other := PackedStringArray()
	var texture := RegEx.create_from_string('"([^"]+\\.(?:vtex|exr|hdr|png))"')
	for line in vmat.split("\n"):
		var found := texture.search(line)
		if found == null:
			continue
		if line.to_lower().contains("sky"):
			sky.append(found.get_string(1))
		else:
			other.append(found.get_string(1))
	sky.append_array(other)
	return sky


## The buildings and horizon beyond the playable map. Source builds them as
## a separate small map at a sixteenth of the scale, around a sky_camera, and
## draws that around the player. Scaling it up by sixteen about the camera's
## position puts the same buildings in the same places, a long way off, with
## the haze doing the rest. Nothing in it is solid.
func _build_skybox() -> void:
	skybox = make_skybox(paths.skybox_dir)
	if skybox == null:
		print("--- skybox: none (%s)" % paths.extract_command("skybox"))
		return
	add_child(skybox)
	print("--- skybox: %d meshes at %.0fx" % [skybox.stats.get("meshes", 0), skybox.scale_factor / MapImporter.SOURCE2_VIEWER_SCALE])


## The skybox's importer, set up and placed but not yet in the scene; null
## when it has not been extracted. Static so the checks build the one the
## game does.
static func make_skybox(skybox_dir: String) -> MapImporter:
	var map_file := MapImporter.find_map_file(skybox_dir)
	if map_file.is_empty():
		return null
	var camera := Vector3.ZERO
	var sky_scale := 16.0
	for entity in SourceEntities.parse(
		ProjectSettings.globalize_path(map_file.get_base_dir().path_join(MapPaths.ENTITIES_FILE))
	):
		if entity.get("classname", "") == "sky_camera":
			camera = SourceEntities.to_game(SourceEntities.vector(entity.get("origin", "")))
			sky_scale = float(entity.get("scale", "16"))
			break

	var sky_importer := MapImporter.new()
	sky_importer.name = "Skybox"
	sky_importer.source_path = map_file
	sky_importer.scale_factor = MapImporter.SOURCE2_VIEWER_SCALE * sky_scale
	sky_importer.collision_source = MapImporter.CollisionSource.NONE
	sky_importer.layer_textures_dir = skybox_dir
	# Its own baked light, beside its world as the map's is: the two-layer
	# walls take all but the sun from it, and without it are black in shade.
	sky_importer.lightmaps_dir = "."
	# Its terrain sits at its own ground level, which is above some of the
	# map's floors; the map must win wherever they overlap.
	sky_importer.behind_everything = true
	# Scenery, not a caster: the game's skybox never shadows the map.
	sky_importer.cast_shadows = false
	sky_importer.report = false
	# The sky camera's point, scaled up about the map's origin, lands on it.
	sky_importer.position = -camera * sky_scale
	return sky_importer


## A floor to stand on and a message saying why there is no map. Without a
## message of its own, it is the one for a map that has not been extracted
## yet, which is the normal state of a fresh clone.
func _build_fallback(message: String = "") -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
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
	contents.drop_position = Vector3(0.0, 8.0, 0.0)

	if not message.is_empty():
		_show_message(message)
		return
	_show_message(
		"%s has not been extracted yet.\n\n" % map_name
		+ "Run this on a machine with CS2 installed:\n"
		+ "    %s\n\n" % paths.extract_command("map")
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
