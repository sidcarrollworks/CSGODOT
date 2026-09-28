# Repeated player and animation work — 26 September 2026

This follows the [Box3D bridge optimization](box3d-performance-fixes-2026-09-26.md).
The comparison starts at `32148f8`, on the same Box3D branch. Sid's further CS2
testing reports about 5.5 ms recent maximum alone on Dust2, 7–8 ms with nine
bots, and occasional shooting spikes to 13 ms while still feeling smooth.
Those are user observations from CS2 telemetry, not captures made by this
project. The requested 6 ms maximum remains a target, not an achieved
result or a claim about CS2's ten-player maximum.

## Changes and invariants

- Each player model binds animation parameter paths once per locomotion
  variation and writes persistent values only when their inputs change.
  A different AnimationTree or root invalidates the cache. Every variation
  is still prepared before a held-item switch. Landing seeks, transition
  requests and one-shot events retain their consumption/reissue behavior.
- Bots check eligible enemies nearest-first, with stable roster ordering
  for equal distances. A search reuses its eye position, forward direction
  and ray parameters. Visibility and smoke are checked afresh every tick;
  this does not slow reactions or cache a visibility answer.
- Navigation paths retain the subset of their static areas with low ceilings.
  The subset rebuilds when the path changes; the bot's distance and floor
  height checks remain live. Teammate positions remain current in the
  world's sequential player-update order.
- A player reuses its own shooter-state object, refreshing all four fields
  before the weapon reads them, rather than allocating one each armed tick.
- Weapon data caches the damping-dependent recoil peak and frequency
  numerator, shared by its four springs. Changing the authored damping
  invalidates the constants. Recovery times, explicit damping overrides,
  resource copies and the original integration order retain their behavior.

The simulation remains at 64 Hz. This pass changes neither animation
evaluation cadence, hitbox poses, movement traces, physics quality, effects,
graphics settings, nor presentation settings. There is no runtime profiling
branch in the gameplay code. The attribution script alone now splits
`PlayerSim.run_command` at its final animation-parameter update; its small
wrapper must stay in sync with that production method.

## Measurement

All Godot workloads run serially on Sid's Ryzen 7 7800X3D / RTX 4070 Ti,
using the same Godot 4.7.2 executable and addon. Headless simulation and
ordinary rendered frames are separate measurements. The disjoint model
parameter timer measures preparation, not AnimationTree evaluation.

The 768-tick headless workload retains ten living players, 22 shots,
55.31 hull traces per tick (maximum 111), and no legacy physics queries.
Native query calls fall from 59,239 to 59,066: 173 redundant sight rays are
removed. Native hull casts remain 42,582 and native steps remain 3,072.

| Headless simulation | Before | After |
|---|---:|---:|
| Mean tick, ordinary production call | 3.217 ms | 3.095 ms |
| p95 tick | 3.980 ms | 3.825 ms |
| Maximum tick in this run | 5.618 ms | 5.704 ms |
| Instrumented mean tick | 3.577 ms | 3.359 ms |
| Animation parameter preparation, all ten players | 0.2187 ms | 0.1737 ms |
| Bot/player command generation, inclusive of queries | 0.6388 ms | 0.5858 ms |
| Player command self time, excluding queries and model preparation | 1.0395 ms | 0.9707 ms |
| Separate manual ten-player pose batch | 1.5210 ms | 1.5027 ms |

Ordinary mean tick cost falls about 3.8%. The isolated parameter bucket falls
about 21%, and command generation about 8%. These bucket comparisons are
instrumented and do not sum to a promised rendered-frame improvement.
The tiny pose-batch difference is not evidence of faster animation evaluation;
that evaluation was not changed. Neither headless maximum is a frame maximum.

### Rendered 4K captures

These 45-second captures retain nine bots, immortality, seed 20260926, the
follow camera, first equip at two seconds and staged encounters at 30/38
seconds. No scripted grenade effects; normal gunfire visuals remain. The
same original profiler and focus rule are used: exclude intervals overlapping
focus loss/refocus plus 250 ms guards, while retaining every raw row.

| Run | Focused frames / all | Focused mean | Focused p99 | Focused max | Raw max | Mean tick callbacks, all |
|---|---:|---:|---:|---:|---:|---:|
| Before, uncapped | 8,238 / 8,238 | 5.463 ms | 9.720 ms | 15.082 ms | 15.082 ms | 3.145 ms |
| After, uncapped | 7,160 / 8,163 | 5.387 ms | 9.528 ms | 13.623 ms | 101.246 ms | 2.951 ms |
| After, uncapped repeat | 8,333 / 8,333 | 5.401 ms | 9.475 ms | 15.527 ms | 15.527 ms | 2.929 ms |
| After, normal presentation | 7,743 / 8,206 | 5.431 ms | 9.665 ms | 15.923 ms | 107.475 ms | 2.972 ms |

