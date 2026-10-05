# Subtick friction and movement commands — October 4, 2026

This follows the [ordinary command setup](movement-commands-2026-10-04.md)
in PR #191. It ports the saved ground-friction speed and recurring command
phase, and runs local movement key transitions at their timestamps. The
existing grenade snapshot boundary remains part of the same movement loop.

## Evidence

Installed CS2 build **2000924**, patch **1.41.8.8**, SourceRevision
**11076591**, built October 2. Server SHA-256:
`098d4ddd57e2fbe9a73623a2bf68ebaff86f7b6342ddb3d5a0f69cd6335b31cc`.

Ghidra 12.1.4 exported the accumulated server analysis. **35 function spans
match the currently installed PE bytes exactly**, including every path used
below. Offset searches also found unrelated functions; those matches are
not evidence for this algorithm. Assembly confirms the cache comparisons,
byte flags, float writes and clock setters. Binaries, decoded code and
diagnostic scripts remain uncommitted. This was static analysis.

| Function | Server address | Confirmed behavior |
| --- | --- | --- |
| Command setup | `180adb4a0` | Clear the command's cache-refresh flag at move data `+0x13a` |
| Movement interval reset | `180adb830` | Clear per-interval acceleration/raw wish; retain that command flag |
| WalkMove | `180ae3950` | Compare previous raw horizontal wish and quantized incoming speed; save speed/start phase before friction |
| Ground friction | `180abe710` | Select saved control speed while active, clamp drag against actual speed, retain overshoot |
| Speed quantizer wrapper | `180ad93b0` | Existing 20-bit velocity quantizer |
| Interval finish | `180abe000` | Save raw horizontal wish as last movement impulses |
| Command finish | `180abdf20` | Publish the command refresh flag as the next command's active-cache flag |
| Preprocessing | `180adbdd0` | Request an interval at the saved cache phase |
| Forced boundary insertion | `180c71780` | Sorted unique boundaries; exclude endpoints; inherit the next event look |
| Command event ingestion | `180c77d00` | Narrow `(when + 131072)` to float32, subtract the bias; append tick end |
| Movement loop | `180c68400` | Run up to an event with preceding input; apply the event afterward; group equal phases |
| Interval clock setter | `180c5a210` | Write start/end fractions at move data `+0xdc/+0xe0` |
| Command dispatcher | `180c741b0` | Setup, movement intervals, command finish, then post-movement callbacks |

The server names the movement service fields `m_bUseFrictionStashedSpeed`,
`m_flUseFrictionStashedSpeedUntilFrac`, `m_flFrictionStashedSpeed` and
`m_vecLastMovementImpulses`. WalkMove accesses them at `+0x690`, `+0x694`,
`+0x698` and `+0x7a8/+0x7ac`. The rounding bias at `181923960` is confirmed
as float32 **131072**, giving a 1/64-tick grid with ties to even.

## Ported behavior

At each grounded interval, before friction:

- An active cache whose saved phase differs from the interval start is
  reused, even if input changed inside that span.
- At the saved phase, clear the active flag and quantize current horizontal
  speed. Save a new speed/phase if speed differs from the old saved speed
  or raw world-space wish differs from the previous interval's wish.
- Without an active cache, only a changed raw wish starts a cache.
- A command starts with its refresh flag clear. At command finish, retain
  a cache only if some interval refreshed it. Thus an air-only command
  retires old ground state; noclip, placement and revival clear it too.

Friction still uses `max(control_speed, stop_speed) * friction * surface`
and clamps the drop against actual speed. The continuous drag and overshoot
participate in the existing collision deferral and acceleration math. Both
movement backends carry and compare the cache's active/refresh flags,
phase and speed in their bit-for-bit state checks.
When actual speed is zero but a saved control remains active, the nominal
drop still becomes acceleration overshoot. There is no velocity division
at rest; ignoring that drop would create an extra acceleration burst after
a collision stopped the pawn.

Local input now timestamps all four movement keys in addition to Walk,
duck and jump. Commands retain their final axes/buttons; interval input is
recovered by undoing later edges. Movement runs before applying each edge.
Equal-phase edges form one input state without a zero-duration physics step.
The recorded next-event look is used for its preceding interval, including
forced boundaries. Short taps therefore survive a final released state.
Bot and replay jump builders now keep the final Jump bit consistent with
their press event; the following command releases the one-command press.
The existing grenade launch assertions are unchanged.

