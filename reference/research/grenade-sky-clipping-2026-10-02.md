# Dust2 sky and grenade clipping — October 2, 2026

Follow-up to the [jump timer correction](grenade-jump-lineup-2026-10-02.md),
merged in PR #184. Sid's second screenshot shows Godot feet
`(-660.3, 89.8, -343.9)`, yaw `272.6`, pitch `14.1`. A stationary left-click
jump throw reproduced the reported backward bounce above mid. Sid then
supplied a CS2 landing inset and an updated Godot screenshot: feet
`(-660.3, 89.8, -344.0)`, yaw `272.6`, pitch `14.2`. The intended landing
is the top of the open wooden door leaf entering mid, below its lintel.
This initial pass preceded the paired CS2 console inputs recorded below;
an exact CS2 trajectory time series remains unrecorded.

## Extraction check

Source 2 Viewer 20.0 re-exported `maps/de_dust2/world_physics.vmdl_c` from
the installed `game/csgo/maps/de_dust2.vpk` into ignored audit output.
The fresh scene matches the existing export after normalizing the output
buffer filename. Both binary geometry buffers have SHA256
`d2796f904e3ad00f5b9dbe5c045ad339db7cae09cc1201478d4a283796c6560a`.
The archive has one world physics model, not another grenade skybox model.

| Exported part | Triangles | Original PHYS collision attributes |
|---|---:|---|
| `physics_csgo_grenadeclip` | 2,320 | `ConditionallySolid`, interact as `csgo_grenadeclip` |
| `physics_sky` | 266 | `conditionallysolid`, interact as `sky` |

The PHYS data gives neither part an additional ordinary solid interaction.
The main hull contains 39 shapes and 435,649 triangles. No Valve assets or
decompiled code are committed. Raw extraction, PHYS dump, listings and
contact probes stay under `.godot/grenade-map-clips/`.

## Installed-binary evidence

The installed build is 2000924 / patch 1.41.8.8 / Source revision 11076591.
Current server SHA256:
`098d4ddd57e2fbe9a73623a2bf68ebaff86f7b6342ddb3d5a0f69cd6335b31cc`.
The existing server Ghidra project predates this update. Six relevant
function spans below were checked byte-for-byte against the installed DLL
before using their addresses; all match.

| Server VA | Evidence |
|---|---|
| `1809cc3a0` | Grenade projectile spawn supplies collision mask `0x200003001` to the box/sphere initializer. |
| `180d08410` | Box initializer stores that supplied mask at collision properties `+0x20`. |
| `180bd6d50` | Movement filter copies the collision properties' mask at `+0x20`. |
| `180e88aa0`, `180c27940` | Fly movement constructs that filter and uses the entity's hull trace. |
| `180934c70` | Registers `csgo_grenadeclip` at interaction bit index 33. |

Fresh `vphysics2.dll` SHA256:
`f8e13289ecf9a5257d8aac3cc5b77ce599cc773479765687c981ae3aac1e0b4b`.
Its Ghidra function `180296fa0` registers `sky` at interaction index 3,
`window` at 12 and `passbullets` at 13. The Listing confirms `MOV R9D,3`
at `1802970b6`, then the pointer to the literal `sky` at `1802970c4`.
The target function decompiled and its instructions were inspected; the
broader first-pass DLL analysis hit its 90-second bound and is incomplete.

Thus the grenade mask includes bits **0, 12, 13 and 33**, but excludes
**sky bit 3**. Importing `physics_sky` as ordinary world collision changed
the meaning of the authored shape. A fresh export cannot fix that mistake.
This audit establishes the sky distinction, not every entity/group filter;
pass-bullet geometry and interaction-exclusion metadata still need a broader
collision-attribute port.

## Change and checks

`MapImporter` retains `physics_sky` in its own `SkyClip` body on layer 64.
Ordinary world, movement, bullet and grenade masks exclude it. Explicit sky
queries can still inspect the geometry. Grenade clips remain on layer 32.
The native mirror retains all 39 static shapes, so no per-flight filtering
or additional trace is needed. Gravity, throw speed and bounce remain unchanged.

For the second screenshot's jump fixture, the old first contact was
`physics_sky` at `(1173.999, 389.7683, -427.1916)`, normal `(-1, 0, 0)`.
After correction, it passes that plane. Its first contact is the wooden
door assembly at `(1590.942, 51.43002, -446.1241)`. The initial material-only
description called this a roof; inspecting the visible `dust_door_arch_01`
geometry and rendering the rest point identifies the open door leaf.

## Mid-door landing reference

With the updated HUD values and a stationary full-strength left-click jump
at tick fraction `0.25`, the smoke first touches `physics_group_wood_dense`
at `(1593.160, 51.33661, -446.3311)`. It rebounds against the nearby wooden
frame and settles at `(1591.739, 50.5113, -457.0676)` after `4.40625` seconds.
Rendering that point on the extracted visible geometry puts it on the same
open door leaf pictured in Sid's CS2 inset. Release offsets of 0, 2 and 8
ticks all produce that rest point. This adds a second landing regression
without changing throw speed, gravity or bounce.

The reference also exposes a remaining timing limit. The same rounded aim
with jump fractions `0` and `0.75` contacts the door but eventually falls
to the ground: respectively `(1635.546, -124.0718, -432.1899)` and
`(2156.528, -125.4671, -423.5171)`. Their stashed upward pawn velocities
are `220.743` and `225.4305` u/s versus `222.3055` for the quarter-tick case.
Each fraction repeats across all three release offsets. The present port
captures at a whole movement finish; this narrow door landing is sensitive
to the resulting jump-phase variation. The passing quarter-tick regression
does not prove repeatable CS2 jump-throw parity. Recovering the remaining
subtick movement/snapshot scheduling or recording exact CS2 launch states
is still required; these screenshots do not justify fitting global bounce.

The [October 3 Ghidra follow-up](grenade-subtick-snapshot-2026-10-03.md)
now establishes the missing segment clock and explicit snapshot boundary,
and identifies the ordinary jump's fixed gravity adjustment. Its tested
candidate makes throws consistent across jump phases, but this rounded
mid-door setup lands on the floor. Sid requested applying it for playtest,
so that candidate now runs on the branch. The passing quarter-tick landing
above describes the previous runtime. The later
[CS2 console setup](grenade-subtick-snapshot-2026-10-03.md#cs2-console-setup)
reveals the screenshot-derived Godot aim was about 0.8 degrees lower.
The supplied CS2 aim reaches the door with the audited movement and unchanged
flight physics; 130 strict lineup checks now pass. The fixture retains the
verified local floor height pending CS2's exact pawn origin. Recorded CS2
launch/contact measurements and general jump validation remain open.

The asset-dependent lineup suite now checks the actual mid sky plane,
actual grenade-only clipping, all nine original Xbox cases, and three
quarter-tick mid-door releases passing the formerly blocking plane and
settling on the open door. The original Xbox rest points are unchanged.
The synthetic native gameplay suite checks sky pass-through,
collision with a real wall behind it, and explicit sky queries. The map
export fixture checks that sky and grenade clipping import to separate layers.
