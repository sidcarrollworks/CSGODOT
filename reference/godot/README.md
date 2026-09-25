# Godot 4.7 for this project

What the Godot documentation says that matters to CSGODOT, read from the
official docs and checked against this repo's code. Sid asked for it on
2026-09-25 so that agents building a feature work from the engine's own
documentation rather than from memory, which is often Godot 3 or an older 4.x.

Source: [godot-docs](https://github.com/godotengine/godot-docs) branch `4.7`
at commit `9adca4c` (2026-09-21), matching `config/features` "4.7" in
`project.godot` and the 4.7.2 binary CI runs. The docs' "engine details",
manual (`tutorials/`) and class reference (`classes/`) were read; 2D, XR,
mobile, C# and editor walkthroughs were left out.

## How to use these pages

1. Before building or changing a feature, find its row in the table below and
   read that page's **Rules for this project** section, then the sections
   your change touches. Each page starts with a "Read when" line.
2. Look up an engine class in the class index below. Each page's
   **Class notes** give the members this project needs, with exact 4.7
   signatures and defaults.
3. For anything the pages leave out, search the full docs:
   `scripts/godot_docs.sh` fetches them (text only, about 45 MB) into the
   gitignored `.godot-docs/`, then for example
   `rg -n "cast_motion" .godot-docs/classes/class_physicsdirectspacestate3d.rst`.
   Every section cites the doc file it came from, as a path under
   `.godot-docs/`. The class reference is `classes/class_<lowercase name>.rst`.
4. Where a page says "(inferred)", the docs do not say it outright. Check it
   before relying on it.
5. The project's own decisions come first: `CLAUDE.md`, `reference/research/`,
   `reference/systems/`, `reference/performance.md` and `reference/rendering.md`
   (arriving with the render pull requests). These pages say what the engine
   does, not what the game should do.

When `project.godot` moves to a new Godot version, change `BRANCH` and
`COMMIT` in `scripts/godot_docs.sh`, re-read the docs' upgrade page for that
version (`tutorials/migrating/`), and correct the pages and this source line.

## Which page for which task

| Task | Page |
|---|---|
| Any `.gd` file: typing, containers and their copy rules, caches, signals, performance of GDScript | [gdscript.md](gdscript.md) |
| Adding a system to the tick, process order, node lifecycle, pausing, reading files, loading resources, headless runs and exit codes, threads | [main-loop.md](main-loop.md) |
| Rays, hull traces, shape sweeps, collision layers, Jolt settings, rigid bodies, ragdoll joints | [physics.md](physics.md) |
| Vectors, transforms, angles, Source Z-up to Godot Y-up, float precision | [math.md](math.md) |
| Lights, shadows, environment, anti-aliasing, culling, LOD, lightmaps, GPU cost, measuring a frame | [rendering.md](rendering.md) |
| Writing or changing a `.gdshader` | [shaders.md](shaders.md) |
| Importing models, textures, sounds and maps; hand-editing `.tscn`, `.tres` and `.import` files | [import.md](import.md) |
| Skeletons, AnimationTree, bone attachments, hitboxes on bones, ragdolls | [animation.md](animation.md) |
| Sound players, buses, attenuation in inches, reverb, mixing | [audio.md](audio.md) |
| Mouse look, keys, binds, input event order | [input.md](input.md) |
| HUD, menus, buy menu, scoreboard, UI scaling at 4K | [ui.md](ui.md) |
| Bot paths, AStar3D, NavigationServer3D | [navigation.md](navigation.md) |
| Netcode (UserCmds up, snapshots down), ENet, dedicated server, exporting | [networking.md](networking.md) |
| Moving hot code to C++ (GDExtension), custom and server builds, profiling and debugging flags, engine threads | [engine.md](engine.md) |

## Class index

Classes with notes on each page. For a class not listed, search these pages
first (`rg -n "ClassName" reference/godot`), then `.godot-docs/classes/`.

- **gdscript.md**: Array, Callable, Dictionary, GDScript, Object, Packed*Array, RID, RandomNumberGenerator, RefCounted, RegEx, Signal, StringName, Variant
- **main-loop.md**: DisplayServer, Engine, FileAccess, MainLoop, Node, OS, Performance, ProjectSettings, ResourceLoader, SceneTree, Time, WorkerThreadPool
- **physics.md**: AnimatableBody3D, Area3D, CharacterBody3D, CollisionObject3D, Engine, Joint3D, KinematicCollision3D, PhysicsBody3D, PhysicsDirectSpaceState3D, PhysicsMaterial, PhysicsPointQueryParameters3D, PhysicsRayQueryParameters3D, PhysicsServer3D, PhysicsShapeQueryParameters3D, RigidBody3D, Shape3D and its subclasses, StaticBody3D, World3D
- **math.md**: AABB, Basis, Geometry3D, Node3D, Plane, Projection, Quaternion, Transform3D, Vector3, Vector3i
- **rendering.md**: Camera3D, Compositor, DirectionalLight3D, Environment, GeometryInstance3D, Light3D, LightmapGI, Material, Mesh, MeshInstance3D, MultiMesh, OccluderInstance3D, RenderingServer, ShaderMaterial, Texture2D, Viewport, VisualInstance3D
- **shaders.md**: the spatial shader language (render modes, built-ins, depth, instance uniforms)
- **import.md**: EditorScenePostImport, GLTFDocument, GLTFState, PackedScene, ResourceImporterScene, ResourceImporterTexture, ResourceImporterWAV, ResourceUID
- **animation.md**: Animation, AnimationLibrary, AnimationMixer, AnimationNode (and the blend nodes), AnimationPlayer, AnimationTree, BoneAttachment3D, PhysicalBoneSimulator3D, Skeleton3D, SkeletonModifier3D, SkeletonProfile, Skin
- **audio.md**: Area3D, AudioBusLayout, AudioEffectReverb, AudioListener3D, AudioServer, AudioStream, AudioStreamPlayer, AudioStreamPlayer3D, AudioStreamWAV
- **input.md**: DisplayServer, Input, InputEvent, InputEventKey, InputEventMouseButton, InputEventMouseMotion, InputMap, Node, Viewport
- **ui.md**: CanvasItem, CanvasLayer, Container, Control, Font, Label, StyleBoxFlat, TextureRect, Theme
- **navigation.md**: AStar3D, NavigationAgent3D, NavigationMesh, NavigationMeshSourceGeometryData3D, NavigationPathQueryParameters3D, NavigationRegion3D, NavigationServer3D
- **networking.md**: DisplayServer, ENetMultiplayerPeer, Engine, MultiplayerAPI, MultiplayerPeer, MultiplayerSynchronizer, OS, PacketPeerUDP, SceneMultiplayer, StreamPeerBuffer, UDPServer
- **engine.md**: ClassDB, Engine, EngineDebugger, GDExtension, GDExtensionManager, OS, Object, Performance, ResourceUID

## Mistakes the docs warn about that are easy to make here

These come up on several pages; the page named has the detail.

- Every length or speed default in Jolt, audio, navigation, SSAO and fog is
  in metres. Here 1 unit is 1 inch, so a default distance is about 39 times
  too short (physics.md, audio.md, navigation.md, rendering.md).
- Arrays, Dictionaries and packed arrays are shared when passed or returned;
  `duplicate()` is shallow unless `deep` is true, and a Resource's
  `duplicate()` shares its sub-resources by default (gdscript.md).
- The physics space may only be queried during `_physics_process`
  (physics.md).
- Mouse look must read `InputEventMouseMotion.screen_relative`, not
  `relative`, which the stretch mode scales (input.md).
- `physics/common/physics_jitter_fix` should be 0 for a network game or
  custom interpolation (main-loop.md, physics.md).
- An AnimationTree left on its default process mode poses bones per rendered
  frame; anything the tick reads from bones needs manual mode and `advance()`
  from the tick (animation.md).
- `anti_aliasing/quality/msaa_3d` is an enum: 2 means 4x (rendering.md).
- In a shader, writing `ALPHA` or `ALPHA_SCISSOR_THRESHOLD` on any branch
  makes the whole material alpha-tested (shaders.md).
- An exported build can't list `res://` for original file names and ships
  non-resource files (`.md`, `.csv`, `.json`) only if the export filter
  names them (networking.md, main-loop.md).

## Code at odds with the docs (2026-09-25, main at 86e73c2)

Found while reading, not fixed here: this pull request changes no code.
Items marked checked were confirmed by reading the code; the rest were read
from code only and need checking before a fix. Each is written up on the page
named, with file and line.

1. **Mouse sensitivity at 4K is half of CS2's** (checked). `PlayerInput.handle_event`
   (`src/player/player_input.gd:128-129`) aims with `motion.relative`, and
   `project.godot` uses the `canvas_items` stretch mode on a 1920x1080 base,
   so at 3840x2160 each count turns half as far. The docs say to use
   `screen_relative` for aiming. input.md.
2. **Hitboxes follow the drawn pose, not the tick** (checked that
   `SkinnedHitboxes` follows `skeleton_updated` and no tree is set to manual
   outside `scripts/profile_dust2.gd`). The AnimationTree runs per rendered
   frame, and the model's transform is interpolated between ticks, so where
   a shot lands can depend on frame rate. The docs' fix is
   `callback_mode_process = ANIMATION_CALLBACK_MODE_PROCESS_MANUAL` with
   `advance()` from the tick. animation.md.
3. **`physics_jitter_fix` is at its default 0.5** (checked); the docs
   recommend 0 for this project's case. Needs a frame-pacing check on Sid's
   machine. main-loop.md, physics.md, engine.md.
4. **Caches hand out their own Dictionaries** (checked for
   `WeaponSheet.rows()`), against `CLAUDE.md`'s rule; also
   `weapon_vdata.gd` and `surface_properties.gd`, and a shallow
   `WeaponData.duplicate()` in `item_registry.gd`. gdscript.md.
5. **Map shaders may all compile as alpha-tested**: `lightmapped`,
   `probe_lit` and `far` write `ALPHA_SCISSOR_THRESHOLD` inside a runtime
   `if`. Measure with `scripts/profile_dust2.gd` before and after any fix.
   shaders.md.
6. **Project settings read as the wrong thing**: `msaa_3d=2` is 4x MSAA, not
   2x; `soft_shadow_filter_quality=4` is Soft High, not the highest; SSAO fade
   distances are still metre defaults. rendering.md.
7. **Additive animation layers at half strength**: `AnimationTree.deterministic`
   is false while `player_model.gd` uses `Add2` and an additive `OneShot`;
   `AnimationNodeBlendSpace2D.sync` is deprecated for `sync_mode`.
   animation.md.
8. **Physics queried from `_process`** in `muzzle_flashes.gd` and
   `player_view.gd` (visual only; safe while physics stays on the main
   thread). physics.md.
9. **3D sounds start a tick late**: `AudioStreamPlayer3D.play()` waits for
   the next physics frame, and every 3D player keeps the automatic distance
   low-pass, which CS2 does not have. audio.md.
10. **Export blockers for later**: `DirAccess` listings of `res://` in
    `sound_bank.gd` and `map_importer.gd`, `FileAccess` reads of `.md`,
    `.csv`, `.json`, `.vmat` files, and a dedicated-server export strips the
    meshes `map_importer.gd` builds collision from. networking.md,
    main-loop.md.
