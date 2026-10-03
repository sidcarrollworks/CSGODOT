# CS2 grenade and throw audit — October 2, 2026

**Implementation follow-up:** [grenade port, October 2](grenade-port-2026-10-02.md)
now supplies the dedicated contact contract and core throw/flight/activation
rules. This page retains the audit-time implementation gaps and measurements;
the follow-up records what was ported and what still needs local comparison.

**Jump-timer correction:** the [Xbox lineup follow-up](grenade-jump-lineup-2026-10-02.md)
checks the helper's instructions and corrects the movement interval's sign.
The initial audit incorrectly described that interval as an addition.

Roadmap **20a**, with supporting findings for **G1–G5**. This is the research
phase: no grenade gameplay code has been changed. The next implementation
should address release timing, jump snapshots, launch geometry, flight and
map grenade clips together before tuning individual dust2 lineups.

The installed CS2 binaries confirm several numbers that were previously
CS:GO assumptions, and expose differences that those numbers alone cannot
fix. The current game throws immediately from a 22-unit eye sweep and flies
a sphere once per 64 Hz tick. This build of CS2 schedules release, can use
a jump snapshot, traces launch from pawn center, and normally flies a box
in two 1/128 s physics steps per 64 Hz tick.

## Evidence and build identity

Read-only Ghidra 12.1.4 analysis using JDK 25, checked against x64 instructions,
float constants, callers, RTTI/vtables and field writers. Source2Viewer CLI
20.0 freshly decoded the weapon vdata, all six grenade viewmodel graphs and
their throw clips. No Valve DLL was executed or game process attached.

Installed `csgo/steam.inf`: patch **1.41.8.8**, client/server **2000922**,
SourceRevision **11064488**, built September 30, 2026 at 16:29:50. The install's
Steam build ID is **25640462**. The module image base is `0x180000000`.

| Module | SHA-256 |
|---|---|
| `server.dll` | `3541e46a3193fcf1151e97ce19cd4daf86c5fdb2889033c2bab1d4cc7f555b9c` |
| `client.dll` | `9ddf30d68b8ef66607783d418c4f74a6004cf2104572e6c630625e52c1c1202d` |

All addresses below are **virtual addresses in these exact modules**. Function
labels describe recovered behavior; most functions do not have original
symbols. A vtable target can be a short jump thunk outside Ghidra's recognized
functions: `18094fbb0`, for example, jumps to `18094ebf0`. `NO FUNCTION` from
the exporter does not establish that the behavior is absent.

The fresh scalar vdata comparison found **no changed, new or missing values
in 1,629 fields across 43 weapon rows**. All six grenades inherit authored
`m_flThrowVelocity = 750`. Raw decoded resources, DLLs, Ghidra databases and
exports remain outside tracked files. Reproduction instructions are in
[the audit tools guide](../../scripts/shooting_audit/README.md).

**Verified** below means recovered from this build's code/resource path.
Rendered durations, live input windows and complete map lineups still need
local captures. Static extraction does not close those comparisons.

## Holding, releasing and animation

Server entry points: `1809acd00` begins the attack; `1809c1d20` updates the
held buttons; `1809cd2f0` schedules release; `1809c1930` consumes that timer;
`1809ce100` computes and spawns the projectile. Client counterparts checked
include `1807c6b30`, `1807d70b0` and `1807d6de0`.

- Target strength is left **1.0**, both **0.5**, right **0.0**.
- The first eligible hold update assigns the target directly. Later updates
  use `Approach(target, current, 0.0203124992549)` at the next hold tick
  (`m_nNextHoldTick` / `m_flNextHoldFrac`). This is 1.3/64 per eligible update,
  so changing buttons while holding need not produce one of three strengths
  immediately. `180459e20` is the checked approach helper.
- The launch getter `1809adab0` snaps strength to **0.5** when
  `abs(strength - 0.5) <= 0.1`; the launch routine subsequently clamps to [0, 1].
