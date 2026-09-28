// What CS2's prop shaders add to a surface that the glTF has no slot for,
// after Source 2 Viewer's ApplyDecalTexture (texturing.slang),
// GetStandardSelfIllumination and its tinting (complex.frag.slang): the
// tint only where the tint mask is white (F_TINT_MASK: the paint on
// dust2's window frames, doors and awnings, not their chips, bare wood and
// hinges), csgo_environment's model tint, which recolours instead of
// multiplying (its ColorizeTint: dust2's tarp on xbox), a decal texture
// over the colour (F_DECAL_TEXTURE: the dirt down
// dust2's kasbah towers) and self-illumination (F_SELF_ILLUM: the tunnels'
// hanging lamps). Set from the material's description by
// LightmapMaterials.carry_features; at their defaults none does anything.

// The draw call's tint, which Source 2 Viewer's export bakes into the
// glTF's base colour and carry_features moves here, and the mask saying
// where it goes (red, 1 for all of it). White for none.
uniform vec4 tint_color : source_color = vec4(1.0);
uniform sampler2D tint_mask : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool tint_on_uv2 = false;

// csgo_environment's model tint (LightmapMaterials.carry_model_tint): the
// tint, how much of it, and the mask (green, g_tHeight1) with its contrast
// and brightness. An amount of 0 for none.
uniform vec3 colorize_tint : source_color = vec3(1.0);
uniform float colorize_amount = 0.0;
uniform sampler2D colorize_mask : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 colorize_mask_adjust = vec2(1.0);

uniform sampler2D decal_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// -1 none; 0 laid over by its alpha, 1 multiplied in (F_DECAL_BLEND_MODE).
uniform int decal_mode = -1;
uniform bool decal_on_uv2 = false;
uniform sampler2D self_illum_mask : hint_default_black, filter_linear_mipmap, repeat_enable;
// 2 to the brightness, times the scale and the tint, in Godot's units (the
// lightmap's energy); black for none.
uniform vec3 self_illum_color = vec3(0.0);
uniform float self_illum_albedo_factor = 0.0;
uniform bool self_illum_on_uv2 = false;

// Source 2 Viewer's ColorizeTint: the tint's hue at the colour's luma
// (BT.709), no brighter than 3 * luma * the tint's brightest channel, so a
// dark tint cannot brighten it; its ContrastBrightness on the mask.
vec3 prop_colorize(vec3 albedo, vec2 uv) {
	if (colorize_amount <= 0.0) {
		return albedo;
	}
	float mask = texture(colorize_mask, uv).g;
	mask = clamp(((mask - 0.5) * colorize_mask_adjust.x + 0.5) * colorize_mask_adjust.y, 0.0, 1.0);
	const vec3 LUMA = vec3(0.2125, 0.7154, 0.0721);
	vec3 hue = normalize(max(colorize_tint, vec3(0.001)));
	float luma = dot(albedo, LUMA);
	float tinted = min(luma / dot(hue, LUMA), 3.0 * luma * max(max(colorize_tint.r, colorize_tint.g), colorize_tint.b));
	return clamp(mix(albedo, hue * tinted, colorize_amount * mask), 0.0, 1.0);
}

// CS2's form: 1 - mask * (1 - tint), which is mix(1, tint, mask). The
// model tint of csgo_environment first, which the export also baked in.
vec3 prop_tint(vec3 albedo, vec2 uv, vec2 uv2) {
	albedo = prop_colorize(albedo, uv);
	if (tint_color == vec4(1.0)) {
		return albedo;
	}
	float mask = texture(tint_mask, tint_on_uv2 ? uv2 : uv).r;
	return albedo * mix(vec3(1.0), tint_color.rgb, mask);
}

vec3 prop_decal(vec3 albedo, vec2 uv, vec2 uv2) {
	if (decal_mode < 0) {
		return albedo;
	}
	vec4 decal = texture(decal_texture, decal_on_uv2 ? uv2 : uv);
	return decal_mode == 0 ? mix(albedo, decal.rgb, decal.a) : albedo * decal.rgb;
}

vec3 prop_self_illum(vec3 albedo, vec2 uv, vec2 uv2) {
	if (self_illum_color == vec3(0.0)) {
		return vec3(0.0);
	}
	float mask = texture(self_illum_mask, self_illum_on_uv2 ? uv2 : uv).r;
	return self_illum_color * mask * mix(vec3(1.0), albedo, self_illum_albedo_factor);
}
