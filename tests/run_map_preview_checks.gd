extends "res://tests/check_suite.gd"

## Checks the editor's preview of a map (MapPreview): both scenes that play
## a map carry one; it finds the world glTF by the map's name, at the game's
## scale and without the export's sun; it hides the surfaces the game never
## draws; and in the game it frees itself without loading anything.
##
##   godot --headless --path . --script tests/run_map_preview_checks.gd
##
## Needs nothing extracted: it writes a small stand-in map into assets/ and
## removes it again.

const STAND_IN := "zz_map_preview_check"


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_the_scenes_carry_a_preview()
	_test_nothing_to_show()
	_test_a_stand_in_map()
	_test_what_the_game_never_draws()
	await _test_it_leaves_the_game_alone()
	_finish("map-preview")


func _test_the_scenes_carry_a_preview() -> void:
	for path: String in ["res://maps/de_dust2/de_dust2.tscn", "res://maps/play/play.tscn"]:
		var scene := (load(path) as PackedScene).instantiate()
		var preview := scene.get_node_or_null("EditorPreview")
		_check(preview is MapPreview, "%s has a MapPreview" % path)
		if preview is MapPreview:
			_check_equal((preview as MapPreview).shown_map(), "de_dust2",
				"%s previews the map it plays" % path)
		scene.free()


func _test_nothing_to_show() -> void:
	_check(MapPreview.load_world("not a map") == null, "a name that is not a map's shows nothing")
	_check(MapPreview.load_world("zz_never_extracted") == null, "a map not extracted shows nothing")


func _test_a_stand_in_map() -> void:
	var dir := MapPaths.of(STAND_IN).map_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var root := Node3D.new()
	root.name = "world"
	var box := MeshInstance3D.new()
	box.name = "box"
	box.mesh = BoxMesh.new()
	root.add_child(box)
	box.owner = root
	var sun := DirectionalLight3D.new()
	sun.name = "sun"
	root.add_child(sun)
	sun.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(root, state)
	var written := document.write_to_filesystem(state, ProjectSettings.globalize_path(dir.path_join("world.gltf")))
	root.free()
	_check_equal(written, OK, "the stand-in map is written")

	var world := MapPreview.load_world(STAND_IN)
	_check(world != null, "an extracted map is shown")
	if world != null:
		_check_near(world.scale.x, MapImporter.SOURCE2_VIEWER_SCALE, "at the game's scale")
		_check(world.find_children("*", "MeshInstance3D", true, false).size() == 1, "with its meshes")
		_check(world.find_children("*", "Light3D", true, false).is_empty(), "without the export's sun")
		world.free()
	_remove(ProjectSettings.globalize_path(dir))
	# And what was made to hold it, where it was not there before.
	for parent: String in [MapPaths.ROOT, MapPaths.ROOT.get_base_dir()]:
		var absolute := ProjectSettings.globalize_path(parent)
		if DirAccess.get_files_at(absolute).is_empty() and DirAccess.get_directories_at(absolute).is_empty():
			DirAccess.remove_absolute(absolute)


func _test_what_the_game_never_draws() -> void:
	var root := Node3D.new()
	var paths := {
		"wall": "materials/dust2/wall.vmat",
		"clip": "materials/tools/toolsplayerclip.vmat",
		"glow": "materials/effects/light_glow.vmat",
	}
	for mesh_name: String in paths:
		root.add_child(_mesh(mesh_name, {"Name": paths[mesh_name], "ShaderName": "csgo_complex.vfx"}))
	root.add_child(_mesh("dome", {"Name": "materials/skybox/dome.vmat", "ShaderName": "sky.vfx"}))
	root.add_child(_mesh("bare", null))
	_check_equal(MapPreview.hide_unseen(root), 3, "three surfaces left out")
	for mesh_name: String in ["wall", "bare"]:
		_check((root.get_node(mesh_name) as MeshInstance3D).visible, "%s is shown" % mesh_name)
	for mesh_name: String in ["clip", "glow", "dome"]:
		_check(not (root.get_node(mesh_name) as MeshInstance3D).visible, "%s is left out" % mesh_name)
	root.free()


func _test_it_leaves_the_game_alone() -> void:
	var preview := MapPreview.new()
	root.add_child(preview)
	_check(preview.get_child_count() == 0, "in the game it loads nothing")
	await process_frame
	_check(not is_instance_valid(preview), "in the game it frees itself")


func _mesh(mesh_name: String, vmat: Variant) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	if vmat != null:
		material.set_meta("extras", {"vmat": vmat})
	mesh_instance.material_override = material
	return mesh_instance


func _remove(absolute: String) -> void:
	var dir := DirAccess.open(absolute)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for subdirectory in dir.get_directories():
		_remove(absolute.path_join(subdirectory))
	DirAccess.remove_absolute(absolute)
