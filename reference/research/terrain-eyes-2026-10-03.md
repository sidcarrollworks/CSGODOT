# CS2 ground-topology eye sampler — October 3, 2026

This completes the sampler selection and weighting details left open in the
[camera-height audit](camera-height-2026-10-03.md). It describes recovered
server behavior and the resulting gameplay port. It does not establish a
recorded CS2 trajectory match. One simulation eye offset now supplies rendering,
weapon origins and grenade snapshots; rendering interpolation remains separate.

## Evidence and scope

The installed server is build **2000924**, patch **1.41.8.8**, SourceRevision
**11076591**, built October 2, 2026 at 14:45:21. Its SHA-256 is
`098d4ddd57e2fbe9a73623a2bf68ebaff86f7b6342ddb3d5a0f69cd6335b31cc`.

Ghidra 12.1.4 exported the existing project read-only. The eight initial
contiguous spans for this pass match the installed server byte for byte:
`180a6cb30`, `180a69a60`, `180a73ad0`, `180a77f20`, `1802bcdd0`,
`1801519e0`, `18018a110` and `1800caa30`. Ten additional supporting spans
also match: `1800caba0`, `1800cb050`, `1801051e0`, `18014f3e0`,
`180154920`, `180154a40`, `180c28520`, `180caaee0`, `180e75570` and
`1814a0920`. Thus **18 distinct spans** were checked for this follow-up.
The first main span includes three bytes between function body ranges;
the complete exported span, including those bytes, matches.

Current RTTI/vtable entries and constants were independently read from the
installed PE. No Valve DLL was executed, and no debugger was attached.
Valve binaries, Ghidra projects, exports and scratch helpers stay uncommitted.

## Eligibility and caches

Sampler `180a6cb30` first resolves the pawn's entity handle at `+0x3ec`:
pawn slot `0x660` reaches thunk `18014f3e0`, then slot `0x668`, currently
`180e75570`. The resolved entity's slot `0x570` must return true. The
current `CWorld` vtable at `181958658` reaches `180caaee0`, which returns
one; the ordinary pawn implementation `180154a40` returns zero. The
algorithm therefore explicitly requires a world support entity, rather
than accepting every grounded dynamic body.

Only after that eligibility gate does it compare the cached pawn position:
each coordinate is `floor(float32(origin * 100)) / 100`. An unchanged
quantized position reuses the previous result. Leaving world support returns
false before this cache check; returning to the same position can reuse the
stored result. These early returns do not erase the previous position or
height result.

A separate cache stores successful sample heights by integer sample XY.
It clears when its entry count exceeds **512**. A cached height is accepted
only inside the current acceptance box: pawn XY plus **-24 to +24**, and
pawn Z plus **-2 * step height to step height + 1**. The relative box is
initialized on first use from the step height then in effect. Failed samples
are not inserted. This cache has no scene-revision key in the recovered
routine; a port must define invalidation for scene changes and teleports.

## Samples and collision acceptance

All coordinates below use Source's XY ground plane and Z vertical axis.
`sv_stepsize` defaults to **18**, confirmed by registration `1801051e0`.
The ordinary grid is **5 by 5**, at **8-unit** spacing.

For each quantized horizontal coordinate `q`, the first grid coordinate is:

```text
start = int(q - fmod(q, 8) - 16 - 4)
if q > 0:
    start += 8
```

The conversion truncates toward zero. In particular, the positive/negative
and exact-zero boundaries should not be replaced with a floor-based grid
formula. X is the outer loop; Y is the inner loop. A cell's index is
`x_index * 5 + y_index`.

`180a69a60` sweeps an axis-aligned box with XY half extents **3.99** and
**exactly zero vertical extent** downward. Its start is
`(grid_x, grid_y, pawn_z + 2 * step_height)` and its end is
`(grid_x, grid_y, pawn_z - 2 * step_height)`. It floors every start/end
coordinate to an integer before submitting the sweep.

