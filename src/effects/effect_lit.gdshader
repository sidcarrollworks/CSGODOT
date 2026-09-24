shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, diffuse_lambert, specular_disabled;

// An effect card lit by the scene's sun and ambient, blended over what is
// behind it, as CS2 lights its muzzle smoke (a tenth of it self-lit, the
// rest from the scene; effect_quad.gdshaderinc).

#define LIT
#include "res://src/effects/effect_quad.gdshaderinc"
