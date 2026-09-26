# What a frame costs to draw, and the plan to make it cheaper and better

Sid, 2026-09-24: dust2 here does not run well at 1920x1080, where CS2 plays
dust2 at 3840x2160 and 180 frames a second on his RTX 4070 Ti. He wants
time spent on the renderer, so lighting and shaders look as good as Source
2's and cost as little.

`reference/performance.md` measured the script, headless, and nothing it
lists is drawn. This page is about the drawing. It was written from the
code on main (fcf3f80) in a cloud thread, which has no GPU and no extracted
map, so nothing on it was measured when it was written; each item says
what has been since (L1's "Measured", R5's). The suspects below were
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
| Sun shadow | 4 splits, blended, out to 8192 units, pancake 4096; where the map's shadow is baked (R4), only what moves is drawn into it: the map is on render layer 11 (`MapShadows.LAYER`), which the sun's `shadow_caster_mask` leaves out | `MapLighting.build`, `MapImporter` |
| Sun shadow atlas | 8192 x 8192 | `project.godot` |
| Soft shadow filter | quality 4, Soft High (Ultra is 5) | `project.godot` |
| Sun's angular size | 0 where the map's shadow is baked (R4), so no penumbra search; otherwise dust2's `angulardiameter`, which turns on Godot's soft penumbra search (PCSS) | `MapLighting.build` |
| The map's shadow from the sun | CS2's baked `direct_light_shadows` on every lightmapped surface, and the probe atlas's `_dlshd` page, read at every pixel, on everything the probes light (players, props, dropped guns, grenades, smoke, the bomb); both or neither, and live where either is missing (R4) | `MapShadows`, `lightmap.gdshaderinc`, `LightProbes`, `probe_lit.gdshaderinc` |
| Map meshes | every visible one casts from both faces (`SHADOW_CASTING_SETTING_DOUBLE_SIDED`), into the lamps' shadows only where the sun's is baked | `MapImporter`, around line 268 |
| Anti-aliasing | MSAA 4x (`msaa_3d=2` is the enum `MSAA_4X`, not a sample count) | `project.godot` |
| Screen-space occlusion | off. It drew nothing when it was measured, since the map's materials brought their bounce light in through `light()` then (Measured); they hand it to Godot as its ambient light now (R5), which SSAO would darken, so turning it on is a look to judge beside CS2 | `MapLighting.build` |
| Bloom, fog, colour adjustment | on | `MapLighting.build` |
| Bounce light | CS2's own baked lightmaps (irradiance and direction), read in every world material's shader and handed to Godot as its ambient light (`IRRADIANCE`), which keeps its reflections (R5) | `lightmap.gdshaderinc`, `baked_light.gdshaderinc`, `LightmapMaterials` |
| Props without lightmap UVs, players, arms | CS2's light probes, read at one point for each body or prop (an ambient cube; a player's 40 units above the feet) and handed to Godot as its ambient light, as the lightmaps are | `probe_lit.gdshader`, `ProbeMaterials` |
| Direct light | a custom `light()` on every map material, Godot's own Burley and GGX written out, so the sun's light takes its baked shadow (R4) | `baked_light.gdshaderinc` |
| Reflections | a Godot reflection probe at each of CS2's cubemaps (dust2's 43 probe volumes), projected onto its box and drawn once as the map starts, and the sky outside them (R5); before R5, none at all | `MapReflections`, `MapImporter`, `MapLighting.build` |
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
4. **MSAA 4x in Forward+**, with SSAO and glow on top. These scale with
   pixels, so they grow 4x at 3840x2160. `no_msaa`, `no_ssao` (SSAO is
   off now), `no_glow` and `half_resolution` measure them.

## Local items (Sid's machine)

- **L1. Run the profiler.** *(done 2026-09-24, under "Measured")* Every result below depends on these numbers.
  From the repo, with dust2 extracted:

      godot --path . --script scripts/profile_render.gd -- 5 60 1920x1080
      godot --path . --script scripts/profile_render.gd -- 5
      godot --path . --script scripts/profile_render.gd -- 1 60 1920x1080

  Without a size it draws as the game starts, in exclusive fullscreen at
  the screen's own size (3840x2160 here); with one, in a window that size.
  Godot's `--resolution` does nothing since the project starts fullscreen.

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

