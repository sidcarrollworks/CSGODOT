# Godot 4.7: shaders

Source: godot-docs branch 4.7 @9adca4c (2026-09-21). Read when: writing or changing a `.gdshader` or `.gdshaderinc` (the map, props, far scene, view models and effects), writing to `DEPTH`, `POSITION`, `ALPHA` or `light()`, reading the depth or screen texture, adding a uniform (plain, instance or global), or building shader code at run time.

The companion page `rendering.md` covers lights, shadows, culling, anti-aliasing, pipeline compilation stutter and measuring. The project's own decisions are in `reference/rendering.md` and `reference/performance.md`; this page does not repeat them.

## Rules for this project

- Put shared code in `.gdshaderinc` files and include them by absolute `res://` path. Only `.gdshaderinc` files can be included; relative paths work only in shaders saved to files; includes nest at most 25 deep and must not form a cycle (`shader_reference/shader_preprocessor.rst`).
- A material writes `ALPHA` only when it means to be transparent. Reading or writing `ALPHA` puts it on the transparent pipeline, and transparent materials cast no shadows and do not show up in the depth or screen texture (`shader_reference/spatial_shader.rst`, fragment built-ins and the note after the light built-ins).
- If `DEPTH` is written in any branch, write it in every branch. The API leaves the other branches undefined (`spatial_shader.rst`, `DEPTH`).
- If `POSITION` is written anywhere, it always wins. The shader then has to give it a correct value on every path, and the fragment is still lit at `VERTEX` (`spatial_shader.rst`, vertex built-ins).
- Depth is reverse-Z in Forward+: 1.0 is the near plane and 0.0 the far plane. A full-screen quad is `POSITION = vec4(VERTEX.xy, 1.0, 1.0);`. The pre-4.3 form `vec4(VERTEX, 1.0)` is wrong now (`tutorials/shaders/advanced_postprocessing.rst`).
- Ask the shader which renderer it runs under: use `CLIP_SPACE_FAR`, or `#if CURRENT_RENDERER == RENDERER_COMPATIBILITY`. Do not set a uniform from GDScript for this (`spatial_shader.rst` globals; `shader_preprocessor.rst`, built-in defines).
- Per-object values go in `instance uniform`, not in duplicated ShaderMaterials. The docs call instance uniforms faster because they allow more shader reuse. The practical limit is 16 per shader (`shading_language.rst`, per-instance uniforms; `classes/class_shadermaterial.rst`, `set_shader_parameter`).
- Mark colour textures and colour uniforms `source_color`. Forward+ requires it for sRGB data (`shading_language.rst`, "Using source_color").
- Avoid `discard` and alpha scissor on surfaces that don't need them. Either one stops the depth prepass from working for every surface using that shader (`shading_language.rst`, "Discarding").
- Prefer `#if` or a separate shader to a runtime `if` on a uniform when the branch is heavy. Every runtime branch is compiled and holds registers. Each `#define`, though, can double the pipeline variants (`shader_preprocessor.rst`, `#if`; `engine_details/architecture/internal_rendering_architecture.rst`).
- Never read a global uniform back with `global_shader_parameter_get` in a loop. Setting one is cheap; getting one makes the calling thread wait on the render thread (`shading_language.rst`, global uniforms).

## Files, includes and defines

`tutorials/shaders/shader_reference/shader_preprocessor.rst`

