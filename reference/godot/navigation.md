# Godot 4.7: navigation

Source: godot-docs branch 4.7 @9adca4c (2026-09-21). Read when: changing how bots find paths (`SourceNavMesh`, `Bot`), budgeting path searches per tick, adding ladders, doors or jump links to the path graph, or considering Godot's NavigationServer3D in place of, or beside, the CS2 `.nav` graph.

## Rules for this project

- The bots path over **CS2's own nav mesh**, read from `maps/<map>.nav` into an `AStar3D` graph of areas (`src/map/source_nav_mesh.gd`). They do not use Godot's NavigationServer. Keep it that way unless a map has no `.nav`. The research and the game's own bots use CS2's areas, and CS2's data carries what a baked mesh would not: attributes such as CROUCH, and jump and drop links.
- `AStar3D` is **not thread-safe**. One thread per AStar object only. Two threads on the same object corrupt it (`tutorials/performance/thread_safe_apis.rst`; `get_point_path` notes it too). Searches stay on the tick's thread, rationed by `GameWorld.may_search_path()`.
- If NavigationServer3D is ever used: **its defaults are in metres**. `cell_size` and `cell_height` are 0.25, `agent_radius` 0.5, `agent_height` 1.5, `agent_max_climb` 0.25, `edge_connection_margin` 0.25 (`classes/class_navigationmesh.rst`, `classes/class_projectsettings.rst`). In inches these are all about 39x too small. A voxel bake of dust2 at 0.25-inch cells "has the potential to freeze the game or even crash". Set the map's and the mesh's cell size together, since they "must match".
- Never parse source geometry from visual meshes at runtime. That reads mesh data back from the GPU and stalls the RenderingServer. Feed collision or procedural arrays (`tutorials/navigation/navigation_using_navigationmeshes.rst`, `navigation_optimizing_performance.rst`). Better still, bake offline (import time) and save the `NavigationMesh` resource, since nothing may read the disk during a tick.
- Do not use `NavigationAgent3D` for bots. It is a node that expects `get_next_path_position()` "once every physics frame" and runs its own path logic and RVO avoidance on the server's sync. That is a system running itself outside `GameWorld`'s tick (CLAUDE.md). Query paths directly and keep path following in the bot brain.
- A changed navigation map takes effect only **after the next physics frame's sync**, and with `navigation/world/map_use_async_iterations = true` (the default) possibly later. Queries in the meantime see the old map (`tutorials/navigation/navigation_using_navigationservers.rst`). A door that opens mid-round (roadmap 24a's "doors and breakables") is simplest in the AStar graph: `set_point_disabled` takes effect on the next search.

## What Godot offers (`tutorials/navigation/navigation_introduction_3d.rst`)

- `AStar3D` finds the shortest path in a graph of weighted **points** that you add and connect yourself. The docs say it is "best suited for cell-based" navigation to "predefined, distinct positions". CS2's nav areas, with a point per area and connections from the area links, are exactly such a graph.
- `NavigationServer3D` finds the shortest path between any two positions on navigation-mesh polygons, grouped in maps (RID), regions, links, agents and obstacles. Helper nodes: `NavigationRegion3D` (holds a `NavigationMesh`), `NavigationLink3D` (a connection over any distance, such as a jump or ladder), `NavigationAgent3D` (path following and RVO avoidance), and `NavigationObstacle3D` (affects avoidance only, **not** pathfinding).
- Each `World3D` has a default navigation map: `get_world_3d().get_navigation_map()`.

## AStar3D (`classes/class_astar3d.rst`)

