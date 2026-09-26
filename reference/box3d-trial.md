# Dropped-gun Box3D trial

Sid requested this trial on 2026-09-26 after dropped guns continued to
jitter, and chose to start with dropped guns. The branch is
`codex/box3d-dropped-guns`.

The comparison is against `DroppedItem`'s custom GDScript contact and
impulse solver, which uses Jolt's collision queries. It is not a comparison
against Jolt's native rigid-body solver. The shared `DroppedItem` path
covers guns, unthrown inventory grenades, the Zeus and defuse kits.
Movement, hit registration, live thrown grenades, C4 and ragdolls continue
using their existing paths. This experiment does not establish that
Box3D reproduces CS2 physics.

## Setup and switching

The extension is pinned to
[box3d-godot v0.4.3](https://github.com/Stink-O/box3d-godot/releases/tag/v0.4.3),
which requires Godot 4.7. From the trial checkout, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install_box3d.ps1
```

The installer downloads the release's `box3d-addon-v0.4.3.zip`, verifies
its pinned SHA-256, and installs `addons/box3d/`. Restart Godot after
installation. Binary libraries are ignored by Git; the installer makes
the dependency reproducible. The release includes Windows x86-64 debug
and release DLLs, Linux, Android and web libraries; macOS needs a source
build. Upstream describes the binding as experimental and says its
cross-compiled Windows binaries were untested by the author.

The trial branch defaults to `box3d`. Append one of these after Godot's
`--` separator to select the drop backend for a run:

```text
--drop-physics box3d
--drop-physics legacy
```

The `--drop-physics=box3d` form is accepted too. Requesting Box3D without
the addon fails explicitly; use the installer or select `legacy`.

## Simulation boundary

Box3D is a separate node-based GDExtension, not a selectable
`PhysicsServer3DExtension`. A `Box3DWorld` holds the native item bodies
and a static copy of the relevant map collision. All its bodies must be
descendants of that world. The mirror reads world-layer `StaticBody3D`
shapes: boxes, convex/concave hulls and tessellated spheres, capsules and
cylinders. An unsupported static shape fails explicitly. Changing the
range's cover panel with M or relocating it with N schedules an explicit
collision refresh outside the simulation tick. Other moving rigid bodies
are not mirrored into the native world. The adapter
converts Source inches to metres; Box3D's process-wide length setting
stays at its default of 1. Position, linear velocity and collider
dimensions cross that boundary; orientation
and angular velocity keep their existing conventions. The game's 800
inches/s² gravity is 20.32 m/s². Mass stays in kilograms, and an inertia
tensor converts by the square of the length scale.

The world uses `auto_step = false` and `async_step = false`. Each 64 Hz
game tick calls native `step(t.dt / 4)` four times. Each call has four
solver substeps, so contacts are refreshed four times during one game
interval rather than being reused for the whole interval. Each native
call completes its solve and writes the dynamic bodies' solved
`global_transform` before returning; the adapter reads the final pose
back to the game once per game tick. `sync_node_transform` stays enabled.
Rendering continues to interpolate the item's previous/current simulation
state; it must not drive the
native body's pose. The binding has no separate scripted interpolated
body-transform API. Restoring an item snapshot restores its pose and
velocities; it does not preserve the native solver's contact history or
establish deterministic rollback. These details are verified in the pinned
[world implementation](https://github.com/Stink-O/box3d-godot/blob/v0.4.3/godot/src/box3d_world.cpp)
and [body implementation](https://github.com/Stink-O/box3d-godot/blob/v0.4.3/godot/src/box3d_body.cpp).

The trial enables continuous collision on both the world and the item
bodies. Contact recycling distance is 0.005 metres: the default of 0.05
allowed deep penetration with the long AWP hull during the trial.
Contact stiffness remains the native default of 60 Hz, contact damping
10 and sleep threshold 0.05 m/s. No forced-sleep timer is used. The
additional native calls and shorter contact reuse need to be included in
the cost comparison; they are not evidence that the trial is already
accepted.

## API details checked for the adapter

- Guns use convex `HULL` colliders. `collision_mesh` must supply triangle
  faces: the binding takes their vertices and builds a convex hull.
  `MESH` contacts require a static body. An assigned Godot mesh has its
  winding reversed by the binding; raw `mesh_vertices`/`mesh_indices` are
  passed through without a winding change.
- `density` derives mass and inertia from shape volume. `set_mass_data`
  can instead preserve the extracted hull's mass, local centre and
  inertia; shape changes discard that override. `teleport` clears motion,
  so a restored moving item must receive its velocities afterward.
- `is_awake`, `set_awake`, `get_linear_velocity` and
  `get_angular_velocity` expose native motion and sleep. Sleeping should
  come from the solver rather than a timer that freezes a falling gun.
- Default friction mixing is the geometric mean; default restitution
  mixing is the maximum. `Box3DContactRules` supports pair-specific
  values keyed by `user_material_id`, allowing the legacy product of
  elasticities to be retained for a fairer solver comparison.
- Collision masks retain the existing drop behavior: items collide with
  the static world and pass through players and other dropped items.
- Queries return a dictionary containing `hit` even on a miss; do not
  test dictionary emptiness. Query positions/distances use the native
  world's units, normals and fractions do not need conversion. This
  trial leaves gameplay's Jolt queries in place.

See the pinned [body class documentation](https://github.com/Stink-O/box3d-godot/blob/v0.4.3/godot/doc_classes/Box3DBody.xml),
[world class documentation](https://github.com/Stink-O/box3d-godot/blob/v0.4.3/godot/doc_classes/Box3DWorld.xml)
and [contact rules](https://github.com/Stink-O/box3d-godot/blob/v0.4.3/godot/doc_classes/Box3DContactRules.xml).

## Checks and comparison

Run `scripts/profile_drops.gd` headlessly with each backend, a flat floor
and a 14-degree ramp, 36 drops and 640 ticks. For example, replacing the
Godot executable with its local path if it is not on PATH:

```powershell
godot --headless --path . --script scripts/profile_drops.gd -- --drop-physics legacy --slope 0 --count 36 --ticks 640
godot --headless --path . --script scripts/profile_drops.gd -- --drop-physics box3d --slope 0 --count 36 --ticks 640
godot --headless --path . --script scripts/profile_drops.gd -- --drop-physics legacy --slope 14 --count 36 --ticks 640
godot --headless --path . --script scripts/profile_drops.gd -- --drop-physics box3d --slope 14 --count 36 --ticks 640
```

With extracted dust2 assets, append `--map de_dust2` to either backend's
command to drop the guns at the map's T-spawn points instead of the
synthetic floor. The report separates `map_load_ms`,
`collision_setup_ms` and `gun_spawn_ms` from the per-tick measurements.
The deepest-corner measurement only applies to the synthetic plane;
on a map it is reported as null rather than an invented penetration result.

Record settling, residual motion, penetration and tick cost for both.
Synthetic results do not settle how the extracted weapons look: also
drop the long guns and pistols on dust2's T-spawn ramp, curbs and corners,
try pickups, and compare the landing/bounce with CS2. Check cleanup at a
new round and removal on pickup, plus unchanged movement and combat.

## Measured results, 2026-09-26

**Initial trial results: CPU cost was lower in these runs, but the
automated quality checks did not all pass.** Four AWP settling checks
failed, and the broader synthetic-ramp profile showed penetration and
continued motion. Dust2's sampled drops settled, which does not establish
that every surface or throw works. These measurements precede the
playtest follow-up below.

These are single headless runs on Windows with Godot 4.7.2 and an AMD
Ryzen 7 7800X3D. Each case uses seed `924043`, 36 guns (12 each of the
Glock, AK-47 and AWP) and 640 ticks at 64 Hz: ten simulated seconds.
The timed section is `GameSystems.step`, including pickup checks and the
adapter's four native calls. It excludes setup, rendering and the rest
of a match. These are not whole-match or GPU frame-rate measurements,
and single runs do not establish the size of run-to-run variation.

| Scene | Backend | Mean tick (µs) | p95 tick (µs) | First two seconds, mean tick (µs) |
|---|---|---:|---:|---:|
| Flat floor | Legacy | 420.369 | 1,892 | 1,306.570 |
| Flat floor | Box3D | 145.961 | 267 | 197.234 |
| 14° ramp | Legacy | 583.386 | 2,149 | 1,532.648 |
| 14° ramp | Box3D | 154.597 | 301 | 231.820 |
| Dust2 T spawns | Legacy | 615.453 | 2,291 | 1,586.508 |
| Dust2 T spawns | Box3D | 183.345 | 800 | 585.078 |

The native runs made 2,560 world-step calls and no legacy collision
queries. The legacy flat, ramp and dust2 runs made 14,524, 19,033 and
18,953 queries respectively.

| Scene | Legacy asleep | Box3D asleep | Lowest native hull corner during run | Largest native motion per tick in final second |
|---|---|---|---|---|
| Flat floor | 36/36 by 4.625 s | 25/36 at 10 s | −0.4705 in | 0.04846 in; 1.7463° |
| 14° ramp | 36/36 by 8.000 s | 30/36 at 10 s | −1.1364 in | 0.04654 in; 2.0097° |
| Dust2 T spawns | 36/36 by 8.000 s | 36/36 by 1.953 s | Not measured on map geometry | 0 in; 0° |

A negative hull-corner value is below the synthetic plane. Legacy's
corresponding minima were 0 in on the flat floor and approximately
−0.000086 in on the ramp. Legacy forcibly sleeps every drop after eight
seconds, so its ramp and dust2 sleep times do not prove natural settling.
Box3D has no such timer. The final-second motion values are the largest
single-tick changes over that second, not cumulative drift or a bound on
total travel; translation and rotation maxima can belong to different
guns or ticks. The profiler names these fields
`last_second_max_tick_translation_inches` and
`last_second_max_tick_rotation_degrees`.

On dust2, the native collision copy took **492.985 ms** for 34 static
shapes and 420,660 triangles; player clips are excluded. Map loading was
4.083 s for that native run and 4.158 s for the legacy run, measured
separately from native collision setup. Gun creation then took 4.119 ms
and 3.241 ms respectively. This setup cost is not included in the tick
table and must be considered when comparing startup time.

The local full test run reported **3,530 assertions: 3,526 passed and
four failed**. Across 36 suite files, 34 passed, the new Box3D drop suite
failed, and one draw-only suite skipped in headless mode. The failures
are AWP settling checks. Their throws and fixtures differ from the
profiler's seeded cases, so they should be reported alongside, rather
than replaced by, the profile's sleep and penetration results.

Both backends also completed a 180-frame headless dust2 Practice smoke
run with exit code 0; the native run captured the 34 shapes and 420,660
triangles reported above. This verifies startup and simulation, not
visual acceptance. The final focused range run passed all 84 checks,
including five new checks for refreshing the moving cover panel. The
final focused native run passed 46 of 50 checks, with the same four AWP
failures.

The raw profiler JSON is in the local ignored
`.godot/box3d-download/profile-{legacy|box3d}-{flat|ramp|dust2}.log` files;
the tables above preserve the results in the repository. The synthetic
logs were produced before the two motion fields gained `tick` in their
names; their values already measured per-tick changes.

## Playtest follow-up, 2026-09-26

Sid played the Box3D branch and reported that dropped guns feel much
better. He requested two follow-ups: release a gun in the orientation it
was held, and make shooting a gun on the ground push it. This is positive
playtest feedback; it does not replace the initial AWP failures or
synthetic-ramp penetration results above.

The release-orientation correction makes `HeldPose` return the weapon's
attachment-bone frame: its aim basis includes
`ItemPhysics.held_bone.basis`, while the measured hand position stays the
same. `drop_from` already removes that rest frame to recover the world
model's pose; previously it removed it from a model-space aim basis and
turned the barrel sideways. Tumble uses the resulting model-space
lateral axis. The yaw/pitch/crouch approximation remains; this does not
sample animated bones or change the first- or third-person pose systems.

Bullet impulses apply only to native drops whose `ItemDef.is_gun` is
true. Other dropped inventory items do not receive them. Hitscan still
uses the existing Jolt world/player trace and damage path. Each open
segment of that trace also queries the native gun hulls, applying an
impulse at each gun's actual contact point in the shot direction. The
segments stop at walls and players and resume only where the existing
trace successfully penetrates a wall, within the weapon's remaining
range. A gun hit does not alter the existing bullet damage/penetration
path. Each shotgun pellet adds its own impulse; an off-centre contact
also adds angular motion, and a sleeping gun and its view wake up.

`Box3DDrops.BULLET_IMPULSE_PER_DAMAGE` is **6 kg·inch/s per point of
remaining base damage at the contact**: weapon damage with range falloff
and the surviving penetration share, before player armour or hitgroup
multipliers. The adapter converts that impulse to kg·m/s for Box3D.
This strength is experimental, not a number extracted or verified from
CS2. `mp_shoot_dropped_grenades=false` controls shot detonation of dropped
grenades; it does not establish whether bullets should push guns. The
`legacy` drop backend retains its existing behavior and has no bullet
push; blast impulses remain outside this follow-up.

Both follow-ups are implemented. The new orientation suite passed
**41/41 checks** with local extracted models (39 failed before the fix).
It covers every gun, yaw/pitch and crouch combinations, the actual drop
command's release pose/tumble/velocity, and drawn Glock, AK-47 and AWP
poses. After the correction, simulation passed 156/156, contracts
257/257 and item physics 40/40.

The new bullet suite passed **25/25 checks**, covering a real Glock's
impulse and wake/view behavior, off-centre torque, additive pellets,
wall blocking, successful penetration, range, and excluded/removed
items. Existing penetration, shotgun and weapon suites passed 62/62,
104/104 and 198/198 respectively. The native quality suite remained
46/50, with the same four known AWP settling failures.

Human acceptance of the new release orientation and bullet push is
pending. The initial positive playtest preceded these changes. The
dated timings and full-suite counts above describe the initial trial;
the timing profiles contain no firing and do not measure bullet-query
cost. The branch remains an experiment while the existing settling and
penetration issues remain open.
