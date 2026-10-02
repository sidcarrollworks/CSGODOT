shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D puff_color : source_color, filter_linear_mipmap;
uniform sampler2D puff_mask : filter_linear_mipmap;
void fragment() {
	// Current material's texture and Fresnel values; its packed mask and
	// Source 2 blend are approximated, pending the final effect shader.
	vec4 tex = texture(puff_color, UV);
	float facing = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.909091);
	ALBEDO = tex.rgb * COLOR.rgb;
	ALPHA = clamp(texture(puff_mask, UV).r * facing * 4.399, 0.0, 1.0) * COLOR.a;
	ROUGHNESS = 1.0;
}