- `add_point(id, position, weight_scale=1.0)`: `id >= 0`, `weight_scale >= 0`. Re-adding an id updates its position and weight. `reserve_space(n)` before adding many points.
- `connect_points(id, to_id, bidirectional=true)`. With `false`, only `id -> to_id` is walkable, which fits drops and one-way jumps. `are_points_connected(id, to_id, bidirectional=true)`. With `false`, it asks only about the `id -> to_id` direction.
- `get_id_path(from_id, to_id, allow_partial_path=false) -> PackedInt64Array` and `get_point_path(...) -> PackedVector3Array`. Both return an empty array if `from_id` is disabled, even when `from == to`. With `allow_partial_path = true` you get a path to the reachable point closest to the target. That "may take an unusually long time" if `to_id` is disabled.
- A path's cost is the sum of `_compute_cost(u, v)` (default Euclidean) for each segment, times the `weight_scale` of the point being entered. `set_point_weight_scale(id, w)` makes areas costlier. CS2's AVOID or CROUCH areas could get a weight above 1.
- To use your own costs, extend `AStar3D` and override `_compute_cost(from_id, to_id)` and `_estimate_cost(from_id, end_id)`. `_estimate_cost` must be `<=` the true cost for shortest paths. `_filter_neighbor(from_id, neighbor_id)` with `neighbor_filter_enabled = true` skips neighbours per search (return `true` to skip). This could filter per team or per hull without separate graphs. Overriding in GDScript runs script code for every edge the search expands, so it will be slower than the built-in C++ costs (inferred).
- `set_point_disabled(id, disabled=true)` blocks a point, for a closed door or blocked area.
- `get_closest_point(to_position, include_disabled=false) -> int` returns -1 for an empty graph. On a tie it returns the smallest id, deterministically. The docs give no spatial index, so it may scan every point (inferred). The project's own `_grid` lookup is the right tool for "which area am I in".
- Returned `Packed*Array`s are values (copy on write). A caller can keep one safely. The `AStar3D` object is shared by reference.

## NavigationServer3D: queries (`classes/class_navigationserver3d.rst`, `tutorials/navigation/navigation_using_navigationpaths.rst`, `navigation_using_navigationpathqueryobjects.rst`)

- `map_get_path(map, origin, destination, optimize, navigation_layers=1) -> PackedVector3Array` is **synchronous**: it returns the path in the call. `optimize = true` runs the funnel ("string pulling"). `false` puts points at polygon edge centres. The first point is the navmesh point nearest the start and the last the one nearest the target. If the target's mesh is not connected, you get a path to the nearest reachable point on the start's mesh.
- `query_path(parameters: NavigationPathQueryParameters3D, result: NavigationPathQueryResult3D, callback=Callable())` is the configurable form. It fills `result.path`, `path_types`, `path_rids`, `path_owner_ids` and `path_length`. Create the two objects once per bot and reuse them. The docs do not say whether passing a `callback` makes the query asynchronous. Without one, treat it as synchronous like `map_get_path`.
- **Is a synchronous query legal inside a physics tick?** Yes. The NavigationServer is "thread-safe and thread-friendly", query functions "can be called by threads and run in true parallel" (up to `navigation/pathfinding/max_threads` = 4 at once per map), and read-only `get` calls need no waiting for sync (`tutorials/performance/thread_safe_apis.rst`, `navigation_using_navigationservers.rst`). What a query sees is the map as of the last sync. The cost is paid on the calling thread, inside the tick, so ration it as `GameWorld` does now.
- Before the first sync the map is empty and every query returns empty. Check `map_get_iteration_id(map) == 0` ("has never synchronized"), or wait a physics frame (`await get_tree().physics_frame`) after setting up regions.
- `map_force_update(map)` is **deprecated** ("incompatible with asynchronous updates"). Do not use it to get a same-frame map in a test. Step a physics frame instead.
- Query parameters (`NavigationPathQueryParameters3D`): `map`, `start_position`, `target_position`, `navigation_layers` (bitmask), `pathfinding_algorithm` (only `PATHFINDING_ALGORITHM_ASTAR`), `path_postprocessing` (`CORRIDORFUNNEL` default, `EDGECENTERED`, `NONE` for debugging), `metadata_flags` (default 7 = all; turn off what you do not read for speed), `simplify_path` with `simplify_epsilon` (Ramer-Douglas-Peucker; extra cost), `included_regions`/`excluded_regions`, `path_return_max_length`, `path_return_max_radius`, `path_search_max_distance`, and `path_search_max_polygons` (default 4096; on hitting it, you get a partial path toward the closest polygon found).
- Other synchronous reads: `map_get_closest_point(map, to_point)`, `map_get_closest_point_normal`, `map_get_closest_point_to_segment`, `map_get_random_point(map, navigation_layers, uniformly)`, `region_get_closest_point`, `region_owns_point`. `NavigationServer3D.simplify_path(path, epsilon)` works on any point array.
- An unreachable target is the expensive case: the search keeps going until it has ruled out every polygon. Search cost grows with polygon and edge count, not world size (`navigation_optimizing_performance.rst`).

