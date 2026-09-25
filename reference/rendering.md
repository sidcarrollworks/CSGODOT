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
| 3D skybox | ordinary geometry scaled up, its depth squeezed against the far plane in the vertex shader (per fragment until R2) | `FarMaterials`, `far.gdshaderinc` |
| Occlusion culling | on since R3, from the collision hull; before that, only the frustum culled | `project.godot`, `MapOccluders` |
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

- **L1. Run the profiler.** *(done 2026-09-24, under "Measured")* Every result below depends on these numbers.
  From the repo, with dust2 extracted:

      godot --path . --resolution 1920x1080 --script scripts/profile_render.gd -- 5
      godot --path . --resolution 3840x2160 --script scripts/profile_render.gd -- 5
      godot --path . --resolution 1920x1080 --script scripts/profile_render.gd -- 1

  Each takes about 20 seconds after the map loads and prints a Markdown
  table. Paste all three into the thread, or into this page under
  "Measured".
  If one variant takes most of the time, a RenderDoc capture of the
  baseline at that view confirms it.
- **L2. CS2's settings at 180 frames a second.** *(done 2026-09-24, under "Measured")* The video settings Sid
  plays with (shadow quality, MSAA or CMAA, texture filtering, ambient
  occlusion, FidelityFX, boost player contrast), so the comparison is like
  for like.
- **L3. What dust2's lightmaps folder holds.** *(done 2026-09-24: `direct_light_shadows` is there)* In Source 2 Viewer,
  `maps/de_dust2.vpk`, the `lightmaps/` folder: the file names and sizes.
  The extraction takes `irradiance` and `directional_irradiance`. If a
  baked shadow page is there as well (a name like `direct_light_shadows`),
  the static world's sun shadows can come from it (R4). This is inferred
  from Source 2's other games and has to be checked on CS2's files.
- **L4. Which cubemaps or reflection probes dust2 ships** *(done 2026-09-24: one `cubemaps/env_cubemap_array`, 43 `env_combined_light_probe_volume`, no `env_cubemap`)* (the same VPK,
  and `env_cubemap` or `env_combined_light_probe_volume` in the entity
  lump), for R5.

- **L5. Whether the compiled map carries its visibility.** *(done 2026-09-24: `world_visibility.vvis_c`, whose data block Source2Viewer-CLI 20.0 does not decode)* Source 2 maps
  are compiled with precomputed visibility, which CS2 culls with. Check
  whether Source 2 Viewer lists or exports it for dust2 (inferred, not
  checked). If it does, it could replace or back up the occluders (R3).

- **L6. Whether dust2's VPK carries its SST** (R4): list `maps/de_dust2.vpk`
  for anything named `sst`, and note its size and type. If it is there and
  Source 2 Viewer can read it, the static shadow map can be CS2's own
  rather than rendered here at load.

## Remote items (cloud threads)

- **R0. Research CS2's renderer**, as the research pages do: what its
  compiled maps carry for lighting (lightmap pages, probes, cubemaps), its
  shadow settings and what each draws, its anti-aliasing, its tone mapper,
  and what players criticise in it, from CS2's current files first. Waits
  on Sid's go, since he decides what is researched.
- **R1. The profiler** (`scripts/profile_render.gd`, `RenderVariants`,
  checks in `tests/run_render_checks.gd`). Done with this page.
- **R2. The skybox's squeeze in its vertex shader.** *(done 2026-09-24)*
  `far.gdshaderinc`'s `far_position` squeezes the clip position toward
  `CLIP_SPACE_FAR`, so the early depth test throws away skybox fragments
  behind the map. Measured before (`no_skybox`): 0.8 ms at 1080p and
  3.2 ms at 4K. Checked by drawing through the Compatibility renderer in
  the cloud (the map in front, the skybox behind); Forward+ needs the
  profiler again on Sid's machine.
