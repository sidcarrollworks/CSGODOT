# Grenade snapshot movement boundaries — October 3, 2026

Following the Xbox and mid-door screenshots, Sid requested a Ghidra audit
of the remaining jump-throw inconsistency. This report corrects the clock
interpretation in the [initial lineup follow-up](grenade-jump-lineup-2026-10-02.md).
The implementation was initially saved separately because it missed the
mid-door reference. Sid subsequently requested applying it for playtesting.
The branch now runs these movement changes; the landing discrepancy remains
open and its checks remain strict.

## Binary identity and method

The installed CS2 build is **2000924**, patch **1.41.8.8**, SourceRevision
**11076591**, built October 2 at 14:45:21. Installed `server.dll` SHA-256:

`098d4ddd57e2fbe9a73623a2bf68ebaff86f7b6342ddb3d5a0f69cd6335b31cc`

Ghidra 12.1.4 processed the existing server project read-only, without
reanalyzing it. Its imported binary has SHA-256
`3541e46a3193fcf1151e97ce19cd4daf86c5fdb2889033c2bab1d4cc7f555b9c`.
All **28 exported function spans** checked in this pass match the installed
module byte for byte at their original addresses. Instruction listings were
checked alongside the decompiler, particularly where it omitted floating-point
arguments carried in XMM registers. No DLL was executed or attached to CS2.
Valve binaries, function exports and decompiler output remain uncommitted.

## The clock is scoped to each movement segment

The earlier report correctly identified subtraction, but incorrectly treated
`180921a10` as a simulation-tick-to-time conversion. With a nonzero pawn tick
argument, this helper reads the scoped globals' **current time at +0x30**.
It does not multiply that argument by the tick interval.

`180c68400` identifies itself through its embedded profiling string as
`CPlayer_MovementServices::DoMovement::Subtick`. For each movement segment,
it sets current time to that segment's end and frame time at **+0x34** to
its duration, calls movement setup, movement and movement finish, then
restores the clock. Button changes are applied at the intervening boundaries.

Consequently the recovered jump formula means:

```text
stash = segment_end_time - segment_duration + 0.1 seconds
      = actual_takeoff_time + 0.1 seconds
```

The jump fraction therefore affects this clock through movement segmentation.
Using the whole tick's end and duration, as the current port does, loses it.

## CS2 explicitly inserts the stash boundary

| Address | Verified role |
|---|---|
| `180ab57f0`, `180adf830` | Schedule movement-service stash time at +0x68c, copy it to the pawn and clear snapshot validity. |
| `180adbdd0` | Convert the stash deadline to tick/fraction; when it lies in the current movement tick, request a boundary at that fraction. |
| `180c4ad20` | Convert float simulation time to tick/fraction using the 1/64-second tick interval. |
| `180c71780` | Insert a boundary into the ordered movement-step list; reject duplicate boundaries and endpoints 0/1. |
| `180c68400` | Run the actual movement and finish callback for each segment, with its own clock scope. |
| `180abe000` | Publish moved origin/velocity, compare the completed segment against the deadline, invoke the snapshot writer and invalidate the pending service timer. |
| `180add6f0` | Save aim, eye, center and pawn velocity; verified in the earlier audit. |

This is an actual collision-aware movement split. Saving interpolated positions
or rewinding velocity at a whole-tick finish would not reproduce collisions,
ducking or movement changes inside that interval. It adds a boundary once at
the scheduled capture time, rather than requiring a higher global tick rate.

## The ordinary jump also differs from our Source ordering

Both recovered jump paths adjust the ordinary standing jump's impulse by:

```text
adjusted_impulse = sv_jump_impulse - gravity * 0.5 * (1/128 second)
```

The current module constants at `18177e57c` and `18179eec0` read as **0.5**
and **0.0078125**. At gravity 800 this subtracts **3.125 u/s**. Special
movement/ground branches can bypass it; this finding is not a complete port
of moving platforms, water, bunny-hop penalties or crouch transitions.

The air path `180adc620` calls `180ab0670`, which applies full interval
gravity to velocity. It temporarily offsets half the interval's acceleration
for displacement, then `180ad8040` restores that offset to the final velocity.
The new jump setter `180ada250` clears the acceleration bookkeeping when it
sets velocity. Our Verlet step is equivalent for an ordinary unobstructed
air interval, but our default jump overwrites its leading half-gravity and
never puts it back. Its first interval consequently gains a duration-dependent
velocity bonus. Correcting capture time alone cannot remove that bonus.

## Tested candidate and the unresolved landing

A local candidate implemented the actual movement boundary, captured the
post-collision state before running the remainder, scheduled from the actual
takeoff fraction and applied the recovered ordinary jump adjustment in both
script and native movement. Snapshot hooks ran outside the native/script
comparison so they were invoked only once.

Results at the screenshots' rounded HUD inputs:

| Case | PR #184 runtime | Audited candidate |
|---|---|---|
| Xbox, jump fractions 0 / 0.25 / 0.75 | Saved upward speeds 220.743 / 222.3055 / 225.4305 u/s; all land on Xbox, at different points. | About 218.868 u/s for all three; all land near `(1437.39, -26.917, -308.783)`, within 0.002 units of one another. |
| Mid-door, fraction 0.25 | Rests on the open door at `(1591.739, 50.5113, -457.0676)`. | Rests on the floor at `(1481.633, -124.642, -423.4322)`; misses the intended door landing. |

All three eligible release offsets (0, 2 and 8 ticks) repeat each result.
The broader diagnostic also gives the candidate's same mid-door trajectory
at jump fractions 0 and 0.75. That is timing consistency, **not CS2 lineup
parity**. The reference has no exact CS2 starting position, aim, throw input
sequence or launch-state recording. A stationary left-click jump throw is
the current assumption for the second screenshot.

