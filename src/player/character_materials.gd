class_name CharacterMaterials
extends RefCounted

## What CS2's character shader (csgo_character) reads of a player model's
## material that the glTF export leaves out, handed to character.gdshader:
## where the material is cloth and how its sheen is coloured, and how far
## its occlusion darkens the direct light.
##
## ProbeMaterials puts every material CS2 draws with that shader on
## character.gdshader, lit by the map's light probes, so the players, the
## bots and your own arms in first person all take it. A model lit by a
## world of its own instead (RigModel.probe_lit false: the buy menu's agent)
## is put on it here, lit by that world's environment (use_environment).
##
## The cloth mask is the blue channel of the material's metalness texture
## (g_tMetalness), which the export reads only the green of, for the
## metalness in its ORM texture. So it is decompiled on its own
## (scripts/extract_assets.sh character-masks), under TEXTURES_DIR by the
## path the material names it by, and readied for the import there
## (ExportCharacterMasks). A material that asks for cloth shading without
## its mask there is shaded as it was, with GGX, and says so once.
##
## A material that draws eyes (F_EYEBALLS) names the eye's colour
## (g_tEyeAlbedo1, its alpha the iris) and where on the model the eyes are
## (g_tEyeMask1), which the export leaves out too and the same step
## decompiles; ExportCharacterMasks moves the colour's alpha into a file of
## its own. With both there, the material gets them and its eye parameters,
## and each model aims its own copy of it (CharacterEyes). Without them it
## keeps the white eyes the colour texture paints, and says so once.

const SHADER := preload("res://src/player/character.gdshader")
## The shader CS2 draws its agents and their arms with.
const SHADER_NAME := "csgo_character.vfx"
## The texture whose blue channel is the cloth mask.
const MASKS := "g_tMetalness"
const TEXTURES_DIR := ExportCharacterMasks.TEXTURES_DIR
## Where a model's bounce light comes from, per mesh: 1 the map's probes,
## 0 its world's environment.
const AMBIENT_FROM_PROBES := &"ambient_from_probes"
## CS2's own default for a material that leaves it out (Source 2 Viewer's
## texturing.slang).
const SHEEN_SCALE := 0.667
## The eye's colour, its alpha the iris, and where on the model the eyes are.
const EYE_ALBEDO := "g_tEyeAlbedo1"
const EYE_MASK := "g_tEyeMask1"
## The eye parameters handed to the shader, by CS2's name, with CS2's
## defaults (Source 2 Viewer's csgo_character_eyes_ps.slang and _vs.slang).
const EYE_PARAMS := {
	"g_flEyeBallRadius1": ["eye_radius", 0.0],
	"g_flEyeIrisSize1": ["eye_iris_size", 1.0],
	"g_flEyePupilSize1": ["eye_pupil_size", 0.0],
	"g_flEyeHueShift1": ["eye_hue_shift", 0.0],
	"g_flEyeSaturation1": ["eye_saturation", 1.0],
}
## How far each eye turns outward from where the two look, in degrees
## (g_flEyeBallWalleyeL1 and ...R1), kept on the material for CharacterEyes,
## which aims them: left, right.
const WALLEYE := &"eye_walleye"

## The masks found missing, each said once.
static var _missing := {}


## Whether CS2 draws a material, by its description (BlendMaterials.vmat),
## with its character shader.
static func is_character(description: Dictionary) -> bool:
	return String(description.get("ShaderName", "")) == SHADER_NAME


## Whether the material asks for cloth shading (F_CLOTH_SHADING).
static func wants_cloth(description: Dictionary) -> bool:
	return int((description.get("IntParams", {}) as Dictionary).get("F_CLOTH_SHADING", 0)) != 0


## Whether the material draws eyes (F_EYEBALLS).
static func wants_eyes(description: Dictionary) -> bool:
	return int((description.get("IntParams", {}) as Dictionary).get("F_EYEBALLS", 0)) != 0


## Where the material's cloth mask is decompiled to under textures_dir; ""
## for a material that names none.
static func mask_file(description: Dictionary, textures_dir: String = TEXTURES_DIR) -> String:
	var vtex: Variant = (description.get("TextureParams", {}) as Dictionary).get(MASKS, "")
	if not vtex is String or (vtex as String).is_empty():
		return ""
	return textures_dir.path_join((vtex as String).get_basename() + ".png")


## The sheen's tint (g_flSheenTintColor), which the material gives in sRGB,
## in linear light; white where it gives none.
static func sheen_tint(description: Dictionary) -> Color:
	var tint: Variant = (description.get("VectorParams", {}) as Dictionary).get("g_flSheenTintColor")
	if tint is Array and (tint as Array).size() >= 3:
		return Color(float(tint[0]), float(tint[1]), float(tint[2])).srgb_to_linear()
	return Color.WHITE


