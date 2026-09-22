extends SceneTree

## Puts right the things in a Source 2 Viewer export that have to be right
## before Godot imports it, in every extracted glTF:
##
##   - overlays and depth-biased geometry pushed 15.5 units off their walls
##     (src/map/export_offset_fix.gd);
##   - the blend paint, in a vertex attribute Godot drops
##     (src/map/export_paint_channel.gd);
##   - the lightmap's average light, measured once for the ambient of what
##     the lightmap does not cover (src/map/lightmap_materials.gd).
##
##   godot --headless --path . --script scripts/prepare_export.gd
##
## (scripts/extract_assets.sh and scripts/inspect_assets.sh run this for you.)
## Safe to run repeatedly: each fix leaves alone what it has already done.

const ASSETS_DIR := "res://assets"

## By path, not by class name: this runs before the first import, which is what
## registers class names.
const OffsetFix := preload("res://src/map/export_offset_fix.gd")
const PaintChannel := preload("res://src/map/export_paint_channel.gd")
const Lightmaps := preload("res://src/map/lightmap_materials.gd")


func _init() -> void:
	if not DirAccess.dir_exists_absolute(ASSETS_DIR):
		quit(0)
		return

	var gltfs := PackedStringArray()
	_walk(ASSETS_DIR, gltfs)
	for gltf in gltfs:
		var moved: int = OffsetFix.fix_file(gltf)
		if moved > 0:
			print("overlay offsets: %s, %d vertices put back" % [gltf.get_file(), moved])
		var painted: int = PaintChannel.fix_file(gltf)
		if painted > 0:
			print("blend paint: %s, %d primitives' paint kept as vertex colour" % [gltf.get_file(), painted])
		_measure_lightmap(gltf.get_base_dir())
	quit(0)


## The lightmap's average, once per map that has one.
func _measure_lightmap(map_dir: String) -> void:
	var exr: String = map_dir.path_join(Lightmaps.IRRADIANCE_FILE)
	if not FileAccess.file_exists(exr) or FileAccess.file_exists(map_dir.path_join(Lightmaps.AVERAGE_FILE)):
		return
	print("lightmap average: reading %s (a few hundred megabytes)" % exr.get_file())
	var image := Image.load_from_file(ProjectSettings.globalize_path(exr))
	if image == null:
		return
	var average: Color = Lightmaps.measure_average(image)
	Lightmaps.write_average(map_dir, average)
	print("lightmap average: (%.3f, %.3f, %.3f) written to %s" % [average.r, average.g, average.b, Lightmaps.AVERAGE_FILE])


func _walk(dir_path: String, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir_path):
		if file.get_extension().to_lower() == "gltf":
			out.append(dir_path.path_join(file))
	for subdirectory in DirAccess.get_directories_at(dir_path):
		_walk(dir_path.path_join(subdirectory), out)
