extends SceneTree

## Lists the colour textures a Source 2 Viewer export wrote without the alpha
## its material cuts or blends by: one line each, "ALPHA", the texture's path
## in the game (materials/...vtex) and the exported image's path, tabs
## between. scripts/extract_assets.sh decompiles those again on their own,
## which keeps the alpha, and puts them over the export's copies.
##
##   godot --headless --path . --script scripts/export_alpha.gd -- <world.gltf>
##
## The export asks the game's compiled shaders which of a texture's channels
## feed what. Source 2 Viewer 20.0 cannot read CS2's version 72 shaders, and
## without them it writes every colour texture as RGB: an alpha-cut card
## (dust2's skybox palms, bushes, antennas) draws whole. dust2's own export,
## made before CS2's update, kept all 64 of its; the skybox, exported since,
## lost all 11 (reference/asset-pipeline.md).
##
## Runs before the first import, so it names no class.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Give the world glTF's path after --.")
		quit(1)
		return
	for line in missing_alpha(args[0]):
		print("ALPHA\t" + line)
	quit(0)


## "<vtex path>\t<image path>" for each alpha-cut or translucent material
## whose exported colour image has no alpha.
static func missing_alpha(gltf_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(gltf_path))
	if not json is Dictionary:
		return out
	var directory := gltf_path.get_base_dir()
	var textures: Array = (json as Dictionary).get("textures", [])
	var images: Array = (json as Dictionary).get("images", [])
	var seen := {}
	for material: Dictionary in (json as Dictionary).get("materials", []):
		if String(material.get("alphaMode", "OPAQUE")) == "OPAQUE":
			continue
		var colour: Dictionary = (material.get("pbrMetallicRoughness", {}) as Dictionary).get("baseColorTexture", {})
		if not colour.has("index") or int(colour["index"]) >= textures.size():
			continue
		var source := int((textures[int(colour["index"])] as Dictionary).get("source", -1))
		if source < 0 or source >= images.size():
			continue
		var image_path := directory.path_join(String((images[source] as Dictionary).get("uri", "")))
		var vmat: Dictionary = (material.get("extras", {}) as Dictionary).get("vmat", {})
		var vtex := String((vmat.get("TextureParams", {}) as Dictionary).get("g_tColor", ""))
		if vtex.is_empty() or seen.has(image_path):
			continue
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		if image == null or image.detect_alpha() != Image.ALPHA_NONE:
			continue
		seen[image_path] = true
		out.append("%s\t%s" % [vtex, image_path])
	return out
