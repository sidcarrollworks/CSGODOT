# Godot 4.7: main loop, nodes, files and headless runs

Source: godot-docs branch 4.7 @9adca4c (2026-09-21). Read when: adding a system to the tick, ordering physics callbacks, freeing or reparenting nodes, pausing, loading resources or data files, reading or writing files, using threads, writing a test or a headless script, or reading timings and monitors.

Companion pages: `gdscript.md` (language, containers, numbers), `physics.md`, `engine.md`. The project's own pages `reference/performance.md` and `reference/rendering.md` hold its decisions; this page does not repeat them.

## Rules for this project

- Run game logic only from `GameWorld.step()` (`src/sim/game_world.gd`). The engine calls every node's `_physics_process` once per physics tick, ordered by `process_physics_priority` (lower first) then tree order, so a system's own `_physics_process` runs in an order decided by where it sits in the tree, not by the game.
- Order physics callbacks with `process_physics_priority`, never with tree position. Its setter is `set_physics_process_priority()`, not `set_process_physics_priority()`; the property name and accessor name differ.
- Keep time with `SimClock`, not the `delta` argument. `_physics_process`'s `delta` is `Engine.time_scale / physics_ticks_per_second`, so `--time-scale` or `Engine.time_scale` changes it; and when the frame rate drops below `physics_ticks_per_second / max_physics_steps_per_frame` the game runs slower than real time (steps are dropped, not caught up).
- Take real time from `Time.get_ticks_usec()` (or `get_ticks_msec()`), only for input stamps and profiling. `OS` has no `get_ticks_usec` in 4.x; that was Godot 3.
- Keep `physics/common/physics_jitter_fix` at `0`, as `project.godot` sets it. The docs recommend 0 "when using a custom physics interpolation solution, or within a network game"; this project is both, and `DrawClock` needs the ticks kept to the clock.
- Never read the disk inside a tick. `load()` on an uncached path, `FileAccess` and `DirAccess` all block the calling thread. Load and parse at startup or scene load; a cache hands out copies (`gdscript.md`).
- Write only to `user://`. `res://` is read-only in an exported game; `user://` is always writable.
- Read `.tres`/`.tscn`/imported assets with `load()`/`ResourceLoader`, never with `FileAccess`: exports convert text resources to binary and do not ship imported source files. Plain data files (`.csv`, `.md`, `.json`, `.vmdl`) read with `FileAccess` ship only if the export preset's non-resource include filter lists them.
- Test existence of a resource with `ResourceLoader.exists()`, not `FileAccess.file_exists()`; the latter does not see imported resources in an export.
- In a `--script` file, `return` right after `quit()`. `quit()` only ends the loop "at the end of the current iteration", so code after it still runs.
- Always print the `TESTS <name> ...` line before `quit()` in a test. Script errors do not change Godot's exit code (inferred from the docs saying nothing about it and from `scripts/run_tests.sh` relying on the TESTS line), so a missing line is the only sign of a crash.
- Run `godot --headless --path . --import` once before any `--script` run on a fresh checkout: `class_name` globals come from the import/scan step.
- Do not touch the scene tree from a thread. Build a subtree off-tree and add it with `add_child.call_deferred(node)`. Physics queries from another thread are not safe unless `physics/3d/run_on_separate_thread` is on.
- Wait for every `WorkerThreadPool` task and `wait_to_finish()` every `Thread`; the docs require it.
- Keep audio and visual delays on `SceneTreeTimer`s or per-frame code; never on the simulation's side. A `create_timer` fires on real (scaled) process time, not on ticks.

## One frame, in order

Docs: `tutorials/scripting/idle_and_physics_processing.rst`, `classes/class_node.rst`, `classes/class_scenetree.rst`, `classes/class_engine.rst`, `classes/class_mainloop.rst`.

- Each iteration of the main loop runs 0..`max_physics_steps_per_frame` physics steps, then one process (idle) step, then draws (not in headless).
- One physics step, as the docs describe it:
  1. `SceneTree.physics_frame` is emitted, "immediately before `_physics_process` is called on every node".
  2. `_physics_process(delta)` is called on every node that has it enabled. The order is `process_physics_priority` ascending, then tree order (pre-order, parent before children) within one priority.
  3. The physics server steps (inferred from the docs saying `_physics_process` is "called before every physics step").
  4. Deferred calls are flushed, then nodes queued with `queue_free` are deleted.