- Releasing both attack buttons selects action **202** and schedules
  `m_fThrowTime` at **simulation time + 0.1 s**. The timer writer's float
  argument was checked in XMM instructions because Ghidra omitted it from
  its inferred signature. There is also viewmodel tick/time correction;
  do not infer an exact wall-clock lockout from this base delay alone.
- The consumer spawns when **now > throwTime**, rather than on the command's
  release tick. A qualifying jump can postpone this once by another 0.1 s
  and set `m_bJumpThrow`, with a jump-throw grunt.
- The throw emits `grenade_thrown`; angular velocity is
  **{600, RandomInt(-1200, 1200), 0}** in Source coordinates. The spawning
  path also checks position/velocity for non-finite values.

The six freshly decoded `viewmodel_grenade.vnmgraph+*.vnmgraph_c` resources
agree: the **Charge** state signals `WPN_ACTION_COMPLETE` at remaining time
<= **0.2 s**; **Throw** completes at remaining time <= **0.0 s**. Strength
<= **0.33** chooses the underhand animation; otherwise it chooses overhand.
All twelve throw clips have duration **0.5000 s underhand / 0.7667 s overhand**,
play once at speed 1 and contain sound events. Their event lists do not
supply a projectile release ID event. Release is handled by the timer above;
a throw sound is not evidence of the projectile leaving the hand.

The repository already uses approximately those clip durations for hand
busy time, but releases immediately and lacks the gradual strength, middle
snap and jump deferral. Graph completion and clip length also do not by
themselves establish the complete time until the next weapon can fire.

## Launch position and velocity

`1809adab0` obtains strength, `180abf740` selects live/stashed parameters and
`1809adc00` performs the launch calculation. Source uses **Z up and positive
pitch down**; Godot uses Y up and the project's positive pitch points up.
Convert coordinates before porting these equations.

In Source coordinates, preserving the original float32 operation order:

```text
if pitch > 90: pitch -= 360
if pitch < -90: pitch += 360
pitch -= ((90 - abs(pitch)) * 10) / 90
forward = direction_from_angles(pitch, yaw)
base = clamp(authored_throw_velocity * 0.9, 15, 750)
s = clamp(strength_after_middle_snap, 0, 1)
speed = base * (0.7 * s + 0.3)
eye.z += 12 * s - 12
origin = sweep_box(pawn_center, eye + forward * 16).end
velocity = forward * speed + pawn_velocity * 1.25
```

The default launch sweep is a box with **mins −2.02 / maxs +2.02** on all
axes, collision mask literal `0x200003001` and an owner-aware filter. Its
start is **pawn center**, not the eye. There is **no six-unit backward
adjustment** after the trace in this routine. With
`sv_grenade_collision_sphere` enabled, this launch path bypasses that box
sweep and starts from the lowered eye; it is not just a sphere substituted
into the same launch trace.

For authored 750 and a stationary thrower, settled left/both/right strengths
give **675 / 438.75 / 202.5 u/s**. The repo's base-speed scaling, lift, drop
and 1.25 velocity share match this calculation. Its **22 units forward from
the eye**, sweep origin and discrete strength selection do not.

## Jump-throw snapshot

The jump paths `180ab57f0` and `180adf830` schedule movement-service
`m_fStashGrenadeParameterWhen` at **simulation time − movement interval + 0.1 s**.
Helper `1801bdb80` executes `SUBSS`, not addition; the subsequent
`18017e3f0` call adds the 0.1 s delay. The getter reads the
scoped movement-segment clock (`180921a10`); the pawn tick supplied by
`180c7fe60` selects that clock but is not converted into seconds. The
[October 3 follow-up](grenade-subtick-snapshot-2026-10-03.md) verifies that
the resulting deadline is actual takeoff time +0.1 s and that CS2 inserts
a movement boundary there. The original whole-tick interpretation was wrong.
They copy the timestamp to the pawn and clear its snapshot-ready flag.
Movement finish `180abe000` detects crossing that scheduled tick/fraction
and calls `180add6f0`, which stores aim, eye position, pawn center and velocity.

