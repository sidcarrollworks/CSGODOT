# Sky brightness audit, 2026-10-03

The Dust2 reference images (`reference/cs2 _screenshots/dust2_t_spawn_1.webp`,
`dust2_tspawn_2.webp` and `dust2_cat.webp`) show a brighter sky than our
panorama render. The missing material exposure is one concrete cause.
This fixes that input; it does not establish complete colour-grade parity.

## Extracted values and current executable

Dust2's `materials/skybox/sky_de_dust2.vmat` specifies
`g_flBrightnessExposureBias = 0.765` and `g_flRenderOnlyExposureBias = 0`.
Its active `env_sky` has `brightnessscale = 1` and white `tint_color`.
The correct visible gain is therefore `2^0.765 = 1.6993708` before grading.
Previously `MapLighting` used the sun entity's `skyintensity = 0.960784`
and ignored both material biases and the sky entity's brightness/tint.
The change from the previous gain is about 77% in linear light.

Mirage's material DATA sets both biases to zero, with a white, unit-brightness
sky entity. It keeps a gain of 1; Dust2's adjustment is not applied to it.
Both EXR imports have `process/hdr_as_srgb = false`, so an extra gamma
conversion of the extracted HDR image is not appropriate.

Ghidra was run against the installed October 2 CS2 client, version 1.41.8.8,
build 2000924. Its SHA-256 is
`d7db25d48f1d10c5e0b0296e20ed803426eb9509da41760daeda39dd35ba89b9`.
The earlier client database has relocated calls, so the current DLL was
imported into a separate project for this audit.

| Address in current Windows client.dll | Observation |
|---|---|
| `0x18026cd80` | The entity field registration maps `skyname`, `tint_color` and `brightnessscale` to sky material `+0x1098`, byte tint `+0x10ac` and float brightness `+0x10b4`. A separate lighting-only material/tint is registered too. |
| `0x1802820f0` | `C_EnvSky`'s scene-object update converts the byte tint to linear RGB, then multiplies it by brightness when the brightness is positive. Non-positive brightness leaves the tint unscaled. |
| `0x181746f20` | The tint conversion divides bytes by 255 and uses the piecewise sRGB transfer curve (threshold 0.04045, divisor 12.92, offset 0.055 and divisor 1.055). |
| `0x180230750` | The cubemap-fog setup reads the sky texture and both named exposure biases from the material; its multiplier includes `pow(2, brightness bias) * pow(2, render-only bias)` and sky entity brightness/tint. This corroborates the visible sky inputs, rather than identifying the GPU shader itself. |

The public [Source 2 Viewer sky shader](https://github.com/ValveResourceFormat/ValveResourceFormat/blob/master/Renderer/Shaders/sky.frag.slang)
also applies `exp2` of the two biases and the scene tint to the decoded HDR
texel. It is a reimplementation, not Valve's shader source.
[Godot's panorama material](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/3d/sky_material.cpp)
samples `SKY_COORDS` with a `source_color` sampler, then multiplies the
result by its energy. Our replacement keeps that sampling behaviour and
adds the linear tint and authored gain.

## Implementation and validation

`MapSky` accepts both the older decompiled VMAT and original material DATA,
including signed/scientific float notation. The same active sky entity
selects the texture and supplies brightness/tint. Disabled sky entities
are skipped. All settings are read once while loading the map.

The shader samples the existing panorama once. Its cubemap pass excludes
the render-only bias from Godot's sky lighting/reflection capture. That is
our mapping of the parameter's render-only role; a separate authored
`sky_lightingonly_name` and its tint are not implemented. Both tested maps
have zero render-only bias, so this distinction does not alter their result.
The existing baked lightmaps, probes, sun energy and global exposure fit
are retained.

Before/after Dust2 renders used the same mid-door camera at 1920×1080.
The sky patch (x 1300–1749, y 50–199) changed from mean display RGB
`(0.2079, 0.4199, 0.6198)` to `(0.3934, 0.7355, 0.9976)`.
A sunlit wall patch (x 1550–1699, y 450–549) stayed within 0.002 per display
channel. These are our own render measurements, not a measured match to
CS2. Some sky colours still differ from the references; exposure adaptation,
grade differences and sky orientation remain candidates for a paired audit.
There are no Mirage reference images in this folder for a visual match.

The map-mode checks cover both material formats, disabled-sky selection,
the two maps' gains, tint conversion, neutral defaults and shader inputs.
Map and grade suites exercise the existing environment setup. Graphical
captures verified that the sky shader compiles and draws with Vulkan.
