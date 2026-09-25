// What CS2's prop shaders add to a surface that the glTF has no slot for,
// after Source 2 Viewer's ApplyDecalTexture (texturing.slang) and
// GetStandardSelfIllumination (complex.frag.slang): a decal texture over
// the colour (F_DECAL_TEXTURE: the dirt down dust2's kasbah towers) and
// self-illumination (F_SELF_ILLUM: the tunnels' hanging lamps). Set from
// the material's description by LightmapMaterials.carry_features; at their
// defaults neither does anything.

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