The fully focused repeat reduces mean tick callbacks by about 6.9% and p99
frame intervals by about 2.5%. Maximum frame time is not improved in that
comparison, and the **6 ms maximum target is not reached**. The scene is
seeded but not an identical input replay: total shots are 711 before,
713/711 after, and 712 with normal presentation. The clean before/repeat
pair has nearly identical GPU means (4.428/4.431 ms).

The 101/107 ms raw maxima coincide with loss of window focus. Additional
59/26/21 ms intervals overlap refocus/guard periods. They remain in the raw
distribution; they do not establish a gameplay regression or identify an
engine stall's cause. The all-frame p99 for the first optimized run is
9.983 ms, worse than baseline, so using only that unfiltered capture would
hide the focused improvement. Both distributions are provided explicitly in
[the measurement JSON](player-update-performance-2026-09-26.json).

Normal presentation reports exclusive fullscreen (mode 4), V-Sync enabled
(mode 1), and the existing 224 FPS cap at 3840×2160. This is a settings check,
not a before/after presentation comparison or verification of driver VRR.
The recorded frame maximum still exceeds 6 ms with those settings.
Raw logs and CSVs are retained locally in `.godot/player-optimization/`.

## Validation

The complete local `scripts/run_tests.sh` with extracted assets reports
**3,917 assertions: 3,913 passed and four failed**, across 48 suite files
(46 pass, the existing drop-quality suite fails, one draw-only suite skips).
There are no script/parse/compile errors. Existing headless renderer and
shutdown diagnostics remain; no thresholds were relaxed.

The failures are the same AWP floor/ramp settling checks as before: floor
sleep 1/4 and late drift 0.84306 inches / 0.03031 radians; ramp sleep 0/4 and
drift 0.45922 inches / 0.02737 radians. This patch does not change the drop
solver or those fixtures.

New regression coverage passes 41 animation-parameter, 25 bot-target,
32 shooter-state and nine recoil-constant checks. The animation fixture
compares 216 rendered pose samples against the previous unconditional writer
through movement, crouch easing, jumps, landing, weapon switches and different
advance sizes. It also checks consumed requests and tree/root replacement.
The final fixture cleanup was rerun separately: 41/41 and empty stderr.

Existing model checks pass 253/253, weapon checks 198/198, recoil 88/88,
bot movement 32/32, sight 24/24, the Source course 80/80 and real Dust2
integration 10/10. Independent source reviews found no actionable defect.

## Remaining architectural work

The three local bodies are not interchangeable: the hitbox body uses the
existing pose schedule, the visible lower body has folded bones and a back
bend, and the shadow uses a complete held-weapon pose. Sharing their final
poses blindly would alter behavior. Sharing a suitable common pose needs
explicit separation of authoritative pose data from presentation variants.

Likewise, multiplayer needs tick-owned hitbox poses and separately
interpolated render poses. The current frame-derived hitbox policy is a
documented pre-existing limitation, not corrected or made deterministic by
this cache pass. Keep that migration explicit and test shot outcomes across
render rates before networking acceptance.

CPU execution, presentation pacing and input latency need separate evidence.
The uncapped benchmark disables V-Sync for cost measurement; normal play's
settings must be checked independently. These captures are callback wall
intervals, not OS presentation timestamps, and cannot establish whether
G-Sync is active or prove that tearing has been eliminated.

## Reproduce

Create `.godot/player-optimization/` first. Run each workload serially with
the installed addon and extracted/imported assets. The headless production
profiler measures the actual `run_command`; the attribution profiler mirrors
that small wrapper to time its final model update separately. Its extra
timers add overhead, so use the production run for aggregate simulation cost.

```text
godot --headless --path . --script scripts/profile_box3d_match.gd -- --physics box3d
godot --headless --path . --script scripts/profile_box3d_costs.gd -- --physics box3d
godot --path . --script scripts/profile_combat.gd -- 45 immortal --physics box3d --output .godot/player-optimization/optimized-4k
godot --path . --script scripts/profile_combat.gd -- 45 immortal as-played --physics box3d --output .godot/player-optimization/optimized-as-played
python scripts/summarize_frame_audit.py .godot/player-optimization --output .godot/player-optimization/summary.json
scripts/run_tests.sh
```

Before/after baseline code is `32148f8`; the split parameter timer is this
pass's attribution-only change, also applied to that baseline measurement.
All comparisons use the same executable and graphics. Keep the window
focused for a full recording and retain focus interruptions when they occur.
