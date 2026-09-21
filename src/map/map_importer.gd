class_name MapImporter
extends Node3D

## Turns a glTF exported from Source 2 Viewer into something you can walk
## around in.
##
## The export is a pile of meshes, textures and materials with no collision
## shapes, no lighting and no nav mesh. This builds the collision and reports
## what it found, because what it finds is the thing nobody can tell you in
## advance: which materials mark collision geometry, what scale the export
## came out at, and whether it is Y-up.
##
## Nothing here assumes a particular answer. The first run prints an inventory
## and a bounding box; those two numbers settle the scale and up-axis
## questions in one look, and the material list settles the collision one.

signal import_finished(stats: Dictionary)

## Path to the exported glTF. Under res:// if the editor has imported it,
## otherwise it is loaded straight off disk.
@export_file("*.gltf", "*.glb") var source_path: String = ""

## Source 2 exports at Source scale, which is what this project uses, so this
## should be 1. If the bounding box below comes out wrong by a constant factor,
## this is the knob.
@export var scale_factor: float = 1.0

## glTF is Y-up and Source is Z-up, and the exporter is supposed to convert.
## If the map arrives lying on its side, turn this on.
@export var rotate_z_up_to_y_up: bool = false

enum CollisionSource {
	## Use collision-marked meshes if there are any, otherwise every mesh.
	AUTO,
	## Only meshes whose material matches collision_material_hints.
	COLLISION_MESHES_ONLY,
	## Every mesh, collision-marked or not.
	ALL_MESHES,
}

@export var collision_source: CollisionSource = CollisionSource.AUTO

## Material name fragments that mark geometry as collision: solid but not
## drawn. These are a starting guess; the inventory printed on the first import
## is what tells you the real names.
@export var collision_material_hints: PackedStringArray = PackedStringArray([
	"collision", "clip", "nodraw", "invisible", "trigger",
])

## Material name fragments to drop entirely, drawn or not.
@export var skip_material_hints: PackedStringArray = PackedStringArray([
	"skybox", "skydome",
])

## Print the inventory on import. Worth leaving on until the map is settled.
@export var report: bool = true

## Filled in by import(). Also delivered by the import_finished signal.
var stats: Dictionary = {}


## Finds the first glTF under a directory, at any depth, and returns it as a
## res:// path. Uses the real filesystem underneath because extracted content
## is gitignored and may not have been imported by the editor yet.
##
## Nothing hardcodes the exported filename: Source 2 Viewer's output layout
## changes between releases, so the first glTF found wins.
static func find_map_file(res_dir: String) -> String:
	var absolute := ProjectSettings.globalize_path(res_dir)
	var found := _first_gltf(absolute)
	if found.is_empty():
		return ""
	return res_dir.path_join(found.trim_prefix(absolute).trim_prefix("/"))


