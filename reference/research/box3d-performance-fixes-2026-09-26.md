# Box3D bridge and movement performance fixes — 26 September 2026

This follows the [frame-time audit](frame-times-2026-09-26.md). The requested
target is **6 ms maximum frame time** at 4K with nine bots on Sid's Ryzen 7
7800X3D and RTX 4070 Ti. Effects and graphics settings are outside this pass.
The audit commit, `493ce63`, is the baseline.

## Changes

- Query-only player and bone proxies update when a query actually needs their
  layers. The previous begin/end-tick scans refreshed 190 bone capsules twice
  per tick, including ticks without a shot. New scene nodes still flush before
  native stepping, so a late static collider exists even without a query.
- These proxies use static sensors with explicit native teleports. They have
  no physical response and do not need four kinematic target updates per tick.
  The native world still takes four collision steps and four solver substeps;
  dropped-body quality settings are unchanged.
- Moving a proxy reuses its authored shape transforms and dimensions. Explicit
  shape/owner edits refresh geometry; shared Shape3D resource changes invalidate
  every subscriber. Queries compare current global transforms, including
  ancestor motion, rather than treating a whole tick or frame as immutable.
- A movement trace synchronizes and excludes its own hull once across its
  synchronous recovery probes. Exclusions are restored before an object moves.
  Intermediate self movement does not update an excluded mirror; the completed
  simulation publishes it, and another caller's query also pulls its latest pose.
- A zero-travel, zero-normal slide result stops repeated identical recovery
  searches. Deeply overlapping axis-aligned player boxes can prove that every
  allowed recovery offset remains inside the same box, avoiding that search
  entirely. Shallow contacts, compound/rotated shapes and other geometry retain
  native recovery. This does not skip collisions or invent contact normals.

## Measurement

All engine workloads run serially. The same standalone Godot 4.7.2 executable,
native addon binary, renderer and project settings are used as in the audit.
The 4K runs retain nine bots, 64 Hz gameplay, the seeded follow camera,
first AK equip and staged encounters. They use immortality and omit scripted
grenade effects, exactly as the original paired Box3D recordings did. Ordinary
gunfire visuals remain. Trajectories are not an instruction replay.

Wall intervals are measured at the end of ordinary process callbacks, not at
OS presentation. GPU counters are delayed samples and cannot simply be added
to a row's CPU timings. Percentiles use nearest rank. Focus exclusions and
250 ms guards follow the original audit; raw measurements are retained.

The first isolated change (lazy bone updates plus static query sensors) took
the identical 768-tick headless workload from **6.701 to 4.221 ms mean**, with
the same 22 shots, 59,239 native queries, zero fallback queries and 55.31 hull
traces per tick. Headless timings exclude drawing and animation pose batches.

After geometry caching and prepared recovery casts, disjoint instrumentation
measured **0.547 ms/tick in synchronization**, down from **3.470 ms**. The native
step interval fell from **0.415 to 0.144 ms**. These intervals are disjoint.
The four native collision steps were retained. Hitbox registry visits fell
from 296,020 to 4,180 over the workload: queries still synchronize before shots.

That intermediate version's 45-second 4K capture (`optimized-4k`) recorded
8,149 focused frames: mean 5.522 ms, p99 9.932 ms and maximum 16.033 ms.
Average tick callbacks were 3.25 ms, versus 5.61–5.69 ms before this pass.
GPU mean was unchanged at approximately 4.45 ms. This was an improvement,
**not attainment of the 6 ms maximum target**. Later captures below include
the final conservative overlap rejection and deferred intermediate hull sync.

### Final 4K captures

Both final 45-second recordings stayed focused throughout. All frames are
included; no first-use or staged-encounter spike is removed. Machine-readable
summaries, metadata, timing distributions and worst rows are in
[the results JSON](box3d-performance-fixes-2026-09-26.json). Raw CSVs and logs
are retained locally in `.godot/frame-optimization/`.

| Run | Frames | Mean | p95 | p99 | Maximum | Mean tick callback |
|---|---:|---:|---:|---:|---:|---:|
| Original Box3D audit | 6,727 | 6.689 ms | 11.725 ms | 12.764 ms | 18.493 ms | 5.69 ms |
| Original repeat | 6,826 | 6.592 ms | 11.447 ms | 12.477 ms | 18.958 ms | 5.61 ms |
| Final | 8,181 | 5.501 ms | 8.702 ms | 9.836 ms | 15.629 ms | 3.166 ms |
| Final repeat | 8,178 | 5.503 ms | 8.786 ms | 9.754 ms | 26.837 ms | 3.165 ms |

This removes roughly **44% of average tick callback time**. Typical long
frames improve, but **35.4% of frames still exceed 6 ms**. Complete one-second
bucket maximum medians are 9.983 and 10.059 ms, down from 12.64–12.97 ms in
the audit. The 6 ms maximum target is therefore **not achieved**.

