# Grenade snapshot movement boundaries — October 3, 2026

## October 4: fresh-click jump throws

Sid reported that pressing Space and a fresh left click together was less
forgiving than CS2. The previous landing fixture held the pin before the
jump, so it did not cover that input sequence.

Two corrections now apply on the local movement playtest branch:

- Replay attack-button transitions in timestamp order. A press and release
  inside one command now both take effect, and the throw timer starts at
  the release fraction rather than the command's end. Releasing one mouse
  button retains the other; draw readiness and strength's once-per-tick
  update still apply.
- The release writer's jump eligibility call uses a **0.1-second lookahead**,
  as the timer consumer does. At `1809cd52a`, `MOVAPS XMM1,XMM6` supplies the
  0.1 float before `1809cd530 CALL 180acb810`. The decompiled C omitted this
  argument, causing the original audit and port to use zero. This could
  unnecessarily defer a release just after takeoff by another 0.1 seconds.

The installed server DLL still hashes to
`098d4ddd57e2fbe9a73623a2bf68ebaff86f7b6342ddb3d5a0f69cd6335b31cc`.
Release writer `1809cd2f0` (1,755 bytes), timer consumer `1809c1930`
(980 bytes), and eligibility helper `180acb810` (114 bytes) match the saved
Ghidra instruction spans byte for byte.

The extracted Dust2 fixture now also tests fresh clicks at jump fractions
0, 0.25 and 0.75, with release offsets 0, 8, 11 and 12 ticks. The late
cases near 180–191 ms previously fell off the mid door when command-end
rounding let the saved launch parameters expire. These are local landing
regressions, not measured CS2 input-window or bounce-count equivalence.
The flight, gravity, collision masks and restitution are unchanged.

`watch_grenades.gd` now records the exact input release time, takeoff time
derived from the stash deadline, and their difference alongside launch
and contact telemetry. The next human playtest should establish whether
the timing feel and the remaining mid-door bounce discrepancy are resolved.