- One process step: `SceneTree.process_frame` is emitted, then `_process(delta)` runs (ordered by `process_priority`), then `SceneTreeTimer`s are updated "after all nodes", then deferred calls and deletions are flushed.
- `_process` runs "after physics ticks have been processed", so a frame's `_process` sees the result of every tick in that frame.
- `_process`'s `delta` is capped at `time_scale * max_physics_steps_per_frame / physics_ticks_per_second`. With this project's 16 steps at 64 Hz, that is 0.25 s. `--fixed-fps <n>` makes it constant and turns off real-time sync.
- `await get_tree().physics_frame` resumes before that tick's `_physics_process` calls, so after one await `GameWorld.step()` has not run yet for that tick. Await two to see one tick's result (inferred; the tests often await twice).
- `Engine.get_physics_frames()` counts physics steps since start; `get_process_frames()` counts process steps; `get_frames_drawn()` stays 0 in headless. `SceneTree.get_frame()` also counts physics steps.
- `Engine.is_in_physics_frame()` is true inside physics processing, including `_physics_process` and physics callbacks.
- `Node.get_physics_process_delta_time()` grows when the frame rate is below `ticks / max_steps`. For a true duration use `Time.get_ticks_usec()`.

## Physics tick settings and interpolation

Docs: `classes/class_engine.rst`, `classes/class_projectsettings.rst` (`physics/common/*`), `tutorials/physics/interpolation/*`, `classes/class_node.rst` (`physics_interpolation_mode`).

- `physics/common/physics_ticks_per_second` defaults to 60 (project: 64). `physics/common/max_physics_steps_per_frame` defaults to 8 (project: 16). These project settings are read only at startup; at run time change `Engine.physics_ticks_per_second` / `Engine.max_physics_steps_per_frame`.
- `Engine.physics_jitter_fix` (project setting `physics/common/physics_jitter_fix`) defaults to 0.5. It nudges the tick timing to match the monitor refresh. The docs say to set it to 0 for a custom interpolation or a network game, and it is disabled automatically when `physics/common/physics_interpolation` is on.
- `Engine.get_physics_interpolation_fraction()` returns how far the current frame is between the last two physics ticks (0..1). It is only meaningful in `_process`. It is taken at the start of a frame, before the frame's ticks run, so a frame that runs a tick is drawn later than it says; the project's views read `DrawClock.fraction()` instead, which takes it from the wall clock when the frame is drawn.
- Built-in physics interpolation (`physics/common/physics_interpolation`, default false; `SceneTree.physics_interpolation` at run time) moves only the visual transforms of 3D nodes between ticks. `Node.physics_interpolation_mode` is `PHYSICS_INTERPOLATION_MODE_INHERIT` (0), `_ON` (1) or `_OFF` (2); the root is ON, so everything inherits ON once the setting is on. It has no effect while the setting is off.
- After teleporting a node that is interpolated, call `reset_physics_interpolation()` after moving it, not before. That sends `NOTIFICATION_RESET_PHYSICS_INTERPOLATION` (2001) down the branch.
- The project does not use built-in interpolation; each view does its own. Switching would be a project-wide decision (link `reference/rendering.md`).

## Node lifecycle

Docs: `tutorials/scripting/scene_tree.rst`, `tutorials/best_practices/godot_notifications.rst`, `classes/class_node.rst`, `classes/class_object.rst`.

- `_init()`: when the object is created (`new()` or scene instantiation), before it has a parent. Exported properties from a scene are set after `_init`. A `_init` with required arguments breaks instantiation from a scene or `duplicate()` (see `gdscript.md`).
- `NOTIFICATION_PARENTED` (18) / `NOTIFICATION_UNPARENTED` (19): parent set or cleared, even off-tree.
- `NOTIFICATION_SCENE_INSTANTIATED` (20): on the root of a scene just instantiated from a PackedScene.
- `_enter_tree()`: parent first, then children. `NOTIFICATION_POST_ENTER_TREE` (27) follows, before `_ready`.
- `_ready()`: children first, then parent, so a parent's `_ready` can use ready children. Called only once per node; after `remove_child` and re-adding it is not called again unless `request_ready()` was called.
- `_exit_tree()`: children first, then parent. `NOTIFICATION_EXIT_TREE` is sent in reverse order.
- `NOTIFICATION_PREDELETE` (1): the object is about to be freed; sent in reverse order.
- `_process`, `_physics_process`, `_input`, `_unhandled_input` are enabled automatically before `_ready` if the script overrides them. `set_physics_process(false)` turns one off; the callback runs only while the node is inside the tree.
- `NOTIFICATION_PHYSICS_PROCESS` (16) and `NOTIFICATION_PROCESS` (17) are the notification forms of the two callbacks.
- Set a node's properties before `add_child` where possible (`tutorials/best_practices/logic_preferences.rst`): setters that react to the tree then run once, and `_ready` sees final values.
- Every node in the tree costs per-frame propagation even when idle. Removing a branch from the tree is cheaper than hiding or disabling it (`tutorials/performance/cpu_optimization.rst`).

## Adding, moving and freeing nodes

Docs: `classes/class_node.rst`, `classes/class_object.rst`, `tutorials/scripting/nodes_and_scene_instances.rst`.

