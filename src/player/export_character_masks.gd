class_name ExportCharacterMasks
extends RefCounted

## Readies the player models' cloth masks for Godot's import: each agent
## material's metalness texture (g_tMetalness), which
## scripts/extract_assets.sh character-masks decompiles under TEXTURES_DIR,
## by the path the material names it by, and whose blue channel says where
## the material is cloth (CharacterMaterials).
##
## Its alpha is CS2's rim mask, which nothing here draws. Godot's import
## paints the colour of the nearest opaque texel into every texel that is
## nearly transparent (process/fix_alpha_border, on by default, meant for
## cut-out colour), which would paint over the cloth and metal masks
## wherever the rim mask is clear. So the alpha is dropped before the import
## sees it, which also halves what the texture takes in video memory (DXT1
## rather than DXT5).
##
## The eyes' colour textures (g_tEyeAlbedo1) carry the iris in their alpha,
## clear over the white of the eye, which the same import would paint over
## with the iris's colour. So the alpha is moved into a greyscale file of its
## own beside it (IRIS_SUFFIX), which the shader reads as the iris.
##
## Run by scripts/prepare_export.gd on every glTF, before the first import
## has registered any class names, so it names none.

const TEXTURES_DIR := "res://assets/characters"
## Where under TEXTURES_DIR the agents' glTFs are.
const AGENTS_DIR := "agents"

## The file the eye colour's alpha, the iris, is moved into: its name with
## this after it.
const IRIS_SUFFIX := "_iris"

const _MASK := "\"g_tMetalness\"\\s*:\\s*\"([^\"]+)\""
const _EYE := "\"g_tEyeAlbedo1\"\\s*:\\s*\"([^\"]+)\""


## Drops the alpha from the metalness textures an agent's glTF names, and
## moves the eye colours' into their iris files, where they have been
## decompiled. Returns how many were rewritten: 0 for a glTF that is not an
## agent's, and when it was done already.
static func fix_file(gltf_path: String, textures_dir: String = TEXTURES_DIR) -> int:
	if not gltf_path.begins_with(textures_dir.path_join(AGENTS_DIR) + "/"):
		return 0
	var text := FileAccess.get_file_as_string(gltf_path)
	var rewritten := 0
	for vtex: String in _named(_MASK, text):
		if drop_alpha(textures_dir.path_join(vtex.get_basename() + ".png")):
			rewritten += 1
	for vtex: String in _named(_EYE, text):
		if split_iris(textures_dir.path_join(vtex.get_basename() + ".png")):
			rewritten += 1
	return rewritten


## The textures a glTF names for one parameter, each once.
static func _named(pattern: String, text: String) -> Array:
	var named := {}
	for found in RegEx.create_from_string(pattern).search_all(text):
		named[found.get_string(1)] = true
	return named.keys()


## Moves an eye colour's alpha, the iris, into a greyscale PNG beside it
## (IRIS_SUFFIX), and rewrites it without; an alpha all opaque is an iris
## everywhere. Returns whether it did: not where the iris file is there
## already, or the colour is not.
static func split_iris(png_path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(png_path)
	var iris_path := absolute.get_basename() + IRIS_SUFFIX + ".png"
	if not FileAccess.file_exists(absolute) or FileAccess.file_exists(iris_path):
		return false
	var image := Image.load_from_file(absolute)
	if image == null:
		return false
	image.convert(Image.FORMAT_RGBA8)
	var rgba := image.get_data()
	var alpha := PackedByteArray()
	alpha.resize(rgba.size() / 4)
	for i in alpha.size():
		alpha[i] = rgba[i * 4 + 3]
	var iris := Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_L8, alpha)
	if iris.save_png(iris_path) != OK:
		push_warning("Could not write the iris of %s." % png_path)
		return false
	drop_alpha(png_path)
	return true


## Rewrites a PNG without its alpha, if it has one that is not all opaque.
## Returns whether it did.
static func drop_alpha(png_path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(png_path)
	if not FileAccess.file_exists(absolute):
		return false
	var image := Image.load_from_file(absolute)
	if image == null or image.detect_alpha() == Image.ALPHA_NONE:
		return false
	image.convert(Image.FORMAT_RGB8)
	if image.save_png(absolute) != OK:
		push_warning("Could not write %s without its alpha." % png_path)
		return false
	return true
