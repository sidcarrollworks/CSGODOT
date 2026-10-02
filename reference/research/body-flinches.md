# Body and head hit flinches

Read on 2026-10-02 from the installed CS2 **1.41.8.8**, client/server
2000922, SourceRevision 11064488, dated 2026-09-30. Archive:
`D:/SteamLibrary/steamapps/common/Counter-Strike Global Offensive/game/csgo/pak01_dir.vpk`.
Source 2 Viewer 20.0 decoded the current
`animation/graphs/worldmodel/worldmodel.vnmgraph_c` DATA and exported the
individual `animation/anims/world/shared/flinch_*.vnmclip_c` files as glTF.
The local audit is `.godot/pr172-flinches/graph-flinch-audit.json`; raw graph
DATA is beside it. This page is a reading of authored content, not a
reconstruction of the closed-source damage handler.

The current graph matches the flinch parts of the earlier generated
[worldmodel table](../animgraph/worldmodel.md). BodyFlinch and HeadFlinch
are **separate full-body additive layers**, after Weapon Shoot and before
the foot/aim fit. Neither layer has an UpperBody bone mask. Head reaction
clips can therefore affect the spine and gun as well as the head; masking
them to the head alone would discard authored movement.

Each layer starts its first hit in **0 seconds**. Repeated hits alternate
between Flinch_WPNs and Flinch_WPNs0, crossing into the restarted clip in
**0.1 seconds**. BodyFlinch returns to Off in 0 seconds; HeadFlinch in
0.1 seconds. The weapon-category selectors have rifle, pistol and knife
clip families, with a 0.2-second category transition. Rifle is also used
for machine guns and shotguns; the graph uses knife for categories outside
rifle/pistol. The game controls the `flinch_*_type` and `flinch_*_restart`
parameters, so their precise damage-handler clearing timing cannot be
proved from the graph alone.

There are **42 bullet-reaction clips**, fourteen per family:

| Region | Authored choices | Current exported duration |
|---|---|---|
| Chest | front, rear, left, right | 0.5333, 0.4333, 0.5667, 0.5667 seconds |
| Stomach | front, rear | 0.4667, 0.5667 seconds |
| Arm | left, right | 0.4333, 0.5 seconds |
| Leg | left, right | 0.5, 0.25 seconds for rifle; 0.5, 0.5 for pistol/knife |
| Head | front, rear, left, right | 0.6333 seconds; rifle/knife right is 0.6 seconds |

These are the glTF timeline lengths actually consumed by Godot, rounded to
four decimals. Export key times retain small floating-point differences
from nominal 30 Hz durations; runtime uses each imported Animation.length.
The normal files contain additive differences. The sibling
`.vnmclip+non_additive` files are authoring references and are **not** used.
The separate looping molotov reactions belong to FireFlinch and are
outside the bullet-hit implementation.

Graph IDs map chest/head north to the unsuffixed front clip, south to
`_rear`, east to `_right`, west to `_left`. The implementation assigns
those directions by the dominant horizontal component from victim toward
shooter in the victim's facing frame. That quadrant assignment is inferred
from the IDs/clip names; the graph does not expose the closed-source code
that computes the IDs. Arm/leg side comes directly from the hit capsule,
not the incoming direction. Stomach has only front/rear options, so side
hits use the front/rear half-plane.

PR172 loads all 42 clips before play and converts their bone tracks with
the same rest-relative additive conversion used by jump and shooting
layers. `PlayerModel.flinch(zone, side, shot_direction, at_usec)` accepts a
shot direction from shooter toward victim and an optional simulation
event timestamp. Body and head keep independent two-pose restart blends
above shooting. They sample the draw clock, so a model first shown after
the clip ends cannot replay an old hit. Authored clip length ends the body
reaction; the head then fades out for 0.1 seconds. This substitutes the
authored timeline for the unavailable engine parameter-clearing logic.
The weapon family is chosen when a hit starts; an active clip stays in
that family if the player switches weapons midway through it.

The reactions change the animated pose only. They do not change the
player's transform, command angles, camera, movement, tagging slowdown,
weapon action or aim input. Death, ragdoll takeover and respawn clear both
layers. The existing skeleton update still drives the weapon pins and
SkinnedHitboxes, preserving this project's current rendered-pose hitbox
contract. Moving authoritative hitboxes to tick-only poses remains the
separate networking work recorded in the animation reference.

Local validation: **143 checks** in `tests/run_flinch_checks.gd`. Its
synthetic rig verifies actual additive poses against nonzero rests,
independent head/body reactions over a continuing base animation, repeat
cross-fades without rewinding the prior clip, off-screen expiration and
clearing. Asset checks verify all 42 imported clips, their non-looping
authored duration, the actual current chest translation at 0.1 seconds,
event API and death/ragdoll suppression. Synthetic checks also run in CI
without extracted content; authored asset checks skip there.