- `add_child(node, force_readable_name := false, internal := 0)` fails with an error if `node` already has a parent. `force_readable_name = true` is very slow; keep it false in anything run often.
- `remove_child(node)` detaches but does not free. The node becomes an orphan; free it or keep a reference, or it leaks.
- `reparent(new_parent, keep_global_transform := true)` moves a node in one call.
- `replace_by(node, keep_groups := false)` swaps a node in place and does not delete the old one.
- `duplicate(flags := 15)` copies signals, groups, scripts and uses instantiation (flags 1|2|4|8). `DUPLICATE_INTERNAL_STATE` (16) also copies non-exported script variables; it is not in the default.
- `queue_free()` deletes "at the end of the current frame after all other deferred calls". Safe to call more than once. `is_queued_for_deletion()` is true only on the node that was queued, not on its children.
- `free()` deletes at once; anything still holding the node then holds a freed object. Use `is_instance_valid()` before touching a node that may have been freed.
- `Node.print_orphan_nodes()` and `Node.get_orphan_node_ids()` work only in debug builds. `Performance.OBJECT_ORPHAN_NODE_COUNT` likewise.

## Deferred calls

Docs: `classes/class_object.rst` (`call_deferred`, `set_deferred`), `classes/class_callable.rst` (`call_deferred`).

- `call_deferred(method, ...)` and `Callable.call_deferred(...)` run "at idle time", mainly at the end of the process and of the physics frame, and the queue is drained until empty. Calls deferred from one thread run in the order they were made.
- A method that defers a call to itself every time loops forever within one flush (the docs warn of infinite recursion), since the queue is drained until empty.
- `set_deferred(property, value)` is the property form.
- A deferred call made during a tick runs after that tick's `_physics_process` calls, not on the next tick (inferred from "end of the physics frame"). Game state changed that way is changed outside `GameWorld.step()`; avoid it in the simulation.
- `SceneTree.call_group(group, method, ...)` calls at once (not deferred); `call_group_flags` with `GROUP_CALL_DEFERRED` defers.
- The project uses no `call_deferred` today.

## Pause and process modes

Docs: `tutorials/scripting/pausing_games.rst`, `classes/class_node.rst` (`ProcessMode`), `classes/class_scenetree.rst` (`paused`).

- `Node.process_mode`: `PROCESS_MODE_INHERIT` (0, default), `PROCESS_MODE_PAUSABLE` (1, what the root uses), `PROCESS_MODE_WHEN_PAUSED` (2), `PROCESS_MODE_ALWAYS` (3), `PROCESS_MODE_DISABLED` (4).
- While `get_tree().paused` is true: `_process`, `_physics_process`, `_input` and `_input_event` are not called on pausable nodes; signals still fire; the 3D physics server stops (turn it back on with `PhysicsServer3D.set_active(true)` if needed).
- Pausing the tree stops `GameWorld`, so it stops the simulation. A server must not pause for one player's menu (inferred for multiplayer).
- `NOTIFICATION_PAUSED` (14) and `NOTIFICATION_UNPAUSED` (15) are sent to nodes whose processing state changes.

## Processing threads (thread groups)

Docs: `classes/class_node.rst` (`process_thread_group`, `process_thread_group_order`, `process_thread_messages`), `tutorials/performance/thread_safe_apis.rst`.

- `Node.process_thread_group`: `PROCESS_THREAD_GROUP_INHERIT` (default), `PROCESS_THREAD_GROUP_MAIN_THREAD`, `PROCESS_THREAD_GROUP_SUB_THREAD`. A sub-thread group runs its nodes' `_process`/`_physics_process` on a worker thread.
- Nodes in a sub-thread group must not touch nodes outside the group. Use `call_deferred_thread_group()` / `set_deferred_thread_group()` or `call_thread_safe()` / `set_thread_safe()` to cross.
- `process_thread_group_order` orders groups against each other.
- `--single-threaded-scene` on the command line turns sub-thread groups off (useful to rule them out when debugging).
- Not used by the project. The simulation must stay in one deterministic order, so any use belongs in presentation only (inferred).

## SceneTree and MainLoop

Docs: `classes/class_scenetree.rst`, `classes/class_mainloop.rst`, `tutorials/scripting/change_scenes_manually.rst`.

- Godot runs one `MainLoop`. It is a `SceneTree` unless `--script`/`-s` gives a script extending `MainLoop` or `SceneTree`, or `application/run/main_loop_type` names another.
- A `MainLoop` (or `SceneTree` subclass) overrides `_initialize()`, `_finalize()`, `_physics_process(delta) -> bool` and `_process(delta) -> bool`. Returning `true` from either of the last two ends the loop.
- `SceneTree.quit(exit_code := 0)` ends the program at the end of the current iteration, with that exit code. Use codes 0..125 for portability.
- `SceneTree.root` is the root `Window`; never free it.
- `change_scene_to_file(path)` / `change_scene_to_packed(scene)` / `change_scene_to_node(node)`: the current scene is removed at once, freed at the end of the frame, and the new one is added after. `current_scene` is null in between. Await `scene_changed` before using the new scene.
- `get_nodes_in_group(group)` returns nodes in tree order. `queue_delete(obj)` queues any Object for deletion at frame end.
- `create_timer(time_sec, process_always := true, process_in_physics := false, ignore_time_scale := false) -> SceneTreeTimer`. It fires even while paused unless `process_always` is false, and counts process time unless `process_in_physics` is true. It is a real-time timer, never a tick count.
- `auto_accept_quit` (default true) lets the window close button quit; `NOTIFICATION_WM_CLOSE_REQUEST` (1006) arrives first.

