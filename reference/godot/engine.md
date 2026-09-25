# Godot 4.7: engine internals, GDExtension and custom builds

Source: godot-docs branch 4.7 @9adca4c (2026-09-21). Read when: deciding whether hot per-tick code (the collide-and-slide mover, hitscan, lag compensation) should leave GDScript; setting up a godot-cpp GDExtension; compiling a custom editor, export template or dedicated-server binary; stripping the engine with a build profile; considering `precision=double`; profiling or debugging the engine (headless or not); reasoning about which server runs on which thread.

## Rules for this project

- Keep the simulation on the main thread. Physics runs on the main thread unless `physics/3d/run_on_separate_thread` is on (default `false`), and turning it on "restricts API access to only physics process" and, with Jolt, makes errors name nodes `<unknown>` (`classes/class_projectsettings.rst`). `reference/performance.md` already assumes one thread for script, queries and frames.
- Do not turn on `rendering/driver/threads/thread_model` "Separate" to win frame time: the class reference marks it **Experimental**, "several known bugs which can lead to crashing", "not recommended for use in production" (`classes/class_projectsettings.rst`, `tutorials/performance/thread_safe_apis.rst`).
- Never read a value back from RenderingServer, PhysicsServer3D or PhysicsServer2D inside a tick or frame unless the value is the point (a ray hit is fine). "Calling any function that returns a value will stall them and force them to process anything pending" (`tutorials/performance/using_servers.rst`). `RenderingServer.global_shader_parameter_get()` is called out as a large penalty for this reason.
- A resource handed to a server by RID must be kept referenced by us: "references to a resource's RID are *not* counted" (`tutorials/performance/using_servers.rst`). A cache of meshes or shapes built for RenderingServer/PhysicsServer3D use must hold the Resource, not only the RID.
- Before writing C++, measure where the time goes. The hull trace itself is engine (Jolt) time, 20 to 50 us each (`reference/performance.md`); moving the mover to C++ only removes the GDScript and Variant overhead around the traces, not the traces (inferred from the numbers there and from `tutorials/performance/cpu_optimization.rst`: "Built-in engine functions run at the same speed regardless of the scripting language").
- If a GDExtension is added, build it against the **lowest** Godot 4.x it must run on and set `compatibility_minimum`; extensions work in later minor versions, not earlier ones (`tutorials/scripting/cpp/about_godot_cpp.rst`). Build it with `target=template_release` for anything measured; the default is a debug build (`tutorials/scripting/cpp/gdextension_cpp_example.rst`).
- A GDExtension is a Remote-unfriendly change: CI (`.github/workflows/tests.yml`) downloads the official 4.7.2 editor and has no C++ toolchain step; cloud threads would need SCons and a compiler to rebuild the library, and Sid's Windows machine needs its own `.dll`. Say so in the plan before starting one (inferred from the repo and `tutorials/scripting/cpp/build_system/scons.rst`).
- Stay single precision. Dust2 in Source units stays within a few thousand units of the origin, where a float32 step is about 0.0002 unit (0.005 mm at 1 unit = 1 inch); `precision=double` would mean rebuilding the editor, every export template and every GDExtension (`tutorials/physics/large_world_coordinates.rst`). See "Precision" below.
- Use `production=yes` for any binary that is measured or shipped as a server: it is `use_static_cpp=yes debug_symbols=no lto=auto` (`engine_details/development/compiling/introduction_to_the_buildsystem.rst`). For profiling with a C++ profiler, add `debug_symbols=yes` and never `strip` (`engine_details/development/profiling/index.rst`).
- For players' Windows builds prefer MinGW over MSVC: "the GDScript VM ... performs much better with MinGW compared to MSVC", and official binaries use MinGW (`engine_details/development/compiling/compiling_for_windows.rst`).
- In engine or extension C++, error macros fire when the condition is **true** (the reverse of GDScript `assert()`), and Godot "never crashes": return a usable value from `ERR_FAIL_*_V_MSG` (`engine_details/architecture/common_engine_methods_and_macros.rst`).

## How the engine is layered (`engine_details/architecture/godot_architecture_diagram.rst`)

- Three layers top to bottom: **Scene** (SceneTree, Node; `scene/`), **Servers** (rendering, audio, physics, navigation; `servers/`), **Drivers / platform** (graphics APIs, audio backends, `OS` and `DisplayServer` implementations; `drivers/`, `platform/`). **Core** (Object, ClassDB, Variant, containers, I/O) and **Main** (startup, shutdown, main loop) sit beside all three.
- Allowed include order in engine code: `editor/ -> scene/ -> servers/ -> core/`; `scene/` must not include `editor/` even under `#ifdef TOOLS_ENABLED` (`engine_details/editor/introduction_to_editor_development.rst`).
- Servers are singletons created at engine start. The scene system "is optional ... it can be completely bypassed", but not compiled out (`tutorials/performance/using_servers.rst`).
- Engine start order for modules (useful to know at what level a GDExtension class exists), from `engine_details/engine_api/custom_modules_in_cpp.rst`: `preregister_module_types` -> `preregister_server_types` -> `register_core_singletons` -> `register_server_types` -> `register_scene_types` -> editor types -> `register_platform_apis` -> `register_module_types` -> `initialize_physics` -> `initialize_navigation_server` -> `register_server_singletons` -> `register_driver_types` -> `ScriptServer::init_languages`.
- GDExtension initialization levels match: `INITIALIZATION_LEVEL_CORE` (0), `_SERVERS` (1), `_SCENE` (2), `_EDITOR` (3, editor only) (`classes/class_gdextension.rst`). The godot-cpp example registers its classes at `MODULE_INITIALIZATION_LEVEL_SCENE`.

### The main loop and which server runs where

