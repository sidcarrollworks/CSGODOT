# Frame-time audit — 26 September 2026

The full Box3D conversion is slower primarily because of the bridge that
synchronizes Godot's player/hitbox nodes into the native world. In a controlled
ten-player simulation, synchronization takes **3.47 ms per tick**; the interval
containing all four native world steps takes **0.42 ms**. This is evidence about
our integration and workload, not a general ranking of Box3D against Jolt.

At 4K with nine bots, the repeatable Box3D frame-time p99 is **12.5–12.8 ms**,
against **9.1 ms** through the legacy path. Sid's reported CS2 recent worst
frame time is **5–6 ms** on the same machine at 4K, medium/high settings. We have
a substantial gap on both physics paths, plus separate first-use hitches.

No production gameplay or graphics settings were changed by this audit.
Only profiling tools and documentation changed. Gameplay source measured:
`ecaa77e`, branch `codex/box3d-dropped-guns`.

## What was measured

Machine: Ryzen 7 7800X3D, RTX 4070 Ti, approximately 32 GiB RAM, Windows 11
10.0.26200; NVIDIA driver 32.0.16.1692. Godot 4.7.2 official debug-capable
executable, Vulkan 1.4.351, Forward+, exclusive fullscreen 3840×2160. This was
a standalone game process, without an attached editor/debugger; a shipping
release export was not tested. The addon uses its installed native binary.

Project settings include 4× MSAA, an 8192 directional-shadow atlas with Soft
High filtering, occlusion culling, HDR 2D, CS2 colour grading, bloom and
reflections. Normal play enables V-Sync and caps this display at 224 FPS.
Uncapped runs disable V-Sync and the cap. Resolution experiments keep the
4K window/UI and reduce 3D scale to 0.5, meaning 1920×1080 internal 3D.

`profile_combat.gd` leaves ordinary game callbacks in place and measures
end-of-process wall-clock intervals. It also records tick callbacks, frame
callbacks, delayed viewport renderer CPU/GPU counters, draw counts, memory,
pipeline counters, focus and gameplay events. The recorder costs about
**0.009–0.010 ms/frame**, measured inside its callback. That excludes the cost
of enabling GPU timestamp queries; the same instrumentation is used in both
backend comparisons. Data is kept in memory and written after recording.

Each main comparison records 45 seconds after map setup, eight seconds of
load grace and one second of profiler-setup grace. These are not cold map-load
benchmarks: first-use weapon/grenade actions during play remain included.
The seed is 20260926. The camera follows a bot; the local player is a ghost
so it cannot block that bot. The same schedule buys an AK at two seconds and
stages encounters at 30 and 38 seconds. Immortality preserves ten players and
avoids the legacy mode's unsupported native-only ragdolls. Identical seeds
do not guarantee identical trajectories, shots or rendered cameras across
physics engines; this is a workload comparison, not an instruction replay.

Focus changes and their ambiguous frame intervals are excluded from
**focused** statistics, with a 250 ms guard on both sides. All raw samples
remain available. Percentiles use nearest rank. Maximum means the worst
observed frame in that recording, not a guaranteed bound.

