# Combined horizontal movement integration — October 3, 2026

The movement segment now carries combined ground acceleration/friction and
deferred velocity through collision in both GDScript and native movement.
This corrects displacement and collision ordering that final-speed checks
alone could not detect. Gravity uses the same deferred state. Camera/terrain
updates and grenade capture run after restoration, once per segment.

This is an ordinary walk/air integration port, not complete CS2 movement
parity. Current command speed scales and crouch transitions remain in place.

## Evidence

Read-only Ghidra 12.1.4 exports and direct PE reads use the installed October 2
server: build **2000924**, patch **1.41.8.8**, SourceRevision **11076591**.
SHA-256:
`098d4ddd57e2fbe9a73623a2bf68ebaff86f7b6342ddb3d5a0f69cd6335b31cc`.

Recovered methods include friction `180abe710`, ground acceleration
`180ab00d0`, walk move `180ae3950`, air acceleration `180ab07c0`, air move
`180adc620`, gravity `180ab0670`, collision movement `180adffc0`, restoration
`180ad8040`, step retry `180addb20` and axis reset `180ada250`. Saved movement
spans and the ten newly exported ground helper/default spans match current
server bytes. Valve binaries, Ghidra projects and decompiled exports remain
uncommitted. No Valve DLL was executed or debugger attached.

## Ground segment

The three local fields correspond to movement state `+0x108..+0x110`
(acceleration), `+0x114..+0x11c` (deferred velocity) and `+0x128` (friction
overshoot). Each segment starts fresh.
The generic movement loop `180c68400` dispatches setup once per interval
through the movement-services vtable at `+0x118`. Current CS player setup
`180adb830` explicitly zeros these fields; state does not carry from an
earlier interval into the next one.

Friction measures actual velocity magnitude for the stop clamp, but uses
the recovered velocity quantizer for control speed. This is a 20-bit range
from -16384 to +16384 with exact-zero encoding. Its offset grid is different
from rounding speed to 1/32. Constructor `1803ba450`, range-multiplier helper
`1803bff40` and quantize helpers `1803bb390`/`1803bb200` establish the arithmetic.
The ordinary pawn friction multiplier defaults to one (`180cd630c`).

With speed `s`, control `Q(s)`, friction `f` and interval `dt`:

```text
drag_rate = max(Q(s), stop_speed) * f * surface_friction
drop = drag_rate * dt
acceleration -= normalize(v) * min(drag_rate, s / dt)
overshoot = max(drop - s, 0)
v *= max(s - drop, 0) / s

rate = min(max(acceleration_scale * accelerate * surface_friction
               - overshoot / dt, 0), available_wish_speed / dt)
acceleration += wish_direction * rate
v += wish_direction * rate * dt
```

Zero speed, nonpositive duration and the control-speed `<0.1` threshold
take their respective early exits. A total-speed clamp contributes its
actual velocity correction divided by `dt` to acceleration as well.

Before collision, `half = acceleration * dt * 0.5` is subtracted from
velocity and added to deferred velocity. Movement uses that intermediate
velocity; restoration adds deferred velocity afterward. Walk's `<1 u/s`
early stop checks `v_mid + acceleration * (1/64 - dt/2)`.
Current helper `180301fe0` returns fixed **1/64**, while `180ac04d0` reads
the current segment duration. Subdivided segments must use this prediction
rather than testing only their current endpoint speed.

For a clear 64-Hz segment from rest with wish speed 250 and accelerate 5.5,
terminal speed is **21.484375 u/s**. Displacement is now **0.1678466796875**
units, compared with **0.335693359375** when all acceleration preceded motion.
Coasting from 50 u/s ends at 43.5 and moves **0.73046875** units.

## Air segment and gravity

Air acceleration splits its additions against the cap separately:

```text
available = min(wish_speed, air_max_wishspeed) - dot(v, wish_direction)
full = wish_speed * air_accelerate * surface_friction * dt
before = min(available, full / 2)
after = min(available - before, full / 2)
v += wish_direction * before
deferred += wish_direction * after

v.y -= gravity * dt
acceleration.y -= gravity
half = acceleration * dt / 2
v -= half
deferred += half
collide_and_slide(v)
v += deferred
```