For the ordinary throw, getter `180abf740` uses stored parameters only when
the ready flag is set and **0 < now − stash timestamp <= 0.2 s**. Otherwise
it uses live parameters. A caller option can bypass the age check and
retain live aim with stashed positions and velocity; the ordinary throw
path passes false.

Eligibility helper `180acb810` tests the same age predicate with a caller
time offset: **0 < (now + offset) − stash timestamp <= 0.2 s**. The release
check uses offset 0; the timer consumer uses 0.1. On the first qualifying
consume, `1809c1930` postpones release to now + 0.1 and marks the jump throw.

| Pawn offset, this build only | Recovered use |
|---|---|
| `+0x1570` | Snapshot timestamp |
| `+0x1574` | Snapshot-ready flag |
| `+0x1578` | Aim angles |
| `+0x1584` | Eye / throw position |
| `+0x1590` | Pawn center |
| `+0x159c` | Velocity |

**The internal 0.2 s age predicate is not a measured 200 ms player input
window.** Jump timing, delayed snapshot creation, release scheduling and
tick/fraction order all contribute. The repo currently uses live launch
parameters and has none of this snapshot lifecycle.

## Flight, collision and settling

Shared spawn `1809cc3a0` gives the default projectile a **box [−2, +2]**.
Convar registrations `1800b4920` / `1800b49d0` confirm sphere mode defaults
**false**, with configurable sphere radius **2**. A box is verified here;
the earlier inference that default collision follows the grenade mesh
should not drive a port.

The projectile factories set **gravity 0.4, friction 0.2, elasticity 0.45**.
The gravity integrator `180e87c80` applies entity gravity × `sv_gravity` × dt
and uses midpoint vertical velocity for displacement. With normal
`sv_gravity = 800`, acceleration is **320 u/s²**. Friction's field value
does not imply multiplying airborne velocity by 0.8 each tick.

Wrapper `1809c5670` temporarily changes move type 10 to fly-gravity type 4,
invokes the custom body-hit callback, runs fly physics `180e89790`, then
restores type 10. At a 1/64 s frame interval it splits motion into **two
1/128 s steps**. Non-integral interval ratios have a separate fallback;
do not replace this with an arbitrary ceil(dt / step) rule. This does not
make the whole CS2 server 128 Hz. Water flags `0x18000` multiply velocity
by **0.98 after each step**. Angular velocity is damped by **0.995 once
per wrapper update**, with additional normal/tangent adjustment. Nine
consecutive zero-velocity wrapper updates cause the stop path.

Collision callback `1809c7ad0` and clip helper `180e88270` establish:

```text
push = max(-dot(velocity, normal) * 2, 0) + 0.03125
clipped = velocity + normal * push
bounced = clipped * clamp(projectile_elasticity, 0, 0.9)
```

- Player surface hits replace the trace normal with a normalized radial
  vector from player center to hit point. Certain moving entities add
  **0.3 of their velocity**; this is not a universal player restitution.
- A floor branch accepts normal.z > **0.7**, or normal.z > **0.1** when
  post-bounce speed² < **400**, with standability/class checks as well.
  That branch rests the grenade when speed² < 400.
- For post-bounce speed² > **96,000**, an outward normalized dot > 0.5
  adds a speed reduction of **1.5 − dot**.
- Motion uses the remaining fraction of the step, with another trace/clip
  possible after a collision. Base velocity and standability matter; the
  repo's four sphere sweeps are not the same collision algorithm.
- Breakables receive **10 impact damage**. Certain destroyed breakables
  let the grenade continue at **0.4 of its velocity**.
- The bounce counter increments while its old value is < **21**. If the
  old value is already 21, the stop path runs. This is not a 21-second fuse.

