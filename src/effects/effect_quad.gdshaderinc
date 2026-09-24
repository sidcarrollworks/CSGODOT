// What every effect quad draws with (EffectQuads): one flat card per
// instance of a MultiMesh, placed and turned to face the camera on the CPU,
// its texture's rectangle (a sprite sheet's frame) in INSTANCE_CUSTOM and
// its colour, alpha and overbright in the instance colour.
//
// Unshaded, as CS2's flames, tracers and sparks are (self-illumination 1);
// no fog, which would add its colour to what is added. The lit variant
// (effect_lit.gdshader, for smoke) takes the scene's light, a tenth of its
// colour its own. A batch drawn in
// first person takes the view model's projection (player_draw.gdshaderinc),
// so a flash sits on the drawn muzzle as the gun does. A streak's colour
// can run from its head (the card's top) to its tail, as CS2's trails'
// head and tail colour scales do, set per batch.

#include "res://src/player/player_draw.gdshaderinc"

uniform sampler2D effect_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 head_tint : source_color = vec4(1.0);
uniform vec4 tail_tint : source_color = vec4(1.0);

varying float along;

void vertex() {
	along = UV.y;
	UV = mix(INSTANCE_CUSTOM.xy, INSTANCE_CUSTOM.zw, UV);
	POSITION = view_model_clip_position((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, PROJECTION_MATRIX);
}

void fragment() {
	vec4 texel = texture(effect_texture, UV) * COLOR * mix(head_tint, tail_tint, along);
	ALBEDO = texel.rgb;
	ALPHA = texel.a;
#ifdef LIT
	// CS2's smoke's self-illumination: 0.1 for most, 0 to 0.15 for the rest.
	EMISSION = texel.rgb * 0.1;
	ROUGHNESS = 1.0;
#endif
}

#ifdef LIT
// A puff is lit from whichever side the light is on, as a particle is, not
// only on the face it turns to the camera: each light counts as if half
// facing it, shadows kept.
void light() {
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * 0.5 / PI;
}
#endif
