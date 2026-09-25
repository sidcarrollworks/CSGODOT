@tool
class_name MapPreview
extends Node3D

## Shows an extracted map's geometry in the editor's 3D view, so a scene
## that plays a map (maps/de_dust2/de_dust2.tscn) has the map to look at
## while it is being edited.
##
## The game builds the map only when it runs (MapLoader, from PlayScene's
## _ready), so without this the scene is an empty Node3D in the editor. This
## draws the world glTF scripts/extract_assets.sh wrote, as exported: its own
## materials, without the blend layers, lightmaps, sky, skybox or collision
## the game adds, and without the tool and effect surfaces the game leaves
## out. The meshes are not owned by the scene, so they are never saved into
## it and never appear in the scene tree; in the game this node frees itself
## before anything is loaded.

## The map to show, as CS2 names it; empty for the map_name of the node
## this is under (PlayScene's).
@export var map_name: String = "":
	set(value):
		map_name = value
		_rebuild()

## Load the map again, after an extraction or an import has changed it.
@export_tool_button("Reload map") var reload := _rebuild

## What was shown, or why nothing was; for the checks.
var status: String = ""


func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
		return
	_rebuild()


func _rebuild() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	for child in get_children():
		if child.owner == null:
			remove_child(child)
			child.queue_free()
	var shown := shown_map()
	var scene := load_world(shown)
	if scene == null:
		status = "%s: not extracted (scripts/extract_assets.sh map %s)" % [shown, shown]
		return
	scene.name = "Preview"
	add_child(scene)
	var hidden := hide_unseen(scene)
	status = "%s: shown, %d surfaces left out" % [shown, hidden]


## The map this shows: its own map_name, or the parent's.
func shown_map() -> String:
	if not map_name.is_empty():
		return map_name
	var parent_map: Variant = get_parent().get("map_name") if get_parent() != null else null
	if parent_map is String and not (parent_map as String).is_empty():
		return parent_map
	return "de_dust2"


## The map's world geometry at the game's scale, as MapImporter loads it
## (Godot's import when the editor has made one, else the glTF itself);
## null when it has not been extracted.
static func load_world(shown: String) -> Node3D:
	if not MapPaths.is_valid_name(shown):
		return null
	var path := MapImporter.find_map_file(MapPaths.of(shown).map_dir)
	if path.is_empty():
		return null
	var scene: Node3D = null
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			scene = packed.instantiate() as Node3D
	if scene == null:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
			return null
		scene = document.generate_scene(state) as Node3D
	if scene == null:
		return null
	# The export's sun, as MapImporter takes it out: left in, the editor
	# turns off its own preview sun, which lights the view better.
	for light in scene.find_children("*", "Light3D", true, false):
		light.get_parent().remove_child(light)
		light.free()
	scene.scale = Vector3.ONE * MapImporter.SOURCE2_VIEWER_SCALE
	return scene


## Hides what the game never draws, the same surfaces MapImporter skips:
## materials under materials/tools/ or materials/effects/ (clips, triggers,
## nodraw) and the sky dome. Returns how many meshes it hid.
static func hide_unseen(node: Node) -> int:
	var hidden := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			var extras: Variant = material.get_meta("extras", {}) if material != null else {}
			var vmat: Variant = (extras as Dictionary).get("vmat", {}) if extras is Dictionary else {}
			if not vmat is Dictionary:
				continue
			var vmat_path := String((vmat as Dictionary).get("Name", ""))
			if (vmat_path.begins_with("materials/tools/")
					or vmat_path.begins_with("materials/effects/")
					or String((vmat as Dictionary).get("ShaderName", "")).begins_with("sky")):
				mesh_instance.visible = false
				hidden += 1
				break
	for child in node.get_children():
		hidden += hide_unseen(child)
	return hidden