The trace filter's raw mask is **`0x2011`**, collision-group byte **`0x0b`**,
invalid ignored-entity handles, and initialized flag byte
`(old_flags & 0xc9) | 0x49`. This report does not equate those Source 2
layer bits with Godot collision layers. The port must select its equivalent
world/support collision geometry explicitly.

A sample is valid only if the trace reports a hit, is not start-solid, and
its contact normal Z is **strictly greater** than `sv_standable_normal`.
Registration `1800caba0` confirms the default is float32 **0.7**
(`1817aa364`); equality fails. Valid contact height is quantized as
`floor(float32(hit_end_z * 10)) / 10`. The query's return value is not a
success indicator for new traces: it returns zero even when it writes a
valid output. The caller checks the output against the maximum-float
sentinel instead.

Each sample's area is the XY intersection of its conceptual **8 by 8**
cell (`grid center +/- 4`) with the pawn's **32 by 32** footprint
(`quantized pawn center +/- 16`). `180a77f20` computes this rectangle
intersection exactly. Zero-area cells are omitted. The collision box's
3.99 half extent and the area cell's 4-unit half extent serve different
purposes and should stay distinct.

## Discontinuity selection and height weighting

If there are no accepted samples, or if
`pawn_z - maximum_sample_z >= step_height`, the height difference is zero.
Otherwise, if the accepted samples span less than one step height, all
samples proceed directly to the weighted average.

At a height span of **at least one step**, it selects the sample with the
minimum three-dimensional squared distance to the quantized pawn position:
`(x-qx)^2 + (y-qy)^2 + (height-qz)^2`. Strict comparisons preserve the first
sample in X-outer/Y-inner order on a tie.

The selected seed has depth zero and connectivity weight
`max(seed.area / 64, 0.01)`. The routine repeatedly scans samples in storage
order and floods previously unvisited adjacent cells. Neighbor order is
**-1, -5, +1, +5**. It prevents crossing a row boundary for -1 when
`index % 5 == 0`, and for +1 when `(index + 1) % 5 == 0`; -5 requires
`index >= 5`, and +5 requires `index < 20`.

A neighbor is connected only when the absolute height difference is
**strictly less** than the step height. Its depth is the current depth plus
one, and its connectivity weight is:

```text
min(current.connectivity_weight,
    max(min(current.area, neighbor.area) / 64, 0.01))
```

Visited samples are not revisited to search for a better route. The scan
repeats until no additional neighbor is connected, and removes every
unreachable sample. This is ordered flood selection, not simply choosing
all samples nearest the pawn's height.

For each retained sample, `1801e1580` performs a clamped linear remap.
The two height-remap factors and final accumulation are:

```text
upper = remap_clamped(height, qz + step, qz + 2*step, 1, 0)
lower = remap_clamped(height, qz - step, qz - 2*step, 1, 0)
weight = (upper * lower)^2 * area
if discontinuity_flood_added_any_neighbor:
    weight *= connectivity_weight

mean_height = sum(weight * height) / sum(weight)
drop = clamp(qz - mean_height, 0, 24)
```

A zero total weight gives zero drop. The **24-unit** clamp belongs to this
active sampler; old slope-drop convar defaults do not override it.
Getter `180a73ad0` returns the stored drop, converting the maximum-float
sentinel to zero.

## Assembly and remaining boundaries

The existing [camera-height audit](camera-height-2026-10-03.md) establishes
that movement finish assembles this result with duck root/view adjustments
before grenade snapshot capture. When topology use changes, the residual
starts at the previous root offset minus the new target. The current
grounded constant at `1817afa10` is **150 units/s**; an alternative branch
uses `max(abs(movement_service[0x700]), 60)`. Airborne decay uses
`max(abs(vertical_velocity) * 0.5, gravity * 0.05)`. The final root offset
is clamped to **-32 to +32**.

The final view height's `(value + 196608) - 196608` expression must execute
as float32 operations. At ordinary eye values its increment is **1/64**;
using a double-precision expression would lose this rounding. The view
setter then clamps through the registered quantized-float bounds. Base
standing/crouched definitions remain **64/46**.

