# What a frame costs to draw, and the plan to make it cheaper and better

Sid, 2026-09-24: dust2 here does not run well at 1920x1080, where CS2 plays
dust2 at 3840x2160 and 180 frames a second on his RTX 4070 Ti. He wants
time spent on the renderer, so lighting and shaders look as good as Source
2's and cost as little.

`reference/performance.md` measured the script, headless, and nothing it
lists is drawn. This page is about the drawing. It was written from the
code on main (fcf3f80) in a cloud thread, which has no GPU and no extracted
map, so **nothing on it has been measured yet**. The suspects below are
read from the settings and shaders. `scripts/profile_render.gd` is how to
measure them, and the first Local item is running it.

No page in `reference/research/` covers CS2's renderer. Item R0 below
proposes one.

## The budget

180 frames a second is 5.6 ms a frame. The script already takes some of
that on one thread (performance.md, ten players): 64 ticks at about 3 ms
is 190 ms of every second, and each frame's script 1.7 ms. So the script
alone would allow about 475 frames a second. The script leaves room; the
drawing has to fit in what is left, CPU side (culling, draw calls) and GPU
side.

## What the renderer does now

Forward+, Vulkan (Godot's default; `project.godot` names no renderer).

| What | Set to | Where |
|---|---|---|
| Sun shadow | 4 splits, blended, out to 8192 units, pancake 4096 | `MapLighting.build` |
| Sun shadow atlas | 8192 x 8192 | `project.godot` |
| Soft shadow filter | quality 4 (Ultra, the highest) | `project.godot` |
| Sun's angular size | dust2's `angulardiameter`, which turns on Godot's soft penumbra search (PCSS) | `MapLighting.build` |
| Map meshes | every visible one casts from both faces (`SHADOW_CASTING_SETTING_DOUBLE_SIDED`) | `MapImporter`, around line 264 |
| Anti-aliasing | MSAA 2x | `project.godot` |
| Screen-space occlusion | on, radius 24, detail 0.5 | `MapLighting.build` |
| Bloom, fog, colour adjustment | on | `MapLighting.build` |
| Bounce light | CS2's own baked lightmaps (irradiance and direction), read in every world material's shader | `lightmap.gdshaderinc`, `LightmapMaterials` |
| Props without lightmap UVs, players, arms | CS2's light probes, sampled in the shader | `probe_lit.gdshader`, `ProbeMaterials` |
| Direct light | a custom `light()` on every map material, Godot's own Burley and GGX written out, so the baked light rides the sun's pass | `baked_light.gdshaderinc` |
| Reflections | the sky only (`REFLECTION_SOURCE_SKY`), indoors too | `MapLighting.build` |
| 3D skybox | ordinary geometry scaled up, every fragment writing its own depth to sit behind the map | `FarMaterials`, `far.gdshaderinc` |
| Occlusion culling | off; nothing culls a room behind a wall but the frustum | `project.godot` |
| Your own shadow | a second copy of your body, drawn into the shadow maps only | `PlayerView` |

## The suspects, most likely first (inferred, not measured)

1. **The sun's shadows.** Four splits over 8192 units means the whole map
   is drawn into the shadow atlas up to four more times a frame, from both
   faces of every triangle. Each lit pixel then runs the soft filter at its
   highest quality with a penumbra search on top (Godot's documentation
   warns that a light's size costs extra), and the 8192 atlas is four
   times the pixels of Godot's default 4096. CS2 may not do it this way:
   Source 2's other games ship baked sun visibility for the static world
   beside the bounce light, so live shadow maps are needed only for what
   moves. Whether CS2's dust2 does is Local item L3. The profiler's `no_sun_shadows`, `sun_hard_edges`,
   `sun_filter_low`, `sun_atlas_4096`, `sun_distance_2048` and
   `one_sided_casters` take this apart.
2. **Draw calls.** How many meshes and materials the extracted dust2 has
   is not known here. With no occlusion culling, every surface in the
   frustum is drawn, and again in each shadow split that sees it. The
   profiler prints the counts, the camera's pass and the shadow passes
   apart. If they run to thousands, the fix is occluders from the map's
   own geometry, merging, and visibility ranges on small props (R3).
3. **The skybox writing depth.** A fragment that writes its own depth
   cannot be rejected by the early depth test, so the skybox's shader runs
   on every pixel it covers, even where the map is in front. It is exact to
   do the squeeze in the vertex shader instead (R2), which keeps early
   rejection. `no_skybox` says what it costs.
4. **MSAA 2x in Forward+**, with SSAO and glow on top. These scale with
   pixels, so they grow 4x at 3840x2160. `no_msaa`, `no_ssao`, `no_glow`
   and `half_resolution` measure them.

## Local items (Sid's machine)

- **L1. Run the profiler.** Every result below depends on these numbers.
  From the repo, with dust2 extracted:

      godot --path . --resolution 1920x1080 --script scripts/profile_render.gd -- 5
      godot --path . --resolution 3840x2160 --script scripts/profile_render.gd -- 5
      godot --path . --resolution 1920x1080 --script scripts/profile_render.gd -- 1

  Each takes about 20 seconds after the map loads and prints a Markdown
  table. Paste all three into the thread, or into this page under
  "Measured".
  If one variant takes most of the time, a RenderDoc capture of the
  baseline at that view confirms it.
- **L2. CS2's settings at 180 frames a second.** The video settings Sid
  plays with (shadow quality, MSAA or CMAA, texture filtering, ambient
  occlusion, FidelityFX, boost player contrast), so the comparison is like
  for like.
- **L3. What dust2's lightmaps folder holds.** In Source 2 Viewer,
  `maps/de_dust2.vpk`, the `lightmaps/` folder: the file names and sizes.
  The extraction takes `irradiance` and `directional_irradiance`. If a
  baked shadow page is there as well (a name like `direct_light_shadows`),
  the static world's sun shadows can come from it (R4). This is inferred
  from Source 2's other games and has to be checked on CS2's files.
- **L4. Which cubemaps or reflection probes dust2 ships** (the same VPK,
  and `env_cubemap` or `env_combined_light_probe_volume` in the entity
  lump), for R5.

## Remote items (cloud threads)

- **R0. Research CS2's renderer**, as the research pages do: what its
  compiled maps carry for lighting (lightmap pages, probes, cubemaps), its
  shadow settings and what each draws, its anti-aliasing, its tone mapper,
  and what players criticise in it, from CS2's current files first. Waits
  on Sid's go, since he decides what is researched.
- **R1. The profiler** (`scripts/profile_render.gd`, `RenderVariants`,
  checks in `tests/run_render_checks.gd`). Done with this page.
- **R2. The skybox's squeeze in its vertex shader**, so the early depth
  test works again. Small, and exact: the squeeze is affine in the depth
  the rasteriser interpolates, so it gives the same depth at every pixel.
  Waits on L1 only to know if it is worth doing first.
- **R3. Culling**, if L1 shows many draw calls: occluders built at load
  from the map's own geometry (`ArrayOccluder3D`, with occlusion culling
  turned on), visibility ranges on small props, and the map's surfaces
  merged by material where the export split them. Each counted for its CPU
  cost at load and per frame.
- **R4. Shadows split as CS2 splits them**, if L3 finds the baked page:
  the static world's sun shadow read from it in the lightmap shader, and
  the live shadow maps drawing only what moves (players, dropped guns,
  grenades) over a short distance, at the quality the numbers call for.
  Without the baked page, the fallback is fewer splits and a lower filter
  as far as L1 shows is needed, checked by eye against Sid's screenshots.
- **R5. Reflections from the map's own cubemaps** (after L4), in place of
  the sky everywhere. This is for how it looks: specular indoors and in
  tunnels is lit by the sky now.
- **R6. Settings as CS2 names them.** Shadow quality, anti-aliasing and
  the rest as a menu reads them (roadmap item 26), so each player picks
  their own cost.

Anything that would need a change to Godot itself (a custom build or an
engine fork) comes to Sid as a decision first. Nothing on this page needs
one so far.

## Measured

Nothing yet (L1).
