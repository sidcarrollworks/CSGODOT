# Dust2 sky and grenade clipping — October 2, 2026

Follow-up to the [jump timer correction](grenade-jump-lineup-2026-10-02.md),
in PR #184. Sid's second screenshot shows Godot feet
`(-660.3, 89.8, -343.9)`, yaw `272.6`, pitch `14.1`. A stationary left-click
jump throw reproduced the reported backward bounce above mid. The exact
throw input and intended CS2 landing still need a side-by-side capture.

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
After correction, it passes that plane. Its first contact is a real wooden
roof at `(1590.942, 51.43002, -446.1241)`. This does not establish the intended
CS2 landing, which the screenshot does not show.

The asset-dependent lineup suite now checks the actual mid sky plane,
actual grenade-only clipping, all nine original Xbox cases, and the second
throw crossing the formerly blocking plane. The original Xbox rest points
are unchanged. The synthetic native gameplay suite checks sky pass-through,
collision with a real wall behind it, and explicit sky queries. The map
export fixture checks that sky and grenade clipping import to separate layers.