## Autoloads

Docs: `tutorials/scripting/singletons_autoload.rst`.

- An autoload is added under `root` before the main scene, in the order listed, so it is `root`'s first child(ren) and runs before the scene in each tree-order callback of equal priority.
- It is not a true singleton: the class can still be instantiated again. Never free an autoload at run time.
- The project has no autoloads. `GameWorld.current` (a `static var` set in `_enter_tree`) plays that role. `Engine.get_singleton()` returns engine singletons only, not autoloads.

## Resources and loading

Docs: `tutorials/scripting/resources.rst`, `tutorials/io/background_loading.rst`, `classes/class_resourceloader.rst`, `classes/class_resourcesaver.rst`, `classes/class_resource.rst`.

- Resources are cached by path: `load(path)` twice returns the same instance, so changing a loaded resource changes it for everyone who loaded it. `duplicate()` or `resource_local_to_scene` give per-user copies.
- `preload(path)` loads when the script is parsed and needs a constant path. `load(path)` loads when reached and blocks.
- `ResourceLoader.load(path, type_hint := "", cache_mode := CACHE_MODE_REUSE)`. `CacheMode`: `CACHE_MODE_IGNORE` 0, `CACHE_MODE_REUSE` 1, `CACHE_MODE_REPLACE` 2, `CACHE_MODE_IGNORE_DEEP` 3, `CACHE_MODE_REPLACE_DEEP` 4. A path without a scheme gets `res://`. Only imported files (or native resources) load.
- Threaded loading:
  - `ResourceLoader.load_threaded_request(path, type_hint := "", use_sub_threads := false, cache_mode := CACHE_MODE_REUSE) -> Error`.
  - `ResourceLoader.load_threaded_get_status(path, progress := []) -> ThreadLoadStatus`: `THREAD_LOAD_INVALID_RESOURCE` 0, `THREAD_LOAD_IN_PROGRESS` 1, `THREAD_LOAD_FAILED` 2, `THREAD_LOAD_LOADED` 3. Poll it once per frame, not in a tight loop.
  - `ResourceLoader.load_threaded_get(path)` returns the resource and blocks if it is not done yet.
- `ResourceLoader.exists(path, type_hint := "")`, `has_cached(path)`, `get_cached_ref(path)`, `get_dependencies(path)`, `list_directory(path)` (lists original, pre-import names, which also works in an export).
- `ResourceSaver.save(resource, path := "", flags := 0) -> Error`. Flags: `FLAG_RELATIVE_PATHS` 1, `FLAG_BUNDLE_RESOURCES` 2, `FLAG_CHANGE_PATH` 4, `FLAG_OMIT_EDITOR_PROPERTIES` 8, `FLAG_SAVE_BIG_ENDIAN` 16, `FLAG_COMPRESS` 32, `FLAG_REPLACE_SUBRESOURCE_PATHS` 64. UIDs are not written when saving at run time.
- `Resource.resource_local_to_scene` makes each scene instance get its own copy; `_setup_local_to_scene()` runs on each copy.
- 4.6/4.7 scene format: `.tscn` no longer writes `load_steps` and gains unique node IDs. Do not hand-write `load_steps` into new scenes.

## Files and paths

Docs: `tutorials/io/data_paths.rst`, `tutorials/io/saving_games.rst`, `tutorials/export/exporting_projects.rst`, `classes/class_fileaccess.rst`, `classes/class_diraccess.rst`, `classes/class_projectsettings.rst`.

- Paths: always `/`, even on Windows. Linux file systems are case-sensitive; a path that works on Windows with the wrong case fails on Linux and in CI.
- `res://` is the project folder; read-only in an export (packed into the PCK).
- `user://` is always writable. On Linux it is `~/.local/share/godot/app_userdata/<project name>`, or `~/.local/share/<name>` with `application/config/use_custom_user_dir`.
- `ProjectSettings.globalize_path("res://...")` gives the OS path (in an export, `res://` paths do not map to real files); `localize_path()` goes back.
- Logs: `user://logs/godot.log`, at most 5 files kept by default.
- What an export contains:
  - Imported sources (`.png`, `.gltf`, `.wav`...) are not shipped; only their imported forms under `.godot/imported/`. Read them with `load()`.
  - `editor/export/convert_text_resources_to_binary` defaults to true, so `.tres`/`.tscn` are binary in the PCK; parsing them with `FileAccess` fails.
  - Non-resource files (`.csv`, `.json`, `.md`, `.txt`) ship only if listed in the preset's non-resource include filter.
  - `DirAccess.get_files()` on a `res://` folder of an export returns only the files actually in the PCK (e.g. `.import`/`.remap` entries, not the source names). Use `ResourceLoader.list_directory()`.
