class_name MapSky
extends RefCounted

## The visible sky uses env_sky's brightness and linearised tint, multiplied
## by the material's exposure in stops. light_environment.skyintensity is a
## lighting input, not the visible panorama's brightness. See the sky audit.
const SHADER := preload("res://src/map/map_sky.gdshader")

## A renderer fit, not a recovered Valve parameter. The paired October 3
## T-spawn screenshot shows that applying Dust2's full authored exposure
## overshoots under our current grade. Fit the backdrop separately rather
## than changing the accepted exposure of the whole scene. Other skies
## retain their authored gain until they have paired reference captures.
const DUST2_DISPLAY_FIT := 0.75


static func entity(entities: Array[Dictionary]) -> Dictionary:
	for candidate in entities:
		if candidate.get("classname", "") != "env_sky":
			continue
		if String(candidate.get("startdisabled", "false")).to_lower() in ["true", "1"]:
			continue
		if String(candidate.get("enabled", "true")).to_lower() in ["false", "0"]:
			continue
		return candidate
	return {}


## Accept both decompiled VMAT and compiled material DATA. The latter does
## not require Source 2 Viewer to understand the installed shader version.
static func settings(sky_entity: Dictionary, vmat: String, grade: String = "cs2") -> Dictionary:
	var exposure := _float_parameter(vmat, "g_flBrightnessExposureBias")
	var render_only := _float_parameter(vmat, "g_flRenderOnlyExposureBias")
	var brightness := float(sky_entity.get("brightnessscale", "1"))
	# C_EnvSky only multiplies the tint when this value is positive.
	if brightness <= 0.0:
		brightness = 1.0
	var tint := Color.WHITE
	if sky_entity.has("tint_color"):
		var rgb := SourceEntities.vector(String(sky_entity.tint_color)) / 255.0
		tint = Color(rgb.x, rgb.y, rgb.z).srgb_to_linear()
	var material_name := String(sky_entity.get("skyname", "")).trim_prefix('resource_name:').trim_prefix('"').trim_suffix('"')
	var display_fit := DUST2_DISPLAY_FIT if material_name == "materials/skybox/sky_de_dust2.vmat" and grade == "cs2" else 1.0
	var authored_energy := brightness * pow(2.0, exposure + render_only)
	return {
		"exposure_bias": exposure, "render_only_bias": render_only,
		"brightness_scale": brightness, "tint": tint,
		"authored_energy": authored_energy, "display_fit": display_fit,
		"energy": authored_energy * display_fit,
		"lighting_energy": brightness * pow(2.0, exposure),
	}


static func material(panorama: Texture2D, values: Dictionary, lighting_energy: float = 1.0) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHADER
	result.set_shader_parameter(&"panorama", panorama)
	# Already linear: the shader's tint uniform has no source_color hint.
	result.set_shader_parameter(&"tint", Vector3(values.tint.r, values.tint.g, values.tint.b))
	result.set_shader_parameter(&"energy", values.energy)
	# Preserve the existing radiance capture used by reflections, ambient
	# lighting and fog. Visible sky exposure/tint must not change the world.
	# Translating Source 2's separate lighting-only sky remains an audit item.
	result.set_shader_parameter(&"lighting_energy", lighting_energy)
	return result


static func _float_parameter(vmat: String, parameter: String) -> float:
	var number := '([-+]?(?:[0-9]+\\.?[0-9]*|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?)'
	var decompiled := RegEx.create_from_string('"%s"\\s+"%s"' % [parameter, number]).search(vmat)
	if decompiled != null:
		return float(decompiled.get_string(1))
	var compiled := RegEx.create_from_string('m_name\\s*=\\s*"%s"\\s*;?\\s*m_flValue\\s*=\\s*%s' % [parameter, number]).search(vmat)
	return float(compiled.get_string(1)) if compiled != null else 0.0
