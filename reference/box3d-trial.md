# Box3D physics trial

**Status (2026-09-28).** Sid chose Box3D as the game's physics going forward;
this page keeps the trial's record. Two choices came with it:

- CI and the cloud threads build the Linux library from the release's pinned
  source (`scripts/install_box3d.sh`): the release's needs glibc 2.43 (libm's
  `GLIBC_2.43`, from its `.gnu.version_r`), and GitHub's ubuntu-latest, Ubuntu
  24.04, has 2.39. There it failed to load, a match's world never ticked, and
  every CI run on this branch hung until the job's limit. `scripts/run_tests.sh`
  now stops before the tests when Box3D does not load, and gives each file a
  time limit.
- The AWP's four settling checks in `tests/run_box3d_drop_checks.gd` are known
  open (`_check_known_open` in `tests/check_suite.gd`): run and printed every
  time, not failing the suite, until the AWP comes to rest. The thresholds are
  unchanged.

The [bridge and movement optimizations](research/box3d-performance-fixes-2026-09-26.md)
follow Sid's request to address the code bottleneck while leaving effects for
later. Their measurements supersede the performance figures below; the
6 ms maximum frame-time target remains open.

The earlier [full frame-time audit](research/frame-times-2026-09-26.md) follows the
full conversion: 4K ten-player p99 12.5–12.8 ms versus legacy 9.1 ms, with
3.47 ms/tick in proxy synchronization and 0.42 ms in the four-native-step
interval. These are different scopes; see the audit before comparing them.

Sid requested this trial on 2026-09-26 after dropped guns continued to
jitter, and chose to start with dropped guns. He subsequently requested
conversion of all game physics and a slight increase to the bullet kick;
the branch applies a 15% increase. The branch remains
`codex/box3d-dropped-guns`.

The dated dropped-item comparison below is against `DroppedItem`'s
custom GDScript contact and impulse solver, which uses Jolt's collision
queries. It is not a comparison
against Jolt's native rigid-body solver. The shared `DroppedItem` path
covers guns, unthrown inventory grenades, the Zeus and defuse kits. The
current branch also routes movement, combat, grenade and presentation
collision queries through Box3D, and builds ragdolls in the same native
world. Source movement and grenade-flight rules remain game code; this
experiment does not establish that Box3D reproduces CS2 physics. Current
conversion checks are recorded separately from the historical timings.

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

The trial branch defaults to `box3d` through
`csgodot/physics/backend`. Append one of these after Godot's `--`
separator to select the backend for a run:

```text
--physics box3d
--physics legacy
```

The `--physics=box3d` form and the old `--drop-physics` alias are accepted
too. Requesting Box3D without the addon fails explicitly. `legacy` is a
query/drop comparison path; converted ragdolls require the shared
Box3D world, so it is not a complete feature fallback. The Jolt project
setting supplies that comparison and unattached test spaces; it is not
the active game physics when the full native adapter is initialized.

## Simulation boundary

Box3D is a separate node-based GDExtension, not a selectable
`PhysicsServer3DExtension`. A `Box3DWorld` holds native items, ragdoll
bodies/joints, query representations of player hulls and hitboxes, and
map collision including player and grenade clips. All its bodies must
be descendants of that world. The mirror reads `StaticBody3D` shapes:
boxes, convex/concave hulls and tessellated spheres, capsules and
cylinders. An unsupported static shape fails explicitly. Original
static-body, character-body and hitbox RIDs are detached from Godot's
physics space while the adapter owns them; their nodes retain the
geometry, identity and shape names used by game code. Changing the
range's cover panel with M or relocating it with N schedules an explicit
collision refresh outside the simulation tick. Scene additions/removals
update the native representations, and player/hitbox poses synchronize
before queries. Ragdolls are created natively. The adapter
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
- Raw native queries return a dictionary containing `hit` even on a
  miss; do not test their dictionary emptiness. `PhysicsQueries`
  translates them to the game-facing empty-dictionary miss contract,
  converts positions/distances back to Source inches, and preserves the
  original collider, RID and shape index for damage/material lookup.
  Normals and fractions do not need length conversion. Game callers use
  this facade rather than calling Godot's direct-space queries themselves.

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
true. Other dropped inventory items do not receive them. At this stage,
hitscan used the existing Jolt world/player trace and damage path; the
later full conversion routes that trace through Box3D. Each open
segment of that trace also queries the native gun hulls, applying an
impulse at each gun's actual contact point. Its initial direction is the
shot direction; the grounded response below can redirect its component
into the supporting surface. Segments stop at walls and players and
resume only where the existing
trace successfully penetrates a wall, within the weapon's remaining
range. A gun hit does not alter the existing bullet damage/penetration
path. Each shotgun pellet adds its own impulse; an off-centre contact
also adds angular motion, and a sleeping gun and its view wake up.

The initial `Box3DDrops.BULLET_IMPULSE_PER_DAMAGE` was **6 kg·inch/s per point of
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

