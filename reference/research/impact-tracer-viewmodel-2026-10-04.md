# Impact placement, tracer attachments and viewmodel recoil

Local Ghidra audit on October 4, 2026, prompted by Sid's oblique wall-hit
and strafing screenshots. Installed CS2 client/server **2000924**, source
revision **11076591**, built **2026-10-02 14:45:21**. Fresh modules were used
rather than assuming addresses from the September 30 audit still match.

| Module | SHA-256 |
|---|---|
| `client.dll` | `d7db25d48f1d10c5e0b0296e20ed803426eb9509da41760daeda39dd35ba89b9` |
| `particles.dll` | `2cf870d86cddc8326534f37fce39735b5f2937755bf538e50d9b1932c79ddd2b` |

Local projects: `CS2_Viewmodel_Current_20261004` and
`CS2_Particles_20261004`. Binaries, projects and decompiled listings remain
outside tracked source. Addresses below are virtual addresses in these
modules; the existing `scripts/shooting_audit` workflow can index/decompile
the listed functions against this installation.

## The puff normal was being used as a position

**Verified in the particle module.** The RTTI-backed `C_INIT_NormalOffset`
vtable is `1804fb4c8`. Read-mask getter `180113db0` returns `0x200000`
(NORMAL, attribute 21); write-mask getter `18015a850` returns `0x200100`
(NORMAL plus attribute 8). Initializer `18015a910` reads the
existing normal, samples the min/max vector, optionally transforms it
through the control-point frame, adds it to the normal and optionally
normalizes the result. It does not translate the particle position.
Deserializer `1801a55e0` maps the local-coordinate and normalization flags.

The shipped `impact_fx_hit_darken_model` specifies `[0, 0, 10]`, local
coordinates and normalization. Our runtime interpreted those ten units as
a translation. That placed the 3D puff ten inches away from the wall,
producing increasing separation from the bullet mark at oblique view angles.
The mesh starts at its base; its pivot is not the cause.

The generator now preserves both flags. The runtime updates a particle
normal and uses it to orient the model, leaving the spawn at the contact
plus any actual authored position offset. Authored outward velocity still
moves the puff after emission. The preceding world-effect frame fix remains:
Source +Z points along the contact normal. Exact CS2 event control-point
assignments remain an approximation.

## Tracers sample a projected muzzle, then travel in world space

**Verified in the client module.** `180901420` drains queued shot records
through `180901580`. The latter selects `muzzle_flash` / `muzzle_flash2`,
reads the current attachment through `18093f0a0`, and applies first-person
projection helper `180c76be0` before creating the effect.

That helper expresses the attachment relative to the rendered camera,
scales right/up components by the world/viewmodel FOV tangent ratio and
preserves forward depth. Our `Muzzles.as_drawn` already matches this
projection; no different FOV multiplier was needed.

The tracer path creates an effect through `1807c90f0`, writes its projected
start/orientation through `180a12530` and endpoint through `180a11ea0`.
This path supplies fixed points rather than a continuing muzzle attachment.
An already launched tracer should stay in world space as the player moves.

Our pending shots now drain at `RenderingServer.frame_pre_draw`, after
camera interpolation and the deferred skeleton attachment update. This
fixes sampling an earlier barrel pose while strafing. Each tracer keeps
the real bullet impact as its endpoint and retains its captured origin
after launch.

## Viewmodel angles have their own aim-follow contribution

**Verified in the client module.** Viewmodel pose function `1810c05c0`
calls aim-punch reconstruction `1808533c0` at `1810c0fd1`, loads **0.325**
from `181d09e58`, scales the vector through `18082ce60`, and adds it to
its angle vector through `1807fe500`. Both helpers were checked in
disassembly. Living camera path `180882790` separately uses **0.45** from
`181bfb07c`; these contributions should not be interchanged.

We add the 0.325 aim-follow contribution alongside the model's existing
cosmetic firing springs. A presentation copy of recoil advances between
shots and recovers after release; drawing never advances the ballistic
state. Both contributions use the same simulation-to-render interpolation.
The model follows recoil rather than individual random spread samples.

We also corrected a local transform-order error: the imported rig's rest
basis includes a 180-degree Y turn. Applying pitch after that basis reversed
its vertical direction. Recoil now rotates in the camera frame before the
rest basis, so upward recoil lifts the barrel.

This is not a complete CS2 camera/weapon animation port. Our accepted camera
springs, firing clips and measured/provisional ballistic patterns remain.
The binary establishes this contribution and attachment projection; full
prediction, animation blending and camera-channel parity still require
the captures listed in the earlier shooting audit.

## Verification

Checks cover puff origins and model normals across multiple wall/view
angles, late camera/weapon movement before muzzle sampling, unchanged
launched-tracer endpoints, correct imported-barrel pitch, recoil following
and recovery, and unchanged ballistic trajectories. The effects,
hit-effects, hit-table, hit-particle, model, weapon, recoil, scope and
simulation suites pass **2,822 checks**. Visual strafing and spray comparison
remains a local playtest.
