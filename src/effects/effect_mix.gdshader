shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

// An effect quad blended over what is behind it, as smoke is
// (effect_quad.gdshaderinc).

#include "res://src/effects/effect_quad.gdshaderinc"