- `#include "path"` pastes in the whole `.gdshaderinc`. A `.gdshader` cannot be included. A `.gdshaderinc` can include another `.gdshaderinc`.
- The path is `res://...` or relative to the current file. Relative paths are allowed only in shaders saved as `.gdshader`/`.gdshaderinc`. A shader built in code or embedded in a resource must use absolute paths.
- A function or macro can be defined only once, so two includes that define the same name clash.
- `#include` may sit inside a function body. The editor may then flag errors in the include; the docs suggest wrapping it in an `#ifdef` guard.
- Other directives: `#define`/`#undef`, `#if`/`#elif`/`#else`/`#endif`, `#ifdef`/`#ifndef`, `defined()`, `#error`, and `#pragma disable_preprocessor`.
- Built-in defines (4.4+): `CURRENT_RENDERER` is 0, 1 or 2; `RENDERER_COMPATIBILITY` = 0, `RENDERER_MOBILE` = 1 and `RENDERER_FORWARD_PLUS` = 2.
- Cost: runtime branches are all compiled, and their variables can take up registers even when the branch never runs. `#if` cuts the code out, but each `#define` a scene uses multiplies the shader versions to compile (the preprocessor page; `internal_rendering_architecture.rst`, "Core material shaders").

## Render modes (spatial)

`shader_reference/spatial_shader.rst`, "Render modes"

- Blend: `blend_mix` (default), `blend_add`, `blend_sub`, `blend_mul`, `blend_premul_alpha`. Premultiplied alpha acts as add when fully transparent and as mix when fully opaque. A shaded material using it should write `PREMUL_ALPHA_FACTOR`.
- Depth draw: `depth_draw_opaque` (default: writes depth only for opaque geometry), `depth_draw_always`, `depth_draw_never`, `depth_prepass_alpha` (an opaque depth prepass for transparent geometry).
- Depth test:
  - `depth_test_disabled`.
  - `depth_test_default`: in Forward+ only, a pixel at exactly the same depth as another is also discarded.
  - `depth_test_inverted`: discards pixels that are in front; meant for stencil effects.
- Cull: `cull_back` (default), `cull_front`, `cull_disabled`.
- Shading:
  - `unshaded`: albedo only, no lighting, and `light()` is skipped.
  - `vertex_lighting`: `light()` is not run. The same applies when the project setting `rendering/shading/overrides/force_vertex_shading` is on, which is the default on mobile.
  - `diffuse_burley` (default), `diffuse_lambert`, `diffuse_lambert_wrap`, `diffuse_toon`.
  - `specular_schlick_ggx` (default), `specular_toon`, `specular_disabled`. `specular_disabled` turns off only the direct-light specular lobes; to remove reflections, write `SPECULAR = 0.0`.
- Receiving:
  - `shadows_disabled`: the surface receives no shadows but still casts them.
  - `ambient_light_disabled`: removes the ambient light and the radiance map. In 4.7.2's forward shader that takes every reflection with them, the sky's and the reflection probes' (read in `scene_forward_clustered.glsl`, rendering.md R5).
  - `fog_disabled`: no depth or volumetric fog. The docs recommend it for `blend_add` particles.
- Space:
  - `skip_vertex_transform`: you transform `VERTEX`, `NORMAL`, `TANGENT` and `BINORMAL` yourself, using `MODELVIEW_MATRIX`.
  - `world_vertex_coords`: those values arrive in world space instead of model space.
  - `ensure_correct_normals` is listed but "currently unimplemented".
- Anti-aliasing: `alpha_to_coverage` and `alpha_to_coverage_and_one`. They pair with the `ALPHA_ANTIALIASING_EDGE` and `ALPHA_TEXTURE_COORDINATE` outputs, and the edge value should sit below `ALPHA_SCISSOR_THRESHOLD`.
- Debug and other: `wireframe`, `debug_shadow_splits` (colours each directional split), `shadow_to_opacity` (for AR), `particle_trails`, `sss_mode_skin`.
- Stencil modes (`read`, `write`, `write_if_depth_fail`, `compare_*`) are marked experimental and may change in the next minor version. Stencil can be read only in the transparent pass, not the opaque pass. Compositor effects cannot copy the main stencil buffer.

## Built-ins that matter here

`shader_reference/spatial_shader.rst`

### Global (every function)

