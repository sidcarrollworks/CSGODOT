# Current CS2 movement audit — October 3, 2026

Sid requested rechecking movement against Ghidra after supplying paired
camera/pawn coordinates for the Dust2 mid-door smoke. The movement port
predates the binary audits; matching its native and script implementations
does not establish CS2 parity. This pass examines the ordinary walk/air,
ground, crouch and jump paths. It records differences without changing the
runtime solver or choosing new physics values by eye.

## Evidence and scope

Installed CS2 build **2000924**, patch **1.41.8.8**, SourceRevision
**11076591**, built October 2, 2026. Server SHA-256:

`098d4ddd57e2fbe9a73623a2bf68ebaff86f7b6342ddb3d5a0f69cd6335b31cc`

Ghidra 12.1.4 processed the existing server project read-only. The accumulated
server audit now covers **97 distinct function spans**, all matching the
installed module byte for byte. Current PE constants and assembly were
checked alongside pseudocode, including floating-point arguments omitted
by the decompiler. Binaries, decompiler output and diagnostic helpers remain
uncommitted. No Valve DLL was executed or debugger attached to CS2.

This is not a complete reimplementation of every movement mode. Moving
platforms, ladders, water, collision-backend equivalence, velocity
quantization and all jump/landing branches require further work.

## Confirmed differences

| Area | Installed CS2 | Our current implementation | Consequence |
|---|---|---|---|
| Ground-dependent eyes | Topology/root adjustment assembled during movement finish, before grenade capture | Base 64/46 eye heights with a duck spline | Landmark aim and standing/crouched launch eyes can differ on slopes and edges |
| Air acceleration | Applies part before collision movement and defers the remainder until after it | Applies the full capped addition before moving | Matching final speed can still produce different displacement and contacts |
| Ground acceleration/friction | Tracks acceleration and a deferred velocity contribution; collision movement uses an intermediate velocity | Friction and acceleration update velocity fully before movement | Starts, stops and running throws can sample different positions |
| Crouch | Separate duck amount, duck speed, root and view state; repeated-duck gate | A fixed 0.4-second progress and immediate airborne hull/eye changes | Crouch-jump geometry and camera transitions differ |
| Jump/landing | Modern press/landing time state and a bhop window; ordinary impulse already recovered | Ordinary impulse and grenade deadline splits are implemented; no complete modern landing/press-window port | An ordinary stationary jump passing does not validate chained hops or landing slowdown |
| Ground queries | Grounded step-size reach, inset vertical hull and recovery/quadrant branches | Two-unit categorization plus a separate walking snap and Box3D recovery | Broad Source resemblance does not establish identical edge/step contacts |
| Collision response | Four bumps, accumulated planes, a 0.03125-unit backoff and movement-state updates | Four bumps/five planes, velocity clipping without that backoff | Contacts and crease/ramp exits require comparison, including backend tolerances |

Base eye/hull values and the broad acceleration model are compatible with
ours. CS2 still resets surface friction to 1 and uses **0.25** when an
upward-moving pawn fails to find walkable ground; the ordinary upward
ground-query cutoff remains **140 u/s**. These are not grounds for disabling
dead-strafe behavior or replacing all movement constants.

## The exact door reference

Sid supplied both commands from the same position and aim:

```text
setpos -344.012573 -660.031250 150.364380;setang -14.960024 92.602875 0.000000
setpos_exact -344.012573 -660.031250 89.614380;setang_exact -14.960024 92.602875 0.000000
```

The effective eye offset is **60.75 units**, or **3.25 below** the standing
64-unit base. The Godot fixture now uses the actual pawn origin
`(-660.031250, 89.614380, -344.012573)` with yaw `272.602875` and pitch
`14.960024`, rather than estimating the origin from the camera.

An isolated native collision probe settled that pawn near
`(-660.0313, 89.81289, -343.9957)`: about **0.20 units above** the CS2
origin, with a small horizontal recovery. The local ground is sloped;
neither camera height nor collision clearance should be inferred from the
floor's center point alone.

A scratch 5-by-5 probe using thin boxes and the extracted collision produced
an approximate **2.81-unit** topology drop, short of the measured 3.25-unit
eye deficit. This probe is **not** a port of Source's zero-height square
casts, exact filter/masks or full sample-selection rules. It confirms that
a simple terrain approximation is insufficient to claim a match. Do not
hard-code the difference into the camera or launch position.