- `override.cfg` beside the project or the exported binary overrides project settings at startup.

## FileAccess, DirAccess, JSON, ConfigFile

Docs: `classes/class_fileaccess.rst`, `classes/class_diraccess.rst`, `classes/class_json.rst`, `classes/class_configfile.rst`, `tutorials/io/saving_games.rst`.

- `FileAccess.open(path, flags) -> FileAccess` returns null on failure; read the reason with `FileAccess.get_open_error()`. Flags: `READ` 1, `WRITE` 2, `READ_WRITE` 3, `WRITE_READ` 7.
- `FileAccess.get_file_as_string(path)` / `get_file_as_bytes(path)` return empty on failure; `get_open_error()` tells why.
- `FileAccess.file_exists(path)` does not see imported resources in an export; use `ResourceLoader.exists()` for them.
- `store_*` methods return `bool` in 4.x. The file closes when the `FileAccess` is freed (goes out of scope) or on `close()`; `flush()` forces a write.
- `get_as_text()` lost its `skip_cr` argument (4.6/4.7 change).
- `get_csv_line(delim := ",") -> PackedStringArray` reads one CSV row, quotes handled.
- `store_var(value, full_objects := false)` / `get_var(allow_objects := false)`: with objects allowed, the data can carry scripts and run code. Keep both false for anything from a client or the network.
- `DirAccess.open(path)` returns null on failure. Static `DirAccess.get_files_at(path)`, `get_directories_at(path)`, `make_dir_recursive_absolute(path)`, `remove_absolute(path)`, `rename_absolute(from, to)`, `dir_exists_absolute(path)`; the `*_absolute` forms want a full path (`res://`, `user://` or OS path).
- JSON:
  - `JSON.parse_string(text) -> Variant` returns null on failure with no detail.
  - For errors: `var j := JSON.new(); var err := j.parse(text, keep_text := false)`, then `j.data`, `j.get_error_line()`, `j.get_error_message()`.
  - `JSON.stringify(data, indent := "", sort_keys := true, full_precision := false)`.
  - Every number parses as `float`; cast ints back. `INF` is written as `1e99999`, `NaN` as `null`.
  - `Vector3`, `Color` and other engine types are not JSON; `JSON.from_native(v)` / `JSON.to_native(v)` round-trip them.
  - The parser accepts some non-standard input (for example trailing commas); do not rely on it for files other tools read.
- `ConfigFile`: `load(path) -> Error`, `save(path) -> Error`, `parse(text) -> Error`, `get_value(section, key, default = null)`, `set_value(section, key, value)`, `has_section_key(section, key)`, `get_sections()`, `get_section_keys(section)`, `encode_to_text()`. Comments are lost on save. Encrypted forms: `load_encrypted`, `save_encrypted`, `load_encrypted_pass`, `save_encrypted_pass`.

## Threads

Docs: `tutorials/performance/using_multiple_threads.rst`, `tutorials/performance/thread_safe_apis.rst`, `classes/class_workerthreadpool.rst`, `classes/class_thread.rst`, `classes/class_mutex.rst`, `classes/class_semaphore.rst`.

- The active scene tree is not thread-safe. Build nodes in a thread only while they are off-tree, then `add_child.call_deferred(node)` on the main thread.
- Physics servers are not thread-safe unless `physics/3d/run_on_separate_thread` is on; with it off, do space queries only from the main thread.
- `NavigationServer3D` queries are thread-safe; `AStar3D`/`AStarGrid2D` are not.
- `Array`/`Dictionary`: reading and writing existing elements from several threads is fine; anything that changes the size (append, erase, resize) needs a `Mutex`.
- Do not change one `Resource` from several threads; load a resource on one thread at a time.
- `WorkerThreadPool` (preferred over raw threads):
  - `add_task(action: Callable, high_priority := false, description := "") -> int`.
  - `add_group_task(action: Callable, elements: int, tasks_needed := -1, high_priority := false, description := "") -> int`. The callable gets the element index.
  - `wait_for_task_completion(task_id) -> Error` (can return `ERR_BUSY` when waiting would deadlock), `wait_for_group_task_completion(group_id)`, `is_task_completed(task_id)`, `is_group_task_completed(group_id)`, `get_caller_task_id()`.
  - Every task must be waited on, even if it has finished.
  - `threading/worker_pool/max_threads` defaults to -1 (one per logical core); `threading/worker_pool/low_priority_thread_ratio` 0.3.
