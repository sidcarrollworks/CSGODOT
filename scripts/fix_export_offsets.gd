extends SceneTree

## Undoes Source 2 Viewer's overlay offset in every extracted glTF, before
## Godot imports them. See src/map/export_offset_fix.gd for what and why.
##
##   godot --headless --path . --script scripts/fix_export_offsets.gd
##
## (scripts/extract_assets.sh and scripts/inspect_assets.sh run this for you.)
## Safe to run repeatedly: a file already corrected is left alone.

const ASSETS_DIR := "res://assets"

## By path, not by class name: this runs before the first import, which is what
## registers class names.
const Fix := preload("res://src/map/export_offset_fix.gd")


func _init() -> void:
	if not DirAccess.dir_exists_absolute(ASSETS_DIR):
		quit(0)
		return

	var gltfs := PackedStringArray()
	_walk(ASSETS_DIR, gltfs)
	for gltf in gltfs:
		var moved: int = Fix.fix_file(gltf)
		if moved > 0:
			print("overlay offsets: %s, %d vertices put back" % [gltf.get_file(), moved])
	quit(0)


func _walk(dir_path: String, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir_path):
		if file.get_extension().to_lower() == "gltf":
			out.append(dir_path.path_join(file))
	for subdirectory in DirAccess.get_directories_at(dir_path):
		_walk(dir_path.path_join(subdirectory), out)
