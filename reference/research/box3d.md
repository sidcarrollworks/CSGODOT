# Box3D: what it would mean for the game

Sid asked (2026-09-24) what Box3D, and the box3d-godot binding for it, would
mean for us. The original recommendation below concerned a whole-game
conversion. **Updated 2026-09-26:** Sid requested a branch to try Box3D for
dropped guns, whose current simulation still jitters, and chose dropped
guns first. That request supersedes the earlier recommendation for this
limited trial. [The trial notes](../box3d-trial.md) describe its scope,
setup and comparison procedure; this page remains the wider assessment.

## Sources

- `erincatto/box3d` at `8fda30e` (2026-09-24), tag v0.1.0, MIT. Its README,
  `docs/faq.md` (determinism), `docs/character.md` (the mover) and
  `include/box3d/box3d.h`, `constants.h`. **Primary.**
- `Stink-O/box3d-godot` at `87c5ac9` (2026-09-20), release v0.4.3, MIT.
  Its README, `godot/README.md` and `godot/src/`. **Primary.**
- Rechecked 2026-09-26 against the release-tagged
  [world source](https://github.com/Stink-O/box3d-godot/blob/v0.4.3/godot/src/box3d_world.cpp),
  [body source](https://github.com/Stink-O/box3d-godot/blob/v0.4.3/godot/src/box3d_body.cpp)
  and in-editor class documentation. The binding exposes length-unit
  configuration; the earlier claim below that it did not has been corrected.
- Erin Catto's "Announcing Box3D" (box2d.org, June 2026) is refused by the
  thread's network proxy, as is a translation of it. The lineage below comes
  from search summaries of that post (developersdigest.tech, desdelinux.net,
  read 2026-09-24). **Secondary.**
- Our side: `project.godot`, `src/movement/player_body.gd`,
  `src/combat/hitscan.gd`, `src/combat/ragdoll.gd`,
  `reference/performance.md`, on main at `0793475`.

## What Box3D is

- **Lineage.** Dirk Gregorius, a Valve physics programmer, wrote Rubikon,
  the engine Half-Life: Alyx shipped and Source 2 uses. He keeps a hobby
  version, "Rubikon-Lite". Catto forked Rubikon-Lite and replaced almost all
  of its APIs, data structures and algorithms with Box2D's, and that fork
  became Box3D. Ragnarok is Gregorius's newer engine at Valve for future
  games. So Box3D is Box2D's design in 3D grown from a Rubikon skeleton; it
  is not the engine CS2 runs, and it does not reproduce CS2's physics.
- **Features.** Rigid bodies with the Soft Step solver, continuous
  collision, convex hulls, capsules, spheres, triangle meshes and height
  fields; ray, shape and overlap queries; revolute, prismatic, distance,
  motor, weld and wheel joints with limits, motors and springs; recording
  and replay; multithreading and SIMD.
- **Determinism.** The FAQ promises the same result for the same input,
  across thread counts and across platforms (no fused multiply-add,
  IEEE 754 throughout). It does not offer rollback determinism: a world
  cannot be set back to an earlier state and give identical results.
- **Character mover** (marked experimental): a capsule outside the rigid
  body world, cast with `b3World_CastMover` and resolved against the planes
  `b3World_CollideMover` gathers, via `b3SolvePlanes`.
- **Maturity.** Upstream is v0.1.0, three months old, one author. The
  binding calls itself "early and experimental ... a starting point to
  build on, not a production dependency".

## What box3d-godot is

- A GDExtension that adds its own nodes (`Box3DWorld`, `Box3DBody`,
  `Box3DCollisionShape`, nine joints, `Box3DCharacterBody`) and runs its own
  world beside Godot's. **It is not a physics server.** Nothing in
  `godot/src/` extends `PhysicsServer3DExtension`, so it cannot be picked in
  `3d/physics_engine` the way Jolt is. `get_world_3d().direct_space_state`,
  `move_and_collide`, `Area3D`, `RigidBody3D` and the `Joint3D`s keep using
  Jolt whatever else is loaded.
- Queries are methods on `Box3DWorld`: `raycast`, `raycast_all`,
  `shape_cast_box`, `shape_cast_capsule`, `shape_cast_sphere`,
  `shape_cast_convex` and overlaps. A box cast exists, which our hull would
  need.
- It defaults to metres. Version 0.4.3 exposes
  `physics/box3d/length_units_per_meter`, applied when the extension loads,
  and `Box3DWorld.set_length_units_per_meter()`, which refuses a change
  while any native world exists. These scale the engine's tolerances;
  they do not convert coordinates, density or the binding's separately
  authored distance/speed properties. The opening paragraph in upstream's
  world XML still says the scale is fixed, but the implementation and the
  setter's documentation show otherwise. The dropped-gun trial keeps the
  default of 1 and converts inches to metres at its boundary.
- Godot 4.7 is its minimum, which matches ours. Prebuilt for Windows, Linux,
  Android and web; not macOS.

## What would change for us

What decides how the game feels is not the physics engine. Movement is our
port of Source's TryPlayerMove and StepMove (`player_body.gd`) over hull
traces; shooting and penetration are rays (`hitscan.gd`). A trace against
the same triangles gives the same answer in any engine, to within its
tolerances. Swapping engines would not make movement or hits any closer to
CS2; our port does that.

Moving to Box3D would mean:

1. **A second copy of the world.** Every map's collision built again as
   `Box3DBody` triangle meshes, with its surface names (footsteps and
   penetration read them) carried across.
2. **Every query rewritten.** The hull trace (`move_and_collide` in
   `_trace`), the ground check, the hitscan and penetration rays, grenade
   flight (`cast_motion`), dropped items, footsteps, bot sight lines, and
   the hitbox capsules, which are `Area3D`s on their own layer today.
3. **Ragdolls rebuilt** (`ragdoll.gd`, 25 lines that use `RigidBody3D` and
   `Joint3D`) on Box3D joints.
4. **Units handled explicitly:** either convert to metres at the boundary,
   or configure the length scale before creating a world and scale every
   distance/speed property too. A binding patch is not required.
5. **Its own Source-style mover left unused.** Box3D's mover is a capsule
   that slides by solving planes; Source's is a box hull that clips its
   velocity against each plane it meets (ClipVelocity), which is what
   surfing, ramps and edge behaviour depend on. We would keep our port and
   only use Box3D's box cast underneath it.

What it could give:

- **Cross-platform determinism.** Less than it sounds for this game. CS2's
  servers decide every hit and every move, and a client re-runs its own
  movement, which is our GDScript over traces, not a solver. Ragdolls are
  cosmetic and client-side in CS2. Grenades are our own script over
  `cast_motion`. Rollback, the case determinism usually serves, is the one
  case Box3D says it does not support.
- **Speed.** Unmeasured. A hull trace is 20 to 50 us on Jolt and most of
  what a player costs a tick (`performance.md`); Box3D's box cast might be
  faster or slower, and a GDExtension call costs about what Jolt's does.
  Jolt already took the tick from 4.3 ms to 3.5 (#44).
- **Ragdolls.** The Soft Step solver and the binding's `max_spring_torque`
  on ball and hinge joints are aimed at stiff joints that stay stable,
  which is what Sid asked of his own ragdoll. It is the one place Box3D
  might look better, and the only one that does not touch the tick.

## Recommendation

The original recommendation was to stay on Jolt for a whole-game
conversion: it would require changing every query and building the map's
collision for a v0.1 engine and a young binding, without evidence that it
improves movement or shooting. The units patch originally cited here is
unnecessary, as corrected above. Sid's 2026-09-26 request authorizes the
separate dropped-gun trial; it does not require those other systems to
move. Its baseline is the custom GDScript contact/impulse solver querying
Jolt in `DroppedItem`, not Jolt's native rigid-body solver.

Worth revisiting if any of these happen:

- box3d-godot, or another binding, ships as a `PhysicsServer3DExtension`,
  which makes a trial a one-line change in `project.godot` that
  `scripts/profile_dust2.gd` can measure against Jolt.
- Ragdolls on Jolt still spin or jitter after tuning. A Box3D world holding
  only the ragdolls and a static copy of the map is a contained trial; it
  would not touch the tick.
- Box3D reaches a stable release with its mover out of experimental.

## Local checks

The active dropped-gun trial needs settling and cost measurements on
synthetic floors and ramps, then drops on dust2 with the extracted weapon
hulls and a visual comparison to CS2. See [the trial notes](../box3d-trial.md).
The binding's demo also reruns its samples on Godot Physics, Jolt and
Box3D side by side, and its ragdoll sample remains useful if the scope
later expands to bodies.
