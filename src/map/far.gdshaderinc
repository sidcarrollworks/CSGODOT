// Depth squeezed against the far plane, for what is drawn behind everything.
//
// The fragment keeps a thousandth of its distance from the far plane, so
// the parts of a far scene still sort among themselves while anything of
// the near scene, at any depth, lands in front. Which end of the buffer is
// far depends on the renderer: Forward+ and Mobile reverse it (far is 0),
// Compatibility does not (far is 1); the material is told.

uniform float far_plane_depth = 0.0;
const float FAR_DEPTH_KEEP = 0.001;

float far_depth(float depth) {
	return far_plane_depth + (depth - far_plane_depth) * FAR_DEPTH_KEEP;
}
