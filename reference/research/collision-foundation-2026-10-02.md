# Collision foundation before the grenade port — October 2, 2026

**Implementation follow-up:** [grenade port, October 2](grenade-port-2026-10-02.md)
now supplies the dedicated contact contract and core throw/flight/activation
rules. This page retains the audit-time implementation gaps and measurements;
the follow-up records what was ported and what still needs local comparison.

Roadmap **20a**, following the [grenade audit](grenade-audit-2026-10-02.md).
The shared world does not need replacing before the grenade port. It needs
a projectile trace contract that handles small hulls and contact tolerances
explicitly. The player already has its own recovery and clearance rules;
native drops and ragdolls are another path. Changing solver iterations or
the global tick would not correct the grenade's custom flight.

This pass fixes two narrow problems in the current grenade path: subsequent
bounces share the time remaining in the step, and a sweep reads contact and
fractions together. CS2's launch box, flight box, release scheduling, jump
snapshot, substeps and full bounce rules remain to be ported. The small-hull
fixtures characterize the current backend; they do **not** certify CS2 parity.

## What shares the world, and what shares a solver

| Path | Collision | Integration/response | Consequence |
|---|---|---|---|
| Player | Box3D query adapter, inset box sweeps, clearance offsets and overlap recovery | Source movement in script and its matching native implementation | Keep the existing movement contract while adding projectile traces |
| Grenade | Box3D query adapter, currently whole radius-two spheres | `GrenadeFlight`, currently one midpoint-gravity step per 64 Hz tick | Solver settings on native rigid bodies do not change this arc or bounce |
| Dropped item/ragdoll | Native bodies in the same Box3D world, metre-scaled at the boundary | Box3D rigid-body solver and native contacts | Audit these separately if measured drops or ragdolls misbehave |

All public queries use Source inches and original Godot collider identities.
The native boundary uses 0.0254 metres per unit. The importer supplies world
triangles and player-only clips; it currently discards `grenadeclip` geometry.
The grenade mask already includes layer 32, so enabling that layer in a query
does not recover the missing map shapes. There is no evidence here that the
unit conversion, world's gravity or rigid-body material solver is a common
cause of the grenade differences.

## Ghidra: the trace underneath fly physics

Read-only Ghidra 12.1.4 follow-up over the hash-matched server project from
the grenade audit. The installed server was rehashed for this pass:
`3541e46a3193fcf1151e97ce19cd4daf86c5fdb2889033c2bab1d4cc7f555b9c`.
Patch 1.41.8.8, server 2000922, SourceRevision 11064488, image base
`0x180000000`. Labels below describe recovered behavior, not original symbols.
No Valve DLL was executed or game process attached.

| Server VA | Recovered behavior and port implication |
|---|---|
| `180e88aa0` | Pushes the entity from origin to origin + motion, builds the entity filter, calls the entity-hull trace, moves to the trace's end when fraction is nonzero, then dispatches touches when there is a hit entity. The engine trace's end and fraction travel together. |
| `180c27940` | Derives trace geometry from the entity's collision properties and calls the shared trace wrapper. It is not a universal sphere cast. |
| `180bd6d50` | Constructs a filter from the entity and its collision properties. Owner/group filtering is richer than permanently excluding one RID. Exact owner recontact policy remains open. |
| `180c28520` | Initializes start/end, then queries the engine collision interface through slots `+0x558` or `+0x560`; the latter collects and filters candidates. Converts the accepted engine result to the gameplay trace. |
| `180be76a0` | Computes the gameplay end as start + motion × engine fraction. Copies fraction at gameplay trace `+0xac`, normal at `+0x90`, the engine solid-state byte to `+0xbb`, shape/hit metadata, and resolves the hit entity. |
| `1814a0920` | Initializes the gameplay trace with fraction 1 and clears solid/result flags. |
| `180e89790` | Integrates and pushes fly-gravity motion. The solid-state byte at trace `+0xbb` stops linear and angular velocity; otherwise a partial trace dispatches collision response. This is distinct from merely lacking a normal. |
| `180e86890` | Response mode 2 dispatches entity virtual slot `+0x518`, the grenade collision callback recovered as `1809c7ad0`. Mode 1 uses `180e8c720`, a different generic response. Do not port the generic bounce routine as the grenade's. |
| `180e887a0` | Dispatches entity touch/impact callbacks with the trace, rather than solving native rigid-body restitution. |

The installed engine's inner trace tolerance is **not** established by these
server wrappers. A Box3D zero-normal hit is not proof of CS2's solid-state
flag, and safe/unsafe fractions are not interchangeable with that flag.
The previous audit supplies the launch/flight sizes, gravity, 1/128 s stepping
and custom grenade response. This pass establishes the caller contract
underneath them without claiming to have recovered the whole engine solver.

## Why the small-box port needs care