- **L5. Whether the compiled map carries its visibility.** *(done 2026-09-24: `world_visibility.vvis_c`; read since PR #83 by `WorldVisibility`, which culls with it, R3)* Source 2 maps
  are compiled with precomputed visibility, which CS2 culls with. Check
  whether Source 2 Viewer lists or exports it for dust2 (inferred, not
  checked). If it does, it could replace or back up the occluders (R3).

- **L6. Whether dust2's VPK carries its SST** (R4). *(done 2026-09-25: it
  does not)* List `maps/de_dust2.vpk`
  for anything named `sst`, and note its size and type. If it is there and
  Source 2 Viewer can read it, the static shadow map can be CS2's own
  rather than rendered here at load.
  Found by Sid's local agent: nothing named `sst` in the map's VPK or the
  skybox's (`maps/prefabs/de_dust2/de_dust2_skybox.vpk`). The shadow CS2
  ships there is `direct_light_shadows` (9,595,615 bytes compiled; the
  skybox's 43,059). The world nodes' meshes come in `_shadow` and
  `_noshadow` variants (13 `..._noshadow.vmdl_c` and one
  `n0_lr0_c1_s_cb_bl_mesh_blocklight1_shadow.vmdl_c` in the map; four
  `_shadow` and one `_noshadow` in the skybox), which may be how CS2 marks
  what renders into its shadows (inferred, not checked). So R4's second
  tier, if built, is rendered here at load.

- **L7. The baked shadow on dust2** (R4). *(Extracted and checked
  2026-09-25 at f7be422; the playtest and the profiler are still to do.)*
  Extract the two pages
  (`scripts/extract_assets.sh lightmaps`: only the lightmaps, so dust2's
  materials stay at their extraction from before CS2's shaders moved to
  VCS 72), then run `scripts/run_tests.sh dust2`, whose shadow checks want
  the sun's channel 0, both pages, no map mesh in the live shadow map,
  and no sun down lower tunnels. Play
  dust2 beside CS2: the shadows' edges up close, a player walking into a
  building's shadow, guns dropped and grenades thrown indoors, the
  lamps' shadows in lower tunnels, and light at the foot of walls. Then
  run the profiler at 1080p and 4K as in L1: `baseline` against
  `live_map_shadows` is what the baking saves.
  Found by Sid's local agent on the first run: the lightmaps and the
  probes are the same bake as before (their SHA-256 did not change), and
  the probes' page is 120 slices of 192 by 176, one for every six of the
  atlas's. The map's page is an 8192-square RGBA PNG with alpha 254 or 255.
  255 is blocked, as `MapShadows` reads it: the sun's channel is 255 over
  73.4% of it, 0 over 18.0% and between over 8.6%; faces looking down are
  95.1% blocked, walls facing away from the sun 94.4%, and walls facing
  it 43.3%. The lamps' channels are 99.5% blocked. The entity lump gives
  the sun `bakedshadowindex` 0 and the tunnel lamps 1 and 2. Godot
  finished importing the page and crashed on its way out; a second import
  found nothing left to do, so `import_assets` now runs a failed import
  once more. 84 of 85 dust2 checks passed; the one that failed counted
  the collision hull's meshes, which sit under a hidden node, as drawn
  into the live shadow map, and now counts only what is drawn. The
  skybox's VPK has a page of its own (512 square, one channel: R, G and B
  alike), which the skybox now reads (R4); `scripts/extract_assets.sh
  skybox` fetches it.

- **L8. Reflections and players on dust2** (R5, R7). *(The profiler half
  done, 2026-09-25, under R5; the screenshots are left)* Nothing to extract.
  Play dust2 beside CS2 and take pairs of screenshots from the same spots:
  the same agent up close in the sun and in the shade (under the arch, in
  lower tunnels), guns in hand, and anything on the map that shines.
  Note where the shine differs, and whether the first seconds after the
  map starts stutter while the probes are drawn. Then run the profiler at
  1080p and 4K as in L1: the baseline against the same build before R5
  is what reflecting costs (`no_reflections` is not: R5), and the video
  memory line shows the probes' atlas.
  The same screenshots rank what R7 takes next.