- `Thread`: `start(callable, priority := Thread.PRIORITY_NORMAL) -> Error`, `wait_to_finish()` (required), `is_alive()`, `is_started()`, static `Thread.is_main_thread()`, static `Thread.set_thread_safety_checks_enabled(enabled)`. Creating a thread is slow; make them once, up front.
- `Mutex` is reentrant: `lock()`, `try_lock() -> bool`, `unlock()` (once per lock). `Semaphore` starts at 0: `post(count := 1)`, `wait()`, `try_wait() -> bool`.
- The project uses one: `WorldVisibility.cull` sorts the map's meshes into CS2's visibility clusters on a `WorkerThreadPool` task while the rest of the map loads, draws everything until it is done, and waits on it before its first use and before it is freed. Nothing in the simulation is threaded. A tick must give the same result every run, so any threaded work in the simulation would have to join before the tick continues (inferred).

## Command line and headless runs

Docs: `tutorials/editor/command_line_tutorial.rst`, `tutorials/export/exporting_for_dedicated_servers.rst`, `classes/class_displayserver.rst`, `classes/class_os.rst`.

- Unknown arguments are ignored silently; a typo does nothing, it does not fail.
- `--headless` is shorthand for `--display-driver headless --audio-driver Dummy`. What that disables:
  - No window and no drawing: `Engine.get_frames_drawn()` stays 0, `DisplayServer.get_name()` is `"headless"`, and `DisplayServer.window_can_draw()` returns false.
  - No `RenderingDevice`: `RenderingServer.create_local_rendering_device()` returns null, GPU adapter names are empty, and the shader baker does not run. Nothing about the GPU can be measured.
  - No audio output (Dummy driver). Audio nodes still exist and play logically (inferred).
  - Physics, scripts, resource loading and the main loop run normally.
- `--script <path>` / `-s <path>`: runs the script as the main loop; it must extend `SceneTree` or `MainLoop`. The path is relative to the project (`--path`) or absolute. With `--check-only` it only parses the script.
- `--path <dir>`: the project folder. `--scene <path>`: the scene to run. `--main-loop <name>`: a main loop class by name.
- `--import`: imports resources and quits; editor builds only; it implies `--editor --quit`.
- `--quit`: quit after the first iteration. `--quit-after <n>`: after n iterations.
- `--fixed-fps <fps>`: fixed delta every frame; turns off real-time sync (a run goes as fast as it can). `--time-scale <scale>`, `--max-fps <fps>`, `--disable-vsync`, `--print-fps`.
- `--verbose`/`-v`, `--quiet`/`-q`, `--no-header`, `--log-file <file>`.
- `--debug-collisions`, `--benchmark`, `--single-threaded-scene`.
- `--export-release <preset> <path>`, `--export-debug`, `--export-pack`: the output path is relative to the project folder; editor builds only.
- User arguments go after `--` (or `++`). `OS.get_cmdline_user_args()` returns them; `OS.get_cmdline_args()` returns the others, minus engine arguments.
- Shebang for a standalone script: `#!/usr/bin/env -S godot -s`.
- The `dedicated_server` export mode / feature tag forces headless and can strip visual resources. Check it with `OS.has_feature("dedicated_server")`.

## Class notes

**Node** (`classes/class_node.rst`)
- `process_physics_priority: int = 0` (accessors `set_physics_process_priority` / `get_physics_process_priority`), `process_priority: int = 0`.
- `process_mode = PROCESS_MODE_INHERIT`, `process_thread_group = PROCESS_THREAD_GROUP_INHERIT`, `physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_INHERIT`.
- `set_physics_process(enable)`, `is_physics_processing()`, `set_process(enable)`, `get_physics_process_delta_time()`, `get_process_delta_time()`.
- `add_child(node, force_readable_name := false, internal := 0)`, `remove_child(node)`, `reparent(new_parent, keep_global_transform := true)`, `replace_by(node, keep_groups := false)`, `duplicate(flags := 15)`.
- `queue_free()`, `is_queued_for_deletion()`, `is_inside_tree()`, `is_node_ready()`, `request_ready()`, `reset_physics_interpolation()`.
- `call_deferred_thread_group(method, ...)`, `call_thread_safe(method, ...)`, `set_deferred_thread_group`, `set_thread_safe`.
- Gotcha: `_ready` runs once; `_enter_tree` runs on every insertion.

**SceneTree** (`classes/class_scenetree.rst`)
- Signals: `physics_frame`, `process_frame`, `scene_changed`, `node_added`, `node_removed`, `tree_changed`.
- `quit(exit_code := 0)`, `create_timer(time_sec, process_always := true, process_in_physics := false, ignore_time_scale := false)`, `create_tween()`.
- `paused`, `physics_interpolation`, `auto_accept_quit`, `root`, `current_scene`, `get_frame()`, `call_group`, `get_nodes_in_group`, `queue_delete`.

**MainLoop** (`classes/class_mainloop.rst`)
- Virtuals `_initialize()`, `_finalize()`, `_physics_process(delta) -> bool`, `_process(delta) -> bool`. True ends the loop.

