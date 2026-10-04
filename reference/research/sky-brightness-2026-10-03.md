# Sky brightness audit, 2026-10-03

The Dust2 reference images (`reference/cs2 _screenshots/dust2_t_spawn_1.webp`,
`dust2_tspawn_2.webp` and `dust2_cat.webp`) show a brighter sky than our
panorama render. The material exposure was omitted, but applying its full
gain overshoots under our current grade. A paired T-spawn comparison now
supplies a separate backdrop fit. Complete colour-grade parity remains open.

## Extracted values and current executable

Dust2's `materials/skybox/sky_de_dust2.vmat` specifies
`g_flBrightnessExposureBias = 0.765` and `g_flRenderOnlyExposureBias = 0`.
Its active `env_sky` has `brightnessscale = 1` and white `tint_color`.
The authored visible gain is therefore `2^0.765 = 1.6993708` before grading.
Previously `MapLighting` used the sun entity's `skyintensity = 0.960784`
and ignored both material biases and the sky entity's brightness/tint.
The uncalibrated change from the previous gain is about 77% in linear light.
`MapSky.DUST2_DISPLAY_FIT = 0.75` reduces the gain to 1.2745281 for this
material under the CS2 grade only before world-exposure compensation,
about 33% above the old gain. This is a
measured renderer calibration, not a recovered Valve constant. Other
materials and the ACES comparison keep a fit of 1.

Mirage's material DATA sets both biases to zero, with a white, unit-brightness
sky entity. It keeps a gain of 1; Dust2's adjustment is not applied to it.
Both EXR imports have `process/hdr_as_srgb = false`, so an extra gamma
conversion of the extracted HDR image is not appropriate.
Re-exporting the currently installed Dust2 texture produced an EXR with the
same SHA-256 as our September 21 export:
`68113bcff514f94e938114147b62656fe3c0b60a0f3085c4028f44d22fa71622`.
The current material DATA also retains the same 0.765-stop bias.

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

The shader samples the existing panorama once. Its visible pass uses the
authored gain, linear tint and separate backdrop fit. Its cubemap pass keeps
the previous panorama's `light_environment.skyintensity` and white tint,
so changing the backdrop does not replace the lighting/reflection/fog
capture. A separate authored `sky_lightingonly_name` and its tint remain
unimplemented. Baked lightmaps, probes, sun energy and the grade's curve/LUT
are retained. The subsequent world-exposure refinement is documented below.

The earlier mid-door previews incorrectly saved linear HDR viewport pixels
directly to PNG. Their quoted RGB values were linear, despite being labelled
display RGB, and the previews looked too dark. They are not visual-match
evidence. The corrected capture reads the viewport's RGB half-float pixels
and applies the sRGB transfer curve before PNG quantization, as the display
does. The imported scene-linear sky texture itself is not gamma-adjusted.

The paired October 3 captures use the user's T-spawn feet
`(-1163.7, 77.8, -299.7)`, yaw 270.2, pitch 11.8, at 3840×2160.
The player settles to y 77.79156. The upper sky patch covers normalized
x 0.56–0.70, y 0.09–0.20, avoiding the CS2 reference's grid and HUD.
Mean display RGB, on a 0–255 scale:

| Patch | Previous renderer | Full authored gain | Fitted backdrop | CS2 reference |
|---|---|---|---|---|
| Upper blue sky | 107.34, 156.76, 196.60 | 143.85, 202.65, 247.97 | 124.10, 178.50, 221.77 | 120.45, 178.71, 222.73 |
| Central sky (x 0.56–0.70, y 0.28–0.35) | 149.11, 173.80, 193.26 | 195.49, 222.89, 244.25 | 171.30, 197.04, 218.10 | 164.84, 195.69, 219.60 |

During the sky-only adjustment, relative to the previous renderer, the
fitted backdrop changed mean display
channels by at most 0.28/255 in a shaded wall patch (x 0.15–0.24,
y 0.55–0.60), 0.16/255 in sunlit plaster (x 0.61–0.65, y 0.54–0.60)
and 1.03/255 in shaded ground (x 0.85–0.90, y 0.89–0.94). These bound
the observed change at this view; they do not prove all materials and views
are identical. Sky bloom can still spill onto nearby screen pixels.

The right-hand clouds are still too bright/blue relative to this reference.
Existing world hue differences also remain. There are no Mirage reference
images in this folder for a visual match, so Dust2's fits are not applied
to Mirage.

## World exposure refinement after the sky comparison

The user approved the fitted sky and asked for brighter reflected light on
the buildings. Four captures at the same T-spawn camera compared world
exposure fits of 1.2, 1.35, 1.5 and 1.65. Each inversely scaled the visible
sky gain to retain its exposed input; its lighting/reflection/fog cubemap
gain stayed at 0.960784. All are renderer calibration trials, not extracted
Valve exposure settings.

`MapLighting.DUST2_EXPOSURE_FIT = 1.5` is selected by the map's
`worldspawn.worldname = de_dust2`, versus the previous 1.2. This is 25% more
scene exposure, or about +0.322 stops. Other maps and unidentified fixtures
retain 1.2, and ACES retains its prior exposure. The map's own exposure window
and exposure bias continue to apply. No light, shader pass or per-frame
script is added.

Mean linear luminance from matching display patches, using the sRGB transfer
curve and Rec.709 weights (0.2126, 0.7152, 0.0722):

| Patch | Previous world fit 1.2 | Chosen fit 1.5 | CS2 reference |
|---|---|---|---|
| Shaded wall (x 0.15–0.24, y 0.55–0.60) | 0.1304 | 0.1666 | 0.1652 |
| Sunlit plaster (x 0.61–0.65, y 0.54–0.60) | 0.5133 | 0.6323 | 0.6559 |
| Temple facade (x 0.86–0.94, y 0.425–0.48) | 0.5818 | 0.7174 | 0.6862 |

The shaded wall is within 1% of the reference, sunlit plaster within 4% and
the temple within 5%. At 1.65 the wall overshoots to 0.1853 and the temple
to 0.7775. At 1.5 the sampled plaster has no pixels with all channels at or
above 254/255; the temple has 0.019%, versus 0.232% at 1.65. This measures
white clipping, not individual-channel clipping or detail throughout the map.

The approved sky's gain is multiplied by 1.2/1.5 = 0.8, yielding 1.019622
in the shader. Multiplying by the new world fit gives the same exposed sky
input as 1.274528 at 1.2. The upper and central sky patch means change by
less than 0.5/255 per channel in the probe captures; brighter world bloom
still spills slightly into nearby sky pixels. `ColourGrade.use` restores
the corresponding sky gain when switching between CS2 and ACES, so the
running grade comparison is reversible.

These measurements establish a closer match at this camera, not a match
throughout Dust2. Local hue differences, the right-hand clouds, exposure
adaptation and deeper interior lighting remain open.

The map-mode checks cover both material formats, disabled-sky selection,
the two maps' authored gains, Dust2-only display fitting, tint conversion,
neutral defaults and preservation of the lighting capture's gain.
The grade suite checks Dust2/Mirage exposure selection, invariant exposed
sky input, unchanged sun/radiance energy and both directions of a grade swap.
Map and grade suites exercise the existing environment setup. Graphical
captures verified that the sky shader compiles and draws with Vulkan.