The repeat's 26.837 ms frame occurs at 2.108 seconds, near the first AK equip:
two catch-up ticks account for 6.787 ms, frame callbacks 0.880 ms, and the
remaining 19.170 ms is outside those timers. Focus stays active and the row's
pipeline counters do not change. This does not identify the stall's cause;
it is neither a proven physics spike nor something to discard from the max.
The final runs fire 712 and 713 total shots respectively.

### Final CPU attribution and remaining work

The uninstrumented seeded simulation finishes at **3.284 ms mean, 4.049 ms
p95 and 5.873 ms maximum**, compared with the baseline's 6.701 / 7.924 /
10.552 ms. It still fires 22 shots, executes 59,239 native queries and zero
legacy queries, with 55.31 hull traces per tick (maximum 111). This headless
maximum is not a rendered-frame maximum.

The separate instrumented run averages 3.438 ms (about 4.7% overhead).
Its disjoint costs per tick are:

| Exclusive CPU category | ms/tick |
|---|---:|
| Player command execution outside the nested query timers | 1.1940 |
| Proxy synchronization | 0.5247 |
| Native cast wrappers | 0.4414 |
| Command generation outside nested queries | 0.4109 |
| Ray facade outside nested synchronization | 0.2598 |
| Prepared cast result conversion | 0.1819 |
| End-of-tick systems outside native interval | 0.1507 |
| Four native steps plus item-state transfer | 0.1334 |
| Exclusion preparation | 0.1263 |
| Dispatch and begin-tick | 0.0139 |

Exact accounting has zero unassigned microseconds before rounding. The
separate manual ten-player pose batch costs 1.478 ms; it is outside the
headless tick interval and is not the actual rendered animation schedule.
The native last-step telemetry is 0.0237 ms on average and describes only
the last of four native calls, not their sum.

The original synchronization regression is substantially reduced (3.470 to
0.525 ms, approximately 85%). Further gains toward 6 ms need to shorten the
remaining movement/query and command work on the critical tick frames;
proxy synchronization is no longer most of the tick. At 4K, final no-tick
frames have p99 5.59–5.62 ms, while one-tick frames have p99 10.33–10.49 ms.
The unchanged GPU workload averages 4.44 ms. These measurements do not prove
that a thread-model switch, lower tick rate or lower graphics quality is
necessary, and none was introduced. Effects and first-use work remain
outside this optimization pass as requested.

## Validation

The complete local `scripts/run_tests.sh` run with extracted assets reports
**3,810 assertions: 3,806 passed and four known AWP settling failures**.
There are 44 suite files: 42 pass, the drop-quality suite fails and one
draw-only suite skips headless. There are no script/parse/compile errors.
Existing headless renderer and shutdown resource diagnostics remain.

The four AWP failures reproduce their original results: floor sleep 1/4 and
late drift 0.84306 inches / 0.03031 radians; ramp sleep 0/4 and drift
0.45922 inches / 0.02737 radians. These drop-only fixtures do not use the
changed full-world query proxies. No thresholds or assertions were relaxed.

New synchronization checks pass **51/51**, covering same-tick successive
movement, inherited transforms, bone poses, shared shape resources, resizing,
owner/layer/disabled changes, removal/reentry, exclusions and late static
geometry before a native step. Native movement passes **31/31**, including
deep versus shallow overlap, immediate escape, recovery query accounting,
and exclusion restoration. The Source movement course passes **80/80**,
bot movement **32/32**, native gameplay queries **43/43**, native ragdolls
**67/67**, and real Dust2 integration **10/10**. Independent source review
found no actionable correctness issue. The PR remains a draft because
performance acceptance and the four known settling failures are still open.

## Reproduce

Create the output directory before recording. Run these serially from the
project root with the installed addon and extracted/imported assets:

```text
godot --headless --path . --script scripts/profile_box3d_match.gd -- --physics box3d
godot --headless --path . --script scripts/profile_box3d_costs.gd -- --physics box3d
godot --path . --script scripts/profile_combat.gd -- 45 immortal --physics box3d --output .godot/frame-optimization/final-4k
python scripts/summarize_frame_audit.py .godot/frame-optimization --output .godot/frame-optimization/summary.json
scripts/run_tests.sh
```

`profile_box3d_costs.gd` instruments the shared prepared-cast path so recovery
probes remain counted. Its `shape_cast` self bucket now excludes preparation
and restoration, which remain in other disjoint buckets/caller self time;
do not compare that one bucket alone with the old outer-call timer.
With `--sync-counts`, object rows count actual `sync_object` calls, while
`COST_SYNC_SCANS` counts registry candidates including early unchanged skips.
The counts mode intentionally does not report timings.
