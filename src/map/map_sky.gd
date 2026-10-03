class_name MapSky
extends RefCounted

## The visible sky uses env_sky's brightness and linearised tint, multiplied
## by the material's exposure in stops. light_environment.skyintensity is a
## lighting input, not the visible panorama's brightness. See the sky audit.
const SHADER := preload("res://src/map/map_sky.gdshader")


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
static func settings(sky_entity: Dictionary, vmat: String) -> Dictionary:
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
	return {
		"exposure_bias": exposure, "render_only_bias": render_only,
		"brightness_scale": brightness, "tint": tint,
		"energy": brightness * pow(2.0, exposure + render_only),
		"lighting_energy": brightness * pow(2.0, exposure),
	}


static func material(panorama: Texture2D, values: Dictionary) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHADER
	result.set_shader_parameter(&"panorama", panorama)
	# Already linear: the shader's tint uniform has no source_color hint.
	result.set_shader_parameter(&"tint", Vector3(values.tint.r, values.tint.g, values.tint.b))
	result.set_shader_parameter(&"energy", values.energy)
	result.set_shader_parameter(&"lighting_energy", values.lighting_energy)
	return result


static func _float_parameter(vmat: String, parameter: String) -> float:
	var number := '([-+]?(?:[0-9]+\\.?[0-9]*|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?)'
	var decompiled := RegEx.create_from_string('"%s"\\s+"%s"' % [parameter, number]).search(vmat)
	if decompiled != null:
		return float(decompiled.get_string(1))
	var compiled := RegEx.create_from_string('m_name\\s*=\\s*"%s"\\s*;?\\s*m_flValue\\s*=\\s*%s' % [parameter, number]).search(vmat)
	return float(compiled.get_string(1)) if compiled != null else 0.0