## NavigationServer3D: building and baking (`tutorials/navigation/navigation_using_navigationmeshes.rst`, `classes/class_navigationmesh.rst`, `classes/class_navigationmeshsourcegeometrydata3d.rst`)

- **You can skip baking.** A `NavigationMesh` can be filled directly: `set_vertices(PackedVector3Array)` then `add_polygon(PackedInt32Array)` per convex polygon, and `NavigationServer3D.region_set_navigation_mesh(region, mesh)`. CS2's `.nav` areas are convex 3- and 4-gons, so they could be loaded this way with no voxelization (inferred fit; the docs show a procedural quad). Polygons of different regions join when "at least two vertex positions of one edge exactly overlap". Exact means exact: float error prevents the merge. Otherwise they join by the map's `edge_connection_margin` when edges are "nearly parallel and within distance". `create_from_mesh(mesh)` takes a `PRIMITIVE_TRIANGLES` mesh with an index array.
- Merges are done on the map's cell grid. Vertices merge when they fall in the same cell, which is cheap. Leftover edges are then tested for edge connections, which is costly (`navigation_optimizing_performance.rst`). `map_set_cell_size`/`map_set_cell_height` must match the meshes' `cell_size`/`cell_height`. `navigation/3d/warnings/navmesh_cell_size_mismatch` warns when they do not.
- **Baking off the main thread**, in two steps:
  1. Parse: `NavigationServer3D.parse_source_geometry_data(navigation_mesh, source_geometry_data, root_node, callback=Callable())`. This **must run on the main thread** (or deferred), because the SceneTree is not thread-safe. Which nodes it reads is set on the `NavigationMesh`: `geometry_parsed_geometry_type` (`PARSED_GEOMETRY_MESH_INSTANCES`, `STATIC_COLLIDERS`, `BOTH` = default 2), `geometry_collision_mask`, `geometry_source_geometry_mode` and `geometry_source_group_name`. Or skip the SceneTree and fill a `NavigationMeshSourceGeometryData3D` yourself with `add_faces(faces, xform)` (three vertices per face, clockwise), `add_mesh_array(mesh_array, xform)`, `append_arrays(vertices: PackedFloat32Array, indices: PackedInt32Array)`, `set_vertices`/`set_indices`, and `add_projected_obstruction(vertices, elevation, height, carve)`. With pure data arrays "the entire baking process can be done on a background thread".
  2. Bake: `NavigationServer3D.bake_from_source_geometry_data_async(navigation_mesh, source_geometry_data, callback)` runs "on a background thread". `bake_from_source_geometry_data(...)` is the blocking form. `is_baking_navigation_mesh(mesh)` reports progress. In the callback, apply with `region_set_navigation_mesh`, which takes effect at the next sync.
