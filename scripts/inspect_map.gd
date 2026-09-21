extends SceneTree

## Prints what the map import found, without opening the editor or pressing
## play.
##
##   godot --headless --path . --script scripts/inspect_map.gd
##
## (scripts/inspect_assets.sh runs this for you.)
##
## The output is the thing to send over when asking for help with an import:
## it says how many meshes came through, how big the map is, and every material
## name, which is what decides how collision gets configured.

const MAP_DIR := "res://assets/maps/de_dust2"

var _done: bool = false


func _process(_delta: float) -> bool:
	# One frame of grace so the tree is ready to parent into.
	if not _done:
		_done = true
		return false

	var map_file := MapImporter.find_map_file(MAP_DIR)
	if map_file.is_empty():
		print("No glTF found under %s" % MAP_DIR)
		print("")
		print("Either the extraction has not been run, or it wrote somewhere else.")
		print("Run 'scripts/extract_assets.sh map' on a machine with CS2 installed,")
		print("then check that assets/maps/de_dust2 has files in it.")
		quit(1)
		return true

	print("Found: %s" % map_file)
	print("")

	var importer := MapImporter.new()
	importer.source_path = map_file
	importer.report = true
	root.add_child(importer)

	var failed: bool = importer.stats.has("error")
	importer.free()
	quit(1 if failed else 0)
	return true