- `TIME`: seconds since the engine started. It wraps every 3600 s (`rendering/limits/time/time_rollover_secs`). It follows `Engine.time_scale` and ignores pause. For time that must match the simulation, set a global uniform yourself (inferred for this project: from `SimClock`).
- `OUTPUT_IS_SRGB`: true in Compatibility; false in Forward+ and Mobile.
- `CLIP_SPACE_FAR`: 0.0 in Forward+ and Mobile, -1.0 in Compatibility.
- `IN_SHADOW_PASS`: true while the shader draws into a shadow map. Use it to draw something differently in its shadow.
- `PI`, `TAU` and `E` are built in.

### Vertex

- `VERTEX`, `NORMAL`, `TANGENT` and `BINORMAL` arrive in model space (world space with `world_vertex_coords`). The engine moves them to view space for the fragment stage.
- `POSITION` (out, clip space): if written on any branch, it replaces the modelview and projection transforms, and `VERTEX` no longer places the vertex. `fragment()` still receives the `VERTEX` value, so lighting stays at the true position.
- `Z_CLIP_SCALE` (out): if written on any branch, it scales the vertex towards the camera so it doesn't clip into walls. Lighting and shadows stay correct, but SSAO and SSR "may break with lower scales"; keep it near 1.0. BaseMaterial3D has the same thing as `use_z_clip_scale`/`z_clip_scale`, plus `fov_override` (degrees, behaves like `KEEP_HEIGHT`) (`classes/class_basematerial3d.rst`).
- `MODELVIEW_MATRIX` (inout) is "better suited when floating point issues may arise" than `VIEW_MATRIX * MODEL_MATRIX` far from the origin.
- `PROJECTION_MATRIX` is inout in `vertex()`.
- In the shadow pass, `INV_VIEW_MATRIX` is the light's view. `MAIN_CAM_INV_VIEW_MATRIX` is the real camera's.
- `COLOR` is clamped to 0..1 at 8 bits per channel. For data that needs more precision, use `CUSTOM0` to `CUSTOM3` (UV3 to UV8 in pairs).
- `INSTANCE_CUSTOM` is the MultiMesh/particle custom data; `INSTANCE_ID` and `VERTEX_ID` are also available.
- `CAMERA_VISIBLE_LAYERS` (uint): the cull mask of the camera drawing the current pass.
- `NODE_POSITION_WORLD`, `CAMERA_POSITION_WORLD`, `CAMERA_DIRECTION_WORLD` and `VIEWPORT_SIZE` are available.

### Fragment

- `FRAGCOORD.xy` is in pixels, with the origin at the top left. `FRAGCOORD.z` is the fragment's depth, and is the depth written unless `DEPTH` is.
- `DEPTH` (out, 0..1): if written in any branch, it must be written in all of them.
- `VERTEX` is in view space (not guaranteed with `skip_vertex_transform`). `LIGHT_VERTEX` (inout) moves where the fragment is lit and shadowed without moving the fragment.
- `SCREEN_UV`, `VIEW`, `FRONT_FACING`, `INV_VIEW_MATRIX`, `INV_PROJECTION_MATRIX`.
- `NORMAL_MAP` is tangent-space. Its blue channel is ignored and rebuilt, which is why RGTC two-channel maps work. `NORMAL_MAP_DEPTH` defaults to 1.0.
- `ALPHA`: reading or writing it sends the material to the transparent pipeline.
  - `ALPHA_SCISSOR_THRESHOLD`: if written on any branch, pixels below the threshold are discarded.
  - `ALPHA_HASH_SCALE` and `PREMUL_ALPHA_FACTOR` are also here.
  - How a material that writes both `ALPHA` and `ALPHA_SCISSOR_THRESHOLD` is classed is below, under "Alpha, discard and the depth prepass".
- `AO` is for baked AO. `AO_LIGHT_AFFECT` (default 0.0) sets how much AO darkens direct light.
- `EMISSION` is HDR. `SPECULAR` defaults to 0.5, and 0.0 turns off reflections.
- `FOG`, `RADIANCE` and `IRRADIANCE` (vec4): writing any of them on any branch blends your rgb over the engine's by `.a`.
- `SCREEN_TEXTURE` and `DEPTH_TEXTURE` were removed in Godot 4. Use `sampler2D` uniforms with `hint_screen_texture` or `hint_depth_texture`.
- Outputs that are never written are optimised away: "if you don't write to them, Godot will optimize away the corresponding functionality".