- `MainLoop` is the abstract loop; `SceneTree` is the default. `godot -s my_loop.gd` or `application/run/main_loop_type` replaces it (`classes/class_mainloop.rst`). The project's `scripts/profile_dust2.gd` and every `tests/run_*.gd` are `extends SceneTree` scripts run this way.
- `_physics_process()` runs "before every physics step"; `_process()` "runs after the physics step in single-threaded games" (`tutorials/scripting/idle_and_physics_processing.rst`). So in one frame: zero or more ticks (each: every `_physics_process` in priority order, then the physics server steps), then `_process`, then drawing. `GameWorld` sets `process_physics_priority = -1000` to run first in each tick.
- At most `max_physics_steps_per_frame` ticks run per frame (default 8, project sets 16); below `ticks_per_second / max_steps` frames a second the game slows down rather than catching up ("physics spiral of death") (`classes/class_projectsettings.rst`, `classes/class_engine.rst`).

| Server | Own thread? | Setting / fact | Doc |
|---|---|---|---|
| PhysicsServer3D (Jolt) | No, main thread by default | `physics/3d/run_on_separate_thread = false`; when on, API access only from physics process, and `World3D.direct_space_state` only from `_physics_process()` on the main thread | `class_projectsettings.rst`, `class_world3d.rst`, `tutorials/physics/using_jolt_physics.rst` (the Jolt module supports the setting) |
| RenderingServer | Default model `1` ("safe"); "separate" puts the driver on its own thread (experimental) | `rendering/driver/threads/thread_model`, `--render-thread unsafe/safe/separate`; `RenderingServer.call_on_render_thread(callable)` and `is_on_render_thread()` for code touching RenderingDevice | `class_projectsettings.rst`, `class_renderingserver.rst`, command line tutorial |
| Occlusion culling (inside RenderingServer) | Parallel CPU raster with Embree; buffer resolution scales with CPU thread count | occluders are baked; moving/toggling an `OccluderInstance3D` is slow unless the shape is a quad or box | `engine_details/architecture/internal_rendering_architecture.rst` |
| NavigationServer3D | Map and region sync run async on a background thread by default | `navigation/world/map_use_async_iterations = true`, `region_use_async_iterations = true`; queries "can be called by threads and run in true parallel"; calls are queued to the sync phase | `class_projectsettings.rst`, `class_navigationserver3d.rst`, `thread_safe_apis.rst` |
| AudioServer | The mix runs in the audio driver's loop (inferred: `AudioServer.lock()` "Locks the audio driver's main loop") | `audio/driver/output_latency = 15` ms; `--audio-output-latency` overrides | `class_audioserver.rst`, `class_projectsettings.rst` |
| DisplayServer | n/a | with `--headless` "disables all rendering and window management functions. Most functions ... return dummy values"; `DisplayServer.get_name()` returns `"headless"` | `class_displayserver.rst` |
| WorkerThreadPool | Pool | `threading/worker_pool/max_threads = -1` = all logical cores | `class_projectsettings.rst` |

