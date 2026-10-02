# Hit cards and particle timing

Read on 2026-10-02 alongside the current installed CS2 impact definitions
and textures listed in [blood and impacts](blood-and-impacts.md).
PR #172 merged on 2026-10-02. This page describes the implemented
renderer and its remaining Source 2 approximations;
[the effects fixture](hit-effects-performance-2026-10-02.md) measures its
CPU/GPU costs separately from competitive play.

`HitQuads` prepares one MultiMesh/material batch per texture, motion texture,
blend and gradient while the map loads. Per-card data contains the current
flat frame index, next frame index, interpolation fraction and alpha
threshold. `SpriteSheet.frame()` keeps its existing discrete-frame contract;
the new interpolation and metadata APIs are additive.

The atlas lookup uses each frame's own UV rectangle. Timed sequences retain
their per-frame durations and zero-duration endpoint frames. A clamped
sequence holds its final frame; a looping one interpolates its final frame
back into the first. The secondary forward-spray renderer pairs five static
smoke sequences with three animated flow sequences. A common 15-sequence
timeline preserves each texture's independent sequence wrapping.

[Source 2 Viewer's particle shader](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/master/Renderer/Shaders/particle_spritecard.frag.slang)
reads signed flow from **green and alpha**, not red and green. The motion
sampler therefore has no sRGB conversion. Current and next images are
warped by opposite portions of that flow and blended. Samples remain
inside their respective atlas rectangles. Gradient replacement uses the
image's gamma-space luminance to select the authored colour palette.
MIX_RGBA lookup reads premultiplied source RGB; MIX_RGB lookup reads its
plain RGB. REPLACE keeps the ramp colour and source alpha, while MULTIPLY
composes the ramp with the source RGB and alpha. GPU checks distinguish
those operations rather than treating all palettes as replacements.

The [texture header](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/master/ValveResourceFormat/Resource/ResourceTypes/Texture.cs)
and [texture-layer renderer](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/master/Renderer/Particles/Renderers/ParticleTextureLayer.cs)
describe maximum motion displacement in atlas pixels. The current blood
top motion texture declares a one-pixel maximum. Its forward-spray
renderers override scales with -8 and -16. Applying these overrides in the
same pixel units is an **inference**: their engine-side override path is
not established by the texture header alone.

Alpha-to-zero is a continuous coverage remap, `(alpha-threshold) /
(1-threshold)`, bounded to 0–1. It is independent of the particle's alpha
fade. The low/medium/high blood roots compute CP4.x from distance 128–1024u
to 0.2–0.85. Children inherit this control point; the interpreter updates
it against the current eye before draw and sends its value per card.
Other impacts have separate authored distance remaps, commonly CP6.
The client-side assignment of control-point positions remains inferred;
the numeric remap and child inheritance are read from the files.

`HitParticles` evaluates the generated float descriptors by their input
type, including particle age in seconds, normalized age, particle number,
scalar attributes and CP components. Manual animation uses the authored
frame curve, with its replace/scale-initial/add-initial set method. Fixed
rate uses seconds and fit-lifetime uses normalized age; the FPS option
also divides by the sheet's effective display time. This follows the
[shared renderer's frame selection](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/master/Renderer/Particles/Renderers/ParticleFunctionRenderer.cs).
Draw-time playback only reads the prewarmed `SpriteSheet._loaded` cache;
it does not call `named()` for unresolved assets.

Operator radius bias uses the rational Source curve. Float-map biased
inputs use a separate -1–1 parameter, with standard/gain/exponential
choices, following [ParticleMath](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/master/ValveResourceFormat/Particles/Utils/ParticleMath.cs).
Random fades use smoothstep, while simple fade-out is linear. Combined
fade-and-kill uses its normalized start/end windows and start/end alpha.
The generated table retains these settings. Curve knots are still
piecewise linear here: the generated descriptors retain x/y points, but
not the source spline tangents.

Velocity noise with `PT_TYPE_INVALID` stays in Source world space instead
of turning with the impact axis. The normal's explicit CP velocity keeps
its local alignment. Exported model coordinates are Source `(y,z,x)`;
reversing that permutation gives flecks their intended axes. The exported
Rush Hour puff nodes have identity transforms and their native +Y vertices
all extend above the impact plane. `orient_z=true` therefore aligns native
+Y with the impact normal and rolls around that extrusion axis.

Sid's playtest override doubles off-body blood mist particle counts and
halves their sampled lifetimes. It applies to blood layers containing
`mist`, excluding local/screen reactions. Layer capacities scale with the
counts, while the shared 512-particle budget remains. Extracted source
values are unchanged. This is deliberate project tuning, not a claim
about CS2's authored density or duration.

His subsequent hit-location tuning also clamps the initial body-mist
offset to one Source unit around the per-pellet event contact point.
Velocity still spreads from there. Head, chest and arm contacts are tested
at separate positions, so this never substitutes the model's centre.
Other normal-offset operators retain their authored tangent/normal frame;
the impact puff's `[0,0,10]` offset moves ten units out along the normal.

The current renderer still omits multi-layer breakup composition, the
second sequence/material-age shader paths, and Source's spatial age/velocity
noise lattice. Noise velocities use samples within their authored ranges;
age noise is not reconstructed. Closed game-side control-point and root
selection remain the separate approximations recorded in the impact page.

Local checks: 34 hit-card checks pass on both Forward+ Vulkan (RTX 4070 Ti)
and Compatibility OpenGL, including actual pixels for frame interpolation,
motion channels, gradients, continuous alpha coverage, additive and
premultiplied blending. 84 particle checks cover real generated roots and
sprite/trail/model draw paths, descriptor evaluation, mist tuning/expiry,
world noise axes and puff orientation. The authored flinch pose checks are
recorded separately in [body flinches](body-flinches.md). Material identity
keys are interned canonical strings on private renderer copies prepared at
startup, avoiding per-card gradient hashing and hash-only aliasing.
Timed sequences also cache cumulative frame ends and use binary search.
Attribute operations, static renderer inputs, growth/fade settings and
drag constants are prepared or sampled before draw. The checks compare
prepared evaluation with the uncached public evaluators on actual blood
and world-impact particles.

The explicit group-0 plaster chooser selects one child. Its duplicated
cheap child entries retain their weight, rather than opening all three
entries together. Blood's omitted chooser group remains the separately
documented parent-death approximation.
