shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_add;

// An effect quad blended by adding, as flames, tracers and sparks are
// (effect_quad.gdshaderinc).

#include "res://src/effects/effect_quad.gdshaderinc"