- `NavigationRegion3D.bake_navigation_mesh(on_thread=true)` wraps both steps. The parsing still happens on the main thread, and it emits `bake_finished`. `NavigationServer3D.region_bake_navigation_mesh` is **deprecated**.
- The source geometry resource can be saved and reused, for example to bake several agent sizes, or so the parse is not repeated at runtime.
- The bake settings on `NavigationMesh` that matter here (defaults are in metres): `cell_size` 0.25, `cell_height` 0.25, `agent_radius` 0.5 (rounded up to a multiple of cell_size), `agent_height` 1.5 (rounded up to cell_height), `agent_max_climb` 0.25 (rounded down to cell_height), `agent_max_slope` 45 degrees, `region_min_size` 2.0 (squared, in cells), `edge_max_error` 1.3, `edge_max_length` 0 (off), `vertices_per_polygon` 6, `sample_partition_type` (`WATERSHED` default; `MONOTONE`/`LAYERS` bake faster on blocky maps), `filter_walkable_low_height_spans`, `filter_ledge_spans`, `filter_low_hanging_obstacles`, and `filter_baking_aabb` with `border_size` for chunked bakes (border is XZ only in 3D). For Source's player (hull 32 wide, 72 tall standing, step 18 units, slope 0.7 normal, about 45.6 degrees), the baked equivalent is roughly `agent_radius` 16, `agent_height` 72 (or 54 crouched as a second mesh), `agent_max_climb` 18, and `cell_size`/`cell_height` of a few inches, with the map cell size to match (inferred from the unit rule; check against `reference/movement_constants.md`).
- The baker has no idea of "inside": geometry inside other geometry gets navmesh on it. `navigation/baking/use_crash_prevention_checks` (default true) stops bakes that could crash.
- Never scale source geometry through node scale. Precision errors follow, and "some scaling only exists as visuals".

## Links, layers and costs (`tutorials/navigation/navigation_using_navigationlinks.rst`, `navigation_using_navigationlayers.rst`, `classes/class_navigationlink3d.rst`)

- `NavigationLink3D` joins two navmesh positions over any distance: `start_position`, `end_position`, `bidirectional`, `enter_cost`, `travel_cost` and `navigation_layers`. The link snaps to polygons within the map's `link_connection_radius` (default 1.0, in metres again). "The actual agent handling and movement needs to happen in custom scripts." A path point flagged `PATH_SEGMENT_TYPE_LINK` in the query result's `path_types` tells the bot to jump or climb. This is the NavigationServer's version of what `SourceNavMesh` already does with gap links.
- `navigation_layers` bitmasks on regions and links, checked per query, can separate what a T and a CT may use, or a crouch-only mesh.
- Regions have `enter_cost` and `travel_cost` (travel is multiplied by the distance crossed in the region).

## Class notes

**AStar3D**: see its section. Also `get_point_connections(id)`, `get_point_ids()`, `get_point_count()`, `get_point_capacity()`, `get_available_point_id()`, `remove_point(id)`, `disconnect_points(id, to_id, bidirectional=true)`, `get_closest_position_in_segment(to_position)`, `set_point_position(id, pos)`, `clear()`.

**NavigationServer3D** (`classes/class_navigationserver3d.rst`)
- Maps: `map_create()`, `map_set_active(map, true)`, `map_set_up`, `map_set_cell_size`, `map_set_cell_height`, `map_set_edge_connection_margin`, `map_set_link_connection_radius`, `map_set_merge_rasterizer_cell_scale`, `map_set_use_edge_connections`, `map_set_use_async_iterations(map, enabled)`, `map_get_iteration_id`, and the signal `map_changed(map)`.
- Regions: `region_create()`, `region_set_map`, `region_set_transform`, `region_set_navigation_mesh`, `region_set_enabled`, `region_set_navigation_layers`, `region_set_enter_cost`, `region_set_travel_cost`, `region_get_iteration_id`.
- Links: `link_create()`, `link_set_map`, `link_set_start_position`, `link_set_end_position`, `link_set_bidirectional`, `link_set_enter_cost`, `link_set_travel_cost`.
- Baking: see above. `free_rid(rid)` frees server objects you created yourself, which are not freed with any node. `get_process_info(INFO_POLYGON_COUNT / INFO_EDGE_MERGE_COUNT / INFO_EDGE_CONNECTION_COUNT / ...)` counts merges. The docs want vertex merges to far outnumber edge connections.
- `set_active(false)` turns the server off. `navigation/3d/navigation_engine = "Dummy"` swaps in a no-op server, an option for a build that has no NavigationServer work (inferred use).
- Gotcha: every setter and free waits for the sync at the end of the physics frame. "Waiting is not required for most `get()` functions."

