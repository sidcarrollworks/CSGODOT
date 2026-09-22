extends SceneTree

## Puts right the things in a Source 2 Viewer export that have to be right
## before Godot imports it, in every extracted glTF:
##
##   - overlays and depth-biased geometry pushed 15.5 units off their walls
##     (src/map/export_offset_fix.gd);
##   - the blend paint, in a vertex attribute Godot drops
##     (src/map/export_paint_channel.gd).
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
	quit(0)


func _walk(dir_path: String, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir_path):
		if file.get_extension().to_lower() == "gltf":
			out.append(dir_path.path_join(file))
	for subdirectory in DirAccess.get_directories_at(dir_path):
		_walk(dir_path.path_join(subdirectory), out)
