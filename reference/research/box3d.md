# Box3D: what it would mean for the game

Sid asked (2026-09-24) what Box3D, and the box3d-godot binding for it, would
mean for us. This is an evaluation, not a plan. **Recommendation: stay on
Jolt.** Nothing here changes the roadmap.

## Sources

- `erincatto/box3d` at `8fda30e` (2026-09-24), tag v0.1.0, MIT. Its README,
  `docs/faq.md` (determinism), `docs/character.md` (the mover) and
  `include/box3d/box3d.h`, `constants.h`. **Primary.**
- `Stink-O/box3d-godot` at `87c5ac9` (2026-09-20), release v0.4.3, MIT.
  Its README, `godot/README.md` and `godot/src/`. **Primary.**
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
  `Box3DCollisionShape`, nine joints, `Box3DCharacter`) and runs its own
  world beside Godot's. **It is not a physics server.** Nothing in
  `godot/src/` extends `PhysicsServer3DExtension`, so it cannot be picked in
  `3d/physics_engine` the way Jolt is. `get_world_3d().direct_space_state`,
  `move_and_collide`, `Area3D`, `RigidBody3D` and the `Joint3D`s keep using
  Jolt whatever else is loaded.
- Queries are methods on `Box3DWorld`: `raycast`, `raycast_all`,
  `shape_cast_box`, `shape_cast_capsule`, `shape_cast_sphere`,
  `shape_cast_convex` and overlaps. A box cast exists, which our hull would
  need.
- It works in meters. Box3D can be told another length unit
  (`b3SetLengthUnitsPerMeter`, which scales its slop and margins), but the
  binding does not expose it; our world is in inches, and project.godot
  already rescales five of Jolt's tolerances for that.
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
4. **Units patched** into the binding, or every tolerance off by 39 times.
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

Stay on Jolt. The swap costs a rewrite of every query, a second copy of
every map's collision and a units patch to a v0.1 engine and a young
binding, to gain nothing in how movement and shooting feel, and a
determinism the game does not need.

Worth revisiting if any of these happen:

- box3d-godot, or another binding, ships as a `PhysicsServer3DExtension`,
  which makes a trial a one-line change in `project.godot` that
  `scripts/profile_dust2.gd` can measure against Jolt.
- Ragdolls on Jolt still spin or jitter after tuning. A Box3D world holding
  only the ragdolls and a static copy of the map is a contained trial; it
  would not touch the tick.
- Box3D reaches a stable release with its mover out of experimental.

## Local checks

None needed for this decision. If Sid wants a number anyway: the binding's
demo reruns its samples on Godot Physics, Jolt and Box3D side by side, and
its "ragdoll" sample shows the joint behaviour on his machine.