### Light

- `light()` runs "for every light in every pixel", in a loop per light type.
  - Defining it replaces the built-in diffuse and specular for every light type.
  - Add with `+=` to `DIFFUSE_LIGHT` and `SPECULAR_LIGHT`.
  - It is not run under `unshaded`, `vertex_lighting` or forced vertex shading.
- `LIGHT_COLOR` = colour × energy × PI. The PI is there because PBR formulas divide by PI.
- `SPECULAR_AMOUNT`: for omni and spot lights, 2.0 × `light_specular`; for directional lights, 1.0.
- `ATTENUATION` covers both distance and shadow. `LIGHT` is the light vector in view space.
- `LIGHT_IS_DIRECTIONAL` is true on a directional light's pass. The example in the docs also uses `LIGHT_IS_AREA`, `LIGHT_AREA_DIFFUSE_MULTIPLIER` and `LIGHT_AREA_SPECULAR_MULTIPLIER` for area lights (new in this branch).
- `ALBEDO`, `BACKLIGHT`, `METALLIC` and `ROUGHNESS` come in read-only. Writing `ALPHA` in `light()` also makes the material transparent.
- In Compatibility, `fragment()` works in sRGB and `light()` in linear light. Godot turns `ALBEDO` and `EMISSION` to linear after `fragment()` returns (`drivers/gles3/shaders/scene.glsl`, "Convert colors to linear", read on 4.7.2), so a `source_color` texture read in `fragment()` gives sRGB values, and `ALBEDO` in `light()` is not the value `fragment()` wrote. Forward+ and Mobile are linear in both.
  - A colour handed from `fragment()` to `light()` in a varying and set against `ALBEDO` there has to be converted first, under `#if CURRENT_RENDERER == RENDERER_COMPATIBILITY`.
  - Found building `src/player/character.gdshader` (2026-09-25): before its colours were converted, the ratio of the two came out above 1 and its test sphere drew about a third brighter in the cloud's Compatibility renders.

## Depth, linear depth and reverse-Z

`tutorials/shaders/advanced_postprocessing.rst`, `tutorials/shaders/screen-reading_shaders.rst`

- Since 4.3 the depth buffer is reversed: 1.0 is the near plane and 0.0 the far plane. Values are nonlinear, so a raw depth texture looks black except up close.
- Forward+ and Mobile use Vulkan NDC, with z in [0, 1]. Compatibility uses OpenGL NDC, with z in [-1, 1].
- To linearise a `hint_depth_texture` sample:
  ```glsl
  uniform sampler2D depth_texture : hint_depth_texture;
  float depth = texture(depth_texture, SCREEN_UV).x;
  vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);        // Forward+ / Mobile
  // vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;     // Compatibility
  vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
  view.xyz /= view.w;
  float linear_depth = -view.z;                          // in units, i.e. inches here
  vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
  vec3 world_position = world.xyz / world.w;
  ```
  The docs pick between the two NDC lines with `#if CURRENT_RENDERER == RENDERER_COMPATIBILITY`.
- For a full-screen quad, use a QuadMesh 2×2 with `POSITION = vec4(VERTEX.xy, 1.0, 1.0);` and set `extra_cull_margin` as large as possible so the quad is never frustum-culled.
- In 3D the screen texture is copied after the opaque pass and before the transparent pass, so it holds no transparent objects. A material that samples `hint_screen_texture` is itself treated as transparent (`screen-reading_shaders.rst`).
- `hint_normal_roughness_texture` is Forward+ only.
- The docs are inconsistent on whether Compatibility is reverse-Z. The postprocessing page gives a different NDC formula for it, but no different far value. `CLIP_SPACE_FAR` = -1.0 there means the far plane is at clip z = -1 (inferred: not reversed). `rendering.md` lists the other page that disagrees. Code that must work in both renderers should take the far end from `CLIP_SPACE_FAR` rather than assume it.

