shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// The glass of the AUG's and SG 553's scopes, which CS2 draws clear: the
// world is seen through it at the scope's field of view, with no more than
// a faint tint (reference/research/scopes.md). Drawn as the arms are
// (player_draw.gdshaderinc), so it sits in the scope as drawn.

#include "res://src/player/player_draw.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.62, 0.68, 0.66, 0.06);

void vertex() {
	POSITION = view_model_clip_position((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, PROJECTION_MATRIX);
}

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
