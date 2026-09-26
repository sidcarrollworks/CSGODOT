# CS2's post-processing: how a frame is graded

Research for issue 10 of `reference/playtest-2026-09-25.md` (our colour
grade is more saturated and contrasty than CS2's) and the first part of
`reference/rendering.md` R0. Written 2026-09-26 from public sources only;
Valve's leaked source was not used. What `ColourGrade` and
`MapPostProcessing` build from it is at the end.

## Sources

- **VRF**: Source 2 Viewer (ValveResourceFormat), commit `f3ad9fb`
  (2026-09-25): `Renderer/Shaders/post_processing.frag.slang`,
  `Renderer/Renderer/SceneEnvironment/ScenePostProcessVolume.cs`,
  `Renderer/Renderer/PostProcess/PostProcessRenderer.cs`, `BloomRenderer.cs`,
  `downsample_bloomthreshold.frag.slang`,
  `ValveResourceFormat/Resource/ResourceTypes/PostProcessing.cs` and
  `IO/Extract/FileExtract.cs`. A reimplementation that draws CS2's maps, not
  Valve's code: where it guesses, it says so in its comments, and this page
  repeats those.
- **GT**: SteamDatabase's GameTracking-CS2, commit `3fc98e7` (2026-09-25,
  build 2000918): `DumpSource2/convars.txt`, the schemas
  `DumpSource2/schemas/materialsystem2/PostProcessingResource_t.h` (and the
  parameter structs beside it), and `game/core/postprocessing.fgd`. CS2's
  own files, current.
- **Godot**: Godot 4.7.2-stable's source,
  `servers/rendering/renderer_rd/shaders/effects/tonemap.glsl`,
  `renderer_scene_render_rd.cpp` and `drivers/gles3/shaders/effects/post.glsl`.

## 1. What a vpost holds (GT schema, current)