Candidate verification:

- **202 simulation checks passed**, including an actual held grenade, jump,
  delayed capture and retained aim; 6,202 script/native steps agreed.
- **32 native movement checks passed**; 49,029 script/native steps agreed.
- The unchanged **82-check landing regression failed six checks**: the
  mid-door surface and rest-region checks for three releases. Xbox and
  sky/grenade-clip checks passed; 5,310 script/native steps agreed.

The initial candidate was saved locally at
`.godot/grenade-timing-audit/grenade-subtick-candidate.patch`, based on
`eebdbc914c5ec1e746344e72d30144d7b41af9ec`. Before the playtest request,
it was removed from the runtime. After restoring that runtime and rebuilding its native library,
all **82 landing checks passed again**, with 5,037 script/native steps agreeing.
No global bounce coefficient was fitted to compensate for either result.

## Applied for playtest

At Sid's request, the branch now applies the snapshot boundary and ordinary
jump correction in script and native movement. The simulation suite exercises
jump fractions 0, 0.001, 0.25, 0.6, 0.75 and 0.999, including a snapshot exactly
on a tick boundary. It checks the saved deadline, airborne position/velocity,
delayed release and retained aim through the real held-grenade path. Native
movement comparisons cover both the new default and the legacy jump mode.

`MovementConfig.cs2_jump` defaults to true. Its false setting retains the
older Source ordering and the existing optional textbook correction for
comparisons/custom modes. The legacy course's Source-height tests explicitly
select that mode. General jumps therefore also change under the new default;
standing jump height and ledge reach belong in this playtest, alongside grenades.
Only the snapshot's scheduled tick gains an additional collision-aware movement
step; the global tick rate, grenade gravity and bounce coefficient stay the same.

Focused verification of the applied playtest version passed **243 simulation**,
**80 movement**, **32 native movement**, **45 grenade timer/port** and
**68 native query/gameplay** checks. The simulation suite's six jump phases
all keep the expected 100-ms eye height and vertical velocity. Its 6,690 steps,
the native course's 49,567 steps and the movement course's 1,358 steps agree
between script and native movement. The landing suite still reports the same
six mid-door failures out of 82 checks; they are not suppressed. The full
suite was stopped to prioritize getting the playtest running and is not claimed
as passing for this implementation.

## Next validation

Sid's follow-up playtest still missed the door and appeared to rebound
earlier. Replaying the current defaults at the rounded screenshot inputs
identifies the stationary jump throw's first contact as
`physics_group_wood_dense`, the **door's side**, near
`(1585.539, 41.413, -445.985)` after about **3.58 seconds**. Its normal is
`(-0.893376, 0, -0.44931)`. A standing throw instead first contacts nearby
concrete near `(-401.062, 237.265, -355.769)` after about **0.39 seconds**.
Neither replay contacts `physics_sky`. These distinguish two local paths;
they do not identify the collision in Sid's actual throw.

The subsequent diagnostic practice run recorded two actual full-strength
jump throws. Both used the saved jump snapshot, with upward pawn velocity
about **218.868 u/s**, and first contacted `physics_group_wood_dense` after
**3.578125 seconds**. Their contact heights were **42.379** and **40.550**
units, with the door-side normal above. They then bounced onto the ground.
Neither recorded a sky contact or blocked launch. This confirms the same
remaining door-side miss in actual play, rather than a failed snapshot or
the old sky brush collision.

`scripts/watch_grenades.gd` extends the performance watcher to record exact
launch position/velocity, the player's current state, selected launch
parameters, jump-snapshot eligibility and contact position/normal/material.
It observes entity spawning before flight starts and deduplicates bounce
events within a tick. Contact times and velocities are tick-end values,
not exact collision instants or per-contact incoming/outgoing velocities.
It does not change movement, flight or collision queries. Start a diagnostic
practice run with:

```text
godot --path . --script scripts/watch_grenades.gd -- --mode practice --map de_dust2 --movement native --window=1920x1080 --grenades=.godot/grenade-throws.jsonl
```

Add `--lineup=mid-door` to start at the screenshot's rounded position and
view angles with a smoke selected. This optional setup only places the player
once; you supply the throw input.

Records flush during play, allowing the launch and first collision to be
read without closing the game. Diagnostic disk writes are additional work;
use the ordinary watcher for performance comparisons. Throws made directly
through `throw_from` with synthetic parameters should use userid -1: player
metadata reflects the normal command path's selected parameters.

Record the exact CS2 position, view angles and throw input sequence for the
mid-door lineup, then compare launch position/velocity and first contact
before its final landing. Confirm whether it is stationary, moving or
crouched and whether it uses a jump. Those measurements can distinguish
rounded setup inputs, jump-state differences and collision/flight errors.
The recovered clock/boundary behavior is established. The applied implementation
is ready for local playtesting; merging it still requires assessing the
demonstrated landing regression and general jump feel.

For subsequent builds, recheck binary identity before reusing any address.
The selected functions can be exported with the repository's
`scripts/shooting_audit/AuditDecompile.java` and the read-only workflow in
[the audit tools README](../../scripts/shooting_audit/README.md).

The 28 spans compared in this pass were:
`180ab57f0`, `180adf830`, `180ad5510`, `180ad89b0`, `180abe000`,
`180c7fe60`, `180921a10`, `180c741b0`, `180c75ce0`, `18017d1f0`,
`18091a700`, `1813b7510`, `180c4ad20`, `180c68400`, `180c688a0`,
`180c59be0`, `180c5a210`, `180adbbd0`, `180adbdd0`, `180abf5d0`,
`180c71780`, `180adc620`, `180ab45d0`, `180ab4c40`, `180ad5fb0`,
`180ab0670`, `180ad8040` and `180ada250`.
