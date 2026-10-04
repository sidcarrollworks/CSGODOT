# CS2 eye height and grenade lineup audit — October 3, 2026

Sid reports that matching a CS2 landmark still requires aiming higher in
our game. The corrected console aim in the [subtick audit](grenade-subtick-snapshot-2026-10-03.md#cs2-console-setup)
fixes the local door fixture, but does not establish visual or trajectory
parity. This follow-up checks the current camera and grenade eye paths.
It changes no runtime height or throw parameters.

## Findings

**Verified:** CS2's ordinary view-vector definitions still use a standing
eye height of **64 units** and a crouched eye height of **46 units**.
These match `MovementConfig`'s base values. The April update changed
terrain-dependent height adjustment; it is not evidence for replacing 64
with a new universal standing height.

**Verified:** CS2 updates a ground-topology adjustment, crouch root/view
offsets and the pawn's final view offset during movement finish, before
capturing the jump-throw snapshot. This is simulation state that can
change a grenade's launch position, not just the drawn feet.

**Verified in our code:** `PlayerBody.eye_height()` only blends the base
64/46 values. Neither that method nor grenade launch parameters apply a
ground-topology adjustment. The local rendered camera also adds its
procedural jump/landing dip and interpolates position; grenade snapshots
use simulation position and eye height. These paths must be compared
separately when reproducing a reference.

**Measured:** Sid's paired `getpos`/`getpos_exact` at this starting point
give an effective eye height of **60.75 units**, 3.25 below the base height.
The fixture now uses the supplied pawn coordinates. The missing terrain
adjustment is a plausible contributor, but its exact sampled value and
the remaining trajectory discrepancy are still unresolved. The
[movement follow-up](movement-ghidra-2026-10-03.md) compares the current
walk/air, crouch, ground and takeoff paths. A successful synthetic door
landing is not evidence that CS2 parity is established.

**Live follow-up:** Sid confirms the B-doors throw lands correctly, while
the mid-door landmark throw misses. Its recorded upward pitches are
14.27/14.49 degrees rather than the supplied 14.96. A local collision-ray
comparison shows that our higher standing camera would aim at the same
close wall point at about 14.24 degrees. This supports the missing visual
eye adjustment as the cause of those landmark-based angle differences;
exact CS2 launch/contact comparison remains open. See the
[live aim comparison](movement-ghidra-2026-10-03.md#live-landmark-aim-comparison).

## Valve's documented changes

Valve's [April 1 Animgraph 2 beta notes](https://www.counter-strike.net/newsentry/528750051218948826)
say the slope-height logic was refactored, ramp height became independent
of approach direction, and grenade lineups on slopes could change.
The beta changes went live April 20. Subsequent changes covered slope-to-flat
transitions, thin ledges and step-height transitions. Valve's
[May 7 update](https://www.counter-strike.net/newsentry/702141807556821888)
also changed smoothing when leaving the ground and landing.

These notes describe terrain and transition behavior. They provide no
replacement standing-eye constant. The numeric findings below come from
the locally installed binary, rather than community height estimates.

## Binary identity and verification

Installed build **2000924**, patch **1.41.8.8**, SourceRevision **11076591**,
built October 2, 2026 at 14:45:21:

| Module | SHA-256 |
|---|---|
| `server.dll` | `098d4ddd57e2fbe9a73623a2bf68ebaff86f7b6342ddb3d5a0f69cd6335b31cc` |
| `client.dll` | `d7db25d48f1d10c5e0b0296e20ed803426eb9509da41760daeda39dd35ba89b9` |

Ghidra 12.1.4 processed the existing projects read-only. All **31 server
function spans** exported for this follow-up match the installed server
byte for byte. Constants were also read from the installed PE. The wider
server comparison at the completion of that pass covered **64 distinct
spans**, all unchanged. The subsequent [movement audit](movement-ghidra-2026-10-03.md)
extends the installed-server comparison to **97 distinct spans**, all
matching byte for byte.

Client addresses were resolved independently from current RTTI/vtables.
Four supporting methods match byte for byte: `18015f810`, `1801604d0`,
`1801602e0`, `18016a130`. The normal camera method `180882790` and pawn
eye method `18093c840` retain their instruction layouts, with changed
relative call/global addresses. Those differences were examined explicitly;
these two methods are not described as byte-identical. The old eye-angle
method at `180c74900` has moved and was excluded from the same-address
comparison. Valve modules, databases, exports and scratch helpers remain
uncommitted. No Valve DLL was executed and no debugger was attached to CS2.

## Base height, hull and final eye position

The current server's `CCSGameRules` vtable slot `0x100` resolves to
`1809251a0`, which returns the view-vector table at `1821151a0`.
Initializer `18009a8b0` assigns these ordinary values:

| Definition | Table offset | Value |
|---|---|---|
| Standing view vector Z | `+0x08` | 64 |
| Standing hull maximum Z | `+0x20` | 72 |
| Crouched view vector Z | `+0x44` | 46 |
| Crouched hull maximum Z | `+0x38` | 54 |

The 64 constant is at `181782e14`; the CS-specific crouched constants
46/54 are at `1818ca678`/`1818ca67c`. The generic game-rules fallback has
different crouch values, so reading that fallback alone would be misleading.

Server method `180ae23e0` builds the ordinary pawn view offset from the
standing view vector plus the current root/ground adjustment, duck view
offset and bomb-plant view offset. It writes through `1802677d0` to the
networked `m_vecViewOffset` at pawn `+0x818`. Its vertical expression also
uses `(value + 196608) - 196608`, and the setter applies the registered
quantized-float bounds. A port should preserve these rounding operations.

Client camera method `180882790` calls pawn vtable slot `0x568`, currently
`18093c840`. Its ordinary local-player path reaches `18015f810`, which
adds absolute pawn origin to the transformed view offset returned through
slot `0x5a0` (`1801604d0`). That getter reads the client view-offset wrapper
through `1801602e0` and converts it through `18016a130`. Observer/control
branches and later camera effects are separate from this ordinary path.

## Ground topology and transition behavior

`180a6cb30` computes the ground-topology result; `180a73ad0` reads its
height difference. The sampler uses a **5 by 5 grid at 8-unit spacing**,
with hull overlap and height weighting, rather than a single ground normal.
`180a69a60` performs/caches the supporting collision queries. Samples are
quantized, invalid samples are rejected, and additional sample-selection
logic handles nearby height discontinuities. The final downward height
difference is clamped to **0–24 units**. The complete selection/filtering
logic is not yet ported.

`180ae23e0` uses that result to update these movement-service fields:

| Field | Offset |
|---|---|
| `m_bUsingGroundTopologyOffset` | `+0x3f0` |
| `m_flUsingGroundTopologyOffsetTransitionSmoothing` | `+0x3f4` |
| `m_flDuckRootOffset` | `+0x418` |
| `m_flDuckViewOffset` | `+0x41c` |
| `m_flBombPlantViewOffset` | `+0x424` |

When topology use changes, it initializes a residual from the previous
root adjustment minus the new target, then approaches that residual to
zero at a rate determined by the current movement branch. The subsequent
helper audit confirms an airborne rate of
`max(abs(vertical_velocity) * 0.5, gravity * 0.05)`. At ordinary gravity
800, even the minimum 40-unit/s rate removes a 3.25-unit residual before
the 100-ms jump snapshot, assuming no other root/view offsets. The combined
root adjustment is clamped to **-32–32 units**. It is written through
`180cb1aa0`; `180ca6760`/`180ca6740` read it back when assembling the eye.
Duck root/view adjustments have their own approach rates and account for
the hull-height change. This is more than blending 64 to 46 with a spline.

The strings `slope_drop_enable`, `slope_drop_max_offset` and
`slope_drop_off_ground_blend_speed` also remain in both binaries. Their
server registration methods are `1800c9390`, `1800c9440` and `1800c92f0`.
The recovered references identify registration and destruction, but this
pass did not establish an active runtime consumer. Their 16/160 defaults
are therefore not evidence for the active topology algorithm's clamp or
transition speed.

## The adjustment reaches grenade snapshots

Movement finish `180abe000` publishes position/velocity, calls
`180ae23e0` to update the eye offset, and only then checks the stash deadline
and calls `180add6f0`. That snapshot writer adds absolute origin to the
transformed/scaled `m_vecViewOffset` via `1801595b0` and saves the result
as the grenade eye position. This establishes that matching only a visual
camera adjustment while leaving launch eyes unchanged would miss CS2's
behavior.

## Paired door-lineup comparison

Sid's paired camera/pawn Z values are **150.364380** and **89.614380**,
with pitch **-14.960024** and yaw **92.602875** in Source coordinates.
Their difference is **60.75**, confirming a **3.25-unit** deficit against
the standing base. The Godot preset now uses those exact pawn coordinates
and converted angles. Local collision still settles the feet near 89.8,
so that small grounding difference is separate from the eye-offset gap.
Do not turn either difference into a hard-coded global camera correction.

For each subsequent reference, collect both `getpos` and `getpos_exact`
while grounded and settled at the same starting point. The former gives
camera coordinates; the latter gives pawn coordinates. Their vertical
difference establishes the effective eye height without assuming 64.
Retain the exact aim, throw strength/button combination and jump/run
sequence, then record the trajectory and first contact as well as the
landing. Include a flat-ground reference and a sloped/edge reference.

The implementation target is a shared simulation eye offset derived from
the recovered root/topology and duck rules, used by rendering and grenade
snapshot capture, with render interpolation handled separately. First
validate its value at the recorded starting positions; then compare launch
states and contact sequences. Until then, G1 and exact CS2 lineup parity
remain open.