## Uniforms

`shader_reference/shading_language.rst`, "Uniforms"

- Hints:
  - `source_color`: colour, for vec3/vec4 and sampler2D.
  - `hint_range(min, max[, step])` and `hint_enum("A", "B:30")`.
  - `hint_normal`, `hint_default_white`, `hint_default_black`, `hint_default_transparent` and `hint_anisotropy`.
  - `hint_roughness[_r|_g|_b|_a|_normal|_gray]`: the roughness limiter on import.
  - `filter_nearest` or `filter_linear`, each with optional `_mipmap` and `_anisotropic` suffixes.
  - `repeat_enable` and `repeat_disable`.
  - `hint_screen_texture`, `hint_depth_texture`, `hint_normal_roughness_texture`.
- `source_color` on sRGB textures is required in Forward+ and Mobile, and optional in Compatibility. Normal, roughness, metallic and height maps usually go without it.
- Defaults go after the hint: `uniform vec4 c : source_color = vec4(1.0);`. Uniforms and varyings start at zero if not set (`shading_language.rst`, near the top). `group_uniforms` only groups them in the inspector.
- Size limit: 65536 bytes per shader on most desktop GPUs (4096 vec4), 16384 on mobile. vec2 and vec3 pad to vec4; scalars don't pad; bool pads to int. Arrays count in full.
- Setting from code:
  - `ShaderMaterial.set_shader_parameter(name, value)`. The name is case-sensitive and must match the code, not the inspector's capitalised label.
  - The change affects every user of that material.
  - GDScript types map to GLSL types as the table in the docs shows. A type mismatch gives no error (the uniform keeps its value; inferred from the docs having no error path).
- Global uniforms (`global uniform ...`):
  - Visible to every shader type. The uniform must exist in Project Settings > Shader Globals when the shader is saved, or compilation fails. A default in the code is ignored.
  - Set them with `RenderingServer.global_shader_parameter_set`, which "can be done as many times as desired without impacting performance".
  - `global_shader_parameter_add`/`_remove` at run time costs something.
  - `global_shader_parameter_get` makes the calling thread wait on the render thread; the docs advise keeping your own copy.
- Instance uniforms (`instance uniform ...`):
  - Set on the GeometryInstance3D with `set_instance_shader_parameter`, not on the material. They work in spatial and canvas_item shaders only.
  - Scalars and vectors only: no textures and no arrays. The docs' workaround is a texture array indexed by an instance int.
  - Practical maximum of 16 per shader. Slot indices run 0 to 15, and `instance_index(n)` pins a uniform to a slot.
  - When a mesh has several materials, the first material's parameters "win" unless name, index and type all match.
  - On a MultiMesh the value applies to the whole node, not to each instance (inferred from "set on each GeometryInstance3D"). Per-instance data there goes through `INSTANCE_CUSTOM` or `COLOR`.

## Varyings and precision

`shading_language.rst`, "Varyings", "Precision"

- `varying` carries data from vertex to fragment, or from fragment to `light()`. Arrays are allowed.
- A varying may not be assigned in `light()` or in a custom function; only in `vertex()` or `fragment()`.
- Qualifiers: `flat` (not interpolated) and `smooth` (perspective-correct, the default).
- Precision: `lowp` (about 8-bit, 0..1), `mediump` (about 16-bit) and `highp` (32-bit, the default). They help in fragment code on mobile. The vertex stage "needs full precision most of the time".

## Alpha, discard and the depth prepass

`shading_language.rst` "Discarding"; `spatial_shader.rst`