The pinned Box3D addon is v0.4.3, commit
`3ce52ff999f2509a89ec53538ff77c3cf35092fa`. Its
[cast implementation](https://github.com/Stink-O/box3d-godot/blob/3ce52ff999f2509a89ec53538ff77c3cf35092fa/src/distance.c)
sets the target separation to `max(linearSlop, totalRadius - linearSlop)`
and the initial-hit tolerance to one quarter of the slop. The
[slop constant](https://github.com/Stink-O/box3d-godot/blob/3ce52ff999f2509a89ec53538ff77c3cf35092fa/include/box3d/constants.h)
is 0.005 metres at the default length scale: **0.19685 Source units**.
An initial hit returns fraction zero with no normal. The
[world cast](https://github.com/Stink-O/box3d-godot/blob/3ce52ff999f2509a89ec53538ff77c3cf35092fa/src/physics_world.c)
disables `canEncroach`; that option alone would not provide a general
start-solid/depenetration result anyway.

Local probes on solid boxes and triangle floors confirmed the previously
documented [walking-hitch findings](box3d-walking-hitch-2026-09-28.md), now
with grenade-sized hulls. Start the shape center at y=3 over a floor at y=0,
use a radius-two sphere or four-inch box, and move down two inches:

| Shape | Native hit fraction | Native center at hit | General query center after its 0.06 clearance |
|---|---:|---:|---:|
| Four-inch box | 0.401575 | 2.19685 | 2.25685 |
| Radius-two sphere | 0.598425 | 1.80315 | 1.86315 |

Physical contact would put either center at y=2 and fraction 0.5. For a box
starting at y=2.2, a downward trace reports fraction zero and no normal even
though it is physically clear. At shallow angles, the general query can
spend all of a short motion on clearance. Triangle broad-phase bounds can
also omit a nearby surface that the actual swept shape never reaches, as
documented in the movement audit.

The player contract handles this with inset/reach, capped back-off and a
normal offset consumed by its mover. Substituting that result into a caller
which only consumes fractions would lose the offset. Substituting a box
into the existing sphere caller without handling initial contact would
create zero-normal bounces or sticking. Conversely, reducing global slop
changes rigid-body contact behavior as well as queries; that is not a
measured remedy here.

The added fixtures check both box and triangle floors, small-hull tolerances,
shallow approaches, original material-shape identity, RID exclusion and its
restoration. Existing suites cover player recovery, stairs/slopes, dynamic
proxy synchronization, body masks, grenade-only/player-only clips, drops
and native/script movement equivalence.

## The contained fixes

`GrenadeFlight.step` previously formed each post-bounce motion with
`velocity * dt * (1 - fraction)`. At the second hit that grants a fraction
of the **whole** step again. It now reduces a remaining-time accumulator.
Gravity, sphere geometry, clearance and bounce velocity response retain
their existing rules pending the parity port.

The regression uses corridor faces at x=10 and x=-4, a grenade at x=0 moving
at 1,000 u/s, and a 40 ms step. Two wall hits retain speeds 450 and 202.5 u/s.
Distance/speed between the observed impact locations independently measures
elapsed time, allowing for each 0.01-inch departure push. Before: final
x=0.17502, expected -0.29323. After: x=-0.29323. This tests the shared step
budget rather than assuming exact backend contact geometry.

`GrenadeFlight._sweep` now asks `PhysicsQueries.shape_cast` for fractions,
normal and original collider together. It previously cast, then asked for
rest info at the unsafe endpoint, relying on the bridge's last-cast cache.
On Box3D this removes one adapter query per contacting sweep; it does not
claim that every removed rest query was another native geometry cast.
The legacy adapter still obtains rest info internally when needed. Existing
surface lookup, player detection, masks and departure behavior are checked.

## Validation and cost

Godot 4.7.2, local extracted assets, Box3D and the matching native movement
library. The new one-query and two-bounce checks both failed before the
fixes and passed afterward. The gameplay query suite passes **65 checks**
without a legacy fallback. `scripts/run_tests.sh` passes **7,131 checks in
76 files**; draw-only suites skip in this headless run as designed.

The existing seeded `scripts/profile_box3d_match.gd -- --physics box3d`
fixture runs 768 measured ticks, 10 players, an HE throw/drop and a staged
fight. One before/after process each:

| Metric | Before | After |
|---|---:|---:|
| Mean tick ms | 1.917 | 1.901 |
| p95 tick ms | 2.445 | 2.409 |
| Maximum tick ms | 4.369 | 4.845 |
| Mean/max hull traces | 23.56 / 44 | 23.56 / 44 |
| Adapter query calls | 34,511 | 34,509 |
| Shots / players alive | 22 / 10 | 22 / 10 |
| Legacy queries | 0 | 0 |

This is a workload check, not a statistically established speedup. The
single maximum increased, so this pair does not establish a tail-latency
improvement either. It excludes rendering, audio and automatic Godot server
stepping; it does not close the 6 ms foreground frame target. Both runs used
native movement. The existing fixtures report resource-cycle warnings on
exit; the test runner separately requires successful check totals and exits.

## Order of the remaining work

1. Define a projectile trace result with end position, impact fraction,
   contact normal/identity and explicit blocked-start handling. Separate
   clearance displacement from elapsed flight time. Check tiny motion,
   outgoing contact, shallow slopes, edges, triangles and moving hulls;
   retain the player/native movement contract. A dedicated addon query
   tolerance may be needed; assess it locally instead of changing global
   solver tolerances or assuming that a no-normal hit is physically solid.
2. Restore map grenade clips on their reserved layer, then port the recovered
   launch box, flight box, 1/128 s substeps and grenade callback rules.
3. Port strength approach/snap, scheduled release and jump snapshot together
   with spawn-based fuse/think ordering. Compare standing, running, jumping,
   close-wall throws and actual dust2 lineups against current CS2.

General rigid-body optimization can proceed independently. No broad
physics rewrite is a prerequisite established by this audit.

Reproduce the local fixtures with `scripts/run_tests.sh box3d_query_gameplay
box3d_movement grenade`. The [audit tool guide](../../scripts/shooting_audit/README.md)
lists the additional Ghidra exports. Raw binaries, source downloads, probes
and decompiler exports remain ignored local evidence, not repository content.