- **R3. Culling.** *(Occluders built, 2026-09-24; Sid showed the whole map
  drawn from B tunnels.)* `MapOccluders` builds one `ArrayOccluder3D` at
  load from the collision hull, leaving out player and grenade clips and
  parts named for glass, grates, fences and foliage, and triangles under 64
  square units. Occlusion culling is on in `project.godot`. Measured with
  occluders from the drawn faces: the camera's pass went from about 1,170
  draw calls to 290 (1.2M triangles to 0.4M), saving 0.2 to 0.4 ms of GPU
  and 0.2 ms of the renderer's CPU. It does not touch the shadow passes.
  Those occluders hid most of the map at long doors and buildings down mid
  from top of mid: an occluder blocks from both sides, and a face drawn
  from one side and seen from behind is invisible on screen. The hull
  cannot do that, since a player's eye is never inside it; it needs the same
  walk through long doors and top of mid on Sid's machine. CS2's own
  visibility (`world_visibility.vvis`, L5) is the way to cull the shadow
  maps too, once its data block can be read.
- **R4. Shadows split as CS2 splits them. Next, and the biggest win.**
  dust2 ships `direct_light_shadows` (L3): the sun's shadow from the static
  world, baked per lightmap texel, three lights in channels 0 to 2 (which
  channel is the sun is not recorded; compare each against the live
  shadow). The light probe atlas has a matching `_dlshd` page for what
  moves. So: the map stops casting into the live shadow map; its surfaces
  multiply the sun by the baked channel; players, dropped guns and grenades
  take the sun's shadow from the probes' `_dlshd`; and the live shadow map
  draws only what moves, over a short distance. That takes most of the
  6,200 shadow draw calls and 5 to 6 million triangles a frame away, which
  measured (`no_sun_shadows`) is 2.0 ms of GPU at 1080p, 6.3 ms at 4K, and
  1.7 ms of the renderer's CPU. At 4K most of that is the soft filter run
  on every pixel (3.2 to 3.7 ms), not the drawing, and a static shadow
  read from a texture needs no such filter. Needs both files extracted
  (Local, one line in the extraction each) and the shaders changed
  (Remote).

  How CS2 does it, from its own current files (SteamDatabase's
  GameTracking-CS2 at 760e69c, 2026-09-24: `DumpSource2/convars.txt` and
  the strings of `client.dll` and `scenesystem.dll`). The names are Valve's;
  what they do is read from their descriptions and log lines, not tested:
  - Mixed shadows (`lb_mixed_shadows`, `lb_enable_baked_shadows`): baked
    shadows for what does not move, live ones for what does.
  - A static shadow texture, "SST": the static map rendered from the sun
    once, not every frame. `client.dll` logs "SST data (%s) found in %s.vpk
    for current video settings, loading...", so it ships with the map, one
    per shadow setting. It reaches 2,000 units (`csm_sst_max_visible_dist`),
    and objects are flagged whether they "CAN_RENDER_INTO_SST". Beyond it,
    the baked `direct_light_shadows`.
  - The live cascades draw static objects only in the cascades a setting
    names (`lb_csm_override_staticgeo_cascades`), skip anything under 10
    texels in the shadow map (`lb_sun_csm_size_cull_threshold_texels`), and
    test the sun against precomputed visibility (`r_csgo_enable_sunlight_check`,
    and `m_nSunVisibilityCluster` in `world_visibility.vvis`, L5).
  - Other lights ("Dynamic shadows: All", which Sid plays with) are cheap
    for the same reasons: each light's shadow map is sized by how large it
    is on screen (`lb_dynamic_shadow_resolution_base` 1024, "Shadowmap size
    of a screen sized light"), and it draws only what precomputed
    visibility says it reaches (`sc_barnlight_enable_precomputed_vis`).

  So the same three tiers here: `direct_light_shadows` for the map at any
  distance (first, since it only needs extracting); a static shadow map
  of the map rendered once at load and sampled within 2,000 units, for
  crisp near edges (after, if the baked page looks soft up close); and
  Godot's live shadow for what moves. None of it needs a change to Godot.
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

Sid's machine, 2026-09-24: RTX 4070 Ti, Windows, dust2 as extracted
2026-09-21/22, branch at 4b5f9af, occluders from the drawn faces (since
replaced by the hull's). Each figure is a median over 8 views of 60 frames
with ten players, from `scripts/profile_render.gd` with its sample fix
(the first run printed zeros). At 3840x2160 the window was fullscreen.

The scene: 3,775 mesh instances, 3,834 surfaces, 5.7 million triangles,
860 materials; 3,605 instances cast shadows, 3,554 of them from both faces;
3.1 GB of video memory, 2.2 GB of it textures.

| Variant | GPU ms, 1080p | GPU ms, 4K | Render CPU ms | Draws, view / shadow |
|---|---|---|---|---|
| baseline | 3.07 | 10.37 | 2.31 | 309 / 6,215 |
| no_sun_shadows | 1.02 | 4.09 | 0.59 | 296 / 0 |
| sun_hard_edges | 2.28 | 7.19 | 2.29 | |
| sun_filter_low | 2.10 | 6.65 | 2.32 | |
| sun_atlas_4096 | 2.77 | 9.66 | 2.35 | |
| sun_distance_2048 | 4.12 | 13.31 | 1.35 | 288 / 2,394 |
| one_sided_casters | 2.92 | 10.14 | 2.35 | |
| no_occlusion | 3.27 | 10.80 | 2.59 | 1,167 / 6,267 |
| no_msaa | 2.69 | 8.72 | 2.35 | |
| no_ssao | 2.85 | 9.16 | 2.35 | |
| no_glow | 2.96 | 9.92 | 2.37 | |
| no_fog | 3.04 | 10.18 | 2.39 | |
| no_skybox | 2.23 | 7.13 | 2.38 | 249 / 6,315 |
| no_players | 3.07 | 10.31 | 2.34 | |
| half_resolution | 1.53 | 3.45 | 2.40 | |
| all_off | 0.29 | 0.72 | 0.51 | 249 / 0 |

Whole frames, with the ticks: 6.06 ms (165 a second) at 1080p with ten
players, 4.22 ms (237) alone, and 11.2 ms (89) at 4K.

What it says:

- **The sun's shadows are most of the frame**: 2.0 of 3.1 ms at 1080p, 6.3
  of 10.4 ms at 4K, and 1.7 of the renderer's 2.3 ms of CPU, all from 6,200
  shadow draw calls and 5 to 6 million triangles against the camera's 300
  and 0.4 million. R4 removes most of it. At 4K the soft filter alone is
  3.7 ms and the penumbra search 3.2 ms.
- Shortening the shadows to 2048 units cuts their draws by 60% but makes
  the GPU slower (4.1 against 3.1 ms at 1080p, in all three runs). The
  likely reason, inferred, not checked: each split then covers less ground
  at the same atlas size, so a penumbra of the same width in the world
  spans more texels, and the soft filter searches further.
- **The skybox writing its depth costs 0.8 ms at 1080p and 3.2 ms at 4K**,
  far more than its 166 meshes and 86,000 triangles would. R2 is the fix.
- The frame is bound by pixels: half resolution at 4K lands on the 1080p
  baseline. MSAA 2x is 1.7 ms at 4K and SSAO 1.2.
- Players cost nothing measurable, and neither do fog and glow.

Sid's CS2 settings (L2), from his `cs2_video.txt`: 3840x2160, **4x MSAA**,
global shadow quality **High** with dynamic shadows from all lights,
**anisotropic 2x**, ambient occlusion **Medium**, HDR **Quality**, shader
detail High, FSR off, vsync on and `fps_max` 240. CS2 draws twice our MSAA
samples at 4K, where Sid sees about 180 frames a second, so the gap is in
the shadows and the skybox rather than in the anti-aliasing.