The initial bullet suite passed **25/25 checks**, covering a real Glock's
impulse and wake/view behavior, off-centre torque, additive pellets,
wall blocking, successful penetration, range, and excluded/removed
items. Existing penetration, shotgun and weapon suites passed 62/62,
104/104 and 198/198 respectively. The native quality suite remained
46/50, with the same four known AWP settling failures.

The dated timings and full-suite counts above describe the initial
trial; the timing profiles contain no firing and do not measure
bullet-query cost.

## Grounded bullet response follow-up, 2026-09-26

Sid's next playtest reported that shooting a gun on the ground did
nothing. A reproduction through `PlayerSim` and `UserCmd` confirmed a
hit and initial velocity, but the floor contact and friction absorbed
the downward kick: at roughly 58 degrees downward, the AK-47 moved only
0.0013 inches and the Glock 0.0029 inches after ten ticks. The earlier
25 passing bullet checks tested movement with horizontal shots and
missed this typical shooting angle. They did not establish that a
grounded gun would visibly move.

The follow-up changes the reaction for a gun supported by an actual
native contact. A supporting contact must have a normal with upward
component at least 0.5, a positive contact impulse and separation no
greater than 0.005 metres. If the shot's impulse points into that
surface, its normal component is reflected outward while its tangential
component and total impulse magnitude stay the same. The impulse still
acts at the bullet's actual gun contact point. Unsupported guns and
shots directed away from the support keep the original response. This
is an experimental gameplay reaction, not extracted or verified CS2
physics; the damage-scaled strength for these measurements was
6 kg·inch/s per point. The later 15% increase is recorded below.

The expanded native bullet suite passed **38/38 checks**, including
grounded kick and movement on a flat floor and a 20-degree ramp; four
checks failed before the fix. The player-path suite passed **36/36**
(eight failed before), using actual drop and attack commands against
Glock and AK-47 drops at 30, 60 and 85 degrees downward and checking
that the drawn gun moves with the body.
A combined run passed **438 checks across five suites**: those two plus
penetration (62), shotgun (104) and weapon (198).

At 60 degrees downward, centre-of-mass displacement after ten ticks
changed from **0.0012 to 2.1997 inches for the AK-47**, and from
**0.0034 to 4.8282 inches for the Glock**. These are fixed headless
reproductions through the player command path, not measurements of CS2
or human acceptance of the resulting reaction.

One bounded contact limitation remains: v0.4.3's `get_contacts()` flattens
all manifolds for one collider into a point list with only the last
manifold's normal. In a diagnostic combining floor and wall in one
concave mesh, a Glock against the wall received only the wall normal,
so the grounded redirection did not apply and motion was 0.36 inches.
A six-inch curb case redirected correctly and moved 3.40 inches. Open
floors and ramps pass the checks above; mixed floor/wall contacts still
need a per-manifold support solution.

Sid subsequently confirmed that shooting grounded guns was working and
requested a slightly stronger reaction, followed by the full conversion
below. The branch remains an experiment; the four known AWP settling
failures and synthetic-ramp penetration remain open.

## Full game conversion, 2026-09-26

At Sid's request, the shared world now owns the game's collision and
rigid-body simulation. `GameWorld` initializes the full adapter before
automatic ticks. `PhysicsQueries` routes rays, sweeps and overlaps to
it, including hitscan/penetration, player movement and hitboxes, live
grenades, smoke/fire/flash visibility, bot sight, footsteps, muzzle-light
placement and the spectator camera. An unattached test space retains
Godot queries for comparison. Test counters distinguish native queries
from that fallback.

The port preserves original collider/RID/shape-index identities, area
flags, masks and exclusions. For solid shapes, a ray starting inside
with `hit_from_inside=false` skips its containing body, as penetration's
exit search requires. With the flag true it reports the origin with a
zero normal, as smoke expansion requires. Concave meshes remain hollow.
The result of a native sweep supplies the immediately following
`get_rest_info` contact. Native casts stop about 0.005 m (0.197 inches)
off a surface; an additional 0.06-inch normal clearance avoids an
outgoing grenade or sliding player starting inside the native contact
band. Player recovery is bounded to 0.5 inches. These tolerances differ
from the original engine's and need playtesting on real map edges.

Raw `collide_shape` contact pairs are legacy-only: v0.4.3's overlap API
does not expose an equivalent manifold. Native dropped bodies use
Box3D's solver; the gun-release overlap check uses `intersect_shape`.
Unsupported raw contact-pair requests fail explicitly rather than
inventing contacts.

Ragdolls use native capsule bodies, ball/hinge joints and filter joints,
stepped by the shared world's pre/post tick hooks. The binding's ball
joint has a circular swing cone, so the previous independent-axis 6DOF
limits are represented conservatively with an offset cone; they are not
an exact joint-model conversion. The Source movement and grenade
ballistics algorithms keep their existing rules over native queries.

The current bullet coefficient is **6.9 kg·inch/s per point of remaining
base damage**, 15% above 6.0, chosen for Sid's request for a slight
increase. The support reflection and coefficient remain experimental
gameplay tuning, not extracted CS2 physics. Earlier
kick displacements above used 6.0 and are not new measurements at 6.9.

