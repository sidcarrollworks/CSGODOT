# Grenade throw, flight and activation port — October 2, 2026

Roadmap **20a / G1**, following merged PR #181. This implements the core
rules recovered in the [current-build audit](grenade-audit-2026-10-02.md)
after the [collision foundation](collision-foundation-2026-10-02.md).
It does not mark recorded CS2 lineup parity or G2–G5 effects complete.

## Implemented rules

| Path | Implementation |
|---|---|
| Held strength | First hold assigns left/both/right directly; later eligible command ticks approach the target by 0.0203124992549. Launch snaps within 0.1 of 0.5, then clamps. |
| Release | A hand release schedules simulation time +0.1 s. Consume requires time strictly greater than the deadline; a first qualifying jump consume defers once by another 0.1 s. Inventory removal/event occur at spawn. |
| Jump parameters | An actual jump schedules its stash at simulation time − movement interval +0.1 s, corrected by the [Xbox lineup follow-up](grenade-jump-lineup-2026-10-02.md). Movement finish captures eye, collision center, aim and velocity. Ready snapshots are used only at age >0 and <=0.2 s. Death/respawn clear pending state. |
| Launch | ±2.02-inch box from pawn collision center to lowered eye + forward16; no six-unit backward adjustment. Pitch wrap/lift, authored speed ×0.9 clamped 15..750, strength scale 0.7S+0.3 and pawn velocity ×1.25. |
| Flight | Axis-aligned ±2-inch box. Normal 64 Hz ticks run two 1/128 s steps; the recovered nonintegral-interval fallback remains. Gravity is 320 u/s² with midpoint vertical displacement. |
| Surface bounce | Clip push max(-2 dot(v,n),0)+0.03125, then elasticity 0.45. Player surfaces use a radial normal, with no universal ×0.3 restitution. Floor rest/high-speed outward reduction, the 21-count bounce cap and nine zero-velocity updates are retained. |
| Enemy body hit | Separate radius-3 overlap before flight, once per projectile: two generic damage, radial reflection retaining 0.3 of speed, and +4 s to a fire grenade's air deadline. Our query uses player hulls; full Source2 entity filtering remains open. |
| HE / flash activation | Spawn +1.5 s deadline; danger thinks poll every 0.2 s from the actual executed think and detonate strictly beyond the deadline. |
| Smoke / decoy activation | Smoke checks each tick for age >=1.18799996376 s and speed <=0.1. Decoy first thinks at spawn +2 s, then polls every 0.2 s until speed <=0.2; its existing 15 s active lifetime remains. |
| Fire activation | Ground normal >=cos30 detonates at its contact point. Air think checks the strict spawn +2 s deadline (plus body extension), or more than 0.5 s at speed <=5. Airburst ray goes from position +10 up to position -128 down. |
| Map clips | `grenadeclip` meshes are retained on layer 32, separate from world and player clips, and excluded from camera occluders. |

Explicit console/range/bot `throw` commands remain immediate spawn requests.
The player's pin and hand release use the timer above. Existing throw clips
remain presentation, with independent 0.77/0.50 s hand busy times.

The decoy's initial 2 s think is an additional factory finding:
`server.dll` factory **1809afd80** sets the first think using
`DAT_18177e584 = 2.0`; the subsequent activation think **1809cda40** uses
the speed threshold and 0.2 s retry. The DLL build/hash and remaining
function addresses are recorded in the original audit. No Valve binary,
asset or decompiler output is distributed with this patch.

## Dedicated projectile contact

`ProjectileTrace` returns hit, original collider/RID/shape, normal,
geometric fraction, corrected end, offset and an explicit blocked-start flag.
The geometric fraction consumes flight time. A separate **0.01-inch normal
clearance** affects position only. The native query uses **0.001-inch
linear slop**. These are our numerical bridge choices, **not recovered
Source2 constants**. They are scoped to the new projectile cast; existing
player movement, ordinary query and rigid-body solver settings are unchanged.

The opt-in Box3D query distinguishes a touching plane from an unresolved
embedded start using bounded local distance probes. Outgoing/tangent motion
can leave a touching plane without excluding the whole body, so a different
wall in the same triangle mesh can still be hit. Incoming contact returns
its plane; unresolved starts stop conservatively with no fabricated normal
or bounce event. Concave meshes remain triangle surfaces: this does not
provide a volumetric inside/outside test for a closed mesh.

Each native sweep supplies its fraction and contact in one adapter query.
The flight keeps a bounded maximum of four sweeps per substep for corners;
this is not a claim that Source2 callback recursion has been reproduced
bit for bit. The legacy comparison path explicitly checks initial overlap
before Godot `cast_motion`, which otherwise ignores embedded starts.

## Reproducible addon build

`scripts/install_box3d.ps1` and `.sh` invoke
`build_box3d_projectiles.py`. Git, Python 3 and a C/C++ compiler are required.
It builds both debug and release, cached under ignored `.godot/`.