- **L9. Cloth on the player models** (R7).
  `scripts/extract_assets.sh character-masks`, which takes seconds: it
  decompiles each agent material's metalness texture and exports no
  model, so CS2's newer shaders do not stop it. Then
  `scripts/run_tests.sh model`, which prints which of the agents'
  materials ask for cloth and fails where one's mask is missing. Then
  the same agent beside CS2, up close in the sun, in play and in the buy
  menu: the face mask's knit, the jacket and the first-person sleeves
  should take a soft sheen towards their edges and no highlight on each
  rib, and the creases should be dark in the sun as well as the shade.

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
  walk through long doors and top of mid on Sid's machine. Since PR #83
  the map is also culled by CS2's own visibility (L5, `WorldVisibility`):
  what the camera's cluster cannot see is not drawn, 2,702 of dust2's
  3,589 world meshes from T spawn, and each keeps its shadow. The
  occluders still cull from where the camera stands, inside what that
  leaves. Both run; the profiler's `no_visibility` and `no_occlusion`
  measure what each saves, and whether both are worth keeping is Sid's
  call on those numbers. CS2 also culls its shadow maps with the same
  file (R4's notes), which is not built.
- **R4. Shadows split as CS2 splits them.** *(The first tier built,
  2026-09-25: the map's shadow from CS2's baked pages. Waits on the
  extraction and a playtest, L7.)*
  dust2 ships `direct_light_shadows` (L3): the sun's shadow from the static
  world, baked per lightmap texel, one channel for each of three lights: a
  light's `bakedshadowindex` names its channel, the sun's 0 and the two
  lamps down lower tunnels 1 and 2 (read by Sid's map agent, 2026-09-25).
  The light probe atlas has a matching `_dlshd` page for what moves. So:
  the map stops casting into the live shadow map; its surfaces multiply
  the sun by the baked channel; players, dropped guns and grenades take
  the sun's shadow from the probes' `_dlshd`; and the live shadow map
  draws only what moves, over a short distance. That takes most of the
  6,200 shadow draw calls and 5 to 6 million triangles a frame away, which
  measured (`no_sun_shadows`) is 2.0 ms of GPU at 1080p, 6.3 ms at 4K, and
  1.7 ms of the renderer's CPU. At 4K most of that is the soft filter run
  on every pixel (3.2 to 3.7 ms), not the drawing, and a static shadow
  read from a texture needs no such filter. Needs both files extracted
  (Local, one line in the extraction each) and the shaders changed
  (Remote).

  What is built, the first tier (`MapShadows` says the rest):
  - `scripts/extract_assets.sh lightmaps` fetches `direct_light_shadows`
    and the `_dlshd` slices (under `lightmaps/probes/`, with the atlas's).
    `write_import_settings.gd` imports the page at BC7 without the alpha
    border fix, since each channel is a different light's shadow.
  - Every lightmapped material takes the sun times one minus the sun's
    channel of the page (`lightmap_sun` in `lightmap.gdshaderinc`), as
    Source 2 Viewer's `lighting.slang` does; the channel comes from the
    `light_environment`'s `bakedshadowindex`.
  - The probes' page is packed once into `lightprobe_sun.bin` (a byte a
    cell, how much of the sun gets through) and drawn as one 3D texture
    in a global shader uniform (`probe_sun_visibility`). Each probe-lit
    instance is told where its volume's cells lie in it, and reads it at
    every pixel (`probe_sun`), as Source 2 Viewer's
    `SampleProbeDirectLightShadows` does, so a shadow's edge can cross a
    body. That is the players (`RigModel.light_from`), the props the
    lightmaps do not cover, and now the dropped guns, grenades, smoke and
    the bomb (`ProbeMaterials.light_model`), which were on Godot's own
    lighting and would otherwise take the sun indoors. Whatever of the
    map the lightmaps and the props' probes left on Godot's lighting goes
    on the probes too (`ProbeMaterials.apply_rest`), glows and additive
    surfaces aside. A mesh the export merged from copies all over the map
    (dust2's windows) reads the page in the volume holding the most of the
    points its cube is read at (`ProbeMaterials.shadow_for`, after #83's
    `cube_for`), rather than the one round the middle of its box.
  - The map goes on render layer 11 (`MapShadows.LAYER`), which the sun's
    `shadow_caster_mask` leaves out, so its live shadow map holds only
    what moves; the sun's penumbra search is off, since a body's shadow
    softens by under a unit.
  - Only when both pages are there, and the probes: without the probes'
    page the players would take the sun indoors. The import report says
    which it is, and why when it is live.
  - The 3D skybox reads its own page, in the channel its lump gives its
    sun or else the one the map's sun has (`MapLoader.make_skybox`). It
    needs no probes, since nothing moves in it; and it casts nothing
    live, so until this its buildings threw no shadow at all. The game's
    skybox line says whether it has one.
  - The lamps keep their live shadows, and their channels are unused.
  - Checked in the cloud through the Compatibility renderer: a floor in
    each shader lit where its page is clear and dark where it is blocked,
    and a box on the map's layer casting no live shadow beside one on
    layer 1 that does. Forward+ needs the playtest and the profiler (L7).
  What it leaves: the soft filter still runs at every lit pixel (3.7 ms
  at 4K, measured with the map in the shadow map); the profiler's
  `live_map_shadows` puts the map back in to measure what baking saved,
  and `sun_filter_low` what the filter still costs.

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
  crisp near edges (after, if the baked page looks soft up close; dust2's
  VPK has no SST to take it from, L6); and
  Godot's live shadow for what moves. None of it needs a change to Godot.
  The first is built. The second waits on the playtest: with the first
  alone, a player's shadow from the map comes from the probes' cells, 24
  units apart, so its edge crosses a body over about that much, where
  CS2 at High shadow quality takes it from the static shadow texture;
  and the page's own edges are as sharp as its texels.
- **R5. Reflections from the map's own cubemaps** (after L4). *(The first
  tier built, 2026-09-25: Godot's own probes where CS2's cubemaps are.
  Profiled, 1.15 to 1.18 ms of GPU at 4K, and kept (Sid, 2026-09-25); L8's
  screenshots are left.)*
  Until then nothing on the map, its props or its players reflected
  anything, the sky included, though this page said the sky lit them:
  every map, prop and player material turned Godot's ambient light off
  (`ambient_light_disabled`) to bring CS2's bounce light in through
  `light()`, and in Godot that switch takes every reflection with it
  (Godot 4.7.2's `scene_forward_clustered.glsl`). A body in the shade had
  no shine at all, the first of the reasons the players look flatter than
  CS2's (R7).

  What is built, the first tier:
  - The map's materials hand their bounce light to Godot as its ambient
    light (`IRRADIANCE`), which keeps the reflections. Godot multiplies it
    by the occlusion and by the albedo after the decals, as `light()` did,
    so a bullet hole still darkens it. Drawn in the Compatibility renderer
    in a cloud thread, the four map shaders' bounce light came out as
    before (6 of 2.07 million pixels differed, each by one step in 255,
    which is rounding), and a smooth metal ball in a room reflected the
    room, where it had been black. Forward+ was read from Godot's source,
    not drawn.
  - `MapReflections` puts a `ReflectionProbe` at each cubemap in the
    entity lump (`env_combined_light_probe_volume`, `env_cubemap_box`,
    `env_cubemap`): its box where the entity's is, its picture taken from
    the entity's origin, projected onto the box and faded out over the
    box's `edge_fade_dists`. Godot blends overlapping probes at every
    pixel, as CS2 does, with two differences: one fade distance where CS2
    has one for each axis (the largest is taken), and the smaller probe
    first where CS2 goes by `indoor_outdoor_level`.
  - Each probe is drawn once, as the map starts, with everything but the
    players. Godot draws a probe only once a camera has it in view, and
    one step of one probe a frame, so a camera of MapReflections' own
    looks over them all for a frame, which lines every probe up, and the
    map's visibility is held until they are done: nine frames a probe,
    about 390 for dust2's 43 (2.2 s at 180 frames a second), in which the
    whole map is drawn and a surface reflects the sky until its probe is
    done. Drawn in the Compatibility renderer, a probe the main camera had
    never looked at was ready the first frame it did; without that camera
    it was not. The profiler waits for them before it measures.
  - Godot dims a reflection where the ambient light reaching a surface is
    faint (its specular occlusion), which stands in for CS2 scaling its
    cubemaps by the baked light at each pixel.
  - The profiler's `no_reflections` takes the probes to no strength and
    the sky's reflections off. It is not what reflecting costs: probes at
    no strength are still drawn (measured below).
  - Godot's atlas of probe pictures has room for 64 (the project's
    `reflection_count`, Godot's default) and takes all of it as the first
    probe is drawn: about 400 MB of video memory in Forward+, about 6 MB a
    place (read from Godot's source, not measured), which the profiler's
    memory line will show. Scripts cannot size it for a map. A map with
    more cubemaps than that reflects the sky in the rest, with a warning.

  The second tier takes CS2's own pictures: dust2's
  `cubemaps/env_cubemap_array` (L4), extracted and read into the probes
  in place of Godot's, with CS2's scaling by the baked light. It needs
  the array's layout read from Source 2 Viewer first.

  Measured on Sid's machine (RTX 4070 Ti, 3840x2160 fullscreen,
  2026-09-25), L8's profiler half, on the branch that integrates the open
  performance PRs, against the same branch before R5 was merged:
  - The profiler's baseline, the median over its eight views, went from
    3.24 ms of GPU to 4.39 (+1.15 ms, 35% more), and video memory from
    3,543 MB to 4,058 (textures 2,581 to 3,081 MB: the probes' atlas).
  - `no_reflections` saved only 0.28 ms of it, so the variant does not
    measure what reflecting costs: probes at no strength are still drawn.
    What R5 costs is the baseline before it against the baseline after.
  - In play (`scripts/profile_combat.gd`, two runs), the GPU mean went
    from 3.1 ms to 4.2, the frame mean out of combat from 4.8 to 5.6 and
    5.9, and frames of 20 to 30 ms came back, their time in drawing, not
    in the tick or the scripts, and none compiling a pipeline (1 and 7 in
    a run, against none before). Their cause is not found. The probes had
    finished drawing and the map's visibility was back on by then.
  - Where it goes, from four fixed views (both sides' first spawn points
    at eye height, straight ahead and turned 120 degrees), 23bd700 (main
    just before R5) against 0a1c1ad (R5 alone). Each figure is the
    renderer's own GPU time (`viewport_get_measured_render_time_gpu`),
    the median of 120 frames after 30 to settle at each view, averaged
    over the four; V-Sync off, no cap; probes left out by hiding them
    (`visible` false). The script was a scratch one, not kept. R5 alone
    came to 4.37 to 4.39 ms in four runs; that the profiler's eight views
    above also gave 4.39 is a coincidence of two view sets, and so the
    four views put R5 at 1.18 ms where the eight put it at 1.15:

    | | GPU |
    |---|---|
    | before R5 (23bd700) | 3.21 ms |
    | R5 as built (0a1c1ad) | 4.39 ms |
    | its 17 probes not inside another | 4.31 ms |
    | its 12 largest probes | 4.19 ms |
    | its probes hidden | 3.93 ms |
    | its probes hidden and the sky's reflections off | 3.73 ms |
    | `sky_reflections/texture_array_reflections` false | 4.21 ms (3.74 with the probes hidden) |
    | `specular_occlusion/enabled` false | no change |
    | `reflection_atlas/reflection_size` 128 | no change in GPU time; the memory it saves not measured |

    So the 1.18 ms is about 0.45 for the probes, 0.2 for the sky's
    reflections (read in the shader: one radiance fetch a pixel, two with
    the texture array), and 0.5 left with both gone: Godot's ambient path
    itself, which `ambient_light_disabled` compiled out. Only that
    remainder is measured. What in the path takes it is read from
    `scene_forward_clustered.glsl` (4.7.2): the ambient and reflection code
    the switch left out, with no probe in the cluster to walk; that the
    larger shader also costs occupancy is inferred. It is not the
    specular occlusion, which measured nothing. The environment's ambient
    is a colour on dust2, so no sky sample is thrown away under
    `IRRADIANCE`.
  - In play with the probes hidden, the GPU mean was 3.7 ms against 4.2,
    with one frame over 20 ms (one run).
  - Sid keeps the reflections (2026-09-25): all-metal guns such as the
    Desert Eagle only look right with them. The trims stay options, with
    the look still to judge (L8's screenshots): the texture array off
    (0.18 ms; the probes and the sky then reflect from mipmaps, which
    Godot's docs say brings back jitter noise and upscaling artifacts),
    fewer probes (0.1 to 0.2 ms, the rooms left out reflect a larger
    neighbour or the sky), no probes at all and only the sky (0.45 ms),
    or a smaller atlas (`reflection_size` 128) for video memory alone,
    how much not yet measured against the atlas's 500 MB. The 0.5 ms of
    Godot's ambient path stays with any reflections that Godot draws;
    only the second tier, the material shaders sampling CS2's own
    pictures with Godot's ambient off again, would avoid it (not tried).
- **R6. Settings as CS2 names them.** Shadow quality, anti-aliasing and
  the rest as a menu reads them (roadmap item 26), so each player picks
  their own cost.
- **R7. Players drawn as CS2 draws them.** Sid asked why the player
  models look less detailed than CS2's (2026-09-25). The meshes and
  textures are CS2's own; what differs is how they are shaded and lit.
  Most visible first (the order inferred until screenshots of the same
  agent in the same spot in both games compare them, L8):
  1. No reflections at all. R5 built.
  2. One light sample for each body. The probes are read once, 40 units
     above the feet (`PlayerView`, `Bot`), where CS2 reads them at every
     pixel, so its light changes from boots to head. The probes' sun
     shadow is read at every pixel already (R4).
  3. CS2's character shader's layers are lost in the export: cloth sheen,
     softened skin (subsurface scattering), the eyes' own shader, rim and
     tint masks, and detail textures (Source 2 Viewer's copy of the
     shader). Colour, normal, roughness and metalness are kept. This
     needs a Local list of which features the agents' materials use.
     *(Cloth built, 2026-09-25, with three more of the shader's rules;
     waits on L9.)* Sid's screenshot of the buy menu beside CS2's showed
     ours shiny all over, the face mask's knit most, every rib catching
     the sun. `src/player/character.gdshader` now draws every material
     CS2 draws with `csgo_character`, the players', the bots' and your
     own arms in first person (`CharacterMaterials`):
     - Cloth, where a material asks for it (`F_CLOTH_SHADING`): the blue
       channel of its metalness texture, times one less the metalness,
       marks it, and there the specular is Charlie's sheen under
       Neubelt's visibility, brightest seen edge-on, with a reflectance of
       the tint times the albedo's square root times 0.667, and its
       reflection of the surroundings is CS2's `EnvBRDFCloth`; GGX
       elsewhere. The export reads only that texture's green, for the
       metalness, so it is decompiled on its own
       (`scripts/extract_assets.sh character-masks`, which the characters
       step runs too); its alpha, the rim mask, is dropped before the
       import, which would paint over the mask where the rim is clear.
     - The occlusion darkens the direct light as well as the bounce
       (`g_flAmbientOcclusionDirectDiffuse` and `...Specular`, 1 by
       default); Godot darkens only the bounce, so the sun lit every
       crease.
     - Specular anti-aliasing: the roughness is raised to the cube root of
       how fast the surface's own normal turns from one pixel to the next,
       so a distant body's folds do not sparkle.
     - Lambert diffuse, GGX with Schlick-Smith visibility, and the ambient
       cube read at the normal-mapped normal, as CS2 has them.

     The buy menu's agent, lit by a world of its own, takes it too, with
     that world's light in place of the probes' (`RigModel.probe_lit`
     false). Drawn in the Compatibility renderer in a cloud thread, on a
     ribbed sphere under the buy menu's sun and sky, the highlights on the
     ribs' crests went (its brightest pixel from white to 0.80 of it) and
     the rest was as before, and every variant of the shader compiled;
     Forward+ was read from Godot's source, not drawn. The formulas and
     defaults are Source 2 Viewer's reimplementation of CS2's shaders
     (`complex.frag.slang`, `common/pbr.slang`, `common/lighting.slang`,
     `common/environment.slang`), not CS2's own code. Still lost: the
     softened skin, the eyes, the rim and tint masks, the detail textures,
     retro-reflection and anisotropic gloss.
  4. Textures compressed twice. Source 2 Viewer writes PNGs and Godot
     compresses them again, to DXT1 or DXT5 (`write_import_settings.gd`,
     `compress/high_quality` off), which blurs fine detail and smears the
     roughness and metalness into each other. BC7 for the characters
     would keep them, at a re-import on Sid's machine.

  Agents extracted since CS2's 2026-09-23 update (VCS 72 shaders) may
  also have incomplete materials.

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
  baseline. 4x MSAA is 1.7 ms at 4K and SSAO 1.2, for nothing on screen
  (below).
- Players cost nothing measurable, and neither do fog and glow.

Sid's CS2 settings (L2), from his `cs2_video.txt`: 3840x2160, **4x MSAA**,
global shadow quality **High** with dynamic shadows from all lights,
**anisotropic 2x**, ambient occlusion **Medium**, HDR **Quality**, shader
detail High, FSR off, vsync on and `fps_max` 240. CS2 draws the same 4x
MSAA as here at 4K (this page read `msaa_3d=2` as 2x until the Godot docs
audit), where Sid sees about 180 frames a second, so the gap is in the
shadows and the skybox rather than in the anti-aliasing.

### SSAO, and the map shaders' alpha branch (the Godot docs audit)

Sid's machine, main at b5d8e4d (R2, R3, R4 and the map's visibility in),
the bots hidden so each run sees the same: the GPU's time per frame, the
median of 240 frames at each of five views (T spawn, the palms, the arch,
B site, long), measured with the feature, without it, and with it again.

| At 3840x2160 | With | Without | With again |
|---|---|---|---|
| SSAO | 2.67 to 4.01 ms | 2.09 to 3.06 ms | 2.67 to 4.01 ms |
| The alpha branch on the 702 opaque map materials | 2.67 to 4.01 ms | 2.65 to 3.99 ms | 2.67 to 4.01 ms |

- **SSAO cost 0.6 to 0.95 ms a frame at 4K and drew nothing**: the same
  three views drawn at 1920x1080 with it and without differed in no
  pixel of the 3D.
  Godot's SSAO darkens ambient light only, and every map, prop and player
  material then had `ambient_light_disabled` and added CS2's bounce in
  `light()`, where it counts as direct light. It is off now. Since R5 the
  bounce is Godot's ambient light, which SSAO would darken as it is.
  Whether that looks like CS2's own "ambient occlusion" (Sid plays it at
  Medium), with the fade distances raised from their metre defaults (50
  and 300 units), and whether it wants `ssao_light_affect`, which darkens
  direct light too, the sun's included, is a look to judge beside CS2,
  not a setting to restore.
- **The alpha branch costs nothing measurable.** `lightmapped`, `probe_lit`
  and `far` write `ALPHA_SCISSOR_THRESHOLD` inside a runtime `if`, which
  the Godot docs say makes every material on them alpha-tested. Copies of
  the six shaders without the branch, on every opaque material, changed
  the frame by at most 0.02 ms at 4K and 0.04 ms at 1080p, within the runs'
  noise. Nothing to change.