Final conversion checks:

- Native combat/grenade/drop-placement integration: **43/43**, with
  native-query counters and no fallback calls; exit 0 and empty stderr.
  This includes head damage, box and mesh penetration/materials, flash
  and smoke visibility (including starts inside a wall), grenade rebounds
  and clip masks, fire ground placement, and releasing a long gun beside
  a wall.
- Native world/hitbox lifecycle: **20/20**, including detachment of the
  original Godot bodies, fixed-pose shape changes and native cleanup.
- Native movement: **22/22** focused checks; the movement course passes
  **80/80 on each backend**. Standing and crouch jump heights are 59.37
  and 77.37 inches respectively on both.
- Native ragdolls: **67/67**, including one-sided floor rays, flat/ramp/curb
  landings, anatomical limits, collision exclusions, tick ownership, mass
  and unit conversion, cleanup, and the extracted agent's actual shapes.

The AWP follow-up retained the same 50 drop assertions. Body sleep
thresholds of 0.075, 0.1 and 0.2 m/s all left the same four failures.
An isolated `contact_recycling=false` body experiment reduced final
floor/ramp drift from 0.843/0.459 inches to 0.032/0.044 inches, but still
failed the settling checks. Neither experiment changed production
settings or relaxed assertions; no forced-sleep timer was added.

The real Dust2 Competitive integration passes **10/10**: nine bots move,
22 shots are fired, the inventory drop/HE/death-ragdoll paths execute,
59,945 native queries run with no legacy queries, and Godot's server has
no active bodies or attached map/player collision objects. The physical
floor check samples actual collision rather than nav-polygon heights,
which can bridge small stairs and ledges.

The bot regression exposed overlap recovery discarded by the ground
probe. The native path now preserves that correction separately from
the probe's intentional travel. Recovery candidates use current player
positions, not unsaved history across ticks. The original head-on budget
passes at 4.23 hull traces per bot/tick (4.03 alone, 4.34 control); no
budget assertion was relaxed. Dust2's minute-long route check also passes.
Depenetration is carried separately from commanded travel, so a correction
larger than a low-speed move cannot consume slide time or reverse the
remaining motion. A controlled corner regression exercises that case.

### Full-world CPU comparison

Measured on the same Windows Ryzen 7 7800X3D with Godot 4.7.2, using
`scripts/profile_box3d_match.gd`, one otherwise idle process per backend:

```text
godot --headless --path . --script scripts/profile_box3d_match.gd -- --physics box3d
godot --headless --path . --script scripts/profile_box3d_match.gd -- --physics legacy
```

Both use seed 20260926, 96 warmup ticks, ten immortal players, and a
768-tick schedule with map routes, an AK drop, an HE throw and a staged
bot engagement. Each run fired 22 shots and ended with ten living players.
Ragdolls are omitted from the paired comparison because the converted
ragdoll path requires Box3D; the integration check above covers a death.

| Backend | Mean tick | p95 | Maximum | Mean hull traces/tick |
|---|---:|---:|---:|---:|
| Full Box3D port | 7.091 ms | 8.787 ms | 11.710 ms | 55.31 |
| Legacy queries/drops | 3.296 ms | 4.105 ms | 5.379 ms | 51.77 |

This times `GameWorld.step`: command generation, player simulation,
gameplay systems, and native stepping. Animation posing, rendering,
audio/UI callbacks, map setup and Godot's automatic physics-server step
are outside the interval. Native made 59,239 facade queries and zero
legacy calls; legacy made 16,229 facade queries, with its CharacterBody
motion queries counted separately as hull traces. Different engine
contacts produce different trace counts and routes despite the same
schedule. These are CPU timings, not frame-rate measurements or a
like-for-like comparison of native rigid-body solvers.

The initial unoptimized full port averaged 15.114 ms per tick. Separating
hull/hitbox synchronization, skipping unchanged query proxies, using a
nearest-hit ray fast path, and preserving overlap recovery reduced that
cost. The final port still costs about **2.15 times** the legacy path in
this workload; improved gun feel does not establish a full-game speedup.
A diagnostic run attributes 3.641 ms per tick to query-proxy
synchronization, while native cast wrappers take 0.591 ms. Much of the
remaining cost is this scripted integration, not evidence that the native
solver itself is inherently slower than Jolt.

The final local full run and targeted reruns cover **3,750 assertions:
3,746 passed and four known AWP settling checks failed**. Of 43 suite
files, 41 pass, the drop-quality suite fails, and the draw-only suite
skips headless. The final low-speed recovery correction was followed by
146 passing checks across native movement, bot movement, real Dust2
match/routes and the Source movement course. No script/parse errors were
reported; existing headless-render and shutdown resource warnings remain.

Ragdoll visual acceptance and human acceptance of the combined conversion
remain open, as do the four AWP failures. Keep the PR a draft for this
performance/quality comparison.