### Why a lower standing camera may not fix this jump throw

The camera audit establishes that simulation eyes reach grenade snapshots.
However, `180ae23e0` also removes the topology transition residual after
takeoff with:

```text
rate = max(abs(vertical_velocity) * 0.5, gravity * 0.05)
residual = Approach(0, residual, rate * segment_duration)
```

`180178b30` is the maximum helper, `1808a7be0` clears the sign bit, and
`180459e20` is Approach. At gravity 800 the minimum rate is **40 units/s**.
If the entire 3.25-unit deficit is an ordinary terrain/root residual, it
clears within **81.25 ms** even at that minimum rate, before the grenade
snapshot at takeoff plus **100 ms**; rising jump velocity clears it faster.
This assumes an ordinary standing takeoff without other root/view offsets.

Thus the measured stationary eye gap explains a visual setup difference,
but alone is not proof of an incorrect saved eye height for a stationary
jump throw with exact angles. Horizontal integration differences likewise
do not affect a stationary jump with no horizontal input. Recorded CS2
launch/contact data is still needed to attribute the remaining door miss.

### Live landmark-aim comparison

Sid confirmed that the B-doors throw lands perfectly in the rendered game,
while the mid-door landmark setup still misses. The same practice run
records the B-doors jump using its snapshot and settling near
`(2159.795, 234.001, -1336.495)`. The two mid-door misses also use the
snapshot, with inherited vertical speed **218.868 u/s**, but their upward
aim differs from the supplied **14.960024-degree** CS2 reference:

| Live mid-door throw | Upward pitch | First door-side contact height |
|---|---|---|
| First | 14.273711 | 43.4506 |
| Second | 14.493711 | 46.0617 |

Both hit the vertical wooden side; the door-top contacts are near height
51. The local fixture using the supplied exact angle lands on top. This
distinguishes the observed landmark miss from a failure to use the saved
jump state.

A diagnostic ray from the supplied CS2 camera and aim through the extracted
local collision reaches `(-396.881, 220.7512, -355.9754)`, approximately
**263.42 horizontal units** away. Our standing eyes near this setup are
height **153.825**, about **3.46 units above** the CS2 camera's **150.3644**,
including the small pawn-origin difference. Aiming at that same point from
the local eyes requires upward pitch **14.24359**, about **0.71644 degrees
lower**. That is close to the first recorded miss's 14.273711.

At B-doors, local standing eyes are height **192.2962**, versus the supplied
CS2 camera's **192.0148**. Its analogous local collision target is about
**965.07 horizontal units** away, and the same-point pitch changes by only
**0.01782 degrees**. This explains why the camera discrepancy can affect
the close mid-door landmark much more than the working B reference.

These rays use the locally extracted collision, not a captured CS2
crosshair hit. They give concrete support for a visual-origin/aim mismatch
in the recorded throws; they do not establish complete CS2 flight parity
or the exact terrain sampler result. The next implementation target is
the shared terrain-aware eye state and its transitions. Do not compensate
with a per-lineup pitch correction or a universal eye-height reduction.

## B-doors standing jump reference

Sid supplied a second paired setup and confirmed a standing jump throw:

```text
setpos -1667.957031 -256.021118 192.014847;setang -14.713711 82.148254 0.000000
setpos_exact -1667.957031 -256.021118 128.077347;setang_exact -14.713711 82.148254 0.000000
```

The effective eye height is **63.9375**, only 0.0625 below the standing
base. This contrast with the mid-door setup rules out applying a universal
3.25-unit camera reduction. The Godot setup uses pawn origin
`(-256.021118, 128.077347, -1667.957031)`, yaw **262.148254** and pitch
**14.713711**. Local collision settles the feet near height **128.2962**.

The current stationary jump replay already reaches the roof above B doors:

| Local contact | Position | Surface |
|---|---|---|
| Upper roof | `(1575.847, 418.001, -1415.348)` | Concrete |
| Wooden awning | `(1947.257, 348.8081, -1364.131)` | Wood |
| Roof above gate | `(2103.201, 234.001, -1342.626)` | Concrete |

It settles near `(2159.453, 234.011, -1334.869)` after **7.109375 s**.
The surface sequence and destination are consistent with Sid's screenshot;
there is no recorded CS2 contact time series to establish exact parity.
No movement or grenade-flight parameter changed to obtain this result.

