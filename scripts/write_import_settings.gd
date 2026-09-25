extends SceneTree

## Sets the import settings of every extracted texture, before Godot imports
## them, and the import script of the weapons' models
## (weapon_model_import.gd).
##
##   godot --headless --path . --script scripts/write_import_settings.gd
##
## (scripts/extract_assets.sh and scripts/inspect_assets.sh run this for you.)
##
## Left alone, Godot imports a PNG as a lossless 2D texture with no mipmaps,
## and relies on the editor noticing it being drawn in 3D to switch it over to
## VRAM compression. That never happens here: the import is headless and the map
## is only ever instanced by the running game. dust2 is about 650 textures and
## 800 megapixels, which is 4 GB of video memory uncompressed and 1 GB
## compressed, and without mipmaps every distant wall shimmers.
##
## The sky panorama comes as an .exr and gets the same treatment; VRAM
## compression of an HDR image is BC6H, which is what a sky wants.
##
## Godot keeps a texture's settings in a .import file next to it, and reimports
## when that file changes, so this writes those. Only [params] is touched; an
## existing file keeps its uid. Safe to run repeatedly: a file that is already
## right is not rewritten, and so is not reimported.

const ASSETS_DIR := "res://assets"

const VRAM_COMPRESSED := 2
const NORMAL_MAP_ENABLED := 1
const NORMAL_MAP_DISABLED := 2
const ROUGHNESS_DISABLED := 1
const DETECT_3D_DISABLED := 0
## The lightmap of baked shadows (MapShadows), which is not a colour.
const SHADOW_MASK := "direct_light_shadows"
## The weapons' and kit's models, imported through weapon_model_import.gd,
## which leaves out the second body a gun carries for legacy skins.
const WEAPON_MODELS_DIR := "res://assets/weapons/weapons/models"
const WEAPON_MODEL_IMPORT := "res://scripts/weapon_model_import.gd"


func _init() -> void:
	if not DirAccess.dir_exists_absolute(ASSETS_DIR):
		quit(0)
		return

	var textures := PackedStringArray()
	var gltfs := PackedStringArray()
	_walk(ASSETS_DIR, textures, gltfs)

	# Which images are normal maps is a fact about the materials, not the
	# filenames: 24 of dust2's 168 normal maps do not have "normal" in the name.
	var normal_maps := {}
	for gltf in gltfs:
		_collect_normal_maps(gltf, normal_maps)

	var updated := 0
	for texture in textures:
		if _apply(texture, normal_maps.has(texture)):
			updated += 1

	print("texture import settings: %d textures (%d normal maps), %d updated" % [
		textures.size(), normal_maps.size(), updated,
	])

	var models := 0
	var models_updated := 0
	for gltf in gltfs:
		if gltf.begins_with(WEAPON_MODELS_DIR + "/"):
			models += 1
			if _apply_import_script(gltf, WEAPON_MODEL_IMPORT):
				models_updated += 1
	print("weapon model import script: %d models, %d updated" % [models, models_updated])
	quit(0)


func _walk(dir_path: String, textures: PackedStringArray, gltfs: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir_path):
		var extension := file.get_extension().to_lower()
		if extension in ["png", "jpg", "jpeg", "exr", "hdr"]:
			textures.append(dir_path.path_join(file))
		elif extension == "gltf":
			gltfs.append(dir_path.path_join(file))
	for subdirectory in DirAccess.get_directories_at(dir_path):
		# What Godot will not import needs no settings (the light probes).
		if FileAccess.file_exists(dir_path.path_join(subdirectory).path_join(".gdignore")):
			continue
		_walk(dir_path.path_join(subdirectory), textures, gltfs)


func _collect_normal_maps(gltf_path: String, out: Dictionary) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(gltf_path))
	if not parsed is Dictionary:
		push_warning("Could not read %s as JSON; its normal maps will not be flagged." % gltf_path)
		return
	var gltf: Dictionary = parsed
	var images: Array = gltf.get("images", [])
	var gltf_textures: Array = gltf.get("textures", [])

	for material: Dictionary in gltf.get("materials", []):
		if not material.has("normalTexture"):
			continue
		var texture_index := int(material["normalTexture"].get("index", -1))
		if texture_index < 0 or texture_index >= gltf_textures.size():
			continue
		var image_index := int(gltf_textures[texture_index].get("source", -1))
		if image_index < 0 or image_index >= images.size():
			continue
		var uri: String = images[image_index].get("uri", "")
		if uri.is_empty() or uri.begins_with("data:"):
			continue
		out[gltf_path.get_base_dir().path_join(uri.uri_decode()).simplify_path()] = true


## Returns true if the .import file had to be written.
func _apply(texture_path: String, is_normal_map: bool) -> bool:
	var wanted := {
		"compress/mode": VRAM_COMPRESSED,
		"compress/normal_map": NORMAL_MAP_ENABLED if is_normal_map else NORMAL_MAP_DISABLED,
		"mipmaps/generate": true,
		"roughness/mode": ROUGHNESS_DISABLED,
		"detect_3d/compress_to": DETECT_3D_DISABLED,
	}
	if texture_path.get_file().get_basename() == SHADOW_MASK:
		# Each channel is a different light's shadow, which the default
		# compression (DXT) squeezes onto one line of colours per block and
		# so smears one light's edge into another's; BC7 keeps them apart.
		# An unused channel reads as transparent, and the alpha border fix
		# would paint the others' values over it.
		wanted["compress/high_quality"] = true
		wanted["process/fix_alpha_border"] = false

	var import_path := texture_path + ".import"
	var config := ConfigFile.new()
	var dirty := false
	if config.load(import_path) != OK:
		# Not imported yet. This much is enough for Godot to take the settings
		# from here; it fills in the rest, uid included, when it imports.
		config.set_value("remap", "importer", "texture")
		config.set_value("remap", "type", "CompressedTexture2D")
		config.set_value("deps", "source_file", texture_path)
		dirty = true

	for key: String in wanted:
		if (
			not config.has_section_key("params", key)
			or config.get_value("params", key) != wanted[key]
		):
			config.set_value("params", key, wanted[key])
			dirty = true

	if dirty and config.save(import_path) != OK:
		push_error("Could not write %s" % import_path)
		return false
	return dirty


## Sets a glTF's import script, keeping its other settings. Returns true if
## the .import file had to be written (and so the model is imported again).
func _apply_import_script(gltf_path: String, script_path: String) -> bool:
	var import_path := gltf_path + ".import"
	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		# Not imported yet: Godot fills in the rest when it imports.
		config.set_value("remap", "importer", "scene")
		config.set_value("remap", "type", "PackedScene")
		config.set_value("deps", "source_file", gltf_path)
	elif config.get_value("params", "import_script/path", "") == script_path:
		return false
	config.set_value("params", "import_script/path", script_path)
	if config.save(import_path) != OK:
		push_error("Could not write %s" % import_path)
		return false
	return true
