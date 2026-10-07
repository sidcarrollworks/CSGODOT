shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
uniform sampler2D puff_color : source_color, filter_linear_mipmap;
uniform sampler2D puff_mask : filter_linear_mipmap;
void fragment() {
	// smoke_puff_dirt.vmat (csgo_effects): the colour texture's own alpha
	// shapes the puff, its first mask breaks it up and the Fresnel terms
	// thin its silhouette. The effects shader has no lighting inputs, so
	// the puff is unlit (inferred): lit, a mirrored or shaded side drew it
	// black. Its packed masks and Source 2 blend remain approximated.
	vec4 tex = texture(puff_color, UV);
	float facing = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.909091);
	ALBEDO = tex.rgb * COLOR.rgb;
	ALPHA = clamp(tex.a * texture(puff_mask, UV).r * clamp(facing * 4.399, 0.0, 1.0) * COLOR.a, 0.0, 1.0);
}