static func _first_gltf(dir_path: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var entry := dir.get_next()
	var subdirectories: Array[String] = []
	while entry != "":
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				subdirectories.append(full)
			elif entry.ends_with(".gltf") or entry.ends_with(".glb"):
				dir.list_dir_end()
				return full
		entry = dir.get_next()
	dir.list_dir_end()

	for subdirectory in subdirectories:
		var found := _first_gltf(subdirectory)
		if not found.is_empty():
			return found
	return ""


func _ready() -> void:
	if source_path.is_empty():
		return
	import_map()


## Loads the glTF, builds collision, and returns the stats dictionary. Safe to
## call again; the previously imported geometry is discarded first.
func import_map() -> Dictionary:
	for child in get_children():
		child.queue_free()

	var scene := _load_scene(source_path)
	if scene == null:
		stats = {"error": "could not load %s" % source_path}
		_report_missing()
		import_finished.emit(stats)
		return stats

	add_child(scene)
	scene.scale = Vector3.ONE * scale_factor
	if rotate_z_up_to_y_up:
		scene.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(scene, meshes)

	var materials := {}
	var collision_meshes: Array[MeshInstance3D] = []
	var visible_meshes: Array[MeshInstance3D] = []
	var skipped := 0

	for mesh_instance in meshes:
		var names := _material_names(mesh_instance)
		for name in names:
			materials[name] = int(materials.get(name, 0)) + 1

		if _matches_any(names, skip_material_hints):
			mesh_instance.visible = false
			skipped += 1
			continue

		if _matches_any(names, collision_material_hints):
			collision_meshes.append(mesh_instance)
			# Collision geometry is not meant to be seen.
			mesh_instance.visible = false
		else:
			visible_meshes.append(mesh_instance)

	var targets := _collision_targets(collision_meshes, visible_meshes)
	var triangles := 0
	for mesh_instance in targets:
		triangles += _build_collision(mesh_instance)

	stats = {
		"meshes": meshes.size(),
		"collision_marked": collision_meshes.size(),
		"visible": visible_meshes.size(),
		"skipped": skipped,
		"collision_bodies": targets.size(),
		"collision_triangles": triangles,
		"materials": materials,
		"bounds": _bounds(meshes, scale_factor),
	}

	if report:
		_print_report()
	import_finished.emit(stats)
	return stats


## Which meshes get collision, given what the map actually contained.
func _collision_targets(
	collision_meshes: Array[MeshInstance3D],
	visible_meshes: Array[MeshInstance3D]
) -> Array[MeshInstance3D]:
	match collision_source:
		CollisionSource.COLLISION_MESHES_ONLY:
			return collision_meshes
		CollisionSource.ALL_MESHES:
			return collision_meshes + visible_meshes
		_:
			# Auto. A map that ships real collision geometry should use it and
			# nothing else, because visual geometry is not a collision hull.
			# A map that does not has to fall back on what it has.
			if not collision_meshes.is_empty():
				return collision_meshes
			return visible_meshes


func _load_scene(path: String) -> Node3D:
	# Fast path: the editor has already imported it, so use the native scene.
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			return packed.instantiate() as Node3D

	# Otherwise read the file directly, which works the moment extraction
	# finishes without waiting for an editor import pass.
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(absolute, state)
	if error != OK:
		push_error("glTF load failed for %s (error %d)" % [path, error])
		return null
	return document.generate_scene(state) as Node3D


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _material_names(mesh_instance: MeshInstance3D) -> PackedStringArray:
	var names := PackedStringArray()
	var mesh := mesh_instance.mesh
	for surface in mesh.get_surface_count():
		var material := mesh_instance.get_active_material(surface)
		if material == null:
			continue
		var name := material.resource_name
		if name.is_empty():
			name = material.resource_path.get_file()
		if not name.is_empty():
			names.append(name)
	if names.is_empty():
		names.append(mesh_instance.name)
	return names


func _matches_any(names: PackedStringArray, hints: PackedStringArray) -> bool:
	for name in names:
		var lowered := name.to_lower()
		for hint in hints:
			if lowered.contains(hint.to_lower()):
				return true
	return false


## Attaches a static trimesh collider. Trimesh is right here: map geometry is
## static and concave, and a convex decomposition of dust2 would both take
## forever and round off exactly the corners that movement is judged on.
func _build_collision(mesh_instance: MeshInstance3D) -> int:
	var shape := mesh_instance.mesh.create_trimesh_shape()
	if shape == null:
		return 0

	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	mesh_instance.add_child(body)

	return shape.get_faces().size() / 3


func _bounds(meshes: Array[MeshInstance3D], factor: float) -> AABB:
	var result := AABB()
	var first := true
	for mesh_instance in meshes:
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	result.position *= factor
	result.size *= factor
	return result


func _print_report() -> void:
	var bounds: AABB = stats["bounds"]
	print("--- map import: %s" % source_path)
	print("    meshes %d (collision-marked %d, visible %d, skipped %d)" % [
		stats["meshes"], stats["collision_marked"],
		stats["visible"], stats["skipped"],
	])
	print("    collision: %d bodies, %d triangles" % [
		stats["collision_bodies"], stats["collision_triangles"],
	])
	print("    bounds: %.0f x %.0f x %.0f units, centred near (%.0f, %.0f, %.0f)" % [
		bounds.size.x, bounds.size.y, bounds.size.z,
		bounds.get_center().x, bounds.get_center().y, bounds.get_center().z,
	])
	print("    (dust2 should be a few thousand units across. If it is a few")
	print("     dozen, or a few hundred thousand, set scale_factor.)")

	var materials: Dictionary = stats["materials"]
	var names := materials.keys()
	names.sort()
	print("    %d distinct materials:" % names.size())
	for name in names:
		print("      %s (%d surfaces)" % [name, materials[name]])


func _report_missing() -> void:
	push_warning(
		"Map not imported: %s is not there yet. "
		% source_path
		+ "Run scripts/extract_assets.sh map on a machine with CS2 installed."
	)