The paired CS2 eye heights **60.75** at mid doors and **63.9375** at the
B-doors reference remain external comparison targets, not constants to
hard-code into the sampler. The sampler, collision acceptance and topology
transitions are now recovered and implemented for ordinary fixed-world
support. Collision-backend edge behavior, complete duck/root transitions,
other movement modes and matching CS2 launch/contact trajectories still
require separate implementation and validation.

## Port and validation

`GroundEyes` finishes each collision segment once, after either movement
backend and before `PlayerSim._movement_finished` captures grenade parameters.
Source X/Y map to Godot Z/X, so the port stores cells with Godot Z outer
and X inner to preserve tied-seed and ordered-flood selection.
Its getter is a pure read, including for threaded bot thinking. The camera
and spectator view interpolate previous/current eye heights with the same
fraction as pawn position; subtick gun/knife origins do likewise. Presentation
jump dip remains separate. The current duck spline still supplies the 64/46
base blend: complete Source duck/root rates and its alternate grounded
transition branch are not claimed here.

Actual support ownership comes from existing grounding/step/quadrant traces
and is held bit-identical in script/native movement. Players and animatable
supports do not enable terrain sampling. The sample mask is explicitly
`body.collision_mask & (WORLD_LAYER | PLAYER_CLIP_LAYER)`, excluding pawn,
hitbox, sky and grenade-only layers. Non-fixed hit entities are rejected
before caching. This is the project's fixed-map mapping, not a decoded
equivalence for every Source entity-filter bit. Looking through moving
obstructions authored on world layers remains outside the comparison port.

`TerrainTrace` uses Box3D's existing projectile-box query with zero vertical
extent and **0.001-inch** linear slop, returning the square center at contact
without player/grenade clearance. This slop is a backend tolerance, not a
Valve constant. Smaller tolerances produced invalid normals at distant map
coordinates. The dedicated origin/20-degree solid and triangle fixtures
agree geometrically within 0.002 units; additional distant raised solids
show errors up to 0.0026 units before tenth-unit height quantization. The legacy
comparison uses a 0.002-high thin box; it is an approximation, not an exact
Source collision backend.
Positions, sampled heights and final view rounding explicitly pass through
float32; scalar weighting uses GDScript arithmetic. The port is not claimed
to reproduce every intermediate Source floating-point result bit for bit.

Spawn, revival, teleport through `place()` and noclip transitions clear
terrain/root state and interpolation history. Configuration changes clear
the cache. The current captured map is fixed; future live geometry edits
must explicitly reset eyes or add scene-revision invalidation. Successful
height caching, including reuse after airborne motion, follows the audit;
failed cells deliberately remain uncached. Query totals are monotonic across
state resets and included in `PlayerBody.traces` and `PhysicsQueries` counters.

The paired collision-only Dust2 fixture settles with Box3D's existing hull
clearance, so the comparison is **absolute camera height**, not a hardcoded
relative offset:

| Reference | CS2 camera Y | Port camera Y | Difference |
|---|---:|---:|---:|
| Mid-door | 150.364380 | 150.328514 | -0.035866 |
| B-doors | 192.014847 | 191.999344 | -0.015503 |

Neither point has a lineup-specific correction. Tests allow 0.08 units for
collision/height quantization differences. Standing takeoff clears the
topology residual before the 100-ms grenade snapshot in all three local
lineup fixtures, preserving the airborne 64-unit eye. Xbox, exact-coordinate
mid-door and B-doors pass **246 checks**, with **12,339 movement segments**
matching script/native bit for bit. These fixtures establish local landing
and shared-input regressions, not recorded CS2 flight/contact parity.

The dedicated terrain suite passes **79 checks** and **440 bit-identical
movement segments**, covering analytic/physical slopes, discontinuities,
thin support, cache bounds, float32 view rounding, boost/platform gating,
neighbor exclusion, Source-ordered tied support selection and takeoff/landing.
Existing movement-query budgets
remain unchanged: terrain casts are reported separately when checking those
budgets, while the total profiler count retains both.