Nonpositive available speed adds nothing. Air acceleration is not added to
the continuous acceleration vector. With perpendicular wish speed 250,
air acceleration 12, friction one and `dt=1/64`, movement adds **23.4375**
u/s, restoration adds **6.5625**, and the terminal addition is **30**.
The displacement addition is **0.3662109375**, rather than **0.46875**.
If only ten units of cap remain, all ten precede motion and none are deferred;
averaging the initial and final velocities would be incorrect.

There is no independent trailing gravity half-step. The CS2 jump impulse
retains its fixed half-1/128 gravity adjustment; explicit legacy jump options
retain their previous first-segment arcs through a compatibility adjustment.

## Collision ownership

Ordinary collision planes clip intermediate velocity only, leaving
acceleration/deferred state intact. A wall slide can therefore publish a
small component toward the wall after restoration. Clipping that deferred
component on every contact would change the recovered algorithm.

Hard stops clear velocity, acceleration and deferred velocity together:
exhausted planes, unresolved creases, reversed motion and obstructed zero
progress. A stationary intermediate velocity with no attempted contact
preserves deferred velocity, including at the exact gravity apex.
Box3D's unresolved zero-normal overlap retains the existing stopped-body
fallback. Ground categorization clears the vertical components of all three
states when support is found.

Step retries save/restore position and velocity only. A hard stop's cleared
acceleration/deferred state persists across the alternative attempt, as in
`180addb20`; the port does not save whole state independently per candidate.

WalkMove also retries a failed raised path when the original midpoint speed
is positive but below **64 u/s** and movement input is held. It scales the
saved midpoint velocity to 64 and repeats only the raised path from the
original position. `sv_step_move_vel_min`, registration `1800cac40`, supplies
that default. Valid downward landings require positive commanded travel;
a valid landing suppresses retry even if the flat candidate wins.

This branch matters with Box3D's larger clearance: a rest-start midpoint
moves only 0.1678 units, shorter than its roughly 0.257-unit wall separation.
Without the retry, the existing 16-inch stair fixture became permanently
stuck; with it, the body climbs. The fixture allows 48 rather than 40 approach
ticks while retaining its position, height and grounding requirements.
The larger backend clearance can still force a stop/re-acceleration at an
edge where Source's smaller backoff would not; stair feel needs playtesting.
Integration arithmetic adds no casts on a clear path. A failed low-speed
step can add one bounded raised retry; these casts are counted normally.

## Bot recovery regression

The first full run exposed a deterministic Dust2 route stall. At
`(2705.255, 139.243, 848.1434)`, two steep planes stopped a bot with no
walkable support. The new hard stop correctly cleared gravity along with
the other deferred state; the previous independent gravity tail had nudged
this corner. Bot recovery sampled only grounded velocity and missed the
airborne wedge, producing a 6.8-second stall. The same route passed on
merged `22b6f93`.

`PlayerBody.blocked_air_move()` exposes a completed, unsupported hard stop:
positive gravity, noclip off, known post-move grounding state, and exactly
zero velocity, acceleration and deferred velocity. Normal flight and a
zero-velocity apex retain gravity state and do not qualify. Bots admit
that state to their existing speed window and wiggle recovery. No extra
query, steering distance, recovery timer or stall threshold is introduced.
The original three-second route limit remains unchanged.

## Validation and performance

Final local validation used Godot 4.7.2, the extracted assets and Box3D,
with both native debug/release libraries rebuilt from the final sources.
`scripts/run_tests.sh` passed **8,089 checks across 82 files**. Three draw-only
files skip headless; the four previously recorded AWP drop-settling cases
remain known open. Eligible movement steps were compared with the script
to the last bit, including 49,567 in the native movement course and 19,250
in the Dust2 bot route.

