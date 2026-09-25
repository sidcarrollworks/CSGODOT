# Godot 4.7: rendering, lighting and GPU performance

Source: godot-docs branch 4.7 @9adca4c (2026-09-21). Read when: changing the sun, lamps, shadows, the environment (sky, fog, tone mapping, SSAO, glow), anti-aliasing or resolution, culling (occluders, visibility ranges, LOD), MultiMesh batches, decals, the render profiler, or anything that adds a draw call, a light or a new material at run time.

Shaders (render modes, built-ins, depth, uniforms, shader cost) are on the companion page `shaders.md`.

The project's own decisions and measurements are not restated here:
- `reference/performance.md` (on main): what the script and tick cost, headless, and how to measure again (`scripts/profile_dust2.gd`).
- `reference/rendering.md`: what a frame costs to draw on Sid's RTX 4070 Ti, the suspects, and items R0 to R6 and L1 to L7. On main since PRs #78 and #82, with `scripts/profile_render.gd`, `src/map/render_variants.gd`, `src/map/map_shadows.gd`, `src/map/map_occluders.gd`, `src/map/world_visibility.gd` and `tests/run_render_checks.gd`. Read it before starting render work.

## Rules for this project

- Scale every metre-tuned default. 1 unit = 1 inch, and many rendering defaults are metres in disguise (see "Defaults that assume metres" below). Anything you enable with its default distance (a light's `distance_fade_begin` of 40, SSAO's fade-out at 50 to 300, `volumetric_fog_length` 64, a ReflectionProbe's 20-unit box) acts over inches.
- Cloud threads cannot measure the GPU. `--headless` "disables all rendering and window management functions. Most functions from RenderingServer will return dummy values" (`classes/class_renderingserver.rst`). `get_rendering_device()` returns `null` headless. Frame times, draw counts and video memory come only from Sid's machine (`scripts/profile_render.gd`). Headless tests can check what the scene is set to (layers, masks, cast_shadow, materials), not what it costs.
- Read `msaa_3d` as an enum, not a sample count. `project.godot` has `anti_aliasing/quality/msaa_3d=2`, and `Viewport.MSAA_4X` = 2 (`MSAA_2X` = 1) (`classes/class_viewport.rst`). The project renders **4x MSAA**, the same as Sid's CS2 setting (`reference/rendering.md` and `RenderVariants` said 2x until the docs audit).
- Read `soft_shadow_filter_quality` as an enum too. `project.godot` sets `directional_shadow/soft_shadow_filter_quality=4`, which is `SHADOW_QUALITY_SOFT_HIGH`. `SOFT_ULTRA` is 5 (`classes/class_renderingserver.rst`). The rendering page and `MapLighting`'s comment called it "Ultra, the highest" until the docs audit. Soft High also multiplies the constant blur by 1.5x (Ultra 2x).
- To draw only moving things into a light's shadow map, use `Light3D.shadow_caster_mask` ("the light will only cast shadows using objects in the selected layers"; it does not change what shadows fall onto). Not `light_cull_mask`: "objects disabled via this cull mask will still cast shadows" (`tutorials/3d/lights_and_shadows.rst`). `MapShadows` does this with `MapShadows.LAYER` (`1 << 10`).
- Godot does not split static and dynamic shadow rendering: "Godot currently doesn't separate static shadow rendering from dynamic shadow rendering, but this is planned in a future release" (`engine_details/architecture/internal_rendering_architecture.rst`). A static shadow cache has to be built by the project (R4's plan), not switched on.
- Don't rely on LightmapGI. Baking "is only available in the editor", needs a Forward+/Mobile (GPU) device, and needs UV2 (`classes/class_lightmapgi.rst`). The project reads CS2's own baked lightmaps in its shaders instead (`LightmapMaterials`, `lightmap.gdshaderinc`).
- Keep one MSAA level on every viewport. Pipeline precompilation "only keeps track of one level at a time", so different MSAA levels on different viewports cause stutters, and changing MSAA or other features during play recompiles (`tutorials/performance/pipeline_compilations.rst`).
- Instance every material, effect and light type once while loading (hidden is enough). Pipelines are precompiled only for what the RenderingServer has seen; "material overrides can't be compiled" at mesh load (`pipeline_compilations.rst`).
- Occlusion culling needs `rendering/occlusion_culling/use_occlusion_culling=true` for the root viewport, or `Viewport.use_occlusion_culling` on a SubViewport. Occluders are CPU-rasterized with Embree, and an occludee must be *fully* hidden by its AABB (`tutorials/3d/occlusion_culling.rst`).
- Never move an `OccluderInstance3D` (or its parent) during play. Moving or hiding one "will trigger a background recomputation that can take several frames" (`classes/class_occluderinstance3d.rst`).
- Nothing drawn runs in the tick. Lights, decals, MultiMesh buffers and material parameters are set from `_process` views that read sim state (CLAUDE.md). A light created per event (`GrenadeView._light`) is fine. What matters is that it has no shadows, since each shadowed omni costs up to 6 shadow renders.

## Renderers, and what the cloud can and cannot see

Doc: `tutorials/rendering/renderers.rst`, `engine_details/architecture/internal_rendering_architecture.rst`

- The project is Forward+ (`config/features=PackedStringArray("4.7", "Forward Plus")`, and no `rendering_method` override). On Windows Forward+ uses Vulkan or Direct3D 12, falling back to the other and then to Compatibility (`rendering/rendering_device/fallback_to_opengl3`, default `true`).
- Forward+: clustered lighting via a compute shader, a depth prepass (`rendering/driver/depth_prepass/enable`, default `true`), RGBA16F colour. Only Forward+ has TAA, FSR2, SSR, SSIL, SDFGI, VoxelGI, volumetric fog, directional PCSS, the normal-roughness buffer and SSS.
- Compatibility (OpenGL) lacks decals, FXAA/SMAA/TAA, the screen-space roughness limiter, light projectors, directional PCSS, compositor effects and ubershaders. It has SSAO (a simplified version since 4.6). It lights shadowed lights in extra passes blended in sRGB. A check drawn through Compatibility in the cloud (as the render branch did for R2 and R4) says nothing about decals (`BulletImpacts`), and nothing about Forward+ cost.
- Depth buffer precision: `renderers.rst` says Forward+ is "32-bit with reverse Z" and Compatibility "24-bit without reverse Z". `internal_rendering_architecture.rst` says 3D uses "a 24-bit unsigned normalized integer depth buffer, or 32-bit signed floating-point if a 24-bit depth buffer is not supported", and "All of Godot's renderers use reverse Z". The two pages disagree. The render branch found Compatibility reversed too, by drawing through it (`FarMaterials.far_plane_depth`). Details are in `shaders.md`.
- `RenderingServer.get_current_rendering_method()` returns `"forward_plus"`, `"mobile"` or `"gl_compatibility"`. Headless returns dummy values. In shaders, use `CURRENT_RENDERER` / `RENDERER_*` (4.4+).
- `rendering/driver/threads/thread_model` defaults to 1. Separate-thread rendering is "Experimental ... Not recommended for use in production".

## Defaults that assume metres

Doc: each class page. All values are Godot defaults in "3D units", which here are inches.

| Where | Default | What it means here |
|---|---|---|
| `Camera3D.near` / `far` | 0.05 / 4000 | The project sets 0.5 / 16384 (`PlayerView`). |
| `DirectionalLight3D.directional_shadow_max_distance` | 100 | 8 feet. The project sets 8192. |
| `DirectionalLight3D.directional_shadow_pancake_size` | 20 | The project sets 4096 (`MapLighting.SHADOW_PANCAKE`). |
| `OmniLight3D.omni_range` / `SpotLight3D.spot_range` | 5 | Always set it. |
| `Light3D.distance_fade_begin` / `_shadow` / `_length` | 40 / 50 / 10 | Scale before enabling `distance_fade_enabled`. |
| `SpotLight3D.shadow_bias` | 0.03 (Light3D 0.1) | `MapLighting.LAMP_SHADOW_BIAS` = 1.0. |
| `Light3D.shadow_normal_bias` | 2.0 (omni/spot 1.0) | Unit per the docs: not stated. |
| `Decal.size` / `distance_fade_begin` | (2,2,2) / 40 | `BulletImpacts` sets the size per hole. |
| `ReflectionProbe.size` / `blend_distance` | (20,20,20) / 1 | Must be scaled. |
| `Environment.ssao_radius` | 1.0 | SSAO is off here (see Environment). |
| `rendering/environment/ssao/fadeout_from` / `fadeout_to` | 50 / 300 | **Not overridden.** SSAO would fade from 4 ft and be gone at 25 ft. The same holds for `ssil/fadeout_*`. |
| `Environment.ssil_radius` | 5 | |
| `Environment.fog_depth_begin` / `_end` | 10 / 100 | The project sets both from `env_cubemap_fog`. `fog_depth_end = 0` means `Camera3D.far`. |
| `Environment.volumetric_fog_length` | 64 | |
| `Environment.sdfgi_cascade0_distance` / `max_distance` / `min_cell_size` | 12.8 / 204.8 / 0.2 | |
| `Environment.ssr_depth_tolerance` | 0.5 | |
| `OccluderInstance3D.bake_simplification_distance` | 0.1 | Editor baking only. |
| `Label3D.pixel_size` | 0.005 | The test range uses 0.25. |
| `VisualInstance3D.sorting_offset` | 0.0 | "typically meters". |
| `rendering/mesh_lod/lod_change/threshold_pixels` | 1.0 | Pixels, so it needs no scaling. |

## Light types, limits and what each costs

Doc: `tutorials/3d/lights_and_shadows.rst`, `classes/class_light3d.rst`, `class_omnilight3d.rst`, `class_spotlight3d.rst`, `class_directionallight3d.rst`

- Forward+ is clustered. There is no per-mesh light limit, but there is a default cap of **512 clustered elements in view**. Omni, spot and area lights, decals and reflection probes all count (`rendering/limits/cluster_builder/max_clustered_elements`, Forward+ only). Past it, elements pop in and out. The docs say lowering it "may improve GPU performance on certain setups".
- Up to **8 DirectionalLight3Ds** are visible. Each additional *shadowed* one shares the directional atlas and lowers everyone's resolution.
- The 8 omni + 8 spot per mesh limit is Mobile/Compatibility only (`rendering/limits/opengl/max_lights_per_object`). It does not apply to Forward+.
- AreaLight3D exists in 4.7 (rectangle, LTC). It is "the most expensive to render". In Forward+, one visible area light adds cost to **all** rendered objects.
- "Shadow-less lights can be almost free if they don't occupy much space on screen" in Forward+. Shadowed lights are "much" more expensive. `Light3D.shadow_enabled` defaults to `false`.
- A light's direction is its node's -Z (`DirectionalLight3D`, `SpotLight3D`). A DirectionalLight3D's position is ignored.
- `light_color` is nonlinear sRGB. `light_energy` is not a physical unit unless `rendering/lights_and_shadows/use_physical_light_units` is on (off here).
- `light_specular`: 1.0 on Light3D, but **0.5** on OmniLight3D and SpotLight3D. In `light()` the value arrives as `SPECULAR_AMOUNT` = 2 × `light_specular` for omni/spot, and 1.0 for directional.
- `omni_attenuation` / `spot_attenuation`: 0 is roughly constant with a smooth edge fade, 2.0 is inverse square (the docs call it "physically accurate"), and values above 10 misbehave. The light never reaches past its range, whatever the attenuation.
- `spot_angle` is the half-angle from -Z, default 45. **Spot shadows stop working above 89 degrees**, and wider spots get lower-resolution shadows.
- Omni shadow modes: `SHADOW_CUBE` (default, 6 faces) or `SHADOW_DUAL_PARABOLOID` (2, distorts on low-poly casters). A spot is 1 render.
- `light_size` (omni/spot) and `light_angular_distance` (directional, degrees) above 0 turn on PCSS, which has "a high performance cost, especially for directional lights". Directional PCSS is Forward+ only. The docs recommend letting players turn it off by setting these to 0.0.
- `light_volumetric_fog_energy = 0` skips the light in volumetric fog. Short-lived lights should have it at 0 when temporal reprojection is on.
- `Light3D.light_bake_mode` defaults to `BAKE_DYNAMIC` (2). It only matters for VoxelGI/SDFGI/LightmapGI, which the project doesn't use.
- `distance_fade_enabled` fades the light over `begin + length` and then culls it entirely (omni/spot only). This is the tool for many small lights. `distance_fade_shadow` cuts only the shadow, earlier.

## Shadows

Doc: `tutorials/3d/lights_and_shadows.rst`, `classes/class_directionallight3d.rst`, `classes/class_projectsettings.rst`, `classes/class_geometryinstance3d.rst`

### Directional (the sun)

- PSSM: `SHADOW_ORTHOGONAL` (0), `SHADOW_PARALLEL_2_SPLITS` (1) or `SHADOW_PARALLEL_4_SPLITS` (2, the default and the slowest). An object seen by all four splits is drawn "five times in total: once for each of the four shadow splits and once for the final scene rendering". This is the 6,215 shadow draws against 309 view draws that the project measured.
- `directional_shadow_split_1/2/3` (0.1 / 0.2 / 0.5) are fractions of `directional_shadow_max_distance` (or of the camera's far, if max distance is 0). Split 2 and split 3 are each measured from the previous split.
- `directional_shadow_blend_splits` has a "moderate performance cost". `directional_shadow_fade_start` (0.8 of max distance): set it to 1.0 only if max distance covers the whole scene.
- `directional_shadow_pancake_size`: a large value can cause artifacts on large objects at the frustum edge, and 0 disables pancaking. Change it only for missing shadows that aren't bias problems.
- The atlas is `rendering/lights_and_shadows/directional_shadow/size` (default 4096, "rounded up to the nearest power of 2"; the project uses 8192), with `.../16_bits` (default `true`) and `.../soft_shadow_filter_quality` (default 2 = Soft Low; the project uses 4 = Soft High). At run time: `RenderingServer.directional_shadow_atlas_set_size(size, is_16bits)` and `RenderingServer.directional_soft_shadow_filter_set_quality(quality)`.
- `ShadowQuality`: `SHADOW_QUALITY_HARD` 0, `SOFT_VERY_LOW` 1 (blur ×0.75), `SOFT_LOW` 2, `SOFT_MEDIUM` 3, `SOFT_HIGH` 4 (blur ×1.5), `SOFT_ULTRA` 5 (blur ×2). The blur multiplier applies to `shadow_blur`, not to PCSS's variable blur.
- `DirectionalLight3D.sky_mode`: `SKY_MODE_LIGHT_AND_SKY` (0), `SKY_MODE_LIGHT_ONLY` (1, invisible to sky shaders), `SKY_MODE_SKY_ONLY` (2).
- `Viewport.debug_draw = Viewport.DEBUG_DRAW_PSSM_SPLITS` (14) and `DEBUG_DRAW_DIRECTIONAL_SHADOW_ATLAS` (10) show the splits and the atlas. The `debug_shadow_splits` render mode does the same per material.

### Positional (omni, spot, area): the shadow atlas

- One atlas per viewport: `rendering/lights_and_shadows/positional_shadow/atlas_size` (default 4096), `atlas_16_bits` (true), `atlas_quadrant_0..3_subdiv` (defaults 2, 2, 3, 4 = 1, 4, 16, 64 slots... the docs count "4 + 4 + 16 + 64" = up to **88 shadowed lights in view**), and `soft_shadow_filter_quality` (2). At run time use `Viewport.positional_shadow_atlas_size` etc. on the viewport, or `RenderingServer.positional_soft_shadow_filter_set_quality()`.
- **A SubViewport's `positional_shadow_atlas_size` defaults to 2048**, not the project setting. At 0, no positional shadows render in that viewport.
- Slots are sized by the light's size on screen. Every frame a light re-renders only if it changed slot size or an object in its range changed. Otherwise "nothing is done". So the tunnel lamps re-render whenever a player moves in their range.
- `Viewport.debug_draw = DEBUG_DRAW_SHADOW_ATLAS` (9).

### Casters, receivers and masks

- `GeometryInstance3D.cast_shadow`: `SHADOW_CASTING_SETTING_OFF` 0, `ON` 1 (default; respects face culling), `DOUBLE_SIDED` 2 (ignores culling), `SHADOWS_ONLY` 3 (invisible, casts only; `PlayerView`'s body shadow).
- `Light3D.shadow_caster_mask` (default all 32 bits) picks which render layers cast into that light. `Light3D.light_cull_mask` picks which layers it lights, and cull-masked objects still cast. `VisualInstance3D.layers` has 20 usable layers (`set_layer_mask_value` takes 1 to 20). RenderingServer: `light_set_shadow_caster_mask(light, mask)` and `light_set_cull_mask(light, mask)`. VoxelGI, SDFGI, LightmapGI and volumetric fog ignore the cull mask.
- Receiving is per material: the `shadows_disabled` render mode or `BaseMaterial3D.disable_receive_shadows`. Alpha-blended materials never cast shadows. Alpha scissor, alpha hash and depth-prepass transparency can.
- `rendering/lights_and_shadows/tighter_shadow_caster_culling` (default `true`): skips items that cannot cast into the view frustum.
- `shadow_reverse_cull_face` flips culling in the shadow pass. For two-sided casting, use `SHADOW_CASTING_SETTING_DOUBLE_SIDED` instead.
- Bias: when you raise one, raise `shadow_normal_bias` before `shadow_bias`. Normal bias thins shadows, and plain bias causes peter-panning. Higher atlas resolution fixes both, at a cost.
- Quality levers, cheapest first: fewer shadowed lights, `distance_fade_shadow`, a smaller atlas, fewer splits, a lower filter quality, PCSS off. The docs say to keep the atlas at 4096 "or decreased to 2048 for low-end GPUs". 32-bit shadows have "a significant performance cost".
- (inferred) The directional shadow is redrawn every frame, because its splits follow the camera. The atlas update rule above is only stated for positional lights.
- (measured in the project, not in the docs) Occlusion culling did not reduce shadow-pass draws (`no_occlusion` 6,267 against baseline 6,215).

## Culling, LOD and draw calls

Doc: `tutorials/3d/occlusion_culling.rst`, `tutorials/3d/visibility_ranges.rst`, `tutorials/3d/mesh_lod.rst`, `tutorials/performance/optimizing_3d_performance.rst`, `tutorials/performance/gpu_optimization.rst`, `tutorials/performance/using_multimesh.rst`

### Occlusion culling

- Requirements: the project setting (root viewport) or `Viewport.use_occlusion_culling` (SubViewport), plus at least one `OccluderInstance3D` with an `Occluder3D`. Baking (**Bake Occluders**) is an editor button. At run time, build an `ArrayOccluder3D` and call `set_arrays(vertices, indices)` once. Setting `vertices` and `indices` separately rebuilds twice. `MapOccluders` on the render branch does this.
- The editor bake only takes `MeshInstance3D`s with opaque materials whose `layers` match `bake_mask`. MultiMesh, particles and CSG are ignored. Alpha-scissor and alpha-blended surfaces are ignored.
- The test is the whole AABB of the occludee against a low-resolution CPU buffer. Big occluders and small occludees work best. Occluders block from both sides (the project hit this on the drawn faces).
- CPU cost: `rendering/occlusion_culling/occlusion_rays_per_thread` (512 × logical cores = buffer pixels) and `bvh_build_quality` (2). Both are read at start. At run time: `RenderingServer.viewport_set_occlusion_rays_per_thread()` and `viewport_set_occlusion_culling_build_quality()`. `jitter_projection` (true) hides false culls through small gaps.
- Per occludee: `GeometryInstance3D.ignore_occlusion_culling` (the docs suggest it for "a first-person view model"). `extra_cull_margin` should stay 0. `RenderingServer.instance_set_ignore_culling(rid, true)` skips frustum, occlusion and layer culling.
- Forward+ already has a depth prepass, so the win is fewer draw calls and vertices, not less overdraw.
- Debug: `Viewport.debug_draw = DEBUG_DRAW_OCCLUDERS` (24). At run time, toggle with `get_tree().root.use_occlusion_culling`.

### Visibility ranges (manual HLOD)

- `GeometryInstance3D.visibility_range_begin/end` (0 = off) is measured to the **centre of the instance's AABB**. `_begin_margin/_end_margin` give hysteresis, or a fade width when `visibility_range_fade_mode` is `FADE_SELF` (1) or `FADE_DEPENDENCIES` (2). Fading forces the transparent pipeline during the fade, and fading is Forward+ only.
- `Node3D.visibility_parent` builds HLOD trees. It must point at a GeometryInstance3D, never at a child.
- For cheaper transitions, dither with `BaseMaterial3D.distance_fade_mode` Object/Pixel Dither and margins at 0. Pixel Alpha forces transparency and turns off shadows.
- Unlike mesh LOD, ranges don't account for FOV or resolution.

### Automatic mesh LOD

- It is generated on glTF import by default (meshoptimizer), and picked by a screen-space metric (FOV and resolution aware) from the AABB point nearest the camera. `Viewport.mesh_lod_threshold` (root: `rendering/mesh_lod/lod_change/threshold_pixels`, 1.0) and per node `GeometryInstance3D.lod_bias` (1.0; 0 forces the lowest LOD). `DEBUG_DRAW_DISABLE_LOD` (19) turns it off to compare.
- LOD generation also builds **shadow meshes** (welded positions only) for the shadow and depth passes (`ArrayMesh.shadow_mesh`). It must have exactly the source's vertex positions.
- Shadow and reflection-probe passes pick their own LOD thresholds.
- All instances of one MultiMesh share one LOD level, and a MultiMesh is culled as a whole.

### Draw calls, materials, instancing

- Forward+ automatically instances MeshInstance3Ds sharing a mesh and material if the material is opaque or alpha-tested (never alpha-blended or depth-prepass). Otherwise use MultiMesh.
- "The fewer different materials in the scene, the faster". StandardMaterial3Ds with the same feature set share a shader, even with different parameters. Per-instance uniforms "allow for better shader reuse and are therefore faster" than duplicating a ShaderMaterial (`classes/class_shadermaterial.rst`).
- Joining meshes ahead of time beats run-time batching, but joined meshes cull as one.
- Transparent objects are sorted back to front by **node position** (not by vertex), are drawn after all opaque, never instance, and are costly for fill rate. `Material.render_priority` (-128 to 127) and `VisualInstance3D.sorting_offset` adjust the order. render_priority does not reorder transparent against opaque.
- Fill-rate test: compare frame time in a large and a small window with vsync off (`gpu_optimization.rst`). The project's `half_resolution` variant is this test. Its results show dust2 is pixel-bound.

### MultiMesh

- Set `transform_format`, `use_colors` and `use_custom_data` **before** `instance_count`. Setting `instance_count` "clears and (re)sizes the buffers", and the flags can't be set afterwards. `visible_instance_count` (-1 = all) limits drawing without reallocating.
- `MultiMesh.buffer` (and `RenderingServer.multimesh_set_buffer(rid, buffer)`) takes 12 floats per 3D transform, plus 4 for colour, plus 4 for custom data, per instance. Transforms are row-major: `(basis.x.x, basis.y.x, basis.z.x, origin.x, basis.x.y, basis.y.y, basis.z.y, origin.y, basis.x.z, basis.y.z, basis.z.z, origin.z)`. A size mismatch renders nothing. Reading `buffer` returns a copy.
- The per-instance setters (`set_instance_transform/color/custom_data`) are cheap once a MultiMesh keeps a CPU copy of its instances, but the first one after the buffer is (re)allocated (a new MultiMesh, or `instance_count` changed) makes that copy, and the docs say a buffer in the engine's cache "will have to be fetched from GPU memory" (`multimesh_get_buffer`). Measured on Sid's machine (2026-09-25): each new `EffectQuads` batch's first card held the frame 2 to 4 ms; setting `buffer` whole each frame instead costs nothing extra. Fill a MultiMesh that is new or regrown each frame by `buffer`, as `EffectQuads` and `GrenadeView` do. The array properties (`transform_array`, `color_array`) are deprecated and "very slow".
- Set `custom_aabb` (on the MultiMesh, or `GeometryInstance3D.custom_aabb` on the node) to avoid AABB recomputation. A huge AABB defeats culling, which suits batches spread over the map.
- `set_buffer_interpolated()` / `physics_interpolation_quality` apply only with Godot's physics interpolation, which the project does not use.

## Environment, sky and post-processing

Doc: `tutorials/3d/environment_and_post_processing.rst`, `classes/class_environment.rst`, `classes/class_sky.rst`, `classes/class_cameraattributes.rst`

- Priority: `Camera3D.environment` > the `WorldEnvironment` (one per tree) > the editor preview (never at run time). `CameraAttributes` (exposure, DOF, auto exposure) live on the Camera3D or WorldEnvironment, and the camera's overrides.
- Quality knobs are project settings, not Environment properties: `rendering/environment/ssao/*` (quality 2, `half_size` true, `fadeout_from/to` 50/300, `blur_passes` 2), `ssil/*`, `screen_space_reflection/*`, `glow/upscale_mode`, and `volumetric_fog/*`. At run time: `RenderingServer.environment_set_ssao_quality(...)`.
- Tone mappers: `TONE_MAPPER_LINEAR` 0, `REINHARDT` 1, `FILMIC` 2, `ACES` 3, `AGX` 4 (the slowest). The input is multiplied by 2.0 for Filmic and 1.8 for ACES. For photoreal, the docs recommend `tonemap_white` 6 to 8 (default 1.0; the project keeps 1.0 with ACES). AgX uses `tonemap_agx_white` / `tonemap_agx_contrast`. Adjustments (brightness, contrast, saturation, LUT) apply **after** tonemapping.
- SSAO acts on *ambient* light only, unless `ssao_light_affect` > 0. When the docs audit measured it, the map shaders set `ambient_light_disabled` and brought baked light through `light()`, so SSAO had no ambient to darken: dust2 drawn with it and without differed in no pixel, and it cost 0.6 to 0.95 ms a frame at 4K. It is off (`reference/rendering.md`, "Measured"). Since rendering.md R5 (2026-09-25) the map shaders hand their baked light to Godot as ambient light (`IRRADIANCE`), which SSAO would darken. SSAO, SSIL and SSR run at half resolution by default.
- Glow shows when a pixel exceeds `glow_hdr_threshold` (1.0 = over the tonemapper's white) or when `glow_bloom` > 0. It blends Softlight by default. Glow levels 2 (0.8) and others are defaults, and level 1 does nothing in Compatibility.
- Fog: `FOG_MODE_DEPTH` uses `fog_depth_begin/end/curve`, with `fog_density` as the maximum opacity. `fog_aerial_perspective` 1.0 replaces the fog colour with the sky's. `fog_sky_affect` has no effect when aerial perspective is 1.0. `fog_sun_scatter` tints toward the sun. Materials opt out with `fog_disabled`.
- Ambient: `AMBIENT_SOURCE_BG` 0 (default), `DISABLED` 1, `COLOR` 2, `SKY` 3. `ambient_light_sky_contribution` 1.0 ignores `ambient_light_color`. Reflections: `REFLECTION_SOURCE_BG` 0, `DISABLED` 1, `SKY` 2. Only ReflectionProbe, VoxelGI, SDFGI or a shader writing `RADIANCE` give local reflections.
- Sky: `Sky.radiance_size` (default `RADIANCE_SIZE_256`), `Sky.process_mode` (`AUTOMATIC` picks Quality for a static panorama; Realtime needs 256 and suits a changing sky). `PanoramaSkyMaterial.panorama` needs `.hdr`/`.exr` for HDR (a PNG is LDR). `ProceduralSkyMaterial` takes its sun from the first 4 DirectionalLight3Ds. Radiance is recomputed when the sky changes, so don't animate a Quality sky.
- `BG_KEEP` skips drawing the sky ("hall of mirrors" if any sky shows). Not for dust2.
- Auto exposure (Forward+) evaluates luminance every frame, at a "moderate" cost.

## Global illumination and reflections

Doc: `tutorials/3d/global_illumination/*.rst`, `classes/class_lightmapgi.rst`, `classes/class_reflectionprobe.rst`

- **LightmapGI**: bakes on the GPU in the editor only ("cannot be baked in an exported project"). It needs UV2 (reserved: the material can't use UV2 for anything else), bakes only siblings and children, and caps textures at 16384. Static-bake-mode lights skip real-time lighting on baked surfaces, and dynamic objects then cast no shadow on them. `shadowmask_mode` bakes the first Dynamic directional light's static shadow for use beyond `directional_shadow_max_distance` (Replace/Overlay). The project gets both from CS2's `direct_light_shadows` instead. It has no importer for CS2 data.
- **ReflectionProbe**: `update_mode` `UPDATE_ONCE` (0, default; re-renders when moved) or `UPDATE_ALWAYS`. `size` default (20,20,20). `box_projection`, `interior`, `enable_shadows` (expensive with Always), `cull_mask`/`reflection_mask` (20-bit), `max_distance`, `mesh_lod_threshold`. Up to 4 probes blend at a point. Each probe is a clustered element. The atlas is `rendering/reflections/reflection_atlas/reflection_size` (256) × `reflection_count` (64). A probe renders the scene itself: it can't take a pre-made cubemap such as CS2's `env_cubemap_array` (inferred from its members; nothing lists a texture input). R5 would sample such cubemaps in the material shader (`samplerCube`/`samplerCubeArray`, writing `RADIANCE`; see `shaders.md`). Adding the first ReflectionProbe enables a pipeline feature, which compiles more.
- VoxelGI and SDFGI are Forward+ only and real-time. SDFGI's defaults are metre-sized (see the table). Neither is used, and both would fight the baked CS2 lighting.
- SSIL complements other GI. It is not full GI.

## Anti-aliasing, resolution and texture filtering

Doc: `tutorials/3d/3d_antialiasing.rst`, `tutorials/3d/resolution_scaling.rst`, `classes/class_viewport.rst`

- MSAA (`Viewport.msaa_3d`: `MSAA_DISABLED` 0, `MSAA_2X` 1, `MSAA_4X` 2, `MSAA_8X` 3) smooths only geometry edges. It does nothing for alpha-scissor edges without `alpha_to_coverage`, and nothing for specular aliasing. It is set in `rendering/anti_aliasing/quality/msaa_3d` (read at start) or on the viewport, and changing it in play recompiles pipelines.
- TAA (`use_taa`, Forward+) ghosts on skinned meshes and particles ("implementation is not complete"). FSR2 (`scaling_3d_mode = SCALING_3D_MODE_FSR2`) gives better TAA and ignores `use_taa`. FXAA and SMAA (`screen_space_aa`) are cheap and blurry. The docs point competitive games to MSAA: "avoiding blurriness and temporal artifacts is important, such as in competitive games".
- `scaling_3d_scale` is per axis (0.5 = a quarter of the pixels). Above 1.0 it is SSAA (bilinear only). Modes: `BILINEAR` 0, `FSR` 1, `FSR2` 2, `NEAREST` 5 (MetalFX 3/4 on Apple only). Scales below 1 add a negative mip bias of `log2(scale)`. FXAA adds -0.25 and TAA -0.5. "Dynamic resolution scaling isn't supported yet."
- `rendering/anti_aliasing/screen_space_roughness_limiter/enabled` (default true) has a small cost against specular aliasing. At run time: `RenderingServer.screen_space_roughness_limiter_set_active()`.
- `rendering/textures/default_filters/anisotropic_filtering_level` defaults to 2, which is the enum `ANISOTROPY_4X` (Sid plays CS2 at 2x). It affects only samplers with an `*_anisotropic` filter (every map shader here uses `filter_linear_mipmap_anisotropic`). At run time: `Viewport.anisotropic_filtering_level`.
- `rendering/anti_aliasing/quality/use_debanding` (off). In Forward+ it is `Viewport.use_debanding`.
- Stretch mode `canvas_items` (the project's) renders 3D at the window's full resolution and scales only the 2D.

## Shader and pipeline compilation stutter

Doc: `tutorials/performance/pipeline_compilations.rst`, `tutorials/rendering/jitter_stutter.rst`

- 4.4+: **ubershaders** use specialization constants, so one pipeline compiles ahead of time and the optimized ones compile in the background. **Pipeline precompilation** runs at mesh load and node add. Forward+/Mobile only. Compatibility must draw everything once during loading.
- Monitors (they only grow): `Performance.PIPELINE_COMPILATIONS_CANVAS/MESH/SURFACE/DRAW/SPECIALIZATION` (34 to 38), or `RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_*)` (6 to 10). **Draw** during play is a stutter (and an engine bug to report). **Surface** during play means a feature was first used then. **Specialization** is background work.
- Features that must be seen before assets load, or they compile later: the MSAA level, ReflectionProbe, separate specular (SSS), motion vectors (TAA/FSR2), normal-roughness (SSAO, SSR, SSIL, SDFGI, VoxelGI, or a shader or compositor reading it), lightmaps, VoxelGI, SDFGI, 16/32-bit shadows, and omni shadow cube or dual paraboloid.
- Effects spawned during play (muzzle flashes, grenade clouds, new `EffectQuads` batches per texture and blend) compile when first added, unless a hidden copy was instanced during loading. "Attach a hidden version of the effect somewhere that is guaranteed to show up."
- Before any pipeline, the shader itself: measured, a preloaded `Shader` compiled in the frame its first material was made (6.6 and 10.3 ms for two of the effect shaders). Calling `get_rid()` on it while loading moves that there (`EffectQuads._ready`). The measurement is below, after "Fixed in the docs audit".
- Caches: `rendering/rendering_device/pipeline_cache/enable` (true, saved to disk) and `rendering/shader_compiler/shader_cache/enabled` (true). The driver keeps its own cache, which a driver update wipes. To simulate a first run, turn off the pipeline cache **and** delete the driver cache.
- The shader baker (4.5+, per export preset: Shader Baker > Enabled) ships SPIR-V/DXIL in the PCK to speed up the first load. It doesn't remove stutter, and it can't run from a `--headless` export.

## Measuring

Doc: `classes/class_performance.rst`, `classes/class_renderingserver.rst`, `classes/class_viewport.rst`, `tutorials/performance/gpu_optimization.rst`

- GPU time per viewport: `RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)`, then `viewport_get_measured_render_time_gpu(rid)` / `_cpu(rid)` in ms. This "accurately reflects GPU utilization even if framerate is capped". With a frame cap, the GPU may downclock and report longer times. Sum every viewport drawn. `get_frame_setup_time_cpu()` is shared, with no opt-in.
- Per pass: `RenderingServer.viewport_get_render_info(rid, VIEWPORT_RENDER_INFO_TYPE_VISIBLE | _SHADOW | _CANVAS, VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME | _PRIMITIVES_IN_FRAME | _DRAW_CALLS_IN_FRAME)` (or `Viewport.get_render_info(type, info)`). The totals are `get_rendering_info(RENDERING_INFO_TOTAL_*)`, plus `RENDERING_INFO_TEXTURE/BUFFER/VIDEO_MEM_USED`. Both return 0 until **2 frames have been drawn**.
- `Performance.RENDER_TOTAL_OBJECTS/PRIMITIVES/DRAW_CALLS_IN_FRAME` (11 to 13) and `RENDER_VIDEO/TEXTURE/BUFFER_MEM_USED` (14 to 16). Some monitors are debug-only (0 in release), and some update only once a second.
- `RENDER_VIDEO_MEM_USED` (and `RENDERING_INFO_VIDEO_MEM_USED`) is not the card's memory alone: on Vulkan it sums the allocator's bytes over every heap, system memory included (4.7.2-stable `RenderingDeviceDriverVulkan::get_total_memory_used`). Upload staging buffers left by loads on worker threads count in it: 34 gun models read at once showed 0.7 to 1.0 GiB more than read one at a time, none of it on the card (`nvidia-smi`). For textures and meshes alone read `RenderingDevice.get_memory_usage(MEMORY_TEXTURES)` and `MEMORY_BUFFERS` (`reference/research/weapon-preload.md`).
- Headless all of these return dummy values or 0 (the RenderingServer note above). Headless is valid for `TIME_PROCESS`, `TIME_PHYSICS_PROCESS` and object counts, which is what `profile_dust2.gd` uses.
- Debug views: `Viewport.debug_draw` includes `DEBUG_DRAW_OVERDRAW` 3, `WIREFRAME` 4 (Compatibility needs `RenderingServer.set_debug_generate_wireframes(true)` first), `SHADOW_ATLAS` 9, `DIRECTIONAL_SHADOW_ATLAS` 10, `SSAO` 12, `PSSM_SPLITS` 14, `DECAL_ATLAS` 15, `DISABLE_LOD` 19, `CLUSTER_OMNI_LIGHTS/SPOT_LIGHTS/DECALS/REFLECTION_PROBES` 20 to 23, `OCCLUDERS` 24, `MOTION_VECTORS` 25.
- `RenderingServer.request_frame_drawn_callback(callable)` runs after a frame is drawn. `force_draw(swap_buffers, frame_step)` redraws (main thread only). `global_shader_parameter_get()` and `Texture2D.get_image()` synchronize with the GPU, so avoid them per frame.

## RenderingServer directly

Doc: `tutorials/performance/using_servers.rst`, `classes/class_renderingserver.rst`

- `instance_create()` (or `instance_create2(base, scenario)`), `instance_set_base(rid, mesh)`, `instance_set_scenario(rid, get_world_3d().scenario)`, `instance_set_transform()`, `instance_set_layer_mask()`, `instance_geometry_set_cast_shadows_setting()`, `instance_geometry_set_material_override()`, `instance_geometry_set_shader_parameter()`, `instance_geometry_set_visibility_range(rid, min, max, min_margin, max_margin, fade_mode)`, `instance_set_visible()`, `instance_set_custom_aabb()`, `instance_teleport()`. Free with `free_rid()`.
- **Keep a reference to the Resource** whose RID you pass. The RID doesn't count as a reference, so the mesh and its RID can be freed under you.
- Use it only when the scene tree itself is the bottleneck (tens of thousands of instances). It "won't improve performance ... if the GPU is already fully utilized". Don't drive the RIDs of objects that have nodes.
- `call_on_render_thread(callable)` is for RenderingDevice work (compositor effects).

## Decals, labels, fog volumes, VRS, compositor

Doc: `classes/class_decal.rst`, `tutorials/3d/volumetric_fog.rst`, `tutorials/3d/variable_rate_shading.rst`, `tutorials/rendering/compositor.rst`

- **Decal**: projects along its local -Y within `size`. It is clustered (each one counts toward the 512), drawn when the receiving mesh is drawn, and textures go into one atlas. Forward+/Mobile only. It can't change a material's transparency. It is applied after `fragment()` and before lighting (the reason the map's baked light is not emission: `baked_light.gdshaderinc` hands it to Godot as ambient light, `IRRADIANCE`, which Godot multiplies by the albedo after the decals). `cull_mask` is 20-bit (all by default). `upper_fade`/`lower_fade` (0.3) fade with distance from the AABB centre. `normal_fade` 0 to 1 (small cost). `distance_fade_*` culls far decals. The filter is `rendering/textures/decals/filter` (default 3).
- **Label3D**: `pixel_size` 0.005 units per pixel, `font_size` 32, `billboard`, `no_depth_test`, `fixed_size`, `shaded` false, `double_sided` true, `alpha_cut`. Visibility ranges work on it.
- **Volumetric fog / FogVolume**: Forward+ only, froxels (`rendering/environment/volumetric_fog/volume_size` 64, `depth` 64). `volumetric_fog_length` defaults to 64 units. Temporal reprojection ghosts fast-moving lights and volumes. Not used (smokes are `SmokeVoxels` + MultiMesh).
- **VRS**: Forward+/Mobile on Turing+ / RDNA2+ (Sid's 4070 Ti has it). `Viewport.vrs_mode` (`rendering/vrs/mode`) with a density texture. It cuts fragment cost and keeps edges.
- **Compositor**: `Compositor.compositor_effects` on WorldEnvironment or Camera3D. A `CompositorEffect` subclass implements `_render_callback(effect_callback_type, render_data)` on the **render thread** (guard shared state with a Mutex), at `EFFECT_CALLBACK_TYPE_PRE_OPAQUE` 0, `POST_OPAQUE` 1, `POST_SKY` 2, `PRE_TRANSPARENT` 3 or `POST_TRANSPARENT` 4. Flags: `needs_motion_vectors`, `needs_normal_roughness`, `needs_separate_specular`, `access_resolved_color/depth` (for MSAA). Each flag enables a pipeline feature. Forward+/Mobile only, not the stencil buffer.

## Class notes

**RenderingServer** (`classes/class_renderingserver.rst`). Headless returns dummy values. Useful per frame: `viewport_set_measure_render_time(rid, bool)`, `viewport_get_measured_render_time_gpu/cpu(rid) -> float` (ms), `viewport_get_render_info(rid, type, info) -> int`, `get_rendering_info(info) -> int`, `get_current_rendering_method() -> String`, `directional_shadow_atlas_set_size(size: int, is_16bits: bool)`, `directional_soft_shadow_filter_set_quality(ShadowQuality)`, `positional_soft_shadow_filter_set_quality(ShadowQuality)`, `viewport_set_positional_shadow_atlas_size(rid, size, use_16_bits=false)`, `light_set_shadow_caster_mask(rid, int)`, `multimesh_set_buffer(rid, PackedFloat32Array)`, `global_shader_parameter_set(name, value)` (cheap) / `_get` (syncs, slow), `instance_set_ignore_culling(rid, bool)`, `screen_space_roughness_limiter_set_active(enable, amount, limit)`, `environment_set_ssao_quality(quality, half_size, adaptive_target, blur_passes, fadeout_from, fadeout_to)`.

**Viewport / SubViewport** (`class_viewport.rst`, `class_subviewport.rst`). `msaa_3d` (enum; the root's is from the project setting), `screen_space_aa`, `use_taa`, `scaling_3d_mode`, `scaling_3d_scale`, `fsr_sharpness`, `texture_mipmap_bias`, `anisotropic_filtering_level`, `mesh_lod_threshold` (1.0), `use_occlusion_culling` (false; the root uses the project setting), `positional_shadow_atlas_size` (**2048** by default; the root uses the project setting), `positional_shadow_atlas_16_bits`, `positional_shadow_atlas_quad_0..3`, `debug_draw`, `use_debanding`, `vrs_mode`, `get_render_info(type, info)`, `get_viewport_rid()`. SubViewport: `size` (512×512), `render_target_update_mode` (default 2, `UPDATE_WHEN_VISIBLE`). A SubViewport starts with MSAA and occlusion culling off.

**Camera3D** (`class_camera3d.rst`). `fov` 75 is **vertical** with `keep_aspect` = `KEEP_HEIGHT` (1), `near` 0.05 (lower values cost precision "across the entire range"), `far` 4000, `cull_mask` 1048575 (20 bits), `environment`, `attributes`, `compositor`. `unproject_position(world)`, `project_ray_origin/normal(screen)`, `is_position_in_frustum(world)`. Z-fighting is fixed by raising `near` first.

**Environment / WorldEnvironment / CameraAttributes / Sky** are covered above. `CameraAttributesPractical` uses ISO. `CameraAttributesPhysical` locks the camera's FOV. `WorldEnvironment` has `environment`, `camera_attributes` and `compositor`, and there is one per tree.

**Light3D** (`class_light3d.rst`). `light_color`, `light_energy` (1.0), `light_indirect_energy`, `light_volumetric_fog_energy`, `light_specular` (1.0; 0.5 on omni and spot), `light_negative`, `light_size` (PCSS, omni/spot), `light_angular_distance` (PCSS, directional; degrees; not affected by scale), `light_cull_mask`, `light_bake_mode` (2), `light_projector` (needs shadows, not in Compatibility; filter set globally by `rendering/textures/light_projectors/filter`), `shadow_enabled` (false), `shadow_bias` (0.1; spot 0.03), `shadow_normal_bias` (2.0; omni/spot 1.0), `shadow_blur` (1.0), `shadow_opacity` (1.0), `shadow_caster_mask`, `shadow_reverse_cull_face`, `distance_fade_*`. `set_param(Light3D.PARAM_*, value)` reaches everything. `editor_only`.

**DirectionalLight3D**: `directional_shadow_mode` (2 = 4 splits), `directional_shadow_split_1/2/3` (0.1/0.2/0.5), `directional_shadow_blend_splits` (false), `directional_shadow_fade_start` (0.8), `directional_shadow_max_distance` (100), `directional_shadow_pancake_size` (20), `sky_mode` (0). **OmniLight3D**: `omni_range` (5), `omni_attenuation` (1), `omni_shadow_mode` (1 = cube). **SpotLight3D**: `spot_range` (5), `spot_attenuation` (1), `spot_angle` (45, half-angle; shadows fail above 89), `spot_angle_attenuation` (1).

**GeometryInstance3D** (`class_geometryinstance3d.rst`). `cast_shadow` (1), `gi_mode` (1 = static), `lod_bias` (1.0), `visibility_range_begin/end/_margin/fade_mode`, `ignore_occlusion_culling`, `extra_cull_margin`, `custom_aabb` (all zero = automatic; a huge box stops frustum culling), `material_override`, `material_overlay` (a second pass on every surface), `transparency` (Forward+ only; above 0 forces the transparent pipeline but keeps shadows), `set_instance_shader_parameter(name, value)` (needs `instance uniform`). `gi_lightmap_scale` is deprecated: use `gi_lightmap_texel_scale`.

**VisualInstance3D**: `layers` (1; 20 layers), `set_layer_mask_value(1..20, bool)`, `sorting_offset`, `sorting_use_aabb_center`, `get_instance() -> RID`, `get_base() -> RID`.

**MeshInstance3D**: `mesh`, `skeleton`, `skin`, `set_surface_override_material(surface, material)`, `get_active_material(surface)` (override > mesh material, with `material_override` above both, inferred from the member names), `bake_mesh_from_current_skeleton_pose()`.

**Mesh / ArrayMesh**: `add_surface_from_arrays(primitive, arrays, blend_shapes=[], lods={}, flags=0)` with `arrays.resize(Mesh.ARRAY_MAX)`, `shadow_mesh`, `custom_aabb`, `lightmap_unwrap(transform, texel_size)`, `surface_update_vertex_region(surf, offset, bytes)` for in-place vertex updates, `clear_surfaces()`.

**MultiMesh / MultiMeshInstance3D**: see the MultiMesh section. The node has `multimesh`, and everything else comes from GeometryInstance3D. It is not included in occluder baking.

**Material / BaseMaterial3D / StandardMaterial3D / ORMMaterial3D** (`class_basematerial3d.rst`). `render_priority`, `next_pass`. `transparency`: `DISABLED` 0, `ALPHA` 1 (slowest, no shadows), `ALPHA_SCISSOR` 2 (depth prepass, casts shadows), `ALPHA_HASH` 3, `ALPHA_DEPTH_PRE_PASS` 4 (discards alpha < 0.99 in the prepass and < 0.1 in shadows). `texture_filter` (3 = linear mipmaps; 5 = anisotropic), `shading_mode` (1 = per pixel), `cull_mode`, `depth_draw_mode`, `no_depth_test`, `disable_receive_shadows`, `disable_fog`, `disable_ambient_light`, `distance_fade_mode/min/max`, `use_z_clip_scale` + `z_clip_scale` (pull toward the camera so arms don't clip walls; lighting stays correct; SSAO/SSR may break), `use_fov_override` + `fov_override` (as if `KEEP_HEIGHT`), `alpha_antialiasing_mode`, and `stencil_*` (experimental). ORMMaterial3D takes one ORM texture.

**ShaderMaterial / Shader**: see `shaders.md`.

**Texture2D / ImageTexture / Image / CompressedTexture2D**. `ImageTexture.create_from_image(image)`, `update(image)` (same size, format and mipmaps; fast), `set_image(image)` (reallocates). The maximum texture size is 16384. `Texture2D.get_image()` reads back from the GPU (slow, and returns a copy). `CompressedTexture2D` is an imported `.ctex`. Only **VRAM Compressed** saves GPU memory. Lossless and lossy only save disk. Load imported textures with `load()`, not `Image.load()` (which may fail in exports). Textures above 8192 may fail on old GPUs.

**OccluderInstance3D / ArrayOccluder3D**. `occluder`, `bake_mask`, `bake_simplification_distance` (editor bake). `ArrayOccluder3D.set_arrays(vertices: PackedVector3Array, indices: PackedInt32Array)`, local space. The `vertices`/`indices` getters return copies.

**LightmapGI, ReflectionProbe, VoxelGI, FogVolume, Decal, Label3D**: see their sections. VoxelGI is Forward+ only and baked in the editor or at run time. Its extents are metre-scaled.

**Compositor / CompositorEffect**: see above.

## Where the code already does this

On main (b5d8e4d, after the docs audit), verified by grep:
- Sun, sky and environment: `src/map/map_lighting.gd` (`build`: `DirectionalLight3D` with 4 blended splits, `directional_shadow_max_distance` 8192, pancake 4096, `light_angular_distance` from `angulardiameter`; `PanoramaSkyMaterial`/`ProceduralSkyMaterial`; ambient colour or sky; `REFLECTION_SOURCE_SKY`; ACES; depth fog; no SSAO; glow; saturation). Lamps: `barn_light` builds `SpotLight3D`s with inverse-square attenuation and `shadow_bias` 1.0.
- Project settings: `project.godot` has `directional_shadow/size=8192`, `soft_shadow_filter_quality=4` (Soft High), `msaa_3d=2` (4x), `occlusion_culling/use_occlusion_culling=true` and `[shader_globals] probe_sun_visibility`.
- Map meshes cast from both faces: `src/map/map_importer.gd:267`. The skybox importer casts nothing: `src/map/map_loader.gd:228`.
- Layers and shadow tricks: `src/player/player_view.gd:118` (the camera leaves out `PlayerSim.UNSEEN_LAYER` = `1 << 19`), `:216` (the corpse moves between layers), `:382` (the `SHADOWS_ONLY` body copy); `src/player/player_sim.gd:319`; `src/player/view_model_projection.gd:59` (view models cast nothing); `src/combat/hitbox.gd:71`.
- MultiMesh: `src/effects/effect_quads.gd` (`_batch`: flags set before `instance_count`, `visible_instance_count`, huge `custom_aabb`; `finish`: writes `buffer` whole, 20 floats per card), `src/grenades/grenade_view.gd` (`_draw_cloud` and `_draw_fire` write `buffer` directly, 12 floats per instance, row-major, which matches the documented layout).
- Decals: `src/combat/bullet_impacts.gd:176` (a pool of `max_holes` = 96, `cull_mask` without `RigModel.LAYER`, fades at 0).
- Dynamic lights: `src/effects/muzzle_flashes.gd:125` (a pool, `shadow_enabled = false`), `src/bomb/c4_view.gd:59`, `src/grenades/grenade_view.gd:207` (one per event, tweened out). None casts shadows, so none adds a pipeline variant or an atlas slot.
- Performance monitors (headless): `scripts/profile_dust2.gd:290`.
- Test range: its own sun and environment (`maps/test_range/test_range.gd:1107`), a hitbox SubViewport (`:1092`), and Label3D `pixel_size` 0.25.

The render work (PRs #78, #82): `scripts/profile_render.gd` (`viewport_set_measure_render_time`, `viewport_get_render_info` per pass, `RENDER_*_MEM_USED`); `src/map/render_variants.gd` (toggles `msaa_3d`, `use_occlusion_culling`, the filter quality and `shadow_caster_mask`); `src/map/map_occluders.gd` (`ArrayOccluder3D.set_arrays`); `src/map/map_shadows.gd` (`LAYER = 1 << 10`); `src/map/map_lighting.gd:94` (`shadow_caster_mask = 0xFFFFFFFF & ~MapShadows.LAYER`, `light_angular_distance = 0.0`).

Fixed in the docs audit: the pages, `RenderVariants` and `MapLighting` said 2x MSAA and the highest soft filter (they are 4x and Soft High), and SSAO was on, drawing nothing; its `no_msaa` saving (1.7 ms at 4K) was for 4x.

Measured after a first shot on Sid's machine (2026-09-25, `scripts/profile_combat.gd`): the cost was not the pipelines (a surface compile or two, in frames under 6 ms, and no draw compilations) but the shaders. A `Shader` loaded by `preload` was compiled only when its first material asked for it, in that frame: 6.6 ms for `effect_add`, 10.3 for `effect_lit`. `EffectQuads._ready` now calls `get_rid()` on each as the map loads, and the first batches cost 0.1 ms. That the RID, and the compile, wait for the first `get_rid()` is inferred from these timings. Grenade materials (`grenade_view.gd:59` and later `StandardMaterial3D.new()`) are still first made during play and not measured; check a first grenade the same way.

Looks at odds with the docs (not verified on a GPU):
- `rendering/environment/ssao/fadeout_from/to` are still 50/300: if SSAO is ever turned back on (with `ssao_light_affect`, for a look like CS2's), scale both, and SSIL's, by about 39.37.
- `maps/test_range/test_range.gd:1092`: the hitbox SubViewport keeps the default `msaa_3d` 0 while the root is 4x. The pipeline docs say mixed MSAA levels cause stutters (test range only, minor). It also gets a 2048 positional atlas.
- The docs disagree on whether Compatibility reverses depth (`internal_rendering_architecture.rst` says every renderer does, `renderers.rst` says Compatibility does not). `FarMaterials.far_plane_depth` is 0.0 for every renderer, after the render work drew through Compatibility and found it reversed. See `shaders.md`.

## Not covered here

- Shaders (render modes, built-ins, depth, uniforms, shader cost): `shaders.md`.
- Particles (GPUParticles3D/CPUParticles3D, particle shaders): `tutorials/3d/particles/`, `tutorials/shaders/shader_reference/particle_shader.rst`. The project draws effects as MultiMesh cards.
- Sky and fog shaders: `tutorials/shaders/shader_reference/sky_shader.rst`, `fog_shader.rst`.
- HDR output to HDR displays: `tutorials/rendering/hdr_output.rst`. Physical light units: `tutorials/3d/physical_light_and_camera_units.rst`.
- Compute shaders and RenderingDevice: `tutorials/shaders/compute_shaders.rst`, `classes/class_renderingdevice.rst`.
- SDFGI/VoxelGI setup: `tutorials/3d/global_illumination/using_sdfgi.rst`, `using_voxel_gi.rst`. Faking GI: `faking_global_illumination.rst`.
- Viewports as textures and split screen: `tutorials/rendering/viewports.rst`, `tutorials/shaders/using_viewport_as_texture.rst`. Stretch modes: `tutorials/rendering/multiple_resolutions.rst`.
- Texture import options (VRAM compression, mipmaps, size limit): `tutorials/assets_pipeline/importing_images.rst`. Mesh import (LOD, shadow meshes, UV2): `tutorials/assets_pipeline/importing_3d_scenes/`.
- Physics interpolation (jitter between 64 Hz ticks): `tutorials/physics/interpolation/` and the physics page.
- Multithreaded rendering and thread-safe server APIs: `tutorials/performance/thread_safe_apis.rst`, `using_multiple_threads.rst`.