The final local `scripts/run_tests.sh` run passes **7,887 checks across
81 files**, with rebuilt debug/release native movement and extracted assets.
Three draw-only suites skip in headless mode; the four existing AWP drop
settling cases remain reported as known open. No new failing check remains.

## Performance

Measured locally with Godot 4.7.2, the rebuilt native mover, patched Box3D
and extracted Dust2 collision (39 shapes / 435,649 triangles). Timing runs
were sequential, after the Godot tests finished. Native
and script comparison execution was disabled for profiling.

The seeded ten-player fixture uses 96 warmup and 768 measured ticks, with
the same routes, drop, HE throw and staged engagement as
`profile_box3d_match.gd`. The control substitutes a no-op terrain update
after warmup on this same branch; it is not a stock-main benchmark.
`GameWorld.step()` is the timed boundary, including commands, movement and
gameplay; animation fitting, rendering, audio/UI and Godot's automatic
physics-server step are excluded. Query/endpoint instrumentation runs
outside that boundary.

| Sequential run | Mean tick, ms | P95 tick, ms |
|---|---:|---:|
| Active terrain, first | 2.563 | 3.405 |
| Disabled terrain, first | 1.915 | 2.531 |
| Disabled terrain, reversed | 1.930 | 2.547 |
| Active terrain, reversed | 2.668 | 3.606 |

The mean of the active means is **2.6155 ms**, against **1.9225 ms** for
the controls: **+0.693 ms** (about 36%). This is a measured feature cost,
not a claim of no regression. Each active run added **17,846 terrain
casts**, averaging **23.24 per ten-player tick**, maximum **76**. All four
runs had **22 shots**, ten living players, native movement, zero legacy
queries and identical final player positions/velocities. The latter does
not by itself prove every intermediate gameplay event was identical.

The recovered grid explains the added collision work; successful height
caching eliminates idle casts and reuses cells while walking, but failed
cells are retried whenever quantized position changes. There is at most
one 25-cell sample grid per movement segment, so a subdivided command can
sample more than once in a tick. Negative-caching failures would change
the audited behavior and is not introduced here. A native sampler/math
port is a candidate for a separately measured optimization. Rendered-frame
acceptance and the overall 6-ms maximum target remain open.

Collision-only one-body measurements used 256 ticks per route and eight
alternating active/control repetitions; every paired movement endpoint and
velocity matched bit for bit. These exclude animation and gameplay:

| Route | Active simulation mean, ms | Disabled mean, ms | Terrain casts / 256 ticks |
|---|---:|---:|---:|
| Stationary flat | 0.022645 | 0.022211 | 0 |
| Mid-door slope / descending path | 0.131245 | 0.039150 | 1,013 |
| B-doors mostly flat | 0.103958 | 0.035982 | 648 |
| B-doors pressed against wall | 0.222952 | 0.062932 | 1,476 |
| Diagonal T-spawn walk | 0.102478 | 0.034654 | 857 |
| Off Xbox ledge, then walking | 0.125706 | 0.059265 | 645 |
| Short roof walk, then blocked | 0.060199 | 0.052672 | 112 |

The wall fixture moves only about 13 units, retrying five cells on 207 ticks
and nine on 49 ticks. It is an explicit failed-cell stress case. Timing
`GroundEyes.update()` alone gives 0.299–0.560 ms means for cold 25-cast grids,
1.17–2.04 microseconds at cached stationary positions, about 21–31
microseconds for moving reweighting with all heights cached, and about 1.71
microseconds airborne without casts. Warm means include different map sites;
they are not rendered-frame measurements. Local one-body helpers/logs are
retained under ignored `.godot/terrain-eye-probe/`; only the reusable
ten-player comparison is committed.

Repeat the ten-player comparison in separate processes, then reverse order:

```sh
godot --headless --path . --script scripts/profile_ground_eyes.gd -- --physics box3d --movement native
godot --headless --path . --script scripts/profile_ground_eyes.gd -- --physics box3d --movement native --without-terrain
```
