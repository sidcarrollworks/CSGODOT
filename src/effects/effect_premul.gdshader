shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_premul_alpha;

// An effect quad blended premultiplied, as CS2's BLEND_ADD halos are
// (effect_quad.gdshaderinc).

#include "res://src/effects/effect_quad.gdshaderinc"