- Thread safety summary (`tutorials/performance/thread_safe_apis.rst`): the active scene tree is not thread-safe (use `call_deferred`/`set_deferred`); building a detached subtree on a thread is fine; GDScript Array/Dictionary element reads/writes from several threads are OK but any resize needs a Mutex; AStar2D/AStar3D/AStarGrid2D are not thread-safe; loading resources on one thread is supported, the same resource from several threads is not.
- `Object.call_deferred` runs "during idle time", mainly at the end of process and physics frames, draining until empty, so a method that defers itself loops forever (`classes/class_object.rst`). Deferred work is not tick-ordered; nothing that decides the game should use it (inferred from CLAUDE.md's tick rule).

## Object, Variant and RefCounted: what they cost GDScript

Sources: `engine_details/architecture/object_class.rst`, `variant_class.rst`, `core_types.rst`, `classes/class_object.rst`, `tutorials/scripting/cpp/core_types.rst`.

- A Variant is 24 bytes on 64-bit. GDScript "uses Variant as its atomic/native datatype". All Variant types except Nil and Object are non-nullable.
- Array and Dictionary are Variant containers with shared reference counting ("Modifications to a container will modify all references to it"). This is why the project's caches hand out copies. Packed*Arrays are `Vector<T>` (copy-on-write) in the engine but are passed by reference inside a Variant.
- `Object.set()/get()/call()/has_method()` "are **much** slower than direct references" (`classes/class_object.rst`). Typed GDScript "improves performance by using optimized opcodes when operand/argument types are known at compile time" (`tutorials/scripting/gdscript/static_typing.rst`).
- Engine calls with exactly known types use `ptrcall`, which "avoids using Variant"; calls from dynamically typed code go through the Variant `call` path, and vararg methods such as `emit_signal()` can never use ptrcall (`engine_details/engine_api/gdextension/gdextension_c_example.rst`).
- Plain `Object` must be `free()`d; `RefCounted` (and so `Resource`) frees itself when the last reference goes; `Node` frees its children. A freed Object's variable does not become `null`: test with `is_instance_valid()`, not `== null`. An Object in a boolean context is `false` when null or freed.
- Every query result object is a heap allocation: `move_and_collide()` returns a `KinematicCollision3D`, `PhysicsRayQueryParameters3D.create()` builds a RefCounted per ray (inferred cost; both are RefCounted classes). Reusing one query object per caller avoids that; C++ can call `PhysicsServer3D.body_test_motion(body, parameters, result)` with reused `PhysicsTestMotionParameters3D`/`PhysicsTestMotionResult3D` (signature in `classes/class_physicsserver3d.rst`).
- `get_instance_id()` is only valid for the current session; it is not a network id (`classes/class_object.rst`). In C++, store an `ObjectID` rather than a raw pointer to an object you do not own, and resolve it with `ObjectDB::get_instance()`; a `Variant` holding an Object should be read with `get_validated_object()` (`object_class.rst`).
- `Resource` paths are unique; `ResourceLoader::load` returns the already-loaded instance for a path ("only one resource loaded from a file ... at the same time") (`object_class.rst`).

## GDExtension (godot-cpp): when and what it costs

Sources: `engine_details/engine_api/gdextension/*.rst`, `tutorials/scripting/cpp/*.rst`.

### What it is

- A native shared library the engine loads at run time, without recompiling the engine. Three pieces: `gdextension_interface.h` (C functions both sides use), `extension_api.json` (the classes and methods Godot exposes), and a `.gdextension` file (how to load it).
- godot-cpp "has access to all functions that GDScript and C# have", plus some low-level access. GDExtension classes **are** in ClassDB (script `class_name` classes are not), so they show in reflection like engine classes (`classes/class_classdb.rst`).
- vs a C++ module: a module is compiled into the engine (every change recompiles the engine and every export template); a GDExtension builds only the library and the same library works in the editor and exported games. Modules get "deeper integration". The docs recommend GDExtension for game logic (`about_godot_cpp.rst`, `custom_modules_in_cpp.rst`).

### When to move code out of GDScript (for this project)

- Candidates by the numbers in `reference/performance.md`: bots' `run_command` (mostly movement) is 0.3 to 0.37 ms per player per tick, of which each hull trace is 20 to 50 us of engine time and 2 to 5 traces run per tick. The script share is what C++ would remove (inferred). A ray is 2 to 15 us.
- Lag compensation (rewinding 10 players' hitboxes per shot) and the mover are tight loops over math plus server queries: the case the docs name for C++ ("If your project is making a lot of calculations in its own code, consider moving those calculations to a faster language", `tutorials/performance/cpu_optimization.rst`).
- Hot paths that are mostly engine calls (one `intersect_ray` per bullet) gain little.
- Cross-boundary costs to design around: in godot-cpp, `Packed*Array` data lives on the Godot side and every `[]` calls into Godot. Take `.ptr()` / `.ptrw()` once and loop over the raw pointer (`tutorials/scripting/cpp/core_types.rst`). A `Packed*Array` argument coming from GDScript arrives through a Variant and "may be a copy", so a C++ function cannot modify the caller's array in place. Everything exposed must be Variant-compatible.
- The godot-cpp object pointer differs from the engine's internal Object pointer (extension instance allocated separately); usually unnoticeable.

### Setting one up

- Get godot-cpp on the branch matching the lowest targeted version (`git submodule add -b 4.x https://github.com/godotengine/godot-cpp`). Each branch ships an `extension_api.json` for that version and later. `master` tracks Godot master.
- Layout from the example: `project/` (the Godot project, with `bin/<name>.gdextension`), `godot-cpp/`, `src/` (`register_types.cpp/.h` plus classes), `SConstruct`.
- Class skeleton: `class X : public Node3D { GDCLASS(X, Node3D) protected: static void _bind_methods(); ... };` in `namespace godot`. Override virtuals like `void _physics_process(double delta) override;`.
- Binding: `ClassDB::bind_method(D_METHOD("set_amplitude", "p_amplitude"), &X::set_amplitude);` then `ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "amplitude"), "set_amplitude", "get_amplitude");`. Default args: trailing `DEFVAL(...)`. Enums need `VARIANT_ENUM_CAST(X::Mode)` and `BIND_CONSTANT`. Signals: `ADD_SIGNAL(MethodInfo("name", PropertyInfo(Variant::VECTOR2, "pos")))`, emitted with `emit_signal("name", ...)`. Connect to engine signals with `Callable(this, "method")` in godot-cpp (engine code uses `callable_mp`).
- Registration variants (`object_class.rst`): `GDREGISTER_CLASS` (instantiable, "should expect to be instantiated or freed automatically, for example by the editor or the documentation system"), `GDREGISTER_VIRTUAL_CLASS`, `GDREGISTER_ABSTRACT_CLASS`, `GDREGISTER_INTERNAL_CLASS`, `GDREGISTER_RUNTIME_CLASS` (runtime only, not in editor; useful for sim classes whose constructors must not run in the editor, inferred).
- Entry point: `extern "C" GDExtensionBool GDE_EXPORT example_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization)` building a `godot::GDExtensionBinding::InitObject`, calling `register_initializer`, `register_terminator`, `set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE)`, `return init_obj.init();`.
- Build: `scons platform=<platform>` (debug by default, library lands in `project/bin/`), `scons target=template_release` for optimized, `scons compiledb=yes` for `compile_commands.json`, `scons --clean`. CMake is supported but "secondary"; its `Debug` build type (symbols) is independent of Godot's `template_debug` (debug features) (`build_system/cmake.rst`).

### The `.gdextension` file (`engine_details/engine_api/gdextension/gdextension_file.rst`)

```ini
[configuration]
entry_symbol = "example_library_init"
compatibility_minimum = "4.7"
reloadable = true

[libraries]
linux.debug.x86_64 = "./libx.linux.template_debug.x86_64.so"
linux.release.x86_64 = "./libx.linux.template_release.x86_64.so"
windows.debug.x86_64 = "./x.windows.template_debug.x86_64.dll"
windows.release.x86_64 = "./x.windows.template_release.x86_64.dll"
```

- `[configuration]`: `entry_symbol` (required), `compatibility_minimum` (4.1+), `compatibility_maximum` (4.3+), `reloadable`, `android_aar_plugin`.
- `[libraries]` keys are feature tags joined by dots, matched **top to bottom**; put more specific keys first. Tags include `linux`/`windows`/`macos`, `debug`/`release`/`editor`, `single`/`double`, `x86_64`/`arm64`. Only the matching library is exported. Relative paths are recommended.
- `[dependencies]` lists extra shared libraries to copy on export (per feature set, with an optional subfolder). `[icons]` maps a class to a 16x16 SVG.
- Godot finds `.gdextension` files by scanning the project. The editor's `--recovery-mode` disables GDExtension addons among others (command line tutorial).

### Compatibility across 4.x

- Built for 4.N runs on 4.N+1 and later, not earlier. Exception: 4.0 extensions do not load in 4.1+.
- An extension must match the engine's float precision: a `precision=double` engine needs the extension rebuilt with an `extension_api.json` dumped from that engine; `REAL_T_IS_DOUBLE` is defined and `real_t` becomes `double` (`about_godot_cpp.rst`, `large_world_coordinates.rst`).
- For a custom engine build (other options such as `disable_3d=yes`, `precision=double`, or custom modules) dump its API and build against it: `godot --dump-extension-api` then `scons platform=<p> custom_api_file=<path>` or `localEnv["custom_api_file"] = "extension_api.json"` in SConstruct (`build_system/scons.rst`). The scons page says the file lands "in the executable's directory"; the command line tutorial says "in the current folder" (the two pages disagree; check where it appears).
- `--validate-extension-api <path>` checks an old dump against the current engine and exits non-zero on breakage. `--dump-extension-api-with-docs` includes docs. `--dump-gdextension-interface` / `--dump-gdextension-interface-json` produce the C header / JSON (`gdextension_interface.json`; every function carries a `since` version and is never changed incompatibly) (`gdextension_interface_json_file.rst`).
- Engine-side API changes keep old signatures through `ClassDB::bind_compatibility_method` in `*.compat.inc` files under `#ifndef DISABLE_DEPRECATED` (`engine_details/development/handling_compatibility_breakages.rst`). This is why extensions keep working across minor versions.

### Hot reload

- `reloadable = true` makes the editor reload the library when it is rebuilt, without restarting. Supported for godot-cpp since 4.2, "only works if you compile your extension in debug mode (default)" and is meant for development (`gdextension_cpp_example.rst`, `gdextension_file.rst`).
- `GDExtensionManager.reload_extension(path)` only works in the editor; in release builds it "always fails and returns LOAD_STATUS_FAILED" (`classes/class_gdextensionmanager.rst`).

### Documentation for extension classes

- `godot --doctool ../ --gdextension-docs` (from the project folder) writes XML stubs to `doc_classes/`; add `env.GodotCPPDocData("src/gen/doc_data.gen.cpp", source=Glob("doc_classes/*.xml"))` for `editor`/`template_debug` targets. Needs 4.3+ (`tutorials/scripting/cpp/gdextension_docs_system.rst`). XML format as in `engine_details/class_reference/index.rst`: no empty lines in descriptions (each line is a paragraph), BBCode-style links like `[method Class.name]`, `[member ...]`, `[constant ...]`.

## Compiling custom builds

Sources: `engine_details/development/compiling/introduction_to_the_buildsystem.rst`, `compiling_for_linuxbsd.rst`, `compiling_for_windows.rst`, `optimizing_for_size.rst`.

### Core options

- `platform=` (`p=`): `linuxbsd`, `windows`, `macos`, `web`, `android`, `ios`; `scons platform=list`. Output: `bin/godot.<platform>.<target>[.dev][.double].<arch>[.<extra_suffix>]`.
- `target=editor` (defines `TOOLS_ENABLED` and `DEBUG_ENABLED`), `target=template_debug` (`DEBUG_ENABLED`), `target=template_release`. Available command line flags differ by target (see the flags table below).
- `production=yes` = `use_static_cpp=yes debug_symbols=no lto=auto`. LTO is on for Linux, Web and Windows/MinGW, off for macOS, iOS and MSVC. Override any part: `production=yes debug_symbols=yes`.
- `lto=full` needs about 8 GB free RAM (12 to 16 GB installed) on Linux (the Linux page says "about 7 GB"); on Windows "up to 30 GB". Fallbacks: `lto=none`, `lto=thin` (LLVM only).
- `optimize=speed_trace` (default off-Web), `speed`, `size` (Web default), `size_extra` (4.5+), `debug`, `none`, `custom`.
- `debug_symbols=yes` (default no; official binaries have none), `separate_debug_symbols=yes` (MSVC always writes a `.pdb`).
- `dev_build=yes`: `DEV_ENABLED`, `-O0`, symbols, no `NDEBUG`, `.dev` suffix. Not the same as `dev_mode=yes` (= `verbose=yes warnings=extra werror=yes tests=yes`).
- `precision=double`: `.double` suffix; see Precision below.
- `arch=auto|x86_64|arm64|...`; `-j<n>` threads (default all but one); `scu_build=yes` for faster dev builds (do a normal build before a PR); `custom_modules=<dirs>`; `profile=path/to/custom.py` or a `custom.py` at the source root to hold options; `SCONSFLAGS` env var.
- Linux speed-ups: `use_llvm=yes linker=lld`, or `linker=mold`; system libraries with `builtin_<lib>=no` (not portable). Windows: `use_mingw=yes` (plus `use_llvm=yes` for MinGW-LLVM), `vsproj=yes`, `d3d12=no` to skip the D3D12 SDK. Requirements: Python 3.9+, SCons 4.4+ (Windows page).

### A dedicated server binary

- Godot 4 has no special server binary: any binary with `--headless` (= `--display-driver headless --audio-driver Dummy`) runs without GPU or window (`tutorials/export/exporting_for_dedicated_servers.rst`).
- Recommended: an export template, not the editor ("larger and less optimized"). Optimized server: `scons platform=linuxbsd target=template_release production=yes`; debuggable server: `target=template_debug` (`compiling_for_linuxbsd.rst`).
- Export preset "Export as dedicated server" strips textures/materials to placeholders (**Strip Visuals**), can **Remove** client-only files, and adds the `dedicated_server` feature tag, which also forces `--headless`. Detect with `OS.has_feature("dedicated_server")`, `DisplayServer.get_name() == "headless"`, or a user arg (`"--server" in OS.get_cmdline_user_args()`). For systemd, turn on `application/run/flush_stdout_on_print`.
- Linux binaries do not run on distributions older than the one they were built on; build on an old base (the page suggests Ubuntu 20.04) for portable servers.
- Custom templates: point the export preset's custom template at `bin/` (Advanced Options), or install to `~/.local/share/godot/export_templates/<version>/` named `linux_release.x86_64` etc. with `version.txt` holding e.g. `4.7.2.stable`.

### Stripping the engine

- Build profile: **Project > Tools > Engine Compilation Configuration Editor > Detect from Project**, save a `.gdbuild` JSON (`disabled_build_options`, `disabled_classes`), then `scons target=template_release build_profile=/path/profile.gdbuild` (`tutorials/editor/using_engine_compilation_configuration_editor.rst`). Detection misses classes used only from runtime-created GDScript, `Expression`s, GDExtensions (unless the binding declares used classes) and PCKs loaded at run time. `ClassDB.is_class_enabled(class)` reports whether a class survived.
- Options relevant here (`optimizing_for_size.rst`): `module_godot_physics_3d_enabled=no` (we use Jolt; the inverse is `module_jolt_enabled=no`), `disable_physics_2d=yes`, `disable_advanced_gui=yes` (removes RichTextLabel, Tree, OptionButton, PopupMenu and others; check the HUD and buy menu first), `module_text_server_adv_enabled=no module_text_server_fb_enabled=yes` (always pass both or no text renders), `disable_navigation_2d`-style module switches (`module_navigation_2d_enabled=no`; keep `navigation_3d`, the bots use it). `disable_3d=yes` is 2D-only and needs `target` without tools: not for us.
- Do not strip `module_gltf_enabled` from the editor build; the asset pipeline imports glTF (inferred; export templates do not import).
- Sanitizers: `use_asan=yes` (~2x slower), `use_lsan=yes` (leaks, checked at exit; long-running dedicated servers are the stated reason), `use_msan=yes` (Clang, Linux), `use_tsan=yes` (~10x slower, ~8x memory), `use_ubsan=yes`. ASAN, MSAN and TSAN are mutually exclusive. The binary gets a `.san` suffix (`engine_details/development/debugging/using_sanitizers.rst`).
- Engine C++ unit tests: `scons tests=yes` then `./bin/<godot> --test` (doctest filters `-ts`, `-tc`, `-sf`, `--test-case-exclude="*[Stress]*"`). Editor builds only; export templates cannot be tested (`engine_details/architecture/unit_testing.rst`).

### Precision (`tutorials/physics/large_world_coordinates.rst`)

- GDScript `float` is already 64-bit; `Vector2/3/4` (and the physics and rendering state) are 32-bit unless `precision=double`.
- Single-precision step by magnitude: [2048, 4096) about 0.0002; [4096, 8192) about 0.0005; all integers exact to 16,777,216. The docs' "maximum recommended single-precision range for a first-person 3D game" is [2048; 4096], written with meters in mind.
- Dust2 at 1 unit = 1 inch spans roughly 4000 units, so positions stay within about +-4096 of the origin if the map is centred (inferred; check the map's bounds). A 0.0002-unit step is about 0.005 mm, far below the 0.03125-unit resolution Source itself snaps positions to (Source detail from memory, not these docs). Single precision is fine; the doc's thresholds would bite only past about 32768 units ("Maximum recommended single-precision range for any 3D game" is [32768; 65536]).
- What double would cost: rebuilding editor and every template with `precision=double`, rebuilding every GDExtension (community ones too, such as the godot-steam-audio option in `reference/research/audio-engine.md`), "a performance and memory usage penalty", binary resources re-saved with a double flag, and the recommendation that server and clients use the same build type.

## Profiling and debugging

Sources: `tutorials/scripting/debug/the_profiler.rst`, `custom_performance_monitors.rst`, `overview_of_debugging_tools.rst`, `engine_details/development/profiling/*.rst`, `tutorials/editor/command_line_tutorial.rst`.

### In-engine tools

- Editor **Debugger > Profiler**: off by default ("performance-intensive"); press Start after running, or Autostart (not remembered across sessions). Measures frame time, physics frame, idle time, physics time, then per-function script time; **Inclusive** vs **Self** scope. Does not profile C#. `debug/settings/profiler/max_functions = 16384` per frame.
- **Debugger > Monitors** reads `Performance`; custom monitors via `Performance.add_custom_monitor("category/name", callable)`. Monitors refresh about once a second in the editor.
- Manual timing: `Time.get_ticks_usec()` around a block (what `scripts/profile_dust2.gd` does). The C++ equivalent is `Time::get_singleton()->get_ticks_usec()` with `#include "core/os/time.h"`.
- Debug menu toggles in the editor: Visible Collision Shapes, Visible Paths, Visible Navigation, Visible Avoidance, Synchronize Scene/Script Changes, Keep Debug Server Open, and **Customize Run Instances** (several instances with their own args and feature tags; the doc names it for "building and debugging multiplayer games").
- `print_verbose()` prints only with `--verbose` (`OS.is_stdout_verbose()`).
- `breakpoint` keyword in GDScript is a breakpoint stored in the file.

### C++ profilers (need a self-built binary)

- Sampling: Hotspot (Linux), VerySleepy (Windows), Instruments (Apple). Build with `production=yes debug_symbols=yes`; profiling an unstripped `template_debug` without LTO works but is "less representative". Use `--quit` to benchmark startup only; attach to a running process to skip startup.
- Tracing (engine already instrumented): **Tracy**: build with `profiler=tracy profiler_path=path/to/tracy debug_symbols=yes` (Tracy 0.13.0 when the page was written), run the Tracy server of the same version and press Connect before launching, or events pile up in RAM. **Perfetto**: `profiler=perfetto` after `python misc/scripts/install_perfetto.py`; the page covers Android only (official Perfetto Android templates ship with every stable release since 4.7). Categories `godot` (cheap) and `godot_scripting` (slow, every script call). Instruments also traces on Apple.
- The built-in GDScript profiler still works on stripped binaries; C++ profilers need symbols.
- GPU: `--gpu-validation` (Vulkan validation layers; install the Vulkan SDK on Windows), `--gpu-abort`, `--generate-spirv-debug-info` (RenderDoc source-level), `--extra-gpu-memory-tracking`, `--accurate-breadcrumbs` (GPU resets, Vulkan only). `debug/settings/stdout/print_gpu_profile` prints per-pass GPU time every second.

### Command-line flags for headless testing and profiling

Legend (from the tutorial): R = editor, debug and release templates; D = editor and debug templates only; E = editor only; X = editor, and templates built with `disable_path_overrides=false`. CI and cloud threads run the official **editor** binary, so every flag below is available there.

| Flag | Avail. | What it does | Headless? |
|---|---|---|---|
| `--headless` | R | `--display-driver headless --audio-driver Dummy` | yes |
| `--path <dir>`, `--scene <path or uid>`, `-s/--script <script>` | X | pick project, scene, or a MainLoop/SceneTree script | yes |
| `--check-only` | X | parse the `--script` for errors and quit | yes |
| `--import` | E | import resources then quit; implies `--editor --quit` | yes |
| `--quit`, `--quit-after <n>` | R | quit after the first / n-th iteration | yes |
| `-v/--verbose`, `-q/--quiet`, `--no-header` | R | stdout verbosity | yes |
| `--log-file <file>` | R | write the log to a path | yes |
| `--print-fps` | R | print frames per second to stdout | yes (inferred: counts main-loop iterations; `Engine.get_frames_drawn()` is 0 headless, use `get_process_frames()`) |
| `--fixed-fps <fps>` | R | fixed frame rate, "disables real-time synchronization" | yes; useful to make a headless run advance by exact steps (inferred) |
| `--time-scale <s>` | R | force `Engine.time_scale` | yes |
| `--frame-delay <ms>` | R | add CPU load per frame (simulate a slow machine) | yes |
| `--max-fps <fps>`, `--disable-vsync`, `--delta-smoothing enable/disable` | R | frame pacing | partly (vsync is irrelevant headless) |
| `--benchmark`, `--benchmark-file <abs path>` | E | time the run (JSON with the file form) | yes, editor binary only |
| `--profiling` | R | enable profiling in the script debugger | only with a debugger attached (`-d` or `--remote-debug`) (inferred) |
| `-d/--debug` | R | local stdout debugger | yes, but a break waits on stdin (inferred: avoid in CI) |
| `--remote-debug tcp://host:port` | R | connect to an editor debugger | yes (the Linux page says a `template_debug` server can use it) |
| `-b/--breakpoints file::line,...`, `--ignore-error-breaks` | R | breakpoints from the command line | with a debugger |
| `--gpu-profile` | R | GPU profile of the costliest render tasks | no (needs rendering) |
| `--gpu-validation`, `--gpu-abort` | R / D | validation layers | no |
| `--debug-collisions`, `--debug-paths`, `--debug-navigation`, `--debug-avoidance` | D | draw shapes/paths/navmesh | no (visual only) |
| `--debug-stringnames` | D | print all StringName allocations at exit | yes |
| `--disable-render-loop` | R | render only when called from script | n/a headless |
| `--render-thread unsafe/safe/separate` | R | override the thread model | no |
| `--single-threaded-scene` | R | disable scene sub-thread groups | yes |
| `--write-movie <file>` | R | Movie Maker; forces `--fixed-fps` | no |
| `--test [--help]` | E | engine C++ unit tests (`tests=yes` build) | yes |
| `--doctool`, `--gdextension-docs`, `--gdscript-docs <path>` | E | dump API reference XML | yes |
| `--dump-extension-api`, `--dump-extension-api-with-docs`, `--validate-extension-api <path>`, `--dump-gdextension-interface(-json)` | E | GDExtension API files | yes |
| `-- args` or `++ args` | R | user args, read with `OS.get_cmdline_user_args()` | yes |

## Coding conventions for engine or godot-cpp C++

Sources: `engine_details/architecture/core_types.rst`, `common_engine_methods_and_macros.rst`, `object_class.rst`.

- Allocate with `memnew(T)` / `memdelete(p)` (and `memnew_arr`, `memalloc`), not `new`/`malloc`; they run Object post-init and pre-release hooks. Never `memdelete` a RefCounted; hold it in `Ref<T>`, never a raw pointer.
- Containers: default to `LocalVector` in hot code (no copy-on-write, faster than `Vector`), `AHashMap` (fast, not order-preserving, pointers/iterators unstable), `HashMap` only when stable pointers or insertion order are needed, `HashSet`, `FixedVector` (no heap), `Span` (unchecked view). `Vector` is COW. `List`, `RBMap`, `VSet` are discouraged. STL is usable in godot-cpp but does not interoperate with Godot APIs.
- Containers assume trivially relocatable elements (moved with `memcpy`/`realloc`); do not store self-referencing types in them.
- No container is thread-safe. Locks: `Mutex` (recursive) / `BinaryMutex` with `MutexLock lock(m)`, `RWLock` with `RWLockRead`/`RWLockWrite`, `SafeBinaryMutex` + `ConditionVariable`, `Semaphore`, atomics `SafeNumeric<T>`, `SafeFlag`, `SafeRefCount`. The script-exposed wrappers are RefCounted and slower.
- `String` is UTF-32; use `StringName` for interned identifiers (method and signal names). `D_METHOD` argument names are dropped in release builds.
- Casting: `Object::cast_to<T>(obj)` returns `nullptr` on failure, no RTTI.
- Printing: `print_line`, `print_verbose`, `ERR_PRINT`, `WARN_PRINT`, `*_ONCE` variants; format with `vformat("%d", n)`; `itos`/`rtos`.
- Errors: `ERR_FAIL_COND_MSG(cond, msg)`, `ERR_FAIL_COND_V_MSG(cond, ret, msg)`, `ERR_FAIL_INDEX_MSG`, `ERR_FAIL_INDEX_V_MSG`, `ERR_FAIL_NULL(ptr)`, `ERR_FAIL_MSG`, `ERR_FAIL_V_MSG`; `CRASH_NOW_MSG` only for testing crash handling.
- Settings: `GLOBAL_DEF("a/b/c", default)` once, `GLOBAL_GET` elsewhere.
- `_get`/`_set`/`_get_property_list` in C++ are not virtual and are called at every class level; slower than bound properties (serial name comparison).
- An enum used in a bound signature needs `VARIANT_ENUM_CAST`.

## Class notes

**Object** (`classes/class_object.rst`)
- `free()` deletes now (= `memdelete` in C++); references become invalid, not null. `is_queued_for_deletion()` is not true for children of a `queue_free()`d node.
- `call(method, ...)`, `callv(method, args)`, `get(property)` (returns `null` if missing), `set(property, value)` (silently does nothing if missing or wrong type): all "much slower than direct references".
- `call_deferred(method, ...)` returns `null`; runs at idle time. `set_deferred(property, value)`.
- `get_instance_id() -> int`: session-only; `instance_from_id()` resolves it.
- `set_meta(name, value)` / `get_meta(name, default = null)`: names must be valid identifiers; names starting `_` are editor-only. `set_meta(name, null)` removes.
- `connect(signal, callable, flags = 0) -> Error`.

**ClassDB** (`classes/class_classdb.rst`)
- Holds engine and GDExtension classes, not script `class_name` classes.
- `class_exists(class)`, `can_instantiate(class)`, `instantiate(class) -> Variant`, `get_parent_class(class)`, `is_parent_class(class, inherits)`, `class_has_method(class, method, no_inheritance = false)`, `class_get_method_list(class, no_inheritance = false)`, `class_get_property_list(...)`, `class_call_static(class, method, ...)`, `is_class_enabled(class)` (false for classes a build profile removed).

**Engine** (`classes/class_engine.rst`)
- Properties: `physics_ticks_per_second` (default 60; project 64), `max_physics_steps_per_frame` (8; project 16), `physics_jitter_fix` (0.5), `time_scale` (1.0; does not change tick rate or audio speed), `max_fps` (0 = uncapped), `print_error_messages`, `print_to_stdout`.
- `physics_jitter_fix`: "When using a custom physics interpolation solution, or within a network game, it's recommended to disable the physics jitter fix by setting this property to `0`." The project setting `physics/common/physics_jitter_fix` is read only at start; set `Engine.physics_jitter_fix` at run time.
- `get_physics_frames()` (increments every physics frame), `get_process_frames()` (every process frame, even with the render loop off), `get_frames_drawn()` (0 headless), `get_frames_per_second()`, `get_physics_interpolation_fraction()` (fraction through the current tick at render time), `is_in_physics_frame()`.
- `is_editor_hint()` (running inside the editor) vs `OS.has_feature("editor")` (an editor build, including running the game from it).
- `get_version_info() -> Dictionary` (`major`, `minor`, `patch`, `hex` e.g. `0x040702`, `status`, `build`, `hash`, `timestamp`, `string`).
- `get_singleton(name)`, `has_singleton(name)`, `register_singleton(name, instance)`: global singletons, not autoloads.
- `capture_script_backtraces(include_variables = false) -> Array[ScriptBacktrace]`: frames only in editor/debug unless `debug/settings/gdscript/always_track_call_stacks`.
- `get_architecture_name()`: the binary's arch, not the CPU's.

**OS** (`classes/class_os.rst`)
- `get_cmdline_args()` (engine args removed), `get_cmdline_user_args()` (after `--` / `++`).
- `has_feature(tag)` (case-sensitive; `"dedicated_server"`, `"template"`, `"editor"`, `"double"`), `is_debug_build()` (true in editor and debug templates).
- `get_processor_count()` (logical cores), `get_main_thread_id()`, `get_thread_caller_id()`, `set_thread_name(name)`.
- `get_static_memory_usage()`, `get_static_memory_peak_usage()`: debug builds only. `get_memory_info() -> Dictionary` (`physical`, `free`, `available`, `stack`).
- `delay_usec(usec)` blocks the calling thread; on the main thread it freezes the game.
- `is_stdout_verbose()`.

**Performance** (`classes/class_performance.rst`)
- `get_monitor(monitor) -> float`. Useful: `TIME_FPS` (0, updated once a second), `TIME_PROCESS` (1, seconds), `TIME_PHYSICS_PROCESS` (2, seconds), `TIME_NAVIGATION_PROCESS` (3), `MEMORY_STATIC` (4, not in release), `OBJECT_COUNT` (7), `OBJECT_RESOURCE_COUNT` (8), `OBJECT_NODE_COUNT` (9), `OBJECT_ORPHAN_NODE_COUNT` (10, debug only), `RENDER_TOTAL_OBJECTS_IN_FRAME` (11), `RENDER_TOTAL_PRIMITIVES_IN_FRAME` (12), `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` (13), `RENDER_VIDEO_MEM_USED` (14), `PHYSICS_3D_ACTIVE_OBJECTS` (20), `PHYSICS_3D_COLLISION_PAIRS` (21), `PIPELINE_COMPILATIONS_DRAW` (37, stutters during play), `NAVIGATION_3D_*` (49 to 58).
- Some monitors are debug-only and return 0 in release; some update with up to 1 s delay.
- `add_custom_monitor(id: StringName, callable: Callable, arguments: Array = [], type: MonitorType = 0)`; `MONITOR_TYPE_TIME` expects **seconds**, `MONITOR_TYPE_PERCENTAGE` a fraction. Values below 0 clamp to 0. `get_custom_monitor(id)`, `has_custom_monitor(id)`, `remove_custom_monitor(id)`. Works in exported debug and release builds.

**EngineDebugger** (`classes/class_enginedebugger.rst`)
- Active in the running game; talks to the editor. `is_active()`, `send_message(message, data: Array)`, `register_message_capture(name, callable)` (receives `name:`-prefixed messages with the prefix stripped; return `true` if handled), `register_profiler(name, profiler: EngineProfiler)`, `profiler_add_frame_data(name, data)`, `profiler_enable(name, enable, arguments = [])`, `is_profiling(name)`, `line_poll()`. A route for custom per-tick timings into an editor plugin (inferred).

**GDExtension** (`classes/class_gdextension.rst`)
- Resource for a loaded library. `get_minimum_library_initialization_level()`, `is_library_open()`. Enum `InitializationLevel`: `CORE` 0, `SERVERS` 1, `SCENE` 2, `EDITOR` 3.

**GDExtensionManager** (`classes/class_gdextensionmanager.rst`)
- `load_extension(path) -> LoadStatus` (absolute path to a valid GDExtension), `reload_extension(path)` (editor only; release returns `LOAD_STATUS_FAILED`), `unload_extension(path)`, `is_extension_loaded(path)`, `get_loaded_extensions()`, `get_extension(path)`, `load_extension_from_function(path, init_func)` (path must start `libgodot://`). `LoadStatus`: `OK` 0, `FAILED` 1, `ALREADY_LOADED` 2, `NOT_LOADED` 3, `NEEDS_RESTART` 4. Signals `extension_loaded`, `extension_unloading` (editor builds only), `extensions_reloaded`.

**ResourceUID** (`classes/class_resourceuid.rst`)
- Keeps `uid://` references valid across renames. Static: `ensure_path(path_or_uid)`, `path_to_uid(path)` (unchanged path if none), `uid_to_path(uid)`. Instance: `text_to_id(text)`, `id_to_text(id)`, `has_id(id)`, `get_id_path(id)` (errors if missing), `create_id()` then `add_id`/`set_id` to register, `create_id_for_path(path)` (deterministic per project). The project commits `*.gd.uid` files beside each script; `--scene` accepts a UID.

## Where the code already does this

- `src/sim/game_world.gd:69`: `process_physics_priority = -1000` so the world's `_physics_process` (`:106`) runs the tick first, before the physics server step.
- `src/sim/sim_clock.gd`: simulation time from `Engine.physics_ticks_per_second`, `Engine.get_physics_frames()` (fallback), and `Engine.get_physics_interpolation_fraction()` for draw time. The same fraction is read in `src/player/player_view.gd:241,425,508`, `src/bots/bot.gd:225`, `src/combat/ragdoll.gd:228`, `src/game/dropped_item_view.gd:77`, `src/grenades/grenade_view.gd:115`.
- `src/movement/player_body.gd:592-594`: every hull trace goes through `move_and_collide()` and is counted in `traces`; `:605-623` quadrant rays with `PhysicsRayQueryParameters3D.create` per ray.
- `src/combat/hitscan.gd:85-224`: hitscan and penetration with `intersect_ray` and a fresh query object per ray.
- `scripts/profile_dust2.gd`: an `extends SceneTree` script run with `--headless --script ... -- <team size> <windows>`, timing with `Time.get_ticks_usec()`, `Engine.get_process_frames()`, and `Performance.get_monitor(MEMORY_STATIC / OBJECT_COUNT / OBJECT_NODE_COUNT / OBJECT_RESOURCE_COUNT / OBJECT_ORPHAN_NODE_COUNT)`; it builds a marker node from `GDScript.new()` source to time the physics server step.
- `scripts/run_tests.sh`, `scripts/common.sh:54,59`: `--headless --path ... --import`, then `--headless --path ... --script tests/run_*.gd`; `.github/workflows/tests.yml` uses the official 4.7.2 Linux editor binary.
- `maps/play/play.gd`: map name from `OS.get_cmdline_user_args()` then `OS.get_cmdline_args()`.
- `src/ui/movement_hud.gd`: `Engine.get_frames_per_second()`.
- `src/map/far_materials.gd`: `RenderingServer.get_current_rendering_method()`.
- `project.godot [physics]`: `common/physics_ticks_per_second=64`, `common/max_physics_steps_per_frame=16`, `3d/physics_engine="Jolt Physics"`; nothing sets `3d/run_on_separate_thread` or the render thread model, so both stay on the main thread.
- No `.gdextension` file, godot-cpp checkout, SConstruct, custom build or build profile exists in the repo.

Looks at odds with the docs (not verified):
- `project.godot:188-200` does not set `physics/common/physics_jitter_fix`, so it is 0.5. The project draws between ticks with its own interpolation (`SimClock.draw_usec()`, `src/sim/sim_clock.gd:66-68`) and is heading for networked play; `classes/class_engine.rst` and `class_projectsettings.rst` recommend `0` for both cases. Worth a measured check of whether ticks drift from real time with the default (a Local check, since the effect is in frame pacing).
- `tests/run_model_checks.gd` times out on `Time.get_ticks_usec()` (wall clock) while waiting for tick-driven events; fine for a harness, but under `--fixed-fps` or a slow CI runner the wall-clock bounds and the tick count diverge (inferred).

## Not covered here

- `.tscn`/`.tres` text format: `engine_details/file_formats/tscn.rst` (another page). The 4.7 docs have no GDScript grammar page under `engine_details/file_formats/`; the only file there is `tscn.rst`. GDScript syntax is in `tutorials/scripting/gdscript/gdscript_basics.rst`.
- The full command line reference (window, export and editor flags): `tutorials/editor/command_line_tutorial.rst`.
- Renderer internals (Forward+ clustering, shadows, TAA, SDFGI, LOD selection, core shaders): `engine_details/architecture/internal_rendering_architecture.rst`; the project's decisions are in `reference/rendering.md` and `reference/performance.md`.
- Threads in GDScript (`Thread`, `Mutex`, `Semaphore`, `WorkerThreadPool` usage): `tutorials/performance/using_multiple_threads.rst`.
- Writing a GDExtension in plain C without godot-cpp: `engine_details/engine_api/gdextension/gdextension_c_example.rst`; the JSON interface schema: `gdextension_interface_json_file.rst`.
- Custom modules in full, custom resource loaders, custom AudioStreams, binding external libraries, platform ports: `engine_details/engine_api/`.
- IDE setup for engine/godot-cpp work: `engine_details/development/configuring_an_ide/`.
- Compiling for macOS, Web, Android, iOS; script encryption keys; .NET builds: `engine_details/development/compiling/`.
- macOS engine debugging, Vulkan validation details per platform: `engine_details/development/debugging/`.
- Editor icon creation and editor C++ development: `engine_details/editor/`.
- Class reference XML authoring in full (all BBCode tags): `engine_details/class_reference/index.rst`; reading the API pages: `tutorials/scripting/how_to_read_the_godot_api.rst`.
- Jolt-specific settings and differences: `tutorials/physics/using_jolt_physics.rst` and the physics page.
- ObjectDB profiler and debugger panel details: `tutorials/scripting/debug/objectdb_profiler.rst`, `debugger_panel.rst`.