- `discard` "will prevent the depth prepass from being effective on any surfaces using the shader". A discarded pixel still pays for the vertex shader.
- `ALPHA_SCISSOR_THRESHOLD` discards pixels, so it has the same cost (inferred: it compiles to a discard).
- Writing `ALPHA` normally makes a material transparent. When `ALPHA_SCISSOR_THRESHOLD` is also written, the material stays in the opaque pass as alpha-tested, as BaseMaterial3D's scissor mode does (inferred; the built-ins table does not say this).
- Whether a material is transparent, scissored or opaque is decided when the shader compiles, from which outputs appear anywhere in the code. A runtime `if` around the write does not make it opaque when the condition is false (inferred from "if written to on any branch").
- Transparent materials: cast no shadows, are absent from the depth and screen textures and from SSR and refraction, sort per object (see `tutorials/3d/3d_rendering_limitations.rst`), and show only rough SDFGI reflections.

## Cost and variants

- Every runtime branch is compiled, and its variables can take registers. High VGPR use slows the shader "even if all pixels evaluate to true or false in a given frame" (`internal_rendering_architecture.rst`).
- Each `#define` that differs between materials is a separate shader version to compile. Each distinct Shader is its own pipeline set. A ShaderMaterial duplicated with other uniform values shares its shader but is another material, so it breaks batching (inferred). An instance uniform keeps one material (`class_shadermaterial.rst`).
- Pipeline compilation, ubershaders, and the shader baker for exports are on `rendering.md`, "Shader and pipeline compilation stutter". A shader first used at run time (spawned effects, far variants built in code) compiles then, even one loaded by `preload`: measured 6.6 to 10.3 ms in the frame of its first material, until `EffectQuads` called `get_rid()` on its four as the map loads.

## Class notes

- **Shader** (`classes/class_shader.rst`):
  - `code` is "the shader's code as the user has written it, not the full generated code": `#include` lines stay as they are.
  - `get_shader_uniform_list(get_groups=false)` returns property-list-style dictionaries.
  - `set_default_texture_parameter(name, texture, index=0)`.
  - `inspect_native_shader_code()` works only in the editor.
  - A Shader built in code needs absolute include paths (see Files).
- **ShaderInclude**: the resource behind `.gdshaderinc`.
- **ShaderMaterial** (`classes/class_shadermaterial.rst`):
  - `set_shader_parameter`/`get_shader_parameter` names are case-sensitive, and a change reaches every instance using the material.
  - The docs prefer per-instance uniforms to `duplicate()` because they are faster.
- **Material** (`classes/class_material.rst`):
  - `render_priority` runs from `RENDER_PRIORITY_MIN` -128 to `RENDER_PRIORITY_MAX` 127. Higher draws on top; it applies to spatial materials only.
  - `next_pass` draws the object again with another material, not necessarily right after the first.
  - `inspect_native_shader_code()` is also editor-only.
- **BaseMaterial3D** (`classes/class_basematerial3d.rst`):
  - `use_z_clip_scale` with `z_clip_scale` (default 1.0), and `use_fov_override` with `fov_override` (default 75.0). These are the built-in way to draw view models.
  - Transparency modes map onto the same `ALPHA`, scissor and hash outputs.
- **GeometryInstance3D** (`classes/class_geometryinstance3d.rst`):
  - `set_instance_shader_parameter(name, value)` requires `instance uniform` in the code. It is case-sensitive, and not available to fog, sky or particle shaders.
  - `get_instance_shader_parameter` reads the value back.
- **RenderingServer** (`classes/class_renderingserver.rst`):
  - `global_shader_parameter_set`, `_add`, `_remove`, `_get` (slow, waits on the render thread), `_get_list` and `_get_type`. The `GLOBAL_VAR_TYPE_*` constants name the types.
  - `instance_geometry_set_shader_parameter` is the server-side form of the instance uniform setter.

## Where the code already does this