Separate routine `1809ae940` checks nearby enemy player bodies once per
projectile (guard flag `+0xb3c`). A successful hit applies **2 impact damage**,
reflects the grenade around the radial direction and leaves **0.3 of its
speed**. Fire override `1809af090` adds **4.0 s** to its detonation deadline
when that check succeeds. Do not model every player contact as the current
repo's `0.45 * 0.3` bounce coefficient: these are separate paths.

Full engine collision filtering, owner recontact, start-solid handling,
spin/rolling and all breakable cases still need focused comparison. The
map importer also discards `physics_csgo_grenadeclip` in `hull_skip_hints`;
the reserved query layer alone cannot reproduce CS2 lineups.

## Fuses and activation

These deadlines start at **projectile spawn**, after the release delay.
Think cadence and strict comparisons can make an observed detonation later
than the authored deadline.

| Grenade | Verified rule | Central server paths |
|---|---|---|
| HE | Deadline **spawn + 1.5 s**; shared danger think tests now > deadline, otherwise schedules now + **0.2 s** | `18039dc30`, `1809c9ca0`, `1809b0f50` |
| Flash | Constructor default **1.5 s**, used by spawn to set the same deadline; a script setter can change it | `18039cd80`, `1803a1380`, `18039ced0` |
| Smoke | Normal settling think requires **3D speed <= 0.1 u/s** and **age >= 1.18799996376 s**; schedules itself for current time while waiting | `1809b0b70`, `1809cdd00`, `18024eff0` |
| Decoy | Activates at **3D speed <= 0.2 u/s**; while moving checks again in **0.2 s**; gunfire deadline **activation + 15 s** | `1809afd80`, `1809cda40`, `1809b9d00` |
| Molotov / incendiary | Air deadline convar default **2 s**; valid ground touch normal.z >= cos(**30°**); one-time enemy body hit extends deadline by **4 s** | `1809b02a0`, `1809ad010`, `1809af090` |

Smoke and fire retain a ring of recent positions when movement exceeds
20 units (distance² > 400). Smoke's normal settling path is not the repo's
shared 0.2 s check for an `at_rest` flag; forced detonation from fire is a
different path and should be checked separately.

Fire's deadline think `1809b0fe0` polls at 0.2 s and also has a low-speed
<= **5 u/s**, **0.5 s** fallback. Airburst placement `1809cf4b0` traces from
**position + 10 Z to position − 128 Z**. No hit selects the appropriate
`Molotov.StartFailed` / `IncGrenade.StartFailed` effect and removes the
projectile. This is more specific than a ray only from its position down
128 units. Thrower, breakable, ladder and other touch filters also precede
ground detonation.

## HE damage and flash blindness

**HE:** detonation reaches `18039e840` → `180de95d0` → game-rules vtable
`+0x1f8` → thunk `18094fbb0` → **`18094ebf0`**. The radius damage path reads
radius R and base damage D, selects a target point and obtains a visibility
factor V. Its checked `V_expf` call computes:

```text
sigma = R / 3
damage_before_armour = D * exp(-(distance * distance) / (2 * sigma * sigma)) * V
```

The calculation initially raises the blast's Z by **1 unit**. Visibility
helper `18091fe90` and alternate source-point selection can change V and
the effective distance. The repo's sigma=R/3 is confirmed, but its three
simple rays do not establish parity with these engine traces. Damage
conversion, armour, occlusion, team scaling and the January mid-air fix
still need G2 cases. Do not describe a Gaussian as mathematically zero
at radius R; the radius restricts the candidate query.

**Flash:** `18039dea0` calls `1803a0830` with base **3.0** (checked at
`18039e018`, constant `181782e08`). The search radius is **3,000 units**;
the routine adds 1 Z to the flash position and uses eye distance. Set
**B = 3 * (1 − distance / 3000)** for positive B. Facing dot against the
direction from eyes to flash determines these inputs to the blindness setter:

| Facing dot | Hold input | Fade input |
|---|---|---|
| >= 0.6 | 1.25 B | 2.5 B |
| >= 0.3, < 0.6 | 0.8 B | 1.75 B |
| >= −0.2, < 0.3 | 0.5 B | B |
| < −0.2 | 0.25 B | 0.5 B |