`PostProcessingResource_t`: flags and parameters for a tone map
(`m_toneMapParams`), bloom, vignette, local contrast, fog scattering and
local exposure, and a colour-correction volume (`m_nColorCorrectionVolumeDim`,
an RGBA8 blob). The tone map's struct has, beyond Source 2 Viewer's eight
numbers (`m_flExposureBias` in stops, shoulder, linear strength and angle,
toe strength, numerator and denominator, white point), seven more:
`m_flLuminanceSource`, `m_flExposureBiasShadows`, `m_flExposureBiasHighlights`
and four shadow and highlight luminance limits. VRF does not use them ("The
following params aren't used, I think?"), and nothing public says what they
do; `ColourGrade` leaves them out. If dust2's file sets them away from 0,
that is a gap to look at.

Every other layer an artist stacks in the editor (brightness and contrast,
colour lookups; GT's `postprocessingeditor` icons) is baked into the one
colour table when the file is compiled (VRF: "All other layers are compiled
into a 3D lookup table").

Source 2 Viewer decompiles a `.vpost_c` (`-d`) to KV3 text,
`CPostProcessData` with one layer each for the tone map, the bloom and the
table, the table both inline as floats and as a `.raw` file beside it (8-bit
RGB, red fastest). `-b DATA` prints the compiled fields instead.
`MapPostProcessing` reads both.

## 2. The order a frame is graded in (VRF)

1. The scene times the exposure (`g_flToneMapScalarLinear`, auto exposure
   below) and times 2^`m_flExposureBias`.
2. Bloom: added, mixed ("blur") or, after step 5, screened.
3. Times **2.8**, clamped at 2.8 W (`TonemapSettings.PreTonemapScale`).
4. The Hable curve, `(x(Ax + CB) + DE) / (x(Ax + B) + DF) - E/F`, divided by
   its value at 2.8 W.
5. To sRGB, the exact piecewise curve (`SrgbLinearToGamma`).
6. The table, sampled on its texel centres (`x * 31/32 + 1/64` for 32), with
   weight 1.
7. `pow(x, gamma / 2.2)`, 1 at the default 2.2, and a blue-noise dither of
   2/255.

The **2.8** was not on the playtest page, which put the scene straight into
the curve. With it, VRF's default curve shows scene-linear 0.05, 0.1, 0.2,
0.5 and 1.0 as sRGB 65, 90, 121, 168 and 203, against Godot's ACES (as we
use it) at 60, 103, 158, 224 and 255: the default curve lifts the darkest
shade a little and holds the light well below ACES, which is what Sid saw
(lighter shade, less contrast). The page is corrected.

## 3. Exposure

- The volume (`post_processing_volume`, GT fgd) has `enableexposure`
  (default on), `minexposure` and `maxexposure` (a linear scale, defaults
  0.25 and 8), `exposurecompensation` in stops, `exposurespeedup`,
  `exposurespeeddown`, `exposuresmoothingrange`, and `master`.
- VRF's auto exposure aims the frame's average luminance at the scene value
  the curve shows as middle grey (0.18), clamps that to the window, and
  moves toward it in log2 at the speed up or down a second. The
  compensation multiplies afterwards. It notes its history weighting may be
  wrong ("might be (5 - Math.Abs(5 - i))").
- dust2's window is 0.925 to 1.1 (the playtest page), so wherever it settles
  is within 9% of its middle. `ColourGrade` uses the middle, times the
  compensation. Godot's own auto exposure (CameraAttributes) is a different
  model and is not used.
- GT convars `mat_tonemap_force_*` (cheat) override each exposure input;
  `mat_tonemap_force_scale` fixes it. A Local check in CS2 with
  `mat_tonemap_force_scale 1.0125` against the same spot would show how
  much adaptation moves it there.

## 4. Bloom (VRF, GT)

A pixel is weighed by `clamp((exposure x luminance - threshold) / width)`
(luminance 0.3, 0.59, 0.11; the exposure without the bias), downsampled
with Jimenez's filter, blurred at a half to a 32nd of the screen, each blur
tinted and weighed, then added, mixed or screened (`x / (x + 0.187) x
1.035`, in gamma, after the curve). GT's schema adds a compute bloom
(`m_flComputeBloom*`, `r_csgo_use_compute_bloom`, off). `ColourGrade`
maps this onto Godot's glow as near as it goes: the same blend (Godot
screens before its tone mapper, not after the curve), Godot's smoothstep
for CS2's linear ramp, levels 1 to 5 for the five blurs, no tints. The
skybox's bloom strength and the start value are not drawn. How close it
looks is a Local check.

## 5. The settings (GT convars; secondary sources)

- **High Dynamic Range, Quality or Performance** (the video menu). The menu
  text says Performance "decreases the quality HDR rendering but potentially
  increases performance and reduces GPU memory use"
  (quoted by [a settings guide, 2025-01](https://www.tiktok.com/@shogozftw/video/7455904301227986194); not read in
  the game's own strings). GT's `sc_hdr_enabled_override` lists the
  choices underneath: no HDR, HDR, HDR 10:10:10:2, HDR 11:11:10. So
  Performance is most likely a narrower frame buffer, which bands smoke
  and dark gradients (inferred; players report exactly that, below). The
  grade itself does not change. We draw in 16-bit floats, as Quality would.
- `r_csgo_render_post_local_contrast` is on by default (GT, clientdll
  cheat), so local contrast runs wherever a file has it. VRF does not draw
  it ("requires a scene blur") and has "not found any vpost file that uses"
  a vignette. `MapPostProcessing` lists either in the load report when a
  file has it. If dust2's does, the last resort in the playtest plan (a
  CompositorEffect, Forward+ only) is where it would go.
- `r_csgo_render_post_colorcorrection 0` (clientdll cheat) reads as a
  debug override, 0 meaning "as authored" (inferred; the menu has no such
  switch). `mat_colorcorrection` is development-only.
- "Boost Player Contrast" (the menu) is its own pass on players, not the
  grade; out of scope here.

## 6. What is still open

- **dust2's own numbers.** Nothing public prints dust2's vpost. It is named
  by the map's `post_processing_volume`
  (`lighting/postprocessing/de_dust2_prefab/de_dust2_prefab.vpost`) and
  comes out with `scripts/extract_assets.sh postprocessing` (Local).
- **Units.** How `light_environment` brightness and the baked irradiance
  relate to the exposed scene the curve takes, which would derive our
  eye-fitted `SUN_ENERGY_PER_BRIGHTNESS` 0.7 and `LightmapMaterials.ENERGY`
  0.4 rather than fit them. No public source found says; VRF draws both at
  their stored values times the same exposure. Recalibrating by the patch
  method with the grade on (Local) is the way for now.

## Critiques and improvements players want

Mostly secondary sources; CS2's own notes say nothing about the grade.

- The Performance HDR setting bands colours and blurs the edges of fading
  smokes, so guides tell players to keep Quality for visibility
  ([EveZone, 2025](https://evezone.evetech.co.za/deep-dives/cs2-brightness-guide-fix-dark-corners/);
  [a Steam discussion on washed-out HDR](https://steamcommunity.com/app/730/discussions/0/3821922030304741040/)).
  We draw with 16-bit float buffers only, so our grade has no such mode to
  lose; nothing to build.
- Dark corners: players raise brightness or the driver's digital vibrance
  and saturation to spot enemies in shade
  ([EveZone, 2025](https://evezone.evetech.co.za/deep-dives/cs2-brightness-guide-fix-dark-corners/);
  [prodigygamers, 2026-07-04](https://prodigygamers.com/2026/07/04/cs2-best-video-settings-maximum-visibility-and-high-fps-guide/)).
  A measured option, once the grade matches: a brightness offered in-game
  as a lift of the table's toe (free: the table is built once at load),
  judged by the shade patches' luminance at the long doors spot.

## What was built from it

- `MapPostProcessing` (`src/map/map_post_processing.gd`) reads a vpost in
  either form, with VRF's defaults where there is none.
- `ColourGrade` (`src/map/colour_grade.gd`) puts steps 3 to 6 into one
  64-cubed Godot 3D texture, built at load, on Godot's LINEAR tone mapper
  with the exposure times 2^bias / W. Godot 4.7.2 samples the colour
  correction at the raw sRGB value with no texel-centre offset, after its
  contrast; a contrast of 63/64 puts 0 and 1 on the edge texels' centres,
  as CS2's own sampling does. `tests/run_grade_checks.gd` samples the
  table as Godot does, in linear light (hdr_2d) and in sRGB, against the
  chain in section 2: within 1.2/255 for the defaults and for a made-up
  warm table. With hdr_2d, Godot reads the table through an sRGB view, so
  the table holds sRGB and comes out linear.
- The switch: `--grade cs2` on the command line, or
  `csgodot/rendering/colour_grade` in `project.godot` ("aces" until Sid
  judges it); `RenderVariants`' `other_grade` swaps one for the other on a
  running map.
- Not built: auto exposure, local contrast, vignette, the tone map's
  shadow and highlight fields, blending between volumes, the skybox's bloom
  strength.