| Input | Pin |
|---|---|
| Box3D v0.4.3 | `3ce52ff999f2509a89ec53538ff77c3cf35092fa` |
| godot-cpp | `ba0edfed90512ec64aba51d4295a3e7e30112f86` |
| SCons | 4.8.1 |
| Resource zip SHA-256 | `aa5880b6dd57aae89699b16728d379b521b5332bbf84dfc74dbff912a612ddd3` |
| Source patch | `scripts/box3d-projectiles.patch`, MIT notice in `box3d-projectiles.LICENSE` |

The resource zip's unpatched binaries are never installed. The installer
checks source revision and exact patch diff, refuses linked resource roots,
and detaches only a worktree's linked `bin` entry before installing its own
libraries. Windows/Linux x86-64 are supported; macOS source builds are
available but untested locally. Feature checks fail clearly for an old addon.

The new binding refuses upstream Box3D query recording because that format
does not store per-query tolerance. Gameplay currently does not enable it.
General upstream recording and ordinary casts retain their prior format.

## Validation

`scripts/run_tests.sh`: **7,335 checks in 78 files, all passed**, with
extracted assets and native movement comparison enabled. Offline installer
checks: **10 tests passed**. Fresh pinned Box3D/godot-cpp checkouts and patch
validation also passed. Checkout regression tests cover empty submodule
directories inside the parent repository, which caused the first CI install
to read Box3D's commit instead of initializing godot-cpp. Both patched Windows libraries built successfully;
projectile checks were also rerun against the final installed debug library.
The checks cover:

- Box and triangle contacts at origin and map-scale coordinates, tiny
  rebounds, exact touching departure/incoming contact, corners in one mesh,
  angled floors, embedded stops, exclusions and original shape metadata.
- Low-ceiling pawn-center launches, moving hull synchronization, grenade
  clip masks, one-time enemy impact and fire fuse extension.
- Strength/button changes, strict release boundaries, one jump deferral,
  copied/stale snapshot parameters and activation/think thresholds.
- A real subtick jump through `PlayerSim` and `GameWorld`: a later mouse
  turn must not change the saved launch direction or eye position.
- Installer shared-directory protection, archive path checks and refusal
  to install unpatched archive binaries (offline Python tests).

## Performance

Godot 4.7.2 headless, Windows x86-64, Ryzen 7 7800X3D. Compared merged
main **c1ec2ea** with this port, sequentially, with no simultaneous Godot
run or compiler. The final source patch digest is **66c92c09b84b7db7**.
These are instrumented CPU captures; they do not measure GPU work or prove
the full game's 6 ms maximum-frame target.

| Fixture | Main mean / p95 / max (ms) | Port mean / p95 / max (ms) |
|---|---|---|
| Ten sustained moving grenades, ten stationary hulls, 4,096 ticks | 0.253 / 0.392 / 0.729 | 0.767 / 1.170 / 3.093 |
| Normal Dust2 round, final five-second live window | 2.335 / 3.002 / 5.414 | 2.181 / 2.911 / 3.265 |

The grenade fixture times `_fly` only. Setup, resets, rendering, bots,
smoke/fire effects and rigid-body stepping are excluded. It includes the
new body-overlap check, two flight substeps and contacts. Main made **41,778**
adapter queries; the port **124,091**, about **1.02 versus 3.03 per grenade
per tick**. Contact counts differed (**819 versus 1,480**, peak **3 versus
12 per batch**) because box/substep/bounce rules and imported clips changed.
Both had zero legacy queries, zero blocked updates and finite trajectories.
The hull includes **433,329 versus 435,649 triangles**: the additional
**2,320** are retained grenade clips. The mean increase is about **0.514 ms
for ten**, or **0.051 ms per moving grenade in this fixture**, explained by
the second sweep and separate body check. It is not a measurement of a
single-grenade or twenty-player workload.

The round fixture used `profile_dust2.gd -- 5 5 round --physics box3d
--skip-single-operations --immortal` on both sides. The first windows cover
freeze time; the table uses window 5 after the bots are running. Main and
port each sampled **324 ticks**, with **7,909 versus 7,887 hull traces** and
**21,044 versus 21,082 adapter queries**, zero legacy queries, ten players
alive and **zero shots** in this window. This checks the moving-round cost;
it does not establish combat or drawn-frame performance. There was no
observed regression in this capture; the lower port time is not presented
as an optimization claim. The repeatable flight fixture is
`scripts/profile_grenades.gd`; use the identical script in each checkout.

## Remaining comparisons

Record CS2 standing/running/crouching/jumping throws, button transitions,
close-wall launches, floors/stairs/corners and Dust2 lineups including
grenade clips. Then compare first bounce and landing positions/times.
The snapshot age predicate alone is not a measured user jump-throw window.

Water drag, angular spin, complete standability/entity-class/base-velocity
branches, breakable damage/continuation and owner recontact are not ported.
The enemy overlap uses our collision hulls rather than a fully reconstructed
Source2 entity filter. The jump-throw grunt and the fire StartFailed
presentation remain open. HE target/visibility handling, the audited flash
curve and partial cover, voxel smoke parity, inferno behavior and decoy
weapon burst tables belong to the remaining G2–G5 work.