**Engine** (`classes/class_engine.rst`)
- `physics_ticks_per_second: int = 60`, `max_physics_steps_per_frame: int = 8`, `physics_jitter_fix: float = 0.5`, `time_scale: float = 1.0` (does not scale audio), `max_fps: int = 0`.
- `get_physics_frames()`, `get_process_frames()`, `get_frames_drawn()`, `get_physics_interpolation_fraction()`, `is_in_physics_frame()`, `is_editor_hint()`, `get_main_loop()`, `get_singleton(name)`.
- `print_error_messages` and `print_to_stdout` switch engine output; `capture_script_backtraces` adds GDScript backtraces to logged errors.

**Time** (`classes/class_time.rst`)
- `get_ticks_usec() -> int`, `get_ticks_msec() -> int` (since engine start, 64-bit, monotonic), `get_unix_time_from_system() -> float`. Use these, not `OS`, for durations.

**OS** (`classes/class_os.rst`)
- `get_cmdline_args()`, `get_cmdline_user_args()`, `has_feature(tag)`, `is_debug_build()`, `get_environment(name)`, `get_processor_count()`, `delay_usec(usec)` (blocks), `get_thread_caller_id()`, `get_main_thread_id()`.
- `execute(path, arguments, output := [], read_stderr := false, open_console := false) -> int`: blocks; returns the exit code or -1.
- `low_processor_usage_mode` and `delta_smoothing` change frame timing; leave them off for measurements.
- `add_logger(logger)`: hooks printed errors and messages (a `Logger` subclass).

**ProjectSettings** (`classes/class_projectsettings.rst`)
- `get_setting(name, default = null)` ignores feature-tag overrides; `get_setting_with_override(name)` applies them.
- `set_setting`, `save()`, `globalize_path`, `localize_path`, `has_setting`.
- Physics tick settings are read only at startup (use `Engine` at run time).

**FileAccess / DirAccess / JSON / ConfigFile**: see the section above.

**ResourceLoader / ResourceSaver / Resource**: see "Resources and loading".

**WorkerThreadPool / Thread / Mutex / Semaphore**: see "Threads".

**Performance** (`classes/class_performance.rst`)
- `get_monitor(monitor) -> float`. Useful ids: `TIME_FPS` 0, `TIME_PROCESS` 1, `TIME_PHYSICS_PROCESS` 2, `TIME_NAVIGATION_PROCESS` 3, `MEMORY_STATIC` 4, `OBJECT_COUNT` 7, `OBJECT_RESOURCE_COUNT` 8, `OBJECT_NODE_COUNT` 9, `OBJECT_ORPHAN_NODE_COUNT` 10 (debug only), the `RENDER_*` monitors 11-16 (0 in headless), `PHYSICS_3D_*` 20-22, `PIPELINE_COMPILATIONS_*` 34-38.
- `TIME_*` monitors are in seconds. Some monitors are debug-only or update only once per second.
- `add_custom_monitor(id, callable, arguments := [], type := MONITOR_TYPE_QUANTITY)`. Types: `MONITOR_TYPE_QUANTITY`, `MONITOR_TYPE_MEMORY`, `MONITOR_TYPE_TIME` (return seconds), `MONITOR_TYPE_PERCENTAGE`. The `type` argument is new in 4.6/4.7. Negative values are clamped to 0.

**DisplayServer** (`classes/class_displayserver.rst`)
- `get_name()` is `"headless"` under `--headless`; `window_can_draw(window_id := 0)` is false there; most other members return dummy values.

## Where the code already does this

Tick and ordering:
- `src/sim/game_world.gd:69` sets `process_physics_priority = -1000` in `_init()` so the world ticks before every other `_physics_process`. `:72-78` set and clear `static var current` in `_enter_tree` / `_exit_tree`. `:106` `_physics_process` calls `step()` (`:111`), which iterates `players.duplicate()` so a player leaving mid-tick does not upset the loop.
- `src/sim/sim_clock.gd`: integer microseconds from the tick count. The doc comment at `:9` notes that nothing in the simulation calls `Time.get_ticks_usec()`; the wall clock is in input and in `src/sim/draw_clock.gd` (drawing).
- Presentation code that keeps its own `_physics_process` (it only reads the tick; it runs after the world because of the -1000 priority): `src/player/player_view.gd:401`, `src/audio/footsteps.gd:85`, `src/combat/ragdoll.gd:204`.
- Custom interpolation from `DrawClock.fraction()` and `DrawClock.usec()`: `src/player/player_view.gd`, `src/bots/bot.gd`, `src/combat/ragdoll.gd`, `src/game/dropped_item_view.gd`, `src/grenades/grenade_view.gd`, `src/effects/shot_effects.gd`, `src/grenades/flash_overlay.gd`. `DrawClock` stamps where each frame's last tick stood on `SceneTree.physics_frame`.
- `src/player/player_input.gd:161`, `:219` stamp input with `Time.get_ticks_usec()` (real time, input side only).
- Real-time `SceneTreeTimer` delays in audio, presentation side only: `src/audio/hit_sounds.gd:180`, `src/audio/weapon_sounds.gd:242`, `:265`. They count scaled process time, not ticks, which is fine for sound.