Prepare this point, aim and selected smoke for manual testing with:

```text
godot --path . --script scripts/watch_grenades.gd -- --mode practice --map de_dust2 --movement native --lineup=b-doors --grenades=.godot/b-doors-throws.jsonl
```

The watcher places the player once. Supply the stationary jump/release input;
practice's grenade trails show the actual contacts.

## Horizontal integration evidence

`180adc620` calls air accelerator `180ab07c0`, gravity helper `180ab0670`,
the collision mover `180adffc0`, then restore helper `180ad8040`.
The accelerator computes the same projected wish-speed cap as Source, but
splits the velocity addition:

```text
available = capped_wish_speed - dot(velocity, wish_direction)
full = air_accelerate * wish_speed * surface_friction * dt
before_move = min(available, full * 0.5)
after_move = min(available - before_move, full * 0.5)
```

The later contribution occupies movement state `+0x114..+0x11c`. The
restore helper adds it after collision movement. Gravity's half-displacement
adjustment shares this state; it is not safe to add a second independent
half-gravity correction when porting horizontal integration.

For an unobstructed perpendicular air input at wish speed 250, acceleration
12, friction 1 and a 1/64-second segment, both paths add **30 u/s** in total.
CS2 moves with **23.4375 u/s** of that addition; ours moves with all 30.
The displacement from the addition is **0.3662109375** versus **0.46875**
units. This worked example isolates the equations, without claiming a full
collision or quantization replay.

Ground friction `180abe710` builds acceleration at `+0x108..+0x110` as well
as updating velocity. Ground accelerator `180ab00d0` adds to that state,
uses weapon/walk/duck branches and accounts for friction overshoot. Walk
move `180ae3950` temporarily subtracts half the interval's acceleration
and stores it for restoration. A faithful port needs the combined state,
including its treatment during blocked movement, rather than averaging
the start/end velocities only on clear paths.

## Crouch, ground and modern jump evidence

Crouch method `180abb2c0` maintains duck amount `+0x40c`, duck speed
`+0x410` and transition state, with collision-tested finish/unduck helpers.
The eye updater separately approaches duck root to zero over **0.1 s**
and the 18-unit duck view change over **0.2 s**. Registration `1800cae40`
sets `sv_timebetweenducks` to **0.4 s**. That repeated-input gate is not
the same thing as our fixed 0.4-second interpolation duration.

Ground categorization `180ab45d0` resets friction, handles relative upward
speed, traces with a vertically inset hull and falls back to quadrants.
It uses `sv_stepsize` for the grounded reach; registration `1801051e0`
still defaults that to **18**. `180adffc0` confirms four move bumps and
the **0.03125** backoff constant. Neither observation proves Box3D's
sweep margins equal Source's trace semantics.

Registration `1800ca2c0` confirms `sv_legacy_jump` defaults **false**.
`180ad5c00` selects modern helper `180ab5260` or legacy helper `180ab50b0`
through that setting. Modern jump `180adf830` compares press/landing time
state against `sv_bhop_time_window`; `1800c9830` defaults it to **0.0078125 s**.
Press helper `180ab5260` checks `sv_jump_spam_penalty_time`, whose
registration `1800c9fe0` defaults to **0.015625 s**. Our fresh-press latch
does not reproduce that complete state machine. The full landing-speed
penalty formula is not established by this pass.

## Implementation order and validation

1. Port shared simulation eye state and the actual terrain sampler, with
   bounded cached queries. Check flat ground, slopes, thin edges, takeoff,
   landing and duck transitions against paired console measurements.
2. Port the combined horizontal acceleration/friction and deferred velocity
   state in script and native movement together. Check displacement, blocked
   movement and run/jump throws, not just terminal speeds.
3. Complete modern landing/bhop and crouch behavior with their own boundary
   checks and CS2 captures. Keep these changes separately reviewable from
   grenade-flight tuning.

The Xbox, exact-coordinate mid-door and B-doors regression passes **201
checks**, with **12,339 native/script steps** compared bit for bit. Each
fixture covers three jump phases crossed with three eligible release times.
The door throws reach the local door-top region; all nine B-doors throws
reach the gate roof with the concrete/wood/concrete contact sequence and
rest within 0.1 units of each other. These are local regressions; Sid's
remaining visual/trajectory discrepancy and G1 stay open.
