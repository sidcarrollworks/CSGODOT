class_name UnlitMaterials
extends RefCounted

## CS2's csgo_unlitgeneric materials, drawn unlit and blended as the game
## draws them. Source 2 Viewer's glTF export has no unlit or additive
## material, so it writes one opaque and lit, with the draw's tint as its
## colour and, since it cannot read CS2's version 72 shaders, its colour
## texture without the alpha (scripts/export_alpha.gd). The clouds over
## dust2's 3D skybox came out as an opaque, sunlit sheet across the sky,
## which CS2's grade showed as dark slate grey
## (reference/playtest-2026-09-25.md, issue 24).
##
## What CS2 does, from its own files and public sources:
## - The shader calls itself "(S1) unlit/unlittwotexture shader for CSGO",
##   and names F_BLEND_MODE's values Opaque, Translucent, Alpha Test, Mod2x,
##   Additive, Multiply and ModThenAdd (csgo_unlitgeneric_vulkan_50_features.vcs
##   in csgo_core's shaders_vulkan_dir.vpk, read with Source 2 Viewer's
##   -b DATA on 2026-09-28). Source 2 Viewer's renderer blends Additive by
##   the source's alpha onto what is there (RenderMaterial.cs: SrcAlpha, One).
## - Source 1's UnlitTwoTexture multiplies its two textures and its
##   modulation colour, alpha too (Source SDK 2013's UnlitTwoTexture.psh and
##   unlittwotexture_ps2x.fxc).
## - The tint is the draw's, the object's tint times g_vColorTint, which the
##   export writes as the colour factor: albedo_color here.
##
## Only the Additive blend is built, the one blend on the maps extracted so
## far (dust2's skybox clouds, nuke_clouds_002). A material under another is
## left as imported, and so are the texture coordinates' own transforms
## (g_vTexCoordScale and the rest), the identity on that material.
##
## Both textures come from under the map's materials/ directory, where
## scripts/extract_assets.sh layers fetches them with their alpha. Until it
## has, a mesh drawn only by such materials is hidden: as imported it is the
## opaque sheet, and what it would add is faint (the clouds' alpha averages
## 11 of 255 in one texture and 56 in the other).

const SHADER_NAME := "csgo_unlitgeneric.vfx"
## F_BLEND_MODE's Additive, fifth of the shader's names for it.
const ADDITIVE := 4
const ADD_SHADER := preload("res://src/map/unlit_add.gdshader")


## Puts every csgo_unlitgeneric surface of these meshes on its unlit
## material, and hides a mesh drawn only by additive ones whose textures are
## not on disk. textures_dir is where extract_assets.sh put the map's
## materials/ directory. Returns {"surfaces": surfaces switched over,
## "hidden": meshes hidden, "left": names of the materials not built}.
static func apply(meshes: Array[MeshInstance3D], textures_dir: String) -> Dictionary:
	var built := {}  # imported material -> its unlit material, or null
	var surfaces := 0
	var hidden := 0
	var left := {}
	for mesh_instance in meshes:
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var waiting := 0  # additive surfaces whose textures are not there
		for surface in mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			var description := BlendMaterials.vmat(material)
			if not is_unlit(description):
				continue
			if not built.has(material):
				built[material] = build(material, textures_dir)
			if built[material] != null:
				mesh_instance.set_surface_override_material(surface, built[material])
				surfaces += 1
				continue
			left[material.resource_name] = true
			if blend_mode(description) == ADDITIVE:
				waiting += 1
		if waiting > 0 and waiting == mesh.get_surface_count():
			mesh_instance.visible = false
			hidden += 1
	var names := PackedStringArray(left.keys())
	names.sort()
	return {"surfaces": surfaces, "hidden": hidden, "left": names}


static func is_unlit(description: Dictionary) -> bool:
	return String(description.get("ShaderName", "")) == SHADER_NAME


static func blend_mode(description: Dictionary) -> int:
	var flags: Variant = description.get("IntParams", {})
	return int((flags as Dictionary).get("F_BLEND_MODE", 0)) if flags is Dictionary else 0


static func two_textures(description: Dictionary) -> bool:
	var flags: Variant = description.get("IntParams", {})
	return flags is Dictionary and int((flags as Dictionary).get("F_TWOTEXTURE", 0)) == 1


## The unlit material standing in for one imported material, or null if its
## blend is not built or its textures are not there to be had.
static func build(material: BaseMaterial3D, textures_dir: String) -> ShaderMaterial:
	var description := BlendMaterials.vmat(material)
	if not is_unlit(description) or blend_mode(description) != ADDITIVE:
		return null
	var textures: Variant = description.get("TextureParams", {})
	if not textures is Dictionary:
		return null
	var colour := BlendMaterials.load_texture(textures_dir, (textures as Dictionary).get("g_tColor", ""))
	var colour2: Texture2D = null
	if two_textures(description):
		colour2 = BlendMaterials.load_texture(textures_dir, (textures as Dictionary).get("g_tColor2", ""))
		if colour2 == null:
			return null
	if colour == null:
		return null

	var unlit := ShaderMaterial.new()
	unlit.shader = ADD_SHADER
	unlit.resource_name = material.resource_name
	unlit.set_shader_parameter("color_texture", colour)
	if colour2 != null:
		unlit.set_shader_parameter("color2_texture", colour2)
	unlit.set_shader_parameter("tint", material.albedo_color)
	# Kept for whoever reads the material later, the collision classifier included.
	unlit.set_meta("extras", material.get_meta("extras", {}))
	return unlit
