# Godot 4.7: physics, collision queries and ragdolls

Source: godot-docs branch 4.7 @9adca4c (2026-09-21). Read when: adding or changing a ray, hull trace or shape sweep (hitscan, penetration, movement, grenades, smoke, footsteps, line of sight); adding a collision layer, a physics body or an Area3D; touching Jolt project settings; building or tuning ragdolls and joints; drawing anything that moves between 64 Hz ticks.

The 3D math (vectors, transforms, Basis, Quaternion, Plane/AABB, Source Z-up conversion, float precision) is on the companion page `math.md`.

## Rules for this project

- Query the world through `PhysicsDirectSpaceState3D` (`get_world_3d().direct_space_state`) from the tick, which runs in `_physics_process`. The docs say the space is only safe to access during `_physics_process`, and outside it the space "may be locked" (`tutorials/physics/ray-casting.rst`). `World3D.direct_space_state` adds that with multi-threaded physics, access is limited to `_physics_process` on the main thread.
- Never use `move_and_slide()` for players. It applies Godot's own slide response (`floor_max_angle`, `floor_snap_length`, `max_slides=6`, `wall_min_slide_angle`). The project ports Source's TryPlayerMove instead. `move_and_collide()` / `test_move()` are only the hull trace underneath it.
- Count every hull trace you add (`PlayerBody.traces`). The project measured a hull trace through dust2 at 20 to 50 us and a ray at 2 to 15 us (`reference/performance.md`). The docs rank shape cost as sphere < box < capsule < cylinder < convex < heightmap < concave (`classes/class_shape3d.rst` and each shape's class page).
- The project runs Jolt, and every Jolt length setting is documented "in meters". In this project 1 unit = 1 inch, so any Jolt length or speed setting you touch must be multiplied by 39.37. `project.godot` already does this for the ones it sets (listed below). Unitless settings (fractions, radians, iteration counts) must not be scaled.
- Pass RIDs in `exclude` (`Array[RID]`, from `CollisionObject3D.get_rid()`), not nodes. The 2D tutorial's `query.exclude = [self]` predates the typed property. For anything more than a few exclusions, use a mask, which the docs call "much more efficient" (`ray-casting.rst`).
- Hitboxes are `Area3D`s. A ray only sees them with `collide_with_areas = true`, which defaults to `false` on every query parameters class.
- Don't scale physics bodies or collision shapes. "Godot does not currently support scaling of physics bodies or collision shapes" (`troubleshooting_physics_issues.rst`), and `CollisionObject3D` warns against non-uniform scale. Bake the scale into shape sizes or triangles, as `MapImporter._build_collision` and `Ragdoll` already do.
- A shape resource is shared by every node that uses it. Before resizing it per instance, `duplicate()` it (troubleshooting page). `PlayerBody` does this for its hull.
- Physics is not deterministic, "regardless of physics engine" (`physics_introduction.rst`). Anything that decides the game must come from your own tick code and queries, never from `RigidBody3D` simulation. Keep rigid bodies (ragdolls) cosmetic.
- For CS2-style networking, set `physics/common/physics_jitter_fix` to `0`. The docs recommend `0` "within a network game" and "when using a custom physics interpolation solution" (`classes/class_engine.rst`, `class_projectsettings.rst`). The project is both, and it still has the default of 0.5 (see the code section below).

## Spaces and when you may query them

Doc: `tutorials/physics/ray-casting.rst`, `classes/class_world3d.rst`, `classes/class_physicsserver3d.rst`

- All low-level collision data lives in a *space* (an RID). `Node3D.get_world_3d().space` is the RID. `get_world_3d().direct_space_state` (or `PhysicsServer3D.space_get_direct_state(space_rid)`) gives the queryable `PhysicsDirectSpaceState3D`.
- Physics runs on the main thread by default. `physics/3d/run_on_separate_thread` (default `false`) moves it to another thread, and then "restricts API access to only physics process". On Jolt that setting is "experimental" (`using_jolt_physics.rst`) and makes error messages name nodes `<unknown>`.
- `_physics_process(delta)` "is called before each physics step" (`physics_introduction.rst`). So in a tick, every node's `_physics_process` runs first (ordered by `process_physics_priority`; `GameWorld` uses -1000) and then the server steps rigid bodies.
- `_input()` may run while the space is locked. Do input-driven queries in the tick (`ray-casting.rst`).
- (inferred) A body you move with `move_and_collide` or by setting `global_transform` during the tick is seen at its new place by later queries in the same tick. The project's sequential per-player movement relies on this. The docs don't state it.
- `Area3D` overlap lists (`get_overlapping_bodies/areas`, `overlaps_body/area`) and `RigidBody3D.get_colliding_bodies()` are updated "once during the physics step, not immediately after objects are moved". Don't use them for same-tick decisions. Query the space instead (`classes/class_area3d.rst`).

## Ray queries: intersect_ray

Doc: `classes/class_physicsdirectspacestate3d.rst`, `classes/class_physicsrayqueryparameters3d.rst`, `tutorials/physics/ray-casting.rst`

- `PhysicsRayQueryParameters3D.create(from: Vector3, to: Vector3, collision_mask: int = 4294967295, exclude: Array[RID] = []) static`. `from`/`to` are **global** coordinates.
- Properties and defaults: `collide_with_areas=false`, `collide_with_bodies=true`, `collision_mask=4294967295`, `exclude=[]`, `from`, `to`, `hit_back_faces=true`, `hit_from_inside=false`.
- `exclude` getter returns a **copy**: "modify the returned array, and then assign it to the property again".
- `intersect_ray(parameters) -> Dictionary`. It returns an **empty dictionary** on a miss (test with `is_empty()`). On a hit the keys are:
  - `collider` (Object)
  - `collider_id` (ObjectID)
  - `normal`
  - `position`
  - `face_index`
  - `rid`
  - `shape` (shape index within the collider)
  - The 3D class page lists no `metadata` key. The 2D tutorial's dict does have one.
- `normal` is `Vector3(0, 0, 0)` when the ray starts inside a shape and `hit_from_inside` is `true`.
- `face_index` is only valid for `ConcavePolygonShape3D`, otherwise -1. **On Jolt it is always -1** unless `physics/jolt_physics_3d/queries/enable_ray_cast_face_index=true`, which costs about 25% more memory per concave shape (`using_jolt_physics.rst`).
- `hit_from_inside`: "If true, the query will detect a hit when starting inside shapes. ... Does not affect concave polygon shapes or heightmap shapes." With the default `false`, a ray that starts inside a convex or primitive shape passes out of it without a hit.
- `hit_back_faces`: "If true, the query will hit back faces with concave polygon shapes with back face enabled or heightmap shapes." On Jolt a one-sided trimesh (`backface_collision` off, as dust2's collision is) is never hit from behind, with `hit_back_faces` true or false (tested headless in the docs audit). So it matters only for shapes with back faces on; `Hitscan._find_exit` sets it false anyway, which is harmless.
- To get a surface name from a hit, map the shape index back to its `CollisionShape3D` node with `collider.shape_owner_get_owner(collider.shape_find_owner(hit["shape"]))` (`classes/class_collisionobject3d.rst`; the same recipe is in the `RigidBody3D`/`Area3D` signal docs). `Hitscan._surface_name` does this.
- `RayCast3D` nodes re-cast every physics frame. The project uses direct queries instead, which is what the tutorial recommends for interactive or code-driven casts.

## Shape queries: cast_motion, get_rest_info, collide_shape, intersect_shape, intersect_point

Doc: `classes/class_physicsdirectspacestate3d.rst`, `classes/class_physicsshapequeryparameters3d.rst`, `classes/class_physicspointqueryparameters3d.rst`

- `PhysicsShapeQueryParameters3D` properties and defaults:
  - `collide_with_areas=false`, `collide_with_bodies=true`, `collision_mask=4294967295`, `exclude=[]`
  - `margin=0.0`, `motion=Vector3(0,0,0)`, `shape` (Resource), `shape_rid=RID()`, `transform=Transform3D.IDENTITY`
- `shape` holds a reference, so the shape can't be freed mid-query ("always prefer using this over `shape_rid`"). `shape_rid` is for the Servers API: `PhysicsServer3D.sphere_shape_create()` then `shape_set_data(rid, radius)`, and free it with `PhysicsServer3D.free_rid(rid)`.
- `cast_motion(parameters) -> PackedFloat32Array`: `[safe, unsafe]`, both fractions 0 to 1 of `motion`.
  - `safe` is "the maximum fraction of the motion that can be made without a collision".
  - `unsafe` is "the minimum fraction of the distance that must be moved for a collision".
  - No collision gives `[1.0, 1.0]`.
  - Shapes the query shape **already overlaps at the start are ignored**. Use `collide_shape()` to find those.
  - It returns no normal or collider. To learn what was hit, place the shape at `from + motion * unsafe` with `motion = ZERO` and call `get_rest_info` (the grenade sweep does exactly this).
- `get_rest_info(parameters) -> Dictionary`: the nearest intersecting shape, as keys `collider_id`, `linear_velocity` (`(0,0,0)` for an Area3D), `normal`, `point`, `rid`, `shape`.
  - There is **no `collider` key**. Use `instance_from_id(rest["collider_id"])`.
  - `normal` is "of the query shape at the intersection point, pointing away from the intersecting object".
  - A miss returns an empty dict. It ignores `motion`.
- `collide_shape(parameters, max_results: int = 32) -> Array[Vector3]`: contact points in pairs. The first of each pair is on the query shape, the second on the space's shape. It ignores `motion`.
- `intersect_shape(parameters, max_results: int = 32) -> Array[Dictionary]`: each entry has `collider`, `collider_id`, `rid`, `shape`. There are no points or normals. It ignores `motion`.
- `intersect_point(PhysicsPointQueryParameters3D, max_results: int = 32) -> Array[Dictionary]`: each entry has `collider`, `collider_id`, `rid`, `shape`. The docs say it "checks whether a point is inside any solid shape". A `ConcavePolygonShape3D` has no volume, so (inferred) a point inside a trimesh room isn't "inside" it.
- `max_results` exists "to save processing time". Keep it as low as the use allows.
- On Jolt, `physics/jolt_physics_3d/queries/use_enhanced_internal_edge_removal` (default `false`) applies to `cast_motion`, `collide_shape`, `get_rest_info` and `intersect_shape`. It reduces ghost-edge normals when sweeping along seams inside one body, but "can cause certain shapes to be culled from the results entirely" (you still get at least one intersection per body).
- (inferred) Every `PhysicsRayQueryParameters3D.create(...)` / `PhysicsShapeQueryParameters3D.new()` / `SphereShape3D.new()` allocates a RefCounted object. In a hot loop, reuse one params object and one shape and change `from`/`to`/`transform`/`motion`.

## Motion queries: move_and_collide, test_move, body_test_motion

Doc: `classes/class_physicsbody3d.rst`, `classes/class_kinematiccollision3d.rst`, `classes/class_physicstestmotionparameters3d.rst`, `classes/class_physicstestmotionresult3d.rst`

- `PhysicsBody3D.move_and_collide(motion: Vector3, test_only: bool = false, safe_margin: float = 0.001, recovery_as_collision: bool = false, max_collisions: int = 1) -> KinematicCollision3D`.
  - It moves the body and stops at a collision. It returns null when nothing was hit.
  - `test_only` computes the result without moving.
  - `safe_margin` is "the extra margin used for collision recovery": a body at least that close to another counts as colliding and is pushed out before the motion. In this project 0.001 is 0.001 inch.
  - `recovery_as_collision` reports depenetration as a collision.
- `PhysicsBody3D.test_move(from: Transform3D, motion: Vector3, collision: KinematicCollision3D = null, safe_margin: float = 0.001, recovery_as_collision: bool = false, max_collisions: int = 1) -> bool`. It "virtually sets" the body to `from` and returns true if a collision would stop the motion. Pass a `KinematicCollision3D.new()` to fill it.
- `KinematicCollision3D`:
  - `get_travel()`, `get_remainder()`, `get_depth()`, `get_collision_count()`
  - Per collision index (default 0, "the deepest collision"): `get_position`, `get_normal`, `get_angle(idx, up=Vector3.UP)`, `get_collider`, `get_collider_id`, `get_collider_rid`, `get_collider_shape`, `get_collider_shape_index`, `get_collider_velocity`, `get_local_shape`.
  - The `CharacterBody3D` docs warn: "The collision normal is not always the same as the surface normal".
- Server-level equivalent: `PhysicsServer3D.body_test_motion(body: RID, parameters: PhysicsTestMotionParameters3D, result: PhysicsTestMotionResult3D = null) -> bool`.
  - Params and defaults: `from` (Transform3D), `motion`, `margin=0.001`, `max_collisions=1` (1 to 32, deepest first), `exclude_bodies: Array[RID]`, `exclude_objects: Array[int]`, `collide_separation_ray=false`, `recovery_as_collision=false`.
  - The result adds `get_collision_safe_fraction()` and `get_collision_unsafe_fraction()`.
- On Jolt, all four motion paths (`move_and_slide`, `move_and_collide`, `test_move`, `body_test_motion`) use these settings:
  - `physics/jolt_physics_3d/motion_queries/recovery_iterations` (default 4) and `recovery_amount` (0.4, the fraction of penetration removed per iteration).
  - `motion_queries/use_enhanced_internal_edge_removal` (default **true**; only for edges within one body).
- Why not `CharacterBody3D.move_and_slide()`, beyond feel:
  - It reads `velocity` and multiplies by the physics delta itself.
  - It runs `max_slides=6` iterations with Godot's floor, wall and ceiling classification (`floor_max_angle=0.785` rad, `floor_snap_length=0.1`, `wall_min_slide_angle=0.262`, `floor_stop_on_slope`, `floor_block_on_wall`, `platform_*`).
  - It **pushes** other CharacterBody3D and RigidBody3D bodies it touches.
  - None of that is Source's TryPlayerMove/StepMove. `CharacterBody3D` is used only as a `PhysicsBody3D` that has `move_and_collide`.

## Collision objects, layers and masks

Doc: `tutorials/physics/physics_introduction.rst`, `classes/class_collisionobject3d.rst`

- There are 32 layers. `collision_layer` is the layers the object is **in**. `collision_mask` is the layers it **scans**. Both default to 1 (bit 0). "Object A can detect a contact with object B only if object B is in any of the layers that object A scans."
- Layer N is bit `1 << (N - 1)`. Layer numbers in `set_collision_layer_value(layer_number, value)` / `set_collision_mask_value` / the `get_*_value` versions are 1 to 32. A query's `collision_mask` is the raw bitmask, and "all layers" is `0xffffffff` (4294967295).
- `disable_mode` (default `DISABLE_MODE_REMOVE`) decides what happens when `process_mode` is `PROCESS_MODE_DISABLED`: remove from the simulation, make static, or keep active.
- `get_rid()` gives the object's server RID, for `exclude` lists and `PhysicsServer3D` calls.
- Shapes on a body are grouped by owner. The `shape_owner_*` API maps a server shape index to its node, via `shape_find_owner(shape_index)` and `shape_owner_get_owner(owner_id)`.
- `CollisionShape3D` must be a **direct** child of the body: "Indirect child nodes ... will be ignored" (`collision_shapes_3d.rst`).
- The project's layers (from code):

| Layer bit | Value | Holder |
|---|---|---|
| 1 | 1 | world collision `Hitscan.WORLD_LAYER` |
| 2 | 2 | player/bot hulls `PlayerSim.PLAYER_LAYER` |
| 3 | 4 | hitboxes `Hitbox.LAYER` |
| 4 | 8 | player clip `MapImporter.PLAYER_CLIP_LAYER` |
| 5 | 16 | ragdoll bodies `Ragdoll.LAYER` |
| 6 | 32 | grenade clip `GrenadeRules.GRENADE_CLIP_LAYER` |
| 20 | 1<<19 | `PlayerSim.UNSEEN_LAYER` |

## Body types

Doc: `physics_introduction.rst`, `classes/class_staticbody3d.rst`, `class_animatablebody3d.rst`, `class_rigidbody3d.rst`, `class_characterbody3d.rst`, `class_area3d.rst`

- `StaticBody3D` isn't moved by the engine. If you move it, it teleports without affecting bodies in its path. `constant_linear_velocity` and `constant_angular_velocity` affect touching bodies without moving the body itself. It can take `physics_material_override`. It's the right home for level trimeshes.
- `AnimatableBody3D`: moved by code or animation. Its velocity is estimated from the movement and "used to affect other physics bodies in its path" (doors, platforms). `sync_to_physics=true` by default. "Do **not** use together with `move_and_collide()`."
- `RigidBody3D` (simulated):
  - Control it through forces and impulses, or `_integrate_forces(state)`. The docs repeat: don't set the transform or `linear_velocity` "every frame ... Use `_integrate_forces()`". The `RigidBody3D` class note also says a rigid body that is a child of a moving node has its global transform reset whenever the ancestor moves.
  - `freeze` + `freeze_mode`:
    - `FREEZE_MODE_STATIC` (default): no collisions along its path.
    - `FREEZE_MODE_KINEMATIC`: collides along its path.
    - For an always-frozen body, use `StaticBody3D`/`AnimatableBody3D` instead.
  - `continuous_cd` (default `false`).
  - Contacts need both `contact_monitor=true` and `max_contacts_reported>0`. `body_entered`/`body_shape_entered` signals need both.
  - `gravity_scale` multiplies `physics/3d/default_gravity`, which this project sets to 0 (gravity is applied by hand).
  - Damping: the per-tick factor is `1 - combined_damp / physics_ticks_per_second` (tick-rate dependent). `*_damp_mode` is `DAMP_MODE_COMBINE` (added to the default of 0.1) or `DAMP_MODE_REPLACE`.
  - `apply_*_impulse` are one-shot. `apply_*_force` are per-tick. `add_constant_*` persist until cleared.
  - A sleeping body skips `_integrate_forces`.
- `CharacterBody3D`: "not affected by physics at all, but they affect other physics bodies in their path". See the section above for why the project only uses its `move_and_collide`.
- `Area3D`:
  - `monitoring` (detects others) and `monitorable` (can be detected) both default `true`.
  - Signals: `body_entered/exited`, `area_entered/exited`, and the `*_shape_*` forms with shape indices.
  - A trimesh (`ConcavePolygonShape3D`) inside an Area3D is hollow and "may give unexpected results". Use convex pieces, as `BrushVolume.shapes()` does.
  - Areas and bodies created directly with `PhysicsServer3D` "might not interact as expected" with Area3D.
  - The project's `Hitbox` is an `Area3D` with `monitoring=false`, `monitorable=true`, found by rays with `collide_with_areas`.

## Shapes

Doc: `tutorials/physics/collision_shapes_3d.rst`, `classes/class_shape3d.rst` and the per-shape pages

- Choose primitives for anything dynamic (they're the most reliable and fastest). Use concave (trimesh) only for level geometry in a `StaticBody3D`: it "will likely not behave well for CharacterBody3Ds or RigidBody3Ds in a mode other than Static".
- `ConcavePolygonShape3D`:
  - It's **hollow**. Its triangles have no inside, so fast small bodies can tunnel through and `intersect_point` doesn't count as inside.
  - `backface_collision=false` by default: "collisions occur only along the face normals". `set_faces(PackedVector3Array)` takes a triangle list whose length is a multiple of 3. `get_faces()` returns one.
  - Contact reporting is "less precise than primitive shapes".
- `ConvexPolygonShape3D` is **solid**: it detects objects fully inside it. `points` (PackedVector3Array) is used as a convex hull. The getter returns a copy. Keep the shape count low: many convex pieces can cost more than one trimesh.
- `BoxShape3D.size` is the **full** size (default `Vector3(1,1,1)`). In `PhysicsServer3D.shape_set_data`, SHAPE_BOX takes **half-extents**.
- `CapsuleShape3D.height` is the **full** height including hemispheres (default 2.0; `radius` 0.5). `mid_height` is the cylinder part only. The height must be at least 2 x radius or the values are adjusted.
- `SphereShape3D.radius` defaults to 0.5.
- `CylinderShape3D`: "several known bugs ... Using CapsuleShape3D or BoxShape3D instead is recommended". Jolt handles it better (troubleshooting page).
- `HeightMapShape3D`:
  - `map_width` x `map_depth` grid spaced 1 unit apart and centred on the node.
  - Use NAN for holes (supported on both engines).
  - Non-uniform scale needs Jolt.
- `SeparationRayShape3D`:
  - `length=1.0`, `slide_on_slope=false`.
  - It separates by moving its endpoint to the contact (step-up helper).
  - It only stops motion in `body_test_motion` when `collide_separation_ray=true`.
- `Shape3D.margin` defaults to 0.04 and is "not used in Godot Physics". Jolt uses it (next section). `custom_solver_bias` has no effect on Jolt.
- "Avoid translating, rotating, or scaling CollisionShapes to benefit from the physics engine's internal optimizations". With one untransformed shape in a StaticBody, the broad phase can discard it. With many shapes, the narrow phase checks each (`collision_shapes_3d.rst`).
- `shape_set_data` formats (`class_physicsserver3d.rst`):

| Shape | Data |
|---|---|
| sphere | float radius |
| box | Vector3 half-extents |
| capsule, cylinder | `{"height", "radius"}` |
| convex | PackedVector3Array |
| concave | `{"faces": PackedVector3Array, "backface_collision": bool}` |
| heightmap | `{"width", "depth", "heights", optional "min_height"/"max_height"}` |
| separation ray | `{"length", "slide_on_slope"}` |
| world boundary | Plane |

## Jolt Physics: how it differs, and its settings at inch scale

Doc: `tutorials/physics/using_jolt_physics.rst`, `classes/class_projectsettings.rst`

- Jolt is built in since 4.4, and the default for new projects since 4.6. `physics/3d/physics_engine="DEFAULT"` still means GodotPhysics3D, so set `"Jolt Physics"` explicitly (the project does).
- **Collision margins ("convex radius")**:
  - Jolt first **shrinks** a convex shape by the margin, then adds a rounded shell of the same size. The size doesn't change, but edges and corners are rounded.
  - The margin is `physics/jolt_physics_3d/collisions/collision_margin_fraction` (default 0.08) x the shape AABB's **shortest axis**, capped at `Shape3D.margin` (default 0.04). This applies to box, cylinder and convex polygon shapes.
  - The docs warn margins "can sometimes result in odd collision normals when performing shape queries". Setting the fraction to 0.0 is possible but "too small of a margin can also cause odd collision results".
  - (inferred) At inch scale the cap of 0.04 is 0.04 inch, so Jolt's rounding is about 1/40 of what a metre-scale game gets. That keeps the 32-unit player hull a sharp box, as Source's is, but it's also well below the size Jolt is tuned for. Test before changing either knob.
- **Ghost collisions**:
  - `collisions/active_edge_threshold` (default 0.8727 rad, 50 degrees) marks trimesh and heightmap edges between triangles flatter than that as inactive. A hit on an inactive edge reports the triangle's normal instead.
  - "Enhanced internal edge removal" works only on edges **within one body**. Its three switches have different defaults:

| Setting | Default |
|---|---|
| `simulation/use_enhanced_internal_edge_removal` | true |
| `queries/use_enhanced_internal_edge_removal` | false |
| `motion_queries/use_enhanced_internal_edge_removal` | true |

- **Baumgarte stabilization**: Jolt corrects position only, not velocity, so it can't overshoot and fling bodies apart. The strength is `simulation/baumgarte_stabilization_factor` (0.2; 0 is off, 1 resolves in one step but is unstable).
- **Joints**:
  - These properties are unsupported, and setting them away from their defaults warns:
    - `PinJoint3D`: `bias`, `damping`, `impulse_clamp`
    - `HingeJoint3D`: `bias`, `softness`, `relaxation`
    - `SliderJoint3D`: `angular_*`, `*_limit/softness|restitution|damping`
    - `ConeTwistJoint3D`: `bias`, `relaxation`, `softness`
    - `Generic6DOFJoint3D`: `*_limit_*/softness|restitution|damping|erp`
  - `Joint3D.solver_priority` is ignored.
  - With one body omitted, Jolt treats the body as `node_b` and `node_a` as the world. Godot Physics does the reverse. This is configurable with `joints/world_node`.
  - The extension's JoltPinJoint3D and similar joint nodes aren't in the module.
- **Other differences**:
  - `face_index` is -1 unless enabled (see the ray section).
  - A `FREEZE_MODE_KINEMATIC` rigid body reports no contacts with static or kinematic bodies unless `simulation/generate_all_kinematic_contacts`.
  - `get_contact_impulse()` values are estimates.
  - Area3D reports SoftBody3D overlaps.
  - `WorldBoundaryShape3D` is finite: it covers a box of `limits/world_boundary_shape_size` (default **2000**, i.e. 2000 inches, about 51 m here). Don't use it as a kill floor under dust2 without raising that setting.
  - The settings were renamed from the extension's `physics/jolt_3d/*` to `physics/jolt_physics_3d/*`. Older answers use the old names.
- Settings with physical units, their defaults, and this project's values:

| Setting | Default ("meters") | project.godot |
|---|---|---|
| `simulation/penetration_slop` | 0.02 | 0.787 |
| `simulation/speculative_contact_distance` | 0.02 | 0.787 |
| `simulation/bounce_velocity_threshold` | 1.0 m/s | 39.37 |
| `simulation/sleep_velocity_threshold` | 0.03 m/s | 1.181 |
| `simulation/body_pair_contact_cache_distance_threshold` | 0.001 | 0.0394 |
| `limits/max_linear_velocity` | 500 m/s | 19685 |
| `limits/world_boundary_shape_size` | 2000 | not set |
| `simulation/soft_body_point_radius` | 0.01 | not set (unused) |

- Unitless or other units, leave as is:
  - `limits/max_angular_velocity` (47.12 rad/s)
  - `simulation/continuous_cd_movement_threshold` (0.75) and `continuous_cd_max_penetration` (0.25): fractions of the body's inner radius
  - `simulation/position_steps` (2) and `velocity_steps` (10, must be at least 2 for friction)
  - `simulation/body_pair_contact_cache_angle_threshold` (radians)
  - `simulation/sleep_time_threshold` (0.5 s)
  - `limits/max_bodies` (10240), `max_body_pairs` (65536), `max_contact_constraints` (20480)
  - `limits/temporary_memory_buffer_size` (32 MiB)
- GodotPhysics-only settings **do nothing on Jolt**: `physics/3d/solver/*`, `physics/3d/sleep_threshold_*`, `physics/3d/time_before_sleep`, `Shape3D.custom_solver_bias`, `Joint3D.solver_priority`.

## Tick rate, steps per frame and interpolation

Doc: `tutorials/physics/interpolation/*.rst`, `classes/class_engine.rst`, `classes/class_projectsettings.rst`, `troubleshooting_physics_issues.rst`

- `physics/common/physics_ticks_per_second` (default 60; the project uses 64) is read only at startup. At runtime use `Engine.physics_ticks_per_second`.
- `physics/common/max_physics_steps_per_frame` (default 8; the project uses 16) is the cap on catch-up steps per rendered frame. Past it the game visibly slows. The "physics spiral of death" is the failure it guards against. The runtime version is `Engine.max_physics_steps_per_frame`.
- `physics/common/physics_jitter_fix` (default 0.5; runtime `Engine.physics_jitter_fix`) controls how far ticks may drift from real time to smooth frame jitter. It's automatically disabled when `physics/common/physics_interpolation` is on. Set it to 0 for a custom interpolation scheme or a network game.
- `Engine.get_physics_interpolation_fraction() -> float` is how far through the current tick a rendered frame falls. The project's own interpolation (`SimClock.draw_usec`, views, ragdoll) uses this.
- Godot's built-in interpolation is `physics/common/physics_interpolation` (default `false`; runtime `SceneTree.physics_interpolation`).
  - It interpolates between the last two tick transforms, so everything is drawn 1 to 2 ticks late. The docs themselves suggest a custom scheme for internet multiplayer.
  - In 3D it's scene-side only: bodies created with the servers aren't interpolated.
  - 3D debug collision shapes aren't interpolated.
  - API: `Node.reset_physics_interpolation()` after teleporting (set the transform first, then reset); `Node.physics_interpolation_mode` (`PHYSICS_INTERPOLATION_MODE_INHERIT`/`ON`/`OFF`), where OFF on a child still inherits a moving parent's interpolation; `Node3D.get_global_transform_interpolated()` (only once or twice, e.g. a camera).
  - The project doesn't enable it. It draws between ticks itself. Keep it that way unless you rework every view.
- Mouse look belongs on the camera per frame, not interpolated (`advanced_physics_interpolation.rst`). In the project, what the sim uses is still the `UserCmd`'s angles.
- `Engine.time_scale` scales `delta` but not the tick rate.

## Ragdolls, joints and physical bones

Doc: `tutorials/physics/ragdoll_system.rst`, `classes/class_physicalbone3d.rst`, `class_physicalbonesimulator3d.rst`, `class_joint3d.rst`, `class_conetwistjoint3d.rst`, `class_hingejoint3d.rst`, `class_generic6dofjoint3d.rst`, `class_pinjoint3d.rst`

- Godot's built-in ragdoll setup:
  - A `PhysicalBoneSimulator3D` (a SkeletonModifier3D under the Skeleton3D) is the parent of the `PhysicalBone3D` nodes.
  - `physical_bones_start_simulation(bones: Array[StringName] = [])` starts the simulation. Pass **bone names**, not node names. Unknown names fail silently. `physical_bones_stop_simulation()` stops it, and `is_simulating_physics()` reports it.
  - `physical_bones_add_collision_exception(rid)` and `physical_bones_remove_collision_exception(rid)` handle exceptions.
  - The simulator's `influence` (default 1.0) blends the simulation over the animation.
- `PhysicalBone3D`:
  - `joint_type` is one of `JOINT_TYPE_NONE`/`PIN`/`CONE`/`HINGE`/`SLIDER`/`6DOF`. The generated default is pin, which "leads to crumpling", so use cone and hinge.
  - Other members: `joint_offset`, `joint_rotation`, `body_offset`, `mass`, `friction`, `bounce`, `gravity_scale`, `linear_damp`/`angular_damp` (+ modes), `can_sleep`, `apply_impulse`, `apply_central_impulse`, `get_bone_id()`.
  - Rays only detect physical bones when the simulator's `active` is true and `get_bone_id() >= 0`.
- The tutorial's joint advice:
  - Use hinges for elbows and knees, with `angular_limit/enable` on.
  - For cones, `swing_span` 20 to 90 degrees and `twist_span` 20 to 45.
  - Remove tiny and utility bones (each costs simulation time).
  - Put the ragdoll on its own layer so the living character's collider doesn't hit its own inactive ragdoll.
- `Joint3D`:
  - `node_a`, `node_b` (NodePaths to PhysicsBody3D). If one is empty, it attaches to a fixed invisible StaticBody3D.
  - `exclude_nodes_from_collision=true`: jointed bodies don't collide with each other.
  - `solver_priority` (Godot Physics only), `get_rid()`.
- `ConeTwistJoint3D`:
  - The twist axis is the joint's **X** axis.
  - `swing_span` (default pi/4) and `twist_span` (default pi), in radians. Each is locked below 0.05.
  - `bias`, `softness` and `relaxation` are ignored on Jolt.
- `HingeJoint3D`:
  - It rotates about the joint's **Z**.
  - `angular_limit/enable` (`FLAG_USE_LIMIT`), `angular_limit/lower`/`upper` (default -pi/2 to pi/2 radians), motor (`FLAG_ENABLE_MOTOR`, `motor/target_velocity`, `motor/max_impulse`).
  - `PARAM_LIMIT_SOFTNESS` is deprecated and unused. Bias, softness and relaxation are ignored on Jolt.
- `Generic6DOFJoint3D`:
  - Per-axis linear and angular limits, springs and motors (`FLAG_ENABLE_LINEAR_LIMIT`, `FLAG_ENABLE_ANGULAR_LIMIT`, `FLAG_ENABLE_*_SPRING`, `FLAG_ENABLE_MOTOR`, `FLAG_ENABLE_LINEAR_MOTOR`).
  - `angular_limit_*/enabled` defaults to true with lower = upper = 0, so a fresh 6DOF is **locked** on every angular axis.
  - Several spring params are undocumented.
- The project doesn't use `PhysicalBone3D`. `Ragdoll` builds plain `RigidBody3D`s and joints from the hitbox capsules (see below). If it's migrated, joint frames (`joint_offset`) and bone-name selection are what change.

## Class notes

**PhysicsDirectSpaceState3D** (`classes/class_physicsdirectspacestate3d.rst`)

`intersect_ray(PhysicsRayQueryParameters3D) -> Dictionary`; `intersect_shape(params, max_results=32) -> Array[Dictionary]`; `intersect_point(PhysicsPointQueryParameters3D, max_results=32) -> Array[Dictionary]`; `cast_motion(params) -> PackedFloat32Array [safe, unsafe]`; `collide_shape(params, max_results=32) -> Array[Vector3]` (pairs); `get_rest_info(params) -> Dictionary`. Get it from `World3D.direct_space_state`. Don't instantiate it. The result keys are in the sections above.

**PhysicsRayQueryParameters3D**

`create(from, to, collision_mask=0xffffffff, exclude: Array[RID]=[]) static`; `from`, `to` (global); `collide_with_areas=false`; `collide_with_bodies=true`; `hit_back_faces=true`; `hit_from_inside=false` (no effect on concave or heightmap shapes); `exclude` getter returns a copy.

**PhysicsShapeQueryParameters3D**

`shape` (Resource, preferred) or `shape_rid`; `transform`; `motion` (used only by `cast_motion`); `margin=0.0`; `collision_mask`; `exclude`; `collide_with_areas=false`; `collide_with_bodies=true`.

**PhysicsPointQueryParameters3D**

`position` (global); `collision_mask`; `exclude`; `collide_with_areas=false`; `collide_with_bodies=true`.

**PhysicsServer3D** (`classes/class_physicsserver3d.rst`)

- Queries: `space_get_direct_state(space) -> PhysicsDirectSpaceState3D`; `body_test_motion(body, PhysicsTestMotionParameters3D, PhysicsTestMotionResult3D=null) -> bool`.
- Shapes: `sphere_shape_create()`, `box_shape_create()`, `capsule_shape_create()`, `cylinder_shape_create()`, `convex_polygon_shape_create()`, `concave_polygon_shape_create()`, `heightmap_shape_create()`, `separation_ray_shape_create()`, `world_boundary_shape_create()`, then `shape_set_data(shape, data)`. Also `shape_get_data`, `shape_get_type`, `shape_get_margin` (always 0 on Godot Physics).
- Bodies: `body_create()`, `body_set_space`, `body_add_shape(body, shape, transform=IDENTITY, disabled=false)`, `body_set_shape_transform`, `body_set_shape_disabled`, `body_set_collision_layer/mask`, `body_set_mode`, `body_set_state(body, BodyState, value)`, `body_get_state`, `body_get_direct_state(body)` (null if removed), `body_attach_object_instance_id`, `body_add_collision_exception`.
- Other: `free_rid(rid)` for anything created here; `get_process_info(INFO_ACTIVE_OBJECTS | INFO_COLLISION_PAIRS | INFO_ISLAND_COUNT)`; `set_active(bool)`; `space_create()`, `space_set_active`, `space_set_param`.
- Server bodies aren't physics-interpolated and interact poorly with Area3D nodes.

**World3D**

`space` (RID), `direct_space_state`, `scenario`, `navigation_map`. `direct_space_state` is limited to `_physics_process` on the main thread when physics is multithreaded.

**CollisionObject3D**

`collision_layer=1`, `collision_mask=1`, `collision_priority=1.0`, `disable_mode`, `input_ray_pickable=true`, `get_rid()`, `set_collision_layer_value(layer_number 1..32, bool)` (and the mask/get versions), `shape_find_owner(shape_index)`, `shape_owner_get_owner(owner_id)`, `create_shape_owner`, `shape_owner_add_shape`, `shape_owner_set_transform`, `shape_owner_set_disabled`. Mouse picking (`input_event`) is irrelevant to the sim.

**PhysicsBody3D**

`move_and_collide(...)` and `test_move(...)` (signatures above); `add_collision_exception_with(body: Node)`, `remove_collision_exception_with`, `get_collision_exceptions()`; `axis_lock_*`, `set_axis_lock(axis, lock)`; `get_gravity()`. It warns against non-uniform scale.

**StaticBody3D**

`constant_linear_velocity`, `constant_angular_velocity` (they don't move the body), `physics_material_override`. Moving it teleports it.

**AnimatableBody3D**

`sync_to_physics=true`. It pushes bodies with estimated velocity. Not for `move_and_collide`.

**RigidBody3D**

`mass=1.0`, `gravity_scale=1.0`, `linear_velocity`, `angular_velocity` (rad/s), `linear_damp`/`angular_damp=0.0` with `DAMP_MODE_COMBINE` (added to the global 0.1) or `DAMP_MODE_REPLACE`, `can_sleep=true`, `sleeping`, `freeze`/`freeze_mode`, `continuous_cd=false`, `contact_monitor=false`, `max_contacts_reported=0`, `custom_integrator`, `lock_rotation`, `center_of_mass_mode`, `inertia` (ZERO means auto). Forces: `apply_force(force, position)`, `apply_impulse(impulse, position)` (position is a global offset from the origin), `apply_central_*`, `apply_torque*`, `add_constant_*`. `_integrate_forces(state)` is the safe place to change state. `get_colliding_bodies()` updates once per step.

**CharacterBody3D**

`velocity`, `up_direction=UP`, `motion_mode` (`MOTION_MODE_GROUNDED`/`FLOATING`), `floor_*`, `max_slides=6`, `safe_margin=0.001`, `move_and_slide() -> bool`, `is_on_floor()` and the other `is_on_*` methods, `get_slide_collision(i)`, `get_real_velocity()`. The project uses the node only for `move_and_collide`, never `move_and_slide`.

**Area3D**

`monitoring=true`, `monitorable=true`, overlap getters (updated per step), `body_entered/exited`, `area_entered/exited`, `*_shape_entered/exited(rid, node, other_shape_index, local_shape_index)`. Gravity, damping, audio bus and wind overrides are irrelevant here (the project's gravity is 0).

**KinematicCollision3D**

`get_travel`, `get_remainder`, `get_depth`, `get_collision_count`, and per index `get_position`, `get_normal`, `get_angle(idx, up)`, `get_collider*`, `get_local_shape`.

**Shape3D and subclasses**

Covered in the Shapes section. The traps: box `size` is the full size but server data is half-extents; capsule `height` includes the caps; a trimesh is hollow and one-sided by default; cylinders are buggy on Godot Physics.

**PhysicsMaterial**

`friction=1.0`, `bounce=0.0`, `rough=false` (true uses the rough body's friction; if both are rough, the higher), `absorbent=false` (subtracts bounciness). Bounce 1.0 still loses energy to damping unless damping is replaced with 0.

**Joint3D, HingeJoint3D, ConeTwistJoint3D, PinJoint3D, Generic6DOFJoint3D, PhysicalBone3D, PhysicalBoneSimulator3D**

See the ragdoll section. `set_param(Param, float)`/`get_param`, and `set_flag(Flag, bool)` on hinge and 6DOF. Only limits, spans, motors and (6DOF) springs are honoured on Jolt.

**Engine (physics members)**

`physics_ticks_per_second` (int), `max_physics_steps_per_frame` (int, default 8), `physics_jitter_fix` (float, default 0.5; use 0 for netcode or custom interpolation), `get_physics_interpolation_fraction() -> float`, `get_physics_frames() -> int`, `is_in_physics_frame() -> bool`, `time_scale`.

## Where the code already does this

- `src/movement/player_body.gd`: `PlayerBody extends CharacterBody3D`.
  - `_trace()` wraps `move_and_collide(motion, test_only)` and counts `traces`.
  - `_ground_normal_in_quadrants()` casts four rays with `collision_mask` and `exclude=[get_rid()]`.
  - `_set_hull()` resizes a `BoxShape3D` that `_ready` duplicated first (line 88).
  - It never calls `move_and_slide`.
- `src/combat/hitscan.gd`:
  - `trace()` runs rays on `WORLD_LAYER | Hitbox.LAYER` with `collide_with_areas=true`.
  - `_find_exit()` finds a wall's far side by casting back from depth with `hit_back_faces=false` and `hit_from_inside=false`.
  - `_surface_name()` maps a shape index back to the node name.
- `src/grenades/grenade_flight.gd:120-160`: `_sweep()` runs `cast_motion` on a sphere and then `get_rest_info` at `from + motion * unsafe`, and reads `collider_id` through `instance_from_id`.
- `src/map/map_importer.gd:524-560`: builds world collision as `ConcavePolygonShape3D`s (faces baked with the mesh transform, no scale) under one `StaticBody3D` per layer, with `collision_mask=0`.
- `src/map/brush_volume.gd`: convex pieces for Area3D volumes. `contains()` tests `Plane.distance_to` in script.
- `src/combat/hitbox.gd`, `src/combat/skinned_hitboxes.gd`, `src/combat/hit_target.gd`: hitbox `Area3D`s on layer 4 with capsules or boxes. Their layer is set to 0 when inactive.
- `src/combat/ragdoll.gd`:
  - Builds `RigidBody3D`s plus `ConeTwistJoint3D`s and `HingeJoint3D`s on layer 16, masking the world only.
  - Replaces damping (`DAMP_MODE_REPLACE`), uses `continuous_cd=true`, and applies gravity with `add_constant_central_force`.
  - Skips `PARAM_BIAS` on Jolt (`on_jolt()`).
  - Draws between ticks with `Engine.get_physics_interpolation_fraction()`.
- Rays elsewhere:
  - `src/bots/bot.gd:514` (line of sight)
  - `src/audio/footsteps.gd:131` (surface below)
  - `src/grenades/smoke_voxels.gd:238`, `fire_spread.gd:115`, `grenade_entity.gd:139`, `flash_blind.gd:32`
  - `src/game/item_drops.gd:198`, `src/game/dropped_item.gd:121`
  - `src/player/player_view.gd:229`, `src/effects/muzzle_flashes.gd:616`
- `src/sim/game_world.gd:132`: hands `find_world_3d().direct_space_state` to `GameSystems.step` each tick.
- `src/sim/sim_clock.gd`: tick length from `Engine.physics_ticks_per_second`; draw time from `get_physics_interpolation_fraction()`.
- `project.godot [physics]`: 64 ticks, 16 max steps, Jolt, the Jolt length and speed settings scaled by 39.37, gravity 0.

Looks at odds with the docs (not verified):

- `project.godot` doesn't set `physics/common/physics_jitter_fix`, so it's 0.5. The docs recommend 0 for network games and custom interpolation, and the project is both (its own interpolation in `SimClock.draw_usec` and the views, with CS2-style netcode planned). With 0.5, tick timing is allowed to drift from real time to hide frame jitter.
- `src/effects/muzzle_flashes.gd:616` (`_to_ground`, reached from `ShotEffects._process` → `flashes.advance`) and `src/player/player_view.gd:229` (`death_cam_position`, reached from `_process` → `_spectate`) query `direct_space_state` in `_process`. The docs say the space is only safe in `_physics_process`. It works while physics is on the main thread (inferred), but it breaks if `physics/3d/run_on_separate_thread` is ever enabled. Both are visual-only.
- `src/combat/ragdoll.gd:204-219` writes `angular_velocity` on every body every tick from `_physics_process`. The RigidBody3D docs advise `_integrate_forces()` for per-tick state changes. It's cosmetic, and `ragdoll.gd` documents why it does this.
- `src/grenades/smoke_voxels.gd:239` sets `hit_from_inside = true` on a `WORLD_LAYER` ray. The docs say that flag doesn't affect concave shapes, which is what dust2's collision is. It only matters for convex or box world pieces (e.g. test-range cover), where the hit then has a zero normal. It's harmless but may not do what it reads as.
- `src/grenades/grenade_flight.gd:125` makes a new `SphereShape3D` and query params on every sweep. (inferred) Reusing one per grenade would avoid allocations in the tick.
- The player hull's `CollisionShape3D` is offset (`transform ... 0, 36, 0` in `src/player/player.tscn`, `src/bots/bot.tscn`, and `_set_hull` moves it). `collision_shapes_3d.rst` advises untransformed shapes for broad-phase optimisations. This is minor, and moving the body origin to the hull centre would ripple through movement.

## Not covered here

- Soft bodies: `tutorials/physics/soft_body.rst`.
- 2D physics and `CharacterBody2D` tutorials: `tutorials/physics/using_character_body_2d.rst`, `kinematic_character_2d.rst`, `using_area_2d.rst`, `collision_shapes_2d.rst`.
- `RayCast3D` and `ShapeCast3D` nodes: `classes/class_raycast3d.rst`, `classes/class_shapecast3d.rst`.
- `SliderJoint3D`: `classes/class_sliderjoint3d.rst`.
- `VehicleBody3D`.
- `PhysicsDirectBodyState3D` (for `_integrate_forces`): `classes/class_physicsdirectbodystate3d.rst`.
- Area3D gravity, damping and audio overrides: `classes/class_area3d.rst`.
- `WorldBoundaryShape3D`: `classes/class_worldboundaryshape3d.rst`.
- Generating collision on import (`-col`, `-colonly` suffixes): `tutorials/assets_pipeline/importing_3d_scenes/`.
- Custom physics servers: `PhysicsServer3DExtension`.
- Navigation queries: see the navigation page.
- Large world coordinates and float precision: see `math.md` and `tutorials/physics/large_world_coordinates.rst`.