Both inputs are multiplied by visibility weight. The requested maximum
alpha is **255**, rather than the repo's facing-dependent grey peak.
Visibility `1803a02c0` first tries the direct ray. If blocked it tries
three routes around the flash: up 50, right −75/up 10 and right +75/up 10
in the flash-to-eye basis. Direct visibility returns weight 1; each
successful alternate route contributes **0.167** (literal
`0x3e2b020c`). Those routes use `18039d870` and specialized filters; a
single blocked ray is not enough to prove zero blindness.

Pawn dispatch `1801c08f0` reaches setter **`18021ab10`**. It maintains the
blind-until deadline as the later of the previous deadline and
**now + hold + 0.5 * fade**, and stores network `m_flFlashDuration` from
**fade / 1.4** (`18179eed4 = 1.399999976158142`). An overlapping flash takes
the larger of new duration and the previous duration remaining, preserves
the larger alpha, and adds **0.01 s** when the stored duration would otherwise
be unchanged. `player_blind.blind_duration` uses that network duration.

These are different clocks: do not equate hold+fade, the blind-until deadline,
the replicated duration and a measured full-white period. The client overlay,
ringing thresholds and complete partial-visibility filters remain to audit/
capture. The repo's 250–2,000 unit curve, continuous facing interpolation,
4.87 s constant and fixed 3 s fade are not this server algorithm.

## Smoke lifetime and decoy data: partial results

Smoke update **`1809cde80`** measures time from `m_nSmokeEffectTickBegin`:
it starts a model-alpha fade at **12.5 s**, reaches the fade endpoint at
**17.05 s**, and switches to cleanup at **21.05 s**, with removal scheduled
one second later. It changes an associated volume-state flag after **19 s**;
that flag's complete downstream meaning has not been resolved.
**This is not sufficient evidence for the whole cloud's visible or
sight-blocking duration.** Async volume creation enters `buildSmokeVolume`
through `1809ad2c0`; the complete voxel/renderer lifetime, fill algorithm,
HE holes and bullet tunnels remain G4 work.

Decoy `1809b9d00` uses authored weapon-dependent burst counts, delays and
weapon cycle time. Activation + 15 s is verified; the repo's generic
1–5 shots / 0.5–2 s pauses and pop damage/radius are not verified here.
Recover the per-weapon burst table and compare the final damage path for G5.
Inferno spreading, damage ramp and extinguishing behavior also remain open;
the fire-grenade fuse/placement findings do not close those systems.

## Implementation and local checks

1. **20a / G1:** preserve simulation command ownership, add strength state,
   delayed release and movement-owned jump snapshots. Check button switches,
   middle snap boundaries and release before/after a jump across tick fractions.
2. **20a / G1:** port center-to-eye launch box, 1/128 s flight substeps and
   bounce/settle rules. Import grenade-only clips on their own layer. Measure
   the added query cost with the existing performance tools.
3. **G1:** compare CS2 and this game from identical origin/angles, left/right/
   both, standing, running, crouching and jumping. Record spawn time, initial
   position/velocity, wall/floor bounce points, settling and detonation time.
   Include close-wall releases and representative dust2 clip surfaces.
4. **G2 / G3:** port flash server clocks and overlap rules separately from
   the client overlay; compare flashed distance/facing/partial cover and
   repeated flashes. Validate HE at 50/100/200/300 units, airborne/grounded,
   with armour, walls and teammates.
5. **G4 / G5:** continue volume/inferno and decoy-table audits, then capture
   smoke cover lifetime, holes, fire interaction and decoy bursts/pop.

Validation for this research PR: full project suite **7,109 checks in 76
files passed** with local native physics and extracted assets; draw-only
checks skip headlessly. Audit helper fixtures **7 passed**, including PE
identity/address mapping and custom case-insensitive string filtering.
Fresh data comparison and Ghidra exports completed. No live trajectory,
blindness or lineup comparison was performed in this audit.