**NavigationMesh**: see the bake settings above. Also `get_polygon(idx)`, `get_polygon_count()`, `get_vertices()`, `clear_polygons()`, `clear()`.

**NavigationMeshSourceGeometryData3D**: `add_faces`, `add_mesh`, `add_mesh_array`, `append_arrays`, `add_projected_obstruction`, `clear_projected_obstructions`, `merge(other)`, `get_bounds()`, `has_data()`, `clear()`. `set_vertices` warns: "Inappropriate data can crash the baking process."

**NavigationRegion3D**: `navigation_mesh`, `enabled`, `navigation_layers`, `enter_cost`, `travel_cost`, `use_edge_connections`, `bake_navigation_mesh(on_thread=true)`, `is_baking()`, `get_rid()`, `get_region_rid()`, `get_navigation_map()`/`set_navigation_map()`, and the signals `bake_finished` and `navigation_mesh_changed`. A region pushes `global_transform` changes to the server, but **not scale**.

**NavigationAgent3D** (`classes/class_navigationagent3d.rst`, `tutorials/navigation/navigation_using_navigationagents.rst`): `target_position`, `get_next_path_position()` (call once per physics frame), `is_navigation_finished()`, `path_desired_distance`, `target_desired_distance`, `avoidance_enabled` (RVO, "significant performance cost"), and the signal `velocity_computed(safe_velocity)`, sent just before the physics server syncs. Avoidance ignores the navmesh, so a safe velocity can leave it. Not for this project's bots (rules above).

**NavigationPathQueryParameters3D / Result3D**: see the query section. `NavigationPathQueryResult3D.reset()` clears it for reuse.

## Where the code already does this

- `src/map/source_nav_mesh.gd`: reads CS2's `.nav` (versions 30 to 36) into areas and links, keeps a 128-unit `_grid` index to find the area under a point, builds one `AStar3D` per hull in `_graph(hull)` (:767), with one point per area at its centre and one-way connections for links that reach an edge (`connect_points(area.id, link.area, false)`), and caches it in `_graphs`. `route()` calls `get_id_path` (:247). `find_path()` (:257) turns the area route into portal and landing points itself, instead of a funnel.
- `src/sim/game_world.gd`: `PATH_SEARCHES_PER_TICK = 2` and `may_search_path()` ration searches per tick. The comment measures about 0.5 ms a search.
- `src/bots/bot.gd`: asks the world for a search before routing.
- Nothing in `src/`, `maps/` or `scripts/` uses `NavigationServer3D`, `NavigationRegion3D`, `NavigationAgent3D` or `NavigationMesh` (checked with grep).

Looks at odds with the docs (not verified):
- `SourceNavMesh._graph()` hands out the shared, cached `AStar3D`. That is fine single-threaded, but the docs say one AStar object must never be searched from two threads. If path searches ever move to a worker (for example to lift the two-a-tick cap), each worker needs its own graph, or a lock.
- The AStar points sit at area centres, so the search cost between two areas is centre-to-centre distance, not the distance through the shared edge. Long thin areas can then yield a route that is not the shortest walk. This is a design note, not a doc conflict (inferred). `_compute_cost` could use the portal distance at a GDScript cost.

## Not covered here

- 2D navigation (`tutorials/navigation/navigation_introduction_2d.rst`, `AStarGrid2D`).
- RVO avoidance and obstacles in detail (`tutorials/navigation/navigation_using_navigationobstacles.rst`, `navigation_using_navigationagents.rst`).
- Actor types and locomotion (several maps for different agent sizes: `navigation_different_actor_types.rst`, `navigation_different_actor_locomotion.rst`, `navigation_different_actor_area_access.rst`).
- Debug drawing of navmeshes and paths (`tutorials/navigation/navigation_debug_tools.rst`). Useful only on Sid's machine.
- Custom source geometry parsers (`NavigationServer3D.source_geometry_parser_create`, `source_geometry_parser_set_callback`).