Tests and scripts:
- `tests/check_suite.gd` extends `SceneTree`; each `tests/run_*.gd` extends it, builds scenes under `root` in `_initialize()`, uses `await physics_frame` (e.g. `tests/run_shotgun_checks.gd:45-46`, twice in a row) and ends with `quit(0|1)` after the `TESTS` line.
- `scripts/run_tests.sh`: `godot --headless --path . --import` first, then `--headless --path "$PROJECT_DIR" --script "tests/$name"` per file; it fails a file on a missing `TESTS` line or a non-zero exit.
- `scripts/profile_dust2.gd`: user args through `OS.get_cmdline_user_args()` (`:49`), wall time through `Time.get_ticks_usec()` (`:54`, `:71`, `:89`), a marker node at `process_physics_priority = 1 << 30` (`:63`) so it runs after every other physics callback, and `Performance.get_monitor` (`:290-292`). `scripts/convert_rcs_patterns.gd:48` also reads user args.

Files and data:
- `FileAccess` reads of `res://reference/...` at load time: `src/weapons/weapon_sheet.gd:129`, `src/weapons/weapon_vdata.gd:117`, `src/weapons/weapon_library.gd:195`, `:235` (`reference/weapons/equipment.md`, `models.md`), `src/audio/weapon_sounds.gd:312` (`sounds.md`, `timings.csv`), `src/weapons/recoil_pattern.gd:33` (write at `:53`, returning `get_open_error()` correctly).
- The `reference/*.csv` files carry `.import` files with `importer="keep"`, so the editor leaves them as plain files for `FileAccess`.
- JSON: `src/effects/sprite_sheet.gd:37`, `src/map/lightmap_materials.gd:297` (stringify `:289`), `src/map/brush_volume.gd:156`, `src/player/player_model.gd:655`.
- `ResourceLoader.exists` before `load`: e.g. `src/bomb/c4_view.gd:139`, `src/economy/buy_menu.gd:215`.
- Caches that copy correctly: `src/combat/hitbox_set.gd:71` returns `.duplicate(true)`.
- `export_presets.cfg` is gitignored, so the include filter lives only on Sid's machine.

Looks at odds with the docs:
- Data read with `FileAccess` from `res://` at run time: `res://reference/weapons/*.md` and `*.csv` (`src/weapons/weapon_library.gd:157-159`, `src/audio/weapon_sounds.gd:33-34`), `.vmdl` next to models (`src/combat/hitbox_set.gd:68-70`), `.vmat` (`src/combat/bullet_impacts.gd:130`), `.sheet.json` (`src/effects/sprite_sheet.gd:37`). In an export these exist only if the preset's non-resource include filter lists them, and `FileAccess.file_exists` returns false otherwise, so the features silently turn off. Looks at odds for exports, not verified (the preset is not in git).
- `src/effects/shot_effects.gd:284-286` checks `FileAccess.file_exists` on an extracted `.png` and loads it with `Image.load_from_file(ProjectSettings.globalize_path(file))`. An imported `.png` source is not in an export and `globalize_path` of a `res://` path does not point to a real file there; `load()` of the imported texture is the documented route. Fine in the editor and headless runs; looks at odds for exports, not verified.
- `tests/run_shotgun_checks.gd:45-46` and others `await physics_frame`. The signal fires before that tick's `_physics_process`, so code right after a single await sees the previous tick's state. The tests await twice, which fits; a new test that awaits once and then checks a tick's result would be off by one (inferred).

## Not covered here

- GDScript language, containers, numbers, typing, warnings: `gdscript.md` (`tutorials/scripting/gdscript/*`).
- Physics queries, Jolt, shapes, layers: `physics.md` (`tutorials/physics/*`).
- Rendering, `RenderingServer`, shader compilation, GPU monitors: `engine.md` and `reference/rendering.md` (`tutorials/rendering/*`, `tutorials/performance/*`).
- Input events and `_input` order: `tutorials/inputs/inputevent.rst` (the project takes input only through `UserCmd`).
- High-level multiplayer (`MultiplayerAPI`, `ENetMultiplayerPeer`, RPCs): `tutorials/networking/*`.
- Exporting step by step and export presets: `tutorials/export/exporting_projects.rst`, `tutorials/export/feature_tags.rst`.
- Custom `ResourceFormatLoader`/`ResourceFormatSaver` and import plugins: `tutorials/plugins/editor/import_plugins.rst`.
- Tweens (`create_tween`) and `AnimationPlayer` timing: `classes/class_tween.rst`, `tutorials/animation/*`.
- Debugger, remote scene tree and profiler GUI: `tutorials/scripting/debug/*` (editor GUI, skipped).
- Encryption of the PCK: `tutorials/export/exporting_pcks.rst`, `contributing/development/compiling/compiling_with_script_encryption_key.rst`.