CS2's telemetry displays the worst frame over a recent window, whereas FPS
is averaged. Valve does not specify a one-second window in that explanation;
our one-second maxima are a useful approximation, not the identical HUD
algorithm. These are also different measurement endpoints: Godot callback
intervals are **not OS presentation timestamps**. [Valve's telemetry explanation](https://help.steampowered.com/en/faqs/view/5E6F-5B36-5485-F6B9).

If the CS2 comparison is an online match, its authoritative server simulation
also runs elsewhere; this project runs all nine bots and authoritative game
logic locally. That is a workload distinction, not a reason to accept our
current slow frames. A like-for-like CS2 local-bot capture remains unmeasured.

## Frame distribution

All times below are milliseconds. The three paired 4K rows were focused for
their entire recording. The two-player run has one bot. Other rows explicitly
use the focused subset.

| Scenario | Frames used | Mean | Median | p95 | p99 | p99.9 | Observed max |
|---|---:|---:|---:|---:|---:|---:|---:|
| Box3D, 4K, ten immortal players | 6,727 | 6.69 | 4.75 | 11.72 | 12.76 | 14.78 | 18.49 |
| Box3D, same 4K run repeated | 6,826 | 6.59 | 4.71 | 11.45 | 12.48 | 13.94 | 18.96 |
| Legacy, 4K, ten immortal players | 8,263 | 5.45 | 4.75 | 8.31 | 9.07 | 11.01 | 14.94 |
| Box3D, 1080p internal 3D, focused subset | 7,488 | 5.55 | 3.88 | 10.39 | 11.61 | 13.86 | 17.52 |
| Box3D, 4K, two immortal players | 9,831 | 4.58 | 4.53 | 5.73 | 6.23 | 6.84 | 27.72 |
| Normal cap/V-Sync, 4K, deaths and grenade sequence, focused subset | 6,218 | 6.78 | 4.60 | 11.97 | 15.04 | 18.97 | 119.07 |
| Live Competitive round, 4K, deaths/grenades, focused subset | 6,301 | 6.35 | 4.52 | 11.35 | 12.58 | 14.99 | 17.79 |

The paired uncapped Box3D runs average 150–152 FPS; legacy averages 184 FPS.
**42.2–42.9%** of those Box3D frames exceed 6 ms, against **35.0%** on legacy.
The median of complete focused one-second peak buckets is **12.64–12.97 ms**
for Box3D and **9.36 ms** for legacy. These recent peaks, rather than the
4.7 ms frame median, are closer to the quantity Sid is reading in CS2.

In normal capped play, frames without a tick have a **4.00 ms median**;
frames with one tick have a **10.50 ms median**. At roughly 150 FPS, the
64 Hz simulation puts a long tick into about 43% of frames. Average FPS hides
that repeated unevenness. Lowering the graphics load improves ordinary
frames much more than the tick-containing tail.

The initial half-resolution run was entirely unfocused and is excluded as a
foreground comparison; the row above uses the subsequent foreground capture.
Its all-sample GPU mean was **1.76 ms**, versus **4.44–4.45 ms** at native 4K.
Despite that large GPU reduction, the focused p99 still exceeds 11 ms.
GPU/component means in the JSON are all-sample values, not the same focused
subset as every frame percentile in this table.

The verified live round omits staged encounters, records 22 shots and four
deaths (six to ten players alive), and confirms HE, smoke, active inferno and
flash events. The follower remains non-colliding throughout: zero recorded
ghost collision faults. It is a different workload from the immortal pair;
its lower late-round player count should not be credited as an optimization.

## Where the CPU time goes

Separate, serial, headless diagnostic: fixed 768-tick Dust2 workload with
ten players, an AK drop, an HE throw, route movement and a staged engagement;
22 shots, 59,239 native facade queries, zero legacy facade queries.
The uninstrumented control averages **6.701 ms/tick**; nested instrumentation
averages **7.024 ms/tick**, about **4.8%** higher. The earlier branch numbers
7.091/3.296 were simulation-only too; neither set was a full frame time.

The following diagnostic costs are **exclusive and additive**. Inclusive
world-phase costs and query costs overlap and must not be added again.

| Work | Mean ms/tick | Interpretation |
|---|---:|---|
| Dynamic proxy synchronization | 3.4702 | Scans, transforms, shape metadata, native proxy updates |
| Player command/movement self time | 1.2954 | Excludes timed nested queries; includes explicit hull refreshes |
| Bot command generation self time | 0.4311 | Excludes nested queries |
| Native cast wrapper | 0.4750 | Native cast plus its thin wrapper, not solver stepping |
| Shape-cast facade self time | 0.3477 | Excludes synchronization/native cast/exclusion buckets |
| Ray facade self time | 0.2743 | Includes native ray/inside-overlap work, excludes sync |
| Temporarily applying query exclusions | 0.1377 | Proxy layer changes/restoration path |
| Four native-step interval | 0.4152 | Four calls plus dropped-state transfer between profiler signals |
| End-tick self time | 0.1591 | Remaining systems/events outside measured children |
| Dispatch and begin-tick self time | 0.0176 | Bookkeeping |

Exact timer accounting closes to zero microseconds for both tick and separate
animation batch. Last-native-call telemetry is 0.0703 ms mean, but describes
only the last of four `b3World_Step` calls, including collision work. It must
not be called total solver cost or multiplied into an asserted full-tick cost.
This controlled run has no deaths/ragdolls; it does not bound a corpse pile.

Counts collected in a separate, untimed inspection run explain the sync cost:

- 60,775 calls to `sync_dynamic` over 768 ticks: about 79 calls per tick.
- 482,600 hull-registry entries and 296,020 hitbox entries visited.
- 509,619 hull synchronizations including explicit calls; **475,119 (93.2%)**
  immediately find an unchanged pose/layer. 7,066 further calls force a
  geometry refresh despite unchanged pose. Some refreshes can be necessary
  for resizing: they are candidates, not proof all can be removed.
- 257,467 hitbox updates see changed poses/layers. Those are real state
  changes, so simply skipping synchronization would break bullet hits.
- There are only ten hulls and 190 hitboxes. Repeated registry scans and
  per-shape GDScript/native calls are expensive relative to that body count.

Code paths: `GameWorld.begin_tick()` and `Box3DDrops.tick()` both synchronize
all proxies; individual queries synchronize matching registries again.
`Box3DQueries.sync_object()` traverses shape owners and computes shape keys
when transforms change. Movement also explicitly refreshes its hull.
The native binding pushes kinematic transforms in each world step. Source:
`src/sim/game_world.gd`, `src/physics/box3d_queries.gd`,
`src/physics/box3d_drops.gd`, `src/movement/player_body.gd`.

A separate visible callback-attribution run records **1.37–1.48 ms/frame**
of timed script/animation work: player models 0.59–0.68 ms, skeletons/hitbox
attachments 0.31–0.34 ms, other animation trees 0.10–0.11 ms, HUD about
0.14 ms. Its timer/dispatch overhead makes inclusive frame callbacks
1.49–1.61 ms. This profiler manually invokes callbacks and poses skeletons,
so use it for attribution, not as an unmodified-frame benchmark.

That run also found movement-heavy ticks of **13.5–13.8 ms**, with **260–285
hull traces** and almost 10 ms in bot `run_command`. Trace amplification
around contacts/recovery is a second CPU target, beyond ordinary sync costs.

The ordinary 4K paired runs measure tick callbacks at **5.61–5.69 ms** on
Box3D and **2.61 ms** on legacy. Native stepping happens inside those callbacks;
Godot's automatic Jolt server step happens outside them. Therefore this
tick-only comparison is asymmetric. The full frame comparison includes both
and still shows the regression. CPU and GPU execution overlap; their times
must not simply be added into a claimed frame cost.

## Rendering and cold spikes

GPU attribution uses eight fixed spawn views, 20 warm frames plus 40 measured
frames each. Simulation is frozen after startup so deaths/movement do not
change the scene between variants; visual animation can still progress.
The initial and final baseline agree within 0.01 ms. These are feature
ablations at fixed views, not guaranteed savings at every camera or additive
savings when several features change together.

| Variant | GPU median ms | Difference from 4.21 ms baseline |
|---|---:|---:|
| Baseline | 4.21 | — |
| No sun shadows | 2.89 | 1.32 |
| No 4× MSAA | 3.43 | 0.78 |
| No bloom | 3.72 | 0.48 |
| No HUD blur | 4.11 | 0.10 |
| Half width/height 3D | 1.60 | 2.61 |
| Hidden player meshes | 4.18 | 0.03 |
| Baseline repeated | 4.20 | 0.01 |

Baseline renderer CPU is 0.72–0.73 ms in those views, with about 294 visible
draw calls and 72 shadow draws, 264k visible/182k shadow triangles. The
renderer reports approximately 4,968 MiB total video allocation, including
3,944 MiB textures and 494 MiB buffers. This monitor is not a claim that all
allocation is physical VRAM, nor a memory-leak investigation. Hidden-player
cost depends strongly on the views; it says nothing about their CPU AI,
animation or collision cost. Reflections were retained; the existing
`no_reflections` variant is not a clean measurement of their full cost.

Observed hitches are separate from the regular tick penalty:

- **119.07 ms**, focused, near the first Molotov throw at 22.18 seconds in
  normal capped play. The frame contains six catch-up ticks (32.88 ms) and
  an 82.23 ms uninstrumented remainder. A delayed renderer-CPU sample reaches
  **80.03 ms** two rows later; surface/specialization compilation counters
  also change. This implicates first-use/render-related work, but does not
  establish a particular shader or prove the entire remainder is rendering.
  Bottle instantiation/probe material adoption and later fire creation are
  distinct paths. A later grenade sequence did not reproduce this peak.
- **27.72 ms**, focused, at the first AK equip in the two-player run:
  22.38 ms lies inside frame callbacks, versus 1.19 ms in tick callbacks.
  This survives reducing the bot load and is a separate first-use view/model
  problem. No contemporaneous pipeline count increase was reported.
- Raw 164 ms, 184 ms and 68.8 ms peaks coincide with focus loss/transition
  in their captures. They are retained but are not used as foreground
  gameplay maxima. Catch-up ticks following a stall are partly its consequence.

The corrected live round's largest focused frame is **17.79 ms**, near the
Molotov/inferno start; its tick callbacks take 13.28 ms. All-sample 51/80 ms
focus-related peaks from that run are likewise excluded. Driver/resource
caches were not purged between runs; absence of the original 119 ms peak
on later runs does not establish that its cause has been fixed.

Other audited risks need targeted timings before assigning them milliseconds:
smoke/fire rebuild their draw buffers each frame and use a 200,000-unit
MultiMesh AABB; ragdoll creation allocates bodies/joints and adds pairwise
collision exclusions to nearby ragdolls; awake corpse parts perform floor
rays. Map visibility cluster transitions walk the map's meshes. A first
route can lazily build the nav graph, and a missing/incomplete preload can
still block in `RigModel.preload_scene`. The corrected live grenade run includes
one active inferno, but does not isolate its steady GPU cost. Menus, large corpse piles,
many simultaneous smokes, every camera/map and a release export are not
covered by these recordings.

## Work to do first

1. **Make proxy updates explicit and incremental.** Track transform, pose,
   collision-layer and shape revisions; separate transform-only updates from
   geometry rebuilds. Update animated hitboxes at defined pose changes and
   query boundaries. Remove repeated whole-registry scans while preserving
   same-tick movement, crouch resize, disabled hitboxes and bullet semantics.
   Batch transforms/native calls if the addon API is the remaining bottleneck.
   The 3.47 ms measured bucket is a ceiling on this opportunity, not a promised
   saving: necessary hitbox updates remain.
2. **Reduce contact/recovery trace amplification.** Profile crowded spawn and
   wall/step cases; preserve the existing movement/penetration checks. Count
   traces and p99 tick cost, not just average FPS. Avoid weakening collision
   quality or lowering native step count before measuring its small share.
3. **Warm the actual first-use paths.** Investigate first weapon-view
   instantiation, grenade bottle/probe materials and fire MultiMeshes
   independently. Compare first and second use within the same process;
   preload alone does not exercise all mesh/material/render paths.
4. **Then tune rendering quality with visual comparison.** Shadows, MSAA and
   bloom have measurable GPU cost. Try a smaller shadow atlas/filter and
   antialiasing choices before changing appearance defaults. Lower resolution
   alone does not get the current ten-player p99 near 6 ms.
5. **Retest against the actual target.** Foreground recent-window peaks,
   p99/p99.9 and cold interactions at 4K, with identical schedules and external
   presentation capture when available. Use release builds and comparable
   local/online workloads before claiming parity with CS2.

## Reproduction and evidence

Run each process serially, from the worktree, with extracted assets and the
installed Box3D addon. Substitute the path to Godot 4.7.2 for `godot`; on
Windows use `Start-Process -Wait` to wait for this GUI executable to finish.
Create `.godot/frame-audit` before specifying output paths.

```text
godot --path . --script scripts/profile_combat.gd -- 45 immortal --physics box3d --output .godot/frame-audit/box3d-4k
godot --path . --script scripts/profile_combat.gd -- 45 immortal --physics legacy --output .godot/frame-audit/legacy-4k
godot --path . --script scripts/profile_combat.gd -- 45 immortal --variant half_resolution --physics box3d --output .godot/frame-audit/half-res
godot --path . --script scripts/profile_combat.gd -- 45 as-played effects --physics box3d --output .godot/frame-audit/played
godot --path . --script scripts/profile_combat.gd -- 45 round natural effects --physics box3d --output .godot/frame-audit/live-round
godot --path . --script scripts/profile_combat.gd -- 45 immortal --team-size 1 --physics box3d --output .godot/frame-audit/two-players
godot --headless --path . --script scripts/profile_box3d_match.gd -- --physics box3d
godot --headless --path . --script scripts/profile_box3d_costs.gd -- --physics box3d
godot --headless --path . --script scripts/profile_box3d_costs.gd -- --physics box3d --sync-counts
godot --path . --script scripts/profile_dust2.gd -- 5 3 --physics box3d --skip-single-operations --immortal
godot --path . --script scripts/profile_render.gd -- 5 40 native baseline,no_msaa,no_sun_shadows,no_glow,no_hud_blur,half_resolution,no_players,baseline --freeze --physics box3d
python scripts/summarize_frame_audit.py .godot/frame-audit --output .godot/frame-audit/summary.json
```

Machine-readable summaries are in `frame-times-2026-09-26.json` beside this
report. Original CSV/metadata and logs remain in the local ignored
`.godot/frame-audit/` directory. `profile_dust2.gd` now includes the previously
omitted `begin_tick` synchronization cost and separates nested event timing
from additive totals. The query profiler checks exact exclusive accounting.
The frame summary guards whole focus-transition intervals, including a long
first refocused frame. An initial live-round recording
(`box3d-4k-live-round`) is excluded from conclusions: fresh-round respawn
restored the follower's collision. The profiler now reapplies ghost state on
respawn and records collision faults; the corrected run is kept separately.

An OS presentation trace was unavailable. The installed NVIDIA PresentMon
fork exited silently without a CSV; the cause is unestablished. Automatic
approval review blocked the portable official profiler download with
“blocked by policy.” No elevation or installation was performed. Therefore
none of these measurements should be described as captured screen presents
or input latency.

Validation: all changed Godot profilers parse, and the recorded runtime runs
complete without script/parse errors. The invalid render-subset guard exits
2 as expected; focus-filter fixtures cover clean focus, a two-second refocus
gap, an interval crossing the guard and overlapping guards. Exclusive tick/
pose accounting closes exactly. The full 43-file headless suite exercises
3,750 assertions: **3,746 pass; the four existing AWP settling assertions
fail**, and the draw-only suite skips headless. This branch remains a draft
trial, not merge-ready. Logs also retain existing shutdown resource/ObjectDB
warnings; these were not mistaken for frame-time measurements or resolved
by this audit.
