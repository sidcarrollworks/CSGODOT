shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_premul_alpha;
#define PREMULTIPLY_HIT_COLOR
#include "res://src/effects/hit_card.gdshaderinc"
