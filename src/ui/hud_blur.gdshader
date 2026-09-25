shader_type canvas_item;

// The world behind a HUD panel, blurred, as Panorama's world-blur draws it
// (csgostyles.css hudWorldBlur): what a shape drawn with this material shows
// is the screen under it read from a blurred level of Godot's screen mip
// chain, its drawn alpha kept as its edge. HudElement copies only the part
// of the screen under its panels first (a BackBufferCopy), and puts this
// under the panel's own dark tint.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
// Which level of the chain at the 1920x1080 base size: each is half the size
// of the one before, blurred. A bigger window reads a level further down, so
// the blur reaches as far across the HUD at any size.
uniform float level = 4.0;

void fragment() {
	float scale = log2(max(1.0 / SCREEN_PIXEL_SIZE.y / 1080.0, 0.25));
	COLOR = vec4(textureLod(screen_texture, SCREEN_UV, level + scale).rgb, COLOR.a);
}