Following the Xbox and mid-door screenshots, Sid requested a Ghidra audit
of the remaining jump-throw inconsistency. This report corrects the clock
interpretation in the [initial lineup follow-up](grenade-jump-lineup-2026-10-02.md).
The implementation was initially saved separately because it missed the
mid-door reference. Sid subsequently requested applying it for playtesting.
These movement changes are merged in #184. The subsequent
[CS2 console setup](#cs2-console-setup) resolves the local door miss with
unchanged physics: the earlier Godot screenshot aim was about 0.8 degrees
lower. Surface and landing checks remain strict. Sid subsequently supplied
paired camera/pawn coordinates, and the fixture now uses the exact pawn
origin. Recorded trajectory comparison and general jump validation remain open.
Sid subsequently confirmed that aiming at matching landmarks still requires
an upward correction. The [camera-height follow-up](camera-height-2026-10-03.md)
verifies matching 64/46 base values and a missing ground-topology eye
adjustment that also reaches CS2's jump snapshots. The measured effective
eye height is 60.75; the exact sampler result and its contribution to the
remaining trajectory discrepancy stay open. The
[movement audit](movement-ghidra-2026-10-03.md) also finds horizontal
integration, crouch and modern landing/press-window differences.
The B-doors standing jump landing was accepted in play. Shared terrain-aware
simulation eyes are the next implementation; the earlier experiments and
targeted measurements below retain their original scope.

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
six mid-door failures out of 82 checks before the CS2 console aim was supplied;
they were not suppressed. The full
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

Add `--lineup=mid-door` to start at the paired CS2 pawn coordinates and aim
with a smoke selected. `--lineup=b-doors` prepares the second paired
standing-jump reference described in the [movement audit](movement-ghidra-2026-10-03.md#b-doors-standing-jump-reference).
This optional setup places the player once; local movement settles the feet,
and you supply the throw input.

Records flush during play, allowing the launch and first collision to be
read without closing the game. Diagnostic disk writes are additional work;
use the ordinary watcher for performance comparisons. Throws made directly
through `throw_from` with synthetic parameters should use userid -1: player
metadata reflects the normal command path's selected parameters.

Record the CS2 pawn origin and launch/contact time series for the supplied
console setup, then compare them with the local stationary jump throw.
Those measurements can distinguish camera height, jump-state differences
and collision/flight errors. The recovered clock/boundary behavior is
established; the corrected local lineup is ready for playtesting. General
jump feel and exact recorded trajectory parity still require assessment.

## CS2 console setup

After the trail made the first door-side contact visible, Sid supplied this
CS2 command output:

```text
setpos -344.002014 -660.031250 150.361557;setang -15.030418 92.595718 0.000000
```

`SourceEntities.to_game` maps Source X/Y/Z to Godot Z/X/Y, yaw adds 180
degrees, and upward pitch changes sign. The known horizontal point is
therefore Godot X/Z `(-660.031250, -344.002014)`, yaw **272.595718**,
pitch **15.030418**. The previous local preset used pitch 14.2; the latest
recorded user throw used 14.244. These are different launch inputs.

Plain `getpos` reports a cached camera position; `getpos_exact` reports the
pawn origin. At this stage the local preset and fixture retained their
verified grounded height **89.8** while awaiting the latter. The supplied
camera Z was not treated as the pawn's feet or converted by assuming an
eye offset. The paired-coordinate follow-up below supersedes this setup.

At the supplied horizontal point and the local grounded height:

| Local jump replay | First contact | Rest |
|---|---|---|
| Godot screenshot pitch 14.2 | Door side `(1585.447, 41.77911, -445.8009)` | Floor `(1481.398, -124.6448, -423.4414)` |
| CS2 console pitch 15.030418 | Door top `(1592.765, 51.36539, -446.124)` | Door top `(1592.502, 50.5321, -456.8343)` |

The corrected local throw settles after **4.421875 seconds**. No changes
to jump movement, grenade speed, inherited velocity, gravity, bounce or
collision masks were needed. Updating the fixture to the supplied aim
initially passes all 82 checks; expanding the door to jump fractions
0, 0.25 and 0.75 crossed with release offsets 0, 2 and 8 ticks passes
**130 checks**, with **7,383 script/native movement steps** agreeing bit
for bit. The nine Xbox cases and sky/grenade-clip queries remain covered.
This explains the local miss under the earlier aim; it is not a measured
CS2 launch/contact trajectory match.

### Paired-coordinate follow-up

Sid subsequently supplied:

```text
setpos -344.012573 -660.031250 150.364380;setang -14.960024 92.602875 0.000000
setpos_exact -344.012573 -660.031250 89.614380;setang_exact -14.960024 92.602875 0.000000
```

The watcher and fixture now use that exact pawn origin and aim. The local
mid-door throw still settles on the door, near
`(1594.406, 50.5391, -456.7559)`, after **4.390625 s**. The measured
stationary eye offset is **60.75 units**; the terrain sampler remains
unported. The [movement follow-up](movement-ghidra-2026-10-03.md) records
the takeoff transition and additional integration differences, plus the
B-doors standing jump reference. The three-fixture suite now passes
**201 checks** and **12,339 bit-identical native/script movement steps**.
Runtime movement and grenade flight remain unchanged in this follow-up.

For the height distinction, the imported client's `180c0ccf0` reads cached
camera values for `getpos` and calls the pawn-origin getter for the exact
variant. The current client's corresponding body is at `180c0cc00`: its
351-byte instruction layout matches apart from ten RIP-relative/call
addresses, whose operands were checked against current command strings.
The client module SHA-256 is
`d7db25d48f1d10c5e0b0296e20ed803426eb9509da41760daeda39dd35ba89b9`.
This relocated body is not described as byte-identical. Local exports
and instruction listings remain ignored.

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