Main at `b5d8e4d`, after the render work (PRs #78, #82) and the docs audit.

- **Includes.** All includes use absolute `res://` paths, so the runtime-built far shaders resolve them.
  - `src/map/lightmapped.gdshader`, `probe_lit.gdshader`, `blend_material.gdshader`, `lightmapped_overlay.gdshader` and `far.gdshader` include `lightmap`, `baked_light`, `prop_features`, `probe_lit` and `far`.
  - `src/effects/effect_*.gdshader` include `effect_quad.gdshaderinc`, which includes `src/player/player_draw.gdshaderinc`.
  - `effect_lit.gdshader:8` does `#define LIT` before the include. It is the only preprocessor switch, and it gives exactly one extra shader, matching the docs' advice.
- **Custom `light()`.**
  - `src/map/baked_light.gdshaderinc:39-71` writes out Burley and Schlick-GGX, using `LIGHT_COLOR`'s PI and `SPECULAR_AMOUNT` as documented.
  - It hands the sun's baked shadow over in the varying `baked_sun` (fragment→light, which the docs allow), and applies it only when `LIGHT_IS_DIRECTIONAL`.
  - Until rendering.md R5 (2026-09-25) the baked bounce light came through `light()` too, added only for the directional light, so with no sun in view there was none, and a second sun would have added it twice. Since R5 each shader writes it to `IRRADIANCE` in `fragment()`, as Godot's ambient light, whatever lights are drawn.
  - `effect_quad.gdshaderinc:44-46` is the lit smoke's `light()`.
  - `src/player/character.gdshader` (rendering.md R7, 2026-09-25) is the player models' `light()`: Lambert, GGX with Schlick-Smith visibility, and on cloth Charlie's sheen under Neubelt's visibility. It darkens the direct light by the occlusion texture as CS2 does. Godot's `AO_LIGHT_AFFECT` would darken the direct diffuse and specular by one amount, where CS2 has one for each.
  - It converts its colours to linear light for the Compatibility renderer (see Light above).
- **Render modes.**
  - Map shaders: `blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx`. They also had `ambient_light_disabled`, all but `far.gdshader:2`, until rendering.md R5 moved their baked light to `IRRADIANCE`; the flag took every reflection with it. `far` takes the environment's ambient light.
  - `src/player/character.gdshader` has `blend_mix, depth_draw_opaque, cull_back` and no diffuse or specular mode, since its own `light()` replaces both.
  - Effects: `unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled` with add, mix or premul blending. `effect_lit` is shaded with `diffuse_lambert, specular_disabled` and keeps fog. These match the docs' advice for additive particles.
- **`POSITION` override for view models.**
  - `player_draw.gdshaderinc` narrows the FOV and squeezes depth by hand in clip space through the instance uniform `view_model_projection`. `probe_lit.gdshader:25`, `src/player/character.gdshader:117` and `effect_quad.gdshaderinc:26` use it.
  - This follows the docs: the fragment keeps the true `VERTEX` for lighting.
  - 4.7's `Z_CLIP_SCALE` (vertex out) and BaseMaterial3D `fov_override` do the same job built in. They are an option if the hand-rolled version ever breaks SSAO or shadows. The docs warn that `Z_CLIP_SCALE` below 1 can upset SSAO and SSR, and the manual squeeze presumably can too (inferred).
- **Instance uniforms.**
  - Ten on the probe-lit shader (`probe_lit.gdshaderinc:12-17` and `:31-34`: six probe values and four for its shadow page) plus `view_model_projection`, 11 in all, under the 16 limit. Adding more should be counted.
  - Twelve on the character shader (`src/player/character.gdshader`): the probe-lit shader's 11, then `ambient_from_probes`. Godot numbers the slots in the order the uniforms are declared (`servers/rendering/shader_language.cpp`, `uniform.instance_index = instance_index++`, read on 4.7.2) and reads them by slot, so a mesh with surfaces on both shaders needs the shared ones in the same slots. The character shader's includes declare the shared ones first, in the same order, for that; `tests/run_character_checks.gd` compares the two lists.
  - `probe_lit.gdshaderinc` also reads `global uniform sampler3D probe_sun_visibility`, with the matching `[shader_globals]` entry and the matching `[shader_globals]` entry in `project.godot`. A global uniform must be in Project Settings before a shader using it is saved.
- **Effects on MultiMesh.** `effect_quad.gdshaderinc:25` reads the UV rect from `INSTANCE_CUSTOM`, which is correct for MultiMesh custom data. Its `view_model_projection` instance uniform can only apply to the whole MultiMesh node (inferred).
- **Conditional alpha scissor (measured: no cost).**
  - Code: `src/map/lightmapped.gdshader:32-35`, `src/map/probe_lit.gdshader:36-39`, `src/map/far.gdshader:29-32`, and the same block in `src/player/character.gdshader:132-135`.
  - All three write `ALPHA` and `ALPHA_SCISSOR_THRESHOLD` inside `if (alpha_scissor >= 0.0)`. Per the docs, "if written to on any branch" is decided when the shader compiles. Every material on these shaders, including the opaque walls and floors that set `alpha_scissor < 0`, is therefore compiled as alpha-tested (inferred).
  - Alpha-tested surfaces lose the depth prepass (the discard note) and pay for the branch in registers, so a separate scissored shader or an `#ifdef ALPHA_SCISSOR` variant looked like the fix.
  - Measured in the docs audit on Sid's machine: copies of the six shaders without the branch, on all 702 opaque dust2 materials, changed the GPU's frame by at most 0.02 ms at 4K and 0.04 ms at 1080p, within the noise (`reference/rendering.md`, "Measured"). Nothing to change.
- **The 3D skybox's depth squeeze is in the vertex stage** (R2). `far.gdshader` and the variants `FarMaterials.variant_of` builds set `POSITION = far_position(clip, CLIP_SPACE_FAR)`, which keeps early depth rejection; writing `DEPTH` per fragment, as before, cost 0.8 ms at 1080p. A shader with a `vertex()` of its own still gets `DEPTH = far_depth(FRAGCOORD.z)` at the top of `fragment()`, unconditionally, so it meets the "all branches" rule.
- **`far_plane_depth`** is 0.0 for every renderer (`FarMaterials.far_plane_depth`), after the render work drew through Compatibility and found it reversed too, where the docs disagree (see Depth above). Only the per-fragment path reads it.
- **Runtime-built shaders.**
  - `far_materials.gd:97-108` (`variant_of`) builds a new `Shader` from `base.code` with string replaces, and caches it per base shader in `_variants`.
  - Because `Shader.code` is the user code, `#include` lines survive, and they are absolute, so they resolve.
  - Each variant is a new pipeline compiled when first used (inferred). See `rendering.md` on precompilation.
- **Normal maps.** `lightmapped.gdshader:40` and `far.gdshader:34` write `NORMAL_MAP = vec3(rg, 1.0)`. The docs say blue is ignored and rebuilt, so the 1.0 is harmless.
- **Overlays.** `src/map/lightmapped_overlay.gdshader:31` writes `ALPHA` with no condition. It is intentionally transparent (decal-like overlays), so it casts no shadows and is not in the depth texture.
- **Global uniform upkeep.** A search of `src/` found no `global_shader_parameter_get`.

## Not covered here

- Sky, fog, particle, canvas_item and texture-blit shaders (`shader_reference/sky_shader.rst`, `fog_shader.rst`, `particle_shader.rst`, `canvas_item_shader.rst`, `texture_blit_shader.rst`).
- Compute shaders and the compositor (`tutorials/shaders/compute_shaders.rst`; `rendering.md` has a line on CompositorEffect).
- Visual shaders (`tutorials/shaders/visual_shaders.rst`).
- The built-in function list (`shader_reference/shader_functions.rst`), which is standard GLSL ES 3.0 plus Godot extras.
- Converting GLSL (`converting_glsl_to_godot_shaders.rst`) and the style guide (`shaders_style_guide.rst`).
- Pipeline compilation, ubershaders and the shader baker: in `rendering.md`.
- `reference/rendering.md` and `reference/performance.md`: the project's decisions and measurements.