The new horizontal suite passes 158 checks covering independent quantizer
and displacement oracles, overshoot, subticks, caps, real wall/overlap
contacts and deferred-state lifetime. Bot movement passes 40 checks,
including actual airborne collision recovery and exclusions for fresh
spawns, apexes, falls, noclip and zero gravity. Simulation passes 279 checks,
including moving jump-throw snapshots and their 1.25 velocity inheritance.
Grenade lineups pass 246 checks; crouch movement passes 138. The existing
clear-path and stair query budgets remain unchanged.

The paired cost comparison uses merged `22b6f93` as baseline, with terrain
sampling active in both builds. `scripts/profile_ground_eyes.gd` runs ten
players on Dust2: seed 20260926, 96 warmup ticks, 768 measured ticks, a gun
drop, HE throw and staged engagement. Both repetitions of each build report
22 shots, ten survivors, zero legacy queries and identical endpoint/cast
records within that build. Endpoints differ between builds because the
movement integration changes displacement and subsequent bot commands.

Serial order was current / baseline / baseline / current:

| Build/run | Mean tick (ms) | p95 (ms) | Maximum (ms) | Mean hull traces | Maximum hull traces |
|---|---:|---:|---:|---:|---:|
| Current 1 | 2.669 | 3.430 | 5.578 | 46.35 | 102 |
| Baseline 1 | 2.557 | 3.478 | 5.419 | 45.47 | 95 |
| Baseline 2 | 2.544 | 3.289 | 5.279 | 45.47 | 95 |
| Current 2 | 2.653 | 3.541 | 4.947 | 46.35 | 102 |

Mean tick cost is **2.661 vs 2.5505 ms**, an increase of **0.1105 ms (4.3%)**
in this fixture. Mean hull traces rise by 0.88; terrain casts are 17,858 vs
17,846 over 768 ticks, and native queries are 51,166 vs 50,928. The new
acceleration/state bridge, bounded stair retry and changed routes contribute
work, but this aggregate comparison does not isolate their individual cost.
An earlier exploratory pair measured only +0.024 ms; these final repeats
record the observed increase rather than asserting no regression.

This times `GameWorld.step`, excluding rendering, UI/audio/pose callbacks
and the engine's automatic physics step. It is a short headless simulation
comparison, not rendered-frame acceptance or proof of the 6-ms maximum
target. Counter-strafing, stairs, wall/slopes and moving jump throws still
need playtesting and paired CS2 captures.

Reproduce on each separately built checkout, alternating runs:

```sh
godot --headless --path . --script scripts/profile_ground_eyes.gd -- --physics box3d --movement native
```

Native source stamps:

- Current: `777e0d99fd0761972d4fc53ee7d60b53d2ee1f10806442127c6596a2317f936d`.
- Baseline: `c36865cfb92e6943c9f8e0b7eefe41f79cfd291149ca6d0b6bb1082aa5a53d01`.

Local logs are retained under `.godot/horizontal-full-tests-final.log` and
`.godot/horizontal-final-profile-{current,baseline}-{1,2}.{out,err}.log`;
they are not committed. The profiling fixture emits the full endpoints
and workload summary along with its timing lines.

## Remaining boundaries

- The command path retains existing acceleration scales and the gradual
  crouch residual-speed cap. CS2's ordinary walk scale (130), five-unit goal
  taper, special scoped weapon branches, friction stashing and absolute
  movement-speed-cap setup still need their command/state port.
- Full duck/root/view transitions, repeated-input gates and modern landing/
  bhop windows remain the next movement stage. The modern air-landing special
  movement branch is not included here.
- Source base velocity, moving-platform semantics and complete collision
  backoff/quantization remain differences, including the recovered small
  outward velocity and next-endpoint biases. Ground quadrants still use the
  existing corner-ray approximation. This port does not infer material
  friction from older Source 1 tables.
- Script/native bit agreement and recovered numeric oracles establish local
  implementation consistency. Recorded CS2 paths, especially the mid-door
  visual aim discrepancy and additional Mirage throws, remain playtest work.