## Hands a material on character.gdshader what its description asks of it:
## the occlusion on the direct light, and, where it asks for cloth shading,
## the mask from textures_dir with the sheen's scale and tint.
static func carry(lit: ShaderMaterial, description: Dictionary, textures_dir: String = TEXTURES_DIR) -> void:
	var floats: Dictionary = description.get("FloatParams", {})
	lit.set_shader_parameter("direct_diffuse_occlusion", float(floats.get("g_flAmbientOcclusionDirectDiffuse", 1.0)))
	lit.set_shader_parameter("direct_specular_occlusion", float(floats.get("g_flAmbientOcclusionDirectSpecular", 1.0)))
	if wants_eyes(description):
		_carry_eyes(lit, description, textures_dir)
	if not wants_cloth(description):
		return
	var mask := BlendMaterials.load_texture(textures_dir, (description.get("TextureParams", {}) as Dictionary).get(MASKS))
	if mask == null:
		var path := mask_file(description, textures_dir)
		if not _missing.has(path):
			_missing[path] = true
			push_warning(
				"%s asks for cloth shading, but its cloth mask %s is not there, so it is shaded as before;"
				% [description.get("Name", "A material"), path if not path.is_empty() else "(none named)"]
				+ " scripts/extract_assets.sh character-masks extracts the agents' masks."
			)
		return
	lit.set_shader_parameter("cloth_shading", true)
	lit.set_shader_parameter("cloth_mask", mask)
	lit.set_shader_parameter("sheen_scale", float(floats.get("g_flSheenScale", SHEEN_SCALE)))
	var tint := sheen_tint(description)
	lit.set_shader_parameter("sheen_tint", Vector3(tint.r, tint.g, tint.b))


## Where a material's eye texture (EYE_ALBEDO or EYE_MASK) is decompiled to
## under textures_dir, and the eye colour's iris beside it (iris true); ""
## for a material that names none.
static func eye_file(description: Dictionary, param: String, iris: bool = false, textures_dir: String = TEXTURES_DIR) -> String:
	var vtex: Variant = (description.get("TextureParams", {}) as Dictionary).get(param, "")
	if not vtex is String or (vtex as String).is_empty():
		return ""
	return textures_dir.path_join((vtex as String).get_basename() + (ExportCharacterMasks.IRIS_SUFFIX if iris else "") + ".png")


## The eye's colour, iris and mask, and its parameters, for a material that
## draws eyes; nothing, said once, where the textures are not there.
static func _carry_eyes(lit: ShaderMaterial, description: Dictionary, textures_dir: String) -> void:
	var textures: Dictionary = description.get("TextureParams", {})
	var albedo := BlendMaterials.load_texture(textures_dir, textures.get(EYE_ALBEDO))
	var mask := BlendMaterials.load_texture(textures_dir, textures.get(EYE_MASK))
	var iris: Texture2D = null
	var iris_vtex: Variant = textures.get(EYE_ALBEDO)
	if iris_vtex is String and not (iris_vtex as String).is_empty():
		iris = BlendMaterials.load_texture(
			textures_dir, (iris_vtex as String).get_basename() + ExportCharacterMasks.IRIS_SUFFIX + ".vtex"
		)
	if albedo == null or mask == null or iris == null:
		var path := eye_file(description, EYE_ALBEDO, false, textures_dir)
		if not _missing.has(path):
			_missing[path] = true
			push_warning(
				"%s draws eyes, but its eye textures (%s, its iris, and %s) are not all there, so its eyes stay white;"
				% [
					description.get("Name", "A material"), path if not path.is_empty() else "(none named)",
					eye_file(description, EYE_MASK, false, textures_dir),
				]
				+ " scripts/extract_assets.sh character-masks extracts them."
			)
		return
	lit.set_shader_parameter("eyes", true)
	lit.set_shader_parameter("eye_albedo", albedo)
	lit.set_shader_parameter("eye_iris", iris)
	lit.set_shader_parameter("eye_mask", mask)
	var floats: Dictionary = description.get("FloatParams", {})
	for param: String in EYE_PARAMS:
		lit.set_shader_parameter(EYE_PARAMS[param][0], float(floats.get(param, EYE_PARAMS[param][1])))
	lit.set_meta(WALLEYE, Vector2(float(floats.get("g_flEyeBallWalleyeL1", 0.0)), float(floats.get("g_flEyeBallWalleyeR1", 0.0))))


## Puts a mesh's character surfaces on character.gdshader lit by its world's
## environment, not the map's probes, for a model that stands in a world of
## its own; its other surfaces are left as they are. Returns whether any
## moved.
static func use_environment(mesh: MeshInstance3D) -> bool:
	if mesh.mesh == null:
		return false
	var moved := false
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface)
		if material is BaseMaterial3D and is_character(BlendMaterials.vmat(material)):
			mesh.set_surface_override_material(surface, ProbeMaterials.build(material as BaseMaterial3D))
			moved = true
	if moved:
		mesh.set_instance_shader_parameter(AMBIENT_FROM_PROBES, 0.0)
	return moved


## Lights a mesh's character surfaces from the map's probes after all,
## where use_environment had them take the environment's light.
static func use_probes(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null:
		return
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(surface)
		if material is ShaderMaterial and is_character(BlendMaterials.vmat(material)):
			mesh.set_instance_shader_parameter(AMBIENT_FROM_PROBES, 1.0)
			return