Live input uses CS2's 1/64-tick phase grid. Explicit `UserCmd` fixtures can
still supply finer timestamps. A jump pressed exactly at tick end waits
for the next movement interval without consuming its fresh press. Jump
releases update the held state between intervals. Full duck transitions and
modern jump/landing gates are separate work; this ports their input timing.
Same-phase wheel press/release pulses remain fresh jumps, and an endpoint
pulse is carried into the next command even when already released. This
is local edge preservation for the new event loop; it does not claim to
recover CS2's modern jump eligibility or landing windows.

Raw diagonal wish is retained for the cache before normalization/clamping.
Analog command magnitudes are also retained instead of being promoted to
full speed. There are no added collision probes in the cache/input helpers;
an actual event or recurring saved phase can require an additional movement
interval and its ordinary collision/eye queries.

## Validation

The focused suite checks cache reuse, refresh, retirement and forced phase
boundaries; equal-phase and endpoint events; live timestamp rounding;
short WASD/jump taps; Walk/duck timing; zero-speed clamping; noclip reset;
and independently worked acceleration and friction values. Splitting a
200 u/s stop into 1, 4 or 16 intervals yields the same constant saved drag
within float32 accumulation error. The fixture exercises both real Box3D
movement backends and compares the full mutating step state bit for bit.

The final debug/release native builds carry source stamp
`e297eda19841a6f1849aad8907ef26f265893bfb6eacceff6cfe83580e30e67a`.
The full runner passes **8,818 checks across 84 files**, with no script
errors. Three drawing suites skip in headless mode; four existing AWP
drop-settling cases remain reported as known open. This includes **48
subtick-friction checks** with **123 native/script steps identical to the
last bit**, **354 grenade lineup**, **283 simulation**, **138 crouch
movement**, **158 horizontal integration**, **66 command movement** and
**32 native movement** checks. Dust2 route and threaded-match checks pass.
The new loop initially exposed inconsistent synthetic jump builders;
their final button state is corrected without changing launch assertions.
A final lineup rerun after the wheel-edge changes passes all **354 checks**
with **16,743 native/script movement steps identical to the last bit**.

### Paired performance

Separate, otherwise idle native processes ran the seeded ten-player Dust2
fixture in order updated, PR #191, PR #191, updated. Each warms up for
96 ticks and measures 768 `GameWorld.step()` ticks. Both use Box3D and
active terrain eyes. Rendering, audio/UI, pose refresh and Godot's automatic
server step are excluded. The baseline is commit
`e83c9a14d3777eef9d8883f95fc565a508905a70`, source stamp
`76ba47d9c4a369cf1cdd1affa791ed74fedc72607ee336d12b74b7bc5903a7aa`.

| Run | Mean ms | p95 ms | Maximum ms | Movement traces/tick |
| --- | ---: | ---: | ---: | ---: |
| Updated 1 | 2.688 | 3.570 | 4.949 | 44.65 |
| PR #191 1 | 2.636 | 3.553 | 5.931 | 44.66 |
| PR #191 2 | 2.634 | 3.377 | 4.913 | 44.66 |
| Updated 2 | 2.649 | 3.524 | 5.240 | 44.65 |

The paired mean is **2.635 → 2.669 ms**, **+0.034 ms (+1.3%)** for ten
players. Both updated means exceed both baseline means; this is a small
measured increase alongside the new input/cache bookkeeping, not a claim
of zero overhead. The updated means vary by 0.039 ms. Four runs do not
establish the exact attribution or worst-case cost.

All runs fire 22 shots and retain ten players. Terrain casts stay at
16,717; native queries change slightly from 50,294 to 50,291. Query counts
and endpoints reproduce within each version. Raw-input precision changes
some endpoints, so these are comparable match workloads rather than
identical trajectories. Bots mostly issue whole-tick movement inputs;
this benchmark does not bound a player repeatedly inserting interior
movement events. Those events and recurring cache phases can run additional
collision intervals. Local playtest/performance watching remains useful.

## Remaining boundaries

This is the supported ordinary land/air path and digital movement edges.
Subtick analog deltas and pure look-only samples are not yet captured by
the local command format. Use/hostage constraints, water, ladders, moving
platforms, complete duck/root/view transitions and modern landing/bhop
press windows remain outside this port. The jump compatibility flag still
allows a direct body driver to select the older whole-tick jump path.

Scalar arithmetic uses the port's existing precision; the cache and live
phase rounding do not complete CS2's vector quantization or input transport.
Script/native agreement establishes agreement between these two ports.
Paired CS2 counter-strafe/scoped movement captures and local Dust2/Mirage
run/jump smoke playtests remain necessary to establish trajectory parity.
