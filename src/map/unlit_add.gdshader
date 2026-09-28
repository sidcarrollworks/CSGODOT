shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded, shadows_disabled, fog_disabled;

// CS2's csgo_unlitgeneric under its Additive blend (F_BLEND_MODE 4): the
// clouds over dust2's 3D skybox. Unlit, its colour times its alpha added to
// what is behind it, and no fog, as the effects that add are drawn; the
// material's own g_bFogEnabled is 0 besides. The colour is its two textures
// and the draw's tint multiplied, colour and alpha alike, as Source 1's
// UnlitTwoTexture, which the shader says it is, multiplies them. What each
// value is, and where it was read, is in UnlitMaterials.

uniform sampler2D color_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D color2_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 colour = texture(color_texture, UV) * texture(color2_texture, UV) * tint;
	ALBEDO = colour.rgb;
	ALPHA = colour.a;
}
